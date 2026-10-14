import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_models.dart';
import 'preferences_service.dart';
import 'recording_auth_service.dart';
import 'app_notification_service.dart';
import 'google_drive_backup_service.dart';

/// A service that manages screen recording using platform channels for Android
/// and screen_recorder for web/iOS fallback
class RecordingService {
  static final RecordingService _instance = RecordingService._internal();
  factory RecordingService() => _instance;
  RecordingService._internal() {
    _channel.setMethodCallHandler(_handlePlatformCall);
  }

  static const MethodChannel _channel = MethodChannel('screen_recording');

  static final ValueNotifier<Map<String, dynamic>> stateNotifier = ValueNotifier<Map<String, dynamic>>({});
  static final ValueNotifier<Map<String, dynamic>?> navigationNotifier = ValueNotifier<Map<String, dynamic>?>(null);
  static final ValueNotifier<double> transcodeProgressNotifier = ValueNotifier<double>(0.0);

  Future<dynamic> _handlePlatformCall(MethodCall call) async {
    if (call.method == 'onRecordingStateChanged') {
      try {
        final map = Map<String, dynamic>.from(call.arguments as Map);
        _isRecording = map['isRecording'] as bool? ?? _isRecording;
        _isPaused = map['isPaused'] as bool? ?? _isPaused;
        _micMuted = map['isAudioMuted'] as bool? ?? _micMuted;
        _videoEnabled = map['isVideoEnabled'] as bool? ?? _videoEnabled;
        _showFacecam = map['showFacecam'] as bool? ?? _showFacecam;
        if (map['facecamShape'] != null) {
          _facecamShape = map['facecamShape'] as String;
        }
        if (map['lastRecordingPath'] != null) {
          _currentFilePath = map['lastRecordingPath'] as String;
          if (!_isRecording && _currentFilePath != null && _currentFilePath!.isNotEmpty) {
            unawaited(GoogleDriveBackupService().uploadRecording(_currentFilePath!));
          }
        }
        stateNotifier.value = Map<String, dynamic>.from(map);
      } catch (e) {
        debugPrint('Error handling onRecordingStateChanged: $e');
      }
    } else if (call.method == 'onNavigateRoute') {
      try {
        final map = Map<String, dynamic>.from(call.arguments as Map);
        navigationNotifier.value = map;
      } catch (e) {
        debugPrint('Error handling onNavigateRoute: $e');
      }
    } else if (call.method == 'onTranscodeProgress') {
      try {
        final map = Map<String, dynamic>.from(call.arguments as Map);
        final p = (map['progress'] as num?)?.toDouble() ?? 0.0;
        transcodeProgressNotifier.value = p;
      } catch (_) {}
    }
  }

  RecordingMode _currentMode = RecordingMode.screen;
  RecordingSettings? _lastSettings;
  bool _isRecording = false;
  bool _isPaused = false;
  DateTime? _startTime;
  String? _currentFilePath;
  Duration _elapsed = Duration.zero;
  Duration _pausedDuration = Duration.zero;
  DateTime? _pauseStartTime;

  // Dual audio and video stream states
  bool _micMuted = false;
  bool _systemAudioMuted = false;
  bool _noiseCancellation = true;
  bool _videoEnabled = true;
  bool _showFacecam = false;
  String _facecamShape = 'Square (PiP)';
  double _facecamNormalizedX = 0.68;
  double _facecamNormalizedY = 0.72;
  double _facecamSizeRatio = 0.28;
  String? _lastFacecamSnapshotPath;
  Uint8List? _lastFacecamSnapshotBytes;

  // In-memory list of completed recordings
  final List<MediaItem> _savedMediaItems = [];

