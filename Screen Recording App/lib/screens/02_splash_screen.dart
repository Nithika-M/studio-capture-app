import 'package:flutter/material.dart';
import '../utils/theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Auto navigate to Onboarding after 2.5s
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/onboarding');
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFC),
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 390),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top Header Pill
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'ENGINE INITIALIZING',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.black.withOpacity(0.08)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.hdr_on_rounded, size: 14, color: Colors.grey.shade700),
                          const SizedBox(width: 4),
                          Text(
                            'STUDIO PRO',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Center Hero Branding
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Squircle Logo Box
                    Container(
                      width: 112,
                      height: 112,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.white, Color(0xFFF8F9FC)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.18),
                            blurRadius: 28,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black.withOpacity(0.06)),
                          ),
                          child: Center(
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.7),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    // App Title
                    Text(
                      'Consolidated Screen Recorder',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 26,
                            color: const Color(0xFF111827),
                          ),
                    ),
                    const SizedBox(height: 8),
                    // Subtitle / Tagline
                    Text(
                      'Pro Capture & Screen Studio',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF4B5563),
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    const SizedBox(height: 20),
                    // Tech Specs Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.black.withOpacity(0.08)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 6,
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
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          RichText(
                            text: const TextSpan(
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937),
                              ),
                              children: [
                                TextSpan(text: 'FHD '),
                                TextSpan(text: '• ', style: TextStyle(color: Colors.grey)),
                                TextSpan(text: '120 FPS '),
                                TextSpan(text: '• ', style: TextStyle(color: Colors.grey)),
                                TextSpan(text: 'Lossless Audio'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Bottom Loading Section
                Column(
                  children: [
                    // Indeterminate Progress Indicator
                    Container(
                      width: 192,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: const LinearProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                          backgroundColor: Colors.transparent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Initializing capture engine...',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Ready to record • v2.4.0 Studio Build',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
