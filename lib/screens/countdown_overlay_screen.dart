import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/app_models.dart';
import '../../services/app_notification_service.dart';
import '../../services/recording_auth_service.dart';
import 'active_recording_screen.dart';

class CountdownOverlayScreen extends StatefulWidget {
  final RecordingSettings settings;

  const CountdownOverlayScreen({super.key, required this.settings});

  @override
  State<CountdownOverlayScreen> createState() => _CountdownOverlayScreenState();
}

class _CountdownOverlayScreenState extends State<CountdownOverlayScreen> with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _pulseController;
  int _countdown = 3;
  bool _isCompleted = false;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    )..repeat(reverse: true);

    _startCountdown();
  }

  void _startCountdown() {
    if (widget.settings.countdown == 'Off') {
      _completeCountdown();
      return;
    }
    
    int initialValue = widget.settings.countdown == '5s' ? 5 : 3;
    setState(() => _countdown = initialValue);
    AppNotificationService.playCountdownTick();

    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      _animateCountdown(initialValue - 1);
    });
  }

  void _animateCountdown(int nextValue) {
    _scaleController.forward().then((_) {
      if (!mounted) return;
      setState(() => _countdown = nextValue);
      // Tick sound + haptic for each countdown number
      AppNotificationService.playCountdownTick();
      _scaleController.reverse().then((_) {
        if (nextValue > 1) {
          Future.delayed(const Duration(milliseconds: 800), () {
            _animateCountdown(nextValue - 1);
          });
        } else {
          _completeCountdown();
        }
      });
    });
  }

  void _completeCountdown() {
    _scaleController.forward().then((_) {
      if (!mounted) return;
      setState(() {
        _countdown = 0;
        _isCompleted = true;
      });
      _scaleController.reverse().then((_) {
        // Play start chime exactly when recording is about to start
        AppNotificationService.playStartChime();
        _navigateToRecording();
      });
    });
  }

  void _navigateToRecording() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => ActiveRecordingScreen(settings: widget.settings),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _cancelCountdown() {
    RecordingAuthService.resetSessionAuth();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA).withOpacity(0.95),
      body: Stack(
        children: [
          // Ambient glow
          Positioned.fill(
            child: Center(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (_, __) => Container(
                  width: 288,
                  height: 288,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFDC2626).withOpacity(0.1 * _pulseController.value),
                  ),
                ),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Column(
              children: [
                // Top HUD
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(9999),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        child: Row(
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFDC2626)),
                                ).animate(onPlay: (c) => c.repeat())
                                    .scale(duration: 1200.ms, begin: const Offset(1, 1), end: const Offset(1.5, 1.5))
                                    .then()
                                    .fadeOut(duration: 1200.ms),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFDC2626)),
                                ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'CAPTURE ARMED',
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF111827),
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(width: 1, height: 12, color: const Color(0xFFD1D5DB)),
                            const SizedBox(width: 8),
                            Text(
                              '1080P 60FPS',
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(9999),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.graphic_eq, size: 15, color: Color(0xFF6B7280)),
                            const SizedBox(width: 4),
                            Row(
                              children: List.generate(4, (i) {
                                final heights = [12, 12, 16, 8];
                                return AnimatedContainer(
                                  duration: Duration(milliseconds: 200 + i * 100),
                                  curve: Curves.easeInOut,
                                  width: 3,
                                  height: _isCompleted ? 4 : heights[i].toDouble(),
                                  margin: const EdgeInsets.symmetric(horizontal: 1),
                                  decoration: BoxDecoration(
                                    color: i == 3 ? const Color(0xFFDC2626) : const Color(0xFF374151),
                                    borderRadius: BorderRadius.circular(1.5),
                                  ),
                                ).animate(onPlay: (c) => c.repeat(reverse: true))
                                    .scaleY(duration: Duration(milliseconds: 800 + i * 200), begin: 0.5, end: 1.0);
                              }),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Center countdown
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Pulse glow ring
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (_, __) => Container(
                            width: 208 + 16 * _pulseController.value,
                            height: 208 + 16 * _pulseController.value,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFDC2626).withOpacity(0.3 * (1 - _pulseController.value * 0.5)),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFDC2626).withOpacity(0.4 * (1 - _pulseController.value * 0.5)),
                                  blurRadius: 35 + 25 * _pulseController.value,
                                ),
                                BoxShadow(
                                  color: const Color(0xFFDC2626).withOpacity(0.15 * (1 - _pulseController.value * 0.5)),
                                  blurRadius: 75 + 45 * _pulseController.value,
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Countdown number
                        AnimatedBuilder(
                          animation: _scaleController,
                          builder: (_, __) => Transform.scale(
                            scale: _isCompleted ? 1.0 : (1.0 - _scaleController.value * 0.25),
                            child: Opacity(
                              opacity: _isCompleted ? 1.0 : (1.0 - _scaleController.value * 0.5),
                              child: Container(
                                width: 160,
                                height: 160,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withOpacity(0.9),
                                  border: Border.all(color: const Color(0xFFDC2626).withOpacity(0.3), width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFDC2626).withOpacity(0.1),
                                      blurRadius: 24,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: _isCompleted
                                      ? Text(
                                          'REC',
                                          style: GoogleFonts.manrope(
                                            fontSize: 48,
                                            fontWeight: FontWeight.w800,
                                            color: const Color(0xFFDC2626),
                                            letterSpacing: -0.48,
                                          ),
                                        )
                                      : Text(
                                          '$_countdown',
                                          style: GoogleFonts.manrope(
                                            fontSize: 96,
                                            fontWeight: FontWeight.w800,
                                            color: const Color(0xFFDC2626),
                                            letterSpacing: -0.96,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        Text(
                          'Recording starts in...',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF111827),
                          ),
                        ),

                        const SizedBox(height: 4),

                        Text(
                          'Consolidated studio pipeline ready for capture',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 12,
                            color: const Color(0xFF9CA3AF),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom cancel button
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton(
                          onPressed: _cancelCountdown,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: const Color(0xFFE5E7EB)),
                            backgroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.close, color: Color(0xFFDC2626), size: 24),
                              const SizedBox(width: 8),
                              Text(
                                'Cancel Countdown',
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF111827),
                                  letterSpacing: 0.14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Tap anywhere outside to abort',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF9CA3AF),
                          letterSpacing: 0.22,
                        ),
                      ),
                    ],
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