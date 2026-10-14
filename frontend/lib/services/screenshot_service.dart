import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import '../models/app_models.dart';
import 'recording_service.dart';

class ScreenshotService {
  static final GlobalKey repaintBoundaryKey = GlobalKey();

  /// Captures whatever is currently displayed on screen and saves to system Gallery
  static Future<bool> captureAndSave(BuildContext? context) async {
    try {
      final boundary = repaintBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint('Screenshot boundary is null');
        return false;
      }

      // Capture UI
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return false;
      final bytes = byteData.buffer.asUint8List();

      final now = DateTime.now();
      final dateStr = DateFormat('yyyyMMdd_HHmmss').format(now);
      final filename = 'Screenshot_$dateStr.png';

      // 1. Save to local recordings folder
      final recDir = await RecordingService().getRecordingsDirectory();
      final localFile = File('${recDir.path}/$filename');
      await localFile.writeAsBytes(bytes);

      // 2. Save to Android/iOS native Gallery (MediaStore)
      await RecordingService().saveImageToGallery(bytes, filename: filename);
      await RecordingService().scanFile(localFile.path);

      // 3. Register in in-memory / disk library
      final mediaItem = MediaItem(
        id: 'screenshot_${now.millisecondsSinceEpoch}',
        title: filename,
        date: DateFormat('MMM d, yyyy h:mm a').format(now),
        duration: 'Screenshot',
        size: RecordingService().formatSize(bytes.length),
        resolution: '${image.width}x${image.height}',
        type: 'screenshot',
        thumbnail: localFile.path,
        filePath: localFile.path,
      );
      RecordingService().addSavedRecording(mediaItem);

      // 4. Show confirmation SnackBar
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF1E293B),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Screenshot saved to Gallery ($filename)',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      return true;
    } catch (e) {
      debugPrint('Screenshot error: $e');
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
            content: Text('Failed to take screenshot: $e'),
          ),
        );
      }
      return false;
    }
  }
}