  // Getters
  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  Duration get elapsed => _elapsed;
  RecordingMode get currentMode => _currentMode;
  RecordingSettings? get lastSettings => _lastSettings;
  String? get currentFilePath => _currentFilePath;
  bool get micMuted => _micMuted;
  bool get systemAudioMuted => _systemAudioMuted;
  bool get noiseCancellation => _noiseCancellation;
  bool get videoEnabled => _videoEnabled;
  bool get showFacecam => _showFacecam;
  String get facecamShape => _facecamShape;
  double get facecamNormalizedX => _facecamNormalizedX;
  double get facecamNormalizedY => _facecamNormalizedY;
  double get facecamSizeRatio => _facecamSizeRatio;
  String? get lastFacecamSnapshotPath => _lastFacecamSnapshotPath;
  Uint8List? get lastFacecamSnapshotBytes => _lastFacecamSnapshotBytes;
  List<MediaItem> get savedMediaItems => List.unmodifiable(_savedMediaItems);

  void updateFacecamPosition({required double xRatio, required double yRatio, required double sizeRatio}) {
    _facecamNormalizedX = xRatio;
    _facecamNormalizedY = yRatio;
    _facecamSizeRatio = sizeRatio;
  }

  void setFacecamSnapshot({String? path, Uint8List? bytes}) {
    if (path != null) _lastFacecamSnapshotPath = path;
    if (bytes != null) _lastFacecamSnapshotBytes = bytes;
  }

  void setMicMuted(bool muted) {
    _micMuted = muted;
    setAudioMuted(_micMuted && _systemAudioMuted);
  }

  void setSystemAudioMuted(bool muted) {
    _systemAudioMuted = muted;
    setAudioMuted(_micMuted && _systemAudioMuted);
  }

  void setNoiseCancellation(bool enabled) {
    _noiseCancellation = enabled;
  }

  void addSavedRecording(MediaItem item) {
    _savedMediaItems.insert(0, item);
  }

  void removeSavedRecording(String id) {
    _savedMediaItems.removeWhere((item) => item.id == id);
  }

  void deleteSavedItem(String identifier) {
    _savedMediaItems.removeWhere((item) => item.id == identifier || item.filePath == identifier || item.title == identifier);
    try {
      PreferencesService().removeCloudFile(identifier);
    } catch (_) {}
  }

  void clearSavedRecordings() {
    _savedMediaItems.clear();
  }

  void renameSavedItem(String identifier, String newTitle, {String? newFilePath}) {
    final idx = _savedMediaItems.indexWhere((item) => item.id == identifier || item.filePath == identifier);
    if (idx != -1) {
      final old = _savedMediaItems[idx];
      _savedMediaItems[idx] = MediaItem(
        id: old.id,
        title: newTitle,
        date: old.date,
        duration: old.duration,
        size: old.size,
        resolution: old.resolution,
        type: old.type,
        thumbnail: old.thumbnail,
        filePath: newFilePath ?? old.filePath,
        isVoiceScreen: old.isVoiceScreen,
        hasFacecam: old.hasFacecam,
        facecamShape: old.facecamShape,
      );
    }
  }

  /// Initialize permissions
  Future<bool> initialize({bool requireCamera = false}) async {
    if (kIsWeb) {
      final micStatus = await Permission.microphone.request();
      return micStatus.isGranted;
    }
    if (Platform.isWindows) {
      return true;
    }

    final permissions = [
      Permission.microphone,
      Permission.storage,
      Permission.manageExternalStorage,
    ];
    if (requireCamera) {
      permissions.add(Permission.camera);
    }

    final results = await permissions.request();
    return results.values.every((status) => status.isGranted);
  }

  /// Request screen recording permission (Android MediaProjection)
  Future<bool> requestPermission() async {
    if (kIsWeb || Platform.isWindows) return true;
    
    try {
      final result = await _channel.invokeMethod<bool>('requestPermission').timeout(const Duration(seconds: 10));
      return result ?? false;
    } catch (e) {
      throw Exception('Failed to request permission: $e');
    }
  }

