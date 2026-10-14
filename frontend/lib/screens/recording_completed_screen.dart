import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_file/open_file.dart';
import '../../models/app_models.dart';
import '../../services/recording_service.dart';
import '../../services/app_notification_service.dart';
import '../../services/preferences_service.dart';
import '../../services/recording_auth_service.dart';
import '../../services/google_drive_backup_service.dart';
import '../../widgets/facecam_window.dart';
import 'video_editor_screen.dart';
import 'main_wrapper_screen.dart';

class ExportPreset {
  final String key;
  final String name;
  final String description;
  final int targetWidth;
  final int targetHeight;
  final int targetBitrateBps;
  final int targetFps;
  final String badge;

  const ExportPreset({
    required this.key,
    required this.name,
    required this.description,
    required this.targetWidth,
    required this.targetHeight,
    required this.targetBitrateBps,
    required this.targetFps,
    required this.badge,
  });
}

const List<ExportPreset> kExportPresets = [
  ExportPreset(
    key: 'high_perf_1080p',
    name: 'H.264 High Performance MP4',
    description: '1080p • 60fps • 16 Mbps — Studio master quality',
    targetWidth: 1080,
    targetHeight: 1920,
    targetBitrateBps: 16000000,
    targetFps: 60,
    badge: '1080p • 60fps • 16M',
  ),
  ExportPreset(
    key: 'social_1080p',
    name: 'Social Media 1080p',
    description: '1080p • 30fps • 8 Mbps — Ideal for YouTube, WhatsApp, Reels',
    targetWidth: 1080,
    targetHeight: 1920,
    targetBitrateBps: 8000000,
    targetFps: 30,
    badge: '1080p • 30fps • 8M',
  ),
  ExportPreset(
    key: 'small_720p',
    name: 'Small File 720p',
    description: '720p • 30fps • 2.5 Mbps — Fast upload, 60% smaller file size',
    targetWidth: 720,
    targetHeight: 1280,
    targetBitrateBps: 2500000,
    targetFps: 30,
    badge: '720p • 30fps • 2.5M',
  ),
  ExportPreset(
    key: 'original',
    name: 'Original Quality',
    description: 'Lossless remux with source resolution, bitrate and frame rate',
    targetWidth: 0,
    targetHeight: 0,
    targetBitrateBps: 0,
    targetFps: 0,
    badge: 'Original',
  ),
];

class RecordingCompletedScreen extends StatefulWidget {
  final RecordingMode selectedMode;
  final int duration;
  final String? filePath;
  final RecordingSettings? settings;

  const RecordingCompletedScreen({
    super.key,
    required this.selectedMode,
    required this.duration,
    this.filePath,
    this.settings,
  });

  @override
  State<RecordingCompletedScreen> createState() => _RecordingCompletedScreenState();
}

class _RecordingCompletedScreenState extends State<RecordingCompletedScreen> {
  late String _filename;
  late TextEditingController _filenameController;
  bool _isSaved = false;
  bool _isSaving = false;  // guard against double-taps
  VideoPlayerController? _videoController;

  // ── Quick Export Profile state ───────────────────────────────────────────
  late String _selectedPresetKey;
  bool _isExporting = false;
  double _exportProgress = 0.0;
  String? _exportedFilePath;

  // ── Google Drive Direct Backup state ────────────────────────────────────
  String _driveStatus = 'idle'; // 'idle', 'uploading', 'uploaded', 'failed'
  double _driveProgress = 0.0;
  String? _driveFileLink;
  String? _driveAccountEmail;
  String? _driveErrorMessage;

  ExportPreset get _currentPreset => kExportPresets.firstWhere(
    (p) => p.key == _selectedPresetKey,
    orElse: () => kExportPresets[1],
  );

  // Dual-Track Studio Mix controls for Voice + Screen mode
  double _micVolume = 1.0;
  double _systemVolume = 0.85;
  bool _micMuted = false;
  bool _systemMuted = false;
  bool _noiseCancellationActive = true;
  bool _autoDuckingActive = true;

  // ── Fullscreen state ──────────────────────────────────────────────────────
  bool _isFullscreen = false;

  void _enterFullscreen() {
    setState(() => _isFullscreen = true);
    if (!kIsWeb && !Platform.isWindows) {
      final ar = _videoController?.value.aspectRatio ?? 16 / 9;
      if (ar > 1.0) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  void _exitFullscreen() {
    setState(() => _isFullscreen = false);
    if (!kIsWeb && !Platform.isWindows) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  double get _progress {
    if (_videoController != null &&
        _videoController!.value.isInitialized &&
        _videoController!.value.duration.inMilliseconds > 0) {
      return (_videoController!.value.position.inMilliseconds /
              _videoController!.value.duration.inMilliseconds)
          .clamp(0.0, 1.0);
    }
    return 0.0;
  }

  @override
  void initState() {
    super.initState();
    RecordingAuthService.resetSessionAuth();
    _filename = widget.filePath != null ? widget.filePath!.split(RegExp(r'[\\/]')).last : 'recording.mp4';
    _filenameController = TextEditingController(text: _filename);
    _selectedPresetKey = PreferencesService().quickExportPreset;

    // Video controller initialization moved to a separate method with retry logic.
    _initializeVideoController();
  }

  @override
  void dispose() {
    RecordingAuthService.resetSessionAuth();
    _filenameController.dispose();
    _videoController?.dispose();
    // Always restore orientation/UI when leaving this screen
    if (!kIsWeb && !Platform.isWindows) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  void _shareFile() async {
    final modeLabel = widget.selectedMode == RecordingMode.voiceScreen
        ? 'Voice + Screen Recording (Dual-Track Audio)'
        : 'Screen Recording';
    final shareText = 'Check out my $modeLabel: $_filename (${_formatDuration(widget.duration)})';
    final filePath = widget.filePath;

    if (!kIsWeb && filePath != null) {
      final file = File(filePath);
      if (file.existsSync()) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(filePath)],
            text: shareText,
          ),
        );
        return;
      }
    }
    await SharePlus.instance.share(ShareParams(text: shareText));
  }

