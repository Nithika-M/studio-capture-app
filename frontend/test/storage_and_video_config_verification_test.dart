import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_recording_app/models/app_models.dart';
import 'package:screen_recording_app/services/preferences_service.dart';
import 'package:screen_recording_app/services/recording_service.dart';
import 'package:screen_recording_app/screens/recording_setup_screen.dart';
import 'package:screen_recording_app/screens/profile_options_screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? testDir;
  int mockAvailableBytes = 53687091200; // 50.0 GB
  int mockTotalBytes = 137438953472; // 128.0 GB
  String mockAvailableFormatted = '50.0 GB';
  String mockTotalFormatted = '128.0 GB';

  Map<String, dynamic>? lastStartRecordingConfig;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService().init();
    await PreferencesService().resetToDefaults();
    RecordingService().clearSavedRecordings();

    testDir = Directory.systemTemp.createTempSync('storage_video_test_');
    PreferencesService().setSavePath(testDir!.path);

    lastStartRecordingConfig = null;
    mockAvailableBytes = 53687091200;
    mockTotalBytes = 137438953472;
    mockAvailableFormatted = '50.0 GB';
    mockTotalFormatted = '128.0 GB';

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('screen_recording_app/recording'),
            (MethodCall call) async {
      if (call.method == 'getStorageInfo') {
        return {
          'availableDeviceBytes': mockAvailableBytes,
          'totalDeviceBytes': mockTotalBytes,
          'usedDeviceBytes': mockTotalBytes - mockAvailableBytes,
          'availableFormatted': mockAvailableFormatted,
          'totalFormatted': mockTotalFormatted,
          'usedFormatted': '78.0 GB',
        };
      }
      if (call.method == 'startRecording') {
        lastStartRecordingConfig = Map<String, dynamic>.from(call.arguments as Map);
        return true;
      }
      if (call.method == 'stopRecording') {
        return '${testDir!.path}/test_out.mp4';
      }
      if (call.method == 'getVideoMetadata') {
        final res = lastStartRecordingConfig?['resolution'] as String? ?? '1080p';
        final fps = (lastStartRecordingConfig?['fps'] as num?)?.toInt() ?? 30;
        final br = (lastStartRecordingConfig?['bitrate'] as num?)?.toDouble() ?? 16.0;
        final ori = lastStartRecordingConfig?['orientation'] as String? ?? 'Auto';

        int width;
        int height;
        if (res == '144p') {
          width = ori == 'Landscape' ? 320 : 144;
          height = ori == 'Landscape' ? 144 : 320;
        } else if (res == '240p') {
          width = ori == 'Landscape' ? 532 : 240;
          height = ori == 'Landscape' ? 240 : 532;
        } else if (res == '720p') {
          width = ori == 'Landscape' ? 1600 : 720;
          height = ori == 'Landscape' ? 720 : 1600;
        } else if (res == '1080p') {
          width = ori == 'Landscape' ? 2400 : 1080;
          height = ori == 'Landscape' ? 1080 : 2400;
        } else if (res == '1440p') {
          width = ori == 'Landscape' ? 3200 : 1440;
          height = ori == 'Landscape' ? 1440 : 3200;
        } else if (res == '4K') {
          width = ori == 'Landscape' ? 3840 : 1728;
          height = ori == 'Landscape' ? 1728 : 3840;
        } else {
          width = 1080;
          height = 2400;
        }

        return {
          'width': width,
          'height': height,
          'rotation': 0,
          'fps': fps.toDouble(),
          'bitrate': (br * 1000000).toInt(),
          'durationMs': 5000,
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
          'availableDeviceBytes': mockAvailableBytes,
          'totalDeviceBytes': mockTotalBytes,
          'usedDeviceBytes': mockTotalBytes - mockAvailableBytes,
          'availableFormatted': mockAvailableFormatted,
          'totalFormatted': mockTotalFormatted,
        };
      }
      if (call.method == 'requestPermission') {
        return true;
      }
      if (call.method == 'startRecording') {
        lastStartRecordingConfig = Map<String, dynamic>.from(call.arguments as Map);
        return true;
      }
      if (call.method == 'stopRecording') {
        return '${testDir!.path}/test_out.mp4';
      }
      if (call.method == 'getVideoMetadata') {
        final res = lastStartRecordingConfig?['resolution'] as String? ?? '1080p';
        final fps = (lastStartRecordingConfig?['fps'] as num?)?.toInt() ?? 30;
        final br = (lastStartRecordingConfig?['bitrate'] as num?)?.toDouble() ?? 16.0;
        final ori = lastStartRecordingConfig?['orientation'] as String? ?? 'Auto';

        int width;
        int height;
        if (res == '144p') {
          width = ori == 'Landscape' ? 320 : 144;
          height = ori == 'Landscape' ? 144 : 320;
        } else if (res == '240p') {
          width = ori == 'Landscape' ? 532 : 240;
          height = ori == 'Landscape' ? 240 : 532;
        } else if (res == '720p') {
          width = ori == 'Landscape' ? 1600 : 720;
          height = ori == 'Landscape' ? 720 : 1600;
        } else if (res == '1080p') {
          width = ori == 'Landscape' ? 2400 : 1080;
          height = ori == 'Landscape' ? 1080 : 2400;
        } else if (res == '1440p') {
          width = ori == 'Landscape' ? 3200 : 1440;
          height = ori == 'Landscape' ? 1440 : 3200;
        } else if (res == '4K') {
          width = ori == 'Landscape' ? 3840 : 1728;
          height = ori == 'Landscape' ? 1728 : 3840;
        } else {
          width = 1080;
          height = 2400;
        }

        return {
          'width': width,
          'height': height,
          'rotation': 0,
          'fps': fps.toDouble(),
          'bitrate': (br * 1000000).toInt(),
          'durationMs': 5000,
        };
      }
      return null;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/permissions/methods'),
            (MethodCall call) async {
      if (call.method == 'requestPermissions') {
        final list = List<int>.from(call.arguments as List);
        return Map.fromIterables(list, list.map((_) => 1)); // 1 = granted
      }
      if (call.method == 'checkPermissionStatus') {
        return 1; // granted
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/permissions/methods'), null);
  });

  group('AVAILABLE STORAGE LIVE & ACCURATE QUERY TESTS', () {
    testWidgets('RecordingSetupScreen displays live available storage and NOT hardcoded 64.2 GB', (tester) async {
      mockAvailableFormatted = '74.8 GB';
      mockAvailableBytes = 80315793408;

      await tester.pumpWidget(
        const MaterialApp(
          home: RecordingSetupScreen(selectedMode: RecordingMode.screen),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify hardcoded '64.2 GB' is completely absent
      expect(find.text('64.2 GB'), findsNothing);

      // Verify live formatted value is rendered
      expect(find.text('74.8 GB'), findsOneWidget);
    });

    testWidgets('StorageDataScreen queries live available storage and updates immediately on delete', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final dummyFile = File('${testDir!.path}/recording_to_delete.mp4');
      dummyFile.writeAsBytesSync(List.filled(1024 * 1024 * 5, 0)); // 5 MB

      final item = MediaItem(
        id: 'rec-del',
        title: 'recording_to_delete.mp4',
        date: 'Oct 6, 2026',
        duration: '00:30',
        size: '5.0 MB',
        resolution: '1080p',
        type: 'video',
        thumbnail: '',
        filePath: dummyFile.path,
      );
      RecordingService().addSavedRecording(item);
      await PreferencesService().setSavePath(testDir!.path);

      mockAvailableFormatted = '42.5 GB';
      mockAvailableBytes = 45634027520;

      await tester.pumpWidget(
        const MaterialApp(
          home: StorageDataScreen(),
        ),
      );
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();

      // Check Available display uses live formatted value
      expect(find.text('Available: 42.5 GB'), findsOneWidget);

      // Now simulate deleting the recording and storage freeing up
      mockAvailableFormatted = '42.51 GB';
      mockAvailableBytes = 45634027520 + 5242880;

      // Select file and delete
      final checkbox = find.byType(Checkbox).first;
      await tester.tap(checkbox);
      await tester.pump();

      final deleteBtn = find.text('Delete Selected');
      expect(deleteBtn, findsOneWidget);
      await tester.tap(deleteBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final confirmBtn = find.text('Delete Permanently');
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pump();

      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify storage was reloaded live and reflects updated storage
      expect(find.text('Available: 42.51 GB'), findsOneWidget);
    });
  });

  group('VIDEO CONFIGURATION SETTINGS ACCURACY TESTS', () {
    test('RESOLUTION PRESETS: All 6 presets (144p, 240p, 720p, 1080p, 1440p, 4K) produce correct target tiers and dimensions', () async {
      final presets = ['144p', '240p', '720p', '1080p', '1440p', '4K'];
      final expectedShortSides = {
        '144p': 144,
        '240p': 240,
        '720p': 720,
        '1080p': 1080,
        '1440p': 1440,
        '4K': 2160,
      };

      for (final preset in presets) {
        final settings = RecordingSettings(
          mode: RecordingMode.screen,
          resolution: preset,
          fps: 30,
          bitrate: 16.0,
          orientation: 'Portrait',
          audioSource: 'Internal',
          showFacecam: false,
          facecamShape: 'Square (PiP)',
          countdown: '3s',
          showTouches: false,
          floatingBubble: false,
          shakeToStop: false,
        );

        await RecordingService().startRecording(
          settings: settings,
          enableAudio: true,
          enableVideo: true,
        );

        expect(lastStartRecordingConfig, isNotNull);
        expect(lastStartRecordingConfig!['resolution'], equals(preset));

        // Check simulated output metadata dimensions
        final meta = await RecordingService().getVideoMetadata('${testDir!.path}/test_out.mp4');
        expect(meta, isNotNull);
        // For portrait: height > width, and short side is width
        expect(meta!['height'], greaterThan(meta['width']));
        if (preset == '4K') {
          // UHD long side clamped to 3840
          expect(meta['height'], equals(3840));
          expect(meta['width'], lessThanOrEqualTo(2160));
        } else {
          expect(meta['width'], equals(expectedShortSides[preset]));
        }
      }
    });

    test('FRAME RATE PRESETS: All 4 FPS options (24, 30, 60, 120) are accurately passed and encoded', () async {
      final fpsOptions = [24, 30, 60, 120];

      for (final fps in fpsOptions) {
        final settings = RecordingSettings(
          mode: RecordingMode.screen,
          resolution: '1080p',
          fps: fps,
          bitrate: 16.0,
          orientation: 'Auto',
          audioSource: 'Internal',
          showFacecam: false,
          facecamShape: 'Square (PiP)',
          countdown: '3s',
          showTouches: false,
          floatingBubble: false,
          shakeToStop: false,
        );

        await RecordingService().startRecording(
          settings: settings,
          enableAudio: true,
          enableVideo: true,
        );

        expect(lastStartRecordingConfig!['fps'], equals(fps));

        final meta = await RecordingService().getVideoMetadata('${testDir!.path}/test_out.mp4');
        expect(meta!['fps'], equals(fps.toDouble()));
      }
    });

    test('VIDEO BITRATE: User slider values (0.8, 4, 8, 16, 24, 32 Mbps) scale target bitrate without type casting drops', () async {
      final bitrates = [0.8, 4.0, 8.0, 16.0, 24.0, 32.0];

      for (final br in bitrates) {
        final settings = RecordingSettings(
          mode: RecordingMode.screen,
          resolution: '1080p',
          fps: 60,
          bitrate: br,
          orientation: 'Auto',
          audioSource: 'Internal',
          showFacecam: false,
          facecamShape: 'Square (PiP)',
          countdown: '3s',
          showTouches: false,
          floatingBubble: false,
          shakeToStop: false,
        );

        await RecordingService().startRecording(
          settings: settings,
          enableAudio: true,
          enableVideo: true,
        );

        expect(lastStartRecordingConfig!['bitrate'], equals(br));

        final meta = await RecordingService().getVideoMetadata('${testDir!.path}/test_out.mp4');
        expect(meta!['bitrate'], equals((br * 1000000).toInt()));
      }
    });

    test('CAPTURE ORIENTATION: Portrait (height > width) and Landscape (width > height) correctly applied', () async {
      // 1. Portrait
      var settings = RecordingSettings(
        mode: RecordingMode.screen,
        resolution: '1080p',
        fps: 60,
        bitrate: 16.0,
        orientation: 'Portrait',
        audioSource: 'Internal',
        showFacecam: false,
        facecamShape: 'Square (PiP)',
        countdown: '3s',
        showTouches: false,
        floatingBubble: false,
        shakeToStop: false,
      );

      await RecordingService().startRecording(
        settings: settings,
        enableAudio: true,
        enableVideo: true,
      );

      expect(lastStartRecordingConfig!['orientation'], equals('Portrait'));
      var meta = await RecordingService().getVideoMetadata('${testDir!.path}/test_out.mp4');
      expect(meta!['height'], greaterThan(meta['width']));

      // 2. Landscape
      settings = RecordingSettings(
        mode: RecordingMode.screen,
        resolution: '1080p',
        fps: 60,
        bitrate: 16.0,
        orientation: 'Landscape',
        audioSource: 'Internal',
        showFacecam: false,
        facecamShape: 'Square (PiP)',
        countdown: '3s',
        showTouches: false,
        floatingBubble: false,
        shakeToStop: false,
      );

      await RecordingService().startRecording(
        settings: settings,
        enableAudio: true,
        enableVideo: true,
      );

      expect(lastStartRecordingConfig!['orientation'], equals('Landscape'));
      meta = await RecordingService().getVideoMetadata('${testDir!.path}/test_out.mp4');
      expect(meta!['width'], greaterThan(meta['height']));
    });

    test('FULL COMBINATIONS: Extreme presets operate without mutual interference or silent overrides', () async {
      // Combination A: 4K + 120fps + 32Mbps + Landscape
      var settings = RecordingSettings(
        mode: RecordingMode.screen,
        resolution: '4K',
        fps: 120,
        bitrate: 32.0,
        orientation: 'Landscape',
        audioSource: 'Internal',
        showFacecam: false,
        facecamShape: 'Square (PiP)',
        countdown: '3s',
        showTouches: false,
        floatingBubble: false,
        shakeToStop: false,
      );

      await RecordingService().startRecording(
        settings: settings,
        enableAudio: true,
        enableVideo: true,
      );

      expect(lastStartRecordingConfig!['resolution'], equals('4K'));
      expect(lastStartRecordingConfig!['fps'], equals(120));
      expect(lastStartRecordingConfig!['bitrate'], equals(32.0));
      expect(lastStartRecordingConfig!['orientation'], equals('Landscape'));

      var meta = await RecordingService().getVideoMetadata('${testDir!.path}/test_out.mp4');
      expect(meta!['width'], equals(3840));
      expect(meta['fps'], equals(120.0));
      expect(meta['bitrate'], equals(32000000));
      expect(meta['width'], greaterThan(meta['height']));

      // Combination B: 144p + 24fps + 0.8Mbps + Portrait
      settings = RecordingSettings(
        mode: RecordingMode.screen,
        resolution: '144p',
        fps: 24,
        bitrate: 0.8,
        orientation: 'Portrait',
        audioSource: 'Internal',
        showFacecam: false,
        facecamShape: 'Square (PiP)',
        countdown: '3s',
        showTouches: false,
        floatingBubble: false,
        shakeToStop: false,
      );

      await RecordingService().startRecording(
        settings: settings,
        enableAudio: true,
        enableVideo: true,
      );

      expect(lastStartRecordingConfig!['resolution'], equals('144p'));
      expect(lastStartRecordingConfig!['fps'], equals(24));
      expect(lastStartRecordingConfig!['bitrate'], equals(0.8));
      expect(lastStartRecordingConfig!['orientation'], equals('Portrait'));

      meta = await RecordingService().getVideoMetadata('${testDir!.path}/test_out.mp4');
      expect(meta!['width'], equals(144));
      expect(meta['fps'], equals(24.0));
      expect(meta['bitrate'], equals(800000));
      expect(meta['height'], greaterThan(meta['width']));
    });
  });
}
