import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/app_models.dart';
import '../../services/preferences_service.dart';
import '../../services/app_notification_service.dart';
import '../../services/recording_auth_service.dart';
import '../../services/theme_service.dart';
import '../../widgets/facecam_window.dart';
import '../../services/recording_service.dart';
import 'permission_request_screen.dart';

class RecordingSetupScreen extends StatefulWidget {
  final RecordingMode selectedMode;

  const RecordingSetupScreen({super.key, required this.selectedMode});

  @override
  State<RecordingSetupScreen> createState() => _RecordingSetupScreenState();
}

class _RecordingSetupScreenState extends State<RecordingSetupScreen> {
  AppColors get colors => context.appColors;

  String _selectedResolution = '1080p';
  int _selectedFps = 60;
  double _bitrate = 16;
  String _selectedOrientation = 'Auto';
  String _audioSource = 'Internal + Mic';
  bool _showTouches = true;
  bool _floatingBubble = true;
  bool _shakeToStop = false;
  String _countdown = '3s';
  bool _showFacecam = true;
  String _facecamShape = 'Square (PiP)';

  String _availableStorageStr = 'Loading...';

  @override
  void initState() {
    super.initState();
    _loadPersistedDefaults();
    _loadLiveStorage();
  }

  Future<void> _loadLiveStorage() async {
    try {
      final storageMap = await RecordingService().getDeviceStorageInfo();
      if (!mounted) return;
      if (storageMap != null) {
        final formatted = storageMap['availableFormatted'] as String?;
        if (formatted != null && formatted.isNotEmpty) {
          setState(() {
            _availableStorageStr = formatted;
          });
          return;
        }
        final bytes = (storageMap['availableDeviceBytes'] as num?)?.toInt() ?? 0;
        if (bytes > 0) {
          setState(() {
            _availableStorageStr = RecordingService().formatSize(bytes);
          });
          return;
        }
      }
    } catch (_) {}
    if (mounted && _availableStorageStr == 'Loading...') {
      setState(() {
        _availableStorageStr = '--';
      });
    }
  }

  void _loadPersistedDefaults() {
    final prefs = PreferencesService();
    setState(() {
      _selectedResolution = prefs.resolution;
      _selectedFps = prefs.fps;
      _bitrate = prefs.bitrate;
      _selectedOrientation = prefs.orientation.split(' ').first;
      _audioSource = widget.selectedMode == RecordingMode.voiceScreen ? 'Internal + Mic' : prefs.audioSource;
      _showTouches = prefs.showTouches;
      _floatingBubble = prefs.floatingWidget;
      _shakeToStop = prefs.shakeToStop;
      _showFacecam = prefs.enableFacecam;
      _facecamShape = prefs.facecamShape;
    });
  }

  String _getResolutionBadge(String res) {
    switch (res) {
      case '144p': return '144p Eco';
      case '240p': return '240p Lite';
      case '720p': return '720p HD';
      case '1080p': return '1080p FHD';
      case '1440p': return '1440p 2K';
      case '4K': return '4K UHD';
      default: return '$res Profile';
    }
  }

  Color _getResolutionBadgeColor(String res) {
    switch (res) {
      case '144p': return const Color(0xFF6B7280);
      case '240p': return const Color(0xFFF59E0B);
      case '720p': return const Color(0xFF0891B2);
      case '1080p': return const Color(0xFFDC2626);
      case '1440p': return const Color(0xFF7C3AED);
      case '4K': return const Color(0xFF10B981);
      default: return const Color(0xFFDC2626);
    }
  }

  String _getBitrateRecommendation() {
    switch (_selectedResolution) {
      case '144p': return 'Recommended: 0.5 - 1.5 Mbps for 144p ultra-compact';
      case '240p': return 'Recommended: 1.0 - 2.5 Mbps for 240p low bandwidth';
      case '720p': return 'Recommended: 4 - 8 Mbps for 720p HD video';
      case '1080p': return 'Recommended: 10 - 16 Mbps for 1080p high action';
      case '1440p': return 'Recommended: 16 - 24 Mbps for 1440p 2K studio';
      case '4K': return 'Recommended: 24 - 40 Mbps for 4K UHD lossless';
      default: return 'Recommended for $_selectedResolution ${_selectedFps}fps';
    }
  }

