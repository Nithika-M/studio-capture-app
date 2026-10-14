import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_recording_app/models/app_models.dart';
import 'package:screen_recording_app/services/preferences_service.dart';
import 'package:screen_recording_app/services/app_notification_service.dart';
import 'package:screen_recording_app/services/recording_service.dart';
import 'package:screen_recording_app/screens/profile_options_screens.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  final List<MethodCall> methodChannelCalls = [];

  setUp(() async {
    methodChannelCalls.clear();
    AppNotificationService.resetDebounce();
    SharedPreferences.setMockInitialValues({});
    await PreferencesService().init();
    await PreferencesService().resetToDefaults();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('screen_recording'), (MethodCall call) async {
      methodChannelCalls.add(call);
      if (call.method == 'playAudioCue') {
        return true;
      }
      if (call.method == 'vibrate') {
        return true;
      }
      if (call.method == 'showSystemNotification') {
        return true;
      }
      if (call.method == 'getStorageInfo') {
        return {
          'totalDeviceBytes': 128 * 1024 * 1024 * 1024,
          'availableDeviceBytes': 500 * 1024 * 1024, // 500 MB (below 1 GB)
          'usedDeviceBytes': 127 * 1024 * 1024 * 1024,
        };
      }
      if (call.method == 'startRecording') {
        return true;
      }
      if (call.method == 'stopRecording') {
        return 'test_output.mp4';
      }
      if (call.method == 'pauseRecording' || call.method == 'resumeRecording') {
        return true;
      }
      if (call.method == 'areNotificationsEnabled') {
        return true;
      }
      if (call.method == 'saveToGallery') {
        return true;
      }
      if (call.method == 'getVideoMetadata') {
        return {
          'durationMs': 5000,
          'width': 1080,
          'height': 1920,
          'thumbnailPath': null,
        };
      }
      return null;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/permissions/methods'), (MethodCall call) async {
      if (call.method == 'requestPermissions') {
        final List<dynamic> permissions = call.arguments as List<dynamic>;
        return Map.fromIterables(permissions, permissions.map((_) => 1)); // 1 = PermissionStatus.granted
      }
      if (call.method == 'checkPermissionStatus') {
        return 1; // 1 = PermissionStatus.granted
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('screen_recording'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/permissions/methods'), null);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('NOTIFICATIONS SCREEN - ALL 6 TOGGLES FUNCTIONAL VERIFICATION', () {
    // ── 1. Start & Stop Chime ────────────────────────────────────────────────
    test('1. Start & Stop Chime: plays audio cues only when ON, silent when OFF', () async {
      final prefs = PreferencesService();

      // When ON: audio cue called on start and stop
      await prefs.setStartStopChime(true);
      expect(prefs.startStopChime, isTrue);

      methodChannelCalls.clear();
      AppNotificationService.playStartChime();
      AppNotificationService.playStopChime();

      final audioCallsOn = methodChannelCalls.where((c) => c.method == 'playAudioCue').toList();
      expect(audioCallsOn.any((c) => c.arguments['type'] == 'start'), isTrue);
      expect(audioCallsOn.any((c) => c.arguments['type'] == 'stop'), isTrue);

      // When OFF: no audio cue called on start or stop
      await prefs.setStartStopChime(false);
      expect(prefs.startStopChime, isFalse);

      methodChannelCalls.clear();
      AppNotificationService.playStartChime();
      AppNotificationService.playStopChime();

      final audioCallsOff = methodChannelCalls.where((c) => c.method == 'playAudioCue').toList();
      expect(audioCallsOff.isEmpty, isTrue, reason: 'Zero audio cues must play when chime toggle is OFF');
    });

    // ── 2. Countdown Sound ───────────────────────────────────────────────────
    test('2. Countdown Sound: plays tick tone only when ON, silent when OFF', () async {
      final prefs = PreferencesService();

      // When ON: tick sound triggers on each countdown step
      await prefs.setCountdownSound(true);
      expect(prefs.countdownSound, isTrue);

      methodChannelCalls.clear();
      AppNotificationService.playCountdownTick();

      final tickCallsOn = methodChannelCalls.where((c) => c.method == 'playAudioCue' && c.arguments['type'] == 'tick').toList();
      expect(tickCallsOn.length, 1);

      // When OFF: countdown runs completely silent
      await prefs.setCountdownSound(false);
      expect(prefs.countdownSound, isFalse);

      methodChannelCalls.clear();
      AppNotificationService.playCountdownTick();

      final tickCallsOff = methodChannelCalls.where((c) => c.method == 'playAudioCue' && c.arguments['type'] == 'tick').toList();
      expect(tickCallsOff.isEmpty, isTrue, reason: 'Countdown tick must be completely silent when toggle is OFF');
    });

    // ── 3. Vibration Feedback ────────────────────────────────────────────────
    test('3. Vibration Feedback: triggers haptic pulse on start/pause/resume/stop when ON, zero vibration when OFF', () async {
      final prefs = PreferencesService();

      // When ON: vibrate invoked on start, pause, resume, and stop
      await prefs.setVibrationFeedback(true);
      expect(prefs.vibrationFeedback, isTrue);

      methodChannelCalls.clear();
      AppNotificationService.playStartChime();
      AppNotificationService.onRecordingPaused();
      AppNotificationService.onRecordingResumed();
      AppNotificationService.playStopChime();

      final vibrateCallsOn = methodChannelCalls.where((c) => c.method == 'vibrate').toList();
      expect(vibrateCallsOn.length, 4, reason: 'Must trigger vibration on start, pause, resume, and stop');

      // When OFF: zero vibration occurs on any action
      await prefs.setVibrationFeedback(false);
      expect(prefs.vibrationFeedback, isFalse);

      methodChannelCalls.clear();
      AppNotificationService.resetDebounce();
      AppNotificationService.playStartChime();
      AppNotificationService.onRecordingPaused();
      AppNotificationService.onRecordingResumed();
      AppNotificationService.playStopChime();

      final vibrateCallsOff = methodChannelCalls.where((c) => c.method == 'vibrate').toList();
      expect(vibrateCallsOff.isEmpty, isTrue, reason: 'Zero vibration must occur when vibration toggle is OFF');
    });

    // ── 4. Low Storage Warning ───────────────────────────────────────────────
    testWidgets('4. Low Storage Warning: displays warning alert when ON (< 1GB), completely suppressed when OFF', (tester) async {
      final prefs = PreferencesService();

      // When ON and storage < 1 GB: alert dialog appears
      await prefs.setLowStorageWarning(true);
      expect(prefs.lowStorageWarning, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => AppNotificationService.checkAndWarnLowStorage(context),
                child: const Text('Check Storage'),
              ),
            ),
          ),
        ),
      );
      await pumpScreen(tester);

      await tester.tap(find.text('Check Storage'));
      await pumpScreen(tester);

      expect(find.text('Low Storage Warning'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await pumpScreen(tester);

      // When OFF: alert dialog is never shown even with low storage (< 1 GB)
      await prefs.setLowStorageWarning(false);
      expect(prefs.lowStorageWarning, isFalse);

      await tester.tap(find.text('Check Storage'));
      await pumpScreen(tester);

      expect(find.text('Low Storage Warning'), findsNothing, reason: 'Warning must be suppressed when toggle is OFF');
    });

    // ── 5. Export & Trim Complete Notification ───────────────────────────────
    testWidgets('5. Export & Trim Complete: shows notification when ON, suppressed when OFF', (tester) async {
      final prefs = PreferencesService();

      // When ON: triggers notification and in-app alert
      await prefs.setExportTrimComplete(true);
      expect(prefs.exportTrimComplete, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => AppNotificationService.notifyExportComplete(context, label: 'Trim finished successfully!'),
                child: const Text('Export Action'),
              ),
            ),
          ),
        ),
      );
      await pumpScreen(tester);

      methodChannelCalls.clear();
      await tester.tap(find.text('Export Action'));
      await pumpScreen(tester);

      expect(find.text('Trim finished successfully!'), findsOneWidget);
      final notifCallsOn = methodChannelCalls.where((c) => c.method == 'showSystemNotification').toList();
      expect(notifCallsOn.length, 1);

      // When OFF: no notification or alert
      await prefs.setExportTrimComplete(false);
      expect(prefs.exportTrimComplete, isFalse);

      methodChannelCalls.clear();
      await tester.tap(find.text('Export Action'));
      await pumpScreen(tester);

      final notifCallsOff = methodChannelCalls.where((c) => c.method == 'showSystemNotification').toList();
      expect(notifCallsOff.isEmpty, isTrue, reason: 'Zero notifications must appear when toggle is OFF');
    });

    // ── 6. Floating Controls Notification ────────────────────────────────────
    test('6. Floating Controls Notification: config injects floatingNotification state to native service', () async {
      final prefs = PreferencesService();

      // When ON: floatingNotification is true in recording config
      await prefs.setFloatingNotification(true);
      expect(prefs.floatingNotification, isTrue);

      final settings = RecordingSettings(
        mode: RecordingMode.screen,
        resolution: '1080p',
        fps: 60,
        bitrate: 16,
        orientation: 'Auto',
        audioSource: 'Device Audio',
        showFacecam: false,
        facecamShape: 'Square',
        countdown: 'Off',
        showTouches: false,
        floatingBubble: false,
        shakeToStop: false,
      );

      methodChannelCalls.clear();
      await RecordingService().startRecording(settings: settings, enableAudio: true, enableVideo: true);

      final startCallOn = methodChannelCalls.firstWhere((c) => c.method == 'startRecording');
      expect(startCallOn.arguments['floatingNotification'], isTrue,
          reason: 'floatingNotification must be true in startRecording config when toggle is ON');

      // When OFF: floatingNotification is false in recording config
      await prefs.setFloatingNotification(false);
      expect(prefs.floatingNotification, isFalse);

      methodChannelCalls.clear();
      await RecordingService().startRecording(settings: settings, enableAudio: true, enableVideo: true);

      final startCallOff = methodChannelCalls.firstWhere((c) => c.method == 'startRecording');
      expect(startCallOff.arguments['floatingNotification'], isFalse,
          reason: 'floatingNotification must be false in startRecording config when toggle is OFF');
    });

    // ── Settings Screen UI & Persistence Verification ────────────────────────
    testWidgets('7. NotificationsSettingsScreen renders all 6 switches and toggles persist correctly', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: NotificationsSettingsScreen()));
      await pumpScreen(tester);

      expect(find.text('Start & Stop Chime'), findsOneWidget);
      expect(find.text('Countdown Sound'), findsOneWidget);
      expect(find.text('Vibration Feedback'), findsOneWidget);
      expect(find.text('Low Storage Warning'), findsOneWidget);
      expect(find.text('Export & Trim Complete'), findsOneWidget);
      expect(find.text('Floating Controls Notification'), findsOneWidget);

      final switches = find.byType(Switch);
      expect(switches, findsNWidgets(6));

      // Toggle first switch (Start & Stop Chime) OFF
      await tester.tap(switches.at(0));
      await pumpScreen(tester);
      expect(PreferencesService().startStopChime, isFalse);

      // Toggle first switch back ON
      await tester.tap(switches.at(0));
      await pumpScreen(tester);
      expect(PreferencesService().startStopChime, isTrue);
    });
  });
}
