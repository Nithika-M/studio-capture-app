import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_recording_app/services/preferences_service.dart';
import 'package:screen_recording_app/services/recording_service.dart';
import 'package:screen_recording_app/services/google_drive_backup_service.dart';
import 'package:screen_recording_app/screens/splash_screen.dart';
import 'package:screen_recording_app/screens/cloud_vault_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService().init();
    await PreferencesService().resetToDefaults();
    RecordingService().clearSavedRecordings();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('screen_recording'), (MethodCall call) async {
      if (call.method == 'getAppBuildInfo') {
        return {
          'packageName': 'com.example.studio_capture_app',
          'sha1': 'AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF:12',
        };
      }
      if (call.method == 'isWifiConnected') {
        return true;
      }
      if (call.method == 'pickDeviceAccount') {
        return 'test.device.account@gmail.com';
      }
      return true;
    });
  });

  group('Splash Screen Tests', () {
    testWidgets('1. Studio Capture Splash Screen displays logo, title and navigates to Home', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SplashScreen(),
        ),
      );

      // Verify app name "Studio Capture" is displayed
      expect(find.text('Studio Capture'), findsOneWidget);
      expect(find.text('Pro Screen & Audio Recording'), findsOneWidget);

      // Verify progress indicator is present
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Advance clock past 1800ms splash duration
      await tester.pump(const Duration(milliseconds: 1900));
      await tester.pump(const Duration(milliseconds: 500));

      // Should have transitioned to Home / MainWrapperScreen
      expect(find.byType(SplashScreen), findsNothing);
    });
  });

  group('Cloud Vault & Backup Screen Tests', () {
    testWidgets('2. Screen displays title, Auto-Sync toggle, Wi-Fi toggle, and Cloud Recordings', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CloudVaultScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify title is "Cloud Vault & Backup"
      expect(find.text('Cloud Vault & Backup'), findsOneWidget);

      // Verify required toggles and headers
      expect(find.text('Auto-Sync New Recordings'), findsOneWidget);
      expect(find.text('Backup via Wi-Fi Only'), findsOneWidget);
      expect(find.text('Cloud Recordings'), findsOneWidget);
    });

    testWidgets('3. Cloud recordings list displays items when present in Drive', (tester) async {
      final driveFile = CloudDriveFile(
        id: 'drive_file_1',
        name: 'SCR_Demo_Rec.mp4',
        sizeBytes: 15 * 1024 * 1024,
        createdTime: DateTime.now(),
        webViewLink: 'https://drive.google.com/file/d/drive_file_1/view',
      );
      GoogleDriveBackupService().cloudFilesNotifier.value = [driveFile];

      await tester.pumpWidget(
        const MaterialApp(
          home: CloudVaultScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SCR_Demo_Rec.mp4'), findsOneWidget);
      expect(find.textContaining('15.0 MB'), findsOneWidget);
    });
  });
}
