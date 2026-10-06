import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'recording_mode_selection_screen.dart';
import 'main_wrapper_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _currentSlide = 0;
  final CarouselSliderController _carouselController = CarouselSliderController();
  final List<OnboardingSlide> _slides = [
    OnboardingSlide(
      title: 'Capture Everything on Your Screen',
      description: 'From full 4K screen recording and high-refresh 120 FPS game captures to PiP facecam and animated GIFs with lossless audio.',
      icon: Icons.lens_blur,
      iconColor: const Color(0xFFDC2626),
      tag: 'Versatile Recording Modes',
      illustration: _buildSlide1Illustration(),
    ),
    OnboardingSlide(
      title: 'Trim, Annotate, and Organize',
      description: 'Cut key moments, draw live annotations directly on-screen, and manage your recordings with instant local media storage.',
      icon: Icons.auto_fix_high,
      iconColor: const Color(0xFFDC2626),
      tag: 'Edit & Organize Studio',
      illustration: _buildSlide2Illustration(),
    ),
    OnboardingSlide(
      title: 'Ready to Record Studio Quality',
      description: 'Grant screen capture, microphone, and camera access to unlock high-fidelity streaming and recordings.',
      icon: Icons.verified_user,
      iconColor: const Color(0xFFDC2626),
      tag: 'Seamless Studio Permissions',
      illustration: _buildSlide3Illustration(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFC),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFDC2626),
                        ),
                      ).animate(onPlay: (controller) => controller.repeat(reverse: true))
                          .scale(duration: 1100.ms, begin: const Offset(1, 1), end: const Offset(0.9, 0.9)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Studio Capture',
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827),
                          letterSpacing: -0.16,
                        ),
                      ),
                      Text(
                        'CONSOLIDATED RECORDER',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF6B7280),
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _navigateToRecordingMode(),
                    child: Text(
                      'Skip',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF4B5563),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Carousel
            Expanded(
              child: CarouselSlider.builder(
                carouselController: _carouselController,
                itemCount: _slides.length,
                options: CarouselOptions(
                  height: double.infinity,
                  viewportFraction: 1.0,
                  enlargeCenterPage: false,
                  enableInfiniteScroll: false,
                  onPageChanged: (index, reason) {
                    setState(() => _currentSlide = index);
                  },
                ),
                itemBuilder: (context, index, realIndex) {
                  final slide = _slides[index];
                  return _buildSlide(slide, index == _currentSlide);
                },
              ),
            ),

            // Footer with pagination and actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                children: [
                  // Pagination dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_slides.length, (index) {
                      final isActive = index == _currentSlide;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 4,
                        width: isActive ? 28 : 8,
                        decoration: BoxDecoration(
                          color: isActive ? const Color(0xFFDC2626) : const Color(0xFFD1D5DB),
                          borderRadius: BorderRadius.circular(9999),
                        ),
                      ).animate(target: isActive ? 1 : 0)
                          .scale(duration: 300.ms, begin: const Offset(0.8, 1), end: const Offset(1, 1));
                    }),
                  ),

                  const SizedBox(height: 24),

                  // Action buttons
                  Row(
                    children: [
                      // Previous button
                      AnimatedOpacity(
                        opacity: _currentSlide == 0 ? 0 : 1,
                        duration: const Duration(milliseconds: 200),
                        child: IgnorePointer(
                          ignoring: _currentSlide == 0,
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(color: const Color(0xFFE5E7EB)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.arrow_back, color: Color(0xFF111827), size: 24),
                              onPressed: () => _carouselController.previousPage(),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Next / Get Started button
                      Expanded(
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9999),
                            gradient: const LinearGradient(
                              colors: [Color(0xFFDC2626), Color(0xFFEF4444)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFDC2626).withOpacity(0.25),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (child, animation) {
                              return ScaleTransition(scale: animation, child: child);
                            },
                            child: _currentSlide == _slides.length - 1
                                ? _buildGetStartedButton()
                                : _buildNextButton(),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Home indicator
                  Container(
                    width: 128,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(9999),
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

  Widget _buildSlide(OnboardingSlide slide, bool isActive) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Illustration
            slide.illustration
                .animate(target: isActive ? 1 : 0)
                .fadeIn(duration: 500.ms, delay: 100.ms)
                .slideY(begin: 0.2, end: 0),

            const SizedBox(height: 32),

            // Tag badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(9999),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(slide.icon, size: 14, color: slide.iconColor),
                  const SizedBox(width: 6),
                  Text(
                    slide.tag,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF111827),
                    ),
                  ),
                ],
              ),
            ).animate(target: isActive ? 1 : 0)
                .fadeIn(duration: 400.ms, delay: 200.ms)
                .slideY(begin: 0.2, end: 0),

            const SizedBox(height: 16),

            // Title
            Text(
              slide.title,
              style: GoogleFonts.manrope(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF111827),
                letterSpacing: -0.28,
                height: 36 / 28,
              ),
              textAlign: TextAlign.center,
            ).animate(target: isActive ? 1 : 0)
                .fadeIn(duration: 400.ms, delay: 300.ms)
                .slideY(begin: 0.2, end: 0),

            const SizedBox(height: 12),

            // Description
            Text(
              slide.description,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF4B5563),
                height: 20 / 14,
              ),
              textAlign: TextAlign.center,
            ).animate(target: isActive ? 1 : 0)
                .fadeIn(duration: 400.ms, delay: 400.ms)
                .slideY(begin: 0.2, end: 0),
          ],
        ),
      ),
    );
  }

  Widget _buildNextButton() {
    return ElevatedButton(
      key: const ValueKey('next'),
      onPressed: () => _carouselController.nextPage(),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
        padding: EdgeInsets.zero,
      ),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9999),
          gradient: const LinearGradient(colors: [Color(0xFFDC2626), Color(0xFFEF4444)]),
        ),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Next',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 0.14,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGetStartedButton() {
    return ElevatedButton(
      key: const ValueKey('getstarted'),
      onPressed: _navigateToRecordingMode,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
        padding: EdgeInsets.zero,
      ),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9999),
          gradient: const LinearGradient(colors: [Color(0xFFDC2626), Color(0xFFEF4444)]),
        ),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Get Started',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 0.14,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.rocket_launch, color: Colors.white, size: 20),
            ],
          ),
        ),
      ),
    ).animate(onPlay: (controller) => controller.repeat(reverse: true))
        .scale(duration: 1100.ms, begin: const Offset(1, 1), end: const Offset(1.02, 1.02));
  }

  void _navigateToRecordingMode() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => MainWrapperScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  // Slide illustrations
  static Widget _buildSlide1Illustration() {
    return Container(
      width: double.infinity,
      height: 320,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Technical grid backdrop
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPainter(),
            ),
          ),
          // Preview card
          Center(
            child: Container(
              width: 280,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA).withOpacity(0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Status pill
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
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
                            '4K • 120 FPS',
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFDC2626),
                              letterSpacing: 0.22,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(Icons.graphic_eq, size: 12, color: const Color(0xFF9CA3AF)),
                          const SizedBox(width: 4),
                          Text('96kHz', style: GoogleFonts.hankenGrotesk(fontSize: 11, color: const Color(0xFF9CA3AF))),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Recording ring
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                          color: const Color(0xFFFEF2F2),
                        ),
                      ),
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFFDC2626).withOpacity(0.3)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ).animate(onPlay: (c) => c.repeat(reverse: true))
                          .scale(duration: 1100.ms, begin: const Offset(1, 1), end: const Offset(1.05, 1.05))
                          .shimmer(duration: 2200.ms, color: const Color(0xFFDC2626).withOpacity(0.3)),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFDC2626),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.videocam, color: Colors.white, size: 18),
                      ),
                      // PiP badge
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.person, size: 10, color: Color(0xFF9CA3AF)),
                              const SizedBox(width: 4),
                              Text(
                                'PiP CAM',
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF9CA3AF),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Spec badges
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildSpecBadge('120Hz', 'Refresh'),
                      _buildSpecBadge('Lossless', 'Audio'),
                      _buildSpecBadge('GIF/MP4', 'Format'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Bottom glow
          Positioned(
            bottom: -20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 192,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildSlide2Illustration() {
    return Container(
      width: double.infinity,
      height: 320,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Center(
            child: Container(
              width: 280,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA).withOpacity(0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.movie_edit, size: 16, color: Color(0xFFDC2626)),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Timeline Editor',
                            style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF111827)),
                          ),
                        ],
                      ),
                      Text(
                        '00:04:32',
                        style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFFDC2626), fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Trim timeline
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Stack(
                      children: [
                        // Full track
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: List.generate(12, (i) {
                                final heights = [12, 24, 32, 40, 28, 40, 16, 32, 44, 20, 28, 12];
                                final colors = [const Color(0xFFD1D5DB), const Color(0xFF9CA3AF), const Color(0xFFF87171), const Color(0xFFDC2626), const Color(0xFFF87171), const Color(0xFFDC2626), const Color(0xFFD1D5DB), const Color(0xFFF87171), const Color(0xFFDC2626), const Color(0xFF9CA3AF), const Color(0xFFF87171), const Color(0xFFD1D5DB)];
                                return Container(
                                  width: 4,
                                  height: heights[i].toDouble(),
                                  decoration: BoxDecoration(
                                    color: colors[i],
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                );
                              }),
                            ),
                          ),
                        ),
                        // Selection range
                        Positioned(
                          left: 48,
                          right: 64,
                          top: 4,
                          bottom: 4,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFFDC2626), width: 2),
                              borderRadius: BorderRadius.circular(4),
                              color: const Color(0xFFDC2626).withOpacity(0.1),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(width: 3, height: 24, color: const Color(0xFFDC2626)),
                                Container(width: 3, height: 24, color: const Color(0xFFDC2626)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Tool strip
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildToolButton(Icons.draw, 'Pen', true),
                        _buildToolButton(Icons.crop, 'Crop', false),
                        _buildToolButton(Icons.content_cut, 'Cut', false),
                        _buildToolButton(Icons.speed, 'Speed', false),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Export status
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Local Media Sync', style: GoogleFonts.hankenGrotesk(fontSize: 10, color: const Color(0xFF9CA3AF), fontWeight: FontWeight.w500)),
                      Row(
                        children: [
                          Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF10B981))),
                          const SizedBox(width: 4),
                          Text('Ready to Export', style: GoogleFonts.hankenGrotesk(fontSize: 10, fontWeight: FontWeight.w500, color: const Color(0xFF111827))),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 4,
            left: 80,
            child: Container(width: 160, height: 32, decoration: BoxDecoration(color: const Color(0xFFDC2626).withOpacity(0.1), shape: BoxShape.circle)),
          ),
        ],
      ),
    );
  }

  static Widget _buildSlide3Illustration() {
    return Container(
      width: double.infinity,
      height: 320,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Center(
            child: Container(
              width: 280,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA).withOpacity(0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Capture Telemetry', style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF111827))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                          borderRadius: BorderRadius.circular(9999),
                        ),
                        child: Row(
                          children: [
                            Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFDC2626))),
                            const SizedBox(width: 4),
                            Text('Ready', style: GoogleFonts.hankenGrotesk(fontSize: 9, fontWeight: FontWeight.w500, color: const Color(0xFFDC2626))),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  _buildPermissionToggle(Icons.screenshot_monitor, 'Screen Video', 'Up to 4K Ultra HD', true),
                  _buildPermissionToggle(Icons.mic, 'Microphone', 'Internal & Voice-over', true),
                  _buildPermissionToggle(Icons.camera_front, 'Facecam Overlay', 'PiP reaction window', true),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 4,
            right: 4,
            child: Container(width: 176, height: 32, decoration: BoxDecoration(color: const Color(0xFFDC2626).withOpacity(0.1), shape: BoxShape.circle)),
          ),
        ],
      ),
    );
  }

  static Widget _buildSpecBadge(String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 2, offset: const Offset(0, 1))],
      ),
      child: Column(
        children: [
          Text(title, style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
          Text(subtitle, style: GoogleFonts.hankenGrotesk(fontSize: 8, color: const Color(0xFF9CA3AF))),
        ],
      ),
    );
  }

  static Widget _buildToolButton(IconData icon, String label, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: isActive
          ? BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)],
            )
          : null,
      child: Column(
        children: [
          Icon(icon, size: 16, color: isActive ? const Color(0xFFDC2626) : const Color(0xFF9CA3AF)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.hankenGrotesk(fontSize: 9, fontWeight: FontWeight.w600, color: isActive ? const Color(0xFFDC2626) : const Color(0xFF9CA3AF))),
        ],
      ),
    );
  }

  static Widget _buildPermissionToggle(IconData icon, String title, String subtitle, bool isOn) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: const Color(0xFF111827)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF111827))),
                Text(subtitle, style: GoogleFonts.hankenGrotesk(fontSize: 9, color: const Color(0xFF9CA3AF))),
              ],
            ),
          ),
          // Toggle
          Container(
            width: 40,
            height: 22,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: isOn ? const Color(0xFFDC2626) : const Color(0xFFE5E7EB),
            ),
            child: Stack(
              children: [
                AnimatedAlign(
                  alignment: isOn ? Alignment.centerRight : Alignment.centerLeft,
                  duration: const Duration(milliseconds: 200),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 4)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OnboardingSlide {
  final String title;
  final String description;
  final IconData icon;
  final Color iconColor;
  final String tag;
  final Widget illustration;

  OnboardingSlide({
    required this.title,
    required this.description,
    required this.icon,
    required this.iconColor,
    required this.tag,
    required this.illustration,
  });
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD1D5DB).withOpacity(0.7)
      ..strokeWidth = 1;
    const spacing = 16.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}