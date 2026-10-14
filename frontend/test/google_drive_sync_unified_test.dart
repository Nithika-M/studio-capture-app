import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:screen_recording_app/services/google_drive_backup_service.dart';
import 'package:googleapis/drive/v3.dart' as drive;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GoogleDriveBackupService Unit Tests', () {
    late GoogleDriveBackupService service;

    setUp(() {
      service = GoogleDriveBackupService();
    });

    test('Singleton instance is maintained', () {
      final s1 = GoogleDriveBackupService();
      final s2 = GoogleDriveBackupService();
      expect(identical(s1, s2), isTrue);
    });

    test('parseDriveError correctly identifies disabled Drive API in Google Cloud', () {
      final error = drive.DetailedApiRequestError(
        403,
        'Google Drive API has not been used in project 123456789 before or it is disabled. Enable it by visiting https://console.developers.google.com/apis/api/drive.googleapis.com/overview?project=123456789 then retry.',
      );

      final errorInfo = service.parseDriveError(error);
      expect(errorInfo.type, equals(DriveErrorType.driveApiDisabled));
      expect(errorInfo.statusCode, equals(403));
      expect(errorInfo.userMessage, contains('Google Drive API is disabled'));
      expect(errorInfo.technicalDetails, contains('APIs & Services'));
    });

    test('parseDriveError correctly identifies missing drive.file scope authorization', () {
      final error = drive.DetailedApiRequestError(
        403,
        'The request cannot be identified with insufficient permissions. Reason: ACCESS_TOKEN_SCOPE_INSUFFICIENT.',
      );

      final errorInfo = service.parseDriveError(error);
      expect(errorInfo.type, equals(DriveErrorType.permissionNotGranted));
      expect(errorInfo.statusCode, equals(403));
      expect(errorInfo.userMessage, contains('Google Drive access permission was not granted'));
    });

    test('parseDriveError correctly identifies Code 10 Developer Error', () {
      final error = PlatformException(
        code: '10',
        message: 'com.google.android.gms.common.api.ApiException: 10: ',
      );

      final errorInfo = service.parseDriveError(error);
      expect(errorInfo.type, equals(DriveErrorType.developerErrorCode10));
      expect(errorInfo.userMessage, contains('Code 10 DEVELOPER_ERROR'));
      expect(errorInfo.technicalDetails, contains('com.example.studio_capture_app'));
    });

    test('parseDriveError correctly identifies Drive storage quota full', () {
      final error = drive.DetailedApiRequestError(
        403,
        'The user\'s Drive storage quota has been exceeded (storageQuotaExceeded).',
      );

      final errorInfo = service.parseDriveError(error);
      expect(errorInfo.type, equals(DriveErrorType.storageFull));
      expect(errorInfo.userMessage, contains('storage is full'));
    });

    test('parseDriveError correctly identifies expired or invalid token (HTTP 401)', () {
      final error = drive.DetailedApiRequestError(
        401,
        'Invalid Credentials / Token expired',
      );

      final errorInfo = service.parseDriveError(error);
      expect(errorInfo.type, equals(DriveErrorType.tokenExpired));
      expect(errorInfo.statusCode, equals(401));
      expect(errorInfo.userMessage, contains('session expired'));
    });

    test('parseDriveError correctly identifies network disconnection', () {
      const error = SocketException('Failed host lookup: googleapis.com');

      final errorInfo = service.parseDriveError(error);
      expect(errorInfo.type, equals(DriveErrorType.noNetwork));
      expect(errorInfo.userMessage, contains('No internet connection'));
    });

    test('DriveErrorInfo format and technical details formatting', () {
      const info = DriveErrorInfo(
        type: DriveErrorType.driveApiDisabled,
        userMessage: 'Drive API is disabled',
        technicalDetails: 'HTTP 403: Api disabled',
        statusCode: 403,
      );

      expect(info.statusCode, equals(403));
      expect(info.toString(), contains('Drive API is disabled'));
      expect(info.toString(), contains('DriveErrorType.driveApiDisabled'));
    });

    test('SyncingVideoItem copyWith and formattedSize work properly', () {
      final item = SyncingVideoItem(
        title: 'sample.mp4',
        filePath: '/tmp/sample.mp4',
        sizeBytes: 15 * 1024 * 1024,
        progress: 0.25,
        status: 'uploading',
      );

      expect(item.formattedSize, equals('15.0 MB'));
      final updated = item.copyWith(progress: 1.0, status: 'synced');
      expect(updated.progress, equals(1.0));
      expect(updated.status, equals('synced'));
    });

    test('CloudDriveFile formattedDate and formattedSize calculations', () {
      final file = CloudDriveFile(
        id: 'drive_123',
        name: 'recording.mp4',
        sizeBytes: 50 * 1024 * 1024,
        createdTime: DateTime.now(),
      );

      expect(file.formattedSize, equals('50.0 MB'));
      expect(file.formattedDate, contains('Today at'));
    });

    test('parseDriveError correctly identifies OAuth consent blocked (test user required)', () {
      final error = drive.DetailedApiRequestError(
        403,
        'Access denied. Project in test mode requires test user.',
      );

      final errorInfo = service.parseDriveError(error);
      expect(errorInfo.type, equals(DriveErrorType.oauthConsentBlocked));
      expect(errorInfo.userMessage, contains('Test User'));
    });

    test('DriveException with uploadVerificationFailed encapsulates verification errors', () {
      final exception = DriveException(
        DriveErrorType.uploadVerificationFailed,
        'Upload verification failed: Drive file size (100 B) does not match local file size (200 B).',
      );

      final errorInfo = service.parseDriveError(exception);
      expect(errorInfo.type, equals(DriveErrorType.uploadVerificationFailed));
      expect(errorInfo.userMessage, contains('Upload verification failed'));
    });
  });
}
