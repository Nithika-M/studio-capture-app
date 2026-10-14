import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/recording_service.dart';
import '../services/theme_service.dart';
import '../services/preferences_service.dart';
import '../services/app_notification_service.dart';

// ==========================================
// 1. NOTIFICATIONS SCREEN
// ==========================================
class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() => _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState extends State<NotificationsSettingsScreen> with WidgetsBindingObserver {
  final _prefs = PreferencesService();

  bool _startStopAlerts = true;
  bool _countdownSound = true;
  bool _vibrationFeedback = true;
  bool _storageWarning = true;
  bool _exportFinished = true;
  bool _floatingNotification = true;
  bool _notificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadState();
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
      _loadState();
    }
  }

  void _loadState() {
    setState(() {
      _startStopAlerts = _prefs.startStopChime;
      _countdownSound = _prefs.countdownSound;
      _vibrationFeedback = _prefs.vibrationFeedback;
      _storageWarning = _prefs.lowStorageWarning;
      _exportFinished = _prefs.exportTrimComplete;
      _floatingNotification = _prefs.floatingNotification;
    });
  }

  Future<void> _checkPermission() async {
    final enabled = await AppNotificationService.areNotificationsEnabled();
    if (mounted) {
      setState(() => _notificationsEnabled = enabled);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        title: Text('Notifications', style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: colors.textPrimary)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_notificationsEnabled) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.isDark ? const Color(0xFF3B1515) : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.notifications_off_rounded, color: Color(0xFFDC2626), size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Notifications are turned off for Studio Capture',
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: colors.isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ongoing recording controls, background timer, trim alerts, and storage warnings require system notification permission.',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 13,
                      color: colors.isDark ? const Color(0xFFF87171) : const Color(0xFFB91C1C),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.settings_outlined, size: 18),
                      label: Text(
                        'Open system settings',
                        style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      onPressed: () => AppNotificationService.openNotificationSettings(),
                    ),
                  ),
                ],
              ),
            ),
          ],
          _buildSectionHeader('Recording Alerts', colors),
          _buildCard([
            _buildSwitchTile('Start & Stop Chime', 'Play audio cue when recording begins or ends', _startStopAlerts, (v) {
              setState(() => _startStopAlerts = v);
              _prefs.setStartStopChime(v);
              if (v) AppNotificationService.playStartChime();
            }, colors),
            _buildDivider(colors),
            _buildSwitchTile('Countdown Sound', 'Audible tick during the 3-second pre-recording countdown', _countdownSound, (v) {
              setState(() => _countdownSound = v);
              _prefs.setCountdownSound(v);
              if (v) AppNotificationService.playCountdownTick();
            }, colors),
            if (!Platform.isWindows) ...[
              _buildDivider(colors),
              _buildSwitchTile('Vibration Feedback', 'Haptic pulse on start, pause, resume, and stop actions', _vibrationFeedback, (v) {
                setState(() => _vibrationFeedback = v);
                _prefs.setVibrationFeedback(v);
                if (v) AppNotificationService.triggerVibration();
              }, colors),
            ],
          ], colors),
          const SizedBox(height: 24),
          _buildSectionHeader('System & Storage', colors),
          _buildCard([
            _buildSwitchTile('Low Storage Warning', 'Alert when device free space drops below 1 GB', _storageWarning, (v) {
              setState(() => _storageWarning = v);
              _prefs.setLowStorageWarning(v);
              if (v) AppNotificationService.checkAndWarnLowStorage(context);
            }, colors),
            _buildDivider(colors),
            _buildSwitchTile('Export & Trim Complete', 'Notification when background video operations finish', _exportFinished, (v) {
              setState(() => _exportFinished = v);
              _prefs.setExportTrimComplete(v);
            }, colors),
            _buildDivider(colors),
            _buildSwitchTile(
              'Floating Controls Notification',
              'Show quick Pause & Stop buttons in the recording notification. When OFF, a minimal notification is shown as required by Android.',
              _floatingNotification,
              (v) {
                setState(() => _floatingNotification = v);
                _prefs.setFloatingNotification(v);
              },
              colors,
            ),
          ], colors),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700, color: colors.textSecondary),
      ),
    );
  }

  Widget _buildCard(List<Widget> children, AppColors colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Material(color: Colors.transparent, child: Column(children: children)),
    );
  }

  Widget _buildDivider(AppColors colors) {
    return Divider(height: 1, color: colors.borderLight, indent: 16, endIndent: 16);
  }

  Widget _buildSwitchTile(String title, String subtitle, bool value, ValueChanged<bool> onChanged, AppColors colors) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeColor: const Color(0xFFDC2626),
      title: Text(title, style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600, color: colors.textPrimary)),
      subtitle: Text(subtitle, style: GoogleFonts.hankenGrotesk(fontSize: 12, color: colors.textSecondary)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}

