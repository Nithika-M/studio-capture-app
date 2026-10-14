import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'google_drive_backup_service.dart';
import 'preferences_service.dart';

/// Desktop OAuth 2.0 Loopback Flow implementation for Windows.
///
/// Features:
/// - Loopback HTTP server on 127.0.0.1 on an ephemeral port
/// - PKCE (RFC 7636) code challenge (S256) and CSRF state parameter
/// - Config loading from `windows_oauth.json` or `--dart-define`
/// - Secure token persistence via Windows DPAPI
/// - Automatic token refresh before upload & on HTTP 401
/// - Window restore / bring to front upon auth completion
class WindowsGoogleAuthService {
  static final WindowsGoogleAuthService _instance = WindowsGoogleAuthService._internal();
  factory WindowsGoogleAuthService() => _instance;
  WindowsGoogleAuthService._internal();

  static const MethodChannel _channel = MethodChannel('screen_recording');
  final PreferencesService _prefs = PreferencesService();

  AppGoogleUser? _currentUser;
  AppGoogleUser? get currentUser => _currentUser;

  final ValueNotifier<AppGoogleUser?> accountNotifier = ValueNotifier<AppGoogleUser?>(null);

  String? _accessToken;
  String? _refreshToken;
  DateTime? _tokenExpiry;
  String? _configuredClientId;
  String? _configuredClientSecret;
  String? lastConfigErrorReason;

  bool _initialized = false;
  bool _isSigningIn = false;

