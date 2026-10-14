import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_recording_app/models/app_models.dart';
import 'package:screen_recording_app/services/preferences_service.dart';
import 'package:screen_recording_app/services/recording_service.dart';
import 'package:screen_recording_app/screens/profile_options_screens.dart';
import 'package:screen_recording_app/screens/recording_setup_screen.dart';
import 'package:screen_recording_app/screens/permission_request_screen.dart';
import 'package:screen_recording_app/screens/active_recording_screen.dart';
import 'package:screen_recording_app/widgets/facecam_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> channelCalls = [];
  final List<String> requestedPermissions = [];
  Directory? tempDir;

  setUp(() async {
    channelCalls.clear();
    requestedPermissions.clear();
    SharedPreferences.setMockInitialValues({});
    await PreferencesService().init();
    await PreferencesService().resetToDefaults();
    RecordingService().clearSavedRecordings();

    tempDir = Directory.systemTemp.createTempSync('facecam_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('screen_recording_app/recording'),
            (MethodCall call) async {
      channelCalls.add(call);
      if (call.method == 'openEmailClient') {
        return true;
      }
      return null;
    });

    final dummyFile = File('${tempDir!.path}/test_recording.mp4');
    dummyFile.writeAsBytesSync(List.filled(1024, 0));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('screen_recording'),
            (MethodCall call) async {
      channelCalls.add(call);
      if (call.method == 'requestPermission') {
        return true;
      }
      if (call.method == 'startRecording') {
        return true;
      }
      if (call.method == 'stopRecording') {
        return dummyFile.path;
      }
      if (call.method == 'getRecordingStatus') {
        return {'isRecording': true};
      }
      if (call.method == 'getVideoMetadata') {
        return {'durationMs': 5000, 'width': 1080, 'height': 2400};
      }
      return null;
    });

    // Mock permission_handler channel to track which permissions are requested
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/permissions/methods'),
            (MethodCall call) async {
      if (call.method == 'requestPermissions') {
        final list = List<int>.from(call.arguments as List);
        for (final p in list) {
          if (p == 1) requestedPermissions.add('camera');
          if (p == 7) requestedPermissions.add('microphone');
          if (p == 9) requestedPermissions.add('storage');
        }
        return Map.fromIterables(list, list.map((_) => 1)); // 1 = granted
      }
      if (call.method == 'checkPermissionStatus') {
        return 1; // granted
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('screen_recording_app/recording'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('screen_recording'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/permissions/methods'), null);

    try {
      if (tempDir != null && tempDir!.existsSync()) {
        tempDir!.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('FEATURE 1: Contact Button Single-Step "Open with" Selection', () {
    testWidgets('Tapping Contact shows ONE simple "Open with" chooser with Gmail and Outlook',
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

      // Initially no chooser is open
      expect(find.text('Open with'), findsNothing);

      // 1. Exactly ONE tap on Contact button
      final contactBtn = find.widgetWithText(ElevatedButton, 'Contact');
      expect(contactBtn, findsOneWidget);
      await tester.tap(contactBtn);
      await tester.pumpAndSettle();

      // 2. Exactly ONE chooser titled "Open with" appears listing Gmail and Outlook
      expect(find.text('Open with'), findsOneWidget);
      expect(find.text('Gmail'), findsOneWidget);
      expect(find.text('Outlook'), findsOneWidget);

      // 3. Exactly ONE tap on Gmail
      await tester.tap(find.text('Gmail'));
      await tester.pumpAndSettle();

      // 4. Directly triggers launch with to: contact@ispcorp.in without any secondary dialog
      expect(find.text('Open with'), findsNothing);
      final emailCalls = channelCalls.where((c) => c.method == 'openEmailClient').toList();
      expect(emailCalls.length, 1);
      expect(emailCalls.first.arguments['client'], 'gmail');
      expect(emailCalls.first.arguments['to'], 'contact@ispcorp.in');
      expect(emailCalls.first.arguments['subject'], 'Studio Capture — Support Request');
    });

    testWidgets('Tapping Contact and selecting Outlook launches Outlook directly on single tap',
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

      // Tap Contact
      await tester.tap(find.widgetWithText(ElevatedButton, 'Contact'));
      await tester.pumpAndSettle();

      expect(find.text('Open with'), findsOneWidget);
      expect(find.text('Outlook'), findsOneWidget);

      // Single tap on Outlook
      await tester.tap(find.text('Outlook'));
      await tester.pumpAndSettle();

      // Directly triggers Outlook
      final emailCalls = channelCalls.where((c) => c.method == 'openEmailClient').toList();
      expect(emailCalls.length, 1);
      expect(emailCalls.first.arguments['client'], 'outlook');
      expect(emailCalls.first.arguments['to'], 'contact@ispcorp.in');
    });
  });

  group('FEATURE 2: Facecam Picture-in-Picture Toggle Reliability', () {
    testWidgets('Permission test: When Facecam toggle is ON -> Camera permission IS requested',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settings = RecordingSettings(
        mode: RecordingMode.screen,
        resolution: '1080p',
        fps: 60,
        bitrate: 16.0,
        orientation: 'Portrait',
        audioSource: 'Internal + Mic',
        showFacecam: true, // ON
        facecamShape: 'Square (PiP)',
        countdown: 'Off',
        showTouches: false,
        floatingBubble: false,
        shakeToStop: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PermissionRequestScreen(settings: settings),
        ),
      );
      await tester.pump();

      final allowBtn = find.text('Allow & Start Recording');
      expect(allowBtn, findsOneWidget);
      await tester.tap(allowBtn);
      await tester.pump(const Duration(milliseconds: 100));

      expect(requestedPermissions.contains('camera'), isTrue);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Permission test: When Facecam toggle is OFF -> Camera permission is NOT requested',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      requestedPermissions.clear();

      final settings = RecordingSettings(
        mode: RecordingMode.screen,
        resolution: '1080p',
        fps: 60,
        bitrate: 16.0,
        orientation: 'Portrait',
        audioSource: 'Internal + Mic',
        showFacecam: false, // OFF
        facecamShape: 'Square (PiP)',
        countdown: 'Off',
        showTouches: false,
        floatingBubble: false,
        shakeToStop: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PermissionRequestScreen(settings: settings),
        ),
      );
      await tester.pump();

      final allowBtn = find.text('Allow & Start Recording');
      expect(allowBtn, findsOneWidget);
      await tester.tap(allowBtn);
      await tester.pump(const Duration(milliseconds: 100));

      expect(requestedPermissions.contains('camera'), isFalse);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Active Recording: When toggle is ON -> Live FacecamWindow is rendered on screen',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settings = RecordingSettings(
        mode: RecordingMode.screen,
        resolution: '1080p',
        fps: 60,
        bitrate: 16.0,
        orientation: 'Portrait',
        audioSource: 'Internal + Mic',
        showFacecam: true, // ON
        facecamShape: 'Square (PiP)',
        countdown: 'Off',
        showTouches: false,
        floatingBubble: false,
        shakeToStop: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ActiveRecordingScreen(settings: settings),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      // Live facecam window MUST be present on screen
      expect(find.byType(FacecamWindow), findsOneWidget);
    });

    testWidgets('Active Recording: When toggle is OFF -> Absolutely NO FacecamWindow is rendered',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settings = RecordingSettings(
        mode: RecordingMode.facecam, // Even if mode was facecam, toggle OFF must govern
        resolution: '1080p',
        fps: 60,
        bitrate: 16.0,
        orientation: 'Portrait',
        audioSource: 'Internal + Mic',
        showFacecam: false, // OFF
        facecamShape: 'Square (PiP)',
        countdown: 'Off',
        showTouches: false,
        floatingBubble: false,
        shakeToStop: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ActiveRecordingScreen(settings: settings),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      // Absolutely NO facecam window on screen
      expect(find.byType(FacecamWindow), findsNothing);
    });

    testWidgets('Sequential Reliability: RecordingService accurately composited hasFacecam across 3 sessions (ON -> OFF -> ON)',
        (WidgetTester tester) async {
      final settingsOn = RecordingSettings(
        mode: RecordingMode.screen,
        resolution: '1080p',
        fps: 60,
        bitrate: 16.0,
        orientation: 'Portrait',
        audioSource: 'Internal + Mic',
        showFacecam: true,
        facecamShape: 'Circle Head',
        countdown: 'Off',
        showTouches: false,
        floatingBubble: false,
        shakeToStop: false,
      );

      final settingsOff = RecordingSettings(
        mode: RecordingMode.screen,
        resolution: '1080p',
        fps: 60,
        bitrate: 16.0,
        orientation: 'Portrait',
        audioSource: 'Internal + Mic',
        showFacecam: false,
        facecamShape: 'Circle Head',
        countdown: 'Off',
        showTouches: false,
        floatingBubble: false,
        shakeToStop: false,
      );

      // --- Session 1: ON ---
      await RecordingService().startRecording(
        settings: settingsOn,
        enableAudio: true,
        enableVideo: true,
      );
      expect(RecordingService().showFacecam, isTrue);
      await tester.runAsync(() => RecordingService().stopRecording());
      expect(RecordingService().savedMediaItems.first.hasFacecam, isTrue);

      // --- Session 2: OFF ---
      await RecordingService().startRecording(
        settings: settingsOff,
        enableAudio: true,
        enableVideo: true,
      );
      expect(RecordingService().showFacecam, isFalse);
      await tester.runAsync(() => RecordingService().stopRecording());
      expect(RecordingService().savedMediaItems.first.hasFacecam, isFalse);

      // --- Session 3: ON again ---
      await RecordingService().startRecording(
        settings: settingsOn,
        enableAudio: true,
        enableVideo: true,
      );
      expect(RecordingService().showFacecam, isTrue);
      await tester.runAsync(() => RecordingService().stopRecording());
      expect(RecordingService().savedMediaItems.first.hasFacecam, isTrue);
    });

    testWidgets('RecordingSetupScreen persists Facecam toggle changes immediately to PreferencesService',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = PreferencesService();
      await prefs.setEnableFacecam(true);
      expect(prefs.enableFacecam, isTrue);

      await tester.pumpWidget(
        const MaterialApp(
          home: RecordingSetupScreen(selectedMode: RecordingMode.screen),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Find the Facecam Picture-in-Picture toggle row
      expect(find.text('Facecam Picture-in-Picture'), findsOneWidget);
      expect(find.text('PIP Active'), findsOneWidget);

      // Tap on Facecam Picture-in-Picture toggle to turn it OFF
      await tester.tap(find.text('Facecam Picture-in-Picture'));
      await tester.pump(const Duration(milliseconds: 300));

      // Verified: Preference is now false
      expect(prefs.enableFacecam, isFalse);
      expect(find.text('PIP Active'), findsNothing);

      // Tap again to turn it back ON
      await tester.tap(find.text('Facecam Picture-in-Picture'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(prefs.enableFacecam, isTrue);
      expect(find.text('PIP Active'), findsOneWidget);
    });
  });
}
