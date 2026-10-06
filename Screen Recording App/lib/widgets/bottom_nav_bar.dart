import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../utils/theme.dart';

class CustomBottomNavBar extends ConsumerWidget {
  const CustomBottomNavBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(bottomNavIndexProvider);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                context: context,
                ref: ref,
                index: 0,
                icon: Icons.videocam_rounded,
                label: 'Home',
                isSelected: currentIndex == 0,
                routeName: '/dashboard',
              ),
              _buildNavItem(
                context: context,
                ref: ref,
                index: 1,
                icon: Icons.folder_open_rounded,
                label: 'Recordings',
                isSelected: currentIndex == 1,
                routeName: '/media-library',
              ),
              _buildNavItem(
                context: context,
                ref: ref,
                index: 2,
                icon: Icons.auto_fix_high_rounded,
                label: 'Tools',
                isSelected: currentIndex == 2,
                routeName: '/video-editor',
              ),
              _buildNavItem(
                context: context,
                ref: ref,
                index: 3,
                icon: Icons.settings_rounded,
                label: 'Settings',
                isSelected: currentIndex == 3,
                routeName: '/settings',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required WidgetRef ref,
    required int index,
    required IconData icon,
    required String label,
    required bool isSelected,
    required String routeName,
  }) {
    return GestureDetector(
      onTap: () {
        ref.read(bottomNavIndexProvider.notifier).state = index;
        Navigator.of(context).pushReplacementNamed(routeName);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFEF2F2) : Colors.transparent, // red-50
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