// ==========================================
// 2. PRIVACY & SECURITY SCREEN
// ==========================================
class PrivacySecurityScreen extends StatefulWidget {
  const PrivacySecurityScreen({super.key});

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  final _prefs = PreferencesService();
  static const _channel = MethodChannel('screen_recording');

  bool _hideSensitive = false;
  bool _biometricLock = false;
  bool _anonymousAnalytics = false;

  @override
  void initState() {
    super.initState();
    setState(() {
      _hideSensitive = _prefs.hideSensitiveContent;
      _biometricLock = _prefs.biometricLock;
      _anonymousAnalytics = _prefs.anonymousDiagnostics;
    });
  }

  Future<void> _setHideSensitive(bool value) async {
    setState(() => _hideSensitive = value);
    await _prefs.setHideSensitiveContent(value);
    // Apply FLAG_SECURE immediately to the activity window.
    if (!kIsWeb) {
      try {
        await _channel.invokeMethod('setHideSensitiveContent', value);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        title: Text('Privacy & Security', style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: colors.textPrimary)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCard([
            _buildSwitchTile(
              'Hide Sensitive Content',
              'Automatically mask password inputs and notifications during capture',
              _hideSensitive,
              (v) => _setHideSensitive(v),
              colors,
            ),
            Divider(height: 1, color: colors.borderLight, indent: 16, endIndent: 16),
            _buildSwitchTile(
              'App Lock / Biometrics',
              'Require fingerprint or face unlock before accessing saved recordings',
              _biometricLock,
              (v) {
                setState(() => _biometricLock = v);
                _prefs.setBiometricLock(v);
              },
              colors,
            ),
            Divider(height: 1, color: colors.borderLight, indent: 16, endIndent: 16),
            _buildSwitchTile(
              'Share Anonymous Diagnostics',
              'Send crash logs to help improve encoder stability (never includes recordings)',
              _anonymousAnalytics,
              (v) {
                setState(() => _anonymousAnalytics = v);
                _prefs.setAnonymousDiagnostics(v);
                AppNotificationService.logDiagnostic('diagnostics_toggled', data: {'enabled': v});
              },
              colors,
            ),
          ], colors),
          const SizedBox(height: 24),
          Text(
            'System Permissions',
            style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700, color: colors.textSecondary),
          ),
          const SizedBox(height: 8),
          _buildCard([
            _buildPermissionItem('Screen Capture', 'Enabled', Icons.screen_share, true, colors),
            Divider(height: 1, color: colors.borderLight, indent: 16, endIndent: 16),
            _buildPermissionItem('Microphone', 'Granted', Icons.mic, true, colors),
            Divider(height: 1, color: colors.borderLight, indent: 16, endIndent: 16),
            _buildPermissionItem('Camera (Facecam)', 'Granted', Icons.camera_alt, true, colors),
            Divider(height: 1, color: colors.borderLight, indent: 16, endIndent: 16),
            _buildPermissionItem('Storage Access', 'Granted', Icons.folder, true, colors),
          ], colors),
        ],
      ),
    );
  }

  Widget _buildCard(List<Widget> children, AppColors colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Material(color: Colors.transparent, child: Column(children: children)),
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, bool value, ValueChanged<bool> onChanged, AppColors colors) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeColor: const Color(0xFFDC2626),
      title: Text(title, style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600, color: colors.textPrimary)),
      subtitle: Text(subtitle, style: GoogleFonts.hankenGrotesk(fontSize: 12, color: colors.textSecondary)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildPermissionItem(String name, String status, IconData icon, bool granted, AppColors colors) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: colors.primaryBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(0xFFDC2626), size: 20),
      ),
      title: Text(name, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: colors.textPrimary)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: granted ? (colors.isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5)) : colors.primaryBg,
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Text(
          status,
          style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w600, color: granted ? const Color(0xFF10B981) : const Color(0xFFDC2626)),
        ),
      ),
    );
  }
}

