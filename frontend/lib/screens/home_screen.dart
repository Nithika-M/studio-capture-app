import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'main_wrapper_screen.dart';
import '../services/theme_service.dart';
import '../services/screenshot_service.dart';
import '../widgets/app_drawer.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Builder(
          builder: (context) {
            return Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Center(
                child: InkWell(
                  onTap: () => Scaffold.of(context).openDrawer(),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.border),
                      boxShadow: [
                        BoxShadow(
                          color: colors.isDark
                              ? Colors.black.withValues(alpha: 0.3)
                              : Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.menu_rounded,
                      color: colors.textPrimary,
                      size: 22,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFDC2626),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Studio Capture',
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: colors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      drawer: const AppDrawer(currentRoute: 'home'),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- SECTION 1: STUDIO STATUS HERO CARD ---
                  _buildStudioStatusCard(colors)
                      .animate()
                      .fadeIn(duration: 350.ms)
                      .slideY(
                        begin: 0.06,
                        end: 0,
                        duration: 350.ms,
                        curve: Curves.easeOutCubic,
                      ),

                  const SizedBox(height: 28),

                  // --- SECTION 2: QUICK ACTIONS HEADER ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Quick Actions',
                            style: GoogleFonts.manrope(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: colors.textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'STUDIO',
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFFDC2626),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Tap to launch',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 12,
                          color: colors.textTertiary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ).animate().fadeIn(delay: 100.ms, duration: 300.ms),

                  const SizedBox(height: 14),

                  // --- QUICK ACTIONS GRID ---
                  GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.14,
                    children: [
                      _QuickActionCard(
                        icon: Icons.videocam_rounded,
                        label: 'Start Recording',
                        subtitle: 'New session',
                        color: const Color(0xFFDC2626),
                        gradientColors: const [
                          Color(0xFFFF5252),
                          Color(0xFFDC2626),
                        ],
                        colors: colors,
                        animDelayMs: 140,
                        onTap: () {
                          MainWrapperScreen.navigateToTab(context, 1);
                        },
                      ),
                      _QuickActionCard(
                        icon: Icons.folder_open_rounded,
                        label: 'Recordings',
                        subtitle: 'Local library',
                        color: const Color(0xFF7C3AED),
                        gradientColors: const [
                          Color(0xFF8B5CF6),
                          Color(0xFF6D28D9),
                        ],
                        colors: colors,
                        animDelayMs: 190,
                        onTap: () {
                          MainWrapperScreen.navigateToTab(context, 2);
                        },
                      ),
                      _QuickActionCard(
                        icon: Icons.photo_camera_rounded,
                        label: 'Screenshot',
                        subtitle: 'Instant capture',
                        color: const Color(0xFFF59E0B),
                        gradientColors: const [
                          Color(0xFFFBBF24),
                          Color(0xFFD97706),
                        ],
                        colors: colors,
                        animDelayMs: 240,
                        onTap: () {
                          ScreenshotService.captureAndSave(context);
                        },
                      ),
                      _QuickActionCard(
                        icon: Icons.person_rounded,
                        label: 'Profile',
                        subtitle: 'Settings & account',
                        color: const Color(0xFF64748B),
                        gradientColors: const [
                          Color(0xFF64748B),
                          Color(0xFF475569),
                        ],
                        colors: colors,
                        animDelayMs: 290,
                        onTap: () {
                          MainWrapperScreen.navigateToTab(context, 3);
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // --- SECTION 3: RECENT RECORDINGS ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent Recordings',
                        style: GoogleFonts.manrope(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          MainWrapperScreen.navigateToTab(context, 2);
                        },
                        icon: const Icon(
                          Icons.arrow_forward_rounded,
                          size: 15,
                          color: Color(0xFFDC2626),
                        ),
                        label: Text(
                          'View All',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFDC2626),
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                        ),
                      ),
                    ],
                  ).animate().fadeIn(delay: 320.ms, duration: 300.ms),

                  const SizedBox(height: 14),

                  // --- EMPTY STATE CARD ---
                  _buildEmptyRecordingsCard(context, colors)
                      .animate()
                      .fadeIn(delay: 360.ms, duration: 400.ms)
                      .slideY(
                        begin: 0.06,
                        end: 0,
                        delay: 360.ms,
                        duration: 400.ms,
                        curve: Curves.easeOutCubic,
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Refined Studio Status Hero Card with animated pulsing live indicator
  Widget _buildStudioStatusCard(AppColors colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.isDark
                ? Colors.black.withValues(alpha: 0.35)
                : const Color(0xFFDC2626).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Pulsing live status indicator
              SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer pulsating wave
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFDC2626).withValues(alpha: 0.22),
                      ),
                    )
                        .animate(
                          onPlay: (controller) => controller.repeat(reverse: true),
                        )
                        .scale(
                          begin: const Offset(0.85, 0.85),
                          end: const Offset(1.15, 1.15),
                          duration: 1600.ms,
                          curve: Curves.easeInOut,
                        )
                        .fade(
                          begin: 0.4,
                          end: 0.85,
                          duration: 1600.ms,
                        ),
                    // Inner glowing core
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.surface,
                        border: Border.all(
                          color: const Color(0xFFDC2626).withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFDC2626).withValues(alpha: 0.35),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Color(0xFFFF4B4B), Color(0xFFDC2626)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Studio Capture',
                            style: GoogleFonts.manrope(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: colors.textPrimary,
                              letterSpacing: -0.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFF10B981).withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'ONLINE',
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF059669),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ready to Record',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 13,
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Capability Badges
          Row(
            children: [
              _buildFeaturePill(colors, Icons.hd_rounded, '4K UHD 60FPS'),
              const SizedBox(width: 8),
              _buildFeaturePill(colors, Icons.graphic_eq_rounded, 'Dual-Audio'),
              const SizedBox(width: 8),
              _buildFeaturePill(colors, Icons.security_rounded, 'Local Vault'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturePill(AppColors colors, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colors.textSecondary),
          const SizedBox(width: 5),
          Text(
            text,
            style: GoogleFonts.hankenGrotesk(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Empty state card with styled illustration and gradient CTA
  Widget _buildEmptyRecordingsCard(BuildContext context, AppColors colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Multi-layer glowing circular icon
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFDC2626).withValues(alpha: 0.08),
            ),
            child: Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFDC2626).withValues(alpha: 0.14),
                ),
                child: const Icon(
                  Icons.videocam_rounded,
                  size: 30,
                  color: Color(0xFFDC2626),
                ),
              ),
            ),
          ),

          const SizedBox(height: 18),

          Text(
            'No Recordings Yet',
            style: GoogleFonts.manrope(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            'Start your first screen recording to see it here',
            style: GoogleFonts.hankenGrotesk(
              fontSize: 13,
              color: colors.textSecondary,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 22),

          // Primary CTA Button
          ElevatedButton.icon(
            onPressed: () {
              MainWrapperScreen.navigateToTab(context, 1);
            },
            icon: const Icon(Icons.videocam_rounded, size: 20),
            label: Text(
              'Start Recording',
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              elevation: 4,
              shadowColor: const Color(0xFFDC2626).withValues(alpha: 0.45),
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9999),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final List<Color> gradientColors;
  final AppColors colors;
  final int animDelayMs;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.gradientColors,
    required this.colors,
    required this.animDelayMs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          splashColor: color.withValues(alpha: 0.12),
          highlightColor: color.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon badge with smooth gradient and shadow
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.32),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, size: 24, color: Colors.white),
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                    letterSpacing: -0.1,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(
          delay: Duration(milliseconds: animDelayMs),
          duration: 350.ms,
        )
        .slideY(
          begin: 0.08,
          end: 0,
          delay: Duration(milliseconds: animDelayMs),
          duration: 350.ms,
          curve: Curves.easeOutCubic,
        );
  }
}