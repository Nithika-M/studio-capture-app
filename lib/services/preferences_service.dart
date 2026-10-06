import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static final PreferencesService _instance = PreferencesService._internal();
  factory PreferencesService() => _instance;
  PreferencesService._internal();

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // --- Recording Defaults ---
  String get resolution => _prefs?.getString('pref_resolution') ?? '1080p';
  Future<bool> setResolution(String value) async => await _prefs?.setString('pref_resolution', value) ?? false;

  int get fps => _prefs?.getInt('pref_fps') ?? 60;
  Future<bool> setFps(int value) async => await _prefs?.setInt('pref_fps', value) ?? false;

  double get bitrate => _prefs?.getDouble('pref_bitrate') ?? 16.0;
  Future<bool> setBitrate(double value) async => await _prefs?.setDouble('pref_bitrate', value) ?? false;

  String get orientation => _prefs?.getString('pref_orientation') ?? 'Auto';
  Future<bool> setOrientation(String value) async => await _prefs?.setString('pref_orientation', value) ?? false;

  // --- Audio & Inputs ---
  String get audioSource => _prefs?.getString('pref_audio_source') ?? 'Internal + Mic';
  Future<bool> setAudioSource(String value) async => await _prefs?.setString('pref_audio_source', value) ?? false;

  String get audioQuality => _prefs?.getString('pref_audio_quality') ?? '48 kHz Stereo (AAC)';
  Future<bool> setAudioQuality(String value) async => await _prefs?.setString('pref_audio_quality', value) ?? false;

  bool get micGainBoost => _prefs?.getBool('pref_mic_gain_boost') ?? true;
  Future<bool> setMicGainBoost(bool value) async => await _prefs?.setBool('pref_mic_gain_boost', value) ?? false;

  bool get noiseSuppression => _prefs?.getBool('pref_noise_suppression') ?? true;
  Future<bool> setNoiseSuppression(bool value) async => await _prefs?.setBool('pref_noise_suppression', value) ?? false;

  // --- Facecam & Overlay ---
  bool get enableFacecam => _prefs?.getBool('pref_enable_facecam') ?? true;
  Future<bool> setEnableFacecam(bool value) async => await _prefs?.setBool('pref_enable_facecam', value) ?? false;

  String get facecamShape => _prefs?.getString('pref_facecam_shape') ?? 'Square (PiP)';
  Future<bool> setFacecamShape(String value) async => await _prefs?.setString('pref_facecam_shape', value) ?? false;

  bool get showTouches => _prefs?.getBool('pref_show_touches') ?? true;
  Future<bool> setShowTouches(bool value) async => await _prefs?.setBool('pref_show_touches', value) ?? false;

  bool get floatingWidget => _prefs?.getBool('pref_floating_widget') ?? true;
  Future<bool> setFloatingWidget(bool value) async => await _prefs?.setBool('pref_floating_widget', value) ?? false;

  bool get shakeToStop => _prefs?.getBool('pref_shake_to_stop') ?? false;
  Future<bool> setShakeToStop(bool value) async => await _prefs?.setBool('pref_shake_to_stop', value) ?? false;

  // --- Storage & Export ---
  String get savePath => _prefs?.getString('pref_save_path') ?? '/Movies/ConsolidatedRecorder';
  Future<bool> setSavePath(String value) async => await _prefs?.setString('pref_save_path', value) ?? false;

  bool get autoSync => _prefs?.getBool('pref_auto_sync') ?? false;
  Future<bool> setAutoSync(bool value) async => await _prefs?.setBool('pref_auto_sync', value) ?? false;

  bool get autoDeleteOldVideos => _prefs?.getBool('pref_auto_delete_old') ?? false;
  Future<bool> setAutoDeleteOldVideos(bool value) async => await _prefs?.setBool('pref_auto_delete_old', value) ?? false;

  int get autoDeleteDays => _prefs?.getInt('pref_auto_delete_days') ?? 30;
  Future<bool> setAutoDeleteDays(int value) async => await _prefs?.setInt('pref_auto_delete_days', value) ?? false;

  // --- Appearance ---
  String get themeMode => _prefs?.getString('pref_theme_mode') ?? 'light';
  Future<bool> setThemeMode(String value) async => await _prefs?.setString('pref_theme_mode', value) ?? false;

  bool get hapticFeedback => _prefs?.getBool('pref_haptic_feedback') ?? _prefs?.getBool('pref_vibration_feedback') ?? true;
  Future<bool> setHapticFeedback(bool value) async {
    await _prefs?.setBool('pref_vibration_feedback', value);
    return await _prefs?.setBool('pref_haptic_feedback', value) ?? false;
  }

  // --- Privacy & Security ---
  bool get hideSensitiveContent => _prefs?.getBool('pref_hide_sensitive') ?? false;
  Future<bool> setHideSensitiveContent(bool value) async => await _prefs?.setBool('pref_hide_sensitive', value) ?? false;

  bool get biometricLock => _prefs?.getBool('pref_biometric_lock') ?? false;
  Future<bool> setBiometricLock(bool value) async => await _prefs?.setBool('pref_biometric_lock', value) ?? false;

  bool get anonymousDiagnostics => _prefs?.getBool('pref_anon_diagnostics') ?? false;
  Future<bool> setAnonymousDiagnostics(bool value) async => await _prefs?.setBool('pref_anon_diagnostics', value) ?? false;

  // --- Notifications ---
  bool get startStopChime => _prefs?.getBool('pref_start_stop_chime') ?? true;
  Future<bool> setStartStopChime(bool value) async => await _prefs?.setBool('pref_start_stop_chime', value) ?? false;

  bool get countdownSound => _prefs?.getBool('pref_countdown_sound') ?? true;
  Future<bool> setCountdownSound(bool value) async => await _prefs?.setBool('pref_countdown_sound', value) ?? false;

  bool get vibrationFeedback => _prefs?.getBool('pref_vibration_feedback') ?? _prefs?.getBool('pref_haptic_feedback') ?? true;
  Future<bool> setVibrationFeedback(bool value) async {
    await _prefs?.setBool('pref_haptic_feedback', value);
    return await _prefs?.setBool('pref_vibration_feedback', value) ?? false;
  }

  bool get lowStorageWarning => _prefs?.getBool('pref_low_storage_warn') ?? true;
  Future<bool> setLowStorageWarning(bool value) async => await _prefs?.setBool('pref_low_storage_warn', value) ?? false;

  bool get exportTrimComplete => _prefs?.getBool('pref_export_trim_done') ?? true;
  Future<bool> setExportTrimComplete(bool value) async => await _prefs?.setBool('pref_export_trim_done', value) ?? false;

  bool get floatingNotification => _prefs?.getBool('pref_floating_notif') ?? true;
  Future<bool> setFloatingNotification(bool value) async => await _prefs?.setBool('pref_floating_notif', value) ?? false;

  // --- Profile / Display Name ---
  String get displayName => _prefs?.getString('pref_display_name') ?? '';
  Future<bool> setDisplayName(String value) async => await _prefs?.setString('pref_display_name', value) ?? false;

  // --- Cloud Vault Sync List ---
  List<String> get deletedCloudTitles => _prefs?.getStringList('pref_deleted_cloud_titles') ?? [];
  List<String> get syncedCloudTitles => _prefs?.getStringList('pref_synced_cloud_titles') ?? [];

  bool isCloudSynced(String identifier) {
    final filename = identifier.split(RegExp(r'[\\/]')).last.trim();
    if (deletedCloudTitles.contains(filename)) return false;
    return syncedCloudTitles.contains(filename);
  }

  bool isCloudDeleted(String identifier) {
    final filename = identifier.split(RegExp(r'[\\/]')).last.trim();
    return deletedCloudTitles.contains(filename);
  }

  Future<void> addSyncedCloudFile(Map<String, dynamic> fileData) async {
    final title = (fileData['title'] as String?)?.split(RegExp(r'[\\/]')).last.trim() ?? '';
    if (title.isEmpty) return;

    final delList = List<String>.from(deletedCloudTitles);
    if (delList.contains(title)) {
      delList.remove(title);
      await _prefs?.setStringList('pref_deleted_cloud_titles', delList);
    }

    final titles = List<String>.from(syncedCloudTitles);
    if (!titles.contains(title)) {
      titles.add(title);
      await _prefs?.setStringList('pref_synced_cloud_titles', titles);
    }

    final rawList = _prefs?.getStringList('pref_cloud_vault_records') ?? [];
    final records = List<String>.from(rawList);
    records.removeWhere((r) {
      try {
        final map = jsonDecode(r);
        return map['title'] == title;
      } catch (_) {
        return false;
      }
    });
    records.add(jsonEncode(fileData));
    await _prefs?.setStringList('pref_cloud_vault_records', records);
  }

  Future<void> removeCloudFile(String identifier) async {
    final filename = identifier.split(RegExp(r'[\\/]')).last.trim();
    if (filename.isEmpty) return;

    final delList = List<String>.from(deletedCloudTitles);
    if (!delList.contains(filename)) {
      delList.add(filename);
      await _prefs?.setStringList('pref_deleted_cloud_titles', delList);
    }

    final titles = List<String>.from(syncedCloudTitles);
    if (titles.contains(filename)) {
      titles.remove(filename);
      await _prefs?.setStringList('pref_synced_cloud_titles', titles);
    }

    final rawList = _prefs?.getStringList('pref_cloud_vault_records') ?? [];
    final records = List<String>.from(rawList);
    records.removeWhere((r) {
      try {
        final map = jsonDecode(r);
        return map['title'] == filename;
      } catch (_) {
        return false;
      }
    });
    await _prefs?.setStringList('pref_cloud_vault_records', records);
  }

  List<Map<String, dynamic>> get cloudVaultRecords {
    final rawList = _prefs?.getStringList('pref_cloud_vault_records') ?? [];
    final List<Map<String, dynamic>> result = [];
    final deleted = deletedCloudTitles;
    for (final r in rawList) {
      try {
        final map = Map<String, dynamic>.from(jsonDecode(r) as Map);
        if (!deleted.contains(map['title'])) {
          result.add(map);
        }
      } catch (_) {}
    }
    return result;
  }

  // Reset to Defaults
  Future<void> resetToDefaults() async {
    await _prefs?.remove('pref_resolution');
    await _prefs?.remove('pref_fps');
    await _prefs?.remove('pref_bitrate');
    await _prefs?.remove('pref_orientation');
    await _prefs?.remove('pref_audio_source');
    await _prefs?.remove('pref_audio_quality');
    await _prefs?.remove('pref_mic_gain_boost');
    await _prefs?.remove('pref_noise_suppression');
    await _prefs?.remove('pref_enable_facecam');
    await _prefs?.remove('pref_facecam_shape');
    await _prefs?.remove('pref_show_touches');
    await _prefs?.remove('pref_floating_widget');
    await _prefs?.remove('pref_shake_to_stop');
    await _prefs?.remove('pref_save_path');
    await _prefs?.remove('pref_auto_sync');
    await _prefs?.remove('pref_auto_delete_old');
    await _prefs?.remove('pref_auto_delete_days');
    await _prefs?.remove('pref_theme_mode');
    await _prefs?.remove('pref_haptic_feedback');
    await _prefs?.remove('pref_hide_sensitive');
    await _prefs?.remove('pref_biometric_lock');
    await _prefs?.remove('pref_anon_diagnostics');
    await _prefs?.remove('pref_start_stop_chime');
    await _prefs?.remove('pref_deleted_cloud_titles');
    await _prefs?.remove('pref_synced_cloud_titles');
    await _prefs?.remove('pref_cloud_vault_records');
    await _prefs?.remove('pref_countdown_sound');
    await _prefs?.remove('pref_vibration_feedback');
    await _prefs?.remove('pref_low_storage_warn');
    await _prefs?.remove('pref_export_trim_done');
    await _prefs?.remove('pref_floating_notif');
  }
}