  /// Get available monitors and application windows on Windows Desktop
  Future<List<Map<String, dynamic>>> getSources() async {
    if (!Platform.isWindows) return [];
    try {
      final list = await _channel.invokeMethod<List>('getSources').timeout(const Duration(seconds: 5));
      if (list != null) {
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('getSources error: $e');
    }
    return [];
  }

  /// Start recording
  Future<String?> startRecording({
    required RecordingSettings settings,
    required bool enableAudio,
    required bool enableVideo,
  }) async {
    _currentMode = settings.mode;
    _lastSettings = settings;
    _micMuted = false;
    _systemAudioMuted = false;
    _videoEnabled = enableVideo;
    _noiseCancellation = settings.mode == RecordingMode.voiceScreen;
    _showFacecam = settings.showFacecam;
    _facecamShape = settings.facecamShape;

    try {
      final isFacecam = settings.showFacecam;
      if (!kIsWeb && !Platform.isWindows && isFacecam) {
        final camStatus = await Permission.camera.status;
        if (!camStatus.isGranted) {
          final requested = await Permission.camera.request();
          if (!requested.isGranted) {
            debugPrint('Camera permission denied for Facecam mode');
          }
        }
      }

      final hasPermission = await _checkPermissions();
      if (!hasPermission) {
        final granted = await requestPermission();
        if (!granted) {
          throw Exception('Required permissions not granted. Please grant screen recording permission in the system dialog.');
        }
      }

      final config = settings.toMap();
      config['enableAudio'] = enableAudio;
      config['enableVideo'] = enableVideo;
      // Inject live preference values so Kotlin can act on them at start time
      config['hideSensitiveContent'] = PreferencesService().hideSensitiveContent;
      config['floatingNotification'] = PreferencesService().floatingNotification;
      config['vibrationFeedback'] = PreferencesService().vibrationFeedback;
      config['lowStorageWarning'] = PreferencesService().lowStorageWarning;
      config['shakeToStop'] = settings.shakeToStop || PreferencesService().shakeToStop;
      config['showTouches'] = PreferencesService().showTouches;
      config['floatingBubble'] = PreferencesService().floatingWidget;

      if (kIsWeb) {
        // Web recording mock
        _isRecording = true;
        _isPaused = false;
        _startTime = DateTime.now();
        _elapsed = Duration.zero;
        AppNotificationService.playStartChime();
        return 'mock_recording_started';
      } else {
        // Native recording via platform channel
        final result = await _channel.invokeMethod<bool>('startRecording', config).timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException('Starting capture timed out after 10 seconds. Please check display/encoder settings and retry.'),
        );
        if (result == true) {
          _isRecording = true;
          _isPaused = false;
          _startTime = DateTime.now();
          _elapsed = Duration.zero;
          AppNotificationService.playStartChime();
          return 'recording_started';
        } else {
          throw Exception('Failed to start recording. The screen recording permission may have been denied or encoder failed.');
        }
      }
    } catch (e) {
      throw Exception('Failed to start recording: $e');
    }
  }

  /// Pause recording
  Future<void> pauseRecording() async {
    if (!_isRecording || _isPaused) return;
    
    try {
      if (!kIsWeb) {
        await _channel.invokeMethod('pauseRecording');
      }
      _isPaused = true;
      _pauseStartTime = DateTime.now();
      AppNotificationService.onRecordingPaused();
    } catch (e) {
      throw Exception('Failed to pause recording: $e');
    }
  }

  /// Resume recording
  Future<void> resumeRecording() async {
    if (!_isRecording || !_isPaused) return;
    
    try {
      if (!kIsWeb) {
        await _channel.invokeMethod('resumeRecording');
      }
      _isPaused = false;
      if (_pauseStartTime != null) {
        _pausedDuration += DateTime.now().difference(_pauseStartTime!);
        _pauseStartTime = null;
      }
      AppNotificationService.onRecordingResumed();
    } catch (e) {
      throw Exception('Failed to resume recording: $e');
    }
  }

  /// Toggle video capture
  Future<void> setVideoEnabled(bool enabled) async {
    _videoEnabled = enabled;
    if (!_isRecording) return;
    try {
      if (!kIsWeb) {
        await _channel.invokeMethod('setVideoEnabled', enabled);
      }
    } catch (e) {
      throw Exception('Failed to toggle video: $e');
    }
  }

