import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/recording_service.dart';
import '../../services/preferences_service.dart';
import '../../services/app_notification_service.dart';
import '../../services/recording_auth_service.dart';
import '../../models/app_models.dart';
import 'countdown_overlay_screen.dart';

class PermissionRequestScreen extends StatefulWidget {
  final RecordingSettings settings;

  const PermissionRequestScreen({super.key, required this.settings});

  @override
  State<PermissionRequestScreen> createState() => _PermissionRequestScreenState();
}

class _PermissionRequestScreenState extends State<PermissionRequestScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _glowController;
  bool _isRequesting = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _glowController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
  }

  Timer? _navTimer;

  @override
  void dispose() {
    _navTimer?.cancel();
    _pulseController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
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

    setState(() => _isRequesting = true);

    final permissions = <Permission>[
      Permission.microphone,
    ];
    if (widget.settings.showFacecam) {
      permissions.add(Permission.camera);
    }

    // Storage & Overlay permissions not supported on web
    if (!kIsWeb) {
      permissions.add(Permission.storage);
      permissions.add(Permission.manageExternalStorage);
      permissions.add(Permission.systemAlertWindow);
    }

    await permissions.request();

    if (!mounted) return;

    // Request MediaProjection (screen recording) permission on Android
    if (!kIsWeb) {
      final recordingService = RecordingService();
      final granted = await recordingService.requestPermission();
      if (!granted) {
        if (!mounted) return;
        
        // Show a dialog to explain why permission is needed
        final shouldRetry = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text('Screen Recording Permission Required'),
            content: Text(
              'Screen recording requires your permission to capture the screen. '
              'Please tap "Allow" or "Start recording" in the system dialog that appears next. '
              'This permission is required for the app to record your screen.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('Retry'),
              ),
            ],
          ),
        );

        if (shouldRetry == true && mounted) {
          _requestPermissions(); // Retry
        }
        return;
      }
    }

    if (!mounted) return;

    _navTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        _navigateToCountdown();
      }
    });
  }

  void _navigateToCountdown() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => CountdownOverlayScreen(settings: widget.settings),
        transitionsBuilder: (_, animation, __, child) {
          return ScaleTransition(
            scale: animation.drive(Tween(begin: 0.95, end: 1.0).chain(CurveTween(curve: Curves.easeOutCubic))),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Stack(
        children: [
          // Background dashboard (blurred)
          Positioned.fill(
            child: Opacity(
              opacity: 0.7,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: _buildBackgroundDashboard(),
              ),
            ),
          ),

          // Dark overlay
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.45),
            ),
          ),

          // Permission Modal
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 40, offset: const Offset(0, 20)),
                      BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 1, spreadRadius: 1),
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                      // Drag handle
                      Container(
                        width: 48,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1D5DB),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Icon with glow
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: _glowController,
                            builder: (_, __) => Container(
                              width: 80 + 12 * _glowController.value,
                              height: 80 + 12 * _glowController.value,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFDC2626).withOpacity(0.15 * _glowController.value),
                              ),
                            ),
                          ),
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFFEF2F2), Color(0xFFFEE2E2)],
                              ),
                              border: Border.all(color: Color(0xFFFECACA)),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0xFFDC2626).withOpacity(0.2),
                                  blurRadius: 16,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.screen_share, size: 36, color: Color(0xFFDC2626)),
                          ),
                          // Pulse dots
                          Positioned(
                            top: 4,
                            right: 4,
                            child: AnimatedBuilder(
                              animation: _pulseController,
                              builder: (_, __) => Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFDC2626).withOpacity(0.75 * _pulseController.value),
                                ),
                              ),
                            ),
                          ),
                          Positioned(top: 4, right: 4, child: Container(width: 12, height: 12, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFDC2626)))),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Android badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(9999),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.verified_user, size: 14, color: Color(0xFFDC2626)),
                            const SizedBox(width: 6),
                            Text(
                              'Android 14+ Secure Capture',
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF1F2937),
                                letterSpacing: 0.22,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Title & Description
                      Text(
                        'Allow Screen Recording',
                        style: GoogleFonts.manrope(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF111827),
                          letterSpacing: -0.24,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Consolidated Screen Recorder needs permission to capture your screen, gameplay, and system audio. Sensitive info like passwords and personal payment details will not be captured.',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 14,
                          color: const Color(0xFF4B5563),
                          height: 20 / 14,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 20),

                      // Feature chips
                      Row(
                        children: [
                          _buildFeatureChip(Icons.high_quality, '1080p / 4K', 'Stream Capture'),
                          _buildFeatureChip(Icons.call_split, 'Dual Audio', 'Internal & Mic'),
                          _buildFeatureChip(Icons.lock, 'Local Vault', 'Device Stored'),
                        ],
                      ),

                      const SizedBox(height: 28),

                      // Buttons
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isRequesting ? null : _requestPermissions,
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
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFDC2626).withOpacity(0.35),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.radio_button_checked, color: Colors.white, size: 24),
                                  const SizedBox(width: 8),
                                  Text(
                                    _isRequesting ? 'Requesting...' : 'Allow & Start Recording',
                                    style: GoogleFonts.hankenGrotesk(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                      letterSpacing: 0.28,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      TextButton(
                        onPressed: _isRequesting ? null : () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9999),
                            side: BorderSide(color: const Color(0xFFD1D5DB)),
                          ),
                        ),
                        child: Text(
                          'Not Now',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1F2937),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Info text
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.info_outline, size: 14, color: Color(0xFF9CA3AF)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'You can revoke this permission anytime in Android App Settings.',
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF9CA3AF),
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureChip(IconData icon, String title, String subtitle) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: const Color(0xFFDC2626)),
            const SizedBox(height: 6),
            Text(
              title,
              style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF111827)),
            ),
            Text(
              subtitle,
              style: GoogleFonts.hankenGrotesk(fontSize: 9, color: const Color(0xFF9CA3AF)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

Widget _buildBackgroundDashboard() {
    return Container(
      color: const Color(0xFFF1F5F9),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: const Color(0xFFE5E7EB))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFF3F4F6),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: const Icon(Icons.person, size: 16, color: Color(0xFF6B7280)),
                    ),
                    const SizedBox(width: 12),
                    Text('Studio Capture', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1F2937))),
                  ],
                ),
                const Icon(Icons.tune, color: Color(0xFF9CA3AF), size: 24),
              ],
            ),
          ),

          // Content
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFDC2626)),
                                  ).animate(onPlay: (c) => c.repeat())
                                      .scale(duration: 1000.ms, begin: const Offset(1, 1), end: const Offset(1.3, 1.3))
                                      .then()
                                      .fadeOut(duration: 1000.ms),
                                  const SizedBox(width: 8),
                                  Text('READY FOR CAPTURE', style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFFDC2626), letterSpacing: 0.22)),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(9999),
                                  border: Border.all(color: const Color(0xFFE5E7EB)),
                                ),
                                child: Text('4K 60FPS', style: GoogleFonts.hankenGrotesk(fontSize: 10, color: const Color(0xFF6B7280), fontWeight: FontWeight.w500)),
                              ),
                            ],
                          ),
                        const SizedBox(height: 16),
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9FAFB),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: Center(child: Icon(Icons.screen_share, size: 48, color: const Color(0xFFD1D5DB))),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('System Audio', style: GoogleFonts.hankenGrotesk(fontSize: 11, color: const Color(0xFF9CA3AF))),
                            Text('-12 dB', style: GoogleFonts.hankenGrotesk(fontSize: 11, color: const Color(0xFF111827), fontFeatures: [FontFeature.tabularFigures()])),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE5E7EB),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: 0.66,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF9CA3AF),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  width: 8,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDC2626),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.mic, color: Color(0xFFDC2626), size: 28),
                              const SizedBox(height: 8),
                              Text('Microphone', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1F2937))),
                              Text('Noise Cancellation Active', style: GoogleFonts.hankenGrotesk(fontSize: 11, color: const Color(0xFF9CA3AF))),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.camera_front, color: Color(0xFFDC2626), size: 28),
                              const SizedBox(height: 8),
                              Text('Face Cam', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1F2937))),
                              Text('1080p PiP Circle', style: GoogleFonts.hankenGrotesk(fontSize: 11, color: const Color(0xFF9CA3AF))),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
}