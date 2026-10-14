import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'models/app_models.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/recording_setup_screen.dart';
import 'screens/permission_request_screen.dart';
import 'screens/countdown_overlay_screen.dart';
import 'screens/active_recording_screen.dart';
import 'screens/recording_completed_screen.dart';
import 'screens/video_player_screen.dart';
import 'screens/video_editor_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/main_wrapper_screen.dart';
import 'screens/profile_options_screens.dart';
import 'screens/cloud_vault_screen.dart';
import 'screens/ui_guide_screen.dart';

import 'services/preferences_service.dart';
import 'services/screenshot_service.dart';
import 'services/app_notification_service.dart';
import 'services/google_drive_backup_service.dart';
import 'services/recording_service.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PreferencesService().init();
  GoogleDriveBackupService().init();

  // Apply hide-sensitive-content flag immediately if it was ON last session
  final prefs = PreferencesService();
  if (prefs.hideSensitiveContent) {
    try {
      const channel = MethodChannel('screen_recording');
      await channel.invokeMethod('setHideSensitiveContent', true);
    } catch (_) {}
  }

  // Auto-delete old recordings (no-op if toggle is OFF)
  AppNotificationService.runAutoDeleteIfEnabled();

  final savedTheme = prefs.themeMode;
  if (savedTheme == 'dark') {
    themeNotifier.value = ThemeMode.dark;
  } else if (savedTheme == 'system') {
    themeNotifier.value = ThemeMode.system;
  } else {
    themeNotifier.value = ThemeMode.light;
  }
  runApp(const ScreenRecorderApp());
}

class ScreenRecorderApp extends StatefulWidget {
  const ScreenRecorderApp({super.key});

  @override
  State<ScreenRecorderApp> createState() => _ScreenRecorderAppState();
}

class _ScreenRecorderAppState extends State<ScreenRecorderApp> {
  @override
  void initState() {
    super.initState();
    RecordingService.navigationNotifier.addListener(_onNavigation);
    _checkInitialRoute();
  }

  @override
  void dispose() {
    RecordingService.navigationNotifier.removeListener(_onNavigation);
    super.dispose();
  }

  Future<void> _checkInitialRoute() async {
    try {
      const channel = MethodChannel('screen_recording');
      final routeMap = await channel.invokeMethod<Map>('getInitialRoute');
      if (routeMap != null) {
        _handleRoute(Map<String, dynamic>.from(routeMap));
      }
    } catch (_) {}
  }

  void _onNavigation() {
    final nav = RecordingService.navigationNotifier.value;
    if (nav != null) {
      _handleRoute(nav);
    }
  }

