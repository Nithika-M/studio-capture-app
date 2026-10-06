import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import '../services/preferences_service.dart';
import '../services/app_notification_service.dart';
import '../services/theme_service.dart';
import '../services/cloud_vault_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';

class SettingsScreen extends StatefulWidget {
  final String? initialSection;

  const SettingsScreen({super.key, this.initialSection});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final PreferencesService _prefs = PreferencesService();
  final ScrollController _scrollController = ScrollController();

  AppColors get colors => context.appColors;

  // Recording defaults
  String _resolution = '1080p FHD';
  String _frameRate = '60 FPS (Constant)';
  String _bitrate = '16 Mbps (Auto)';
  String _orientation = 'Auto / Match Display';

  // Audio & inputs
  String _audioSource = 'Internal Audio + Mic';
  String _audioQuality = '48 kHz Stereo (AAC)';
  bool _micGainBoost = true;
  bool _noiseSuppression = true;

  // Facecam & overlay
  bool _enableFacecam = true;
  String _facecamShape = 'Circle (PiP)';
  bool _showTouches = false;
  bool _floatingWidget = true;
  bool _shakeToStop = false;

  // Storage & export
  String _savePath = '/Movies/ConsolidatedRecorder';
  bool _autoSync = false;
  bool _autoDelete = false;
  int _autoDeleteDays = 30;
  String _cacheSize = 'Calculating...';

  // Appearance
  String _theme = 'Light';
  bool _hapticFeedback = true;

