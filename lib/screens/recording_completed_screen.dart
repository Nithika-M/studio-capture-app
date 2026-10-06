import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/app_models.dart';
import '../../services/recording_service.dart';
import '../../services/app_notification_service.dart';
import '../../services/preferences_service.dart';
import '../../services/recording_auth_service.dart';
import '../../services/cloud_vault_service.dart';
import '../../widgets/facecam_window.dart';
import 'video_editor_screen.dart';
import 'main_wrapper_screen.dart';

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
  bool _autoUpload = false;
  bool _isSaved = false;
  bool _isSaving = false;  // guard against double-taps
  VideoPlayerController? _videoController;

  // Dual-Track Studio Mix controls for Voice + Screen mode
  double _micVolume = 1.0;
  double _systemVolume = 0.85;
  bool _micMuted = false;
  bool _systemMuted = false;
  bool _noiseCancellationActive = true;
  bool _autoDuckingActive = true;

  // ── Fullscreen state ──────────────────────────────────────────────────────
  bool _isFullscreen = false;
  bool _showControls = true;

  void _enterFullscreen() {
    setState(() => _isFullscreen = true);
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

  void _exitFullscreen() {
    setState(() => _isFullscreen = false);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
    _filename = widget.filePath != null ? widget.filePath!.split('/').last : 'recording.mp4';
    _filenameController = TextEditingController(text: _filename);
    _autoUpload = PreferencesService().autoSync;

    // Video controller initialization moved to a separate method with retry logic.
    _initializeVideoController();
  }

  @override
  void dispose() {
    RecordingAuthService.resetSessionAuth();
    _filenameController.dispose();
    _videoController?.dispose();
    // Always restore orientation/UI when leaving this screen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
            label: 'Saved to Gallery & Library — $_filename',
          );
          if (_autoUpload || PreferencesService().autoSync) {
            CloudVaultService().syncRecording(
              filePath: finalPath,
              title: _filename,
              duration: _formatDuration(widget.duration),
              resolution: widget.settings?.resolution ?? '1080p',
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                duration: const Duration(seconds: 4),
                backgroundColor: const Color(0xFF065F46),
                content: Row(
                  children: [
                    const Icon(Icons.cloud_done_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Auto-uploaded $_filename to Cloud Vault',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 5),
              backgroundColor: const Color(0xFF111827),
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Saved to Gallery & Library',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              action: SnackBarAction(
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
                            _buildIconButton(Icons.cloud_done, onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Recording queued for Cloud Vault backup.')),
                              );
                            }),
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

  /// Format Duration for fullscreen time display
  String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
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
    final actions = [
      {
        'icon': _isSaved ? Icons.check_circle_rounded : Icons.photo_library_outlined,
        'label': _isSaving ? 'Saving...' : (_isSaved ? 'In Gallery' : 'Save to Gallery'),
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
            else if (action['label'] == 'Save to Gallery' || action['label'] == 'Save') _saveFile();
            else if (action['label'] == 'In Gallery' || action['label'] == 'Saved') {
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
                      widget.filePath != null ? widget.filePath! : '/Movies/ConsolidatedRecorder',
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
          // Export profile
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.tune, size: 16, color: Color(0xFF6B7280)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Quick Export Profile', style: GoogleFonts.hankenGrotesk(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF111827))),
                    Text(
                      '${widget.settings?.resolution ?? "1080p"} • ${widget.settings?.fps ?? 60}fps • H.264 MP4',
                      style: GoogleFonts.hankenGrotesk(fontSize: 11, color: const Color(0xFF9CA3AF)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF), size: 20),
            ],
          ),
          const Divider(height: 20, color: Color(0xFFF3F4F6)),
          // Cloud sync
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: const Color(0xFFDC2626).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.cloud_upload, size: 16, color: Color(0xFFDC2626)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Auto-upload to Cloud Vault', style: GoogleFonts.hankenGrotesk(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF111827))),
                    Text('Back up to private cloud storage', style: GoogleFonts.hankenGrotesk(fontSize: 11, color: const Color(0xFF9CA3AF))),
                  ],
                ),
              ),
              _buildSwitch(_autoUpload, (v) {
                setState(() => _autoUpload = v);
                PreferencesService().setAutoSync(v);
                if (v) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Auto-upload enabled. Recordings will back up to Cloud Vault.')),
                  );
                }
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSwitch(bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 24,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: value ? const Color(0xFFDC2626) : const Color(0xFFE5E7EB),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4)],
            ),
          ),
        ),
      ),
    );
  }
}