// ==========================================
// 3. STORAGE & DATA SCREEN
// ==========================================
class StorageDataScreen extends StatefulWidget {
  const StorageDataScreen({super.key});

  @override
  State<StorageDataScreen> createState() => _StorageDataScreenState();
}

class _StorageDataScreenState extends State<StorageDataScreen> {
  int _recordingCount = 0;
  String _usedStorage = 'Calculating...';
  String _cacheSizeStr = '0 KB';
  int _totalBytes = 0;
  int _cacheBytes = 0;
  int _availableDeviceBytes = 0;
  int _totalDeviceBytes = 0;
  String? _availableFormatted;
  String? _totalFormatted;
  bool _autoDeleteOld = false;
  int _autoDeleteDays = 30;
  String _storagePath = '/Movies/Studio Capture';
  List<FileSystemEntity> _files = [];
  final Set<String> _selectedPaths = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final prefs = PreferencesService();
    _autoDeleteOld = prefs.autoDeleteOldVideos;
    _autoDeleteDays = prefs.autoDeleteDays;
    _storagePath = prefs.savePath.isNotEmpty ? prefs.savePath : '/Movies/Studio Capture';
    _loadStorageStats();
  }

  Future<void> _loadStorageStats() async {
    setState(() => _isLoading = true);
    if (kIsWeb) {
      setState(() {
        _recordingCount = 0;
        _usedStorage = '0 MB';
        _cacheSizeStr = '0 KB';
        _isLoading = false;
      });
      return;
    }

    try {
      final service = RecordingService();
      final diskFiles = await service.getRecordings();
      final Map<String, FileSystemEntity> uniqueFiles = {};

      String normalizePath(String path) {
        try {
          return File(path).resolveSymbolicLinksSync();
        } catch (_) {
          return path.replaceAll('/', Platform.pathSeparator);
        }
      }

      for (final f in diskFiles) {
        if (f is File && f.existsSync()) {
          uniqueFiles[normalizePath(f.path)] = f;
        }
      }
      for (final item in service.savedMediaItems) {
        if (item.filePath != null) {
          final f = File(item.filePath!);
          if (f.existsSync()) {
            uniqueFiles[normalizePath(f.path)] = f;
          }
        }
      }

      int totalBytes = 0;
      final List<FileSystemEntity> validFiles = uniqueFiles.values.toList();
      for (final f in validFiles) {
        try {
          totalBytes += (f as File).lengthSync();
        } catch (_) {}
      }

      // Calculate cache size
      int cacheBytes = 0;
      try {
        final tempDir = await getTemporaryDirectory();
        if (await tempDir.exists()) {
          for (final f in tempDir.listSync(recursive: true)) {
            if (f is File) {
              cacheBytes += f.lengthSync();
            }
          }
        }
      } catch (_) {}

      // Get real save path
      try {
        final dir = await service.getRecordingsDirectory();
        _storagePath = dir.path;
      } catch (_) {}

      // Get real device storage capacity and available space
      int availDeviceBytes = 0;
      int totalDevBytes = 0;
      String? availFormatted;
      String? totalFormatted;
      try {
        final storageMap = await service.getDeviceStorageInfo();
        if (storageMap != null) {
          availDeviceBytes = (storageMap['availableDeviceBytes'] as num?)?.toInt() ?? 0;
          totalDevBytes = (storageMap['totalDeviceBytes'] as num?)?.toInt() ?? 0;
          availFormatted = storageMap['availableFormatted'] as String?;
          totalFormatted = storageMap['totalFormatted'] as String?;
        }
      } catch (_) {}

      setState(() {
        final prefs = PreferencesService();
        _autoDeleteOld = prefs.autoDeleteOldVideos;
        _autoDeleteDays = prefs.autoDeleteDays;
        _storagePath = prefs.savePath.isNotEmpty ? prefs.savePath : _storagePath;
        _files = validFiles;
        _recordingCount = validFiles.length;
        _totalBytes = totalBytes;
        _cacheBytes = cacheBytes;
        _availableDeviceBytes = availDeviceBytes;
        _totalDeviceBytes = totalDevBytes;
        _availableFormatted = availFormatted;
        _totalFormatted = totalFormatted;
        _usedStorage = service.formatSize(totalBytes);
        _cacheSizeStr = service.formatSize(cacheBytes);
        _selectedPaths.removeWhere((p) => !_files.any((f) => f.path == p));
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _recordingCount = 0;
        _usedStorage = '0 MB';
        _cacheSizeStr = '0 KB';
        _isLoading = false;
      });
    }
  }

  Future<void> _clearCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        for (final f in tempDir.listSync(recursive: true)) {
          try {
            if (f is File) await f.delete();
          } catch (_) {}
        }
      }
      await _loadStorageStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Temporary thumbnail and export cache cleared successfully! Storage updated.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear cache: $e')),
        );
      }
    }
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedPaths.length == _files.length) {
        _selectedPaths.clear();
      } else {
        _selectedPaths.addAll(_files.map((f) => f.path));
      }
    });
  }

  void _confirmDeleteSelected() {
    if (_selectedPaths.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.appColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete ${_selectedPaths.length} Recording(s)?',
          style: TextStyle(fontWeight: FontWeight.w700, color: context.appColors.textPrimary),
        ),
        content: Text(
          'Are you sure you want to permanently delete these ${_selectedPaths.length} file(s)? This will free up storage immediately.',
          style: TextStyle(fontSize: 14, color: context.appColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: context.appColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final toDelete = List<String>.from(_selectedPaths);
              final prefs = PreferencesService();
              for (final p in toDelete) {
                try {
                  final f = File(p);
                  if (f.existsSync()) f.deleteSync();
                } catch (e) {
                  debugPrint('FILE DELETE ERROR: $e');
                }
                prefs.removeCloudFile(p);
                prefs.removeCloudFile(p.split(Platform.pathSeparator).last);
                RecordingService().deleteSavedItem(p);
                try {
                  RecordingService().scanFile(p);
                } catch (_) {}
              }
              _selectedPaths.clear();
              await _loadStorageStats();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Permanently deleted ${toDelete.length} recording(s). Storage updated.')),
                );
              }
            },
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final service = RecordingService();
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        title: Text('Storage & Data', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colors.textPrimary)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Storage Metrics',
            onPressed: _loadStorageStats,
          ),
        ],
      ),
      bottomNavigationBar: _selectedPaths.isNotEmpty
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  Text(
                    '${_selectedPaths.length} selected',
                    style: TextStyle(fontWeight: FontWeight.w600, color: colors.textPrimary),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.delete_forever_rounded, size: 18),
                    label: const Text('Delete Selected'),
                    onPressed: _confirmDeleteSelected,
                  ),
                ],
              ),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFDC2626)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Real-time Storage Overview Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFDC2626), Color(0xFF991B1B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFFDC2626).withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Recordings Storage', style: const TextStyle(fontSize: 13, color: Colors.white70)),
                          if (_availableDeviceBytes > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: Colors.black.withOpacity(0.25), borderRadius: BorderRadius.circular(6)),
                              child: Text(
                                'Available: ${_availableFormatted != null && _availableFormatted!.isNotEmpty ? _availableFormatted! : service.formatSize(_availableDeviceBytes)}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6EE7B7)),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(_usedStorage, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: Colors.white)),
                      const SizedBox(height: 12),
                      // Visual storage breakdown bar
                      if (_totalDeviceBytes > 0) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            height: 8,
                            child: Row(
                              children: [
                                // Recordings fraction
                                Expanded(
                                  flex: (_totalBytes * 1000 ~/ _totalDeviceBytes).clamp(1, 1000),
                                  child: Container(color: Colors.white),
                                ),
                                // Cache fraction
                                Expanded(
                                  flex: (_cacheBytes * 1000 ~/ _totalDeviceBytes).clamp(1, 1000),
                                  child: Container(color: const Color(0xFFFBBF24)),
                                ),
                                // Free device storage fraction
                                Expanded(
                                  flex: (_availableDeviceBytes * 1000 ~/ _totalDeviceBytes).clamp(1, 1000),
                                  child: Container(color: const Color(0xFF10B981)),
                                ),
                                // Other device used space
                                Expanded(
                                  flex: ((_totalDeviceBytes - _availableDeviceBytes - _totalBytes - _cacheBytes) * 1000 ~/ _totalDeviceBytes).clamp(1, 1000),
                                  child: Container(color: Colors.white.withOpacity(0.25)),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(9999)),
                            child: Text('$_recordingCount Saved Files', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(9999)),
                            child: Text('Cache: $_cacheSizeStr', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                          ),
                          if (_totalDeviceBytes > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(9999)),
                              child: Text('Device Total: ${_totalFormatted != null && _totalFormatted!.isNotEmpty ? _totalFormatted! : service.formatSize(_totalDeviceBytes)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _buildCard([
                  ListTile(
                    leading: const Icon(Icons.folder_outlined, color: Color(0xFFDC2626)),
                    title: Text('Save Location', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                    subtitle: Text(_storagePath, style: TextStyle(fontSize: 11, color: colors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                  Divider(height: 1, color: colors.borderLight, indent: 16, endIndent: 16),
                  SwitchListTile(
                    value: _autoDeleteOld,
                    onChanged: (v) async {
                      setState(() => _autoDeleteOld = v);
                      await PreferencesService().setAutoDeleteOldVideos(v);
                      if (v) {
                        final purged = await AppNotificationService.runAutoDeleteIfEnabled();
                        await _loadStorageStats();
                        if (mounted && purged > 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Auto-deleted $purged old recording(s) older than $_autoDeleteDays days.')),
                          );
                        }
                      }
                    },
                    activeColor: const Color(0xFFDC2626),
                    title: Text('Auto-Delete Old Videos', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                    subtitle: Text('Automatically purge recordings older than $_autoDeleteDays days', style: TextStyle(fontSize: 12, color: colors.textSecondary)),
                  ),
                  if (_autoDeleteOld) ...[
                    Divider(height: 1, color: colors.borderLight, indent: 16, endIndent: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Purge Rule / Threshold', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                          DropdownButton<int>(
                            value: _autoDeleteDays,
                            dropdownColor: colors.surface,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFDC2626)),
                            underline: const SizedBox(),
                            items: const [
                              DropdownMenuItem(value: 7, child: Text('Older than 7 Days')),
                              DropdownMenuItem(value: 14, child: Text('Older than 14 Days')),
                              DropdownMenuItem(value: 30, child: Text('Older than 30 Days')),
                              DropdownMenuItem(value: 60, child: Text('Older than 60 Days')),
                              DropdownMenuItem(value: 90, child: Text('Older than 90 Days')),
                            ],
                            onChanged: (days) async {
                              if (days != null) {
                                setState(() => _autoDeleteDays = days);
                                await PreferencesService().setAutoDeleteDays(days);
                                if (_autoDeleteOld) {
                                  final purged = await AppNotificationService.runAutoDeleteIfEnabled();
                                  await _loadStorageStats();
                                  if (mounted && purged > 0) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Auto-deleted $purged recording(s) older than $days days.')),
                                    );
                                  }
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                  Divider(height: 1, color: colors.borderLight, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.cleaning_services_outlined, color: Color(0xFFDC2626)),
                    title: Text('Clear Temp Cache ($_cacheSizeStr)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                    subtitle: Text('Frees up thumbnail and editing scratch space', style: TextStyle(fontSize: 12, color: colors.textSecondary)),
                    trailing: TextButton(
                      onPressed: _clearCache,
                      child: const Text('Clear', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFDC2626))),
                    ),
                  ),
                ], colors),

                const SizedBox(height: 24),

                // Multi-select Manage Files Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'MANAGE RECORDINGS ($_recordingCount)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textSecondary, letterSpacing: 0.5),
                    ),
                    if (_files.isNotEmpty)
                      TextButton.icon(
                        icon: Icon(_selectedPaths.length == _files.length ? Icons.deselect_rounded : Icons.select_all_rounded, size: 16),
                        label: Text(_selectedPaths.length == _files.length ? 'Deselect All' : 'Select All'),
                        onPressed: _toggleSelectAll,
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                if (_files.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.border),
                    ),
                    child: Center(
                      child: Text(
                        'No saved recordings on disk to manage.',
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    ),
                  )
                else
                  _buildCard(
                    _files.map((file) {
                      final name = file.path.split(Platform.pathSeparator).last;
                      final stat = file.statSync();
                      final sizeStr = RecordingService().formatSize(stat.size);
                      final isSelected = _selectedPaths.contains(file.path);

                      return CheckboxListTile(
                        value: isSelected,
                        activeColor: const Color(0xFFDC2626),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedPaths.add(file.path);
                            } else {
                              _selectedPaths.remove(file.path);
                            }
                          });
                        },
                        title: Text(
                          name,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '$sizeStr • ${stat.modified.month}/${stat.modified.day} ${stat.modified.hour}:${stat.modified.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(fontSize: 11, color: colors.textSecondary),
                        ),
                      );
                    }).toList(),
                    colors,
                  ),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _buildCard(List<Widget> children, AppColors colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Material(color: Colors.transparent, child: Column(children: children)),
    );
  }
}