  @override
  void initState() {
    super.initState();
    _loadAllSettings();
    _calculateCacheSize();
    if (widget.initialSection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSection(widget.initialSection!);
      });
    }
  }

  void _scrollToSection(String section) {
    double offset = 0.0;
    switch (section) {
      case 'Recording Defaults':
        offset = 0.0;
        break;
      case 'Audio & Inputs':
        offset = 290.0;
        break;
      case 'Facecam & Overlay':
        offset = 540.0;
        break;
      case 'Storage & Export':
        offset = 780.0;
        break;
      case 'Appearance':
        offset = 980.0;
        break;
      case 'About & Legal':
        offset = 1200.0;
        break;
    }
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        offset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _loadAllSettings() {
    setState(() {
      final res = _prefs.resolution;
      _resolution = res.contains('p') ? '$res HD' : res;
      _frameRate = '${_prefs.fps} FPS';
      _bitrate = '${_prefs.bitrate.toInt()} Mbps';
      _orientation = _prefs.orientation;

      _audioSource = _prefs.audioSource;
      _audioQuality = _prefs.audioQuality;
      _micGainBoost = _prefs.micGainBoost;
      _noiseSuppression = _prefs.noiseSuppression;

      _enableFacecam = _prefs.enableFacecam;
      _facecamShape = _prefs.facecamShape;
      _showTouches = _prefs.showTouches;
      _floatingWidget = _prefs.floatingWidget;
      _shakeToStop = _prefs.shakeToStop;

      _savePath = _prefs.savePath;
      _autoSync = _prefs.autoSync;
      _autoDelete = _prefs.autoDeleteOldVideos;
      _autoDeleteDays = _prefs.autoDeleteDays;

      final themeMode = _prefs.themeMode;
      if (themeMode == 'dark') {
        _theme = 'Dark';
      } else if (themeMode == 'system') {
        _theme = 'System';
      } else {
        _theme = 'Light';
      }

      _hapticFeedback = _prefs.hapticFeedback;
    });
  }

  void _calculateCacheSize() async {
    if (kIsWeb) {
      setState(() => _cacheSize = '14.2 MB');
      return;
    }
    try {
      final tempDir = await getTemporaryDirectory();
      int totalBytes = 0;
      if (await tempDir.exists()) {
        final list = tempDir.listSync(recursive: true, followLinks: false);
        for (final entity in list) {
          if (entity is File) {
            totalBytes += await entity.length();
          }
        }
      }
      setState(() {
        if (totalBytes < 1024 * 1024) {
          _cacheSize = '${(totalBytes / 1024).toStringAsFixed(1)} KB';
        } else {
          _cacheSize = '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
        }
      });
    } catch (_) {
      setState(() => _cacheSize = '0 B');
    }
  }

  void _clearCache() async {
    if (_hapticFeedback) HapticFeedback.lightImpact();
    if (!kIsWeb) {
      try {
        final tempDir = await getTemporaryDirectory();
        if (await tempDir.exists()) {
          final list = tempDir.listSync(recursive: true, followLinks: false);
          for (final entity in list) {
            try {
              if (entity is File) await entity.delete();
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
    setState(() => _cacheSize = '0 B');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Temporary preview cache cleared successfully!')),
      );
    }
  }

  void _showSelectionModal({
    required String title,
    required List<String> options,
    required String currentValue,
    required ValueChanged<String> onSelected,
  }) {
    if (_hapticFeedback) HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(title, style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: colors.textPrimary)),
                ),
                Divider(color: colors.border),
                ...options.map((opt) {
                  final isSelected = opt.toLowerCase().contains(currentValue.toLowerCase().split(' ').first);
                  return ListTile(
                    title: Text(opt, style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? const Color(0xFFDC2626) : colors.textPrimary)),
                    trailing: isSelected ? const Icon(Icons.check_circle, color: Color(0xFFDC2626)) : null,
                    onTap: () {
                      Navigator.pop(context);
                      onSelected(opt);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _selectSavePath() {
    if (_hapticFeedback) HapticFeedback.selectionClick();
    final controller = TextEditingController(text: _savePath);
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Default Save Path', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: colors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Specify directory for recorded media:', style: GoogleFonts.hankenGrotesk(fontSize: 13, color: colors.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: colors.surfaceSecondary,
                border: OutlineInputBorder(borderSide: BorderSide(color: colors.border)),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.border)),
                prefixIcon: Icon(Icons.folder, color: colors.textSecondary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text('Cancel', style: TextStyle(color: colors.textSecondary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            onPressed: () {
              final newPath = controller.text.trim();
              if (newPath.isNotEmpty) {
                setState(() => _savePath = newPath);
                _prefs.setSavePath(newPath);
              }
              Navigator.pop(c);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Save location updated to: $_savePath')),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _applyTheme(String label) {
    if (_hapticFeedback) HapticFeedback.selectionClick();
    setState(() => _theme = label);
    if (label == 'Dark') {
      _prefs.setThemeMode('dark');
      themeNotifier.value = ThemeMode.dark;
    } else if (label == 'System') {
      _prefs.setThemeMode('system');
      themeNotifier.value = ThemeMode.system;
    } else {
      _prefs.setThemeMode('light');
      themeNotifier.value = ThemeMode.light;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colors.surface.withOpacity(0.9),
                border: Border(bottom: BorderSide(color: colors.borderLight)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.surfaceSecondary,
                    ),
                    child: IconButton(
                      icon: Icon(Icons.arrow_back, color: colors.iconColor, size: 22),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('Settings', style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: colors.textPrimary, letterSpacing: -0.18)),
                  const Spacer(),
                  _buildIconButton(Icons.restart_alt, onTap: () async {
                    if (_hapticFeedback) HapticFeedback.mediumImpact();
                    await _prefs.resetToDefaults();
                    _loadAllSettings();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('All settings restored to factory defaults.')),
                      );
                    }
                  }),
                ],
              ),
            ),

            // Main content
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pro Recorder Telemetry Banner
                    _buildTelemetryBanner(),

                    const SizedBox(height: 24),

                    // Section 1: Recording Defaults
                    _buildSectionHeader('Recording Defaults', Icons.circle, const Color(0xFFDC2626), 'Global Presets'),
                    _buildSettingsCard([
                      _buildNavigationRow(
                        Icons.video_settings,
                        'Video Resolution',
                        _resolution,
                        onTap: () => _showSelectionModal(
                          title: 'Default Video Resolution',
                          options: ['144p Eco', '240p Lite', '720p HD', '1080p FHD', '1440p 2K', '4K UHD'],
                          currentValue: _resolution,
                          onSelected: (val) {
                            setState(() => _resolution = val);
                            final raw = val.split(' ').first;
                            _prefs.setResolution(raw);
                          },
                        ),
                      ),
                      _buildNavigationRow(
                        Icons.speed,
                        'Frame Rate (FPS)',
                        _frameRate,
                        onTap: () => _showSelectionModal(
                          title: 'Default Frame Rate',
                          options: ['24 FPS (Cinematic)', '30 FPS (Standard)', '60 FPS (Smooth)', '120 FPS (High Refresh Gaming)'],
                          currentValue: _frameRate,
                          onSelected: (val) {
                            setState(() => _frameRate = val);
                            final fpsVal = int.tryParse(val.split(' ').first) ?? 60;
                            _prefs.setFps(fpsVal);
                          },
                        ),
                      ),
                      _buildNavigationRow(
                        Icons.data_usage,
                        'Video Bitrate',
                        _bitrate,
                        onTap: () => _showSelectionModal(
                          title: 'Target Encoder Bitrate',
                          options: ['4 Mbps (Eco)', '8 Mbps (Standard)', '16 Mbps (High Quality)', '24 Mbps (Ultra)', '32 Mbps (Lossless)'],
                          currentValue: _bitrate,
                          onSelected: (val) {
                            setState(() => _bitrate = val);
                            final br = double.tryParse(val.split(' ').first) ?? 16.0;
                            _prefs.setBitrate(br);
                          },
                        ),
                      ),
                      _buildNavigationRow(
                        Icons.screen_rotation,
                        'Orientation',
                        _orientation,
                        onTap: () => _showSelectionModal(
                          title: 'Capture Orientation',
                          options: ['Auto / Match Display', 'Portrait (9:16)', 'Landscape (16:9)'],
                          currentValue: _orientation,
                          onSelected: (val) {
                            setState(() => _orientation = val);
                            _prefs.setOrientation(val.split(' ').first);
                          },
                        ),
                      ),
                    ]),

                    // Section 2: Audio & Inputs
                    _buildSectionHeader('Audio & Inputs', Icons.circle, const Color(0xFF9CA3AF)),
                    _buildSettingsCard([
                      _buildNavigationRow(
                        Icons.mic,
                        'Audio Source',
                        _audioSource,
                        onTap: () => _showSelectionModal(
                          title: 'Default Audio Source',
                          options: ['Internal Audio + Mic', 'Internal Audio Only', 'Microphone Only', 'Mute / No Audio'],
                          currentValue: _audioSource,
                          onSelected: (val) {
                            setState(() => _audioSource = val);
                            _prefs.setAudioSource(val);
                          },
                        ),
                      ),
                      _buildNavigationRow(
                        Icons.graphic_eq,
                        'Audio Quality / Sampling',
                        _audioQuality,
                        onTap: () => _showSelectionModal(
                          title: 'Audio Sample Rate',
                          options: ['44.1 kHz Stereo (CD Quality)', '48 kHz Stereo (AAC Studio Master)'],
                          currentValue: _audioQuality,
                          onSelected: (val) {
                            setState(() => _audioQuality = val);
                            _prefs.setAudioQuality(val);
                          },
                        ),
                      ),
                      _buildToggleRow(
                        Icons.volume_up,
                        'Microphone Gain Boost',
                        '+6dB clean pre-amplification',
                        _micGainBoost,
                        (v) {
                          setState(() => _micGainBoost = v);
                          _prefs.setMicGainBoost(v);
                        },
                      ),
                      _buildToggleRow(
                        Icons.noise_control_off,
                        'Noise Suppression',
                        'Neural voice isolation algorithm',
                        _noiseSuppression,
                        (v) {
                          setState(() => _noiseSuppression = v);
                          _prefs.setNoiseSuppression(v);
                        },
                      ),
                    ]),

                    // Section 3: Facecam & Overlay
                    _buildSectionHeader('Facecam & Overlay', Icons.circle, const Color(0xFF9CA3AF)),
                    _buildSettingsCard([
                      _buildToggleRow(
                        Icons.face,
                        'Enable Facecam',
                        'Front camera picture-in-picture',
                        _enableFacecam,
                        (v) {
                          setState(() => _enableFacecam = v);
                          _prefs.setEnableFacecam(v);
                        },
                      ),
                      _buildNavigationRow(
                        Icons.aspect_ratio,
                        'Facecam Window Shape',
                        _facecamShape,
                        onTap: () => _showSelectionModal(
                          title: 'Facecam Window Frame',
                          options: ['Circle Head', 'Rounded Rectangle (PiP)', 'Square (PiP)'],
                          currentValue: _facecamShape,
                          onSelected: (val) {
                            setState(() => _facecamShape = val);
                            _prefs.setFacecamShape(val);
                          },
                        ),
                      ),
                      _buildToggleRow(
                        Icons.touch_app,
                        'Show Touches / Taps',
                        'Render visual tap indicators',
                        _showTouches,
                        (v) {
                          setState(() => _showTouches = v);
                          _prefs.setShowTouches(v);
                        },
                      ),
                      _buildToggleRow(
                        Icons.widgets,
                        'Floating Control Widget',
                        'Quick access recorder overlay (FRO)',
                        _floatingWidget,
                        (v) {
                          setState(() => _floatingWidget = v);
                          _prefs.setFloatingWidget(v);
                        },
                      ),
                      _buildToggleRow(
                        Icons.vibration,
                        'Shake to Finish',
                        'Halt recording instantly by shaking phone',
                        _shakeToStop,
                        (v) {
                          setState(() => _shakeToStop = v);
                          _prefs.setShakeToStop(v);
                        },
                      ),
                    ]),

                    // Section 4: Storage & Export
                    _buildSectionHeader('Storage & Export', Icons.circle, const Color(0xFF9CA3AF)),
                    _buildSettingsCard([
                      _buildNavigationRow(
                        Icons.folder,
                        'Default Save Path',
                        _savePath,
                        isPath: true,
                        onTap: _selectSavePath,
                      ),
                      _buildToggleRow(
                        Icons.cloud_upload,
                        'Auto-Sync to Cloud Vault',
                        'Encrypted background backup',
                        _autoSync,
                        (v) async {
                          setState(() => _autoSync = v);
                          await _prefs.setAutoSync(v);
                          if (v) {
                            await CloudVaultService().enableAutoSync();
                          } else {
                            await CloudVaultService().disableAutoSync();
                          }
                        },
                      ),
                      _buildToggleRow(
                        Icons.auto_delete_outlined,
                        'Auto-Delete Old Recordings',
                        'Automatically delete recordings older than $_autoDeleteDays days',
                        _autoDelete,
                        (v) {
                          setState(() => _autoDelete = v);
                          _prefs.setAutoDeleteOldVideos(v);
                          if (v) AppNotificationService.runAutoDeleteIfEnabled();
                        },
                      ),
                      if (_autoDelete)
                        _buildNavigationRow(
                          Icons.calendar_today_outlined,
                          'Delete after (days)',
                          '$_autoDeleteDays days',
                          onTap: () => _showSelectionModal(
                            title: 'Auto-Delete Threshold',
                            options: ['7 days', '14 days', '30 days', '60 days', '90 days'],
                            currentValue: '$_autoDeleteDays',
                            onSelected: (val) {
                              final days = int.tryParse(val.split(' ').first) ?? 30;
                              setState(() => _autoDeleteDays = days);
                              _prefs.setAutoDeleteDays(days);
                            },
                          ),
                        ),
                      _buildActionRow(
                        Icons.cleaning_services,
                        'Clear Cache ($_cacheSize)',
                        'Purge temporary preview renders',
                        onTap: _clearCache,
                      ),
                    ]),

                    // Section 5: Appearance
                    _buildSectionHeader('Appearance', Icons.circle, const Color(0xFF9CA3AF)),
                    _buildSettingsCard([
                      _buildThemeSelector(),
                      _buildToggleRow(
                        Icons.vibration,
                        'Haptic Feedback',
                        'Tactile responses on triggers & stops',
                        _hapticFeedback,
                        (v) {
                          setState(() => _hapticFeedback = v);
                          _prefs.setHapticFeedback(v);
                          if (v) HapticFeedback.mediumImpact();
                        },
                      ),
                    ]),

                    // Section 6: About & Legal
                    _buildSectionHeader('About & Legal', Icons.circle, const Color(0xFF9CA3AF)),
                    _buildSettingsCard([
                      _buildNavigationRow(
                        Icons.security,
                        'Privacy Policy',
                        '',
                        onTap: () => launchUrl(
                          Uri.parse('https://ispcorp.in/privacy-policy'),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                      _buildNavigationRow(
                        Icons.description,
                        'Terms of Service',
                        '',
                        onTap: () => launchUrl(
                          Uri.parse('https://ispcorp.in/privacy-policy'),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                      _buildInfoRow(Icons.info, 'App Version', 'v1.0.0'),
                    ]),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, {VoidCallback? onTap}) {
    return Container(
      width: 40,
      height: 40,
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.surfaceSecondary,
      ),
      child: IconButton(
        icon: Icon(icon, color: colors.iconColor, size: 22),
        onPressed: onTap,
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildTelemetryBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.04), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -48,
            right: -48,
            child: Container(
              width: 144,
              height: 144,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFDC2626).withOpacity(0.05),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: colors.primaryBg,
                  border: Border.all(color: colors.primaryBorder),
                  boxShadow: [BoxShadow(color: const Color(0xFFDC2626).withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: const Icon(Icons.verified, color: Color(0xFFDC2626), size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Pro Capture Engine', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700, color: colors.textPrimary)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: colors.primaryBg,
                            borderRadius: BorderRadius.circular(9999),
                            border: Border.all(color: colors.primaryBorder),
                          ),
                          child: Text('Active', style: GoogleFonts.hankenGrotesk(fontSize: 9, fontWeight: FontWeight.w700, color: const Color(0xFFDC2626), letterSpacing: 0.18)),
                        ),
                      ],
                    ),
                    Text('Hardware Accelerated • H.264 / AAC', style: GoogleFonts.hankenGrotesk(fontSize: 11, color: colors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData dotIcon, Color dotColor, [String? subtitle]) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
          ),
          const SizedBox(width: 8),
          Text(title, style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w700, color: dotColor, letterSpacing: 0.22)),
          if (subtitle != null) ...[
            const Spacer(),
            Text(subtitle, style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w500, color: colors.textSecondary)),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.02), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildNavigationRow(IconData icon, String title, String value, {bool isPath = false, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.surfaceSecondary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: colors.textSecondary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(title, style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: colors.textPrimary)),
            ),
            if (value.isNotEmpty) ...[
              Text(
                value,
                style: isPath ? GoogleFonts.jetBrainsMono(fontSize: 10, color: colors.textSecondary) : GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w500, color: colors.textSecondary),
              ),
              const SizedBox(width: 6),
            ],
            Icon(Icons.chevron_right, size: 18, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleRow(IconData icon, String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.surfaceSecondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: colors.textSecondary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                Text(subtitle, style: GoogleFonts.hankenGrotesk(fontSize: 11, color: colors.textSecondary)),
              ],
            ),
          ),
          _buildSwitch(value, onChanged),
        ],
      ),
    );
  }

  Widget _buildActionRow(IconData icon, String title, String subtitle, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.primaryBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: const Color(0xFFDC2626)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFFDC2626))),
                  Text(subtitle, style: GoogleFonts.hankenGrotesk(fontSize: 11, color: colors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward, size: 16, color: Color(0xFFDC2626)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.surfaceSecondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: colors.textSecondary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(title, style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: colors.textPrimary)),
          ),
          Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.w500, color: colors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildSwitch(bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () {
        if (_hapticFeedback) HapticFeedback.selectionClick();
        onChanged(!value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 24,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: value ? const Color(0xFFDC2626) : colors.border,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 4)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThemeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.surfaceSecondary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.palette, size: 20, color: colors.textSecondary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'App Theme',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Interface styling paradigm',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: colors.surfaceSecondary,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Expanded(child: _buildThemeButton('Light', _theme == 'Light')),
                Expanded(child: _buildThemeButton('Dark', _theme == 'Dark')),
                Expanded(child: _buildThemeButton('System', _theme == 'System')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeButton(String label, bool isActive) {
    return GestureDetector(
      onTap: () => _applyTheme(label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          color: isActive ? (colors.isDark ? const Color(0xFF2E3342) : Colors.white) : Colors.transparent,
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(colors.isDark ? 0.3 : 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isActive) ...[
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFDC2626),
                ),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive
                    ? (colors.isDark ? Colors.white : const Color(0xFF111827))
                    : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}