import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/app_models.dart';
import 'preferences_service.dart';
import 'recording_service.dart';
import 'app_notification_service.dart';
import 'windows_google_auth_service.dart';

enum SignInStatus {
  success,
  cancelled,
  developerError,
  error,
}

enum DriveErrorType {
  none,
  noNetwork,
  notSignedIn,
  permissionNotGranted,
  driveApiDisabled,
  oauthConsentBlocked,
  developerErrorCode10,
  tokenExpired,
  storageFull,
  fileNotFound,
  invalidFile,
  uploadVerificationFailed,
  unknown,
}

class DriveErrorInfo {
  final DriveErrorType type;
  final String userMessage;
  final String technicalDetails;
  final int? statusCode;

  const DriveErrorInfo({
    required this.type,
    required this.userMessage,
    required this.technicalDetails,
    this.statusCode,
  });

  @override
  String toString() => '$userMessage ($type)';
}

class DriveException implements Exception {
  final DriveErrorType type;
  final String message;
  final String? technicalDetails;
  final int? statusCode;

  DriveException(
    this.type,
    this.message, {
    this.technicalDetails,
    this.statusCode,
  });

  @override
  String toString() => message;
}

class AppGoogleUser {
  final String email;
  final String displayName;
  final String? photoUrl;
  final String id;

  AppGoogleUser({
    required this.email,
    required this.displayName,
    this.photoUrl,
    required this.id,
  });

  factory AppGoogleUser.fromGoogleSignIn(GoogleSignInAccount account) {
    return AppGoogleUser(
      email: account.email,
      displayName: account.displayName ?? account.email.split('@').first,
      photoUrl: account.photoUrl,
      id: account.id,
    );
  }
}

class GoogleSignInResult {
  final SignInStatus status;
  final AppGoogleUser? account;
  final String? errorMessage;
  final String? packageName;
  final String? sha1;

  const GoogleSignInResult({
    required this.status,
    this.account,
    this.errorMessage,
    this.packageName,
    this.sha1,
  });
}

class SyncingVideoItem {
  final String title;
  final String filePath;
  final int sizeBytes;
  final double progress; // 0.0 to 1.0
  final String status; // 'uploading', 'waiting', 'synced', 'failed'
  final String? errorMessage;

  SyncingVideoItem({
    required this.title,
    required this.filePath,
    required this.sizeBytes,
    required this.progress,
    required this.status,
    this.errorMessage,
  });

