import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_recording_app/models/app_models.dart';
import 'package:screen_recording_app/services/preferences_service.dart';
import 'package:screen_recording_app/services/recording_auth_service.dart';
import 'package:screen_recording_app/services/recording_service.dart';
import 'package:screen_recording_app/screens/recording_setup_screen.dart';
import 'package:screen_recording_app/screens/permission_request_screen.dart';
import 'package:screen_recording_app/screens/countdown_overlay_screen.dart';
import 'package:screen_recording_app/screens/active_recording_screen.dart';
import 'package:screen_recording_app/screens/recording_completed_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> methodCalls = [];
  bool biometricAuthSuccess = false;

  setUp(() async {
    methodCalls.clear();
    biometricAuthSuccess = false;
    RecordingAuthService.resetSessionAuth();

    SharedPreferences.setMockInitialValues({});
    await PreferencesService().init();
    await PreferencesService().resetToDefaults();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('screen_recording'), (MethodCall call) async {
      methodCalls.add(call);
      if (call.method == 'authenticateBiometric') {
        return biometricAuthSuccess;
      }
      if (call.method == 'startRecording') {
        return true;
      }
      if (call.method == 'stopRecording') {
        return 'test_recording.mp4';
      }
      if (call.method == 'pauseRecording' ||
          call.method == 'resumeRecording' ||
          call.method == 'setAudioMuted' ||
          call.method == 'setVideoEnabled' ||
          call.method == 'setFacecamEnabled' ||
          call.method == 'getStorageInfo') {
        return true;
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
        return 1;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('screen_recording'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/permissions/methods'), null);
    RecordingAuthService.resetSessionAuth();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  RecordingSettings testRecordingSettings({String countdown = 'Off'}) {
    return RecordingSettings(
      mode: RecordingMode.screen,
      resolution: '1080p',
      fps: 60,
      bitrate: 16,
      orientation: 'Auto',
      audioSource: 'Device Audio',
      showFacecam: false,
      facecamShape: 'Square',
      countdown: countdown,
      showTouches: false,
      floatingBubble: false,
      shakeToStop: false,
    );
  }

  group('BIOMETRIC RECORDING GATE TESTS', () {
    testWidgets('1. When App Lock is OFF, starting recording prompts zero biometrics', (tester) async {
      final prefs = PreferencesService();
      await prefs.setBiometricLock(false);
      expect(prefs.biometricLock, isFalse);

      await tester.pumpWidget(
        const MaterialApp(
          home: RecordingSetupScreen(selectedMode: RecordingMode.screen),
        ),
      );
      await pumpScreen(tester);

      // Tap "Start Recording"
      final startBtn = find.text('Start Recording');
      expect(startBtn, findsOneWidget);
      await tester.tap(startBtn);
      await pumpScreen(tester);

      // Verify no biometric call was made
      final biometricCalls = methodCalls.where((c) => c.method == 'authenticateBiometric').toList();
      expect(biometricCalls.length, 0);

      // Verify navigation proceeded to PermissionRequestScreen
      expect(find.byType(PermissionRequestScreen), findsOneWidget);
    });

    testWidgets('2. When App Lock is ON, failed/cancelled auth blocks recording and stays on setup screen', (tester) async {
      final prefs = PreferencesService();
      await prefs.setBiometricLock(true);
      expect(prefs.biometricLock, isTrue);

      biometricAuthSuccess = false; // Simulate user cancel or auth failure

      await tester.pumpWidget(
        const MaterialApp(
          home: RecordingSetupScreen(selectedMode: RecordingMode.screen),
        ),
      );
      await pumpScreen(tester);

      final startBtn = find.text('Start Recording');
      expect(startBtn, findsOneWidget);
      await tester.tap(startBtn);
      await pumpScreen(tester);

      // Verify authenticateBiometric was called exactly once
      final biometricCalls = methodCalls.where((c) => c.method == 'authenticateBiometric').toList();
      expect(biometricCalls.length, 1);

      // Verify recording did NOT start and screen stays on RecordingSetupScreen
      expect(RecordingAuthService.isSessionAuthenticated, isFalse);
      expect(find.byType(RecordingSetupScreen), findsOneWidget);
      expect(find.byType(PermissionRequestScreen), findsNothing);
      expect(find.text('Authentication required to start recording.'), findsOneWidget);
    });

    testWidgets('3. When App Lock is ON, successful auth prompts exactly ONCE and never again for that session', (tester) async {
      final prefs = PreferencesService();
      await prefs.setBiometricLock(true);
      expect(prefs.biometricLock, isTrue);

      biometricAuthSuccess = true;

      await tester.pumpWidget(
        const MaterialApp(
          home: RecordingSetupScreen(selectedMode: RecordingMode.screen),
        ),
      );
      await pumpScreen(tester);

      // 3a. Tap Start Recording -> Biometric prompt appears exactly ONCE
      final startBtn = find.text('Start Recording');
      await tester.tap(startBtn);
      await pumpScreen(tester);

      final biometricCallsAfterStart = methodCalls.where((c) => c.method == 'authenticateBiometric').toList();
      expect(biometricCallsAfterStart.length, 1, reason: 'Must prompt exactly ONCE on start recording');
      expect(RecordingAuthService.isSessionAuthenticated, isTrue);
      expect(find.byType(PermissionRequestScreen), findsOneWidget);

      // 3b. Verify subsequent permission request does not prompt again
      final allowBtn = find.text('Allow & Start Recording');
      expect(allowBtn, findsOneWidget);
      await tester.tap(allowBtn);
      await pumpScreen(tester);

      final biometricCallsAfterPerm = methodCalls.where((c) => c.method == 'authenticateBiometric').toList();
      expect(biometricCallsAfterPerm.length, 1, reason: 'Must NOT prompt again on permission grant');

      // 3c. During countdown, zero additional prompts
      final settings = testRecordingSettings();
      await tester.pumpWidget(
        MaterialApp(
          home: CountdownOverlayScreen(settings: settings),
        ),
      );
      await pumpScreen(tester);

      final biometricCallsAfterCountdown = methodCalls.where((c) => c.method == 'authenticateBiometric').toList();
      expect(biometricCallsAfterCountdown.length, 1, reason: 'Must NOT prompt again during countdown');

      // 3d. In ActiveRecordingScreen (pause/resume/mute/stop), zero additional prompts
      await tester.pumpWidget(
        MaterialApp(
          home: ActiveRecordingScreen(settings: settings),
        ),
      );
      await pumpScreen(tester);

      // Pause recording
      await RecordingService().pauseRecording();
      await pumpScreen(tester);

      // Resume recording
      await RecordingService().resumeRecording();
      await pumpScreen(tester);

      // Mute audio
      await RecordingService().setAudioMuted(true);
      await pumpScreen(tester);

      final biometricCallsDuringActive = methodCalls.where((c) => c.method == 'authenticateBiometric').toList();
      expect(biometricCallsDuringActive.length, 1, reason: 'Must NOT prompt during active recording controls');

      // 3e. In RecordingCompletedScreen, zero additional prompts
      await tester.pumpWidget(
        MaterialApp(
          home: RecordingCompletedScreen(
            selectedMode: RecordingMode.screen,
            duration: 10,
            filePath: '/dummy/path.mp4',
            settings: settings,
          ),
        ),
      );
      await pumpScreen(tester);

      final biometricCallsAfterReview = methodCalls.where((c) => c.method == 'authenticateBiometric').toList();
      expect(biometricCallsAfterReview.length, 1, reason: 'Must NOT prompt on review screen');

      // Stop recording clears session auth
      await RecordingService().stopRecording();
      expect(RecordingAuthService.isSessionAuthenticated, isFalse);
    });

    testWidgets('4. Fresh biometric prompt triggers again for a second new recording session', (tester) async {
      final prefs = PreferencesService();
      await prefs.setBiometricLock(true);
      biometricAuthSuccess = true;

      // Session 1: Start and complete
      await tester.pumpWidget(
        const MaterialApp(
          home: RecordingSetupScreen(selectedMode: RecordingMode.screen),
        ),
      );
      await pumpScreen(tester);

      await tester.tap(find.text('Start Recording'));
      await pumpScreen(tester);

      expect(methodCalls.where((c) => c.method == 'authenticateBiometric').length, 1);
      expect(RecordingAuthService.isSessionAuthenticated, isTrue);

      // Stop session 1
      await RecordingService().stopRecording();
      expect(RecordingAuthService.isSessionAuthenticated, isFalse);

      // Session 2: Fresh "Start Recording" action
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: const RecordingSetupScreen(selectedMode: RecordingMode.screen),
        ),
      );
      await pumpScreen(tester);

      await tester.tap(find.text('Start Recording'));
      await pumpScreen(tester);

      // Biometric prompt was invoked a 2nd time for the 2nd session
      expect(methodCalls.where((c) => c.method == 'authenticateBiometric').length, 2,
          reason: 'Must prompt again for the second new recording session');
      expect(RecordingAuthService.isSessionAuthenticated, isTrue);
    });
  });
}
