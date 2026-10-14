import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/app_models.dart';
import '../services/theme_service.dart';
import '../screens/main_wrapper_screen.dart';
import '../screens/recording_setup_screen.dart';
import '../screens/video_editor_screen.dart';
import '../screens/cloud_vault_screen.dart';
import '../screens/profile_options_screens.dart';
import '../screens/ui_guide_screen.dart';

class AppDrawer extends StatefulWidget {
  final String currentRoute;

  const AppDrawer({super.key, required this.currentRoute});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  void _navigate(BuildContext context, Widget screen) {
    Navigator.of(context).pop(); // Close drawer first smoothly
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (ctx, anim, secAnim) => screen,
        transitionsBuilder: (ctx, animation, secAnim, child) {
          return SlideTransition(
            position: animation.drive(
              Tween(begin: const Offset(0.05, 0), end: Offset.zero)
                  .chain(CurveTween(curve: Curves.easeOutCubic)),
            ),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _navigateToTab(BuildContext context, int tabIndex) {
    Navigator.of(context).pop(); // Close drawer first
    MainWrapperScreen.navigateToTab(context, tabIndex);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Drawer(
      backgroundColor: colors.surface,
      elevation: 16,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Sleek, minimal top header bar with close button
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
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
                        'Studio Menu',
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: colors.textSecondary, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: 'Close Menu',
                  ),
                ],
              ),
            ),
            Divider(color: colors.border.withValues(alpha: 0.6), height: 1),

            // Scrollable Navigation Items - Exactly 10 essential items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  // --- SECTION 1: CORE NAVIGATION (4 items) ---
                  _buildSectionLabel('CORE NAVIGATION', colors),

                  // 1. Home / Dashboard
                  _buildNavItem(
                    colors: colors,
                    icon: Icons.dashboard_rounded,
                    title: 'Home / Dashboard',
                    routeKey: 'home',
                    onTap: () => _navigateToTab(context, 0),
                  ),

                  // 2. Start Recording
                  _buildNavItem(
                    colors: colors,
                    icon: Icons.fiber_manual_record_rounded,
                    iconColor: const Color(0xFFDC2626),
                    title: 'Start Recording',
                    subtitle: '5 Pro Recording Profiles',
                    badge: '5 Modes',
                    badgeColor: const Color(0xFFDC2626),
                    routeKey: 'record',
                    onTap: () => _navigateToTab(context, 1),
                  ),

                  // 3. Recordings Library
                  _buildNavItem(
                    colors: colors,
                    icon: Icons.video_library_rounded,
                    title: 'Recordings Library',
                    badge: 'Local',
                    routeKey: 'recordings',
                    onTap: () => _navigateToTab(context, 2),
                  ),

                  // 4. Trim / Video Editor
                  _buildNavItem(
                    colors: colors,
                    icon: Icons.content_cut_rounded,
                    title: 'Trim / Video Editor',
                    badge: 'Studio',
                    badgeColor: const Color(0xFF7C3AED),
                    routeKey: 'video-editor',
                    onTap: () => _navigate(context, const VideoEditorScreen()),
                  ),

                  // --- SECTION 2: STUDIO & BACKUP (2 items) ---
                  const SizedBox(height: 8),
                  _buildSectionLabel('STUDIO & BACKUP', colors),

                  // 5. Cloud Vault / Backup
                  _buildNavItem(
                    colors: colors,
                    icon: Icons.cloud_done_rounded,
                    title: 'Cloud Vault / Backup',
                    subtitle: 'Auto-sync to Google Drive',
                    badge: 'Drive',
                    badgeColor: const Color(0xFF3B82F6),
                    routeKey: 'cloud-vault',
                    onTap: () => _navigate(context, const CloudVaultScreen()),
                  ),

                  // 6. Recording Settings
                  _buildNavItem(
                    colors: colors,
                    icon: Icons.tune_rounded,
                    title: 'Recording Settings',
                    subtitle: 'Resolution, FPS, Bitrate, Audio',
                    routeKey: 'recording-setup',
                    onTap: () => _navigate(
                      context,
                      const RecordingSetupScreen(selectedMode: RecordingMode.screen),
                    ),
                  ),

                  // --- SECTION 3: HELP & ACCOUNT (4 items) ---
                  const SizedBox(height: 8),
                  _buildSectionLabel('HELP & ACCOUNT', colors),

                  // 7. UI Guide
                  _buildNavItem(
                    colors: colors,
                    icon: Icons.menu_book_rounded,
                    title: 'UI Guide',
                    subtitle: 'Walkthrough of features & controls',
                    badge: 'Tour',
                    badgeColor: const Color(0xFFDC2626),
                    routeKey: 'ui-guide',
                    onTap: () => _navigate(context, const UiGuideScreen()),
                  ),

                  // 8. Help & Support
                  _buildNavItem(
                    colors: colors,
                    icon: Icons.help_outline_rounded,
                    title: 'Help & Support',
                    subtitle: 'FAQ & troubleshooting guide',
                    routeKey: 'help',
                    onTap: () => _navigate(context, const HelpSupportScreen()),
                  ),

                  // 9. Support & Legal
                  _buildNavItem(
                    colors: colors,
                    icon: Icons.shield_outlined,
                    title: 'Support & Legal',
                    subtitle: 'Terms of service & privacy policy',
                    routeKey: 'about',
                    onTap: () => _navigate(context, const SupportLegalScreen()),
                  ),

                  // 10. Profile
                  _buildNavItem(
                    colors: colors,
                    icon: Icons.person_rounded,
                    title: 'Profile',
                    subtitle: 'Account, settings & storage',
                    routeKey: 'profile',
                    onTap: () => _navigateToTab(context, 3),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildSectionLabel(String text, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
      child: Text(
        text,
        style: GoogleFonts.hankenGrotesk(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: colors.textTertiary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required AppColors colors,
    required IconData icon,
    required String title,
    String? subtitle,
    String? badge,
    Color? badgeColor,
    Color? iconColor,
    required String routeKey,
    required VoidCallback onTap,
  }) {
    final bool isSelected = widget.currentRoute == routeKey;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? colors.primaryBg : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: isSelected
            ? Border.all(color: colors.primary.withOpacity(0.35), width: 1.5)
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          onTap: onTap,
          dense: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isSelected ? colors.primary.withOpacity(0.12) : colors.surfaceSecondary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 18,
              color: isSelected
                  ? colors.primary
                  : (iconColor ?? (colors.isDark ? Colors.white70 : const Color(0xFF4B5563))),
            ),
          ),
          title: Text(
            title,
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected ? colors.primary : colors.textPrimary,
            ),
          ),
          subtitle: subtitle != null
              ? Text(
                  subtitle,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 11,
                    color: isSelected ? colors.primary.withOpacity(0.8) : colors.textSecondary,
                  ),
                )
              : null,
          trailing: badge != null
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (badgeColor ?? const Color(0xFFDC2626)).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: Text(
                    badge,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: badgeColor ?? const Color(0xFFDC2626),
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
