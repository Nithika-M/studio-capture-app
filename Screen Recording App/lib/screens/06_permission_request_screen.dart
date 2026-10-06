import 'package:flutter/material.dart';
import '../utils/theme.dart';

class PermissionRequestScreen extends StatelessWidget {
  const PermissionRequestScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.5),
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Bottom Sheet Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 20,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Drag Handle Indicator
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Alert Icon
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.screen_share_rounded,
                          size: 32,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Allow Screen Recording',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Consolidated Screen Recorder will start capturing everything displayed on your screen. Sensitive info like passwords or financial data may be visible during recording.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      // CTA Buttons
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pushReplacementNamed('/countdown');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                            elevation: 2,
                          ),
                          child: const Text(
                            'Allow & Start Recording',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            shape: const StadiumBorder(),
                          ),
                          child: const Text('Not Now', style: TextStyle(fontWeight: FontWeight.w600)),
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
}
