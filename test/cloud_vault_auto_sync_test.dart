import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_recording_app/models/app_models.dart';
import 'package:screen_recording_app/services/preferences_service.dart';
import 'package:screen_recording_app/services/cloud_vault_service.dart';
import 'package:screen_recording_app/services/recording_service.dart';
import 'package:screen_recording_app/screens/cloud_vault_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<String> nativeInvocations = [];
  Directory? tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService().init();
    await PreferencesService().resetToDefaults();
    RecordingService().clearSavedRecordings();

    nativeInvocations.clear();
    tempDir = Directory.systemTemp.createTempSync('cloud_sync_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('screen_recording'), (MethodCall call) async {
      nativeInvocations.add(call.method);
      if (call.method == 'enableAutoSync' || call.method == 'disableAutoSync') {
        return true;
      }
      if (call.method == 'syncRecordingNow') {
        return true;
      }
      if (call.method == 'showSystemNotification') {
        return true;
      }
      return null;
    });
  });

  tearDown(() {
    try {
      tempDir?.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Cloud Vault Auto-Sync Logic Tests', () {
    test('1. Toggle state defaults to OFF (false)', () {
      final prefs = PreferencesService();
      expect(prefs.autoSync, isFalse);
    });

    test('2. Toggle ON invokes enableAutoSync and syncs local recordings to Cloud Vault', () async {
      final prefs = PreferencesService();
      final cloudService = CloudVaultService();

      // Create dummy local recordings in RecordingService
      final video1 = File('${tempDir!.path}/rec_gameplay.mp4')..writeAsStringSync('dummy content 1');
      final video2 = File('${tempDir!.path}/rec_tutorial.mp4')..writeAsStringSync('dummy content 2');

      RecordingService().addSavedRecording(MediaItem(
        id: '1',
        title: 'rec_gameplay.mp4',
        type: 'video',
        thumbnail: '',
        duration: '02:00',
        resolution: '1080p',
        date: 'Today',
        size: '10 MB',
        filePath: video1.path,
      ));

      RecordingService().addSavedRecording(MediaItem(
        id: '2',
        title: 'rec_tutorial.mp4',
        type: 'video',
        thumbnail: '',
        duration: '01:30',
        resolution: '1080p',
        date: 'Today',
        size: '5 MB',
        filePath: video2.path,
      ));

      // Enable Auto-Sync
      await cloudService.enableAutoSync();

      expect(prefs.autoSync, isTrue);
      expect(nativeInvocations, contains('enableAutoSync'));

      // Both files should be recorded as synced in Cloud Vault
      expect(prefs.isCloudSynced(video1.path), isTrue);
      expect(prefs.isCloudSynced(video2.path), isTrue);
      expect(prefs.cloudVaultRecords.length, greaterThanOrEqualTo(2));
    });

    test('3. Avoids duplicate uploads for already synced files', () async {
      final prefs = PreferencesService();
      final cloudService = CloudVaultService();

      final video = File('${tempDir!.path}/rec_existing.mp4')..writeAsStringSync('sample content');
      await prefs.setAutoSync(true);

      // First sync
      final firstResult = await cloudService.syncRecording(
        filePath: video.path,
        title: 'rec_existing.mp4',
      );
      expect(firstResult, isTrue);
      final initialRecordsCount = prefs.cloudVaultRecords.length;

      // Second sync attempt for same file
      final secondResult = await cloudService.syncRecording(
        filePath: video.path,
        title: 'rec_existing.mp4',
      );
      expect(secondResult, isTrue);

      // Records count should remain the same (no duplicates)
      expect(prefs.cloudVaultRecords.length, equals(initialRecordsCount));
    });

    test('4. Toggle OFF pauses/cancels background sync and does NOT delete cloud files', () async {
      final prefs = PreferencesService();
      final cloudService = CloudVaultService();

      final video = File('${tempDir!.path}/rec_preserved.mp4')..writeAsStringSync('cloud content');
      await prefs.setAutoSync(true);
      await cloudService.syncRecording(filePath: video.path, title: 'rec_preserved.mp4');

      expect(prefs.isCloudSynced(video.path), isTrue);
      final countBeforeToggleOff = prefs.cloudVaultRecords.length;

      // Toggle OFF
      await cloudService.disableAutoSync();

      expect(prefs.autoSync, isFalse);
      expect(nativeInvocations, contains('disableAutoSync'));

      // Cloud files must NOT be deleted
      expect(prefs.isCloudSynced(video.path), isTrue);
      expect(prefs.cloudVaultRecords.length, equals(countBeforeToggleOff));

      // Attempting to sync new video while OFF should be skipped
      final video2 = File('${tempDir!.path}/rec_new_blocked.mp4')..writeAsStringSync('new video');
      final newSyncResult = await cloudService.syncRecording(
        filePath: video2.path,
        title: 'rec_new_blocked.mp4',
      );
      expect(newSyncResult, isFalse);
      expect(prefs.isCloudSynced(video2.path), isFalse);
    });

    test('5. Saving a new recording triggers auto-sync only when toggle is ON', () async {
      final prefs = PreferencesService();
      final video = File('${tempDir!.path}/rec_trigger.mp4')..writeAsStringSync('recording stopped video');

      // Case A: Toggle is OFF
      await prefs.setAutoSync(false);
      await CloudVaultService().enqueueRecording(filePath: video.path, title: 'rec_trigger.mp4');
      expect(prefs.isCloudSynced(video.path), isFalse);

      // Case B: Toggle is ON
      await prefs.setAutoSync(true);
      await CloudVaultService().enqueueRecording(filePath: video.path, title: 'rec_trigger.mp4');
      expect(prefs.isCloudSynced(video.path), isTrue);
      expect(nativeInvocations, contains('syncRecordingNow'));
    });

    testWidgets('6. CloudVaultScreen SwitchListTile toggle interaction works without modifying UI', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CloudVaultScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Find Auto-Sync SwitchListTile
      final switchFinder = find.byWidgetPredicate(
        (widget) => widget is SwitchListTile && widget.title is Text &&
            (widget.title as Text).data == 'Auto-Sync New Recordings',
      );
      expect(switchFinder, findsOneWidget);

      final switchWidget = tester.widget<SwitchListTile>(switchFinder);
      // Default state is OFF
      expect(switchWidget.value, isFalse);

      // Tap toggle to turn ON
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(PreferencesService().autoSync, isTrue);
      expect(nativeInvocations, contains('enableAutoSync'));

      // Tap toggle to turn OFF
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(PreferencesService().autoSync, isFalse);
      expect(nativeInvocations, contains('disableAutoSync'));
    });
  });
}
