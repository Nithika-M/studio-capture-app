import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'home_screen.dart';
import 'recording_mode_selection_screen.dart';
import 'recordings_library_screen.dart';
import 'profile_screen.dart';

import '../services/theme_service.dart';
import '../services/app_notification_service.dart';
import '../main.dart';

class MainWrapperScreen extends StatefulWidget {
  final int initialTab;
  const MainWrapperScreen({super.key, this.initialTab = 0});

  static _MainWrapperScreenState? _activeState;

  /// Global notifier tracking the single source of truth for the active tab (0: Home, 1: Record, 2: Recordings, 3: Profile)
  static final ValueNotifier<int> activeTabNotifier = ValueNotifier<int>(0);

  /// Whether the Library tab is currently the active selected tab.
  static bool get isLibraryTabActive =>
      _activeState != null && _activeState!._currentIndex == 2;

  /// Whether the screen is running standalone without MainWrapperScreen ancestor.
  static bool get isStandalone => _activeState == null;

  /// Switches the active tab in-place.
  static void switchTabInPlace(BuildContext? context, int index) {
    navigateToTab(context, index);
  }

  /// Navigate to a tab from anywhere in the app (bottom nav, drawer, in-app buttons, deep links).
  /// Always routes to the root shell, switches the tab, records history, and updates active tab highlight.
  static void navigateToTab(BuildContext? context, int index) {
    // 1. Pop any modal/pushed routes back to the root shell first so we are back at the main shell
    if (context != null && Navigator.of(context).canPop()) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else if (navigatorKey.currentState?.canPop() ?? false) {
      navigatorKey.currentState?.popUntil((route) => route.isFirst);
    }

    // 2. Switch tab on the active state
    if (_activeState != null && _activeState!.mounted) {
      _activeState!.changeTab(index);
      return;
    }

    // 3. Update global notifier
    activeTabNotifier.value = index;

    // 4. Fallback if no instance is mounted
    final nav = context != null ? Navigator.of(context) : navigatorKey.currentState;
    nav?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => MainWrapperScreen(initialTab: index)),
      (route) => false,
    );
  }

  @override
  State<MainWrapperScreen> createState() => _MainWrapperScreenState();
}

class _MainWrapperScreenState extends State<MainWrapperScreen> {
  late int _currentIndex;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // ── Real tab-visit history ───────────────────────────────────────────────
  // Each tab switch pushes the outgoing index here. Back pops this list
  // to retrace the exact sequence of screens the user visited — whether from
  // bottom nav, hamburger menu, in-app links (e.g. View All), or direct taps.
  final List<int> _tabHistory = [];

  @override
  void initState() {
    super.initState();
    MainWrapperScreen._activeState = this;
    _currentIndex = widget.initialTab;
    MainWrapperScreen.activeTabNotifier.value = _currentIndex;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppNotificationService.checkAndWarnLowStorage(context);
      }
    });
  }

  @override
  void dispose() {
    if (MainWrapperScreen._activeState == this) {
      MainWrapperScreen._activeState = null;
    }
    super.dispose();
  }

  /// Switch to [index] and record the outgoing tab so back can retrace it.
  void changeTab(int index) {
    if (!mounted || index == _currentIndex) return;
    setState(() {
      _tabHistory.add(_currentIndex);
      _currentIndex = index;
      MainWrapperScreen.activeTabNotifier.value = index;
    });
  }

  /// Pop one step of tab history — called by PopScope on system/device back.
  void _popTabHistory() {
    if (_tabHistory.isEmpty) return;
    setState(() {
      _currentIndex = _tabHistory.removeLast();
      MainWrapperScreen.activeTabNotifier.value = _currentIndex;
    });
  }

  static final List<Widget> _screens = [
    const HomeScreen(),
    const RecordingModeSelectionScreen(),
    const RecordingsLibraryScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return PopScope(
      canPop: _tabHistory.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _popTabHistory();
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: colors.bg,
        body: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
        bottomNavigationBar: ValueListenableBuilder<int>(
          valueListenable: MainWrapperScreen.activeTabNotifier,
          builder: (context, activeTab, _) {
            final effectiveIndex = _currentIndex;
            return Container(
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(
                  top: BorderSide(color: colors.border),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: colors.isDark ? 0.35 : 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildNavItem(0, Icons.home_rounded, 'Home', colors, effectiveIndex),
                      _buildNavItem(1, Icons.videocam_rounded, 'Record', colors, effectiveIndex),
                      _buildNavItem(2, Icons.video_library_rounded, 'Recordings', colors, effectiveIndex),
                      _buildNavItem(3, Icons.person_rounded, 'Profile', colors, effectiveIndex),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    IconData icon,
    String label,
    AppColors colors,
    int activeIndex,
  ) {
    final isSelected = activeIndex == index;
    final primaryColor = const Color(0xFFDC2626);

    return Expanded(
      child: Semantics(
        selected: isSelected,
        button: true,
        label: '$label tab, ${isSelected ? "selected" : "not selected"}',
        child: GestureDetector(
          key: ValueKey('bottom_nav_item_$index'),
          onTap: () => changeTab(index),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            key: ValueKey(isSelected ? 'bottom_nav_tab_${index}_active' : 'bottom_nav_tab_${index}_inactive'),
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: isSelected
                  ? (colors.isDark ? const Color(0xFF381515) : const Color(0xFFFEE2E2))
                  : Colors.transparent,
              border: isSelected
                  ? Border.all(color: primaryColor.withValues(alpha: 0.3), width: 1.2)
                  : Border.all(color: Colors.transparent, width: 1.2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 23,
                  color: isSelected ? primaryColor : colors.textSecondary,
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                      color: isSelected ? primaryColor : colors.textSecondary,
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
}