  void _handleRoute(Map<String, dynamic> nav) {
    final route = nav['route'] as String?;
    final filePath = nav['filePath'] as String? ?? nav['savedPath'] as String?;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route == '/active-recording') {
        navigatorKey.currentState?.pushNamed('/active-recording');
      } else if (route == '/recording-completed') {
        navigatorKey.currentState?.pushNamed('/recording-completed', arguments: {
          'filePath': filePath,
          'duration': 1,
          'mode': RecordingMode.screen,
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'Consolidated Screen Recorder',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFDC2626),
              brightness: Brightness.light,
            ),
            textTheme: GoogleFonts.hankenGroteskTextTheme(),
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              centerTitle: false,
              titleTextStyle: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF111827),
              ),
              iconTheme: const IconThemeData(color: Color(0xFF111827), size: 24),
            ),
            scaffoldBackgroundColor: const Color(0xFFFAFAFC),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                side: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            cardTheme: CardThemeData(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
            ),
            dividerTheme: const DividerThemeData(
              color: Color(0xFFE5E7EB),
              thickness: 1,
            ),
            bottomNavigationBarTheme: BottomNavigationBarThemeData(
              backgroundColor: Colors.white,
              elevation: 8,
              selectedItemColor: const Color(0xFFDC2626),
              unselectedItemColor: const Color(0xFF9CA3AF),
              type: BottomNavigationBarType.fixed,
              selectedLabelStyle: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w700),
              unselectedLabelStyle: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFDC2626),
              brightness: Brightness.dark,
            ),
            textTheme: GoogleFonts.hankenGroteskTextTheme(ThemeData.dark().textTheme),
            scaffoldBackgroundColor: const Color(0xFF0F1117),
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: false,
              titleTextStyle: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              iconTheme: const IconThemeData(color: Colors.white, size: 24),
            ),
            cardTheme: CardThemeData(
              color: const Color(0xFF1A1D26),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF2E3342)),
              ),
            ),
          ),
          home: const SplashScreen(),
          builder: (context, child) => RepaintBoundary(
            key: ScreenshotService.repaintBoundaryKey,
            child: child ?? const SizedBox.shrink(),
          ),
          onGenerateRoute: _generateRoute,
        );
      },
    );
  }

  Route<dynamic>? _generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/splash':
        return _buildRoute(const SplashScreen());
      case '/onboarding':
        return _buildRoute(const OnboardingScreen());
      case '/recording-mode':
        WidgetsBinding.instance.addPostFrameCallback((_) {
          MainWrapperScreen.navigateToTab(navigatorKey.currentContext, 1);
        });
        return _buildRoute(const SizedBox.shrink());
      case '/recording-setup':
        final args = settings.arguments as RecordingMode?;
        return _buildRoute(RecordingSetupScreen(selectedMode: args ?? RecordingMode.screen));
      case '/permissions':
        final args = settings.arguments as RecordingSettings?;
        return _buildRoute(PermissionRequestScreen(settings: args ?? _defaultSettings()));
      case '/countdown':
        final args = settings.arguments as RecordingSettings?;
        return _buildRoute(CountdownOverlayScreen(settings: args ?? _defaultSettings()));
      case '/active-recording':
        final args = settings.arguments as RecordingSettings?;
        return _buildRoute(ActiveRecordingScreen(settings: args ?? _defaultSettings()));
      case '/recording-completed':
        final args = settings.arguments as Map<String, dynamic>?;
        return _buildRoute(RecordingCompletedScreen(
          selectedMode: args?['mode'] ?? RecordingMode.screen,
          duration: args?['duration'] ?? 0,
        ));
      case '/recordings':
        WidgetsBinding.instance.addPostFrameCallback((_) {
          MainWrapperScreen.navigateToTab(navigatorKey.currentContext, 2);
        });
        return _buildRoute(const SizedBox.shrink());
      case '/video-player':
        final args = settings.arguments as MediaItem?;
        return _buildRoute(VideoPlayerScreen(item: args!));
      case '/video-editor':
        return _buildRoute(const VideoEditorScreen());
      case '/settings':
        final section = settings.arguments as String?;
        return _buildRoute(SettingsScreen(initialSection: section));
      case '/cloud-vault':
      case '/backup':
        return _buildRoute(const CloudVaultScreen());
      case '/profile':
        WidgetsBinding.instance.addPostFrameCallback((_) {
          MainWrapperScreen.navigateToTab(navigatorKey.currentContext, 3);
        });
        return _buildRoute(const SizedBox.shrink());
      case '/notifications-settings':
        return _buildRoute(const NotificationsSettingsScreen());
      case '/privacy-security':
        return _buildRoute(const PrivacySecurityScreen());
      case '/storage-data':
        return _buildRoute(const StorageDataScreen());
      case '/help-support':
        return _buildRoute(const HelpSupportScreen());
      case '/about':
        return _buildRoute(const AboutScreen());
      case '/ui-guide':
        return _buildRoute(const UiGuideScreen());
      default:
        return null;
    }
  }

  PageRouteBuilder _buildRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: animation.drive(
              Tween(begin: const Offset(0.05, 0), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutCubic)),
            ),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  RecordingSettings _defaultSettings() {
    return RecordingSettings(
      mode: RecordingMode.screen,
      resolution: '1080p',
      fps: 30,
      bitrate: 16.0,
      orientation: 'Auto',
      audioSource: 'Internal + Mic',
      showFacecam: false,
      facecamShape: 'Square (PiP)',
      countdown: '3s',
      showTouches: true,
      floatingBubble: true,
      shakeToStop: false,
    );
  }
}