import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../utils/theme.dart';

class RecordingSetupScreen extends ConsumerWidget {
  const RecordingSetupScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolution = ref.watch(resolutionProvider);
    final fps = ref.watch(fpsProvider);
    final isInternalOn = ref.watch(isInternalAudioOnProvider);
    final isMicOn = ref.watch(isMicOnProvider);
    final isFacecamOn = ref.watch(isFacecamOnProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Recording Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Video Configuration Section
                      _buildSectionHeader('Video Configuration'),
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
                              title: const Text('Resolution', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              trailing: DropdownButton<String>(
                                value: resolution,
                                underline: const SizedBox(),
                                items: ['4K Ultra HD', '1080p', '720p', '480p'].map((e) {
                                  return DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13)));
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) ref.read(resolutionProvider.notifier).state = val;
                                },
                              ),
                            ),
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(Icons.speed_rounded, color: AppColors.primary),
                              title: const Text('Frame Rate (FPS)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              trailing: DropdownButton<int>(
                                value: fps,
                                underline: const SizedBox(),
                                items: [120, 60, 30, 24].map((e) {
                                  return DropdownMenuItem(value: e, child: Text('$e FPS', style: const TextStyle(fontSize: 13)));
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) ref.read(fpsProvider.notifier).state = val;
                                },
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Audio Configuration Section
                      _buildSectionHeader('Audio Configuration'),
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
                              title: const Text('Internal Audio', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: const Text('Capture in-app sounds', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              value: isInternalOn,
                              onChanged: (val) => ref.read(isInternalAudioOnProvider.notifier).state = val,
                            ),
                            const Divider(height: 1),
                            SwitchListTile(
                              activeColor: AppColors.primary,
                              secondary: const Icon(Icons.mic_rounded, color: AppColors.primary),
                              title: const Text('Microphone Voice-over', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: const Text('Record external mic commentary', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              value: isMicOn,
                              onChanged: (val) => ref.read(isMicOnProvider.notifier).state = val,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Camera & Overlays Section
                      _buildSectionHeader('Camera & Overlays'),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: SwitchListTile(
                          activeColor: AppColors.primary,
                          secondary: const Icon(Icons.camera_front_rounded, color: AppColors.primary),
                          title: const Text('Facecam Overlay', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: const Text('PiP front camera window', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          value: isFacecamOn,
                          onChanged: (val) => ref.read(isFacecamOnProvider.notifier).state = val,
                        ),
                      ),
                    ],
                  ),
                ),

                // Start Recording CTA
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pushNamed('/permission-request');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                        elevation: 4,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.play_arrow_rounded, size: 24),
                          SizedBox(width: 8),
                          Text('Start Recording', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
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
