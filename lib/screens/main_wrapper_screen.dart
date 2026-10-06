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

  /// Whether the Library tab is currently the active selected tab.
  static bool get isLibraryTabActive => _activeState != null && _activeState!._currentIndex == 2;

  /// Whether the screen is running standalone without MainWrapperScreen ancestor.
  static bool get isStandalone => _activeState == null;

  /// Switches the active tab. Always goes through [changeTab] so
  /// tab history is recorded and back retraces the real visit path.
  static void switchTabInPlace(BuildContext? context, int index) {
    if (_activeState != null && _activeState!.mounted) {
      _activeState!.changeTab(index);
      return;
    }
    if (context != null) {
      context
          .findAncestorStateOfType<_MainWrapperScreenState>()
          ?.changeTab(index);
    }
  }

  /// Navigate to a tab from anywhere in the app.
  /// All paths go through [changeTab] so history is always recorded.
  static void navigateToTab(BuildContext? context, int index) {
    // 1. Ancestor in the current widget tree (best path).
    if (context != null) {
      final state =
          context.findAncestorStateOfType<_MainWrapperScreenState>();
      if (state != null) {
        state.changeTab(index);
        return;
      }
    }
    // 2. Cached singleton (works from overlays / services / deep links).
    if (_activeState != null && _activeState!.mounted) {
      if (context != null) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        navigatorKey.currentState?.popUntil((route) => route.isFirst);
      }
      _activeState!.changeTab(index);
      return;
    }
    // 3. Last resort – push a new MainWrapperScreen.
    final nav = context != null
        ? Navigator.of(context)
        : navigatorKey.currentState;
    nav?.pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (_) => MainWrapperScreen(initialTab: index)),
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
  // Each tab switch pushes the OUTGOING index here. System back pops this
  // list to retrace the exact sequence of tabs the user visited — regardless
  // of whether the switch came from the bottom nav, drawer, or any button.
  // When the list is empty, back bubbles up to the Flutter Navigator so it
  // can pop a real route or exit the app — the only valid exit point.
  final List<int> _tabHistory = [];

  @override
  void initState() {
    super.initState();
    MainWrapperScreen._activeState = this;
    _currentIndex = widget.initialTab;
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
    });
  }

  /// Pop one step of tab history — called by PopScope on back.
  void _popTabHistory() {
    if (_tabHistory.isEmpty) return;
    setState(() {
      _currentIndex = _tabHistory.removeLast();
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
      // canPop: true  → no tab history; let Flutter Navigator act
      //                  (pop a route or exit the app at true root).
      // canPop: false → we have history; intercept back to step through it.
      canPop: _tabHistory.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        // didPop == true means canPop was true and Flutter already handled it.
        if (!didPop) _popTabHistory();
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: colors.bg,
        body: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(
              top: BorderSide(color: colors.border),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: colors.isDark ? 0.3 : 0.08),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem(0, Icons.home_rounded, 'Home', colors),
                  _buildNavItem(1, Icons.videocam_rounded, 'Record', colors),
                  _buildNavItem(2, Icons.video_library_rounded, 'Recordings', colors),
                  _buildNavItem(3, Icons.person_rounded, 'Profile', colors),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, AppColors colors) {
    final isSelected = _currentIndex == index;
    return Expanded(
      child: GestureDetector(
        // Always go through changeTab so tab history is correctly recorded.
        onTap: () => changeTab(index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: isSelected ? colors.primaryBg : Colors.transparent,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: isSelected ? colors.primary : colors.textSecondary,
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? colors.primary : colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}