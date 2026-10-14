import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:open_file/open_file.dart';
import '../models/app_models.dart';
import '../services/recording_service.dart';
import '../widgets/facecam_window.dart';
import 'video_editor_screen.dart';

class VideoPlayerScreen extends StatefulWidget {
  final MediaItem item;

  const VideoPlayerScreen({super.key, required this.item});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with TickerProviderStateMixin {
  late MediaItem _item;
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';
  double _progress = 0.0;
  String _speed = '1.0x';
  bool _loop = true;

  // Fullscreen state
  bool _isFullscreen = false;

  // Controls visibility (YouTube-style: controls auto-hide)
  bool _showControls = true;

  late AnimationController _playPauseController;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _playPauseController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _initPlayer();
  }

  void _initPlayer() {
    if (_item.type == 'screenshot' || _item.filePath == null) {
      return;
    }

    final file = File(_item.filePath!);
    if (!file.existsSync()) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Recording file not found on disk';
      });
      return;
    }

    try {
      _controller = VideoPlayerController.file(file)
        ..initialize().then((_) {
          if (mounted) {
            setState(() {
              _isInitialized = true;
            });
            _controller?.setLooping(_loop);
            _controller?.play();
            _playPauseController.forward();
          }
        }).catchError((err) {
          if (mounted) {
            setState(() {
              _hasError = true;
              _errorMessage = 'Could not decode recording: $err';
            });
          }
        });

      _controller?.addListener(_onControllerUpdate);
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = '$e';
      });
    }
  }

  void _onControllerUpdate() {
    if (!mounted || _controller == null || !_controller!.value.isInitialized) {
      return;
    }
    final pos = _controller!.value.position;
    final dur = _controller!.value.duration;
    final isPlaying = _controller!.value.isPlaying;

    if (isPlaying && !_playPauseController.isCompleted) {
      _playPauseController.forward();
    } else if (!isPlaying && !_playPauseController.isDismissed) {
      _playPauseController.reverse();
    }

    setState(() {
      _progress = dur.inMilliseconds > 0
          ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
          : 0.0;
    });
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    _playPauseController.dispose();
    // Restore orientation on dispose
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ── Fullscreen ───────────────────────────────────────────────────────────────

  void _enterFullscreen() {
    setState(() => _isFullscreen = true);
    // Determine if video is landscape or portrait
    final aspectRatio =
        _controller?.value.aspectRatio ?? 16 / 9;
    if (aspectRatio > 1.0) {
      // Landscape video → lock to landscape
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      // Portrait/square video → keep portrait but fill screen edge-to-edge
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    // Hide system UI for true immersive fullscreen
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitFullscreen() {
    setState(() => _isFullscreen = false);
    // Restore portrait orientation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // ── Playback ─────────────────────────────────────────────────────────────────

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      _playPauseController.reverse();
    } else {
      _controller!.play();
      _playPauseController.forward();
    }
  }

  void _seekToProgress(double progress) {
    if (_controller == null || !_isInitialized) return;
    final dur = _controller!.value.duration;
    final target =
        Duration(milliseconds: (progress * dur.inMilliseconds).toInt());
    _controller!.seekTo(target);
  }

  void _skipSeconds(int seconds) {
    if (_controller == null || !_isInitialized) return;
    final current = _controller!.value.position;
    final target = current + Duration(seconds: seconds);
    _controller!.seekTo(target);
  }

  void _setSpeed(String speed) {
    setState(() => _speed = speed);
    final val = double.tryParse(speed.replaceAll('x', '')) ?? 1.0;
    _controller?.setPlaybackSpeed(val);
  }


  String _formatTime(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Actions ──────────────────────────────────────────────────────────────────

  void _handleRename() {
    final oldFilename = _item.title;
    final ext = oldFilename.contains('.')
        ? '.${oldFilename.split('.').last}'
        : '';
    final nameWithoutExt = oldFilename.contains('.')
        ? oldFilename.substring(0, oldFilename.lastIndexOf('.'))
        : oldFilename;
    final controller = TextEditingController(text: nameWithoutExt);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Rename Recording',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'File Name',
            suffixText: ext,
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final newBase = controller.text.trim();
              if (newBase.isNotEmpty && _item.filePath != null) {
                final newFilename = '$newBase$ext';
                final oldFile = File(_item.filePath!);
                if (await oldFile.exists()) {
                  final newPath =
                      '${oldFile.parent.path}/$newFilename';
                  await oldFile.rename(newPath);
                  RecordingService().renameSavedItem(_item.id, newFilename,
                      newFilePath: newPath);
                  await RecordingService().scanFile(newPath);
                  await RecordingService().scanFile(oldFile.path);
                  setState(() {
                    _item = MediaItem(
                      id: _item.id,
                      title: newFilename,
                      date: _item.date,
                      duration: _item.duration,
                      size: _item.size,
                      resolution: _item.resolution,
                      type: _item.type,
                      thumbnail: _item.thumbnail,
                      filePath: newPath,
                      isVoiceScreen: _item.isVoiceScreen,
                      hasFacecam: _item.hasFacecam,
                      facecamShape: _item.facecamShape,
                    );
                  });
                }
              }
              if (mounted) {
                // ignore: use_build_context_synchronously
                Navigator.pop(dialogCtx);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _handleTrim() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoEditorScreen(filePath: _item.filePath),
      ),
    );
    if (result != null && mounted) {
      Navigator.of(context).pop(result);
    }
  }

  void _handleShare() async {
    if (_item.filePath == null) return;
    final f = File(_item.filePath!);
    final path = _item.filePath!;
    final title = _item.title;
    final type = _item.type;
    if (await f.exists()) {
      final mimeType = type == 'screenshot'
          ? 'image/png'
          : (type == 'gif' ? 'image/gif' : 'video/mp4');
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: mimeType)],
          text: 'Sharing recording: $title',
        ),
      );
    }
  }

  void _handleDelete() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Recording?',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        content: Text(
          'Are you sure you want to permanently delete "${_item.title}"? This cannot be undone.',
          style: GoogleFonts.hankenGrotesk(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final filePath = _item.filePath;
              final itemId = _item.id;
              if (filePath != null) {
                final f = File(filePath);
                if (await f.exists()) {
                  await f.delete();
                  await RecordingService().scanFile(filePath);
                }
              }
              RecordingService().deleteSavedItem(itemId);
              if (mounted) {
                // ignore: use_build_context_synchronously
                Navigator.pop(dialogCtx);
                // ignore: use_build_context_synchronously
                Navigator.pop(context);
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isFullscreen, // prevent pop when fullscreen
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isFullscreen) {
          _exitFullscreen();
        }
      },
      child: _isFullscreen ? _buildFullscreenView() : _buildNormalView(),
    );
  }

  // ── Normal (Half-screen embedded) View ───────────────────────────────────────

  Widget _buildNormalView() {
    final pos = _controller?.value.position ?? Duration.zero;
    final dur = _controller?.value.duration ?? Duration.zero;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFC),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top App Bar ────────────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                    bottom: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border:
                          Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back,
                          color: Color(0xFF111827), size: 24),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _item.title,
                          style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF111827)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF10B981))),
                            const SizedBox(width: 6),
                            Text(
                              _isInitialized
                                  ? 'Playing Live Recording'
                                  : (_item.type == 'screenshot'
                                      ? 'Photo Preview'
                                      : 'Ready'),
                              style: GoogleFonts.hankenGrotesk(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF9CA3AF)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      _buildIconButton(Icons.share, onTap: _handleShare),
                      _buildIconButton(Icons.delete_outline,
                          onTap: _handleDelete),
                    ],
                  ),
                ],
              ),
            ),

            // ── Video Player (embedded bounded stage) ─────────────────────
            SizedBox(
              width: double.infinity,
              height: (MediaQuery.of(context).size.height * 0.32)
                  .clamp(180.0, 240.0),
              child: _buildVideoStack(
                  pos: pos, dur: dur, isFullscreen: false),
            ),

            // ── Content below player ──────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Video info card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: const Color(0xFFE5E7EB)),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 4,
                              offset: const Offset(0, 1))
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(0xFFDC2626))),
                              const SizedBox(width: 8),
                              Text('AUTHENTIC RECORDING',
                                  style: GoogleFonts.hankenGrotesk(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF6B7280),
                                      letterSpacing: 0.2)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _item.title,
                            style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF111827)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Recorded on ${_item.date} • ${_item.size}',
                            style: GoogleFonts.hankenGrotesk(
                                fontSize: 12,
                                color: const Color(0xFF6B7280)),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    _buildSpecsGrid(),
                    const SizedBox(height: 16),

                    // Playback options card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Playback Speed',
                                  style: GoogleFonts.manrope(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF111827))),
                              const SizedBox(width: 8),
                              Flexible(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      '0.5x',
                                      '1.0x',
                                      '1.25x',
                                      '1.5x',
                                      '2.0x'
                                    ]
                                        .map((s) => Padding(
                                              padding:
                                                  const EdgeInsets.only(
                                                      left: 4),
                                              child: _buildSpeedButton(s),
                                            ))
                                        .toList(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ── Fullscreen View ───────────────────────────────────────────────────────────

  Widget _buildFullscreenView() {
    final pos = _controller?.value.position ?? Duration.zero;
    final dur = _controller?.value.duration ?? Duration.zero;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: _buildVideoStack(
            pos: pos, dur: dur, isFullscreen: true),
      ),
    );
  }

  // ── Shared Video Stack (used by both views) ────────────────────────────────

  Widget _buildVideoStack(
      {required Duration pos,
      required Duration dur,
      required bool isFullscreen}) {
    return GestureDetector(
      // Toggle controls visibility on tap
      onTap: () => setState(() => _showControls = !_showControls),
      child: Container(
        color: const Color(0xFF0C0E14),
        child: Stack(
          children: [
            // ── Video / image display ────────────────────────────────
            Positioned.fill(child: _buildPlayerDisplay()),

            // ── Top info badges ──────────────────────────────────────
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF33343B).withValues(alpha: 0.85),
                        borderRadius:
                            BorderRadius.circular(9999),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFFDC2626))),
                          const SizedBox(width: 6),
                          Text(_item.resolution,
                              style: GoogleFonts.hankenGrotesk(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  letterSpacing: 0.2)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color:
                            const Color(0xFF33343B).withValues(alpha: 0.7),
                        borderRadius:
                            BorderRadius.circular(9999),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      child: Text(_item.size,
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),

            // ── Center play/pause + skip controls ───────────────────
            if (_item.type != 'screenshot' && _isInitialized)
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildControlButton(Icons.replay_10,
                          onTap: () => _skipSeconds(-10)),
                      const SizedBox(width: 24),
                      GestureDetector(
                        onTap: _togglePlayPause,
                        child: Container(
                          width: isFullscreen ? 64 : 56,
                          height: isFullscreen ? 64 : 56,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFDC2626),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x66DC2626),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Icon(
                            _controller?.value.isPlaying == true
                                ? Icons.pause
                                : Icons.play_arrow,
                            color: Colors.white,
                            size: isFullscreen ? 38 : 32,
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      _buildControlButton(Icons.forward_10,
                          onTap: () => _skipSeconds(10)),
                    ],
                  ),
                ),
              ),

            if (Platform.isWindows && _item.type != 'screenshot' && !_isInitialized)
              Center(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.play_circle_fill_rounded, size: 28, color: Colors.white),
                  label: Text('Play in Windows Media Player', style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    if (_item.filePath != null) {
                      OpenFile.open(_item.filePath!);
                    }
                  },
                ),
              ),

            // ── Facecam overlay ──────────────────────────────────────
            if ((kIsWeb || !Platform.isAndroid) && _item.hasFacecam)
              Builder(
                builder: (context) {
                  final media = MediaQuery.of(context);
                  final screenW = media.size.width;
                  final screenH = media.size.height;
                  final overlaySize = (_item.facecamSizeRatio != null && _item.facecamSizeRatio! > 0)
                      ? (screenW * _item.facecamSizeRatio!).clamp(120.0, 220.0)
                      : (screenW * 0.28).clamp(120.0, 200.0);
                  final posX = _item.facecamNormalizedX != null
                      ? (_item.facecamNormalizedX! * screenW).clamp(8.0, screenW - overlaySize - 8.0)
                      : screenW - overlaySize - 16.0;
                  final posY = _item.facecamNormalizedY != null
                      ? (_item.facecamNormalizedY! * screenH).clamp(40.0, screenH - overlaySize - 80.0)
                      : screenH - overlaySize - 80.0;

                  return Positioned(
                    left: posX,
                    top: posY,
                    child: FacecamWindow(
                      shape: _item.facecamShape ?? 'Square (PiP)',
                      size: overlaySize,
                      isLive: false,
                      showBorder: true,
                      previewImagePath: _item.facecamSnapshotPath ?? RecordingService().lastFacecamSnapshotPath,
                    ),
                  );
                },
              ),

            // ── Bottom scrubber + fullscreen button ─────────────────
            if (_item.type != 'screenshot' && _isInitialized)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: Container(
                    padding:
                        const EdgeInsets.fromLTRB(16, 20, 16, 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.8),
                          Colors.black,
                        ],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Scrubber track
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6),
                            overlayShape:
                                const RoundSliderOverlayShape(
                                    overlayRadius: 12),
                            activeTrackColor:
                                const Color(0xFFDC2626),
                            inactiveTrackColor: Colors.white24,
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            value: _progress,
                            onChanged: (v) {
                              setState(() => _progress = v);
                              _seekToProgress(v);
                            },
                          ),
                        ),

                        // Time row + fullscreen toggle
                        Row(
                          children: [
                            // Time labels
                            Text(_formatTime(pos),
                                style: GoogleFonts.hankenGrotesk(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        const Color(0xFFFFB4AB))),
                            Text(' / ',
                                style: GoogleFonts.hankenGrotesk(
                                    fontSize: 12,
                                    color: Colors.white54)),
                            Text(_formatTime(dur),
                                style: GoogleFonts.hankenGrotesk(
                                    fontSize: 12,
                                    color: Colors.white70,
                                    fontWeight:
                                        FontWeight.w500)),

                            const Spacer(),

                            // Speed badge
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF33343B)
                                    .withValues(alpha: 0.8),
                                borderRadius:
                                    BorderRadius.circular(4),
                              ),
                              child: Text(_speed,
                                  style: GoogleFonts.hankenGrotesk(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white)),
                            ),

                            const SizedBox(width: 8),

                            // ── YouTube-style fullscreen toggle button ──
                            _buildFullscreenToggleButton(
                                isFullscreen),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ── Screenshot fullscreen toggle (no scrubber) ──────────
            if (_item.type == 'screenshot')
              Positioned(
                bottom: 12,
                right: 12,
                child: _buildFullscreenToggleButton(isFullscreen),
              ),
          ],
        ),
      ),
    );
  }

  // ── YouTube-style expand / collapse button ────────────────────────────────

  Widget _buildFullscreenToggleButton(bool isFullscreen) {
    return GestureDetector(
      onTap: () {
        if (isFullscreen) {
          _exitFullscreen();
        } else {
          _enterFullscreen();
        }
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Icon(
          isFullscreen
              ? Icons.fullscreen_exit_rounded
              : Icons.fullscreen_rounded,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }

  // ── Player display ────────────────────────────────────────────────────────

  Widget _buildPlayerDisplay() {
    if (_item.type == 'screenshot') {
      final f =
          _item.filePath != null ? File(_item.filePath!) : null;
      if (f != null && f.existsSync()) {
        return Center(
          child: InteractiveViewer(
            panEnabled: true,
            minScale: 0.5,
            maxScale: 4.0,
            child: Image.file(f, fit: BoxFit.contain),
          ),
        );
      } else {
        return const Center(
            child: Text('Image file not found on disk',
                style: TextStyle(color: Colors.white70)));
      }
    }

    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Color(0xFFDC2626), size: 40),
              const SizedBox(height: 10),
              Text(_errorMessage,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
                color: Color(0xFFDC2626)),
            const SizedBox(height: 12),
            Text('Loading recording...',
                style: GoogleFonts.hankenGrotesk(
                    color: Colors.white70, fontSize: 12)),
          ],
        ),
      );
    }

    // Render the video filling the container, preserving aspect ratio
    return Center(
      child: AspectRatio(
        aspectRatio: _controller!.value.aspectRatio > 0
            ? _controller!.value.aspectRatio
            : 16 / 9,
        child: VideoPlayer(_controller!),
      ),
    );
  }

  // ── Shared small widgets ──────────────────────────────────────────────────

  Widget _buildIconButton(IconData icon, {VoidCallback? onTap}) {
    return Container(
      width: 38,
      height: 38,
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: IconButton(
          icon: Icon(icon, color: const Color(0xFF111827), size: 20),
          onPressed: onTap,
          padding: EdgeInsets.zero),
    );
  }

  Widget _buildControlButton(IconData icon, {VoidCallback? onTap}) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1E1F26).withValues(alpha: 0.7),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: IconButton(
          icon: Icon(icon, color: Colors.white, size: 26),
          onPressed: onTap,
          padding: EdgeInsets.zero),
    );
  }

  Widget _buildSpecsGrid() {
    final specs = [
      {
        'label': 'Resolution',
        'value': _item.resolution,
        'sub': 'Native Capture'
      },
      {
        'label': 'Format',
        'value': _item.type.toUpperCase(),
        'sub': _item.type == 'video' ? 'MPEG-4 AVC' : 'Lossless'
      },
      {
        'label': 'Duration',
        'value': _item.duration ?? '--:--',
        'sub': 'Playable Length'
      },
      {
        'label': 'File Size',
        'value': _item.size,
        'sub': 'Storage Used'
      },
      {
        'label': 'Recorded Date',
        'value': _item.date,
        'sub': 'Local Timestamp'
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.15,
      ),
      itemCount: specs.length,
      itemBuilder: (context, index) {
        final s = specs[index];
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(s['label']!,
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF9CA3AF),
                      letterSpacing: 0.2)),
              const SizedBox(height: 4),
              Text(s['value']!,
                  style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111827)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(s['sub']!,
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF9CA3AF)),
                  maxLines: 1),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSpeedButton(String speed) {
    final isActive = _speed == speed;
    return GestureDetector(
      onTap: () => _setSpeed(speed),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9999),
          color: isActive
              ? const Color(0xFFDC2626)
              : const Color(0xFFF3F4F6),
          border: Border.all(
              color: isActive
                  ? const Color(0xFFDC2626)
                  : const Color(0xFFE5E7EB)),
        ),
        child: Text(
          speed,
          style: GoogleFonts.hankenGrotesk(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: isActive ? Colors.white : const Color(0xFF6B7280),
          ),
        ),
      ),
    );
  }


  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border:
            const Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, -4))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                  child: _buildBottomAction(Icons.edit_document, 'Rename',
                      onTap: _handleRename)),
              Expanded(
                  child: _buildBottomAction(
                      Icons.content_cut, 'Edit / Trim',
                      onTap: _handleTrim)),
              Expanded(
                  child: _buildBottomAction(Icons.share, 'Share',
                      onTap: _handleShare)),
              Expanded(
                  child: _buildBottomAction(
                      Icons.delete_outline, 'Delete',
                      color: const Color(0xFFDC2626),
                      onTap: _handleDelete)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomAction(IconData icon, String label,
      {Color? color, VoidCallback? onTap}) {
    final c = color ?? const Color(0xFF111827);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color == const Color(0xFFDC2626)
                  ? const Color(0xFFFEF2F2)
                  : const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: color == const Color(0xFFDC2626)
                      ? const Color(0xFFFECACA)
                      : const Color(0xFFE5E7EB)),
            ),
            child: Icon(icon, size: 22, color: c),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: c)),
        ],
      ),
    );
  }
}