// ── Contact Support Bottom Sheet & Email Handler ─────────────────────────────
Future<void> openSupportEmail(BuildContext context, {required String client}) async {
  const channelApp = MethodChannel('screen_recording_app/recording');
  const channelBase = MethodChannel('screen_recording');
  const to = 'contact@ispcorp.in';
  const subject = 'Studio Capture — Support Request';
  bool launched = false;
  try {
    final result = await channelApp.invokeMethod<bool>('openEmailClient', {
      'client': client,
      'to': to,
      'subject': subject,
    });
    launched = result == true;
  } catch (_) {
    launched = false;
  }

  if (!launched) {
    try {
      final result = await channelBase.invokeMethod<bool>('openEmailClient', {
        'client': client,
        'to': to,
        'subject': subject,
      });
      launched = result == true;
    } catch (_) {
      launched = false;
    }
  }

  if (!launched) {
    // Fallback: system mailto handler via url_launcher
    final uri = Uri.parse('mailto:$to?subject=${Uri.encodeComponent(subject)}');
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
  }

  if (!launched && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not open $client. Please email support directly at $to'),
      ),
    );
  }
}

Future<void> showContactSupportBottomSheet(BuildContext context, AppColors colors) {
  return showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Contact Support',
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose an email app to compose your message:',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 13,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              // Option 1: Gmail
              Material(
                color: colors.isDark
                    ? const Color(0xFF1E1F26)
                    : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Navigator.of(ctx, rootNavigator: true).pop();
                    openSupportEmail(context, client: 'gmail');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEA4335).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.mail_rounded,
                            color: Color(0xFFEA4335),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Gmail',
                                style: GoogleFonts.manrope(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Opens with your signed-in Gmail account',
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: colors.textTertiary),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Option 2: Outlook
              Material(
                color: colors.isDark
                    ? const Color(0xFF1E1F26)
                    : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Navigator.of(ctx, rootNavigator: true).pop();
                    openSupportEmail(context, client: 'outlook');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0078D4).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.mark_email_unread_rounded,
                            color: Color(0xFF0078D4),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Outlook',
                                style: GoogleFonts.manrope(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Opens with your signed-in Microsoft account',
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: colors.textTertiary),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

// ==========================================
// 4. HELP & SUPPORT SCREEN
// ==========================================
class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  final List<Map<String, String>> _faqs = [
    {
      'q': 'How do I capture internal game or app audio?',
      'a': 'Go to Recording Setup and set Audio Source to "Internal Audio" or "Internal + Microphone". Android 10+ allows direct digital audio capture without ambient noise.',
    },
    {
      'q': 'Why is my screen recording showing a black screen?',
      'a': 'Certain streaming apps (like Netflix or banking apps) enforce DRM protection (FLAG_SECURE) which forbids capture at the Android OS level. Regular apps and games record normally.',
    },
    {
      'q': 'How does Facecam Picture-in-Picture work?',
      'a': 'Toggle "Facecam" ON in settings. You can drag the camera overlay anywhere on the screen during capture or choose between Circle and Rectangle frames.',
    },
    {
      'q': 'How do I trim and cut my recorded video?',
      'a': 'Once your recording finishes, tap the "Trim" quick action on the completed screen or select any video from your library. Move the timeline handles and tap Export.',
    },
    {
      'q': 'Can I record at 120 FPS for gaming?',
      'a': 'Yes, if your device display and hardware encoder support high refresh rates, select 120 FPS in the Recording Setup screen.',
    },
  ];

  bool _isOpeningContact = false;

  void _openContactDialog(AppColors colors) async {
    if (_isOpeningContact) return;
    _isOpeningContact = true;
    try {
      await showContactSupportBottomSheet(context, colors);
    } finally {
      _isOpeningContact = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        title: Text('Help & Support', style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: colors.textPrimary)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Help Banner
          Material(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.border),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.02), blurRadius: 8)],
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: colors.primaryBg, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.support_agent_rounded, color: Color(0xFFDC2626), size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Need Direct Assistance?', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: colors.textPrimary)),
                        const SizedBox(height: 2),
                        Text('Get in touch with our engineering team', style: GoogleFonts.hankenGrotesk(fontSize: 12, color: colors.textSecondary)),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => _openContactDialog(colors),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                    child: const Text('Contact'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Frequently Asked Questions', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: colors.textPrimary)),
          const SizedBox(height: 12),
          ..._faqs.map((faq) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.border),
                ),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  iconColor: const Color(0xFFDC2626),
                  collapsedIconColor: colors.textTertiary,
                  title: Text(faq['q']!, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text(faq['a']!, style: GoogleFonts.hankenGrotesk(fontSize: 13, height: 1.4, color: colors.textSecondary)),
                    ),
                  ],
                ),
              ),
            ),
          )),
        ],
      ),
    );
  }
}

