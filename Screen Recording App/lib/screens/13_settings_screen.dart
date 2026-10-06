import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../utils/theme.dart';
import '../widgets/bottom_nav_bar.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolution = ref.watch(resolutionProvider);
    final fps = ref.watch(fpsProvider);
    final isInternalOn = ref.watch(isInternalAudioOnProvider);
    final isMicOn = ref.watch(isMicOnProvider);
    final isCloudOn = ref.watch(isCloudBackupOnProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const CustomBottomNavBar(),
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Group 1: Recording Settings
                _buildSectionHeader('Recording Engine'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.hd_rounded, color: AppColors.primary),
                        title: const Text('Default Resolution', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        trailing: Text(resolution, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.speed_rounded, color: AppColors.primary),
                        title: const Text('Target Frame Rate', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        trailing: Text('$fps FPS', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Group 2: Audio & Inputs
                _buildSectionHeader('Audio & Inputs'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        activeColor: AppColors.primary,
                        secondary: const Icon(Icons.graphic_eq_rounded, color: AppColors.primary),
                        title: const Text('Internal Audio Capture', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        value: isInternalOn,
                        onChanged: (val) => ref.read(isInternalAudioOnProvider.notifier).state = val,
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        activeColor: AppColors.primary,
                        secondary: const Icon(Icons.mic_rounded, color: AppColors.primary),
                        title: const Text('Microphone Track', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        value: isMicOn,
                        onChanged: (val) => ref.read(isMicOnProvider.notifier).state = val,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Group 3: Storage & Backup
                _buildSectionHeader('Storage & Cloud Backup'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        activeColor: AppColors.primary,
                        secondary: const Icon(Icons.cloud_upload_rounded, color: AppColors.primary),
                        title: const Text('Auto Sync to Cloud', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        value: isCloudOn,
                        onChanged: (val) => ref.read(isCloudBackupOnProvider.notifier).state = val,
                      ),
                      const Divider(height: 1),
                      const ListTile(
                        leading: Icon(Icons.folder_rounded, color: AppColors.primary),
                        title: Text('Storage Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text('/Internal/Movies/ScreenRecorder', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Group 4: About & Legal
                _buildSectionHeader('About & Support'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.info_outline_rounded, color: AppColors.primary),
                        title: Text('App Version', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        trailing: Text('v2.4.0 (Build 1082)', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ),
                      Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.privacy_tip_outlined, color: AppColors.primary),
                        title: Text('Privacy Policy', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        trailing: Icon(Icons.chevron_right_rounded, color: Colors.grey),
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

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
    );
  }
}
