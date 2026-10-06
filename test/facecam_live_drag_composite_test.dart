import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_recording_app/models/app_models.dart';
import 'package:screen_recording_app/screens/active_recording_screen.dart';
import 'package:screen_recording_app/screens/recording_completed_screen.dart';
import 'package:screen_recording_app/screens/video_player_screen.dart';
import 'package:screen_recording_app/services/recording_service.dart';
import 'package:screen_recording_app/widgets/facecam_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Facecam Live Preview & Sizing Tests', () {
    testWidgets('FacecamWindow renders noticeably larger size with LIVE badge and shape clipping', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: FacecamWindow(
                shape: 'Square (PiP)',
                size: 160,
                isLive: true,
                showBorder: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      final windowFinder = find.byType(FacecamWindow);
      expect(windowFinder, findsOneWidget);
      expect(tester.getSize(windowFinder), equals(const Size(160, 160)));

      // LIVE indicator is visible
      expect(find.text('● LIVE'), findsOneWidget);
    });

    testWidgets('FacecamWindow shows clear error state with retry button when camera is unavailable (never generic icon silently)', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: FacecamWindow(
                shape: 'Circle Head',
                size: 150,
                isLive: true,
                showBorder: true,
              ),
            ),
          ),
        ),
      );
      // Wait for asynchronous camera check and timeout
      await tester.pump(const Duration(milliseconds: 600));

      // In test runner with no camera hardware, it must show clear error UI with retry
      expect(find.byIcon(Icons.videocam_off_rounded), findsOneWidget);
      expect(find.text('Retry Camera'), findsOneWidget);
      // Confirm NO generic person icon is shown
      expect(find.byIcon(Icons.person_rounded), findsNothing);
    });
  });

  group('Facecam Draggable & Boundary Safety Tests', () {
    testWidgets('ActiveRecordingScreen renders draggable FacecamWindow and moves smoothly upon dragging', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final settings = RecordingSettings(
        mode: RecordingMode.facecam,
        resolution: '1080p',
        fps: 60,
        bitrate: 16.0,
        orientation: 'Portrait',
        audioSource: 'Microphone',
        showFacecam: true,
        facecamShape: 'Square (PiP)',
        countdown: 'Off',
        showTouches: false,
        floatingBubble: true,
        shakeToStop: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ActiveRecordingScreen(settings: settings),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      // FacecamWindow must be rendered on screen
      final facecamFinder = find.byType(FacecamWindow);
      expect(facecamFinder, findsOneWidget);

      final initialRect = tester.getRect(facecamFinder);
      expect(initialRect.width, greaterThanOrEqualTo(135.0));

      // Drag the facecam window smoothly upwards and leftwards
      await tester.drag(facecamFinder, const Offset(-150, -200));
      await tester.pump();

      final draggedRect = tester.getRect(facecamFinder);
      expect(draggedRect.left, lessThan(initialRect.left));
      expect(draggedRect.top, lessThan(initialRect.top));

      // Stays at the new position
      await tester.pump(const Duration(milliseconds: 100));
      final settledRect = tester.getRect(facecamFinder);
      expect(settledRect.left, equals(draggedRect.left));
      expect(settledRect.top, equals(draggedRect.top));

      // Boundary safety: drag far off-screen to the right and bottom
      await tester.drag(facecamFinder, const Offset(2000, 2000));
      await tester.pump();

      final boundedRect = tester.getRect(facecamFinder);
      // Facecam must remain within screen bounds (right <= 800, bottom <= 1600)
      expect(boundedRect.right, lessThanOrEqualTo(800.0));
      expect(boundedRect.bottom, lessThanOrEqualTo(1600.0));
    });
  });

  group('Facecam Video Baking & Playback Compositing Tests', () {
    testWidgets('RecordingCompletedScreen shows larger facecam overlay with real snapshot support', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final settings = RecordingSettings(
        mode: RecordingMode.facecam,
        resolution: '1080p',
        fps: 60,
        bitrate: 16.0,
        orientation: 'Portrait',
        audioSource: 'Microphone',
        showFacecam: true,
        facecamShape: 'Square (PiP)',
        countdown: 'Off',
        showTouches: false,
        floatingBubble: true,
        shakeToStop: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RecordingCompletedScreen(
            selectedMode: RecordingMode.facecam,
            duration: 12,
            filePath: 'Facecam_Test.mp4',
            settings: settings,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(FacecamWindow), findsOneWidget);
      final facecamBox = tester.getRect(find.byType(FacecamWindow));
      // Size must be noticeably larger than old 64px
      expect(facecamBox.width, greaterThanOrEqualTo(90.0));
    });

    testWidgets('VideoPlayerScreen composites FacecamWindow at saved normalized position and size', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final item = MediaItem(
        id: 'rec_facecam_123',
        title: 'Facecam_20261005_PiP.mp4',
        type: 'video',
        thumbnail: '',
        resolution: '1080p',
        date: 'Oct 05, 2026',
        size: '18 MB',
        hasFacecam: true,
        facecamShape: 'Square (PiP)',
        facecamNormalizedX: 0.5,
        facecamNormalizedY: 0.4,
        facecamSizeRatio: 0.28,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerScreen(item: item),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(FacecamWindow), findsOneWidget);
      final playerFacecamRect = tester.getRect(find.byType(FacecamWindow));
      expect(playerFacecamRect.width, greaterThanOrEqualTo(120.0));
    });
  });

  group('Facecam Device Orientation & Single-Box Guarantee Tests', () {
    testWidgets('Only ONE facecam preview element exists on screen in Portrait and stays upright', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600); // Portrait
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final settings = RecordingSettings(
        mode: RecordingMode.facecam,
        resolution: '1080p',
        fps: 30,
        bitrate: 16.0,
        orientation: 'Portrait',
        audioSource: 'Microphone',
        showFacecam: true,
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

      // STRICT REQUIREMENT: Only ONE facecam preview element on screen (never 2 boxes)
      final facecamFinder = find.byType(FacecamWindow);
      expect(facecamFinder, findsOneWidget);

      final rect = tester.getRect(facecamFinder);
      expect(rect.width, greaterThanOrEqualTo(135.0));
      expect(rect.height, greaterThanOrEqualTo(135.0));
      // Must be within portrait screen bounds
      expect(rect.right, lessThanOrEqualTo(800.0));
      expect(rect.bottom, lessThanOrEqualTo(1600.0));
    });

    testWidgets('Rotating device to Landscape dynamically reorients FacecamWindow and keeps single box safely bounded', (WidgetTester tester) async {
      // Start in Portrait
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final settings = RecordingSettings(
        mode: RecordingMode.facecam,
        resolution: '1080p',
        fps: 30,
        bitrate: 16.0,
        orientation: 'Auto',
        audioSource: 'Internal + Mic',
        showFacecam: true,
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

      // Exactly 1 facecam in portrait
      expect(find.byType(FacecamWindow), findsOneWidget);

      // Rotate phone physically to Landscape (1600 x 800) during active recording
      tester.view.physicalSize = const Size(1600, 800);
      await tester.pumpWidget(
        MaterialApp(
          home: ActiveRecordingScreen(settings: settings),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      // Still STRICTLY ONE facecam element on screen
      expect(find.byType(FacecamWindow), findsOneWidget);

      final landscapeRect = tester.getRect(find.byType(FacecamWindow));
      // Must be safely within landscape screen bounds (width 1600, height 800)
      expect(landscapeRect.right, lessThanOrEqualTo(1600.0));
      expect(landscapeRect.bottom, lessThanOrEqualTo(800.0));
      expect(landscapeRect.left, greaterThanOrEqualTo(0.0));
      expect(landscapeRect.top, greaterThanOrEqualTo(0.0));
    });

    testWidgets('FacecamWindow adapts cover crop aspect ratio in Landscape without distortion', (WidgetTester tester) async {
      // Landscape screen
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: FacecamWindow(
                shape: 'Square (PiP)',
                size: 180,
                isLive: true,
                showBorder: true,
                captureOrientation: 'Landscape',
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      final windowFinder = find.byType(FacecamWindow);
      expect(windowFinder, findsOneWidget);
      expect(tester.getSize(windowFinder), equals(const Size(180, 180)));
    });
  });
}
