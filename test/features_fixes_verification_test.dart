import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_recording_app/services/preferences_service.dart';
import 'package:screen_recording_app/screens/profile_options_screens.dart';
import 'package:screen_recording_app/screens/settings_screen.dart';
import 'package:screen_recording_app/widgets/app_drawer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> recordingChannelCalls = [];

  setUp(() async {
    recordingChannelCalls.clear();
    SharedPreferences.setMockInitialValues({});
    await PreferencesService().init();
    await PreferencesService().resetToDefaults();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('screen_recording_app/recording'),
            (MethodCall call) async {
      recordingChannelCalls.add(call);
      if (call.method == 'openEmailClient') {
        return true;
      }
      return null;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('screen_recording'),
            (MethodCall call) async {
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('screen_recording_app/recording'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('screen_recording'), null);
  });

  group('FEATURE 1 & FEATURE 2: Contact Button & Email client pre-fill', () {
    testWidgets('Single tap on Contact button shows bottom sheet, and single tap on Gmail triggers compose to contact@ispcorp.in',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: SupportLegalScreen(),
        ),
      );
      await tester.pump();

      // Verify bottom sheet is NOT open initially
      expect(find.text('Open with'), findsNothing);

      // Single tap on Contact button
      final contactButton = find.widgetWithText(ElevatedButton, 'Contact');
      expect(contactButton, findsOneWidget);
      await tester.tap(contactButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Bottom sheet is immediately shown with Gmail and Outlook
      expect(find.text('Open with'), findsOneWidget);
      expect(find.text('Gmail'), findsOneWidget);
      expect(find.text('Outlook'), findsOneWidget);

      // Single tap on Gmail option
      await tester.tap(find.text('Gmail'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify method call was triggered with contact@ispcorp.in
      expect(recordingChannelCalls.where((c) => c.method == 'openEmailClient').length, 1);
      final call = recordingChannelCalls.firstWhere((c) => c.method == 'openEmailClient');
      expect(call.arguments['client'], 'gmail');
      expect(call.arguments['to'], 'contact@ispcorp.in');
    });

    testWidgets('Single tap on Outlook triggers compose to contact@ispcorp.in',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: SupportLegalScreen(),
        ),
      );
      await tester.pump();

      // Single tap on Contact button
      await tester.tap(find.widgetWithText(ElevatedButton, 'Contact'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Single tap on Outlook
      await tester.tap(find.text('Outlook'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(recordingChannelCalls.where((c) => c.method == 'openEmailClient').length, 1);
      final call = recordingChannelCalls.firstWhere((c) => c.method == 'openEmailClient');
      expect(call.arguments['client'], 'outlook');
      expect(call.arguments['to'], 'contact@ispcorp.in');
    });
  });

  group('FEATURE 3: Simplify App Version in Settings Screen', () {
    testWidgets('Settings shows only v1.0.0 without build number or marketing tagline',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll down to About & Legal section
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();

      // Shows clean v1.0.0
      expect(find.text('v1.0.0'), findsOneWidget);

      // Verify no build number
      expect(find.textContaining('Build 104'), findsNothing);
      expect(find.textContaining('Build 102'), findsNothing);

      // Verify no marketing tagline text
      expect(find.textContaining('Consolidated Media Engine'), findsNothing);
      expect(find.textContaining('Imagine Pro Suite'), findsNothing);
      expect(find.textContaining('Pro Suite'), findsNothing);
    });
  });

  group('FEATURE 4: Rename Obsidian theme to Dark', () {
    testWidgets('Theme selector displays Dark instead of Obsidian and toggles dark mode',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to Appearance section
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();

      // Verify "Dark" is present
      expect(find.text('Dark'), findsOneWidget);
      // Verify "Obsidian" is NOT present anywhere
      expect(find.text('Obsidian'), findsNothing);

      // Tap "Dark" theme button
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      // Preferences should now have dark theme
      expect(PreferencesService().themeMode, 'dark');
    });
  });

  group('FEATURE 5: Remove version line and theme icon from hamburger menu', () {
    testWidgets('AppDrawer does not show version line or theme toggle symbol at bottom',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final scaffoldKey = GlobalKey<ScaffoldState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            key: scaffoldKey,
            drawer: const AppDrawer(currentRoute: 'home'),
            body: const Center(child: Text('Home')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      scaffoldKey.currentState?.openDrawer();
      await tester.pumpAndSettle();

      // AppDrawer is open
      expect(find.byType(AppDrawer), findsOneWidget);

      // Verify version line and build string are NOT present
      expect(find.textContaining('v1.0.0 (Build 102)'), findsNothing);
      expect(find.textContaining('Build 102'), findsNothing);
      expect(find.textContaining('Ready'), findsNothing);

      // Verify theme toggle icon button is NOT at the bottom of the drawer
      expect(find.byTooltip('Toggle Theme'), findsNothing);

      // Verify the 10 navigation items are intact
      expect(find.text('Home / Dashboard'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
    });
  });
}
