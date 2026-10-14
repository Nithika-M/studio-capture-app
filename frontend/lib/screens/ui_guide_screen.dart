import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/theme_service.dart';

class UiGuideScreen extends StatefulWidget {
  const UiGuideScreen({super.key});

  @override
  State<UiGuideScreen> createState() => _UiGuideScreenState();
}

class _UiGuideScreenState extends State<UiGuideScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  final List<GuideStep> _steps = const [
    GuideStep(
      badge: 'QUICK START',
      title: 'Home & Instant Capture',
      subtitle: 'One-tap access to studio recordings',
      description:
          'Tap the red capture button from the dashboard to instantly launch your preferred recording setup. Access recent recordings, storage metrics, and quick resolution toggles directly from your home feed.',
      icon: Icons.dashboard_customize_rounded,
      accentColor: Color(0xFFDC2626),
      features: [
        'Real-time resolution & FPS presets (720p up to 4K UHD)',
        'Three-line menu gives instant access to every tool and screen',
        'One-tap screenshot capture and quick storage metrics',
      ],
    ),
    GuideStep(
      badge: 'VERSATILE MODES',
      title: '5 Studio Recording Profiles',
      subtitle: 'Tailored capturing for every workflow',
      description:
          'Choose between 5 dedicated recording modes crafted for specific creator needs:',
      icon: Icons.video_collection_rounded,
      accentColor: Color(0xFF7C3AED),
      features: [
        'Screen Recording: Full display capture up to 120 FPS',
        'Voice + Screen: Simultaneous microphone commentary & lossless system audio',
        'Facecam Recording: Front-camera PiP overlay in circle, rounded rect, or square',
        'Gaming Record: Optimized high-frame-rate low-latency recording',
        'GIF Recording: Lightweight shareable snippets and animations',
      ],
    ),
    GuideStep(
      badge: 'PRO AUDIO',
      title: 'Dual-Track Audio & AI Noise Filter',
      subtitle: 'Broadcast quality voice commentary',
      description:
          'In Voice + Screen mode, microphone and internal device audio are captured as independent synchronized tracks. Real-time AI noise cancellation removes unwanted background hums and keyboard clicks.',
      icon: Icons.multitrack_audio_rounded,
      accentColor: Color(0xFF2563EB),
      features: [
        'Independent track volume & mute controls in the post-recording mixer',
        'Live commentary visualizer during recording',
        'Video Off blackout mode keeps audio recording active',
        'Auto-ducking suppresses system audio when you speak',
      ],
    ),
    GuideStep(
      badge: 'LIVE CONTROLS',
      title: 'Active Recording Controls',
      subtitle: 'Full command without interrupting capture',
      description:
          'Control your active session with smooth on-screen floating widgets or the persistent recording bar:',
      icon: Icons.play_circle_filled_rounded,
      accentColor: Color(0xFF059669),
      features: [
        'Pause / Resume: Perfect drift-free sync between audio & video',
        'Instant Mic Mute: Silence your commentary without dropping app audio',
        'Draggable Floating Bubble: Minimizes to screen edge while recording',
        'Shake to Finish: Shake your device to automatically stop and save',
      ],
    ),
    GuideStep(
      badge: 'PICTURE-IN-PICTURE',
      title: 'Facecam Window Customization',
      subtitle: 'Real clipped frames baked into output',
      description:
          'Personalize your front-camera overlay with customizable geometry that remains intact from live preview through final video export:',
      icon: Icons.camera_front_rounded,
      accentColor: Color(0xFFEA580C),
      features: [
        'Circle Head: Clean circular mask with smooth anti-aliased border',
        'Rounded Rectangle: Modern 16px corner curve for PiP layouts',
        'Square (PiP): Crisp edge-to-edge frame for technical streams',
        'Live repositioning anywhere on your screen during capture',
      ],
    ),
    GuideStep(
      badge: 'STUDIO REVIEW',
      title: 'Review, Trim & Studio Mix',
      subtitle: 'Post-recording refinement made simple',
      description:
          'After stopping a recording, immediately inspect your video in the Review studio. Rename files inline, adjust dual-track audio balance, trim exact start and end cut points, and export in lossless quality.',
      icon: Icons.tune_rounded,
      accentColor: Color(0xFF0891B2),
      features: [
        'Inline filename renaming with one-tap confirmation',
        'Built-in video trimmer with frame-accurate timeline scrubbing',
        'Instant local save with gallery Studio Capture folder',
        'Direct system sharing to messaging and social apps',
      ],
    ),
    GuideStep(
      badge: 'LIBRARY & BACKUP',
      title: 'Recordings Library & Backup',
      subtitle: 'Studio Capture gallery & cloud sync',
      description:
          'Recordings are saved directly into the Studio Capture folder of your gallery. Turn on Google Photos backup to sync to your Google account or back up individual clips to Google Drive.',
      icon: Icons.backup_rounded,
      accentColor: Color(0xFF10B981),
      features: [
        'Search and filter local clips by mode and date',
        'Saved in phone gallery under Movies/Studio Capture',
        'One-tap Google Photos backup launcher',
        'Instant Back up to Google Drive via Android share sheet',
      ],
    ),
  ];

  void _nextPage() {
    if (_currentIndex < _steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  void _prevPage() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final step = _steps[_currentIndex];

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: colors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Close Guide',
        ),
        title: Text(
          'UI & Feature Guide',
          style: GoogleFonts.manrope(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Skip',
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(color: colors.border, height: 1),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Step Progress Indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: colors.surfaceSecondary.withOpacity(0.5),
              child: Row(
                children: [
                  Text(
                    'Step ${_currentIndex + 1} of ${_steps.length}',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9999),
                      child: LinearProgressIndicator(
                        value: (_currentIndex + 1) / _steps.length,
                        backgroundColor: colors.border,
                        valueColor: AlwaysStoppedAnimation<Color>(step.accentColor),
                        minHeight: 6,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Main Carousel
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _steps.length,
                onPageChanged: (idx) {
                  setState(() => _currentIndex = idx);
                },
                itemBuilder: (context, index) {
                  final s = _steps[index];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Badge & Icon header
                        Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: s.accentColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: s.accentColor.withOpacity(0.25)),
                              ),
                              child: Icon(s.icon, color: s.accentColor, size: 28),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: s.accentColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      s.badge,
                                      style: GoogleFonts.hankenGrotesk(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: s.accentColor,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    s.subtitle,
                                    style: GoogleFonts.hankenGrotesk(
                                      fontSize: 12,
                                      color: colors.textSecondary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Title
                        Text(
                          s.title,
                          style: GoogleFonts.manrope(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Description
                        Text(
                          s.description,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 14,
                            color: colors.textSecondary,
                            height: 1.5,
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Feature Highlights Card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: colors.border),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.stars_rounded, color: s.accentColor, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'KEY HIGHLIGHTS',
                                    style: GoogleFonts.hankenGrotesk(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: colors.textPrimary,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ...s.features.map(
                                (f) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        margin: const EdgeInsets.only(top: 4, right: 10),
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: s.accentColor,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          f,
                                          style: GoogleFonts.hankenGrotesk(
                                            fontSize: 13,
                                            color: colors.textPrimary,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Bottom Navigation Controls
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  if (_currentIndex > 0) ...[
                    OutlinedButton.icon(
                      onPressed: _prevPage,
                      icon: const Icon(Icons.arrow_back_rounded, size: 16),
                      label: Text('Back', style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.textPrimary,
                        side: BorderSide(color: colors.border),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _nextPage,
                      icon: Icon(
                        _currentIndex == _steps.length - 1 ? Icons.check_circle_rounded : Icons.arrow_forward_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                      label: Text(
                        _currentIndex == _steps.length - 1 ? 'Get Started' : 'Next Step',
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: step.accentColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GuideStep {
  final String badge;
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final Color accentColor;
  final List<String> features;

  const GuideStep({
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.accentColor,
    required this.features,
  });
}
