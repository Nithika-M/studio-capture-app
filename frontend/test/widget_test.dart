import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_recording_app/models/app_models.dart';
import 'package:screen_recording_app/screens/home_screen.dart';
import 'package:screen_recording_app/screens/main_wrapper_screen.dart';
import 'package:screen_recording_app/screens/profile_screen.dart';
import 'package:screen_recording_app/services/preferences_service.dart';
import 'package:screen_recording_app/services/recording_service.dart';
import 'package:screen_recording_app/screens/video_player_screen.dart';
import 'package:screen_recording_app/screens/profile_options_screens.dart';
import 'package:screen_recording_app/screens/recording_completed_screen.dart';
import 'package:screen_recording_app/widgets/app_drawer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService().init();
  });

  test('RecordingSettings model test', () {
    final settings = RecordingSettings(
      mode: RecordingMode.screen,
      resolution: '1080p',
      fps: 60,
      bitrate: 16,
      orientation: 'Auto',
      audioSource: 'Microphone',
      showFacecam: false,
      facecamShape: 'Circle',
      countdown: '3s',
      showTouches: true,
      floatingBubble: true,
      shakeToStop: true,
    );
    expect(settings.resolution, '1080p');
    expect(settings.fps, 60);
    expect(settings.bitrate, 16);
    expect(settings.toMap()['resolution'], '1080p');
    expect(settings.toMap()['fps'], 60);
    expect(settings.toMap()['shakeToStop'], true);
  });

  testWidgets('FEATURE 1: AppDrawer has exactly 10 essential items and no removed items', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          drawer: AppDrawer(currentRoute: 'home'),
          body: Center(child: Text('Main Content')),
        ),
      ),
    );

    // Open drawer
    final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
    scaffoldState.openDrawer();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AppDrawer), findsOneWidget);

    // The exact 10 items kept in the drawer
    final expected10Items = [
      'Home / Dashboard',
      'Start Recording',
      'Recordings Library',
      'Trim / Video Editor',
      'Cloud Vault / Backup',
      'Recording Settings',
      'UI Guide',
      'Help & Support',
      'Support & Legal',
      'Profile',
    ];

    for (final title in expected10Items) {
      final tileFinder = find.descendant(
        of: find.byType(AppDrawer),
        matching: find.text(title),
      );
      if (tileFinder.evaluate().isEmpty) {
        // Scroll down in the drawer if needed
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pump();
      }
      expect(tileFinder, findsOneWidget, reason: 'Item "$title" should exist in AppDrawer');
    }

    // Verify removed items are NOT present anywhere in AppDrawer
    expect(find.text('App Tour / Onboarding'), findsNothing);
    expect(find.text('Share App / Invite Friends'), findsNothing);
    expect(find.text('Take Quick Screenshot'), findsNothing);
  });

  testWidgets('FEATURE 2: Profile page removed the two descriptive lines cleanly', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: ProfileScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // Must still have Guest User and LOCAL DEVICE badge
    expect(find.text('Guest User'), findsAtLeastNWidgets(1));
    expect(find.text('LOCAL DEVICE'), findsAtLeastNWidgets(1));

    // The two descriptive lines MUST NOT exist
    expect(find.text('Local Storage Profile • No Account or Sign-in Required'), findsNothing);
    expect(find.text('Offline Ready • Direct Gallery Export'), findsNothing);

    // Other core items on the Profile page must remain unchanged
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Privacy & Security'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Support & Legal'), findsOneWidget);
  });

  test('FEATURE 3: Complete audit of all toggles across the app (persistence, runtime state & defaults)', () async {
    final prefs = PreferencesService();

    // 1. Privacy Settings
    // Hide Sensitive Content (default false)
    expect(prefs.hideSensitiveContent, false);
    await prefs.setHideSensitiveContent(true);
    expect(prefs.hideSensitiveContent, true);
    await prefs.setHideSensitiveContent(false);
    expect(prefs.hideSensitiveContent, false);

    // App Lock / Biometrics (default false)
    expect(prefs.biometricLock, false);
    await prefs.setBiometricLock(true);
    expect(prefs.biometricLock, true);
    await prefs.setBiometricLock(false);
    expect(prefs.biometricLock, false);

    // Share Anonymous Diagnostics (default false)
    expect(prefs.anonymousDiagnostics, false);
    await prefs.setAnonymousDiagnostics(true);
    expect(prefs.anonymousDiagnostics, true);
    await prefs.setAnonymousDiagnostics(false);
    expect(prefs.anonymousDiagnostics, false);

    // 2. Notifications Settings
    // Start and Stop Chime (default true)
    expect(prefs.startStopChime, true);
    await prefs.setStartStopChime(false);
    expect(prefs.startStopChime, false);
    await prefs.setStartStopChime(true);
    expect(prefs.startStopChime, true);

    // Countdown Sound (default true)
    expect(prefs.countdownSound, true);
    await prefs.setCountdownSound(false);
    expect(prefs.countdownSound, false);
    await prefs.setCountdownSound(true);
    expect(prefs.countdownSound, true);

    // Vibration Feedback (default true)
    expect(prefs.vibrationFeedback, true);
    await prefs.setVibrationFeedback(false);
    expect(prefs.vibrationFeedback, false);
    await prefs.setVibrationFeedback(true);
    expect(prefs.vibrationFeedback, true);

    // Low Storage Warning (default true)
    expect(prefs.lowStorageWarning, true);
    await prefs.setLowStorageWarning(false);
    expect(prefs.lowStorageWarning, false);
    await prefs.setLowStorageWarning(true);
    expect(prefs.lowStorageWarning, true);

    // Export and Trim Complete (default true)
    expect(prefs.exportTrimComplete, true);
    await prefs.setExportTrimComplete(false);
    expect(prefs.exportTrimComplete, false);
    await prefs.setExportTrimComplete(true);
    expect(prefs.exportTrimComplete, true);

    // Floating Controls Notification (default true)
    expect(prefs.floatingNotification, true);
    await prefs.setFloatingNotification(false);
    expect(prefs.floatingNotification, false);
    await prefs.setFloatingNotification(true);
    expect(prefs.floatingNotification, true);

    // 3. Storage & Export
    // Auto-sync to Cloud Vault (default false)
    expect(prefs.autoSync, false);
    await prefs.setAutoSync(true);
    expect(prefs.autoSync, true);
    await prefs.setAutoSync(false);
    expect(prefs.autoSync, false);

    // Auto-delete Old Videos (default false)
    expect(prefs.autoDeleteOldVideos, false);
    await prefs.setAutoDeleteOldVideos(true);
    expect(prefs.autoDeleteOldVideos, true);
    await prefs.setAutoDeleteOldVideos(false);
    expect(prefs.autoDeleteOldVideos, false);

    // 4. Recording Settings
    // Show Screen Touches (default true)
    expect(prefs.showTouches, true);
    await prefs.setShowTouches(false);
    expect(prefs.showTouches, false);
    await prefs.setShowTouches(true);
    expect(prefs.showTouches, true);

    // Floating Control Bubble (default true)
    expect(prefs.floatingWidget, true);
    await prefs.setFloatingWidget(false);
    expect(prefs.floatingWidget, false);
    await prefs.setFloatingWidget(true);
    expect(prefs.floatingWidget, true);

    // Shake to Finish (default false)
    expect(prefs.shakeToStop, false);
    await prefs.setShakeToStop(true);
    expect(prefs.shakeToStop, true);
    await prefs.setShakeToStop(false);
    expect(prefs.shakeToStop, false);

    // 5. Appearance
    // App Theme (default light)
    expect(prefs.themeMode, 'light');
    await prefs.setThemeMode('dark');
    expect(prefs.themeMode, 'dark');
    await prefs.setThemeMode('system');
    expect(prefs.themeMode, 'system');

    // Haptic Feedback (default true)
    expect(prefs.hapticFeedback, true);
    await prefs.setHapticFeedback(false);
    expect(prefs.hapticFeedback, false);
    await prefs.setHapticFeedback(true);
    expect(prefs.hapticFeedback, true);
  });

  testWidgets('AppDrawer navigation transitions smoothly to Profile', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: MainWrapperScreen(initialTab: 0),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(HomeScreen), findsOneWidget);

    final homeScaffoldFinder = find.descendant(
      of: find.byType(HomeScreen),
      matching: find.byType(Scaffold),
    );
    final homeScaffoldState = tester.state<ScaffoldState>(homeScaffoldFinder);
    homeScaffoldState.openDrawer();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(AppDrawer), findsOneWidget);

    final profileDrawerTile = find.descendant(
      of: find.byType(AppDrawer),
      matching: find.widgetWithText(ListTile, 'Profile'),
    );
    expect(profileDrawerTile, findsOneWidget);

    await tester.tap(profileDrawerTile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Profile & Preferences'), findsOneWidget);
  });

  test('FEATURE 1: Auto-save immediately adds recording to library without tapping Save', () {
    final service = RecordingService();
    final item = MediaItem(
      id: 'rec_test_auto_save_1',
      title: 'Auto_Saved_Recording.mp4',
      type: 'video',
      thumbnail: '',
      duration: '01:23',
      resolution: '1080x1920',
      date: 'Oct 05, 2026',
      size: '25.4 MB',
      filePath: '/storage/emulated/0/Movies/Auto_Saved_Recording.mp4',
    );

    // Verify adding immediately populates library
    service.addSavedRecording(item);
    expect(service.savedMediaItems.any((m) => m.id == 'rec_test_auto_save_1'), isTrue);
    expect(service.savedMediaItems.firstWhere((m) => m.id == 'rec_test_auto_save_1').title, 'Auto_Saved_Recording.mp4');

    // Renaming immediately updates the library item
    service.renameSavedItem('/storage/emulated/0/Movies/Auto_Saved_Recording.mp4', 'Renamed_Recording.mp4');
    expect(service.savedMediaItems.firstWhere((m) => m.id == 'rec_test_auto_save_1').title, 'Renamed_Recording.mp4');
  });

  testWidgets('FEATURE 1: Recording Completed review screen shows auto-saved status and Save to Gallery button', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: RecordingCompletedScreen(
          duration: 45,
          filePath: 'mock_recording.mp4',
          selectedMode: RecordingMode.screen,
        ),
      ),
    );
    await tester.pump();

    // Verify auto-save badge/text is shown
    expect(find.textContaining('Auto-saved to Library'), findsOneWidget);

    // Verify explicit action to save to Gallery is present
    expect(find.text('Save to Gallery'), findsOneWidget);
  });

  testWidgets('BUG FIX: VideoPlayerScreen has zero RenderFlex overflow on portrait screens', (WidgetTester tester) async {
    // 412x800 is a standard Android portrait device viewport where the 180px overflow previously appeared
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final portraitItem = MediaItem(
      id: 'rec_portrait_test',
      title: 'Mobile Screen Capture.mp4',
      type: 'video',
      thumbnail: '',
      duration: '00:45',
      resolution: '1080x1920',
      date: 'Oct 05, 2026',
      size: '18.2 MB',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerScreen(item: portraitItem),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Confirm no layout exception / overflow occurred
    final err = tester.takeException();
    if (err is FlutterError) {
      for (final d in err.diagnostics) {
        debugPrint('DIAG: ${d.toString()}');
      }
    }
    expect(err, isNull);
    expect(find.text('Mobile Screen Capture.mp4'), findsWidgets);
    expect(find.text('1080x1920'), findsWidgets);
  });

  testWidgets('FEATURE 2: Contact Support button displays bottom sheet with Gmail and Outlook options', (WidgetTester tester) async {
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

    // Find and tap the "Contact" button
    final contactBtn = find.widgetWithText(ElevatedButton, 'Contact');
    expect(contactBtn, findsOneWidget);
    await tester.tap(contactBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Modal bottom sheet should now be visible with the two options
    expect(find.text('Contact Support'), findsOneWidget);
    expect(find.text('Gmail'), findsOneWidget);
    expect(find.text('Opens with your signed-in Gmail account'), findsOneWidget);
    expect(find.text('Outlook'), findsOneWidget);
    expect(find.text('Opens with your signed-in Microsoft account'), findsOneWidget);

    // Tap Gmail option
    await tester.tap(find.text('Gmail'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Confirm sheet closes smoothly
    expect(find.text('Opens with your signed-in Gmail account'), findsNothing);
  });
}
