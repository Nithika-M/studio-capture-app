import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_recording_app/services/preferences_service.dart';
import 'package:screen_recording_app/services/cloud_vault_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferencesService prefs;
  late CloudVaultService cloudVault;
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = PreferencesService();
    await prefs.init();
    await prefs.resetToDefaults();

    tempDir = Directory.systemTemp.createTempSync('cloud_actions_test_');
    cloudVault = CloudVaultService();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('screen_recording'), (MethodCall call) async {
      return true;
    });
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('1. Delete from cloud marks file as deleted and prevents re-uploading', () async {
    final localFile = File('${tempDir.path}/demo_test.mp4')..writeAsStringSync('video dummy content');

    await prefs.setAutoSync(true);

    // Initial sync
    final synced = await cloudVault.syncRecording(
      filePath: localFile.path,
      title: 'demo_test.mp4',
    );
    expect(synced, isTrue);
    expect(prefs.isCloudSynced('demo_test.mp4'), isTrue);

    // Delete from cloud using preferences service removeCloudFile
    await prefs.removeCloudFile('demo_test.mp4');

    // Local file MUST still exist!
    expect(localFile.existsSync(), isTrue);

    // Must be marked deleted from cloud and removed from synced list
    expect(prefs.isCloudDeleted('demo_test.mp4'), isTrue);
    expect(prefs.isCloudSynced('demo_test.mp4'), isFalse);

    // Auto-sync must NOT re-upload that same video again
    final reSync = await cloudVault.syncRecording(
      filePath: localFile.path,
      title: 'demo_test.mp4',
    );
    expect(reSync, isTrue);
    expect(prefs.isCloudSynced('demo_test.mp4'), isFalse);
  });

  test('2. Generate shareable cloud link creates valid URL', () async {
    final link = await cloudVault.getShareableLink({
      'title': 'my_recording.mp4',
      'url': 'https://firebasestorage.googleapis.com/v0/b/app.appspot.com/o/vault%2Fmy_recording.mp4?alt=media',
    });

    expect(link, isNotEmpty);
    expect(link.startsWith('http'), isTrue);
  });
}
