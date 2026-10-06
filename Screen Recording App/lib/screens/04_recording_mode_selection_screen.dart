import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_models.dart';
import '../providers/app_providers.dart';
import '../utils/theme.dart';

class RecordingModeSelectionScreen extends ConsumerWidget {
  const RecordingModeSelectionScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMode = ref.watch(selectedCaptureModeProvider);

    final modes = [
      const CaptureMode(
        type: CaptureModeType.screen,
        title: 'Screen Recording',
        subtitle: 'Capture full display, apps, or game streams with system & mic audio sync.',
        iconName: 'screenshot_monitor',
        badgeText: 'MOST POPULAR',
      ),
      const CaptureMode(
        type: CaptureModeType.voiceAndScreen,
        title: 'Voice + Screen',
        subtitle: 'Optimized for tutorials & reaction videos with external mic noise suppression.',
        iconName: 'record_voice_over',
        badgeText: 'DUAL AUDIO',
      ),
      const CaptureMode(
        type: CaptureModeType.facecam,
        title: 'Facecam Overlay',
        subtitle: 'Picture-in-picture front camera with customizable circular/square mask frames.',
        iconName: 'person_pin',
        badgeText: 'PIP READY',
      ),
      const CaptureMode(
        type: CaptureModeType.game,
        title: 'Game Mode (120 FPS)',
        subtitle: 'Ultra-low overhead capture engine preserving maximum GPU performance.',
        iconName: 'sports_esports',
        badgeText: 'PRO GAMING',
      ),
      const CaptureMode(
        type: CaptureModeType.screenshot,
        title: 'Instant Screenshot',
        subtitle: 'High-res full viewport or cropped area grab with instant annotation editor.',
        iconName: 'camera',
        badgeText: 'QUICK CAPTURE',
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Choose Recording Mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: modes.length,
                    itemBuilder: (context, index) {
                      final mode = modes[index];
                      final isSelected = selectedMode == mode.type;

                      return GestureDetector(
                        onTap: () {
                          ref.read(selectedCaptureModeProvider.notifier).state = mode.type;
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? AppColors.primary : AppColors.border,
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isSelected ? AppColors.primary.withOpacity(0.08) : Colors.black12,
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: isSelected ? Colors.red.shade50 : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _getIconData(mode.iconName),
                                  color: isSelected ? AppColors.primary : Colors.grey.shade700,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          mode.title,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        if (mode.badgeText != null) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade50,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              mode.badgeText!,
                                              style: const TextStyle(
                                                fontSize: 8,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      mode.subtitle,
                                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.3),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Radio<CaptureModeType>(
                                value: mode.type,
                                groupValue: selectedMode,
                                activeColor: AppColors.primary,
                                onChanged: (value) {
                                  if (value != null) {
                                    ref.read(selectedCaptureModeProvider.notifier).state = value;
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Bottom Action CTA
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pushNamed('/recording-setup');
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
                          Text('Confirm Mode & Proceed', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, size: 20),
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

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'screenshot_monitor':
        return Icons.screenshot_monitor_rounded;
      case 'record_voice_over':
        return Icons.record_voice_over_rounded;
      case 'person_pin':
        return Icons.person_pin_rounded;
      case 'sports_esports':
        return Icons.sports_esports_rounded;
      case 'camera':
        return Icons.camera_alt_rounded;
      default:
        return Icons.videocam_rounded;
    }
  }
}
