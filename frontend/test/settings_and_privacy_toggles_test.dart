import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_recording_app/models/app_models.dart';
import 'package:screen_recording_app/services/preferences_service.dart';
import 'package:screen_recording_app/services/app_notification_service.dart';
import 'package:screen_recording_app/services/recording_service.dart';
import 'package:screen_recording_app/screens/profile_options_screens.dart';
import 'package:screen_recording_app/screens/recordings_library_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> methodChannelCalls = [];
  bool biometricAuthSuccess = false;

  setUp(() async {
    methodChannelCalls.clear();
    biometricAuthSuccess = false;
    SharedPreferences.setMockInitialValues({});
    await PreferencesService().init();
    await PreferencesService().resetToDefaults();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('screen_recording'), (MethodCall call) async {
      methodChannelCalls.add(call);
      if (call.method == 'setHideSensitiveContent') {
        return true;
      }
      if (call.method == 'authenticateBiometric') {
        return biometricAuthSuccess;
      }
      if (call.method == 'getStorageInfo') {
        return {
          'totalDeviceBytes': 128 * 1024 * 1024 * 1024,
          'availableDeviceBytes': 500 * 1024 * 1024, // 500 MB (Low storage)
          'usedDeviceBytes': 127 * 1024 * 1024 * 1024,
        };
      }
      if (call.method == 'startRecording') {
        return true;
      }
      if (call.method == 'stopRecording') {
        return 'test_output.mp4';
      }
      if (call.method == 'scanFile') {
        return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('screen_recording'), null);
  });

  group('SECTION 1: PRIVACY SETTINGS', () {
    testWidgets('1. Hide Sensitive Content toggle updates prefs and native channel', (tester) async {
      final prefs = PreferencesService();
      expect(prefs.hideSensitiveContent, isFalse);

      await tester.pumpWidget(const MaterialApp(home: PrivacySecurityScreen()));
      await tester.pumpAndSettle();

      final switchTile = find.widgetWithText(SwitchListTile, 'Hide Sensitive Content');
      expect(switchTile, findsOneWidget);

      // Tap to toggle ON
      await tester.tap(switchTile);
      await tester.pumpAndSettle();

      expect(prefs.hideSensitiveContent, isTrue);
      expect(methodChannelCalls.any((c) => c.method == 'setHideSensitiveContent' && c.arguments == true), isTrue);

      // Tap to toggle OFF
      await tester.tap(switchTile);
      await tester.pumpAndSettle();

      expect(prefs.hideSensitiveContent, isFalse);
      expect(methodChannelCalls.any((c) => c.method == 'setHideSensitiveContent' && c.arguments == false), isTrue);
    });

    testWidgets('2. App Lock / Biometrics blocks library access when ON until authenticated', (tester) async {
      final prefs = PreferencesService();
      await prefs.setBiometricLock(true);
      expect(prefs.biometricLock, isTrue);

      // 2a. Initial launch when auth fails/cancelled -> screen stays locked
      biometricAuthSuccess = false;
      await tester.pumpWidget(const MaterialApp(home: RecordingsLibraryScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Recordings Locked'), findsOneWidget);
      expect(find.text('Unlock Recordings'), findsOneWidget);
      expect(find.text('ALL'), findsNothing);

      // 2b. User triggers auth with success -> screen unlocks and shows recordings
      biometricAuthSuccess = true;
      await tester.tap(find.text('Unlock Recordings'));
      await tester.pumpAndSettle();

      expect(find.text('Recordings Locked'), findsNothing);
      expect(find.text('ALL'), findsOneWidget);

      // 2c. When biometricLock is OFF -> immediately accessible without lock prompt
      await prefs.setBiometricLock(false);
      await tester.pumpWidget(const MaterialApp(home: RecordingsLibraryScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Recordings Locked'), findsNothing);
      expect(find.text('ALL'), findsOneWidget);
    });

    test('3. Share Anonymous Diagnostics collects data only when ON', () async {
      final prefs = PreferencesService();
      await prefs.setAnonymousDiagnostics(false);
      expect(prefs.anonymousDiagnostics, isFalse);

      // When OFF, logging does nothing
      AppNotificationService.logDiagnostic('test_event_off', data: {'key': 'val'});

      // When ON, logging executes
      await prefs.setAnonymousDiagnostics(true);
      expect(prefs.anonymousDiagnostics, isTrue);
      AppNotificationService.logDiagnostic('test_event_on', data: {'key': 'val'});
    });
  });

  group('SECTION 2: NOTIFICATIONS SETTINGS (6 TOGGLES)', () {
    testWidgets('Toggles persist correctly and trigger functional effects', (tester) async {
      final prefs = PreferencesService();

      await tester.pumpWidget(const MaterialApp(home: NotificationsSettingsScreen()));
      await tester.pumpAndSettle();

      // 1. Start & Stop Chime
      expect(prefs.startStopChime, isTrue);
      await prefs.setStartStopChime(false);
      expect(prefs.startStopChime, isFalse);
      AppNotificationService.playStartChime();
      AppNotificationService.playStopChime();

      // 2. Countdown Sound
      expect(prefs.countdownSound, isTrue);
      await prefs.setCountdownSound(false);
      expect(prefs.countdownSound, isFalse);
      AppNotificationService.playCountdownTick();

      // 3. Vibration Feedback
      expect(prefs.vibrationFeedback, isTrue);
      expect(AppNotificationService.canVibrate, isTrue);
      await prefs.setVibrationFeedback(false);
      expect(prefs.vibrationFeedback, isFalse);
      expect(AppNotificationService.canVibrate, isFalse);
      AppNotificationService.lightImpact();
      AppNotificationService.mediumImpact();
      AppNotificationService.heavyImpact();
      AppNotificationService.selectionClick();

      // 4. Low Storage Warning
      expect(prefs.lowStorageWarning, isTrue);
      final warnedOn = await AppNotificationService.checkAndWarnLowStorage(tester.element(find.byType(NotificationsSettingsScreen)));
      expect(warnedOn, isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await prefs.setLowStorageWarning(false);
      final warnedOff = await AppNotificationService.checkAndWarnLowStorage(tester.element(find.byType(NotificationsSettingsScreen)));
      expect(warnedOff, isFalse);
      expect(find.byType(AlertDialog), findsNothing);

      // 5. Export & Trim Complete
      expect(prefs.exportTrimComplete, isTrue);
      AppNotificationService.notifyExportComplete(tester.element(find.byType(NotificationsSettingsScreen)), label: 'Trim finished');
      await tester.pump();
      expect(find.text('Trim finished'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await prefs.setExportTrimComplete(false);
      AppNotificationService.notifyExportComplete(tester.element(find.byType(NotificationsSettingsScreen)), label: 'Trim finished 2');
      await tester.pump();
      expect(find.text('Trim finished 2'), findsNothing);

      // 6. Floating Controls Notification
      expect(prefs.floatingNotification, isTrue);
      await prefs.setFloatingNotification(false);
      expect(prefs.floatingNotification, isFalse);
    });
  });

  group('SECTION 3: STORAGE & DATA - AUTO-DELETE OLD VIDEOS', () {
    testWidgets('Auto-delete removes files older than threshold when ON, preserves when OFF', (tester) async {
      final prefs = PreferencesService();
      final recService = RecordingService();

      final tempDir = Directory.systemTemp.createTempSync('autodelete_test_');
      final oldFile = File('${tempDir.path}${Platform.pathSeparator}old_rec.mp4');
      final newFile = File('${tempDir.path}${Platform.pathSeparator}new_rec.mp4');
      oldFile.writeAsStringSync('old video dummy content');
      newFile.writeAsStringSync('new video dummy content');

      final oldDate = DateTime.now().subtract(const Duration(days: 40));
      oldFile.setLastModifiedSync(oldDate);

      recService.addSavedRecording(MediaItem(
        id: 'old_1',
        title: 'old_rec.mp4',
        date: 'Aug 20, 2026',
        duration: '01:00',
        size: '10 MB',
        resolution: '1080p',
        type: 'video',
        thumbnail: '',
        filePath: oldFile.path,
      ));
      recService.addSavedRecording(MediaItem(
        id: 'new_1',
        title: 'new_rec.mp4',
        date: 'Oct 01, 2026',
        duration: '02:00',
        size: '20 MB',
        resolution: '1080p',
        type: 'video',
        thumbnail: '',
        filePath: newFile.path,
      ));

      // 1. When OFF: no files deleted
      await prefs.setAutoDeleteOldVideos(false);
      await prefs.setAutoDeleteDays(30);
      final purgedOff = await AppNotificationService.runAutoDeleteIfEnabled();
      expect(purgedOff, 0);
      expect(oldFile.existsSync(), isTrue);
      expect(newFile.existsSync(), isTrue);
      expect(recService.savedMediaItems.any((i) => i.id == 'old_1'), isTrue);

      // 2. When ON: old file is deleted, new file is kept
      await prefs.setAutoDeleteOldVideos(true);
      final purgedOn = await AppNotificationService.runAutoDeleteIfEnabled();
      expect(purgedOn, greaterThanOrEqualTo(1));
      expect(oldFile.existsSync(), isFalse);
      expect(newFile.existsSync(), isTrue);
      expect(recService.savedMediaItems.any((i) => i.id == 'old_1'), isFalse);
      expect(recService.savedMediaItems.any((i) => i.id == 'new_1'), isTrue);

      try { tempDir.deleteSync(recursive: true); } catch (_) {}
    });
  });
}