  double get _minBitrate {
    if (_selectedResolution == '144p') return 0.5;
    if (_selectedResolution == '240p') return 1.0;
    return 4.0;
  }

  double get _maxBitrate {
    if (_selectedResolution == '144p') return 4.0;
    if (_selectedResolution == '240p') return 6.0;
    if (_selectedResolution == '4K') return 40.0;
    return 32.0;
  }

  void _onResolutionChanged(String newRes) {
    setState(() {
      _selectedResolution = newRes;
      if (newRes == '144p') {
        _bitrate = 0.8;
      } else if (newRes == '240p') {
        _bitrate = 1.5;
      } else if (newRes == '720p' && (_bitrate < 4 || _bitrate > 12)) {
        _bitrate = 8.0;
      } else if (newRes == '1080p' && (_bitrate < 8 || _bitrate > 24)) {
        _bitrate = 16.0;
      } else if (newRes == '1440p' && (_bitrate < 16 || _bitrate > 30)) {
        _bitrate = 20.0;
      } else if (newRes == '4K' && _bitrate < 24) {
        _bitrate = 32.0;
      }
    });
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              decoration: BoxDecoration(
                color: colors.surface.withOpacity(0.95),
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))],
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back, color: Color(0xFF374151), size: 22),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(9999),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFDC2626)),
                            ).animate(onPlay: (c) => c.repeat())
                                .scale(duration: 1000.ms, begin: const Offset(1, 1), end: const Offset(1.3, 1.3))
                                .then()
                                .fadeOut(duration: 1000.ms),
                            const SizedBox(width: 6),
                            Text(
                              widget.selectedMode == RecordingMode.voiceScreen
                                  ? 'Voice + Screen Pro • Dual Audio'
                                  : 'Pro 1080p Profile',
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: widget.selectedMode == RecordingMode.voiceScreen
                                    ? const Color(0xFF7C3AED)
                                    : const Color(0xFFDC2626),
                                letterSpacing: 0.22,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))],
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.tune, color: Color(0xFF6B7280), size: 22),
                          onPressed: () {},
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recording Settings',
                        style: GoogleFonts.manrope(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827),
                          letterSpacing: -0.18,
                        ),
                      ),
                      Text(
                        'Engine v4.2',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Main content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.selectedMode == RecordingMode.voiceScreen)
                      Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C3AED).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF7C3AED).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.mic_external_on, color: Color(0xFF7C3AED), size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Voice + Screen Recording Active',
                                    style: GoogleFonts.manrope(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF7C3AED),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Simultaneous mic commentary + system audio capture configured with active AI background noise reduction.',
                                    style: GoogleFonts.hankenGrotesk(
                                      fontSize: 11,
                                      color: const Color(0xFF4B5563),
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Video Configuration
                    _buildSectionHeader(Icons.videocam, 'Video Configuration', badge: 'H.264/AVC'),
                    _buildCard([
                      _buildDropdownField(
                        label: 'Resolution Preset',
                        value: _selectedResolution,
                        items: ['144p', '240p', '720p', '1080p', '1440p', '4K'],
                        onChanged: (v) => _onResolutionChanged(v!),
                        badge: _getResolutionBadge(_selectedResolution),
                        badgeColor: _getResolutionBadgeColor(_selectedResolution),
                      ),
                      _buildSegmentedControl(
                        label: 'Frame Rate (FPS)',
                        subtitle: 'Smooth Motion',
                        options: ['24', '30', '60', '120'],
                        selected: _selectedFps.toString(),
                        onChanged: (v) => setState(() => _selectedFps = int.parse(v!)),
                        highlightIndex: 2,
                      ),
                      _buildSliderField(
                        label: 'Video Bitrate',
                        value: _bitrate.clamp(_minBitrate, _maxBitrate),
                        min: _minBitrate,
                        max: _maxBitrate,
                        divisions: ((_maxBitrate - _minBitrate) * 2).round().clamp(1, 100),
                        suffix: ' Mbps',
                        recommendation: _getBitrateRecommendation(),
                        onChanged: (v) => setState(() => _bitrate = v),
                        labels: [
                          '${_minBitrate < 1 ? _minBitrate.toStringAsFixed(1) : _minBitrate.toInt().toString()} Mbps',
                          '${((_minBitrate + _maxBitrate) / 2).toStringAsFixed(1)} Mbps',
                          '${_maxBitrate.toInt()} Mbps'
                        ],
                      ),
                      _buildSegmentedControl(
                        label: 'Capture Orientation',
                        options: ['Auto', 'Portrait', 'Landscape'],
                        selected: _selectedOrientation,
                        onChanged: (v) => setState(() => _selectedOrientation = v!),
                        icons: [Icons.screen_rotation, Icons.stay_current_portrait, Icons.stay_current_landscape],
                        highlightIndex: 0,
                      ),
                    ]),

                    const SizedBox(height: 24),

                    // Audio Configuration
                    _buildSectionHeader(Icons.mic, 'Audio Configuration', badge: '48 kHz Stereo'),
                    _buildCard([
                      _buildRadioGroup(
                        label: 'Audio Source',
                        options: [
                          _RadioOption(
                            icon: Icons.speaker,
                            title: 'Internal Audio',
                            subtitle: 'In-game and pristine system audio only',
                            value: 'Internal',
                          ),
                          _RadioOption(
                            icon: Icons.mic_external_on,
                            title: 'Microphone',
                            subtitle: 'Voiceover and real-world room speech',
                            value: 'Microphone',
                          ),
                          _RadioOption(
                            icon: Icons.graphic_eq,
                            title: 'Internal + Mic',
                            subtitle: 'Both channels separated with software noise gate',
                            value: 'Internal + Mic',
                            isDefault: true,
                            badge: 'STUDIO DUAL',
                          ),
                          _RadioOption(
                            icon: Icons.mic_off,
                            title: 'Mute / None',
                            subtitle: 'Silent high-efficiency stream',
                            value: 'Mute',
                          ),
                        ],
                        selectedValue: _audioSource,
                        onChanged: (v) => setState(() => _audioSource = v!),
                      ),
                      _buildAudioVisualizer(),
                    ]),

                    const SizedBox(height: 24),

                    // Camera & Overlays
                    _buildSectionHeader(Icons.photo_camera_front, 'Camera & Overlays', badge: _showFacecam ? 'PIP Active' : 'Off', badgeColor: _showFacecam ? const Color(0xFFDC2626) : const Color(0xFF9CA3AF)),
                    _buildCard([
                      _buildToggleRow(
                        title: 'Facecam Picture-in-Picture',
                        subtitle: 'Render selfie camera on top of recording',
                        value: _showFacecam,
                        onChanged: (v) {
                          setState(() => _showFacecam = v);
                          PreferencesService().setEnableFacecam(v);
                        },
                      ),
                      if (_showFacecam) ...[
                        const Divider(height: 1, color: Color(0xFFF3F4F6)),
                        _buildFacecamSettings(),
                      ],
                    ]),

                    const SizedBox(height: 24),

                    // Recording Tools
                    _buildSectionHeader(Icons.auto_fix_high, 'Recording Tools & Convenience'),
                    _buildCard([
                      _buildSegmentedControl(
                        label: 'Countdown Lead-in',
                        subtitle: 'Buffer before capture activates',
                        options: ['3s', '5s', 'Off'],
                        selected: _countdown,
                        onChanged: (v) => setState(() => _countdown = v!),
                        highlightIndex: 0,
                      ),
                      const Divider(height: 1, color: Color(0xFFF3F4F6)),
                      _buildToggleRow(
                        title: 'Show Screen Touches',
                        subtitle: 'Visual ripple cue on screen taps',
                        value: _showTouches,
                        onChanged: (v) {
                          setState(() => _showTouches = v);
                          PreferencesService().setShowTouches(v);
                        },
                      ),
                      const Divider(height: 1, color: Color(0xFFF3F4F6)),
                      _buildToggleRow(
                        title: 'Floating Control Bubble',
                        subtitle: 'Overlay widget for quick pause & stop',
                        value: _floatingBubble,
                        onChanged: (v) {
                          setState(() => _floatingBubble = v);
                          PreferencesService().setFloatingWidget(v);
                        },
                      ),
                      const Divider(height: 1, color: Color(0xFFF3F4F6)),
                      _buildToggleRow(
                        title: 'Shake to Finish',
                        subtitle: 'Halt recording instantly by shaking phone',
                        value: _shakeToStop,
                        onChanged: (v) {
                          setState(() => _shakeToStop = v);
                          PreferencesService().setShakeToStop(v);
                        },
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title, {String? badge, Color? badgeColor}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFDC2626), size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: GoogleFonts.hankenGrotesk(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF111827),
              letterSpacing: 0.08,
            ),
          ),
          if (badge != null) ...[
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: (badgeColor ?? const Color(0xFFDC2626)).withOpacity(0.1),
                borderRadius: BorderRadius.circular(9999),
                border: Border.all(color: (badgeColor ?? const Color(0xFFDC2626)).withOpacity(0.3)),
              ),
              child: Text(
                badge,
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: badgeColor ?? const Color(0xFFDC2626),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    String? badge,
    Color? badgeColor,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF6B7280))),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (badgeColor ?? const Color(0xFFDC2626)).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(9999),
                    border: Border.all(color: (badgeColor ?? const Color(0xFFDC2626)).withOpacity(0.3)),
                  ),
                  child: Text(badge, style: GoogleFonts.hankenGrotesk(fontSize: 10, fontWeight: FontWeight.w600, color: badgeColor ?? const Color(0xFFDC2626))),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                dropdownColor: Colors.white,
                icon: const Icon(Icons.expand_more, color: Color(0xFF9CA3AF), size: 20),
                style: GoogleFonts.hankenGrotesk(fontSize: 14, color: const Color(0xFF111827), fontWeight: FontWeight.w500),
                items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedControl({
    required String label,
    String? subtitle,
    required List<String> options,
    required String selected,
    required ValueChanged<String?> onChanged,
    List<IconData>? icons,
    int highlightIndex = -1,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF6B7280))),
              if (subtitle != null)
                Text(subtitle, style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w500, color: const Color(0xFF9CA3AF))),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(9999),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: List.generate(options.length, (i) {
                final isSelected = options[i] == selected;
                final isHighlighted = i == highlightIndex && isSelected;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(options[i]),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9999),
                        color: isSelected ? Colors.white : Colors.transparent,
                        border: isSelected && isHighlighted ? Border.all(color: const Color(0xFFDC2626)) : null,
                        boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 1))] : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (icons != null) ...[
                            Icon(icons[i], size: 16, color: isSelected ? const Color(0xFFDC2626) : const Color(0xFF9CA3AF)),
                            const SizedBox(width: 6),
                          ],
                          if (isHighlighted)
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFDC2626)),
                            ),
                          Text(
                            options[i],
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected ? const Color(0xFF111827) : const Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderField({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String suffix,
    String? recommendation,
    required ValueChanged<double> onChanged,
    required List<String> labels,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF6B7280))),
              Text(
                '${value < 4 ? value.toStringAsFixed(1) : value.toStringAsFixed(0)}$suffix',
                style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF111827)),
              ),
            ],
          ),
          Text(recommendation ?? 'Recommended for 1080p 60fps high action', style: GoogleFonts.hankenGrotesk(fontSize: 11, color: const Color(0xFF9CA3AF))),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
              activeTrackColor: const Color(0xFFDC2626),
              inactiveTrackColor: const Color(0xFFE5E7EB),
              thumbColor: Colors.white,
              valueIndicatorColor: const Color(0xFFDC2626),
              valueIndicatorTextStyle: GoogleFonts.hankenGrotesk(color: Colors.white, fontSize: 11),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: '${value.toStringAsFixed(0)}$suffix',
              onChanged: onChanged,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: labels.map((l) => Text(l, style: GoogleFonts.hankenGrotesk(fontSize: 10, fontWeight: FontWeight.w500, color: const Color(0xFF9CA3AF)))).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadioGroup({
    required String label,
    required List<_RadioOption> options,
    required String selectedValue,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: options.map((opt) => _buildRadioOption(opt, selectedValue == opt.value, () => onChanged(opt.value))).toList(),
      ),
    );
  }

  Widget _buildRadioOption(_RadioOption option, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFEF2F2).withOpacity(0.4) : const Color(0xFFF9FAFB).withOpacity(0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFDC2626) : const Color(0xFFE5E7EB),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? const Color(0xFFFEF2F2) : const Color(0xFFE5E7EB).withOpacity(0.8),
              ),
              child: Icon(option.icon, size: 18, color: isSelected ? const Color(0xFFDC2626) : const Color(0xFF6B7280)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(option.title, style: GoogleFonts.hankenGrotesk(fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF111827))),
                      if (option.badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626),
                            borderRadius: BorderRadius.circular(9999),
                          ),
                          child: Text(
                            option.badge!,
                            style: GoogleFonts.hankenGrotesk(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(option.subtitle, style: GoogleFonts.hankenGrotesk(fontSize: 11, color: isSelected ? const Color(0xFF6B7280) : const Color(0xFF9CA3AF))),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? const Color(0xFFDC2626) : Colors.transparent,
                border: Border.all(color: isSelected ? const Color(0xFFDC2626) : const Color(0xFFD1D5DB), width: 2),
              ),
              child: isSelected
                  ? Center(child: Container(width: 10, height: 10, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)))
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioVisualizer() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFDC2626)),
                  ).animate(onPlay: (c) => c.repeat())
                      .scale(duration: 1000.ms, begin: const Offset(1, 1), end: const Offset(1.3, 1.3))
                      .then()
                      .fadeOut(duration: 1000.ms),
                  const SizedBox(width: 6),
                  Text('DUAL CHANNEL MONITOR (L/R)', style: GoogleFonts.hankenGrotesk(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF6B7280), letterSpacing: 0.2)),
                ],
              ),
              Text('-6.2 dB Peak', style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF111827), fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(12, (i) {
                final heights = [12, 18, 28, 35, 24, 30, 12, 28, 40, 18, 32, 8];
                return AnimatedContainer(
                  duration: Duration(milliseconds: 300 + i * 50),
                  curve: Curves.easeOutCubic,
                  width: 16,
                  height: heights[i].toDouble(),
                  decoration: BoxDecoration(
                    color: heights[i] > 32 ? const Color(0xFFDC2626) : (heights[i] > 24 ? const Color(0xFFFBBF24) : const Color(0xFF10B981)),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.hankenGrotesk(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF111827))),
                  Text(subtitle, style: GoogleFonts.hankenGrotesk(fontSize: 11, color: const Color(0xFF9CA3AF))),
                ],
              ),
            ),
            _buildSwitch(value, onChanged),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitch(bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 28,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: value ? const Color(0xFFDC2626) : const Color(0xFFE5E7EB),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 24,
            height: 24,
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

  Widget _buildFacecamSettings() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Screen Placement', style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF6B7280))),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 9 / 16,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB), width: 2),
              ),
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildQuadrant('TL', false),
                      _buildQuadrant('TR', true),
                    ],
                  ),
                  Text('Canvas View', style: GoogleFonts.hankenGrotesk(fontSize: 8, fontWeight: FontWeight.w700, color: const Color(0xFF9CA3AF), letterSpacing: 0.4)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildQuadrant('BL', false),
                      _buildQuadrant('BR', false),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Shape Profile', style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF6B7280))),
          const SizedBox(height: 8),
          Column(
            children: [
              _buildShapeOption('Circle Head', Icons.circle, parseFacecamShape(_facecamShape) == FacecamShapeType.circle),
              _buildShapeOption('Rounded Rect', Icons.crop_free_rounded, parseFacecamShape(_facecamShape) == FacecamShapeType.roundedRect),
              _buildShapeOption('Square (PiP)', Icons.crop_square_rounded, parseFacecamShape(_facecamShape) == FacecamShapeType.square),
            ],
          ),
          const SizedBox(height: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('PIP Scale', style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w500, color: const Color(0xFF6B7280))),
                  Text('22%', style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.22,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuadrant(String label, bool isSelected) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: isSelected ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isSelected ? null : BorderRadius.circular(8),
        border: Border.all(
          color: isSelected ? const Color(0xFFDC2626) : const Color(0xFFD1D5DB),
          width: isSelected ? 2 : 1,
        ),
        color: isSelected ? const Color(0xFFFEF2F2) : Colors.white.withOpacity(0.6),
      ),
      child: isSelected
          ? const Icon(Icons.check, color: Color(0xFFDC2626), size: 14)
          : Center(child: Text(label, style: GoogleFonts.hankenGrotesk(fontSize: 8, fontWeight: FontWeight.w700, color: const Color(0xFF9CA3AF)))),
    );
  }

  Widget _buildShapeOption(String label, IconData icon, bool isSelected) {
    return GestureDetector(
      onTap: () => setState(() => _facecamShape = label),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFEF2F2).withOpacity(0.5) : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? const Color(0xFFDC2626) : const Color(0xFFE5E7EB), width: isSelected ? 1 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: icon == Icons.circle ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: icon == Icons.circle ? null : BorderRadius.circular(4),
                border: Border.all(color: isSelected ? const Color(0xFFDC2626) : const Color(0xFFD1D5DB), width: 2),
              ),
              child: isSelected && icon == Icons.circle
                  ? Center(child: Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFDC2626))))
                  : null,
            ),
            const SizedBox(width: 12),
            Text(label, style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? const Color(0xFF111827) : const Color(0xFF6B7280))),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        border: Border(top: BorderSide(color: const Color(0xFFE5E7EB).withOpacity(0.8))),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.data_usage, size: 16, color: Color(0xFFDC2626)),
                    const SizedBox(width: 6),
                    Text('Footprint: ', style: GoogleFonts.hankenGrotesk(fontSize: 10, fontWeight: FontWeight.w500, color: const Color(0xFF6B7280))),
                    Text(
                      '~${((_bitrate * 60) / 8).toStringAsFixed(1)} MB/min',
                      style: GoogleFonts.hankenGrotesk(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF111827)),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.storage, size: 16, color: Color(0xFF9CA3AF)),
                    const SizedBox(width: 6),
                    Text('Available: ', style: GoogleFonts.hankenGrotesk(fontSize: 10, fontWeight: FontWeight.w500, color: const Color(0xFF6B7280))),
                    Text(_availableStorageStr, style: GoogleFonts.hankenGrotesk(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9999),
                gradient: const LinearGradient(colors: [Color(0xFFDC2626), Color(0xFFEF4444)]),
                boxShadow: [BoxShadow(color: const Color(0xFFDC2626).withOpacity(0.25), blurRadius: 14, offset: const Offset(0, 4))],
              ),
              child: ElevatedButton(
                onPressed: () => _navigateToPermissions(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                    ).animate(onPlay: (c) => c.repeat())
                        .scale(duration: 1000.ms, begin: const Offset(1, 1), end: const Offset(1.3, 1.3))
                        .then()
                        .fadeOut(duration: 1000.ms),
                    const SizedBox(width: 12),
                    Text(
                      'Start Recording',
                      style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: 0.14),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.play_arrow, color: Colors.white, size: 22),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _navigateToPermissions() async {
    // Authenticate with biometrics exactly ONCE before starting recording session
    if (PreferencesService().biometricLock && !RecordingAuthService.isSessionAuthenticated) {
      final authenticated = await AppNotificationService.authenticateForRecording(context);
      if (!authenticated) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Authentication required to start recording.'),
              backgroundColor: Color(0xFFDC2626),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }
    }

    await AppNotificationService.checkAndWarnLowStorage(context);
    if (!mounted) return;

    final settings = RecordingSettings(
      mode: widget.selectedMode,
      resolution: _selectedResolution,
      fps: _selectedFps,
      bitrate: _bitrate,
      orientation: _selectedOrientation,
      audioSource: _audioSource,
      showFacecam: _showFacecam,
      facecamShape: _facecamShape,
      countdown: _countdown,
      showTouches: _showTouches,
      floatingBubble: _floatingBubble,
      shakeToStop: _shakeToStop,
    );

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => PermissionRequestScreen(settings: settings),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }
}

class _RadioOption {
  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final bool isDefault;
  final String? badge;

  _RadioOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    this.isDefault = false,
    this.badge,
  });
}