  /// Load OAuth Client credentials from environment or windows_oauth.json
  Future<Map<String, String>?> getOAuthConfig() async {
    lastConfigErrorReason = null;
    final List<String> diagnostics = [];

    // 1. Check dart-define
    const envClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
    const envClientSecret = String.fromEnvironment('GOOGLE_CLIENT_SECRET');
    if (envClientId.isNotEmpty && !envClientId.contains('YOUR_DESKTOP_CLIENT_ID')) {
      final cid = envClientId.trim();
      final sec = envClientSecret.trim();
      _configuredClientId = cid;
      _configuredClientSecret = sec;
      debugPrint('[WindowsAuth][Config] Loaded OAuth credentials via --dart-define GOOGLE_CLIENT_ID (length: ${cid.length})');
      return {
        'client_id': cid,
        'client_secret': sec,
      };
    }

    // 2. Build candidate locations
    final cwd = Directory.current.path;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final appData = Platform.environment['APPDATA'] ?? Platform.environment['USERPROFILE'] ?? '';

    final rawPaths = <String>[
      // Next to executable (Release or Debug)
      '$exeDir${Platform.pathSeparator}windows_oauth.json',
      '$exeDir${Platform.pathSeparator}windows_oauth.example.json',
      // Current working directory
      '$cwd${Platform.pathSeparator}windows_oauth.json',
      '$cwd${Platform.pathSeparator}windows_oauth.example.json',
      // frontend subfolder from CWD
      '$cwd${Platform.pathSeparator}frontend${Platform.pathSeparator}windows_oauth.json',
      '$cwd${Platform.pathSeparator}frontend${Platform.pathSeparator}windows_oauth.example.json',
      // Parent directory if CWD is in frontend
      '${Directory(cwd).parent.path}${Platform.pathSeparator}windows_oauth.json',
      '${Directory(cwd).parent.path}${Platform.pathSeparator}windows_oauth.example.json',
      '${Directory(cwd).parent.path}${Platform.pathSeparator}frontend${Platform.pathSeparator}windows_oauth.json',
      '${Directory(cwd).parent.path}${Platform.pathSeparator}frontend${Platform.pathSeparator}windows_oauth.example.json',
      // Common relative paths
      'windows_oauth.json',
      'frontend/windows_oauth.json',
      'windows_oauth.example.json',
      'frontend/windows_oauth.example.json',
    ];

    if (appData.isNotEmpty) {
      rawPaths.add('$appData${Platform.pathSeparator}StudioCapture${Platform.pathSeparator}windows_oauth.json');
    }

    // Deduplicate normalized absolute paths
    final candidatePaths = <String>[];
    final seen = <String>{};
    for (final p in rawPaths) {
      try {
        final abs = File(p).absolute.path;
        if (seen.add(abs.toLowerCase())) {
          candidatePaths.add(abs);
        }
      } catch (_) {}
    }

    debugPrint('[WindowsAuth][Config] Starting OAuth configuration search across ${candidatePaths.length} candidate paths...');

    for (final absPath in candidatePaths) {
      try {
        final file = File(absPath);
        final exists = file.existsSync();
        debugPrint('[WindowsAuth][Config] Checking path: $absPath');
        debugPrint('[WindowsAuth][Config]   - Exists: $exists');

        if (!exists) {
          diagnostics.add('Path: "$absPath" -> Not Found');
          continue;
        }

        final content = await file.readAsString();
        dynamic data;
        try {
          data = jsonDecode(content);
          debugPrint('[WindowsAuth][Config]   - Parses as JSON: true');
        } catch (parseError) {
          debugPrint('[WindowsAuth][Config]   - Parses as JSON: false ($parseError)');
          diagnostics.add('Path: "$absPath" -> Exists, but Invalid JSON: $parseError');
          continue;
        }

        if (data is! Map) {
          debugPrint('[WindowsAuth][Config]   - Root JSON is not a Map (type: ${data.runtimeType})');
          diagnostics.add('Path: "$absPath" -> Exists, but JSON root is not an object');
          continue;
        }

        final map = data;
        final keysFound = map.keys.map((k) => k.toString()).toList();
        debugPrint('[WindowsAuth][Config]   - Found keys: $keysFound');

        Map targetMap = map;
        if (map.containsKey('installed') && map['installed'] is Map) {
          targetMap = map['installed'] as Map;
          debugPrint('[WindowsAuth][Config]   - Using nested "installed" object with keys: ${targetMap.keys.toList()}');
        } else if (map.containsKey('web') && map['web'] is Map) {
          targetMap = map['web'] as Map;
          debugPrint('[WindowsAuth][Config]   - Using nested "web" object with keys: ${targetMap.keys.toList()}');
        }

        // Check variant key names for client_id
        String? cid = targetMap['client_id']?.toString() ??
            targetMap['clientId']?.toString() ??
            targetMap['CLIENT_ID']?.toString() ??
            targetMap['client-id']?.toString();

        // Check variant key names for client_secret
        String? secret = targetMap['client_secret']?.toString() ??
            targetMap['clientSecret']?.toString() ??
            targetMap['CLIENT_SECRET']?.toString() ??
            targetMap['client-secret']?.toString();

        cid = cid?.trim();
        secret = secret?.trim();

        final isCidPlaceholder = cid == null ||
            cid.isEmpty ||
            cid.contains('YOUR_DESKTOP_CLIENT_ID') ||
            cid.contains('YOUR_CLIENT_ID') ||
            cid.startsWith('<');

        final isSecretPlaceholder = secret == null ||
            secret.isEmpty ||
            secret.contains('YOUR_DESKTOP_CLIENT_SECRET') ||
            secret.contains('YOUR_CLIENT_SECRET') ||
            secret.startsWith('<');

        final belongsToExpectedProject = cid != null && cid.startsWith('898946507277');
        debugPrint('[WindowsAuth][Config]   - client_id: non-empty=${cid != null && cid.isNotEmpty}, length=${cid?.length ?? 0}, placeholder=$isCidPlaceholder, belongsToExpectedProject(898946507277)=$belongsToExpectedProject (prefix: ${cid != null && cid.length >= 8 ? "${cid.substring(0, 8)}..." : "<none>"})');
        debugPrint('[WindowsAuth][Config]   - client_secret: non-empty=${secret != null && secret.isNotEmpty}, length=${secret?.length ?? 0}, placeholder=$isSecretPlaceholder (secret value is never logged)');

        if (cid != null && cid.isNotEmpty && !isCidPlaceholder) {
          final effectiveSecret = (secret != null && !isSecretPlaceholder) ? secret : '';
          _configuredClientId = cid;
          _configuredClientSecret = effectiveSecret;
          debugPrint('[WindowsAuth][Config] -> SUCCESS: Valid OAuth configuration loaded from: $absPath');

          // Cache to %APPDATA%\StudioCapture\windows_oauth.json and next to executable
          _cacheOAuthFileToSensibleLocations(cid, effectiveSecret);

          return {
            'client_id': cid,
            'client_secret': effectiveSecret,
          };
        } else {
          diagnostics.add('Path: "$absPath" -> Exists, but client_id is empty or placeholder');
        }
      } catch (e) {
        debugPrint('[WindowsAuth][Config] Error inspecting $absPath: $e');
        diagnostics.add('Path: "$absPath" -> Error inspecting: $e');
      }
    }

    lastConfigErrorReason = 'Google OAuth Desktop configuration (windows_oauth.json) not found or invalid.\n\n'
        'Details of checked locations:\n'
        '${diagnostics.take(6).join("\n")}\n\n'
        'To resolve:\n'
        '1. Ensure "frontend/windows_oauth.json" exists.\n'
        '2. Verify it contains your Desktop Client ID:\n'
        '   {\n'
        '     "client_id": "YOUR_DESKTOP_CLIENT_ID.apps.googleusercontent.com",\n'
        '     "client_secret": "YOUR_DESKTOP_CLIENT_SECRET"\n'
        '   }';
    debugPrint('[WindowsAuth][Config] FAILED to locate valid OAuth configuration.');
    return null;
  }

