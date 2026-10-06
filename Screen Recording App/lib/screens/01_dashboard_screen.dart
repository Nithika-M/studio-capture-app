import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_models.dart';
import '../providers/app_providers.dart';
import '../utils/theme.dart';
import '../widgets/bottom_nav_bar.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaItems = ref.watch(mediaItemsProvider);
    final isInternalOn = ref.watch(isInternalAudioOnProvider);
    final isMicOn = ref.watch(isMicOnProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const CustomBottomNavBar(),
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top App Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: Colors.grey.shade200,
                              child: const Icon(Icons.person, color: Colors.grey, size: 20),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'Studio Capture',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: AppColors.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                ),
                                const Row(
                                  children: [
                                    Icon(Icons.memory_rounded, size: 12, color: AppColors.textSecondary),
                                    SizedBox(width: 4),
                                    Text(
                                      '64.2 GB free',
                                      style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () {},
                              icon: const Icon(Icons.volume_up_rounded, size: 20, color: AppColors.textSecondary),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.grey.shade100,
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                Navigator.of(context).pushNamed('/settings');
                              },
                              icon: const Icon(Icons.tune_rounded, size: 20, color: AppColors.textSecondary),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.grey.shade100,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Hero Recording Trigger Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // System Ready Pill
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F9FA),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(radius: 4, backgroundColor: AppColors.primary),
                                SizedBox(width: 6),
                                Text(
                                  'SYSTEM READY',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                SizedBox(width: 6),
                                Text('•', style: TextStyle(color: Colors.grey)),
                                SizedBox(width: 6),
                                Text(
                                  '1080p 60FPS',
                                  style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            '00:00:00',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const Text(
                            'Standby buffer cleared',
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 20),
                          // Trigger Button
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context).pushNamed('/mode-selection');
                            },
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.4),
                                    blurRadius: 20,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Start Recording',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          ),
                          const Text(
                            'Tap to capture high-definition stream',
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 16),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          // Telemetry Quick Pills
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              _buildPill(
                                icon: Icons.graphic_eq_rounded,
                                label: 'Internal: ${isInternalOn ? "ON" : "OFF"}',
                                color: AppColors.primary,
                              ),
                              _buildPill(
                                icon: isMicOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                                label: 'Mic: ${isMicOn ? "ON" : "Muted"}',
                                color: Colors.grey,
                              ),
                              _buildPill(
                                icon: Icons.hd_rounded,
                                label: 'FHD • 60 FPS',
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Capture Modes Grid Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Capture Modes',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Text('7 Tools', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1.6,
                      children: [
                        _buildModeCard(
                          context,
                          title: 'Screen Recording',
                          subtitle: 'Full display capture',
                          icon: Icons.screenshot_monitor_rounded,
                          isActive: true,
                          type: CaptureModeType.screen,
                        ),
                        _buildModeCard(
                          context,
                          title: 'Voice + Screen',
                          subtitle: 'External commentary',
                          icon: Icons.record_voice_over_rounded,
                          isActive: false,
                          type: CaptureModeType.voiceAndScreen,
                        ),
                        _buildModeCard(
                          context,
                          title: 'Facecam',
                          subtitle: 'PiP front camera',
                          icon: Icons.person_pin_rounded,
                          isActive: false,
                          type: CaptureModeType.facecam,
                        ),
                        _buildModeCard(
                          context,
                          title: 'Game Recording',
                          subtitle: 'Low latency sync',
                          icon: Icons.sports_esports_rounded,
                          badge: '120 FPS',
                          isActive: false,
                          type: CaptureModeType.game,
                        ),
                        _buildModeCard(
                          context,
                          title: 'Screenshot',
                          subtitle: 'Instant screen grab',
                          icon: Icons.camera_alt_rounded,
                          isActive: false,
                          type: CaptureModeType.screenshot,
                        ),
                        _buildModeCard(
                          context,
                          title: 'Draw on Screen',
                          subtitle: 'Annotator brush kit',
                          icon: Icons.draw_rounded,
                          isActive: false,
                          type: CaptureModeType.drawOnScreen,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Full width GIF card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: InkWell(
                      onTap: () {
                        ref.read(selectedCaptureModeProvider.notifier).state = CaptureModeType.gif;
                        Navigator.of(context).pushNamed('/recording-setup');
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.gif_rounded, color: AppColors.textPrimary),
                                ),
                                const SizedBox(width: 12),
                                const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'GIF Recording',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                    ),
                                    Text(
                                      'Lightweight animated clip generator',
                                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Recent Recordings Strip Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recent Recordings',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                            Text(
                              'Saved to Local Media Store',
                              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                        TextButton(
                          onPressed: () {
                            ref.read(bottomNavIndexProvider.notifier).state = 1;
                            Navigator.of(context).pushReplacementNamed('/media-library');
                          },
                          child: const Row(
                            children: [
                              Text('View all', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                              Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.primary),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 210,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: mediaItems.length,
                      itemBuilder: (context, index) {
                        final item = mediaItems[index];
                        return _buildRecentItemCard(context, item);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPill({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildModeCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isActive,
    required CaptureModeType type,
    String? badge,
  }) {
    return Consumer(
      builder: (context, ref, child) {
        return InkWell(
          onTap: () {
            ref.read(selectedCaptureModeProvider.notifier).state = type;
            Navigator.of(context).pushNamed('/recording-setup');
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive ? AppColors.primary : AppColors.border,
                width: isActive ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: isActive ? Colors.red.shade50 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, size: 18, color: isActive ? AppColors.primary : Colors.grey.shade700),
                    ),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(badge, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.primary)),
                      ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentItemCard(BuildContext context, MediaItem item) {
    return Container(
      width: 220,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail Box
          Container(
            height: 110,
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(Icons.movie_rounded, size: 40, color: Colors.white.withOpacity(0.5)),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.duration,
                      style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                Center(
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white.withOpacity(0.9),
                    child: const Icon(Icons.play_arrow_rounded, color: AppColors.primary, size: 22),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.resolution} • ${item.fps}fps • ${item.fileSize}',
                  style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(item.timeAgo, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                    Row(
                      children: [
                        Icon(
                          item.isSynced ? Icons.cloud_done_rounded : Icons.phone_iphone_rounded,
                          size: 12,
                          color: item.isSynced ? AppColors.primary : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item.isSynced ? 'Synced' : 'Local',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: item.isSynced ? AppColors.primary : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