  /// Toggle audio capture
  Future<void> setAudioMuted(bool muted) async {
    if (!_isRecording) return;
    try {
      if (!kIsWeb) {
        await _channel.invokeMethod('setAudioMuted', muted);
      }
    } catch (e) {
      throw Exception('Failed to mute audio: $e');
    }
  }

  /// Toggle facecam live overlay
  Future<void> setFacecamEnabled(bool enabled, {String? shape}) async {
    _showFacecam = enabled;
    if (shape != null) _facecamShape = shape;
    if (!_isRecording) return;
    try {
      if (!kIsWeb) {
        await _channel.invokeMethod('setFacecamEnabled', {
          'enabled': enabled,
          'shape': shape,
        });
      }
    } catch (e) {
      debugPrint('Failed to toggle facecam: $e');
    }
  }

  /// Stop recording and return file path
  Future<String?> stopRecording() async {
    if (!_isRecording) {
      RecordingAuthService.resetSessionAuth();
      return null;
    }

    try {
      final now = DateTime.now();
      final timeStamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      String filename = 'SCR_$timeStamp.mp4';
      if (_currentMode == RecordingMode.voiceScreen) {
        filename = 'VoiceScreen_${timeStamp}_DualAudio.mp4';
      } else if (_currentMode == RecordingMode.facecam) {
        filename = 'Facecam_${timeStamp}_PiP.mp4';
      } else if (_currentMode == RecordingMode.game) {
        filename = 'Gaming_${timeStamp}_120FPS.mp4';
      } else if (_currentMode == RecordingMode.gif) {
        filename = 'Clip_$timeStamp.gif';
      }

      String? path;
      if (kIsWeb) {
        path = filename;
      } else {
        path = await _channel.invokeMethod<String>('stopRecording');

        // ── File-finalization guard ─────────────────────────────────────────
        // The native side runs MediaRecorder.stop() + audio/video remux on the
        // calling thread before returning, but on some devices the OS flushes
        // the last bytes lazily.  Poll until the file size has been stable for
        // two consecutive 150 ms checks, confirming the mux is truly complete.
        if (path != null && path.isNotEmpty) {
          final finalFile = File(path);
          int lastSize = -1;
          for (int i = 0; i < 20; i++) {  // max 3 seconds
            await Future.delayed(const Duration(milliseconds: 150));
            if (!finalFile.existsSync()) continue;
            final currentSize = finalFile.statSync().size;
            if (currentSize > 0 && currentSize == lastSize) break;  // stable
            lastSize = currentSize;
          }
        }

        if ((path == null || !File(path).existsSync()) && Platform.isAndroid) {
          try {
            final extDirs = await getExternalStorageDirectories(type: StorageDirectory.movies);
            if (extDirs != null && extDirs.isNotEmpty) {
              final movieDir = extDirs.first;
              if (await movieDir.exists()) {
                // Only consider non-temp MP4 files
                final files = movieDir.listSync()
                    .where((f) {
                      final name = f.path.split(Platform.pathSeparator).last;
                      return f.path.endsWith('.mp4') &&
                          !name.startsWith('temp_');
                    })
                    .toList();
                if (files.isNotEmpty) {
                  files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
                  path = files.first.path;
                }
              }
            }
          } catch (_) {}
        }
        path ??= filename;
      }

      // Query real disk file properties
      final hasFacecam = _lastSettings != null
          ? _lastSettings!.showFacecam
          : (_currentMode == RecordingMode.facecam);
      final facecamShape = _lastSettings?.facecamShape ?? 'Circle Head';
      final seconds = _elapsed.inSeconds > 0 ? _elapsed.inSeconds : 1;
      final secH = (seconds ~/ 3600).toString().padLeft(2, '0');
      final secM = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
      final secS = (seconds % 60).toString().padLeft(2, '0');
      final durationString = secH != '00' ? '$secH:$secM:$secS' : '$secM:$secS';

      int realSize = 0;
      DateTime realTime = DateTime.now();
      String realFilename = filename;
      int durationMs = 0;
      String? realThumb;
      String res = _currentMode == RecordingMode.voiceScreen
          ? '${_lastSettings?.resolution ?? "1080p"} • Dual Track 48k'
          : hasFacecam
              ? '${_lastSettings?.resolution ?? "1080p"} • PiP $facecamShape'
              : '${_lastSettings?.resolution ?? "1080p"} ${_lastSettings?.fps ?? 60}FPS';

      if (path.isNotEmpty) {
        final diskFile = File(path);
        if (diskFile.existsSync()) {
          final stat = diskFile.statSync();
          realSize = stat.size;
          realTime = stat.modified;
          realFilename = path.split(Platform.pathSeparator).last;
        }

        if (_currentMode != RecordingMode.gif) {
          final meta = await getVideoMetadata(path);
          if (meta != null) {
            durationMs = (meta['durationMs'] as num?)?.toInt() ?? 0;
            final w = (meta['width'] as num?)?.toInt() ?? 0;
            final h = (meta['height'] as num?)?.toInt() ?? 0;
            if (w > 0 && h > 0) res = '${w}x$h';
            realThumb = meta['thumbnailPath'] as String?;
          }
        }
      }

      final dur = durationMs > 0
          ? '${(durationMs ~/ 60000).toString().padLeft(2, '0')}:${((durationMs % 60000) ~/ 1000).toString().padLeft(2, '0')}'
          : durationString;

      final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final dateStr = '${monthNames[realTime.month - 1]} ${realTime.day}, ${realTime.year}';

      final newItem = MediaItem(
        id: 'rec_${realTime.millisecondsSinceEpoch}',
        title: realFilename,
        type: _currentMode == RecordingMode.gif ? 'gif' : 'video',
        thumbnail: realThumb ?? '',
        duration: dur,
        resolution: res,
        date: dateStr,
        size: formatSize(realSize),
        filePath: path,
        isVoiceScreen: _currentMode == RecordingMode.voiceScreen,
        hasFacecam: hasFacecam,
        facecamShape: facecamShape,
        facecamNormalizedX: _facecamNormalizedX,
        facecamNormalizedY: _facecamNormalizedY,
        facecamSizeRatio: _facecamSizeRatio,
        facecamSnapshotPath: _lastFacecamSnapshotPath,
      );
      addSavedRecording(newItem);

      // Save every finished recording into the phone's public gallery (MediaStore, Movies/Studio Capture on Android)
      if (path.isNotEmpty && !kIsWeb && Platform.isAndroid) {
        try {
          await saveToGallery(path);
        } catch (e) {
          debugPrint('[RecordingService] Auto-save to gallery note: $e');
        }
        // Auto-sync new recording to Google Drive in background without blocking
        unawaited(GoogleDriveBackupService().uploadRecording(path, title: realFilename));
      }

      _isRecording = false;
      _isPaused = false;
      _startTime = null;
      _pauseStartTime = null;
      _pausedDuration = Duration.zero;
      _currentFilePath = path;
      AppNotificationService.playStopChime();
      RecordingAuthService.resetSessionAuth();
      return path;
    } catch (e) {
      throw Exception('Failed to stop recording: $e');
    }
  }

