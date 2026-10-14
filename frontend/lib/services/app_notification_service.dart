import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'preferences_service.dart';
import 'recording_service.dart';
import 'recording_auth_service.dart';

/// Central service for all functional toggle effects.
///
/// Every method reads the relevant preference LIVE at call time — nothing is
/// cached at app startup — so toggling a switch takes effect immediately on
/// the very next event.
class AppNotificationService {
  AppNotificationService._();

  static const _channel = MethodChannel('screen_recording');

  // ── Vibration / Haptic Feedback ──────────────────────────────────────────
  static bool get canVibrate {
    final prefs = PreferencesService();
    return prefs.vibrationFeedback;
  }

  /// Light selection feedback (toggle switches, nav taps).
  static void lightImpact() {
    if (canVibrate) {
      HapticFeedback.lightImpact();
    }
  }

  /// Medium press feedback (button taps).
  static void mediumImpact() {
    if (canVibrate) {
      HapticFeedback.mediumImpact();
    }
  }

  /// Heavy impact (recording start/stop).
  static void heavyImpact() {
    if (canVibrate) {
      HapticFeedback.heavyImpact();
    }
  }

  /// Selection click feedback.
  static void selectionClick() {
    if (canVibrate) {
      HapticFeedback.selectionClick();
    }
  }

  /// Trigger real haptic vibration pulse with custom duration.
  static Future<void> triggerVibration({int durationMs = 120}) async {
    if (!canVibrate || Platform.isWindows) return;
    try {
      await _channel.invokeMethod('vibrate', {'duration': durationMs});
    } catch (_) {
      HapticFeedback.mediumImpact();
    }
  }

  // ── Audio Cues (Start, Stop, Countdown Tick) ─────────────────────────────

  static Future<void> _playNativeAudioCue(String type) async {
    try {
      await _channel.invokeMethod('playAudioCue', {'type': type});
    } catch (_) {
      SystemSound.play(SystemSoundType.click);
    }
  }

  static DateTime? _lastStartChimeTime;
  static DateTime? _lastStopChimeTime;

  @visibleForTesting
  static void resetDebounce() {
    _lastStartChimeTime = null;
    _lastStopChimeTime = null;
  }

  /// Play audio cue and haptic pulse exactly when recording STARTS.
  static void playStartChime() {
    final now = DateTime.now();
    if (_lastStartChimeTime != null && now.difference(_lastStartChimeTime!).inMilliseconds < 1000) {
      return;
    }
    _lastStartChimeTime = now;
    if (PreferencesService().startStopChime) {
      _playNativeAudioCue('start');
    }
    if (canVibrate) {
      triggerVibration(durationMs: 140);
    }
  }

  /// Play audio cue and haptic pulse exactly when recording STOPS.
  static void playStopChime() {
    final now = DateTime.now();
    if (_lastStopChimeTime != null && now.difference(_lastStopChimeTime!).inMilliseconds < 1000) {
      return;
    }
    _lastStopChimeTime = now;
    if (PreferencesService().startStopChime) {
      _playNativeAudioCue('stop');
    }
    if (canVibrate) {
      triggerVibration(durationMs: 180);
    }
  }

  /// Haptic pulse when recording is paused.
  static void onRecordingPaused() {
    if (canVibrate) {
      triggerVibration(durationMs: 90);
    }
  }

  /// Haptic pulse when recording is resumed.
  static void onRecordingResumed() {
    if (canVibrate) {
      triggerVibration(durationMs: 90);
    }
  }

  /// Play for each countdown tick (3, 2, 1). Respects countdownSound & vibrationFeedback prefs.
  static void playCountdownTick() {
    if (PreferencesService().countdownSound) {
      _playNativeAudioCue('tick');
    }
    if (canVibrate) {
      triggerVibration(durationMs: 50);
    }
  }

  // ── Low Storage Warning ──────────────────────────────────────────────────

