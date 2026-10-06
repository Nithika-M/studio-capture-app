import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../utils/theme.dart';

class RecordingCompletedScreen extends ConsumerWidget {
  const RecordingCompletedScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Recording Saved', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () {
            ref.read(bottomNavIndexProvider.notifier).state = 0;
            Navigator.of(context).pushReplacementNamed('/dashboard');
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Video Preview Player Box
                  Container(
                    width: double.infinity,
                    height: 220,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Icon(Icons.movie_rounded, size: 64, color: Colors.white.withOpacity(0.4)),
                        ),
                        Center(
                          child: CircleAvatar(
                            radius: 28,
                            backgroundColor: Colors.white.withOpacity(0.9),
                            child: const Icon(Icons.play_arrow_rounded, color: AppColors.primary, size: 36),
                          ),
                        ),
                        Positioned(
                          bottom: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.75),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('02:45', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Editable Filename Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Filename', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'SCR_20260915_StudioRec.mp4',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_rounded, size: 18, color: AppColors.primary),
                              onPressed: () {},
                            ),
                          ],
                        ),
                        const Divider(),
                        const SizedBox(height: 6),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Resolution: 1080p (60fps)', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            Text('Size: 84.5 MB', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Action Buttons Row (Trim, Share, Delete)
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionButton(
                          icon: Icons.content_cut_rounded,
                          label: 'Trim',
                          onTap: () {
                            Navigator.of(context).pushNamed('/video-editor');
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildActionButton(
                          icon: Icons.share_rounded,
                          label: 'Share',
                          onTap: () {},
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildActionButton(
                          icon: Icons.delete_outline_rounded,
                          label: 'Delete',
                          color: AppColors.error,
                          onTap: () {
                            Navigator.of(context).pushReplacementNamed('/dashboard');
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Cloud Backup Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.cloud_upload_rounded, color: AppColors.primary),
                            SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Auto Cloud Backup', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                Text('Sync to Google Drive / Cloud', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ],
                        ),
                        Switch(
                          value: true,
                          activeColor: AppColors.primary,
                          onChanged: (val) {},
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Done / Back to Dashboard Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        ref.read(bottomNavIndexProvider.notifier).state = 0;
                        Navigator.of(context).pushReplacementNamed('/dashboard');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                        elevation: 4,
                      ),
                      child: const Text('Back to Home', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final themeColor = color ?? AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: themeColor, size: 22),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: themeColor)),
          ],
        ),
      ),
    );
  }
}
