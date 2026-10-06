import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_recording_app/models/app_models.dart';
import 'package:screen_recording_app/services/recording_service.dart';
import 'package:screen_recording_app/widgets/app_drawer.dart';
import 'package:screen_recording_app/screens/recording_completed_screen.dart';
import 'package:screen_recording_app/screens/cloud_vault_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RecordingService Dual-Track Voice + Screen Tests', () {
    late RecordingService service;

    setUp(() {
      service = RecordingService();
    });

    test('Initializes with default dual audio and noise cancellation states', () {
      expect(service.micMuted, false);
      expect(service.systemAudioMuted, false);
      expect(service.noiseCancellation, true);
      expect(service.videoEnabled, true);
    });

    test('Mic mute and System audio mute independently control audio tracks', () {
      service.setMicMuted(true);
      expect(service.micMuted, true);
      expect(service.systemAudioMuted, false);

      service.setSystemAudioMuted(true);
      expect(service.systemAudioMuted, true);

      service.setMicMuted(false);
      expect(service.micMuted, false);
      expect(service.systemAudioMuted, true);
    });

    test('Noise cancellation toggle works properly', () {
      service.setNoiseCancellation(false);
      expect(service.noiseCancellation, false);
      service.setNoiseCancellation(true);
      expect(service.noiseCancellation, true);
    });

    test('Video track can be disabled while audio continues', () {
      service.setVideoEnabled(false);
      expect(service.videoEnabled, false);
      service.setVideoEnabled(true);
      expect(service.videoEnabled, true);
    });

    test('Saved recording repository supports add, rename, and delete', () {
      final testItem = MediaItem(
        id: 'test_item_1',
        title: 'VoiceScreen_Test.mp4',
        type: 'video',
        thumbnail: 'assets/thumb.jpg',
        resolution: '1080p',
        date: 'Today',
        size: '18.4 MB',
        filePath: '/storage/VoiceScreen_Test.mp4',
        isVoiceScreen: true,
      );

      service.addSavedRecording(testItem);
      expect(service.savedMediaItems.any((item) => item.id == 'test_item_1'), true);

      service.renameSavedItem('test_item_1', 'VoiceScreen_Renamed.mp4');
      final renamed = service.savedMediaItems.firstWhere((item) => item.id == 'test_item_1');
      expect(renamed.title, 'VoiceScreen_Renamed.mp4');

      service.deleteSavedItem('test_item_1');
      expect(service.savedMediaItems.any((item) => item.id == 'test_item_1'), false);
    });
  });

  group('Navigation Drawer Widget Tests', () {
    testWidgets('Renders all requested categories and entries in AppDrawer', (WidgetTester tester) async {
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

      // Check Profile header
      expect(find.text('Alex Rivera'), findsOneWidget);
      expect(find.text('PRO CREATOR'), findsOneWidget);
      expect(find.textContaining('Cloud Vault Storage'), findsOneWidget);

      // Check Navigation section
      expect(find.text('Home / Dashboard'), findsOneWidget);
      expect(find.text('Start Recording'), findsOneWidget);
      expect(find.text('Recordings / Library'), findsOneWidget);
      expect(find.text('Trim / Editor'), findsOneWidget);
      expect(find.text('Cloud Vault / Backup'), findsOneWidget);
      expect(find.text('Recording Settings'), findsOneWidget);

      // Check Settings & Preferences section
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Notifications & Alerts'), findsOneWidget);
      expect(find.text('Privacy & Permissions'), findsOneWidget);
      expect(find.text('Storage & Data'), findsOneWidget);

      // Check Account & Support section
      expect(find.text('Profile / Account'), findsOneWidget);
      expect(find.text('Help / Support / FAQ'), findsOneWidget);
      expect(find.text('Share App / Invite Friends'), findsOneWidget);
      expect(find.text('Sign Out / Switch Account'), findsOneWidget);
    });

    testWidgets('Expands Start Recording to show all 5 recording modes', (WidgetTester tester) async {
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

      // By default _recordingModesExpanded is true, so all 5 modes are immediately accessible
      expect(find.text('Screen Recording'), findsOneWidget);
      expect(find.text('Voice + Screen'), findsOneWidget);
      expect(find.text('Facecam Recording'), findsOneWidget);
      expect(find.text('Gaming Record'), findsOneWidget);
      expect(find.text('GIF Recording'), findsOneWidget);

      // Tapping toggles collapse
      await tester.tap(find.text('Start Recording'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Screen Recording'), findsNothing);

      // Tapping again re-expands
      await tester.tap(find.text('Start Recording'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Screen Recording'), findsOneWidget);
    });

    testWidgets('Expands Settings to show all sub-sections', (WidgetTester tester) async {
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

      // Tap 'Settings' header icon
      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Recording Defaults'), findsOneWidget);
      expect(find.text('Audio & Inputs'), findsOneWidget);
      expect(find.text('Facecam & Overlay'), findsOneWidget);
      expect(find.text('Storage & Export'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('About & Legal'), findsWidgets);
    });
  });

  group('Cloud Vault Screen Tests', () {
    testWidgets('Renders storage quota and cloud file management', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CloudVaultScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Cloud Vault & Backup'), findsOneWidget);
      expect(find.text('12.4 GB Used'), findsOneWidget);
      expect(find.text('100 GB Total (12.4% Used)'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
      expect(find.text('Auto-Sync New Recordings'), findsOneWidget);
      expect(find.text('Backup via Wi-Fi Only'), findsOneWidget);
    });
  });

  group('Recording Completed Voice + Screen Tests', () {
    testWidgets('Displays dual-track studio mix and telemetry for Voice + Screen recording', (WidgetTester tester) async {
      final settings = RecordingSettings(
        mode: RecordingMode.voiceScreen,
        resolution: '1080p',
        fps: 60,
        bitrate: 16,
        orientation: 'Auto',
        audioSource: 'Internal + Mic',
        showFacecam: false,
        facecamShape: 'Circle Head',
        countdown: '3s',
        showTouches: true,
        floatingBubble: true,
        shakeToStop: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RecordingCompletedScreen(
            selectedMode: RecordingMode.voiceScreen,
            duration: 120,
            settings: settings,
            filePath: '/test/VoiceScreen_demo.mp4',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Check header and preview telemetry
      expect(find.text('Recording Saved'), findsOneWidget);
      expect(find.text('Dual-Track Audio Studio Mix'), findsOneWidget);
      expect(find.text('Track 1: Microphone Commentary'), findsOneWidget);
      expect(find.text('Track 2: System / App Audio'), findsOneWidget);
      expect(find.text('AI Noise: Active'), findsOneWidget);
      expect(find.text('Lossless 48kHz'), findsOneWidget);
      expect(find.text('Synced (0ms)'), findsOneWidget);

      // Check quick action buttons
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Trim'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });
  });
}