  SyncingVideoItem copyWith({
    double? progress,
    String? status,
    String? errorMessage,
  }) {
    return SyncingVideoItem(
      title: title,
      filePath: filePath,
      sizeBytes: sizeBytes,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  String get formattedSize {
    if (sizeBytes <= 0) return '0 B';
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class CloudDriveFile {
  final String id;
  final String name;
  final int sizeBytes;
  final DateTime? createdTime;
  final String? webViewLink;
  final String? webContentLink;
  final String? thumbnailLink;

  CloudDriveFile({
    required this.id,
    required this.name,
    required this.sizeBytes,
    this.createdTime,
    this.webViewLink,
    this.webContentLink,
    this.thumbnailLink,
  });

  String get formattedSize {
    if (sizeBytes <= 0) return '0 B';
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeBytes < 1024 * 1024 * 1024) return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get formattedDate {
    if (createdTime == null) return '';
    final now = DateTime.now();
    final diff = now.difference(createdTime!);
    if (diff.inDays == 0) {
      return 'Today at ${createdTime!.hour.toString().padLeft(2, '0')}:${createdTime!.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays == 1) {
      return 'Yesterday at ${createdTime!.hour.toString().padLeft(2, '0')}:${createdTime!.minute.toString().padLeft(2, '0')}';
    }
    return '${createdTime!.day}/${createdTime!.month}/${createdTime!.year}';
  }
}

/// Custom HTTP Client wrapping all Google Drive API network calls with:
/// - Logging request method, URL, and headers
/// - Token injection
/// - Response status code and error response body logging
/// - Automatic single token refresh on HTTP 401 Unauthorized
class DriveAuthClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  final GoogleSignIn? _googleSignIn;
  final WindowsGoogleAuthService? _windowsAuth;
  Map<String, String>? _cachedHeaders;

  DriveAuthClient([GoogleSignIn? googleSignIn])
      : _googleSignIn = googleSignIn,
        _windowsAuth = null;

  DriveAuthClient.windows([WindowsGoogleAuthService? windowsAuth])
      : _googleSignIn = null,
        _windowsAuth = windowsAuth ?? WindowsGoogleAuthService();

  Future<Map<String, String>?> getFreshHeaders({bool forceRefresh = false}) async {
    if (Platform.isWindows || _windowsAuth != null) {
      final auth = _windowsAuth ?? WindowsGoogleAuthService();
      final headers = await auth.getAuthHeaders(forceRefresh: forceRefresh);
      _cachedHeaders = headers;
      return headers;
    }

    if (_googleSignIn == null) {
      debugPrint('[DriveSync][Auth] No GoogleSignIn available.');
      return null;
    }

    final account = _googleSignIn!.currentUser ?? await _googleSignIn!.signInSilently();
    if (account == null) {
      debugPrint('[DriveSync][Auth] No Google account signed in with GoogleSignIn.');
      return null;
    }

    if (forceRefresh) {
      debugPrint('[DriveSync][Token] Clearing token cache for fresh auth headers...');
      try {
        await account.clearAuthCache();
      } catch (e) {
        debugPrint('[DriveSync][Token] clearAuthCache warning: $e');
      }
    }

    try {
      final headers = await account.authHeaders;
      if (headers.isNotEmpty) {
        _cachedHeaders = headers;
        debugPrint('[DriveSync][Token] Auth headers obtained successfully.');
      } else {
        debugPrint('[DriveSync][Token] Auth headers returned empty.');
      }
      return headers;
    } catch (e) {
      debugPrint('[DriveSync][Token] Error getting authHeaders: $e');
      return null;
    }
  }

  Future<String?> getFreshToken({bool forceRefresh = false}) async {
    if (Platform.isWindows || _windowsAuth != null) {
      final auth = _windowsAuth ?? WindowsGoogleAuthService();
      return await auth.getFreshAccessToken(forceRefresh: forceRefresh);
    }

    final headers = await getFreshHeaders(forceRefresh: forceRefresh);
    final authHeader = headers?['Authorization'] ?? headers?['authorization'];
    if (authHeader != null && authHeader.startsWith('Bearer ')) {
      return authHeader.substring(7);
    }
    if (_googleSignIn != null) {
      final account = _googleSignIn!.currentUser;
      if (account != null) {
        try {
          final auth = await account.authentication;
          return auth.accessToken;
        } catch (_) {}
      }
    }
    return null;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    var headers = _cachedHeaders;
    headers ??= await getFreshHeaders();
    if (headers != null) {
      request.headers.addAll(headers);
    }
    request.headers['X-Goog-AuthUser'] = '0';

    debugPrint('[DriveSync][API] --> ${request.method} ${request.url}');

    final response = await _inner.send(request);
    debugPrint('[DriveSync][API] <-- Status: ${response.statusCode}');

    // If 401 Unauthorized, refresh cached headers so next attempt has fresh credentials
    if (response.statusCode == 401) {
      debugPrint('[DriveSync][API] 401 Unauthorized received. Clearing cached auth headers for refresh...');
      _cachedHeaders = null;
      await getFreshHeaders(forceRefresh: true);
    }

    if (response.statusCode >= 400) {
      final bytes = await response.stream.toBytes();
      final body = utf8.decode(bytes, allowMalformed: true);
      debugPrint('[DriveSync][API] Error Response (${response.statusCode}): $body');
      return http.StreamedResponse(
        Stream.value(bytes),
        response.statusCode,
        contentLength: bytes.length,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    }

    return response;
  }

  @override
  void close() {
    _inner.close();
  }
}

/// Unified Single Service for Google Drive Backup & Cloud Vault
class GoogleDriveBackupService {
  static final GoogleDriveBackupService _instance = GoogleDriveBackupService._internal();
  factory GoogleDriveBackupService() => _instance;
  GoogleDriveBackupService._internal();

  static const MethodChannel _channel = MethodChannel('screen_recording');
  final PreferencesService _prefs = PreferencesService();

  /// Optional Web OAuth Client ID from Google Cloud Console (Credentials > Create Credentials > OAuth client ID > Web application).
  /// Set this if you created a Web Application OAuth Client ID in the same Google Cloud project.
  static const String serverClientId =
      '898946507277-jc09918qf5sl8oo5f847ap64dolpu000.apps.googleusercontent.com';

  GoogleSignIn? _googleSignInInstance;
  GoogleSignIn get _googleSignIn {
    if (Platform.isWindows) {
      throw UnsupportedError('GoogleSignIn cannot be called on Windows. Use WindowsGoogleAuthService instead.');
    }
    return _googleSignInInstance ??= GoogleSignIn(
      serverClientId: serverClientId.isNotEmpty ? serverClientId : null,
      scopes: <String>[
        drive.DriveApi.driveFileScope, // 'https://www.googleapis.com/auth/drive.file'
      ],
    );
  }

  DriveAuthClient? _authClient;
  drive.DriveApi? _driveApi;

  AppGoogleUser? _currentUser;
  AppGoogleUser? get currentUser => _currentUser;

  DriveErrorInfo? _lastErrorInfo;
  DriveErrorInfo? get lastErrorInfo => _lastErrorInfo;

  final ValueNotifier<AppGoogleUser?> accountNotifier = ValueNotifier<AppGoogleUser?>(null);
  final ValueNotifier<bool> isSyncingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String?> syncStatusNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<List<SyncingVideoItem>> activeSyncingNotifier = ValueNotifier<List<SyncingVideoItem>>([]);
  final ValueNotifier<List<CloudDriveFile>> cloudFilesNotifier = ValueNotifier<List<CloudDriveFile>>([]);

  bool _initialized = false;
  bool _isSigningIn = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final savedEmail = _prefs.googleAccountEmail;
    debugPrint('[DriveSync][Init] Initializing GoogleDriveBackupService. Saved email: $savedEmail');

    if (Platform.isWindows) {
      await WindowsGoogleAuthService().init();
      _currentUser = WindowsGoogleAuthService().currentUser;
      accountNotifier.value = _currentUser;
      WindowsGoogleAuthService().accountNotifier.addListener(() {
        _currentUser = WindowsGoogleAuthService().accountNotifier.value;
        accountNotifier.value = _currentUser;
      });

      // Listen for network connectivity changes to resume pending uploads
      Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) async {
        final hasConnection = !results.contains(ConnectivityResult.none);
        if (hasConnection && _prefs.autoSync && _currentUser != null) {
          final isWifi = results.contains(ConnectivityResult.wifi);
          if (!_prefs.wifiOnly || isWifi) {
            debugPrint('[DriveSync][Network] Network active. Retrying pending uploads...');
            unawaited(retryPendingUploads());
          }
        }
      });

      if (_prefs.autoSync && _currentUser != null) {
        unawaited(syncExistingRecordings());
      }
      if (_currentUser != null) {
        unawaited(refreshCloudFiles());
      }
      return;
    }

    if (!kIsWeb) {
      // Listen for account change events
      _googleSignIn.onCurrentUserChanged.listen((GoogleSignInAccount? account) async {
        debugPrint('[DriveSync][Auth] onCurrentUserChanged: ${account?.email}');
        if (account != null) {
          final user = AppGoogleUser.fromGoogleSignIn(account);
          _currentUser = user;
          accountNotifier.value = user;
          await _prefs.setGoogleAccountEmail(user.email);
          _driveApi = null;
          if (_prefs.autoSync) {
            unawaited(syncExistingRecordings());
          }
          unawaited(refreshCloudFiles());
        }
      });

      // Listen for network connectivity changes to resume pending uploads
      Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) async {
        final hasConnection = !results.contains(ConnectivityResult.none);
        if (hasConnection && _prefs.autoSync && _currentUser != null) {
          final isWifi = results.contains(ConnectivityResult.wifi);
          if (!_prefs.wifiOnly || isWifi) {
            debugPrint('[DriveSync][Network] Network active. Retrying pending uploads...');
            unawaited(retryPendingUploads());
          }
        }
      });

      // Restore session seamlessly
      try {
        debugPrint('[DriveSync][Init] Attempting silent sign-in to restore saved session...');
        final account = await _googleSignIn.signInSilently();
        if (account != null) {
          final user = AppGoogleUser.fromGoogleSignIn(account);
          _currentUser = user;
          accountNotifier.value = user;
          await _prefs.setGoogleAccountEmail(user.email);
          debugPrint('[DriveSync][Init] Session restored successfully for: ${user.email}');

          // Verify auth headers
          try {
            final headers = await account.authHeaders;
            debugPrint('[DriveSync][Token] Auth headers present on startup: ${headers.isNotEmpty}');
          } catch (e) {
            debugPrint('[DriveSync][Token] Note on startup authHeaders: $e');
          }

          if (_prefs.autoSync) {
            unawaited(syncExistingRecordings());
          }
          unawaited(refreshCloudFiles());
        } else {
          debugPrint('[DriveSync][Init] Silent sign-in returned null. Session requires user sign-in.');
          _currentUser = null;
          accountNotifier.value = null;
        }
      } catch (e) {
        debugPrint('[DriveSync][Init] Silent sign-in failed/skipped: $e');
        _currentUser = null;
        accountNotifier.value = null;
      }
    } else {
      if (_currentUser != null) {
        unawaited(refreshCloudFiles());
      }
    }
  }

  /// Ensure user is authenticated and drive.file scope is authorized.
  /// If not signed in and context is provided, displays the account picker immediately.
  /// Returns true if authorized, false otherwise.
  Future<bool> ensureAuthorized({BuildContext? context}) async {
    debugPrint('[DriveSync][Auth] ensureAuthorized() requested...');
    if (Platform.isWindows) {
      var user = WindowsGoogleAuthService().currentUser;
      if (user == null) {
        final token = await WindowsGoogleAuthService().getFreshAccessToken();
        if (token != null) {
          user = WindowsGoogleAuthService().currentUser;
        }
      }

      if (user != null) {
        _currentUser = user;
        accountNotifier.value = user;
        await _prefs.setGoogleAccountEmail(user.email);
        return true;
      }

      if (context != null && context.mounted) {
        final result = await signIn(context: context, syncExisting: false);
        return result.status == SignInStatus.success;
      }
      return false;
    }

    var account = _googleSignIn.currentUser;
    if (account == null && !kIsWeb) {
      try {
        account = await _googleSignIn.signInSilently();
      } catch (e) {
        debugPrint('[DriveSync][Auth] signInSilently error: $e');
      }
    }

    if (account != null) {
      _currentUser = AppGoogleUser.fromGoogleSignIn(account);
      accountNotifier.value = _currentUser;
      await _prefs.setGoogleAccountEmail(account.email);

      // Web-only scope check (canAccessScopes is only implemented on web)
      if (kIsWeb) {
        final hasScope = await _googleSignIn.canAccessScopes([drive.DriveApi.driveFileScope]);
        debugPrint('[DriveSync][Scope] Web canAccessScopes: $hasScope');
        if (!hasScope) {
          try {
            final granted = await _googleSignIn.requestScopes([drive.DriveApi.driveFileScope]);
            if (!granted) {
              _lastErrorInfo = const DriveErrorInfo(
                type: DriveErrorType.permissionNotGranted,
                userMessage: 'Google Drive permission was not granted. Please sign in and allow access.',
                technicalDetails: 'User declined scope: https://www.googleapis.com/auth/drive.file',
              );
              if (context != null && context.mounted) {
                _showErrorSnackBar(context, _lastErrorInfo!.userMessage);
              }
              return false;
            }
          } catch (e) {
            debugPrint('[DriveSync][Scope] Web requestScopes error: $e');
          }
        }
      }

      // Check auth headers
      Map<String, String>? headers;
      try {
        headers = await account.authHeaders;
      } catch (e) {
        debugPrint('[DriveSync][Token] authHeaders check note: $e. Clearing cache for fresh headers...');
        try {
          await account.clearAuthCache();
          headers = await account.authHeaders;
        } catch (e2) {
          debugPrint('[DriveSync][Token] clearAuthCache failed: $e2');
        }
      }

      final hasAuth = headers != null && headers.isNotEmpty;
      debugPrint('[DriveSync][Token] Valid auth headers present: $hasAuth');
      if (hasAuth) {
        return true;
      }
    }

    // If no account, show account picker dialog
    if (context != null && context.mounted) {
      debugPrint('[DriveSync][Auth] No active session. Showing account chooser...');
      final result = await signIn(context: context, syncExisting: false);
      if (result.status == SignInStatus.success) {
        return true;
      }
      if (result.status == SignInStatus.developerError || result.status == SignInStatus.error) {
        if (context.mounted) {
          showErrorDialog(context, result);
        }
      }
    }

    return false;
  }

  /// Returns authenticated DriveApi instance with DriveAuthClient wrapper
  Future<drive.DriveApi?> getDriveApi({bool forceRefresh = false}) async {
    if (kIsWeb) return null;

    if (Platform.isWindows) {
      if (!forceRefresh && _driveApi != null && WindowsGoogleAuthService().currentUser != null) {
        return _driveApi;
      }

      final user = WindowsGoogleAuthService().currentUser;
      if (user == null) {
        debugPrint('[DriveSync][API] Cannot create DriveApi: no signed-in Google account on Windows.');
        _driveApi = null;
        _authClient = null;
        return null;
      }

      _authClient = DriveAuthClient.windows(WindowsGoogleAuthService());
      final headers = await _authClient!.getFreshHeaders(forceRefresh: forceRefresh);
      if (headers == null || headers.isEmpty) {
        debugPrint('[DriveSync][API] Failed to obtain valid auth headers on Windows.');
        return null;
      }

      _driveApi = drive.DriveApi(_authClient!);
      return _driveApi;
    }

    if (!forceRefresh && _driveApi != null && _googleSignIn.currentUser != null) {
      return _driveApi;
    }

    final account = _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
    if (account == null) {
      debugPrint('[DriveSync][API] Cannot create DriveApi: no signed-in Google account.');
      _driveApi = null;
      _authClient = null;
      return null;
    }

    _authClient ??= DriveAuthClient(_googleSignIn);
    final headers = await _authClient!.getFreshHeaders(forceRefresh: forceRefresh);
    if (headers == null || headers.isEmpty) {
      debugPrint('[DriveSync][API] Cannot create DriveApi: failed to obtain valid auth headers.');
      return null;
    }

    _driveApi = drive.DriveApi(_authClient!);
    return _driveApi;
  }

  /// Sign In with Google and request Google Drive scopes
  Future<GoogleSignInResult> signIn({BuildContext? context, bool syncExisting = true}) async {
    debugPrint('[DriveSync][Auth] signIn() called...');
    if (_isSigningIn) {
      debugPrint('[DriveSync][Auth] Sign-in already in progress. Ignoring duplicate call.');
      return const GoogleSignInResult(
        status: SignInStatus.cancelled,
        errorMessage: 'Sign-in already in progress',
      );
    }
    _isSigningIn = true;

    if (Platform.isWindows) {
      try {
        final result = await WindowsGoogleAuthService().signIn(context: context, syncExisting: syncExisting);
        if (result.status == SignInStatus.success && result.account != null) {
          _currentUser = result.account;
          accountNotifier.value = result.account;
          await _prefs.setGoogleAccountEmail(result.account!.email);
          await _prefs.setAutoSync(true);
          _driveApi = null;
          if (syncExisting) {
            unawaited(syncExistingRecordings());
          }
          unawaited(refreshCloudFiles());
        } else if (result.status == SignInStatus.developerError || result.status == SignInStatus.error) {
          if (context != null && context.mounted) {
            showErrorDialog(context, result);
          }
        }
        return result;
      } finally {
        _isSigningIn = false;
      }
    }

    if (!kIsWeb) {
      try {
        debugPrint('[DriveSync][Auth] Invoking Google Play Services native account picker...');
        final GoogleSignInAccount? account = await _googleSignIn.signIn();
        if (account == null) {
          debugPrint('[DriveSync][Auth] Google Sign-In was cancelled.');
          return const GoogleSignInResult(
            status: SignInStatus.cancelled,
            errorMessage: 'Sign-in cancelled',
          );
        }

        debugPrint('[DriveSync][Auth] Account selected: ${account.email} (${account.displayName ?? ""}');

        // Web-only scope check
        if (kIsWeb) {
          final hasScope = await _googleSignIn.canAccessScopes([drive.DriveApi.driveFileScope]);
          if (!hasScope) {
            final scopeGranted = await _googleSignIn.requestScopes([drive.DriveApi.driveFileScope]);
            if (!scopeGranted) {
              _lastErrorInfo = const DriveErrorInfo(
                type: DriveErrorType.permissionNotGranted,
                userMessage: 'Google Drive permission was not granted. Please allow access to upload recordings.',
                technicalDetails: 'User declined scope: https://www.googleapis.com/auth/drive.file',
              );
              return GoogleSignInResult(
                status: SignInStatus.error,
                errorMessage: _lastErrorInfo!.userMessage,
              );
            }
          }
        }

        // On Android, Drive scope was requested during signIn(scopes: [...]).
        // Obtain authenticated headers from currentUser.authHeaders.
        Map<String, String>? headers;
        try {
          headers = await account.authHeaders;
        } catch (e) {
          debugPrint('[DriveSync][Auth] Exception reading authHeaders: $e');
          // If scope is missing or needs explicit grant, wrap requestScopes in try/catch
          try {
            final granted = await _googleSignIn.requestScopes([drive.DriveApi.driveFileScope]);
            if (granted) {
              headers = await account.authHeaders;
            }
          } catch (scopeErr) {
            debugPrint('[DriveSync][Auth] requestScopes exception: $scopeErr');
          }
        }

        debugPrint('[DriveSync][Token] Auth headers obtained: ${headers != null && headers.isNotEmpty ? "YES" : "NO"}');

        final user = AppGoogleUser.fromGoogleSignIn(account);
        _currentUser = user;
        accountNotifier.value = user;
        await _prefs.setGoogleAccountEmail(user.email);
        await _prefs.setAutoSync(true);

        _driveApi = null; // Rebuild client with fresh account

        if (syncExisting) {
          unawaited(syncExistingRecordings());
        }
        unawaited(refreshCloudFiles());

        return GoogleSignInResult(
          status: SignInStatus.success,
          account: user,
        );
      } on PlatformException catch (e) {
        debugPrint('[DriveSync][Auth] PlatformException: ${e.code} - ${e.message}');
        if (e.message?.contains('12502') == true) {
          debugPrint('[DriveSync][Auth] Google Sign-in already in progress (12502). Please complete consent prompt.');
          return const GoogleSignInResult(
            status: SignInStatus.cancelled,
            errorMessage: 'Google Sign-In is in progress. Please approve the prompt on your screen.',
          );
        }

        final buildInfo = await getBuildDetails();
        final isDevError = e.message?.contains(' 10:') == true ||
            e.message?.contains('DEVELOPER_ERROR') == true ||
            e.code == '10';

        _lastErrorInfo = DriveErrorInfo(
          type: isDevError ? DriveErrorType.developerErrorCode10 : DriveErrorType.unknown,
          userMessage: isDevError
              ? 'Google Play Services Code 10 (DEVELOPER_ERROR). Check Google Cloud Console OAuth setup.'
              : (e.message ?? e.toString()),
          technicalDetails: 'PlatformException: ${e.code} - ${e.message}\nPackage: ${buildInfo['packageName']}\nSHA-1: ${buildInfo['sha1']}',
        );

        return GoogleSignInResult(
          status: isDevError ? SignInStatus.developerError : SignInStatus.error,
          errorMessage: e.message ?? e.toString(),
          packageName: buildInfo['packageName'],
          sha1: buildInfo['sha1'],
        );
      } catch (e) {
        debugPrint('[DriveSync][Auth] General Sign-In error: $e');
        final buildInfo = await getBuildDetails();
        _lastErrorInfo = DriveErrorInfo(
          type: DriveErrorType.unknown,
          userMessage: e.toString(),
          technicalDetails: e.toString(),
        );
        return GoogleSignInResult(
          status: SignInStatus.error,
          errorMessage: e.toString(),
          packageName: buildInfo['packageName'],
          sha1: buildInfo['sha1'],
        );
      } finally {
        _isSigningIn = false;
      }
    }

    // Web fallback
    final selectedEmail = context != null
        ? await showGoogleAccountChooser(context)
        : 'user@gmail.com';

    if (selectedEmail != null && selectedEmail.isNotEmpty) {
      final user = AppGoogleUser(
        email: selectedEmail,
        displayName: _formatDisplayName(selectedEmail),
        id: 'account_${selectedEmail.hashCode}',
      );
      _currentUser = user;
      accountNotifier.value = user;
      await _prefs.setGoogleAccountEmail(user.email);
      await _prefs.setAutoSync(true);

      if (syncExisting) {
        unawaited(syncExistingRecordings());
      }
      unawaited(refreshCloudFiles());

      return GoogleSignInResult(
        status: SignInStatus.success,
        account: user,
      );
    }

    return const GoogleSignInResult(
      status: SignInStatus.cancelled,
      errorMessage: 'Sign-in cancelled',
    );
  }

  Future<GoogleSignInResult> changeAccount({BuildContext? context}) async {
    _currentUser = null;
    accountNotifier.value = null;
    _driveApi = null;
    if (context != null && !context.mounted) {
      return const GoogleSignInResult(status: SignInStatus.cancelled, errorMessage: 'Sign-in cancelled');
    }
    if (Platform.isWindows) {
      final res = await WindowsGoogleAuthService().changeAccount(context: context);
      if (res.status == SignInStatus.success && res.account != null) {
        _currentUser = res.account;
        accountNotifier.value = res.account;
        await _prefs.setGoogleAccountEmail(res.account!.email);
        await _prefs.setAutoSync(true);
        _driveApi = null;
        unawaited(refreshCloudFiles());
      } else if (res.status == SignInStatus.developerError || res.status == SignInStatus.error) {
        if (context != null && context.mounted) {
          showErrorDialog(context, res);
        }
      }
      return res;
    }
    return await signIn(context: context, syncExisting: false);
  }

  Future<void> signOut() async {
    if (Platform.isWindows) {
      await WindowsGoogleAuthService().signOut();
    } else {
      try {
        if (!kIsWeb) {
          await _googleSignIn.signOut();
        }
      } catch (_) {}
    }
    _currentUser = null;
    _driveApi = null;
    _authClient = null;
    accountNotifier.value = null;
    await _prefs.setGoogleAccountEmail(null);
  }

  Future<GoogleSignInResult?> setAutoSync(bool enabled, {BuildContext? context}) async {
    if (enabled) {
      final isAuth = await ensureAuthorized(context: context);
      if (!isAuth) {
        await _prefs.setAutoSync(false);
        return GoogleSignInResult(
          status: SignInStatus.error,
          errorMessage: _lastErrorInfo?.userMessage ?? 'Sign-in required',
        );
      }
      await _prefs.setAutoSync(true);
      unawaited(syncExistingRecordings());
      return null;
    } else {
      await _prefs.setAutoSync(false);
      return null;
    }
  }

  Future<void> setWifiOnly(bool value) async {
    await _prefs.setWifiOnly(value);
  }

  /// Get or create the 'Studio Capture Recordings' folder in Google Drive
  Future<String?> getOrCreateFolder(drive.DriveApi driveApi) async {
    try {
      final cachedId = _prefs.driveFolderId;
      if (cachedId != null && cachedId.isNotEmpty) {
        try {
          final file = await driveApi.files.get(cachedId, $fields: 'id, name, trashed') as drive.File;
          if (file.trashed != true) {
            debugPrint('[DriveSync][Folder] Using cached folder ID: $cachedId');
            return cachedId;
          }
        } catch (_) {}
      }

      final q = "name = 'Studio Capture Recordings' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
      debugPrint('[DriveSync][Folder] Querying Drive for existing "Studio Capture Recordings" folder...');
      final fileList = await driveApi.files.list(q: q, spaces: 'drive', $fields: 'files(id, name)');
      if (fileList.files != null && fileList.files!.isNotEmpty) {
        final id = fileList.files!.first.id;
        if (id != null) {
          await _prefs.setDriveFolderId(id);
          debugPrint('[DriveSync][Folder] Found existing folder ID: $id');
          return id;
        }
      }

      debugPrint('[DriveSync][Folder] Creating new "Studio Capture Recordings" folder...');
      final folder = drive.File()
        ..name = 'Studio Capture Recordings'
        ..mimeType = 'application/vnd.google-apps.folder';
      final created = await driveApi.files.create(folder, $fields: 'id, name');
      if (created.id != null) {
        await _prefs.setDriveFolderId(created.id);
        debugPrint('[DriveSync][Folder] Created new folder ID: ${created.id}');
      }
      return created.id;
    } catch (e) {
      debugPrint('[DriveSync][Folder] Error getting or creating Drive folder: $e');
      rethrow;
    }
  }

  /// Upload recording using resumable upload, progress updates, and size verification
  Future<bool> uploadRecording(
    String filePath, {
    String? title,
    bool force = false,
    BuildContext? context,
    Function(double)? onProgress,
  }) async {
    if (!_prefs.autoSync && !force) return false;

    // Check Wi-Fi only condition
    if (_prefs.wifiOnly) {
      final isWifi = await isWifiConnected();
      if (!isWifi) {
        debugPrint('[DriveSync] Wi-Fi only enabled; device is on cellular or disconnected.');
        syncStatusNotifier.value = 'Waiting for Wi-Fi';
        final fileName = title ?? filePath.split(Platform.pathSeparator).last;
        final fileSize = (!kIsWeb && File(filePath).existsSync()) ? File(filePath).lengthSync() : 0;
        final waitingItem = SyncingVideoItem(
          title: fileName,
          filePath: filePath,
          sizeBytes: fileSize,
          progress: 0.0,
          status: 'waiting',
          errorMessage: 'Waiting for Wi-Fi connection',
        );
        activeSyncingNotifier.value = [
          ...activeSyncingNotifier.value.where((i) => i.title != fileName),
          waitingItem,
        ];
        return false;
      }
    }

    final fileName = title ?? (filePath.split(Platform.pathSeparator).last);
    if (_prefs.isCloudSynced(fileName) && !force) {
      debugPrint('[DriveSync] File "$fileName" is already cloud synced.');
      return true;
    }

    if (!kIsWeb) {
      final file = File(filePath);
      if (!file.existsSync()) {
        debugPrint('[DriveSync] File does not exist on disk: $filePath');
        return false;
      }

      // Ensure file has finished writing
      int previousSize = -1;
      int currentSize = file.lengthSync();
      int checks = 0;
      while (currentSize == 0 || (currentSize != previousSize && checks < 4)) {
        await Future.delayed(const Duration(milliseconds: 250));
        previousSize = currentSize;
        currentSize = file.lengthSync();
        checks++;
      }
      if (currentSize == 0) {
        debugPrint('[DriveSync] File is 0 bytes: $filePath');
        return false;
      }
    }

    final fileSize = (!kIsWeb && File(filePath).existsSync()) ? File(filePath).lengthSync() : (15 * 1024 * 1024);

    // Track active syncing video in UI queue
    final syncingItem = SyncingVideoItem(
      title: fileName,
      filePath: filePath,
      sizeBytes: fileSize,
      progress: 0.05,
      status: 'uploading',
    );
    activeSyncingNotifier.value = [
      ...activeSyncingNotifier.value.where((i) => i.title != fileName),
      syncingItem,
    ];
    isSyncingNotifier.value = true;
    syncStatusNotifier.value = 'Syncing $fileName...';

    if (kIsWeb) {
      return await _simulateWebUpload(filePath, fileName, fileSize);
    }

    return await _executeUpload(
      filePath: filePath,
      fileName: fileName,
      fileSize: fileSize,
      force: force,
      context: context,
      onProgress: onProgress,
    );
  }

  Future<bool> _executeUpload({
    required String filePath,
    required String fileName,
    required int fileSize,
    required bool force,
    BuildContext? context,
    Function(double)? onProgress,
    bool isRetry = false,
  }) async {
    final file = File(filePath);

    try {
      // Refresh auth headers before every upload
      if (!isRetry && !kIsWeb) {
        if (Platform.isWindows) {
          debugPrint('[DriveSync][Upload] Refreshing Windows auth token before upload...');
          await WindowsGoogleAuthService().getFreshAccessToken();
        } else {
          debugPrint('[DriveSync][Upload] Refreshing auth headers via silentSignIn before upload...');
          try {
            await _googleSignIn.signInSilently();
          } catch (e) {
            debugPrint('[DriveSync][Upload] Pre-upload silentSignIn note: $e');
          }
        }
      }

      // 1. Get authenticated Drive API client
      var driveApi = await getDriveApi(forceRefresh: isRetry);
      if (driveApi == null) {
        debugPrint('[DriveSync][Upload] No active session. Attempting silent authorization...');
        final isAuth = await ensureAuthorized();
        if (isAuth) {
          driveApi = await getDriveApi(forceRefresh: isRetry);
        }
      }

      if (driveApi == null) {
        throw DriveException(
          DriveErrorType.notSignedIn,
          'Google Drive session not authenticated. Please sign in.',
          technicalDetails: 'No active Google account with valid tokens found in GoogleSignIn.',
        );
      }

      // 2. Locate or create folder
      final folderId = await getOrCreateFolder(driveApi);
      if (folderId == null) {
        throw DriveException(
          DriveErrorType.unknown,
          'Could not access "Studio Capture Recordings" folder.',
          technicalDetails: 'getOrCreateFolder returned null.',
        );
      }

      // 3. Prepare resumable upload media with progress streaming
      final totalBytes = file.lengthSync();
      int bytesSent = 0;

      int lastNotifiedPct = -5;
      final progressStream = file.openRead().transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (List<int> chunk, EventSink<List<int>> sink) {
            bytesSent += chunk.length;
            final prog = totalBytes > 0 ? (bytesSent / totalBytes).clamp(0.0, 1.0) : 0.0;
            _updateSyncingProgress(fileName, prog);
            if (onProgress != null) onProgress(prog);
            final currentPct = (prog * 100).toInt();
            if (currentPct - lastNotifiedPct >= 5 || currentPct == 100) {
              lastNotifiedPct = currentPct;
              AppNotificationService.notifyCloudBackupProgress(fileName: fileName, progress: prog);
            }
            sink.add(chunk);
          },
        ),
      );

      final media = drive.Media(progressStream, totalBytes);
      final driveFile = drive.File()
        ..name = fileName
        ..parents = [folderId]
        ..mimeType = 'video/mp4';

      debugPrint('[DriveSync][Upload] Starting resumable upload for "$fileName" ($totalBytes bytes)...');
      final created = await driveApi.files.create(
        driveFile,
        uploadMedia: media,
        uploadOptions: drive.UploadOptions.resumable,
        $fields: 'id, name, size, webViewLink, webContentLink',
      );

      debugPrint('[DriveSync][Upload] Files.create finished. File ID: ${created.id}');

      if (created.id == null || created.id!.isEmpty) {
        throw DriveException(
          DriveErrorType.uploadVerificationFailed,
          'Drive upload verification failed: no file ID was returned by Google Drive.',
        );
      }

      // 4. Verify remote file exists and size matches local file
      debugPrint('[DriveSync][Verify] Fetching created file from Drive to verify size...');
      final verified = await driveApi.files.get(created.id!, $fields: 'id, name, size') as drive.File;
      var remoteSize = int.tryParse(verified.size ?? '0') ?? 0;
      if (remoteSize == 0) {
        // Brief retry to allow Drive metadata to settle
        await Future.delayed(const Duration(milliseconds: 500));
        try {
          final recheck = await driveApi.files.get(created.id!, $fields: 'id, name, size') as drive.File;
          remoteSize = int.tryParse(recheck.size ?? '0') ?? 0;
        } catch (_) {}
      }
      debugPrint('[DriveSync][Verify] Local size: $totalBytes, Remote size in Drive: $remoteSize');

      if (remoteSize > 0 && remoteSize != totalBytes) {
        throw DriveException(
          DriveErrorType.uploadVerificationFailed,
          'Upload verification failed: Drive file size ($remoteSize bytes) does not match local file size ($totalBytes bytes).',
          technicalDetails: 'Expected $totalBytes bytes, but Google Drive reported $remoteSize bytes.',
        );
      }

      final confirmedSize = remoteSize > 0 ? remoteSize : totalBytes;

      // 5. Store synced record in preferences
      await _prefs.addSyncedCloudFile({
        'title': fileName,
        'filePath': filePath,
        'driveId': created.id,
        'size': confirmedSize,
      });

      _updateSyncingProgress(fileName, 1.0, status: 'synced');
      AppNotificationService.notifyCloudBackupComplete(fileName: fileName);
      Future.delayed(const Duration(seconds: 3), () {
        activeSyncingNotifier.value = activeSyncingNotifier.value.where((i) => i.title != fileName).toList();
      });

      await refreshCloudFiles();
      syncStatusNotifier.value = 'Synced';
      _lastErrorInfo = null;
      return true;
    } catch (e) {
      debugPrint('[DriveSync][Upload] Upload failed for "$fileName": $e');
      final errorInfo = parseDriveError(e);
      _lastErrorInfo = errorInfo;

      final is401 = e.toString().contains('401') ||
          errorInfo.type == DriveErrorType.tokenExpired ||
          (e is drive.DetailedApiRequestError && e.status == 401);

      // Single auto-retry with refreshed credentials on auth/token error or HTTP 401
      if (!isRetry && (is401 || errorInfo.type == DriveErrorType.notSignedIn)) {
        debugPrint('[DriveSync][Upload] Encountered 401/expired session. Refreshing auth headers once and retrying...');
        if (_authClient != null) {
          await _authClient!.getFreshHeaders(forceRefresh: true);
        }
        final reauthSuccess = await ensureAuthorized();
        if (reauthSuccess) {
          return await _executeUpload(
            filePath: filePath,
            fileName: fileName,
            fileSize: fileSize,
            force: force,
            context: context,
            onProgress: onProgress,
            isRetry: true,
          );
        }
      }

      // Single auto-retry for transient network glitch with 1.5s backoff
      if (!isRetry && errorInfo.type == DriveErrorType.noNetwork) {
        debugPrint('[DriveSync][Upload] Transient network error. Waiting 1.5s before one retry...');
        await Future.delayed(const Duration(milliseconds: 1500));
        return await _executeUpload(
          filePath: filePath,
          fileName: fileName,
          fileSize: fileSize,
          force: force,
          context: context,
          onProgress: onProgress,
          isRetry: true,
        );
      }

      // Mark as failed in active queue and notify
      AppNotificationService.notifyCloudBackupFailed(fileName: fileName, reason: errorInfo.userMessage);
      final failedItem = SyncingVideoItem(
        title: fileName,
        filePath: filePath,
        sizeBytes: fileSize,
        progress: 0.0,
        status: 'failed',
        errorMessage: errorInfo.userMessage,
      );
      activeSyncingNotifier.value = [
        ...activeSyncingNotifier.value.where((i) => i.title != fileName),
        failedItem,
      ];
      syncStatusNotifier.value = 'Failed: ${errorInfo.userMessage}';
      return false;
    } finally {
      isSyncingNotifier.value = false;
    }
  }

  /// Retries a previously failed upload by re-authorizing credentials first
  Future<bool> retryUpload(BuildContext context, String filePath, String title) async {
    debugPrint('[DriveSync] User tapped Retry for "$title". Re-running authorization...');

    // 1. Re-run authorization: if broken, prompt account chooser
    final isAuthorized = await ensureAuthorized(context: context);
    if (!isAuthorized) {
      debugPrint('[DriveSync] Authorization not completed during retry.');
      return false;
    }

    if (!context.mounted) return false;

    // 2. Perform upload
    return await uploadRecording(filePath, title: title, force: true, context: context);
  }

  /// Parse exceptions into clear, specific, human-readable DriveErrorInfo
  DriveErrorInfo parseDriveError(dynamic error) {
    if (error is DriveException) {
      return DriveErrorInfo(
        type: error.type,
        userMessage: error.message,
        technicalDetails: error.technicalDetails ?? error.message,
        statusCode: error.statusCode,
      );
    }

    if (error is drive.DetailedApiRequestError) {
      final status = error.status;
      final message = error.message ?? '';
      debugPrint('[DriveSync][Error] Drive API DetailedApiRequestError ($status): $message');

      // 1. Drive API Disabled in Google Cloud Console
      if (status == 403 && (message.contains('Drive API has not been used') || message.contains('is disabled') || message.contains('accessNotConfigured'))) {
        return DriveErrorInfo(
          type: DriveErrorType.driveApiDisabled,
          userMessage: 'Google Drive API is disabled in your Google Cloud Project. Enable it in Google Cloud Console.',
          technicalDetails: 'HTTP 403: $message\n\nHow to fix:\n1. Open console.cloud.google.com\n2. Select your project\n3. Go to "APIs & Services" > "Library"\n4. Search "Google Drive API" and click "Enable".',
          statusCode: 403,
        );
      }

      // 2. Drive scope permission not granted
      if (status == 403 && (message.contains('ACCESS_TOKEN_SCOPE_INSUFFICIENT') || message.contains('insufficientPermissions') || message.contains('Insufficient Permission'))) {
        return DriveErrorInfo(
          type: DriveErrorType.permissionNotGranted,
          userMessage: 'Google Drive access permission was not granted. Please sign in and allow access.',
          technicalDetails: 'HTTP 403: $message\n\nScope "https://www.googleapis.com/auth/drive.file" was not consented.',
          statusCode: 403,
        );
      }

      // 3. Storage full
      if (status == 403 && (message.contains('storageQuotaExceeded') || message.contains('quotaExceeded'))) {
        return DriveErrorInfo(
          type: DriveErrorType.storageFull,
          userMessage: 'Your Google Drive storage is full. Free up space and try again.',
          technicalDetails: 'HTTP 403: $message',
          statusCode: 403,
        );
      }

      // 4. Token expired
      if (status == 401) {
        return DriveErrorInfo(
          type: DriveErrorType.tokenExpired,
          userMessage: 'Google Drive session expired. Please sign in again.',
          technicalDetails: 'HTTP 401: $message',
          statusCode: 401,
        );
      }

      // 5. OAuth consent blocked / test user required
      if (status == 403) {
        return DriveErrorInfo(
          type: DriveErrorType.oauthConsentBlocked,
          userMessage: 'Access blocked by Google. Add your account as a Test User in Google Cloud Console.',
          technicalDetails: 'HTTP 403: $message\n\nHow to fix:\n1. In Google Cloud Console, open "OAuth consent screen"\n2. Under "Test users", add your Gmail address\n3. Save and sign in again.',
          statusCode: 403,
        );
      }

      return DriveErrorInfo(
        type: DriveErrorType.unknown,
        userMessage: 'Google Drive error ($status): $message',
        technicalDetails: 'HTTP $status: $message',
        statusCode: status,
      );
    }

    if (error is SocketException ||
        error.toString().contains('SocketException') ||
        error.toString().contains('Network is unreachable') ||
        error.toString().contains('ClientException')) {
      return DriveErrorInfo(
        type: DriveErrorType.noNetwork,
        userMessage: 'No internet connection. Upload will resume when network is available.',
        technicalDetails: error.toString(),
      );
    }

    if (error is PlatformException) {
      if (error.code == '10' ||
          error.message?.contains('10') == true ||
          error.message?.contains('DEVELOPER_ERROR') == true) {
        return DriveErrorInfo(
          type: DriveErrorType.developerErrorCode10,
          userMessage: 'Google Cloud Setup Required (Code 10 DEVELOPER_ERROR). Package name or SHA-1 not registered.',
          technicalDetails: 'PlatformException: ${error.code} - ${error.message}\n\nHow to fix:\nIn Google Cloud Console > "Credentials", add an Android OAuth 2.0 Client ID with:\nPackage: com.example.studio_capture_app\nSHA-1: check Copy Details',
        );
      }
    }

    return DriveErrorInfo(
      type: DriveErrorType.unknown,
      userMessage: error.toString().replaceFirst('Exception: ', ''),
      technicalDetails: error.toString(),
    );
  }

  void _updateSyncingProgress(String fileName, double progress, {String status = 'uploading'}) {
    activeSyncingNotifier.value = activeSyncingNotifier.value.map((i) {
      if (i.title == fileName) {
        return i.copyWith(progress: progress, status: status);
      }
      return i;
    }).toList();
  }

  Future<bool> _simulateWebUpload(String filePath, String fileName, int fileSize) async {
    await Future.delayed(const Duration(milliseconds: 600));
    _updateSyncingProgress(fileName, 0.55);
    await Future.delayed(const Duration(milliseconds: 600));
    _updateSyncingProgress(fileName, 0.95);
    await Future.delayed(const Duration(milliseconds: 400));
    await _prefs.addSyncedCloudFile({
      'title': fileName,
      'filePath': filePath,
      'driveId': 'web_rec_${DateTime.now().millisecondsSinceEpoch}',
      'size': fileSize,
    });
    _updateSyncingProgress(fileName, 1.0, status: 'synced');
    Future.delayed(const Duration(seconds: 3), () {
      activeSyncingNotifier.value = activeSyncingNotifier.value.where((i) => i.title != fileName).toList();
    });
    await refreshCloudFiles();
    isSyncingNotifier.value = false;
    syncStatusNotifier.value = 'Synced';
    return true;
  }

  Future<void> retryPendingUploads() async {
    if (_currentUser == null || !_prefs.autoSync) return;
    if (isSyncingNotifier.value) return;

    final pendingItems = activeSyncingNotifier.value
        .where((i) => i.status == 'failed' || i.status == 'waiting')
        .toList();

    for (final item in pendingItems) {
      if (!kIsWeb && File(item.filePath).existsSync()) {
        await uploadRecording(item.filePath, title: item.title, force: true);
      }
    }

    await syncExistingRecordings();
  }

  Future<void> syncExistingRecordings() async {
    if (_currentUser == null || !_prefs.autoSync) return;

    if (RecordingService().savedMediaItems.isEmpty && !kIsWeb) {
      try {
        final diskFiles = await RecordingService().getRecordings();
        for (final f in diskFiles) {
          final filename = f.path.split(Platform.pathSeparator).last;
          if (!RecordingService().savedMediaItems.any((m) => m.filePath == f.path)) {
            final stat = f.statSync();
            final meta = await RecordingService().getVideoMetadata(f.path);
            final durMs = (meta?['durationMs'] as num?)?.toInt() ?? 0;
            RecordingService().addSavedRecording(
              MediaItem(
                id: 'disk_${f.path.hashCode}',
                title: filename,
                type: 'video',
                thumbnail: meta?['thumbnailPath'] as String? ?? '',
                duration: RecordingService().formatDuration(Duration(milliseconds: durMs)),
                resolution: '1080p',
                date: 'Saved',
                size: RecordingService().formatSize(stat.size),
                filePath: f.path,
              ),
            );
          }
        }
      } catch (_) {}
    }

    final items = List<MediaItem>.from(RecordingService().savedMediaItems);
    for (final item in items) {
      final path = item.filePath;
      if (path != null && path.isNotEmpty && (!kIsWeb && File(path).existsSync())) {
        if (!_prefs.isCloudSynced(item.title)) {
          await uploadRecording(path, title: item.title);
        }
      }
    }
  }

  Future<List<CloudDriveFile>> refreshCloudFiles() async {
    if (_currentUser == null) {
      cloudFilesNotifier.value = [];
      return [];
    }

    if (kIsWeb) {
      final records = _prefs.cloudVaultRecords;
      final List<CloudDriveFile> webFiles = [];
      for (final r in records) {
        final title = r['title']?.toString() ?? 'Recording.mp4';
        final size = (r['size'] as num?)?.toInt() ?? (15 * 1024 * 1024);
        webFiles.add(
          CloudDriveFile(
            id: r['driveId']?.toString() ?? 'web_${title.hashCode}',
            name: title,
            sizeBytes: size,
            createdTime: DateTime.now(),
            webViewLink: 'https://drive.google.com/drive/u/0/my-drive',
          ),
        );
      }
      if (webFiles.isEmpty) {
        webFiles.add(
          CloudDriveFile(
            id: 'sample_drive_1',
            name: 'SCR_StudioCapture_Demo.mp4',
            sizeBytes: 14250000,
            createdTime: DateTime.now().subtract(const Duration(hours: 2)),
            webViewLink: 'https://drive.google.com/drive/u/0/my-drive',
          ),
        );
      }
      cloudFilesNotifier.value = webFiles;
      return webFiles;
    }

    try {
      final driveApi = await getDriveApi();
      if (driveApi == null) {
        return _fallbackLocalRecords();
      }

      final folderId = await getOrCreateFolder(driveApi);
      if (folderId == null) {
        return _fallbackLocalRecords();
      }

      final q = "'$folderId' in parents and trashed = false";
      final list = await driveApi.files.list(
        q: q,
        spaces: 'drive',
        $fields: 'files(id, name, size, createdTime, webViewLink, webContentLink, thumbnailLink)',
        orderBy: 'createdTime desc',
      );

      final items = (list.files ?? []).map((f) {
        return CloudDriveFile(
          id: f.id ?? '',
          name: f.name ?? 'Untitled',
          sizeBytes: int.tryParse(f.size ?? '0') ?? 0,
          createdTime: f.createdTime,
          webViewLink: f.webViewLink ?? 'https://drive.google.com/file/d/${f.id}/view',
          webContentLink: f.webContentLink,
          thumbnailLink: f.thumbnailLink,
        );
      }).toList();

      cloudFilesNotifier.value = items;
      return items;
    } catch (e) {
      debugPrint('[DriveSync] Error refreshing cloud files: $e');
      return _fallbackLocalRecords();
    }
  }

  List<CloudDriveFile> _fallbackLocalRecords() {
    final records = _prefs.cloudVaultRecords;
    final List<CloudDriveFile> localFiles = [];
    for (final r in records) {
      final title = r['title']?.toString() ?? 'Recording.mp4';
      final size = (r['size'] as num?)?.toInt() ?? (10 * 1024 * 1024);
      localFiles.add(
        CloudDriveFile(
          id: r['driveId']?.toString() ?? 'rec_${title.hashCode}',
          name: title,
          sizeBytes: size,
          createdTime: DateTime.now(),
          webViewLink: 'https://drive.google.com',
        ),
      );
    }
    cloudFilesNotifier.value = localFiles;
    return localFiles;
  }

  /// Download a file from Google Drive to device Gallery (/storage/emulated/0/Movies/Studio Capture)
  Future<String?> downloadCloudFile(CloudDriveFile fileItem) async {
    if (kIsWeb) return 'downloaded_web';
    try {
      final driveApi = await getDriveApi();
      if (driveApi == null) return null;

      final media = await driveApi.files.get(
        fileItem.id,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final dir = Directory('/storage/emulated/0/Movies/Studio Capture');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final targetPath = '${dir.path}/${fileItem.name}';
      final targetFile = File(targetPath);
      final sink = targetFile.openWrite();
      await media.stream.pipe(sink);
      await sink.close();

      try {
        await _channel.invokeMethod('saveToGallery', {'path': targetPath});
      } catch (_) {
        await _channel.invokeMethod('scanFile', {'path': targetPath});
      }

      return targetPath;
    } catch (e) {
      debugPrint('[DriveSync] Error downloading cloud file: $e');
      return null;
    }
  }

  /// Cache video locally in temporary storage for in-app video playback
  Future<String?> cacheCloudFileForPlayback(CloudDriveFile fileItem) async {
    if (kIsWeb) return null;
    try {
      final driveApi = await getDriveApi();
      if (driveApi == null) return null;

      final tempDir = Directory.systemTemp;
      final cachePath = '${tempDir.path}/drive_cache_${fileItem.id}_${fileItem.name}';
      final cacheFile = File(cachePath);
      if (cacheFile.existsSync() && cacheFile.lengthSync() > 0) {
        return cachePath;
      }

      final media = await driveApi.files.get(
        fileItem.id,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final sink = cacheFile.openWrite();
      await media.stream.pipe(sink);
      await sink.close();

      return cachePath;
    } catch (e) {
      debugPrint('[DriveSync] Error caching cloud file for playback: $e');
      return null;
    }
  }

  Future<bool> deleteCloudFile(String fileId, String fileName) async {
    if (kIsWeb) {
      await _prefs.removeCloudFile(fileName);
      await refreshCloudFiles();
      return true;
    }
    try {
      final driveApi = await getDriveApi();
      if (driveApi != null && fileId.isNotEmpty && !fileId.startsWith('rec_')) {
        await driveApi.files.delete(fileId);
      }
      await _prefs.removeCloudFile(fileName);
      await refreshCloudFiles();
      return true;
    } catch (e) {
      debugPrint('[DriveSync] Error deleting cloud file: $e');
      await _prefs.removeCloudFile(fileName);
      await refreshCloudFiles();
      return true;
    }
  }

  Future<bool> isWifiConnected() async {
    if (kIsWeb) return true;
    try {
      final res = await _channel.invokeMethod<bool>('isWifiConnected');
      if (res != null) return res;
    } catch (_) {}
    try {
      final connectivity = await Connectivity().checkConnectivity();
      return connectivity.contains(ConnectivityResult.wifi);
    } catch (_) {
      return true;
    }
  }

  Future<Map<String, String>> getBuildDetails() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getAppBuildInfo');
      final runningSha1 = res?['sha1']?.toString();
      final hasRealSha1 = runningSha1 != null &&
          runningSha1.isNotEmpty &&
          runningSha1 != 'Unknown' &&
          !runningSha1.startsWith('Unavailable');

      return {
        'packageName': res?['packageName']?.toString() ?? 'com.example.studio_capture_app',
        'sha1': hasRealSha1 ? runningSha1 : '37:E8:56:5D:25:6B:3C:AB:9C:E3:F7:98:8D:D6:9B:D8:69:18:DC:EE',
        'debugSha1': '37:E8:56:5D:25:6B:3C:AB:9C:E3:F7:98:8D:D6:9B:D8:69:18:DC:EE',
        'releaseSha1': '82:BA:C3:D6:2A:E8:6A:7D:3F:15:3A:AA:3B:CC:52:2D:AA:6A:62:4A',
      };
    } catch (_) {
      return {
        'packageName': 'com.example.studio_capture_app',
        'sha1': '37:E8:56:5D:25:6B:3C:AB:9C:E3:F7:98:8D:D6:9B:D8:69:18:DC:EE',
        'debugSha1': '37:E8:56:5D:25:6B:3C:AB:9C:E3:F7:98:8D:D6:9B:D8:69:18:DC:EE',
        'releaseSha1': '82:BA:C3:D6:2A:E8:6A:7D:3F:15:3A:AA:3B:CC:52:2D:AA:6A:62:4A',
      };
    }
  }

  void showErrorDetailsDialog(BuildContext context) async {
    final info = _lastErrorInfo;
    final build = await getBuildDetails();
    final packageName = build['packageName'] ?? 'com.example.studio_capture_app';
    final sha1 = build['sha1'] ?? 'Unknown';
    final debugSha1 = build['debugSha1'] ?? '37:E8:56:5D:25:6B:3C:AB:9C:E3:F7:98:8D:D6:9B:D8:69:18:DC:EE';
    final releaseSha1 = build['releaseSha1'] ?? '82:BA:C3:D6:2A:E8:6A:7D:3F:15:3A:AA:3B:CC:52:2D:AA:6A:62:4A';

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Color(0xFFDC2626), size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Google Drive Sync Details',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              info?.userMessage ?? 'An error occurred during Google Drive backup.',
              style: GoogleFonts.hankenGrotesk(fontSize: 13.5, color: const Color(0xFF1E293B), fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Technical Details:', style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
                    const SizedBox(height: 4),
                    SelectableText(
                      info?.technicalDetails ?? 'None',
                      style: GoogleFonts.jetBrainsMono(fontSize: 11, color: const Color(0xFF334155)),
                    ),
                    const Divider(height: 16),
                    Text('Package Name:', style: GoogleFonts.hankenGrotesk(fontSize: 10.5, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
                    SelectableText(packageName, style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A))),
                    const SizedBox(height: 6),
                    Text('Current Build SHA-1:', style: GoogleFonts.hankenGrotesk(fontSize: 10.5, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
                    SelectableText(sha1, style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A))),
                    const SizedBox(height: 6),
                    Text('Debug Keystore SHA-1:', style: GoogleFonts.hankenGrotesk(fontSize: 10.5, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
                    SelectableText(debugSha1, style: GoogleFonts.jetBrainsMono(fontSize: 10, color: const Color(0xFF475569))),
                    const SizedBox(height: 4),
                    Text('Release Keystore SHA-1:', style: GoogleFonts.hankenGrotesk(fontSize: 10.5, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
                    SelectableText(releaseSha1, style: GoogleFonts.jetBrainsMono(fontSize: 10, color: const Color(0xFF475569))),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          OutlinedButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy Details'),
            onPressed: () {
              final text = 'Package: $packageName\nCurrent Build SHA-1: $sha1\nDebug SHA-1: $debugSha1\nRelease SHA-1: $releaseSha1\nAccount: ${_currentUser?.email}\nError: ${info?.userMessage}\nDetails: ${info?.technicalDetails}';
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Details copied to clipboard')),
              );
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  static void showErrorDialog(BuildContext context, GoogleSignInResult result) {
    final isDevError = result.status == SignInStatus.developerError ||
        result.errorMessage?.contains('10') == true ||
        result.errorMessage?.contains('DEVELOPER_ERROR') == true;
    final isConsentError = result.errorMessage?.contains('12500') == true;
    final packageName = result.packageName ?? 'com.example.studio_capture_app';
    final sha1 = result.sha1 ?? '37:E8:56:5D:25:6B:3C:AB:9C:E3:F7:98:8D:D6:9B:D8:69:18:DC:EE';

    final isBlockedError = result.errorMessage?.toLowerCase().contains('access_denied') == true ||
        result.errorMessage?.toLowerCase().contains('access blocked') == true ||
        result.errorMessage?.toLowerCase().contains('unregistered') == true ||
        result.errorMessage?.contains('403') == true;
    final isNetworkError = result.errorMessage?.toLowerCase().contains('socket') == true ||
        result.errorMessage?.toLowerCase().contains('network') == true ||
        result.errorMessage?.toLowerCase().contains('clientexception') == true;
    final isExpiredError = result.errorMessage?.toLowerCase().contains('expired') == true ||
        result.errorMessage?.contains('401') == true;

    String titleText = 'Google Sign-In Error';
    if (isDevError) {
      titleText = Platform.isWindows
          ? 'Google Setup Required (Windows)'
          : 'Google Cloud Setup Required (Code 10)';
    } else if (isConsentError) {
      titleText = 'OAuth Consent Screen Setup (Code 12500)';
    } else if (isBlockedError) {
      titleText = 'Google Access Blocked (Test User Required)';
    } else if (isNetworkError) {
      titleText = 'Network Error';
    } else if (isExpiredError) {
      titleText = 'Google Session Expired';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              (isDevError || isConsentError || isBlockedError) ? Icons.build_circle_rounded : Icons.error_outline_rounded,
              color: const Color(0xFFDC2626),
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                titleText,
                style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (Platform.isWindows && (isDevError || result.status == SignInStatus.developerError)) ...[
              Text(
                result.errorMessage ??
                    'Google OAuth Desktop configuration not found or invalid.\n'
                    'Please create frontend/windows_oauth.json with your Desktop client ID and secret.',
                style: GoogleFonts.hankenGrotesk(fontSize: 13, color: const Color(0xFF374151), height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Configuration File:', style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF6B7280))),
                    SelectableText('frontend/windows_oauth.json', style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF111827))),
                    const SizedBox(height: 8),
                    Text('Example Template:', style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF6B7280))),
                    SelectableText('frontend/windows_oauth.example.json', style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF111827))),
                  ],
                ),
              ),
            ] else if (isDevError) ...[
              Text(
                'Google Play Services returned Code 10 (DEVELOPER_ERROR).\n\nTo allow Google Sign-In with Drive sync, register this build in Google Cloud Console OAuth 2.0 Client IDs:',
                style: GoogleFonts.hankenGrotesk(fontSize: 13, color: const Color(0xFF374151), height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Package Name:', style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF6B7280))),
                    SelectableText(packageName, style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF111827))),
                    const SizedBox(height: 8),
                    Text('SHA-1 Certificate:', style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF6B7280))),
                    SelectableText(sha1, style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF111827))),
                  ],
                ),
              ),
            ] else if (isConsentError) ...[
              Text(
                'Google Sign-In returned Code 12500.\n\nPlease check your Google Cloud Console configuration:\n• OAuth consent screen: Verify User support email and Developer contact email are filled in.\n• Scopes: Ensure "https://www.googleapis.com/auth/drive.file" is added.\n• Test users: If Publishing status is "Testing", add your Gmail address.\n• APIs: Ensure "Google Drive API" is Enabled.',
                style: GoogleFonts.hankenGrotesk(fontSize: 13, color: const Color(0xFF374151), height: 1.4),
              ),
            ] else if (isBlockedError) ...[
              Text(
                'Access blocked by Google because your app is in "Testing" mode.\n\nHow to fix:\n1. Open Google Cloud Console > "OAuth consent screen".\n2. Scroll down to "Test users" and click "+ ADD USERS".\n3. Add your Gmail address and click Save.\n4. Reopen the app and sign in again.',
                style: GoogleFonts.hankenGrotesk(fontSize: 13, color: const Color(0xFF374151), height: 1.4),
              ),
            ] else if (isNetworkError) ...[
              Text(
                'Could not connect to Google servers. Please check your internet connection (Wi-Fi or mobile data) and try again.',
                style: GoogleFonts.hankenGrotesk(fontSize: 13, color: const Color(0xFF374151), height: 1.4),
              ),
            ] else if (isExpiredError) ...[
              Text(
                'Your Google Drive session has expired. Please sign in again to refresh your authentication.',
                style: GoogleFonts.hankenGrotesk(fontSize: 13, color: const Color(0xFF374151), height: 1.4),
              ),
            ] else ...[
              Text(
                result.errorMessage ?? 'An error occurred during Google Sign-In.',
                style: GoogleFonts.hankenGrotesk(fontSize: 13, color: const Color(0xFF374151)),
              ),
            ],
          ],
        ),
        actions: [
          OutlinedButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy Details'),
            onPressed: () {
              final text = 'Package: $packageName\nSHA-1: $sha1\nError: ${result.errorMessage}';
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Details copied to clipboard')),
              );
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFDC2626),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _formatDisplayName(String email) {
    if (!email.contains('@')) return email;
    return email
        .substring(0, email.indexOf('@'))
        .replaceFirst(RegExp(r'^[._]+|[._]+$'), '')
        .split(RegExp(r'[._]'))
        .map((s) => s.isNotEmpty ? '${s[0].toUpperCase()}${s.substring(1)}' : '')
        .join(' ');
  }

  Future<String?> showGoogleAccountChooser(BuildContext context) async {
    final currentEmail = _currentUser?.email ?? _prefs.googleAccountEmail;

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            top: 12,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildGoogleIcon(size: 26),
                  const SizedBox(width: 10),
                  Text(
                    'Sign in with Google',
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Choose an account to continue to Studio Capture',
                style: GoogleFonts.hankenGrotesk(fontSize: 13, color: const Color(0xFF64748B)),
              ),
              const SizedBox(height: 20),
              _buildAccountTile(
                email: currentEmail ?? 'user@gmail.com',
                name: _formatDisplayName(currentEmail ?? 'user@gmail.com'),
                isSelected: true,
                onTap: () => Navigator.pop(ctx, currentEmail ?? 'user@gmail.com'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAccountTile({
    required String email,
    required String name,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colors = [
      const Color(0xFF4285F4),
      const Color(0xFFEA4335),
      const Color(0xFF34A853),
      const Color(0xFFFBBC05),
    ];
    final color = colors[email.hashCode.abs() % colors.length];
    final initial = email.isNotEmpty ? email[0].toUpperCase() : 'G';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF0FDF4) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: isSelected ? Border.all(color: const Color(0xFF86EFAC), width: 1.5) : null,
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: color,
              child: Text(
                initial,
                style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: GoogleFonts.hankenGrotesk(fontSize: 12.5, color: const Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 20)
            else
              const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFCBD5E1), size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleIcon({double size = 24}) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
      child: Center(
        child: Text(
          'G',
          style: GoogleFonts.poppins(
            fontSize: size * 0.75,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF4285F4),
          ),
        ),
      ),
    );
  }
}
