import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_recording_app/services/preferences_service.dart';
import 'package:screen_recording_app/screens/main_wrapper_screen.dart';
import 'package:screen_recording_app/screens/home_screen.dart';
import 'package:screen_recording_app/widgets/app_drawer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferencesService prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = PreferencesService();
    await prefs.init();
    await prefs.resetToDefaults();
  });

  group('=== BUG FIX: BOTTOM NAV TAB HIGHLIGHT MUST MATCH ACTUAL SCREEN ===', () {
    testWidgets('1. Home is initially highlighted; tapping Record tab highlights Record and unhighlights Home', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: MainWrapperScreen(initialTab: 0),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Home must be the active tab initially
      expect(MainWrapperScreen.activeTabNotifier.value, 0);
      expect(find.byKey(const ValueKey('bottom_nav_tab_0_active')), findsOneWidget);
      expect(find.byKey(const ValueKey('bottom_nav_tab_1_inactive')), findsOneWidget);

      // Tap on "Record" tab
      await tester.tap(find.byKey(const ValueKey('bottom_nav_item_1')));
      await tester.pump(const Duration(milliseconds: 300));

      // Active tab must now be 1 (Record)
      expect(MainWrapperScreen.activeTabNotifier.value, 1);
      expect(find.byKey(const ValueKey('bottom_nav_tab_1_active')), findsOneWidget);
      expect(find.byKey(const ValueKey('bottom_nav_tab_0_inactive')), findsOneWidget);
    });

    testWidgets('2. Home -> hamburger menu -> Recordings highlights Recordings, not Home; back reverts highlight to Home', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: MainWrapperScreen(initialTab: 0),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Open hamburger menu drawer on HomeScreen
      final homeScaffold = tester.state<ScaffoldState>(
        find.descendant(of: find.byType(HomeScreen), matching: find.byType(Scaffold)),
      );
      homeScaffold.openDrawer();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Tap on "Recordings Library" in drawer
      final recordingsNavItem = find.text('Recordings Library');
      expect(recordingsNavItem, findsOneWidget);
      await tester.tap(recordingsNavItem);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Active tab must be 2 (Recordings), and Recordings must be highlighted
      expect(MainWrapperScreen.activeTabNotifier.value, 2);
      expect(find.byKey(const ValueKey('bottom_nav_tab_2_active')), findsOneWidget);
      expect(find.byKey(const ValueKey('bottom_nav_tab_0_inactive')), findsOneWidget);

      // Trigger system back navigation (e.g. Android back button or back gesture)
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 300));

      // Highlight must accurately revert to 0 (Home)
      expect(MainWrapperScreen.activeTabNotifier.value, 0);
      expect(find.byKey(const ValueKey('bottom_nav_tab_0_active')), findsOneWidget);
      expect(find.byKey(const ValueKey('bottom_nav_tab_2_inactive')), findsOneWidget);
    });

    testWidgets('3. In-app links: Quick Action Start Recording highlights Record tab', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: MainWrapperScreen(initialTab: 0),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Tap Quick Action card "Start Recording" on Home
      final startCard = find.text('Start Recording').first;
      await tester.tap(startCard);
      await tester.pump(const Duration(milliseconds: 300));

      // Tab must be 1 (Record)
      expect(MainWrapperScreen.activeTabNotifier.value, 1);
      expect(find.byKey(const ValueKey('bottom_nav_tab_1_active')), findsOneWidget);
      expect(find.byKey(const ValueKey('bottom_nav_tab_0_inactive')), findsOneWidget);
    });
  });

  group('=== FEATURE: REMOVE GUEST USER BANNER FROM HAMBURGER MENU ===', () {
    testWidgets('Drawer contains no Guest User banner, no Tap to view profile subtext, and starts cleanly', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: AppDrawer(currentRoute: 'home'),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Must NOT contain Guest User label or subtext
      expect(find.text('Guest User'), findsNothing);
      expect(find.text('Tap to view profile & storage'), findsNothing);
      expect(find.text('4K UHD • Dual Audio Studio'), findsNothing);
      expect(find.text('LOCAL DEVICE'), findsNothing);

      // Must start cleanly with top header and core navigation
      expect(find.text('Studio Menu'), findsOneWidget);
      expect(find.text('CORE NAVIGATION'), findsOneWidget);
      expect(find.text('Home / Dashboard'), findsOneWidget);
      expect(find.text('Start Recording'), findsOneWidget);
      expect(find.text('Recordings Library'), findsOneWidget);
    });
  });
}