  /// Remove any items whose files are missing or orphaned
  void clearOrphanedMedia(Set<String> validFilePaths) {
    _savedMediaItems.removeWhere((item) {
      if (item.filePath == null) return true;
      if (!validFilePaths.contains(item.filePath)) return true;
      return !File(item.filePath!).existsSync();
    });
  }

  /// Update elapsed time (call periodically from UI)
  void updateElapsed() {
    if (_isRecording && _startTime != null) {
      if (!_isPaused) {
        _elapsed = DateTime.now().difference(_startTime!) - _pausedDuration;
      }
    }
  }

  /// Get recordings directory
  Future<Directory> getRecordingsDirectory() async {
    if (kIsWeb) {
      return Directory('/tmp/recordings');
    }
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'] ?? '';
      final dir = Directory('$userProfile\\Videos\\Studio Capture');
      if (!dir.existsSync()) {
        try {
          dir.createSync(recursive: true);
        } catch (_) {}
      }
      return dir;
    }
    final customPath = PreferencesService().savePath;
    if (customPath.isNotEmpty) {
      final d = Directory(customPath);
      if (d.existsSync()) return d;
    }
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory('${appDir.path}/recordings');
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }
      return recordingsDir;
    } catch (_) {
      return Directory(customPath.isNotEmpty ? customPath : Directory.systemTemp.path);
    }
  }

  /// Get all recordings
  Future<List<FileSystemEntity>> getRecordings() async {
    if (kIsWeb) return [];
    final List<FileSystemEntity> allFiles = [];
    final Set<String> seenPaths = {};

    void addDirFiles(Directory d) {
      try {
        if (d.existsSync()) {
          final list = d.listSync();
          for (final f in list) {
            if (f is File) {
              final name = f.path.split(Platform.pathSeparator).last;
              // Skip hidden files and ALL temp files (including temp_vid_ / temp_aud_)
              if (name.startsWith('temp_') || name.startsWith('.')) continue;
              final lower = name.toLowerCase();
              if (lower.endsWith('.mp4') || lower.endsWith('.gif') || lower.endsWith('.png')) {
                if (seenPaths.add(f.path)) {
                  allFiles.add(f);
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    try {
      final customPath = PreferencesService().savePath;
      if (customPath.isNotEmpty) {
        addDirFiles(Directory(customPath));
      }
    } catch (_) {}

    try {
      final appDir = await getRecordingsDirectory();
      addDirFiles(appDir);
    } catch (_) {}

    if (Platform.isAndroid) {
      try {
        final extDirs = await getExternalStorageDirectories(type: StorageDirectory.movies);
        if (extDirs != null) {
          for (final d in extDirs) {
            addDirFiles(d);
          }
        }
      } catch (_) {}

      addDirFiles(Directory('/storage/emulated/0/Movies/ScreenRecordingApp'));
      addDirFiles(Directory('/storage/emulated/0/Movies/ConsolidatedRecorder'));
      addDirFiles(Directory('/storage/emulated/0/Movies'));
      addDirFiles(Directory('/storage/emulated/0/DCIM/Screenshots'));
    }

    try {
      final customPath = PreferencesService().savePath;
      if (customPath.isNotEmpty) {
        addDirFiles(Directory(customPath));
      }
    } catch (_) {}

    allFiles.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return allFiles;
  }

  /// Delete a recording
  Future<void> deleteRecording(String path) async {
    if (kIsWeb) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Format duration for display
  String formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// Format file size
  String formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<bool> _checkPermissions() async {
    if (kIsWeb || Platform.isWindows) {
      return true;
    }
    
    final micStatus = await Permission.microphone.status;
    return micStatus.isGranted;
  }

  /// Save a recording directly into the phone's native gallery / media store
  Future<bool> saveToGallery(String filePath) async {
    if (kIsWeb || Platform.isWindows) return true;
    try {
      final res = await _channel.invokeMethod<bool>('saveToGallery', {'filePath': filePath});
      return res ?? false;
    } catch (e) {
      debugPrint('Save to gallery error: $e');
      return false;
    }
  }

  /// Reveal file in Windows Explorer
  Future<bool> showInExplorer(String filePath) async {
    if (!Platform.isWindows) return false;
    try {
      final res = await _channel.invokeMethod<bool>('showInExplorer', {'path': filePath});
      return res ?? true;
    } catch (e) {
      debugPrint('Show in explorer error: $e');
      return false;
    }
  }

  /// Save an image/screenshot directly into the phone's native gallery / MediaStore
  Future<bool> saveImageToGallery(Uint8List bytes, {String? filename}) async {
    if (kIsWeb) return true;
    try {
      final res = await _channel.invokeMethod<bool>('saveImageToGallery', {
        'bytes': bytes,
        'filename': filename,
      });
      return res ?? false;
    } catch (e) {
      debugPrint('Save image to gallery error: $e');
      return false;
    }
  }

  /// Open Google Photos app or its Play Store page (or Windows Explorer on Windows)
  Future<bool> openGooglePhotos({String? filePath}) async {
    if (kIsWeb) {
      final url = Uri.parse('https://photos.google.com');
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    }
    if (Platform.isWindows) {
      final dir = await getRecordingsDirectory();
      final target = (filePath != null && File(filePath).existsSync()) ? filePath : dir.path;
      return await launchUrl(Uri.file(target));
    }
    try {
      final res = await _channel.invokeMethod<bool>('openGooglePhotos');
      if (res == true) return true;
    } catch (e) {
      debugPrint('openGooglePhotos channel error: $e');
    }
    try {
      final url = Uri.parse('https://play.google.com/store/apps/details?id=com.google.android.apps.photos');
      if (await canLaunchUrl(url)) {
        return await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('openGooglePhotos web fallback error: $e');
    }
    return false;
  }

  /// Open Android share sheet so the user can pick Google Drive and an account
  Future<void> backupToGoogleDrive(String filePath, {String? title}) async {
    try {
      final file = File(filePath);
      final filename = title ?? (filePath.split(Platform.pathSeparator).last);
      if (file.existsSync()) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(filePath, mimeType: 'video/mp4', name: filename)],
            subject: 'Back up to Google Drive',
            text: 'Back up $filename to Google Drive',
          ),
        );
      } else {
        await SharePlus.instance.share(
          ShareParams(
            subject: 'Back up to Google Drive',
            text: 'Back up $filename to Google Drive',
          ),
        );
      }
    } catch (e) {
      debugPrint('backupToGoogleDrive error: $e');
    }
  }

  /// Get real video metadata (duration, width, height, rotation)
  Future<Map<String, dynamic>?> getVideoMetadata(String path) async {
    if (kIsWeb) return null;
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getVideoMetadata', {
        'path': path,
      });
      return res;
    } catch (e) {
      debugPrint('Get video metadata error: $e');
      return null;
    }
  }

  /// Check current native recording status
  Future<Map<String, dynamic>?> getRecordingStatus() async {
    if (kIsWeb) return {'isRecording': _isRecording};
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getRecordingStatus');
      return res;
    } catch (_) {
      return null;
    }
  }

  /// Query real device storage capacity and available space
  Future<Map<String, dynamic>?> getDeviceStorageInfo() async {
    if (kIsWeb) return null;
    try {
      final res = await _channel.invokeMethod<dynamic>('getStorageInfo');
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return null;
    } catch (e) {
      debugPrint('getStorageInfo error: $e');
      return null;
    }
  }

  /// Request media scanner to index or update a file in Android Gallery / MediaStore
  Future<void> scanFile(String path) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('scanFile', {'path': path});
    } catch (_) {}
  }

  /// Trim an MP4 video from [startMs] to [endMs] and write output to [outputPath]
  Future<bool> trimVideo({
    required String inputPath,
    required String outputPath,
    required int startMs,
    required int endMs,
  }) async {
    if (kIsWeb) return false;
    try {
      final success = await _channel.invokeMethod<bool>('trimVideo', {
        'inputPath': inputPath,
        'outputPath': outputPath,
        'startMs': startMs,
        'endMs': endMs,
      });
      return success == true;
    } catch (e) {
      debugPrint('trimVideo error: $e');
      return false;
    }
  }

  /// Transcode an MP4 video to target preset resolution, bitrate, and frame rate
  Future<bool> transcodeVideo({
    required String inputPath,
    required String outputPath,
    required int targetWidth,
    required int targetHeight,
    required int targetBitrateBps,
    required int targetFps,
  }) async {
    if (kIsWeb) return true;
    try {
      transcodeProgressNotifier.value = 0.0;
      final success = await _channel.invokeMethod<bool>('transcodeVideo', {
        'inputPath': inputPath,
        'outputPath': outputPath,
        'targetWidth': targetWidth,
        'targetHeight': targetHeight,
        'targetBitrate': targetBitrateBps,
        'targetFps': targetFps,
      });
      return success == true;
    } catch (e) {
      debugPrint('transcodeVideo error: $e');
      return false;
    }
  }

  void dispose() {
    _isRecording = false;
    _isPaused = false;
    _startTime = null;
    _currentFilePath = null;
    _elapsed = Duration.zero;
  }
}