  void _deleteFile() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete Recording?'),
        content: Text('Are you sure you want to delete "$_filename"? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        if (!kIsWeb && widget.filePath != null) {
          final file = File(widget.filePath!);
          if (await file.exists()) {
            await file.delete();
          }
        }
        if (widget.filePath != null) {
          RecordingService().deleteSavedItem(widget.filePath!);
          PreferencesService().removeCloudFile(widget.filePath!);
          PreferencesService().removeCloudFile(_filename);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recording deleted successfully.')),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } catch (e) {
        debugPrint('Failed to delete file: $e');
      }
    }
  }

  void _trimFile() {
    final path = widget.filePath ?? 'demo_recording.mp4';
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VideoEditorScreen(filePath: path)),
    );
  }

  void _saveFile() async {
    // Guard: don't allow double-tap during save
    if (_isSaving || _isSaved) return;
    setState(() => _isSaving = true);

    try {
      String finalPath = widget.filePath ?? '';

      // 1. Rename file on disk if the user edited the filename
      if (!kIsWeb && widget.filePath != null) {
        try {
          final oldFile = File(widget.filePath!);
          if (await oldFile.exists()) {
            final newPath = '${oldFile.parent.path}/$_filename';
            if (oldFile.path != newPath) {
              await oldFile.rename(newPath);
              finalPath = newPath;
              RecordingService().renameSavedItem(widget.filePath!, _filename,
                  newFilePath: finalPath);
            }
          }
        } catch (e) {
          debugPrint('File rename note: $e');
        }
      }

      if (kIsWeb || finalPath.isEmpty) {
        // Web: just mark as saved in-app
        if (mounted) {
          setState(() { _isSaved = true; _isSaving = false; });
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              duration: const Duration(seconds: 4),
              content: const Text('Recording saved to library'),
            ));
        }
        return;
      }

      // 2. Request Gallery write permission (Android)
      bool galleryPermissionGranted = false;
      try {
        PermissionStatus status;
        if (Platform.isAndroid) {
          // Android 13+: uses granular media permissions
          // Android 10-12: uses storage permission
          // Android 9-: uses WRITE_EXTERNAL_STORAGE
          if (await Permission.videos.isGranted) {
            status = PermissionStatus.granted;
          } else {
            status = await Permission.videos.request();
            if (!status.isGranted) {
              // Fallback for older Android
              status = await Permission.manageExternalStorage.request();
            }
          }
        } else {
          // iOS: photos permission
          status = await Permission.photos.request();
        }
        galleryPermissionGranted = status.isGranted;
      } catch (e) {
        debugPrint('Permission check error: $e');
        // Treat as no permission but still save to app library below
      }

      // 3. Save to phone Gallery via native MediaStore / Photos API
      bool savedToGallery = false;
      if (galleryPermissionGranted) {
        try {
          savedToGallery = await RecordingService().saveToGallery(finalPath);
        } catch (e) {
          debugPrint('saveToGallery error: $e');
        }
      }

      // 4. Make sure the file is still indexed in the app library
      //    (it was already added in stopRecording — this ensures the
      //     renamed path is reflected)
      if (finalPath != widget.filePath) {
        RecordingService().renameSavedItem(
          widget.filePath ?? finalPath,
          _filename,
          newFilePath: finalPath,
        );
      }

      // 5. Show result feedback
      if (mounted) {
        setState(() {
          _isSaved = true;
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        if (savedToGallery) {
          // Trigger export-complete notification (respects prefs)
          AppNotificationService.notifyExportComplete(
            context,
            label: Platform.isWindows
                ? 'Saved to Videos & Library — $_filename'
                : 'Saved to Gallery & Library — $_filename',
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 4),
              backgroundColor: const Color(0xFF111827),
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      Platform.isWindows
                          ? 'Saved to Videos\\Studio Capture & Library'
                          : 'Saved to Gallery (Movies/Studio Capture) & Library',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              action: Platform.isWindows
                  ? SnackBarAction(
                      label: 'Show in Explorer',
                      textColor: const Color(0xFFFBBF24),
                      onPressed: () => RecordingService().showInExplorer(finalPath),
                    )
                  : SnackBarAction(
                      label: 'Library',
                      textColor: const Color(0xFFFBBF24),
                      onPressed: () => MainWrapperScreen.navigateToTab(context, 2),
                    ),
            ),
          );
        } else if (!galleryPermissionGranted) {
          // Permission denied — explain and guide user
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 7),
              backgroundColor: const Color(0xFF1F2937),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Saved to app library only',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Gallery access was denied. To also save to Gallery, enable Media permission in Settings.',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 11,
                      color: const Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
              action: SnackBarAction(
                label: 'Settings',
                textColor: const Color(0xFFFBBF24),
                onPressed: () => openAppSettings(),
              ),
            ),
          );
        } else {
          // Permission granted but save failed for another reason
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 5),
              backgroundColor: const Color(0xFF1F2937),
              content: Text(
                'Saved to app library. Gallery save failed — check storage space.',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
              action: SnackBarAction(
                label: 'Library',
                textColor: const Color(0xFFFBBF24),
                onPressed: () => MainWrapperScreen.navigateToTab(context, 2),
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('_saveFile error: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ));
      }
    }
  }

  // ── Quick Export Profile Methods ─────────────────────────────────────────

  void _showExportPresetSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                top: 12,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.tune, color: Color(0xFFDC2626), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Quick Export Profiles',
                            style: GoogleFonts.manrope(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            'Re-encode video with hardware acceleration',
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ...kExportPresets.map((preset) {
                    final isSelected = preset.key == _selectedPresetKey;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? const Color(0xFFDC2626) : const Color(0xFFE2E8F0),
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          setSheetState(() => _selectedPresetKey = preset.key);
                          setState(() => _selectedPresetKey = preset.key);
                          PreferencesService().setQuickExportPreset(preset.key);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Radio<String>(
                                value: preset.key,
                                groupValue: _selectedPresetKey,
                                activeColor: const Color(0xFFDC2626),
                                onChanged: (val) {
                                  if (val != null) {
                                    setSheetState(() => _selectedPresetKey = val);
                                    setState(() => _selectedPresetKey = val);
                                    PreferencesService().setQuickExportPreset(val);
                                  }
                                },
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          preset.name,
                                          style: GoogleFonts.manrope(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFF1E293B),
                                          ),
                                        ),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isSelected ? const Color(0xFFDC2626) : const Color(0xFFE2E8F0),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            preset.badge,
                                            style: GoogleFonts.hankenGrotesk(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: isSelected ? Colors.white : const Color(0xFF475569),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      preset.description,
                                      style: GoogleFonts.hankenGrotesk(
                                        fontSize: 11.5,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _performQuickExport(_currentPreset);
                      },
                      icon: const Icon(Icons.flash_on_rounded, size: 18),
                      label: Text(
                        'Apply & Export (${_currentPreset.name.split(' ').first})',
                        style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _performQuickExport(ExportPreset preset) async {
    if (_isExporting) return;
    final inputPath = widget.filePath;
    if (inputPath == null || !File(inputPath).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Source recording file not found.')),
      );
      return;
    }

    setState(() {
      _isExporting = true;
      _exportProgress = 0.05;
    });

    void progressListener() {
      if (mounted) {
        setState(() {
          _exportProgress = RecordingService.transcodeProgressNotifier.value;
        });
      }
    }

    RecordingService.transcodeProgressNotifier.addListener(progressListener);

    try {
      final now = DateTime.now();
      final timeStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final dir = File(inputPath).parent;
      final outName = 'Export_${preset.key}_$timeStr.mp4';
      final outPath = '${dir.path}/$outName';

      final success = await RecordingService().transcodeVideo(
        inputPath: inputPath,
        outputPath: outPath,
        targetWidth: preset.targetWidth,
        targetHeight: preset.targetHeight,
        targetBitrateBps: preset.targetBitrateBps,
        targetFps: preset.targetFps,
      );

      RecordingService.transcodeProgressNotifier.removeListener(progressListener);

      if (success && File(outPath).existsSync()) {
        await RecordingService().saveToGallery(outPath);
        final meta = await RecordingService().getVideoMetadata(outPath);
        final sizeBytes = File(outPath).lengthSync();
        final res = meta != null && meta['width'] != null
            ? '${meta['width']}x${meta['height']}'
            : preset.badge;
        final durMs = (meta?['durationMs'] as num?)?.toInt() ?? (widget.duration * 1000);
        final durStr = RecordingService().formatDuration(Duration(milliseconds: durMs));

        final newItem = MediaItem(
          id: 'export_${DateTime.now().millisecondsSinceEpoch}',
          title: outName,
          type: 'video',
          thumbnail: meta?['thumbnailPath'] as String? ?? '',
          duration: durStr,
          resolution: res,
          date: 'Today',
          size: RecordingService().formatSize(sizeBytes),
          filePath: outPath,
        );
        RecordingService().addSavedRecording(newItem);

        if (mounted) {
          setState(() {
            _isExporting = false;
            _exportProgress = 1.0;
            _exportedFilePath = outPath;
          });

          AppNotificationService.notifyExportComplete(
            context,
            label: 'Quick Export Complete — $outName',
            filePath: outPath,
            isTrim: false,
          );

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 5),
              content: Text(
                'Exported as ${preset.name}!\nSaved to Gallery & Library ($res • ${RecordingService().formatSize(sizeBytes)})',
                style: GoogleFonts.hankenGrotesk(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              action: SnackBarAction(
                label: 'View',
                textColor: Colors.white,
                onPressed: () => MainWrapperScreen.navigateToTab(context, 2),
              ),
            ),
          );
        }
      } else {
        throw Exception('Hardware transcoding could not finalize output file.');
      }
    } catch (e) {
      RecordingService.transcodeProgressNotifier.removeListener(progressListener);
      debugPrint('Export error: $e');
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
        _showExportFailureDialog(preset, e.toString());
      }
    }
  }

  void _showExportFailureDialog(ExportPreset preset, String error) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 22),
            const SizedBox(width: 8),
            Text('Export Failed', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 16)),
          ],
        ),
        content: Text(
          'Failed to export with preset "${preset.name}":\n$error',
          style: GoogleFonts.hankenGrotesk(fontSize: 13, color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () {
              Navigator.pop(ctx);
              _performQuickExport(preset);
            },
            child: const Text('Retry', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Google Drive Direct Upload Methods ───────────────────────────────────

  Future<void> _backupToGoogleDriveDirectly() async {
    final filePath = widget.filePath;
    if (filePath == null || !File(filePath).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recording file not found on device.')),
      );
      return;
    }

    final backupService = GoogleDriveBackupService();

    // 1. Ensure authenticated and scope authorized (shows account chooser if needed)
    final isAuthorized = await backupService.ensureAuthorized(context: context);
    if (!mounted || !isAuthorized) {
      return;
    }

    final email = backupService.currentUser?.email ?? 'Google Drive';

    setState(() {
      _driveStatus = 'uploading';
      _driveProgress = 0.05;
      _driveAccountEmail = email;
      _driveErrorMessage = null;
    });

    final fileName = _filename;
    void progressListener() {
      final items = backupService.activeSyncingNotifier.value;
      final item = items.firstWhere(
        (i) => i.title == fileName || i.filePath == filePath,
        orElse: () => SyncingVideoItem(title: '', filePath: '', sizeBytes: 0, progress: 0, status: ''),
      );
      if (item.title.isNotEmpty && mounted) {
        setState(() {
          _driveProgress = item.progress;
        });
      }
    }

    backupService.activeSyncingNotifier.addListener(progressListener);

    try {
      final success = await backupService.uploadRecording(
        filePath,
        title: fileName,
        force: true,
        context: context,
      );

      backupService.activeSyncingNotifier.removeListener(progressListener);

      if (success && mounted) {
        final files = backupService.cloudFilesNotifier.value;
        final matched = files.firstWhere(
          (f) => f.name == fileName,
          orElse: () => CloudDriveFile(id: '', name: '', sizeBytes: 0, webViewLink: 'https://drive.google.com'),
        );

        setState(() {
          _driveStatus = 'uploaded';
          _driveProgress = 1.0;
          _driveFileLink = matched.webViewLink ?? 'https://drive.google.com';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 4),
            content: Text('Uploaded to $email\'s Drive!'),
            action: SnackBarAction(
              label: 'Open',
              textColor: Colors.white,
              onPressed: () {
                if (_driveFileLink != null) {
                  launchUrl(Uri.parse(_driveFileLink!), mode: LaunchMode.externalApplication);
                }
              },
            ),
          ),
        );
      } else if (mounted) {
        final errorInfo = backupService.lastErrorInfo;
        final displayMsg = errorInfo?.userMessage ?? backupService.syncStatusNotifier.value ?? 'Upload failed';

        setState(() {
          _driveStatus = 'failed';
          _driveErrorMessage = displayMsg;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFDC2626),
            content: Text('Drive upload failed: $displayMsg'),
            action: SnackBarAction(
              label: 'Details',
              textColor: Colors.white,
              onPressed: () {
                backupService.showErrorDetailsDialog(context);
              },
            ),
          ),
        );
      }
    } catch (e) {
      backupService.activeSyncingNotifier.removeListener(progressListener);
      if (mounted) {
        final errorInfo = backupService.lastErrorInfo;
        final displayMsg = errorInfo?.userMessage ?? e.toString();
        setState(() {
          _driveStatus = 'failed';
          _driveErrorMessage = displayMsg;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFDC2626),
            content: Text('Drive upload failed: $displayMsg'),
            action: SnackBarAction(
              label: 'Details',
              textColor: Colors.white,
              onPressed: () {
                backupService.showErrorDetailsDialog(context);
              },
            ),
          ),
        );
      }
    }
  }

  // Helper to initialize video controller with optional retries
  void _initializeVideoController({int retries = 5}) async {
    if (kIsWeb) {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse('https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4'),
      )..initialize().then((_) => setState(() {})).catchError((e) => debugPrint('Web video preview error: $e'));
      return;
    }
    if (widget.filePath == null) return;
    final file = File(widget.filePath!);
    if (await file.exists()) {
      _videoController = VideoPlayerController.file(file)
        ..initialize().then((_) => setState(() {})).catchError((e) => debugPrint('File video preview error: $e'));
    } else if (retries > 0) {
      // Wait a bit and retry
      await Future.delayed(const Duration(milliseconds: 500));
      _initializeVideoController(retries: retries - 1);
    } else {
      debugPrint('Recorded file still not found after retries: ${widget.filePath}');
    }
  }

  String _formatDuration(int seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _calculateFileSize() {
    final bitrate = widget.settings?.bitrate ?? 16.0;
    final dur = widget.duration > 0 ? widget.duration : 5;
    final mb = (bitrate * dur) / 8.0;
    return '${(mb < 0.8 ? 0.8 : mb).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final formattedDuration = _formatDuration(widget.duration);
    final fileSize = _calculateFileSize();
    final resolution = widget.settings?.resolution ?? '1080p';
    final fps = widget.settings?.fps ?? 60;
    final isVoiceScreen = widget.selectedMode == RecordingMode.voiceScreen;

    return PopScope(
      // When fullscreen, intercept back to exit fullscreen first
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isFullscreen) _exitFullscreen();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFAFAFC),
        body: Stack(
          children: [
            // ── Normal review screen layout ─────────────────────────────────
            SafeArea(
              child: Column(
                children: [
                  // Top App Bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      border: const Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2))],
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Color(0xFF111827), size: 22),
                            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Recording Saved',
                                style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF111827)),
                              ),
                              Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF10B981)),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isVoiceScreen
                                        ? 'Auto-saved to Library • Dual-Track Audio'
                                        : 'Auto-saved to Library • $resolution ${fps}fps',
                                    style: GoogleFonts.hankenGrotesk(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF059669), letterSpacing: 0.2),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            _buildIconButton(Icons.add_to_drive, onTap: _backupToGoogleDriveDirectly),
                            _buildIconButton(Icons.share, onTap: _shareFile),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Main content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Video preview
                          Stack(
      children: [
        _buildVideoPreview(formattedDuration, fileSize, resolution, fps, isVoiceScreen),
        // Fullscreen toggle button
        Positioned(
          bottom: 8,
          right: 8,
          child: IconButton(
            icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
            onPressed: () {
              if (_isFullscreen) {
                _exitFullscreen();
              } else {
                _enterFullscreen();
              }
            },
          ),
        ),
      ],
    ),

                          const SizedBox(height: 20),

                          // Telemetry chips
                          _buildTelemetryChips(formattedDuration, fileSize, isVoiceScreen),

                          const SizedBox(height: 20),

                          // Voice + Screen Dual-Track Audio Studio Mixer
                          if (isVoiceScreen) ...[
                            _buildDualTrackStudioMix(),
                            const SizedBox(height: 20),
                          ],

                          // Filename editor
                          _buildFilenameEditor(),

                          const SizedBox(height: 20),

                          // Quick actions: Save, Trim, Share, Delete
                          _buildQuickActions(),

                          const SizedBox(height: 20),

                          // Storage & workflow
                          _buildStorageWorkflow(),

                          const SizedBox(height: 20),

                          // Bottom actions
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.pushReplacementNamed(
                                      context,
                                      '/recording-setup',
                                      arguments: widget.selectedMode,
                                    );
                                  },
                                  icon: const Icon(Icons.videocam, size: 18, color: Color(0xFF374151)),
                                  label: Text('Record Another', style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF111827))),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    side: const BorderSide(color: Color(0xFFD1D5DB)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    MainWrapperScreen.navigateToTab(context, 2);
                                  },
                                  icon: const Icon(Icons.folder_open, size: 18, color: Color(0xFF374151)),
                                  label: Text('Recordings', style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF111827))),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    backgroundColor: const Color(0xFFF3F4F6),
                                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Fullscreen overlay — covers EVERYTHING ─────────────────────
            if (_isFullscreen) _buildFullscreenOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, {VoidCallback? onTap}) {
    return Container(
      width: 36,
      height: 36,
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: IconButton(
        icon: Icon(icon, size: 18, color: const Color(0xFF374151)),
        onPressed: onTap,
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildVideoPreview(String duration, String fileSize, String resolution, int fps, bool isVoiceScreen) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            children: [
              if (_videoController != null && _videoController!.value.isInitialized)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _videoController!.value.size.width,
                        height: _videoController!.value.size.height,
                        child: VideoPlayer(_videoController!),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0C0E14), Color(0xFF1E1F26), Color(0xFF0C0E14)],
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isVoiceScreen ? Icons.mic_external_on : Icons.videocam,
                          color: Colors.white.withValues(alpha: 0.4),
                          size: 40,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isVoiceScreen ? 'Dual Audio Preview Ready' : 'Screen Capture Ready',
                          style: GoogleFonts.hankenGrotesk(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              // Vignette
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.4), const Color(0xFF0C0E14)],
                  ),
                ),
              ),
              // Top badges
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF33343B).withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(9999),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: Row(
                            children: [
                              Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFDC2626))),
                              const SizedBox(width: 6),
                              Text('$resolution • ${fps}FPS', style: GoogleFonts.hankenGrotesk(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: 0.2)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF33343B).withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(9999),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          child: Text('HDR', style: GoogleFonts.hankenGrotesk(fontSize: 10, color: const Color(0xFFB9C8DE), fontWeight: FontWeight.w500)),
                        ),
                        if (widget.selectedMode == RecordingMode.facecam || (widget.settings?.showFacecam == true)) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626).withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(9999),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.camera_front, size: 10, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  'PiP • ${widget.settings?.facecamShape ?? "Circle Head"}',
                                  style: GoogleFonts.hankenGrotesk(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isVoiceScreen ? const Color(0xFF7C3AED).withValues(alpha: 0.85) : const Color(0xFF33343B).withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(9999),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          Icon(isVoiceScreen ? Icons.multitrack_audio : Icons.surround_sound, size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            isVoiceScreen ? 'DUAL-TRACK 48k' : 'STEREO 48k',
                            style: GoogleFonts.hankenGrotesk(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Composited Facecam overlay preview (only shown if video is not actively initialized/playing,
              // as native recorded video already has the facecam burned into the video frames)
              if ((widget.selectedMode == RecordingMode.facecam || (widget.settings?.showFacecam == true)) &&
                  (kIsWeb || _videoController == null || !_videoController!.value.isInitialized))
                Positioned(
                  bottom: 48,
                  right: 14,
                  child: FacecamWindow(
                    shape: widget.settings?.facecamShape ?? 'Circle Head',
                    size: 96,
                    isLive: false,
                    showBorder: true,
                    previewImagePath: RecordingService().lastFacecamSnapshotPath,
                  ),
                ),
              // Play button
              Center(
                child: GestureDetector(
                  onTap: () {
                    if (Platform.isWindows && widget.filePath != null) {
                      OpenFile.open(widget.filePath!);
                      return;
                    }
                    if (_videoController != null) {
                      setState(() {
                        _videoController!.value.isPlaying ? _videoController!.pause() : _videoController!.play();
                      });
                    }
                  },
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFDC2626),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFFDC2626).withValues(alpha: 0.35), blurRadius: 16, spreadRadius: 4),
                        BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Icon(
                      (_videoController?.value.isPlaying ?? false) ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ),
              // Bottom scrubber
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, const Color(0xFF0C0E14).withValues(alpha: 0.95), const Color(0xFF0C0E14)],
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          // Position indicator
                          Text('00:00', style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFFFFB4AB), letterSpacing: 0.22)),
                          const SizedBox(width: 4),
                          Text('/', style: GoogleFonts.hankenGrotesk(fontSize: 11, color: Colors.white54)),
                          const SizedBox(width: 4),
                          Text(duration, style: GoogleFonts.hankenGrotesk(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w500)),
                          const Spacer(),
                          // ── Fullscreen expand button ──────────────────────────────
                          if (_videoController != null && _videoController!.value.isInitialized)
                            GestureDetector(
                              onTap: _enterFullscreen,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                                ),
                                child: const Icon(
                                  Icons.fullscreen_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Stack(
                        children: [
                          Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: const Color(0xFF33343B),
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: _progress,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDC2626),
                                  borderRadius: BorderRadius.circular(1.5),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── YouTube-style fullscreen overlay ─────────────────────────────────────
  Widget _buildFullscreenOverlay() {
    if (_videoController == null) return const SizedBox.shrink();
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: VideoPlayer(_videoController!),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                onPressed: _exitFullscreen,
              ),
            ),
            // Play/pause overlay
            Center(
              child: GestureDetector(
                onTap: () {
                  if (_videoController != null) {
                    setState(() {
                      if (_videoController!.value.isPlaying) {
                        _videoController!.pause();
                      } else {
                        _videoController!.play();
                      }
                    });
                  }
                },
                child: Icon(
                  _videoController!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryChips(String duration, String fileSize, bool isVoiceScreen) {
    final bitrate = '${(widget.settings?.bitrate ?? 16.0).toStringAsFixed(0)} Mbps';
    final chips = [
      {'icon': Icons.timer, 'value': duration, 'label': 'Length'},
      {'icon': Icons.storage, 'value': fileSize, 'label': 'Size'},
      {'icon': Icons.speed, 'value': bitrate, 'label': 'Bitrate'},
      {
        'icon': isVoiceScreen ? Icons.multitrack_audio : Icons.graphic_eq,
        'value': isVoiceScreen ? 'Dual-Track' : '48 kHz',
        'label': isVoiceScreen ? 'Mic + Sys' : 'Stereo',
      },
    ];

    return Row(
      children: chips.map((chip) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 1))],
          ),
          child: Column(
            children: [
              Icon(chip['icon'] as IconData, size: 16, color: const Color(0xFF9CA3AF)),
              const SizedBox(height: 4),
              Text(chip['value'] as String, style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
              Text(chip['label'] as String, style: GoogleFonts.hankenGrotesk(fontSize: 10, fontWeight: FontWeight.w500, color: const Color(0xFF9CA3AF))),
            ],
          ),
        ),
      )).toList(),
    );
  }

  Widget _buildDualTrackStudioMix() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E7FF)),
        boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.multitrack_audio, size: 18, color: Color(0xFF7C3AED)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dual-Track Audio Studio Mix',
                      style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF111827)),
                    ),
                    Text(
                      'Simultaneous Mic Commentary + System Audio',
                      style: GoogleFonts.hankenGrotesk(fontSize: 11, color: const Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9999),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(width: 5, height: 5, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF10B981))),
                    const SizedBox(width: 4),
                    Text(
                      'Synced (0ms)',
                      style: GoogleFonts.hankenGrotesk(fontSize: 9, fontWeight: FontWeight.w700, color: const Color(0xFF047857)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Track 1: Voice Commentary (Mic)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF3F4F6)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      _micMuted ? Icons.mic_off : Icons.mic,
                      size: 16,
                      color: _micMuted ? const Color(0xFF9CA3AF) : const Color(0xFF7C3AED),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Track 1: Microphone Commentary',
                        style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF1F2937)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Noise Cancellation Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _noiseCancellationActive ? const Color(0xFF10B981).withValues(alpha: 0.15) : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _noiseCancellationActive ? 'AI Noise: Active' : 'Filter Bypass',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: _noiseCancellationActive ? const Color(0xFF047857) : const Color(0xFF6B7280),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() => _micMuted = !_micMuted),
                      child: Text(
                        _micMuted ? 'UNMUTE' : 'MUTE',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _micMuted ? const Color(0xFFDC2626) : const Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text('0%', style: GoogleFonts.hankenGrotesk(fontSize: 9, color: const Color(0xFF9CA3AF))),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          activeTrackColor: const Color(0xFF7C3AED),
                          inactiveTrackColor: const Color(0xFFE5E7EB),
                          thumbColor: const Color(0xFF7C3AED),
                        ),
                        child: Slider(
                          value: _micMuted ? 0.0 : _micVolume,
                          min: 0.0,
                          max: 1.0,
                          onChanged: _micMuted ? null : (v) => setState(() => _micVolume = v),
                        ),
                      ),
                    ),
                    Text('${(_micMuted ? 0 : _micVolume * 100).toInt()}%', style: GoogleFonts.hankenGrotesk(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF374151))),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Track 2: Internal / System Audio
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF3F4F6)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      _systemMuted ? Icons.volume_off : Icons.volume_up,
                      size: 16,
                      color: _systemMuted ? const Color(0xFF9CA3AF) : const Color(0xFF2563EB),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Track 2: System / App Audio',
                        style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF1F2937)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Lossless 48kHz',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1D4ED8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() => _systemMuted = !_systemMuted),
                      child: Text(
                        _systemMuted ? 'UNMUTE' : 'MUTE',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _systemMuted ? const Color(0xFFDC2626) : const Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text('0%', style: GoogleFonts.hankenGrotesk(fontSize: 9, color: const Color(0xFF9CA3AF))),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          activeTrackColor: const Color(0xFF2563EB),
                          inactiveTrackColor: const Color(0xFFE5E7EB),
                          thumbColor: const Color(0xFF2563EB),
                        ),
                        child: Slider(
                          value: _systemMuted ? 0.0 : _systemVolume,
                          min: 0.0,
                          max: 1.0,
                          onChanged: _systemMuted ? null : (v) => setState(() => _systemVolume = v),
                        ),
                      ),
                    ),
                    Text('${(_systemMuted ? 0 : _systemVolume * 100).toInt()}%', style: GoogleFonts.hankenGrotesk(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF374151))),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Ducking & Sync toggle
          Row(
            children: [
              const Icon(Icons.graphic_eq, size: 14, color: Color(0xFF6B7280)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Auto-duck system audio when speaking (-6dB)',
                  style: GoogleFonts.hankenGrotesk(fontSize: 11, color: const Color(0xFF4B5563)),
                ),
              ),
              _buildSwitch(_autoDuckingActive, (v) => setState(() => _autoDuckingActive = v)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilenameEditor() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.description, size: 16, color: Color(0xFFDC2626)),
                  const SizedBox(width: 8),
                  Text('Filename & Rename', style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF374151))),
                ],
              ),
              Text(
                'Ready to Export',
                style: GoogleFonts.hankenGrotesk(fontSize: 10, fontWeight: FontWeight.w500, color: const Color(0xFF10B981)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _filenameController,
                  style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF111827)),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
                  ),
                  onChanged: (v) => _filename = v,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFF3F4F6),
                ),
                child: IconButton(
                  icon: const Icon(Icons.check, size: 18, color: Color(0xFF10B981)),
                  onPressed: () async {
                    final newName = _filenameController.text.trim();
                    if (newName.isEmpty) return;
                    setState(() => _filename = newName);
                    if (!kIsWeb && widget.filePath != null) {
                      try {
                        final oldFile = File(widget.filePath!);
                        if (await oldFile.exists()) {
                          final newPath = '${oldFile.parent.path}/$_filename';
                          if (oldFile.path != newPath) {
                            await oldFile.rename(newPath);
                            RecordingService().renameSavedItem(
                              widget.filePath!,
                              _filename,
                              newFilePath: newPath,
                            );
                          }
                        }
                      } catch (e) {
                        debugPrint('Filename rename error: $e');
                      }
                    } else if (widget.filePath != null) {
                      RecordingService().renameSavedItem(widget.filePath!, _filename);
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Filename updated to "$_filename" in Library')),
                      );
                    }
                  },
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final saveLabel = _isSaving
        ? 'Saving...'
        : (_isSaved
            ? (Platform.isWindows ? 'Show in Explorer' : 'In Gallery')
            : (Platform.isWindows ? 'Save to Videos' : 'Save to Gallery'));

    final actions = [
      {
        'icon': _isSaved ? (Platform.isWindows ? Icons.folder_open_rounded : Icons.check_circle_rounded) : (Platform.isWindows ? Icons.folder_special_rounded : Icons.photo_library_outlined),
        'label': saveLabel,
        'color': _isSaved ? const Color(0xFF10B981) : const Color(0xFFDC2626),
        'bg': _isSaved ? const Color(0xFF10B981) : const Color(0xFFDC2626),
        'fg': Colors.white,
      },
      {'icon': Icons.content_cut, 'label': 'Trim', 'color': const Color(0xFF1F2937), 'bg': Colors.white, 'fg': const Color(0xFF1F2937)},
      {'icon': Icons.share, 'label': 'Share', 'color': const Color(0xFF1F2937), 'bg': Colors.white, 'fg': const Color(0xFF1F2937)},
      {'icon': Icons.delete, 'label': 'Delete', 'color': const Color(0xFFDC2626), 'bg': const Color(0xFFFEF2F2), 'fg': const Color(0xFFDC2626)},
    ];

    return Row(
      children: actions.map((action) => Expanded(
        child: GestureDetector(
          onTap: () {
            if (action['label'] == 'Share') _shareFile();
            else if (action['label'] == 'Delete') _deleteFile();
            else if (action['label'] == 'Trim') _trimFile();
            else if (action['label'] == 'Save to Gallery' || action['label'] == 'Save to Videos' || action['label'] == 'Save') _saveFile();
            else if (action['label'] == 'Show in Explorer') {
              if (widget.filePath != null) {
                RecordingService().showInExplorer(widget.filePath!);
              }
            } else if (action['label'] == 'In Gallery' || action['label'] == 'Saved') {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Video is already saved in phone Gallery & Library.')),
              );
            }
            // 'Saving...' taps are ignored
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: action['bg'] as Color,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: action['label'] == 'Delete' ? const Color(0xFFFECACA) : const Color(0xFFE5E7EB)),
              boxShadow: (action['label'] == 'Save to Gallery' || action['label'] == 'Save' || action['label'] == 'Saving...')
                  ? [BoxShadow(color: const Color(0xFFDC2626).withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 2))]
                  : [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 2, offset: const Offset(0, 1))],
            ),
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: (action['label'] == 'Save to Gallery' || action['label'] == 'Save' || action['label'] == 'Saving...')
                        ? Colors.white.withOpacity(0.2)
                        : const Color(0xFFF3F4F6),
                    shape: BoxShape.circle,
                  ),
                  child: _isSaving && action['label'] == 'Saving...'
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Icon(action['icon'] as IconData, size: 20, color: action['fg'] as Color),
                ),
                const SizedBox(height: 6),
                Text(action['label'] as String, style: GoogleFonts.hankenGrotesk(fontSize: 10.5, fontWeight: FontWeight.w600, color: action['fg'] as Color), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      )).toList(),
    );
  }

  Widget _buildStorageWorkflow() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(
        children: [
          // Save path
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.folder, size: 16, color: Color(0xFF6B7280)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Storage Location', style: GoogleFonts.hankenGrotesk(fontSize: 10, color: const Color(0xFF9CA3AF))),
                    Text(
                      widget.filePath != null ? widget.filePath! : '/Movies/Studio Capture',
                      style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF111827)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(8)),
                child: IconButton(
                  icon: const Icon(Icons.open_in_new, size: 18, color: Color(0xFF9CA3AF)),
                  onPressed: () {
                    MainWrapperScreen.navigateToTab(context, 2);
                  },
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const Divider(height: 20, color: Color(0xFFF3F4F6)),
          // ── Quick Export Profile ──────────────────────────────────────────
          InkWell(
            onTap: _isExporting ? null : _showExportPresetSelector,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.tune_rounded, size: 18, color: Color(0xFFDC2626)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Quick Export Profile',
                                  style: GoogleFonts.hankenGrotesk(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF111827)),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _currentPreset.badge,
                                    style: GoogleFonts.hankenGrotesk(fontSize: 9.5, fontWeight: FontWeight.w700, color: const Color(0xFF475569)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _isExporting
                                  ? 'Re-encoding video... ${(_exportProgress * 100).toInt()}%'
                                  : _currentPreset.name,
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 11,
                                fontWeight: _isExporting ? FontWeight.w600 : FontWeight.w400,
                                color: _isExporting ? const Color(0xFFDC2626) : const Color(0xFF6B7280),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _isExporting ? null : () => _performQuickExport(_currentPreset),
                        child: _isExporting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(
                                _exportedFilePath != null ? 'Re-export' : 'Export',
                                style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                      ),
                    ],
                  ),
                  if (_isExporting) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _exportProgress,
                        minHeight: 4,
                        backgroundColor: const Color(0xFFFEE2E2),
                        color: const Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 20, color: Color(0xFFF3F4F6)),
          // ── Direct Google Drive Cloud Backup (No Share Sheet) ───────────
          InkWell(
            onTap: _driveStatus == 'uploading' ? null : _backupToGoogleDriveDirectly,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.cloud_upload_rounded, size: 18, color: Color(0xFF2563EB)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Back up to Google Drive',
                              style: GoogleFonts.hankenGrotesk(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF111827)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _driveStatus == 'uploading'
                                  ? 'Uploading to ${_driveAccountEmail ?? "Drive"}... ${(_driveProgress * 100).toInt()}%'
                                  : _driveStatus == 'uploaded'
                                      ? 'Uploaded to ${_driveAccountEmail ?? "Drive"} • In Cloud Vault'
                                      : _driveStatus == 'failed'
                                          ? 'Upload failed: ${_driveErrorMessage ?? "Tap to retry"}'
                                          : 'Upload directly to Studio Capture Recordings in Drive',
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 11,
                                fontWeight: _driveStatus == 'failed' ? FontWeight.w600 : FontWeight.w400,
                                color: _driveStatus == 'uploaded'
                                    ? const Color(0xFF10B981)
                                    : _driveStatus == 'failed'
                                        ? const Color(0xFFDC2626)
                                        : const Color(0xFF6B7280),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (_driveStatus == 'uploaded') ...[
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () {
                            if (_driveFileLink != null) {
                              launchUrl(Uri.parse(_driveFileLink!), mode: LaunchMode.externalApplication);
                            }
                          },
                          icon: const Icon(Icons.open_in_new_rounded, size: 14),
                          label: Text('Open', style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                      ] else if (_driveStatus == 'uploading') ...[
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF2563EB)),
                        ),
                      ] else if (_driveStatus == 'failed') ...[
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFDC2626)),
                            foregroundColor: const Color(0xFFDC2626),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _backupToGoogleDriveDirectly,
                          child: Text('Retry', style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                      ] else ...[
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _backupToGoogleDriveDirectly,
                          child: Text('Drive', style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  if (_driveStatus == 'uploading') ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _driveProgress,
                        minHeight: 4,
                        backgroundColor: const Color(0xFFDBEAFE),
                        color: const Color(0xFF2563EB),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitch(bool value, ValueChanged<bool> onChanged) {
    return Transform.scale(
      scale: 0.8,
      child: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFFDC2626),
      ),
    );
  }
}