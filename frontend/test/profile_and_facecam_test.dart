import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_recording_app/models/app_models.dart';
import 'package:screen_recording_app/screens/profile_screen.dart';
import 'package:screen_recording_app/screens/main_wrapper_screen.dart';
import 'package:screen_recording_app/screens/ui_guide_screen.dart';
import 'package:screen_recording_app/screens/recording_completed_screen.dart';
import 'package:screen_recording_app/widgets/app_drawer.dart';
import 'package:screen_recording_app/widgets/facecam_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Profile Screen & Assertion Bug Fix Tests', () {
    testWidgets('ProfileScreen loads without Material assertion failure and displays all sections', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: ProfileScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Header info
      expect(find.text('Alex Rivera'), findsOneWidget);
      expect(find.text('PRO CREATOR'), findsOneWidget);

      // Section 1: Recording Defaults, Audio & Inputs, Facecam & Overlay
      expect(find.text('Recording Defaults'), findsOneWidget);
      expect(find.text('Audio & Inputs'), findsOneWidget);
      expect(find.text('Facecam & Overlay'), findsOneWidget);

      // Section 2: Storage & Export
      expect(find.text('Storage & Export'), findsOneWidget);
      expect(find.text('Cloud Vault & Backup'), findsOneWidget);

      // Section 3: Appearance & System
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Notifications & Alerts'), findsOneWidget);
      expect(find.text('Privacy & Security'), findsOneWidget);

      // Section 4: Guides, Support & Legal
      expect(find.text('UI Guide & Tour'), findsOneWidget);
      expect(find.text('Help & Support'), findsOneWidget);
      expect(find.text('About & Legal'), findsOneWidget);
    });

    testWidgets('MainWrapperScreen navigates to Profile tab without crashing', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: MainWrapperScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Tap on Profile tab in bottom nav bar
      await tester.tap(find.byIcon(Icons.person_rounded).last);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Alex Rivera'), findsOneWidget);
      expect(find.text('Recording Defaults'), findsOneWidget);
    });
  });

  group('UI Guide Feature Tests', () {
    testWidgets('AppDrawer contains UI Guide option that can be tapped', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 380,
              child: AppDrawer(currentRoute: 'home'),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('UI Guide'), findsOneWidget);
      expect(find.text('Tour'), findsOneWidget);
    });

    testWidgets('UiGuideScreen renders walkthrough steps and supports navigation', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: UiGuideScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('UI & Feature Guide'), findsOneWidget);
      expect(find.text('Home & Instant Capture'), findsOneWidget);
      expect(find.text('Step 1 of 7'), findsOneWidget);

      // Tap 'Next Step'
      await tester.tap(find.text('Next Step'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Step 2 of 7'), findsOneWidget);
      expect(find.text('5 Studio Recording Profiles'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
    });
  });

  group('Facecam Window Shape & Overlay Tests', () {
    test('Facecam shape parsing correctly identifies circle, roundedRect, and square', () {
      expect(parseFacecamShape('Circle Head'), FacecamShapeType.circle);
      expect(parseFacecamShape('Circle (PiP)'), FacecamShapeType.circle);
      expect(parseFacecamShape('Rounded Rect'), FacecamShapeType.roundedRect);
      expect(parseFacecamShape('Rounded Rectangle (PiP)'), FacecamShapeType.roundedRect);
      expect(parseFacecamShape('Square (PiP)'), FacecamShapeType.square);
      expect(parseFacecamShape('Square'), FacecamShapeType.square);
      expect(parseFacecamShape(null), FacecamShapeType.circle);
    });

    testWidgets('FacecamWindow renders circle, rounded rectangle, and square shapes', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                FacecamWindow(shape: 'Circle Head', size: 64, isLive: true),
                FacecamWindow(shape: 'Rounded Rectangle (PiP)', size: 64, isLive: false),
                FacecamWindow(shape: 'Square (PiP)', size: 64, isLive: false),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(FacecamWindow), findsNWidgets(3));
      expect(find.byType(ClipOval), findsOneWidget);
      expect(find.byType(ClipRRect), findsNWidgets(2));
      expect(find.text('● LIVE'), findsOneWidget);
      expect(find.text('PiP'), findsNWidgets(2));
    });

    testWidgets('RecordingCompletedScreen shows composited facecam overlay when mode is facecam', (WidgetTester tester) async {
      final settings = RecordingSettings(
        mode: RecordingMode.facecam,
        resolution: '1080p',
        fps: 60,
        bitrate: 16.0,
        orientation: 'Portrait',
        audioSource: 'Microphone',
        showFacecam: true,
        facecamShape: 'Rounded Rect',
        countdown: '3s',
        showTouches: true,
        floatingBubble: true,
        shakeToStop: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RecordingCompletedScreen(
            selectedMode: RecordingMode.facecam,
            duration: 15,
            filePath: 'Facecam_Test_PiP.mp4',
            settings: settings,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('PiP • Rounded Rect'), findsOneWidget);
      expect(find.byType(FacecamWindow), findsOneWidget);
    });
  });
}
