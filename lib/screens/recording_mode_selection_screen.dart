import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/app_models.dart';
import 'recording_setup_screen.dart';
import 'main_wrapper_screen.dart';
import '../services/theme_service.dart';

class RecordingModeSelectionScreen extends StatefulWidget {
  const RecordingModeSelectionScreen({super.key});

  @override
  State<RecordingModeSelectionScreen> createState() => _RecordingModeSelectionScreenState();
}

class _RecordingModeSelectionScreenState extends State<RecordingModeSelectionScreen> {
  RecordingMode _selectedMode = RecordingMode.screen;

  final List<RecordingModeItem> _modes = [
    RecordingModeItem(
      mode: RecordingMode.screen,
      icon: Icons.screen_share,
      title: 'Screen Recording',
      subtitle: 'DEFAULT PROFILE',
      description: 'Full display capture with system audio and high FPS',
      tags: ['Up to 4K UHD', 'System Audio', '60/120 FPS'],
      tagIcons: [Icons.graphic_eq, Icons.volume_up, Icons.speed],
      accentColor: const Color(0xFFDC2626),
      isDefault: true,
    ),
    RecordingModeItem(
      mode: RecordingMode.voiceScreen,
      icon: Icons.mic_external_on,
      title: 'Voice + Screen',
      subtitle: 'CREATOR AUDIO',
      description: 'Simultaneous microphone commentary and lossless internal audio',
      tags: ['Noise Cancellation', 'Dual Track', '48kHz Studio'],
      tagIcons: [Icons.noise_aware, Icons.call_split, Icons.graphic_eq],
      accentColor: const Color(0xFF7C3AED),
    ),
    RecordingModeItem(
      mode: RecordingMode.facecam,
      icon: Icons.picture_in_picture,
      title: 'Facecam Recording',
      subtitle: 'PIP STREAMER',
      description: 'Floating picture-in-picture front camera with customizable shape',
      tags: ['PiP Overlay', 'Circle & Rectangle', 'Beauty Filter'],
      tagIcons: [Icons.picture_in_picture_alt, Icons.crop_free, Icons.face],
      accentColor: const Color(0xFF0891B2),
    ),
    RecordingModeItem(
      mode: RecordingMode.game,
      icon: Icons.sports_esports,
      title: 'Game Recording',
      subtitle: 'ESPORTS TUNED',
      description: 'Optimized low-latency capture tailored for mobile gameplay',
      tags: ['Hardware Boost', 'Zero Dropped Frames', 'DND Mode'],
      tagIcons: [Icons.bolt, Icons.skip_next, Icons.do_not_disturb],
      accentColor: const Color(0xFF10B981),
      badge: '120 FPS',
      badgeColor: const Color(0xFFDC2626),
    ),
    RecordingModeItem(
      mode: RecordingMode.gif,
      icon: Icons.gif_box,
      title: 'GIF Recording',
      subtitle: 'INSTANT MEME / CLIP',
      description: 'Create quick shareable looping clips with instant optimization',
      tags: ['Direct Share', 'Max 30s', 'Auto-Compress'],
      tagIcons: [Icons.share, Icons.timer, Icons.compress],
      accentColor: const Color(0xFFF59E0B),
      badge: 'Lightweight',
      badgeColor: const Color(0xFF9CA3AF),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

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
                      border: Border.all(color: colors.border),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.04), blurRadius: 4, offset: const Offset(0, 2))],
                    ),
                    child: IconButton(
                      icon: Icon(Icons.arrow_back, color: colors.iconColor, size: 20),
                      onPressed: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        } else {
                          MainWrapperScreen.navigateToTab(context, 0);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Choose Recording Mode',
                          style: GoogleFonts.manrope(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                            letterSpacing: -0.18,
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFDC2626),
                              ),
                            ).animate(onPlay: (c) => c.repeat())
                                .scale(duration: 1000.ms, begin: const Offset(1, 1), end: const Offset(1.3, 1.3))
                                .then()
                                .fadeOut(duration: 1000.ms),
                            const SizedBox(width: 6),
                            Text(
                              'Studio Capture Engine',
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 11,
                                color: colors.textSecondary,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.surfaceSecondary,
                      borderRadius: BorderRadius.circular(9999),
                      border: Border.all(color: colors.border),
                    ),
                    child: Text(
                      '5 MODES',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: colors.textSecondary,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Hardware status banner
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.border),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.04), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.primaryBg,
                      border: Border.all(color: colors.primaryBorder),
                    ),
                    child: const Icon(Icons.tune, color: Color(0xFFDC2626), size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Capture Pipeline',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          'Hardware Accelerated Engine 4.2',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 11,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0)),
                    ),
                    child: Text(
                      'READY',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: colors.isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Mode cards
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                itemCount: _modes.length,
                itemBuilder: (context, index) {
                  final mode = _modes[index];
                  final isSelected = _selectedMode == mode.mode;
                  return _ModeCard(
                    mode: mode,
                    isSelected: isSelected,
                    colors: colors,
                    onTap: () => setState(() => _selectedMode = mode.mode),
                  ).animate()
                      .fadeIn(duration: 400.ms, delay: (100 * index).ms)
                      .slideX(begin: 0.2, end: 0);
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomSheet(colors),
    );
  }

  Widget _buildBottomSheet(AppColors colors) {
    final isPushedRoute = ModalRoute.of(context)?.canPop ?? false;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(colors.isDark ? 0.25 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        bottom: isPushedRoute,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Remember choice row (compact)
            Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: true,
                    onChanged: (_) {},
                    activeColor: const Color(0xFFDC2626),
                    checkColor: Colors.white,
                    side: BorderSide(color: colors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Remember my choice for future launches',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 11,
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Reset',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFDC2626),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 5),

            // Confirm button (compact 38px height)
            SizedBox(
              width: double.infinity,
              height: 38,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(colors: [Color(0xFFDC2626), Color(0xFFEF4444)]),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFDC2626).withOpacity(0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () => _navigateToSetup(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: EdgeInsets.zero,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Confirm Mode & Proceed',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 15),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToSetup() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => RecordingSetupScreen(selectedMode: _selectedMode),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: animation.drive(Tween(begin: const Offset(1, 0), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutCubic))),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }
}

class RecordingModeItem {
  final RecordingMode mode;
  final IconData icon;
  final String title;
  final String subtitle;
  final String description;
  final List<String> tags;
  final List<IconData> tagIcons;
  final Color accentColor;
  final bool isDefault;
  final String? badge;
  final Color? badgeColor;

  RecordingModeItem({
    required this.mode,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.tags,
    required this.tagIcons,
    required this.accentColor,
    this.isDefault = false,
    this.badge,
    this.badgeColor,
  });
}

class _ModeCard extends StatelessWidget {
  final RecordingModeItem mode;
  final bool isSelected;
  final VoidCallback onTap;
  final AppColors colors;

  const _ModeCard({
    required this.mode,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(24),
          border: isSelected
              ? Border.all(color: const Color(0xFFDC2626), width: 2)
              : Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? const Color(0xFFDC2626).withOpacity(0.12)
                  : Colors.black.withOpacity(colors.isDark ? 0.2 : 0.04),
              blurRadius: isSelected ? 20 : 4,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Ambient glow for selected
            if (isSelected)
              Positioned(
                top: -48,
                right: -48,
                child: Container(
                  width: 128,
                  height: 128,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFDC2626).withOpacity(0.1),
                  ),
                ),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Icon container
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: isSelected
                            ? colors.primaryBg
                            : colors.surfaceSecondary,
                        border: Border.all(
                          color: isSelected
                              ? colors.primaryBorder
                              : colors.border,
                        ),
                      ),
                      child: Icon(
                        mode.icon,
                        color: isSelected ? const Color(0xFFDC2626) : colors.textSecondary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                mode.title,
                                style: GoogleFonts.manrope(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textPrimary,
                                ),
                              ),
                              if (mode.isDefault) ...[
                                const SizedBox(width: 8),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            mode.subtitle,
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: colors.textSecondary,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Radio indicator
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected ? const Color(0xFFDC2626) : Colors.transparent,
                        border: Border.all(
                          color: isSelected ? const Color(0xFFDC2626) : colors.border,
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white, size: 15)
                          : Container(
                              margin: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.transparent,
                              ),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  mode.description,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 12,
                    color: colors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                // Tags
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(mode.tags.length, (i) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: colors.surfaceSecondary,
                        borderRadius: BorderRadius.circular(9999),
                        border: Border.all(color: colors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (i == 0 && mode.isDefault) ...[
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ] else if (i < mode.tagIcons.length) ...[
                            Icon(mode.tagIcons[i], size: 12, color: colors.textSecondary),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            mode.tags[i],
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: i == 0 ? colors.textPrimary : colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
                if (mode.badge != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.primaryBg,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: colors.primaryBorder),
                      ),
                      child: Text(
                        mode.badge!,
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: mode.badgeColor ?? const Color(0xFFDC2626),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}