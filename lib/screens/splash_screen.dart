import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'onboarding_screen.dart';
import 'main_wrapper_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _progressController;
  int _currentStep = 0;
  final List<String> _loadingMessages = [
    'Initializing capture engine...',
    'Calibrating 120 FPS render buffer...',
    'Configuring lossless audio bus...',
    'Ready to record',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _progressController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    )..repeat();

    _startLoadingSequence();
  }

  void _startLoadingSequence() {
    Timer.periodic(const Duration(milliseconds: 1100), (timer) {
      if (_currentStep < _loadingMessages.length - 1) {
        setState(() => _currentStep++);
      } else {
        timer.cancel();
        _navigateToOnboarding();
      }
    });
  }

void _navigateToOnboarding() {
    if (!mounted) return;
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

  @override
  void dispose() {
    _pulseController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFC),
      body: Stack(
        children: [
          // Ambient glow
          Positioned(
            top: -100,
            left: -100,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (_, __) => Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFDC2626).withOpacity(0.15 * _pulseController.value),
                ),
              ),
            ),
          ),
          Positioned(
            top: 50,
            left: 80,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFDC2626).withOpacity(0.2),
              ),
            ),
          ),
          // Background gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.7,
                  colors: [
                    Color(0x0AFF2626),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // App Icon with pulse rings
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer pulse ring 1
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (_, __) => Container(
                        width: 140 + 20 * _pulseController.value,
                        height: 140 + 20 * _pulseController.value,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFDC2626).withOpacity(0.25 * (1 - _pulseController.value)),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    // Outer pulse ring 2
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (_, __) => Container(
                        width: 160 + 20 * _pulseController.value,
                        height: 160 + 20 * _pulseController.value,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFDC2626).withOpacity(0.15 * (1 - _pulseController.value)),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    // App Icon Container
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.white, Color(0xFFF8F9FC)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 36,
                            offset: const Offset(0, 16),
                          ),
                          BoxShadow(
                            color: const Color(0xFFDC2626).withOpacity(0.18),
                            blurRadius: 28,
                          ),
                        ],
                        border: Border.all(color: Colors.black.withOpacity(0.08)),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Top specular highlight
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 1,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.1),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Inner lens
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black.withOpacity(0.06)),
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Red accent orbit
                                Container(
                                  width: 54,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFFDC2626).withOpacity(0.3),
                                    ),
                                  ),
                                ),
                                // Center record symbol
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFFDC2626),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFDC2626).withOpacity(0.7),
                                        blurRadius: 16,
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(3),
                                        color: Colors.white,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.1),
                                            blurRadius: 2,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
                    .animate()
                    .scale(duration: 800.ms, curve: Curves.elasticOut)
                    .fadeIn(duration: 600.ms),

                const SizedBox(height: 24),

                // App Name
                Text(
                  'Consolidated Screen Recorder',
                  style: GoogleFonts.manrope(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827),
                    letterSpacing: -0.28,
                    height: 36 / 28,
                  ),
                  textAlign: TextAlign.center,
                )
                    .animate(delay: 300.ms)
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.2, end: 0),

                const SizedBox(height: 8),

                // Subtitle
                Text(
                  'Pro Capture & Screen Studio',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF4B5563),
                    letterSpacing: 0.14,
                  ),
                )
                    .animate(delay: 400.ms)
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.2, end: 0),

                const SizedBox(height: 20),

                // Tech specs badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(9999),
                    border: Border.all(color: Colors.black.withOpacity(0.08)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFDC2626),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0xFFDC2626),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'FHD • 120 FPS • Lossless Audio',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1F2937),
                          letterSpacing: 0.12,
                        ),
                      ),
                    ],
                  ),
                )
                    .animate(delay: 500.ms)
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.2, end: 0),

                const SizedBox(height: 48),

                // Progress bar
                Container(
                  width: 192,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: Stack(
                    children: [
                      AnimatedBuilder(
                        animation: _progressController,
                        builder: (_, __) => Positioned(
                          left: -40 + 140 * _progressController.value,
                          top: 0,
                          bottom: 0,
                          width: 60,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(9999),
                              gradient: const LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Color(0xFFDC2626),
                                  Color(0xFFF87171),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFDC2626).withOpacity(0.6),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                    .animate(delay: 600.ms)
                    .fadeIn(duration: 400.ms),

                const SizedBox(height: 16),

                // Status text
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _progressController,
                      builder: (_, __) => Transform.rotate(
                        angle: _progressController.value * 2 * 3.14159,
                        child: const Icon(
                          Icons.sync,
                          size: 15,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _loadingMessages[_currentStep],
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF4B5563),
                        letterSpacing: 0.24,
                      ),
                    ),
                  ],
                )
                    .animate(delay: 700.ms)
                    .fadeIn(duration: 400.ms),

                const SizedBox(height: 32),

                // Version
                Text(
                  'v2.4.0 • Studio Edition',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF6B7280),
                    letterSpacing: 0.4,
                  ),
                )
                    .animate(delay: 800.ms)
                    .fadeIn(duration: 400.ms),

                const SizedBox(height: 16),

                // Home indicator
                Container(
                  width: 128,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(9999),
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