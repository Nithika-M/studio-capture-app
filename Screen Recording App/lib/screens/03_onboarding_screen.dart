import 'package:flutter/material.dart';
import '../utils/theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({Key? key}) : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingSlide> _slides = const [
    OnboardingSlide(
      tag: 'Versatile Recording Modes',
      title: 'Capture Everything on Your Screen',
      description: 'From full 4K screen recording and high-refresh 120 FPS game captures to PiP facecam and animated GIFs with lossless audio.',
      icon: Icons.lens_blur_rounded,
      badge1: '120Hz',
      badge1Sub: 'Refresh',
      badge2: 'Lossless',
      badge2Sub: 'Audio',
      badge3: 'GIF/MP4',
      badge3Sub: 'Format',
    ),
    OnboardingSlide(
      tag: 'Edit & Organize Studio',
      title: 'Trim, Annotate, and Organize',
      description: 'Cut key moments, draw live annotations directly on-screen, and manage your recordings with instant local media storage.',
      icon: Icons.auto_fix_high_rounded,
      badge1: 'Trim',
      badge1Sub: 'Precision',
      badge2: 'Annotate',
      badge2Sub: 'Live Brush',
      badge3: 'Export',
      badge3Sub: 'Instant',
    ),
    OnboardingSlide(
      tag: 'Seamless Studio Permissions',
      title: 'Ready to Record Studio Quality',
      description: 'Grant screen capture, microphone, and camera access to unlock high-fidelity streaming and recordings.',
      icon: Icons.verified_user_rounded,
      badge1: 'Screen',
      badge1Sub: '4K HD',
      badge2: 'Mic',
      badge2Sub: 'Internal',
      badge3: 'Camera',
      badge3Sub: 'PiP Overlay',
    ),
  ];

  void _nextPage() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.of(context).pushReplacementNamed('/dashboard');
    }
  }

  void _skip() {
    Navigator.of(context).pushReplacementNamed('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFC),
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              children: [
                // Top Skip Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Center(
                              child: Icon(Icons.videocam_rounded, size: 14, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Studio Capture',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: _skip,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF4B5563),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text('Skip', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),

                // PageView
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _slides.length,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      final slide = _slides[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [
                            // Graphic Visual Container
                            Expanded(
                              child: Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFE5E7EB)),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Container(
                                    width: 280,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8F9FA),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.grey.shade300),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
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
                                                const SizedBox(width: 6),
                                                const Text(
                                                  '4K • 120 FPS',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppColors.primary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const Row(
                                              children: [
                                                Icon(Icons.graphic_eq_rounded, size: 14, color: Colors.grey),
                                                SizedBox(width: 4),
                                                Text('96kHz', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                              ],
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 20),
                                        // Center Pulsing Circle
                                        Container(
                                          width: 80,
                                          height: 80,
                                          decoration: BoxDecoration(
                                            color: Colors.red.shade50,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.red.shade200),
                                          ),
                                          child: Center(
                                            child: Container(
                                              width: 56,
                                              height: 56,
                                              decoration: BoxDecoration(
                                                color: AppColors.primary,
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: AppColors.primary.withOpacity(0.4),
                                                    blurRadius: 10,
                                                  ),
                                                ],
                                              ),
                                              child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 28),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                        // 3 Badges
                                        Row(
                                          children: [
                                            _buildBadge(slide.badge1, slide.badge1Sub),
                                            const SizedBox(width: 6),
                                            _buildBadge(slide.badge2, slide.badge2Sub),
                                            const SizedBox(width: 6),
                                            _buildBadge(slide.badge3, slide.badge3Sub),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            // Slide Text Content
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: const Color(0xFFE5E7EB)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(slide.icon, size: 14, color: AppColors.primary),
                                      const SizedBox(width: 6),
                                      Text(
                                        slide.tag,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF111827),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  slide.title,
                                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 22,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  slide.description,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: const Color(0xFF4B5563),
                                        height: 1.4,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // Footer & Navigation Controls
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          _slides.length,
                          (index) => AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: _currentPage == index ? 28 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _currentPage == index ? AppColors.primary : Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Action CTA Button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _nextPage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                            elevation: 4,
                            shadowColor: AppColors.primary.withOpacity(0.4),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _currentPage == _slides.length - 1 ? 'Get Started' : 'Next',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_rounded, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String title, String subtitle) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
            Text(subtitle, style: const TextStyle(fontSize: 9, color: Color(0xFF4B5563))),
          ],
        ),
      ),
    );
  }
}

class OnboardingSlide {
  final String tag;
  final String title;
  final String description;
  final IconData icon;
  final String badge1;
  final String badge1Sub;
  final String badge2;
  final String badge2Sub;
  final String badge3;
  final String badge3Sub;

  const OnboardingSlide({
    required this.tag,
    required this.title,
    required this.description,
    required this.icon,
    required this.badge1,
    required this.badge1Sub,
    required this.badge2,
    required this.badge2Sub,
    required this.badge3,
    required this.badge3Sub,
  });
}