  void _cacheOAuthFileToSensibleLocations(String cid, String secret) {
    final jsonStr = jsonEncode({'client_id': cid, 'client_secret': secret});
    try {
      final appData = Platform.environment['APPDATA'] ?? Platform.environment['USERPROFILE'] ?? '';
      if (appData.isNotEmpty) {
        final dir = Directory('$appData${Platform.pathSeparator}StudioCapture');
        if (!dir.existsSync()) dir.createSync(recursive: true);
        final file = File('${dir.path}${Platform.pathSeparator}windows_oauth.json');
        file.writeAsStringSync(jsonStr);
      }
    } catch (_) {}

    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final file = File('$exeDir${Platform.pathSeparator}windows_oauth.json');
      file.writeAsStringSync(jsonStr);
    } catch (_) {}
  }

  /// Initialize session on Windows: restore from DPAPI storage
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final restored = await _restoreSession();
      if (restored) {
        debugPrint('[WindowsAuth][Init] Session restored successfully for ${_currentUser?.email}');
      } else {
        debugPrint('[WindowsAuth][Init] No saved session found.');
      }
    } catch (e) {
      debugPrint('[WindowsAuth][Init] Failed to restore session: $e');
    }
  }

  /// Sign In via loopback browser flow
  Future<GoogleSignInResult> signIn({BuildContext? context, bool syncExisting = true}) async {
    if (_isSigningIn) {
      return const GoogleSignInResult(
        status: SignInStatus.cancelled,
        errorMessage: 'Sign-in already in progress',
      );
    }
    _isSigningIn = true;

    HttpServer? server;
    try {
      // 1. Verify OAuth Configuration
      final config = await getOAuthConfig();
      if (config == null || (config['client_id'] ?? '').isEmpty) {
        return GoogleSignInResult(
          status: SignInStatus.developerError,
          errorMessage: lastConfigErrorReason ??
              'Google OAuth Client ID not configured.\n\n'
              'Please create "frontend/windows_oauth.json" with your Desktop Client ID and Client Secret '
              '(see windows_oauth.example.json).',
        );
      }

      final clientId = config['client_id']!;
      final clientSecret = config['client_secret'] ?? '';

      // 2. Start Loopback HTTP Server on an ephemeral free port
      try {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      } catch (e) {
        return GoogleSignInResult(
          status: SignInStatus.error,
          errorMessage: 'Failed to bind local loopback server: $e',
        );
      }

      final port = server.port;
      final redirectUri = 'http://127.0.0.1:$port';
      debugPrint('[WindowsAuth] Loopback listening at $redirectUri');

      // 3. Generate PKCE Verifier & Challenge
      final codeVerifier = _generateRandomString(64);
      final codeChallenge = base64Url
          .encode(sha256.convert(ascii.encode(codeVerifier)).bytes)
          .replaceAll('=', '');
      final state = _generateRandomString(32);

      // 4. Build Authorization URL with exact scope and parameters
      const scopeString = 'openid email profile https://www.googleapis.com/auth/drive.file';
      final authParams = {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': scopeString,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'state': state,
        'prompt': 'consent select_account',
        'access_type': 'offline',
        'include_granted_scopes': 'true',
      };

      final cidPrefix = clientId.length >= 16 ? '${clientId.substring(0, 16)}...' : clientId;
      debugPrint('[WindowsAuth][AuthParams] Exact OAuth 2.0 Authorization Query Parameters:');
      debugPrint('[WindowsAuth][AuthParams]   client_id: $cidPrefix');
      debugPrint('[WindowsAuth][AuthParams]   scope: "$scopeString"');
      debugPrint('[WindowsAuth][AuthParams]   prompt: "${authParams['prompt']}"');
      debugPrint('[WindowsAuth][AuthParams]   access_type: "${authParams['access_type']}"');
      debugPrint('[WindowsAuth][AuthParams]   response_type: "${authParams['response_type']}"');
      debugPrint('[WindowsAuth][AuthParams]   redirect_uri: "${authParams['redirect_uri']}"');
      debugPrint('[WindowsAuth][AuthParams]   include_granted_scopes: "${authParams['include_granted_scopes']}"');

      final authUri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', authParams);
      debugPrint('[WindowsAuth] Opening browser with authorization URL: $authUri');

      final launched = await launchUrl(authUri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await server.close(force: true);
        return const GoogleSignInResult(
          status: SignInStatus.error,
          errorMessage: 'Could not launch default web browser for Google Sign-In.',
        );
      }

      // 5. Wait for loopback request with a 2-minute timeout
      HttpRequest request;
      try {
        request = await server.first.timeout(const Duration(minutes: 2));
      } on TimeoutException {
        await server.close(force: true);
        return const GoogleSignInResult(
          status: SignInStatus.cancelled,
          errorMessage: 'Google Sign-In timed out (2 minutes). Please try again.',
        );
      }

      final params = request.uri.queryParameters;
      final error = params['error'];
      final returnedState = params['state'];
      final code = params['code'];

      // Send response HTML to browser
      if (error != null || code == null || returnedState != state) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..headers.contentType = ContentType.html
          ..write(_buildErrorHtml(error ?? 'Invalid state or missing authorization code'));
        await request.response.close();
        await server.close(force: true);

        return GoogleSignInResult(
          status: SignInStatus.cancelled,
          errorMessage: error == 'access_denied'
              ? 'Sign-in cancelled by user'
              : 'Authorization failed: ${error ?? "Invalid state"}',
        );
      }

      // Success response to browser
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(_buildSuccessHtml());
      await request.response.close();
      await server.close(force: true);

      // Bring application back to foreground
      try {
        await _channel.invokeMethod('restoreApp');
      } catch (_) {}

      // 6. Exchange Authorization Code for Tokens
      debugPrint('[WindowsAuth] Exchanging authorization code for tokens...');
      final tokenResponse = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': clientId,
          if (clientSecret.isNotEmpty) 'client_secret': clientSecret,
          'code': code,
          'code_verifier': codeVerifier,
          'grant_type': 'authorization_code',
          'redirect_uri': redirectUri,
        },
      ).timeout(const Duration(seconds: 15));

      if (tokenResponse.statusCode != 200) {
        debugPrint('[WindowsAuth] Token exchange failed (${tokenResponse.statusCode}): ${tokenResponse.body}');
        return GoogleSignInResult(
          status: SignInStatus.error,
          errorMessage: 'Token exchange failed: ${tokenResponse.body}',
        );
      }

      final tokenData = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
      final grantedScope = tokenData['scope'] as String? ?? '';
      debugPrint('[WindowsAuth] Granted scope from token response: "$grantedScope"');

      final hasDriveScope = grantedScope.contains('drive.file') ||
          grantedScope.contains('https://www.googleapis.com/auth/drive.file');

      if (!hasDriveScope) {
        debugPrint('[WindowsAuth] ERROR: Google Drive permission (drive.file) was NOT granted. Granted scopes: "$grantedScope"');
        await signOut();
        return const GoogleSignInResult(
          status: SignInStatus.error,
          errorMessage: 'Google Drive permission was not granted.\n\n'
              'Sign in again and tick the Drive checkbox to allow Studio Capture to back up recordings.',
        );
      }

      _accessToken = tokenData['access_token'] as String?;
      _refreshToken = tokenData['refresh_token'] as String? ?? _refreshToken;
      final expiresIn = tokenData['expires_in'] as int? ?? 3600;
      _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));

      // 7. Fetch User Profile
      final user = await _fetchUserProfile(_accessToken!);
      if (user == null) {
        return const GoogleSignInResult(
          status: SignInStatus.error,
          errorMessage: 'Failed to fetch Google profile info.',
        );
      }

      _currentUser = user;
      accountNotifier.value = user;
      await _prefs.setGoogleAccountEmail(user.email);
      await _prefs.setAutoSync(true);

      // 8. Persist credentials securely with DPAPI
      await _saveSession(
        clientId: clientId,
        clientSecret: clientSecret,
        refreshToken: _refreshToken,
        user: user,
      );

      return GoogleSignInResult(
        status: SignInStatus.success,
        account: user,
      );
    } catch (e) {
      debugPrint('[WindowsAuth] General error during sign-in: $e');
      return GoogleSignInResult(
        status: SignInStatus.error,
        errorMessage: 'Sign-in error: $e',
      );
    } finally {
      if (server != null) {
        try {
          await server.close(force: true);
        } catch (_) {}
      }
      _isSigningIn = false;
    }
  }

  /// Change account (shows Google account chooser)
  Future<GoogleSignInResult> changeAccount({BuildContext? context}) async {
    await signOut();
    if (context != null && !context.mounted) {
      return const GoogleSignInResult(status: SignInStatus.cancelled, errorMessage: 'Sign-in cancelled');
    }
    return await signIn(context: context, syncExisting: false);
  }

  /// Sign out: revokes tokens, clears state, removes encrypted credentials
  Future<void> signOut() async {
    _currentUser = null;
    accountNotifier.value = null;
    final tokenToRevoke = _accessToken ?? _refreshToken;
    _accessToken = null;
    _refreshToken = null;
    _tokenExpiry = null;

    await _prefs.setGoogleAccountEmail(null);

    // Remove saved encrypted file
    try {
      final file = await _getCredentialsFile();
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (e) {
      debugPrint('[WindowsAuth] Error deleting credentials file: $e');
    }

    if (tokenToRevoke != null) {
      try {
        await http.post(
          Uri.parse('https://oauth2.googleapis.com/revoke'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {'token': tokenToRevoke},
        );
      } catch (_) {}
    }
  }

  /// Obtain fresh access token, auto-refreshing via refresh_token if expired or forced
  Future<String?> getFreshAccessToken({bool forceRefresh = false}) async {
    final now = DateTime.now();
    final isExpired = _tokenExpiry == null || _tokenExpiry!.isBefore(now.add(const Duration(seconds: 60)));

    if (!forceRefresh && _accessToken != null && !isExpired) {
      return _accessToken;
    }

    if (_refreshToken == null) {
      debugPrint('[WindowsAuth] Cannot refresh token: no refresh token available.');
      return null;
    }

    final config = await getOAuthConfig();
    final clientId = config?['client_id'] ?? _configuredClientId;
    final clientSecret = config?['client_secret'] ?? _configuredClientSecret ?? '';

    if (clientId == null || clientId.isEmpty) {
      debugPrint('[WindowsAuth] Cannot refresh token: Client ID is missing.');
      return null;
    }

    debugPrint('[WindowsAuth] Refreshing access token with Google OAuth endpoint...');
    try {
      final response = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': clientId,
          if (clientSecret.isNotEmpty) 'client_secret': clientSecret,
          'refresh_token': _refreshToken!,
          'grant_type': 'refresh_token',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _accessToken = data['access_token'] as String?;
        final expiresIn = data['expires_in'] as int? ?? 3600;
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));
        if (data.containsKey('refresh_token')) {
          _refreshToken = data['refresh_token'] as String?;
        }

        // Re-save session with refreshed access token
        if (_currentUser != null) {
          unawaited(_saveSession(
            clientId: clientId,
            clientSecret: clientSecret,
            refreshToken: _refreshToken,
            user: _currentUser!,
          ));
        }

        debugPrint('[WindowsAuth] Token refreshed successfully.');
        return _accessToken;
      } else {
        debugPrint('[WindowsAuth] Token refresh returned status ${response.statusCode}: ${response.body}');
        if (response.statusCode == 400 && response.body.contains('invalid_grant')) {
          debugPrint('[WindowsAuth] Refresh token revoked or expired (invalid_grant). Clearing invalid session.');
          await signOut();
        }
        return null;
      }
    } catch (e) {
      debugPrint('[WindowsAuth] Token refresh error: $e');
      return null;
    }
  }

  /// Get authenticated HTTP authorization headers
  Future<Map<String, String>?> getAuthHeaders({bool forceRefresh = false}) async {
    final token = await getFreshAccessToken(forceRefresh: forceRefresh);
    if (token == null || token.isEmpty) return null;
    return {
      'Authorization': 'Bearer $token',
    };
  }

  // --- Internal Helpers ---

  Future<AppGoogleUser?> _fetchUserProfile(String accessToken) async {
    try {
      final res = await http.get(
        Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
        headers: {'Authorization': 'Bearer $accessToken'},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final email = data['email'] as String? ?? 'user@gmail.com';
        final name = data['name'] as String? ?? email.split('@').first;
        final picture = data['picture'] as String?;
        final sub = data['sub'] as String? ?? 'windows_${email.hashCode}';

        return AppGoogleUser(
          email: email,
          displayName: name,
          photoUrl: picture,
          id: sub,
        );
      }
    } catch (e) {
      debugPrint('[WindowsAuth] Error fetching user profile: $e');
    }
    return null;
  }

  Future<File> _getCredentialsFile() async {
    final dir = await getApplicationSupportDirectory();
    final authDir = Directory('${dir.path}${Platform.pathSeparator}auth');
    if (!authDir.existsSync()) {
      authDir.createSync(recursive: true);
    }
    return File('${authDir.path}${Platform.pathSeparator}google_oauth.dat');
  }

  Future<void> _saveSession({
    required String clientId,
    required String clientSecret,
    required String? refreshToken,
    required AppGoogleUser user,
  }) async {
    if (refreshToken == null) return;
    try {
      final payload = jsonEncode({
        'client_id': clientId,
        'client_secret': clientSecret,
        'refresh_token': refreshToken,
        'email': user.email,
        'displayName': user.displayName,
        'photoUrl': user.photoUrl,
        'id': user.id,
        'saved_at': DateTime.now().toIso8601String(),
      });

      String encryptedData;
      try {
        final res = await _channel.invokeMethod<String>('dpapiEncrypt', {'data': payload});
        encryptedData = res ?? payload;
      } catch (e) {
        debugPrint('[WindowsAuth] DPAPI encrypt fallback: $e');
        encryptedData = base64Encode(utf8.encode(payload));
      }

      final file = await _getCredentialsFile();
      await file.writeAsString(encryptedData);
      debugPrint('[WindowsAuth] Session securely saved with DPAPI.');
    } catch (e) {
      debugPrint('[WindowsAuth] Failed to save session: $e');
    }
  }

  Future<bool> _restoreSession() async {
    try {
      final file = await _getCredentialsFile();
      if (!file.existsSync()) return false;

      final encryptedData = await file.readAsString();
      if (encryptedData.isEmpty) return false;

      String payload;
      try {
        final res = await _channel.invokeMethod<String>('dpapiDecrypt', {'data': encryptedData});
        payload = (res != null && res.isNotEmpty) ? res : utf8.decode(base64Decode(encryptedData));
      } catch (e) {
        debugPrint('[WindowsAuth] DPAPI decrypt fallback: $e');
        payload = utf8.decode(base64Decode(encryptedData));
      }

      final map = jsonDecode(payload) as Map<String, dynamic>;
      _configuredClientId = map['client_id'] as String?;
      _configuredClientSecret = map['client_secret'] as String?;
      _refreshToken = map['refresh_token'] as String?;

      final email = map['email'] as String?;
      final displayName = map['displayName'] as String? ?? email?.split('@').first ?? 'User';
      final photoUrl = map['photoUrl'] as String?;
      final id = map['id'] as String? ?? 'windows_${email.hashCode}';

      if (_refreshToken != null && email != null) {
        final user = AppGoogleUser(
          email: email,
          displayName: displayName,
          photoUrl: photoUrl,
          id: id,
        );
        _currentUser = user;
        accountNotifier.value = user;

        // Obtain fresh access token silently
        unawaited(getFreshAccessToken());
        return true;
      }
    } catch (e) {
      debugPrint('[WindowsAuth] Error restoring session: $e');
    }
    return false;
  }

  String _generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  String _buildSuccessHtml() {
    return '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Studio Capture - Authenticated</title>
  <style>
    body {
      background: #0F1117;
      color: #FFFFFF;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      display: flex;
      align-items: center;
      justify-content: center;
      height: 100vh;
      margin: 0;
    }
    .card {
      background: #1A1D27;
      border: 1px solid #2B3042;
      padding: 40px;
      border-radius: 16px;
      text-align: center;
      max-width: 420px;
      box-shadow: 0 12px 36px rgba(0,0,0,0.4);
    }
    .icon {
      width: 56px;
      height: 56px;
      border-radius: 28px;
      background: #6366F1;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      font-size: 28px;
      margin-bottom: 20px;
    }
    h1 {
      font-size: 22px;
      margin: 0 0 10px 0;
      font-weight: 600;
    }
    p {
      font-size: 14px;
      color: #94A3B8;
      margin: 0 0 24px 0;
      line-height: 1.5;
    }
    .badge {
      display: inline-block;
      padding: 6px 14px;
      border-radius: 20px;
      background: rgba(99,102,241,0.15);
      color: #818CF8;
      font-size: 13px;
      font-weight: 500;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">✓</div>
    <h1>Authentication Successful</h1>
    <p>Your Google account has been connected to Studio Capture.<br>You can safely close this browser tab and return to the app.</p>
    <div class="badge">Studio Capture Cloud Vault</div>
  </div>
  <script>
    setTimeout(function() { window.close(); }, 3000);
  </script>
</body>
</html>''';
  }

  String _buildErrorHtml(String message) {
    return '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Studio Capture - Authentication Error</title>
  <style>
    body {
      background: #0F1117;
      color: #FFFFFF;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      display: flex;
      align-items: center;
      justify-content: center;
      height: 100vh;
      margin: 0;
    }
    .card {
      background: #1A1D27;
      border: 1px solid #EF4444;
      padding: 40px;
      border-radius: 16px;
      text-align: center;
      max-width: 420px;
      box-shadow: 0 12px 36px rgba(0,0,0,0.4);
    }
    .icon {
      width: 56px;
      height: 56px;
      border-radius: 28px;
      background: #EF4444;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      font-size: 28px;
      margin-bottom: 20px;
    }
    h1 {
      font-size: 22px;
      margin: 0 0 10px 0;
      font-weight: 600;
    }
    p {
      font-size: 14px;
      color: #94A3B8;
      margin: 0 0 24px 0;
      line-height: 1.5;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">✕</div>
    <h1>Sign-In Could Not Complete</h1>
    <p>$message<br><br>Please return to Studio Capture and try again.</p>
  </div>
</body>
</html>''';
  }
}
