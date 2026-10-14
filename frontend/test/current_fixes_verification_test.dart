import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_recording_app/services/preferences_service.dart';
import 'package:screen_recording_app/services/recording_service.dart';
import 'package:screen_recording_app/services/app_notification_service.dart';
import 'package:screen_recording_app/screens/settings_screen.dart';
import 'package:screen_recording_app/screens/profile_options_screens.dart';
import 'package:screen_recording_app/models/app_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? testDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService().init();
    await PreferencesService().resetToDefaults();
    RecordingService().clearSavedRecordings();

    testDir = Directory.systemTemp.createTempSync('screen_recorder_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('screen_recording_app/recording'),
            (MethodCall call) async {
      if (call.method == 'getStorageInfo') {
        return {
          'availableDeviceBytes': 53687091200, // 50.0 GB
          'totalDeviceBytes': 137438953472, // 128.0 GB
          'freeBytes': 53687091200,
          'usedBytes': 83751862272,
        };
      }
      if (call.method == 'scanFile') {
        return null;
      }
      return null;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('screen_recording'),
            (MethodCall call) async {
      if (call.method == 'getStorageInfo') {
        return {
          'availableDeviceBytes': 53687091200, // 50.0 GB
          'totalDeviceBytes': 137438953472, // 128.0 GB
          'freeBytes': 53687091200,
          'usedBytes': 83751862272,
        };
      }
      if (call.method == 'getVideoMetadata') {
        return {
          'durationMs': 10000,
          'width': 1920,
          'height': 1080,
        };
      }
      return null;
    });
  });

  tearDown(() {
    try {
      if (testDir != null && testDir!.existsSync()) {
        testDir!.deleteSync(recursive: true);
      }
    } catch (_) {}

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('screen_recording_app/recording'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('screen_recording'), null);
  });

  group('FEATURE 1: Remove Rate on Play Store from About & Legal', () {
    testWidgets('Rate on Play Store is completely removed and remaining items reflow cleanly',
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

      // Scroll down to About & Legal
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -700));
      await tester.pumpAndSettle();

      // Verify "Rate on Play Store" is NOT present anywhere
      expect(find.text('Rate on Play Store'), findsNothing);

      // Verify remaining About & Legal items reflow cleanly
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Terms of Service'), findsOneWidget);
      expect(find.text('App Version'), findsOneWidget);
      expect(find.text('v1.0.0'), findsOneWidget);
    });
  });

  group('FEATURE 2: Alignment under App Theme in Appearance Settings', () {
    testWidgets('App Theme label and description sit cleanly aligned on separate lines without squeezing',
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

      // Scroll to Appearance
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -350));
      await tester.pumpAndSettle();

      // Verify "App Theme" and "Interface styling paradigm" exist
      final titleFinder = find.text('App Theme');
      final descFinder = find.text('Interface styling paradigm');
      expect(titleFinder, findsOneWidget);
      expect(descFinder, findsOneWidget);

      // Verify description is aligned directly below the title
      final titleTopLeft = tester.getTopLeft(titleFinder);
      final descTopLeft = tester.getTopLeft(descFinder);
      expect(descTopLeft.dx, titleTopLeft.dx); // same x-alignment
      expect(descTopLeft.dy, greaterThan(titleTopLeft.dy)); // positioned below

      // Verify the 3 theme buttons are present and functional
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
    });
  });

  group('FEATURE 3: Public Gallery & Backup', () {
    test('Default save location is Movies/Studio Capture folder', () async {
      final prefs = PreferencesService();
      expect(prefs.savePath, contains('Studio Capture'));
    });

    test('openGooglePhotos triggers method channel', () async {
      bool called = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('screen_recording'),
              (MethodCall call) async {
        if (call.method == 'openGooglePhotos') {
          called = true;
          return true;
        }
        return null;
      });

      await RecordingService().openGooglePhotos();
      expect(called, isTrue);
    });
  });

  group('FEATURE 4: Auto-delete Old Recordings', () {
    test('When ON: permanently deletes recordings older than threshold from disk, library, and Cloud Vault',
        () async {
      final prefs = PreferencesService();
      await prefs.setAutoDeleteOldVideos(true);
      await prefs.setAutoDeleteDays(7); // threshold: 7 days

      // Create an old file (modified 10 days ago)
      final oldFile = File('${testDir!.path}/old_recording_clip.mp4');
      oldFile.writeAsBytesSync(List.filled(1024 * 5, 1));
      final tenDaysAgo = DateTime.now().subtract(const Duration(days: 10));
      oldFile.setLastModifiedSync(tenDaysAgo);

      // Create a fresh file (modified 2 days ago)
      final freshFile = File('${testDir!.path}/fresh_recording_clip.mp4');
      freshFile.writeAsBytesSync(List.filled(1024 * 5, 1));
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      freshFile.setLastModifiedSync(twoDaysAgo);

      // Add both to saved recordings
      final oldItem = MediaItem(
        id: 'old-1',
        title: 'old_recording_clip.mp4',
        date: 'Sep 26, 2026',
        duration: '01:00',
        size: '5.0 KB',
        resolution: '1080p',
        type: 'video',
        thumbnail: '',
        filePath: oldFile.path,
      );
      final freshItem = MediaItem(
        id: 'fresh-1',
        title: 'fresh_recording_clip.mp4',
        date: 'Oct 4, 2026',
        duration: '01:00',
        size: '5.0 KB',
        resolution: '1080p',
        type: 'video',
        thumbnail: '',
        filePath: freshFile.path,
      );
      RecordingService().addSavedRecording(oldItem);
      RecordingService().addSavedRecording(freshItem);

      // Both synced to Cloud Vault
      await prefs.addSyncedCloudFile({'title': 'old_recording_clip.mp4', 'filePath': oldFile.path});
      await prefs.addSyncedCloudFile({'title': 'fresh_recording_clip.mp4', 'filePath': freshFile.path});

      expect(prefs.isCloudSynced(oldFile.path), isTrue);

      // Run auto-delete check
      final purged = await AppNotificationService.runAutoDeleteIfEnabled();
      expect(purged, 1);

      // Verify old file is physically deleted from disk
      expect(oldFile.existsSync(), isFalse);

      // Verify old file is deleted from library saved items
      expect(RecordingService().savedMediaItems.any((i) => i.filePath == oldFile.path), isFalse);

      // Verify old file is removed from Cloud Vault
      expect(prefs.isCloudSynced(oldFile.path), isFalse);
      expect(prefs.deletedCloudTitles.contains('old_recording_clip.mp4'), isTrue);

      // Verify fresh file remains untouched on disk, library, and cloud
      expect(freshFile.existsSync(), isTrue);
      expect(RecordingService().savedMediaItems.any((i) => i.filePath == freshFile.path), isTrue);
      expect(prefs.isCloudSynced(freshFile.path), isTrue);
    });

    test('When OFF: no recordings are deleted regardless of age', () async {
      final prefs = PreferencesService();
      await prefs.setAutoDeleteOldVideos(false);
      await prefs.setAutoDeleteDays(7);

      final oldFile = File('${testDir!.path}/preserved_old_clip.mp4');
      oldFile.writeAsBytesSync(List.filled(1024 * 5, 1));
      final twentyDaysAgo = DateTime.now().subtract(const Duration(days: 20));
      oldFile.setLastModifiedSync(twentyDaysAgo);

      final oldItem = MediaItem(
        id: 'preserved-1',
        title: 'preserved_old_clip.mp4',
        date: 'Sep 16, 2026',
        duration: '01:00',
        size: '5.0 KB',
        resolution: '1080p',
        type: 'video',
        thumbnail: '',
        filePath: oldFile.path,
      );
      RecordingService().addSavedRecording(oldItem);

      final purged = await AppNotificationService.runAutoDeleteIfEnabled();
      expect(purged, 0);
      expect(oldFile.existsSync(), isTrue);
      expect(RecordingService().savedMediaItems.any((i) => i.filePath == oldFile.path), isTrue);
    });
  });

  group('FEATURE 5: Storage Management Page Accurate Real Numbers', () {
    testWidgets('StorageDataScreen displays actual sum of recording file sizes and real device available storage',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Create two real files: 100 KB and 200 KB = 300 KB total
      final file1 = File('${testDir!.path}/rec_1.mp4');
      file1.writeAsBytesSync(List.filled(100 * 1024, 0));
      final file2 = File('${testDir!.path}/rec_2.mp4');
      file2.writeAsBytesSync(List.filled(200 * 1024, 0));

      final item1 = MediaItem(
        id: 'rec-1',
        title: 'rec_1.mp4',
        date: 'Oct 6, 2026',
        duration: '00:30',
        size: '100.0 KB',
        resolution: '1080p',
        type: 'video',
        thumbnail: '',
        filePath: file1.path,
      );
      final item2 = MediaItem(
        id: 'rec-2',
        title: 'rec_2.mp4',
        date: 'Oct 6, 2026',
        duration: '01:00',
        size: '200.0 KB',
        resolution: '1080p',
        type: 'video',
        thumbnail: '',
        filePath: file2.path,
      );
      RecordingService().addSavedRecording(item1);
      RecordingService().addSavedRecording(item2);
      await PreferencesService().setSavePath(testDir!.path);

      await tester.pumpWidget(
        const MaterialApp(
          home: StorageDataScreen(),
        ),
      );
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();

      // Recordings Storage: 300 KB
      expect(find.text('300 KB'), findsOneWidget);

      // Available: 50.0 GB (from mock getStorageInfo)
      expect(find.text('Available: 50.0 GB'), findsOneWidget);

      // Verify file count shows 2 Saved Files
      expect(find.text('2 Saved Files'), findsOneWidget);

      // Test real-time live update upon deletion:
      // Select rec_1.mp4 and delete it
      final checkbox = find.byType(Checkbox).first;
      await tester.tap(checkbox);
      await tester.pump();

      final deleteSelectedBtn = find.text('Delete Selected');
      expect(deleteSelectedBtn, findsOneWidget);
      await tester.tap(deleteSelectedBtn);
      await tester.pumpAndSettle();

      // Confirm dialog
      final confirmDeleteBtn = find.widgetWithText(ElevatedButton, 'Delete Permanently');
      expect(confirmDeleteBtn, findsOneWidget);
      await tester.tap(confirmDeleteBtn);
      await tester.pump();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();
      // After deleting the first file (rec_2.mp4, 200 KB), storage updates immediately to 100 KB and 1 Saved File
      expect(find.text('100 KB'), findsWidgets);
      expect(find.text('1 Saved Files'), findsOneWidget);
    });
  });
}