// ==========================================
// 5. ABOUT SCREEN
// ==========================================
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        title: Text('About', style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: colors.textPrimary)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 12),
          Center(
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFDC2626), Color(0xFF991B1B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFFDC2626).withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 8)),
                    ],
                  ),
                  child: const Icon(Icons.videocam_rounded, size: 44, color: Colors.white),
                ),
                const SizedBox(height: 16),
                Text('Studio Capture', style: GoogleFonts.manrope(fontSize: 22, fontWeight: FontWeight.w800, color: colors.textPrimary)),
                const SizedBox(height: 4),
                Text('v1.0.0', style: GoogleFonts.jetBrainsMono(fontSize: 13, color: colors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.system_update_rounded, color: Color(0xFFDC2626)),
                  title: Text('Check for Updates', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                  trailing: Icon(Icons.chevron_right, color: colors.textTertiary),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('You are on the latest version (1.0.0).')),
                    );
                  },
                ),
                Divider(height: 1, color: colors.borderLight, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.article_outlined, color: Color(0xFFDC2626)),
                  title: Text('Terms of Service', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                  trailing: Icon(Icons.chevron_right, color: colors.textTertiary),
                  onTap: () => launchUrl(
                    Uri.parse('https://ispcorp.in/privacy-policy'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                Divider(height: 1, color: colors.borderLight, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.policy_outlined, color: Color(0xFFDC2626)),
                  title: Text('Privacy Policy', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                  trailing: Icon(Icons.chevron_right, color: colors.textTertiary),
                  onTap: () => launchUrl(
                    Uri.parse('https://ispcorp.in/privacy-policy'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                Divider(height: 1, color: colors.borderLight, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.code_rounded, color: Color(0xFFDC2626)),
                  title: Text('Open Source Licenses', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                  trailing: Icon(Icons.chevron_right, color: colors.textTertiary),
                  onTap: () {
                    showLicensePage(
                      context: context,
                      applicationName: 'Studio Capture',
                      applicationVersion: '1.0.0',
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '© 2026 Studio Capture. All rights reserved.',
              style: GoogleFonts.hankenGrotesk(fontSize: 12, color: colors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 6. UNIFIED SUPPORT & LEGAL SCREEN
// ==========================================
class SupportLegalScreen extends StatefulWidget {
  const SupportLegalScreen({super.key});

  @override
  State<SupportLegalScreen> createState() => _SupportLegalScreenState();
}

class _SupportLegalScreenState extends State<SupportLegalScreen> {
  final List<Map<String, String>> _faqs = [
    {
      'q': 'How do I capture internal game or app audio?',
      'a': 'Go to Recording Setup and set Audio Source to "Internal Audio" or "Internal + Microphone". Android 10+ allows direct digital audio capture without ambient noise.',
    },
    {
      'q': 'Why is my screen recording showing a black screen?',
      'a': 'Certain streaming apps (like Netflix or banking apps) enforce DRM protection (FLAG_SECURE) which forbids capture at the Android OS level. Regular apps and games record normally.',
    },
    {
      'q': 'How does Facecam Picture-in-Picture work?',
      'a': 'Toggle "Facecam" ON in settings. You can drag the camera overlay anywhere on the screen during capture or choose between Circle and Rectangle frames.',
    },
    {
      'q': 'How do I trim and cut my recorded video?',
      'a': 'Once your recording finishes, tap the "Trim" quick action on the completed screen or select any video from your library. Move the timeline handles and tap Export.',
    },
    {
      'q': 'Can I record at 120 FPS for gaming?',
      'a': 'Yes, if your device display and hardware encoder support high refresh rates, select 120 FPS in the Recording Setup screen.',
    },
  ];

  bool _isOpeningContact = false;

  void _openContactDialog(BuildContext context, AppColors colors) async {
    if (_isOpeningContact) return;
    _isOpeningContact = true;
    try {
      await showContactSupportBottomSheet(context, colors);
    } finally {
      _isOpeningContact = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        title: Text('Support & Legal',
            style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(color: colors.border, height: 1),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── App identity card ─────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFDC2626), Color(0xFF991B1B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: const Color(0xFFDC2626).withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4)),
                    ],
                  ),
                  child: const Icon(Icons.videocam_rounded,
                      size: 32, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Studio Capture',
                          style: GoogleFonts.manrope(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: colors.textPrimary)),
                      const SizedBox(height: 2),
                      Text('v1.0.0',
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 12, color: colors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Contact Support ───────────────────────────────────────────────
          _buildSectionLabel('HELP & SUPPORT', colors),
          const SizedBox(height: 8),
          Material(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.border),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black
                          .withOpacity(colors.isDark ? 0.2 : 0.02),
                      blurRadius: 8)
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        color: colors.primaryBg,
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.support_agent_rounded,
                        color: Color(0xFFDC2626), size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Need Direct Assistance?',
                            style: GoogleFonts.manrope(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary)),
                        const SizedBox(height: 2),
                        Text('Get in touch with our engineering team',
                            style: GoogleFonts.hankenGrotesk(
                                fontSize: 12, color: colors.textSecondary)),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => _openContactDialog(context, colors),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                    ),
                    child: const Text('Contact'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── FAQ ───────────────────────────────────────────────────────────
          Text('Frequently Asked Questions',
              style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary)),
          const SizedBox(height: 10),
          ..._faqs.map((faq) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.border),
                    ),
                    child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  iconColor: const Color(0xFFDC2626),
                  collapsedIconColor: colors.textTertiary,
                  title: Text(faq['q']!,
                      style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: Text(faq['a']!,
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 12,
                              height: 1.5,
                              color: colors.textSecondary)),
                    ),
                  ],
                ),
              ),
            ),
          )),

          const SizedBox(height: 20),

          // ── Legal & About ─────────────────────────────────────────────────
          _buildSectionLabel('LEGAL & ABOUT', colors),
          const SizedBox(height: 8),
          Material(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                children: [
                ListTile(
                  leading: const Icon(Icons.system_update_rounded,
                      color: Color(0xFFDC2626)),
                  title: Text('Check for Updates',
                      style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary)),
                  trailing:
                      Icon(Icons.chevron_right, color: colors.textTertiary),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'You are on the latest version (1.0.0).')),
                    );
                  },
                ),
                Divider(
                    height: 1,
                    color: colors.borderLight,
                    indent: 16,
                    endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.article_outlined,
                      color: Color(0xFFDC2626)),
                  title: Text('Terms of Service',
                      style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary)),
                  trailing:
                      Icon(Icons.chevron_right, color: colors.textTertiary),
                  onTap: () => launchUrl(
                    Uri.parse('https://ispcorp.in/privacy-policy'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                Divider(
                    height: 1,
                    color: colors.borderLight,
                    indent: 16,
                    endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.policy_outlined,
                      color: Color(0xFFDC2626)),
                  title: Text('Privacy Policy',
                      style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary)),
                  trailing:
                      Icon(Icons.chevron_right, color: colors.textTertiary),
                  onTap: () => launchUrl(
                    Uri.parse('https://ispcorp.in/privacy-policy'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                Divider(
                    height: 1,
                    color: colors.borderLight,
                    indent: 16,
                    endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.code_rounded,
                      color: Color(0xFFDC2626)),
                  title: Text('Open Source Licenses',
                      style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary)),
                  trailing:
                      Icon(Icons.chevron_right, color: colors.textTertiary),
                  onTap: () {
                    showLicensePage(
                      context: context,
                      applicationName: 'Studio Capture',
                      applicationVersion: '1.0.0',
                    );
                  },
                ),
              ],
            ),
          ),
        ),

          const SizedBox(height: 24),
          Center(
            child: Text(
              '© 2026 Studio Capture. All rights reserved.',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 12, color: colors.textTertiary),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: GoogleFonts.hankenGrotesk(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: colors.textTertiary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