  static Future<int> _getFreeStorageBytes() async {
    try {
      final result = await _channel.invokeMethod<Map>('getStorageInfo');
      return (result?['availableDeviceBytes'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Shows an AlertDialog when free storage < [thresholdBytes] (default 1 GB).
  /// No-op when lowStorageWarning pref is OFF. Returns true if warning shown.
  static Future<bool> checkAndWarnLowStorage(
    BuildContext context, {
    int thresholdBytes = 1024 * 1024 * 1024,
  }) async {
    if (!PreferencesService().lowStorageWarning) return false;
    final freeBytes = await _getFreeStorageBytes();
    if (freeBytes <= 0 || freeBytes >= thresholdBytes) return false;
    if (!context.mounted) return true;
    final freeMb = (freeBytes / (1024 * 1024)).toStringAsFixed(0);
    logDiagnostic('low_storage_warning_triggered', data: {'freeMb': freeMb});
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B)),
            SizedBox(width: 8),
            Text('Low Storage Warning'),
          ],
        ),
        content: Text(
          'Only $freeMb MB of free space remaining on your device.\n\n'
          'Free up storage before recording to avoid running out of space during capture.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return true;
  }

  // ── Notification Permission & Settings ──────────────────────────────────
  static Future<bool> areNotificationsEnabled() async {
    if (kIsWeb) return true;
    try {
      final enabled = await _channel.invokeMethod<bool>('areNotificationsEnabled');
      return enabled ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> openNotificationSettings() async {
    if (kIsWeb) return true;
    try {
      final opened = await _channel.invokeMethod<bool>('openNotificationSettings');
      return opened ?? true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestNotificationPermission() async {
    if (kIsWeb) return true;
    try {
      final granted = await _channel.invokeMethod<bool>('requestNotificationPermission');
      return granted ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> showSystemNotification({
    int id = 1005,
    String channelId = 'channel_export_trim',
    required String title,
    required String message,
    int? progress,
    int? maxProgress,
    bool ongoing = false,
    String? filePath,
  }) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('showSystemNotification', {
        'id': id,
        'channelId': channelId,
        'title': title,
        'message': message,
        'progress': progress,
        'maxProgress': maxProgress ?? 100,
        'ongoing': ongoing,
        'filePath': filePath,
      });
    } catch (_) {}
  }

  static Future<void> cancelNotification(int id) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('cancelNotification', {'id': id});
    } catch (_) {}
  }

  // ── Export / Trim Complete Notification ──────────────────────────────────

  /// Shows ongoing progress notification while a trim/export is in progress.
  static void notifyExportProgress({
    required String title,
    required int progress,
  }) {
    if (!PreferencesService().exportTrimComplete) return;
    showSystemNotification(
      id: 1004,
      channelId: 'channel_export_trim',
      title: title,
      message: 'Processing video ($progress%)',
      progress: progress,
      ongoing: true,
    );
  }

  /// Show an in-app Snackbar and system notification when a trim/export operation finishes.
  /// No-op when exportTrimComplete pref is OFF.
  static void notifyExportComplete(
    BuildContext? context, {
    String? label,
    String? filePath,
    bool isTrim = false,
  }) {
    if (!PreferencesService().exportTrimComplete) return;

    // Dismiss progress notification
    cancelNotification(1004);

    final title = isTrim ? 'Trim complete' : 'Export complete';
    final msg = label ?? (isTrim ? 'Video trimmed and saved. Tap to view.' : 'Export finished. Tap to view.');

    // Send native system notification on channel_export_trim with tap action
    showSystemNotification(
      id: 1005,
      channelId: 'channel_export_trim',
      title: title,
      message: msg,
      filePath: filePath,
    );

    if (context != null && context.mounted) {
      logDiagnostic('export_trim_complete_notified', data: {'label': label});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label ?? '$title — video saved to your library.'),
              ),
            ],
          ),
          duration: const Duration(seconds: 4),
          backgroundColor: const Color(0xFF111827),
        ),
      );
    }
  }

  // ── Cloud Backup Notifications ───────────────────────────────────────────

  /// Show low-priority notification while uploading to Google Drive
  static Future<void> notifyCloudBackupProgress({
    required String fileName,
    required double progress,
  }) async {
    final notifsOn = await areNotificationsEnabled();
    if (!notifsOn) return;

    final pct = (progress * 100).toInt().clamp(0, 100);
    showSystemNotification(
      id: 1006,
      channelId: 'channel_cloud_backup',
      title: 'Uploading to Google Drive',
      message: '$fileName ($pct%)',
      progress: pct,
      ongoing: true,
    );
  }

  /// Show notification when backup finishes
  static Future<void> notifyCloudBackupComplete({
    required String fileName,
  }) async {
    final notifsOn = await areNotificationsEnabled();
    if (!notifsOn) return;

    cancelNotification(1006);
    showSystemNotification(
      id: 1007,
      channelId: 'channel_cloud_backup',
      title: 'Backed up to Google Drive',
      message: '$fileName saved to Cloud Vault',
    );
  }

  /// Show notification when backup fails
  static Future<void> notifyCloudBackupFailed({
    required String fileName,
    String? reason,
  }) async {
    final notifsOn = await areNotificationsEnabled();
    if (!notifsOn) return;

    cancelNotification(1006);
    showSystemNotification(
      id: 1008,
      channelId: 'channel_cloud_backup',
      title: 'Backup failed',
      message: 'Failed to upload $fileName. Tap to retry.',
    );
  }

  // ── Biometric Authentication ─────────────────────────────────────────────

  /// Authenticates with fingerprint / Face ID before starting a new recording.
  /// Returns true immediately if biometricLock pref is OFF or if already authenticated for this session.
  /// Gated so the biometric prompt triggers exactly ONCE per recording session.
  static Future<bool> authenticateForRecording(BuildContext context) async {
    if (Platform.isWindows) return true;
    if (!PreferencesService().biometricLock) return true;
    if (RecordingAuthService.isSessionAuthenticated) return true;

    try {
      final ok = await _channel.invokeMethod<bool>(
        'authenticateBiometric',
        {'reason': 'Authenticate to start recording'},
      );
      final success = ok ?? false;
      logDiagnostic('biometric_auth_result', data: {'success': success, 'context': 'start_recording'});
      if (success) {
        RecordingAuthService.markSessionAuthenticated();
      }
      return success;
    } on PlatformException catch (e) {
      logDiagnostic('biometric_auth_error', data: {'code': e.code, 'message': e.message});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Biometric authentication unavailable.'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
      return false;
    } catch (e) {
      logDiagnostic('biometric_auth_exception', data: {'error': e.toString()});
      return false;
    }
  }

  /// Authenticates with fingerprint / Face ID before showing the Recordings
  /// library. Returns true immediately when biometricLock pref is OFF.
  static Future<bool> authenticateForLibraryAccess(BuildContext context) async {
    if (!PreferencesService().biometricLock) return true;
    try {
      final ok = await _channel.invokeMethod<bool>(
        'authenticateBiometric',
        {'reason': 'Unlock your saved recordings'},
      );
      final success = ok ?? false;
      logDiagnostic('biometric_auth_result', data: {'success': success});
      return success;
    } on PlatformException catch (e) {
      logDiagnostic('biometric_auth_error', data: {'code': e.code, 'message': e.message});
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Biometric Unavailable'),
            content: Text(
              e.message ??
                  'Fingerprint / Face ID not enrolled on this device. '
                  'Set up biometrics in your device Settings, or '
                  'disable App Lock in Privacy & Security.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return false;
    } catch (e) {
      logDiagnostic('biometric_auth_exception', data: {'error': e.toString()});
      return false;
    }
  }

  // ── Anonymous Diagnostics ────────────────────────────────────────────────

  /// Log an anonymous event. No-op when anonymousDiagnostics pref is OFF.
  static void logDiagnostic(String event, {Map<String, dynamic>? data}) {
    if (!PreferencesService().anonymousDiagnostics) return;
    final timestamp = DateTime.now().toIso8601String();
    debugPrint('[Anonymous Diagnostics $timestamp] $event ${data ?? ''}');
  }

  // ── Auto-Delete Old Recordings ───────────────────────────────────────────

  /// Delete recordings older than [autoDeleteDays] days from disk + library.
  /// Call this at app launch or on setting toggle. No-op when autoDeleteOldVideos pref is OFF.
  static Future<int> runAutoDeleteIfEnabled() async {
    final prefs = PreferencesService();
    if (!prefs.autoDeleteOldVideos) return 0;

    final cutoff = DateTime.now().subtract(Duration(days: prefs.autoDeleteDays));
    int deletedCount = 0;

    try {
      // 1. Clean disk files
      final files = await RecordingService().getRecordings();
      for (final f in files) {
        try {
          final stat = f.statSync();
          if (stat.modified.isBefore(cutoff)) {
            final path = f.path;
            await f.delete();
            RecordingService().deleteSavedItem(path);
            await RecordingService().scanFile(path);
            await prefs.removeCloudFile(path);
            deletedCount++;
          }
        } catch (_) {}
      }

      // 2. Clean in-memory savedMediaItems
      final items = List.from(RecordingService().savedMediaItems);
      for (final item in items) {
        try {
          final path = item.filePath as String?;
          if (path != null && path.isNotEmpty) {
            final f = File(path);
            if (await f.exists()) {
              final stat = await f.stat();
              if (stat.modified.isBefore(cutoff)) {
                await f.delete();
                RecordingService().deleteSavedItem(item.id);
                await RecordingService().scanFile(path);
                await prefs.removeCloudFile(path);
                deletedCount++;
              }
            } else {
              RecordingService().deleteSavedItem(item.id);
              await prefs.removeCloudFile(path);
            }
          }
        } catch (_) {}
      }

      logDiagnostic('auto_delete_executed', data: {
        'thresholdDays': prefs.autoDeleteDays,
        'purgedFiles': deletedCount,
      });
    } catch (e) {
      logDiagnostic('auto_delete_failed', data: {'error': e.toString()});
    }

    return deletedCount;
  }
}
