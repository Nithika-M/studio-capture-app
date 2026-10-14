import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/app_models.dart';
import '../../services/recording_service.dart';
import '../../services/recording_auth_service.dart';
import '../../services/app_notification_service.dart';
import '../../widgets/facecam_window.dart';
import 'recording_completed_screen.dart';

enum RecordingState { recording, paused }

class ActiveRecordingScreen extends StatefulWidget {
  final RecordingSettings settings;

  const ActiveRecordingScreen({super.key, required this.settings});

  @override
  State<ActiveRecordingScreen> createState() => _ActiveRecordingScreenState();
}

class _ActiveRecordingScreenState extends State<ActiveRecordingScreen> with TickerProviderStateMixin {
  late AnimationController _timerController;
  late AnimationController _liveGlowController;
  late AnimationController _rippleController;
  
  final RecordingService _recordingService = RecordingService();
  RecordingState _state = RecordingState.recording;
  int _secondsElapsed = 0;
  bool _micEnabled = true;
  bool _camEnabled = false;
  bool _videoTrackEnabled = true;
  bool _noiseCancellation = true;
  bool _isInitialized = false;
  Offset? _facecamPosition;
  final GlobalKey<FacecamWindowState> _facecamKey = GlobalKey<FacecamWindowState>();

  @override
  void initState() {
    super.initState();
    _noiseCancellation = widget.settings.mode == RecordingMode.voiceScreen;
    _camEnabled = widget.settings.showFacecam;
    
    // Configure screen orientation according to Capture Orientation setting on mobile
    if (!kIsWeb && !Platform.isWindows) {
      final orient = widget.settings.orientation.toLowerCase();
      if (orient.contains('portrait')) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      } else if (orient.contains('landscape')) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    }

    _initializeRecording();
    
    _timerController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..addListener(() {
        if (_state == RecordingState.recording) {
          setState(() => _secondsElapsed++);
        }
      })
      ..repeat();

    _liveGlowController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    )..repeat(reverse: true);

    _rippleController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    )..repeat();

    RecordingService.stateNotifier.addListener(_onNativeStateChanged);
  }

  void _onNativeStateChanged() {
    final state = RecordingService.stateNotifier.value;
    if (!mounted || state.isEmpty) return;

    final isRecording = state['isRecording'] as bool? ?? true;
    final isPaused = state['isPaused'] as bool? ?? false;
    final isAudioMuted = state['isAudioMuted'] as bool? ?? false;
    final isVideoEnabled = state['isVideoEnabled'] as bool? ?? true;
    final showFacecam = state['showFacecam'] as bool?;
    final lastPath = state['lastRecordingPath'] as String?;

    setState(() {
      _state = isPaused ? RecordingState.paused : RecordingState.recording;
      _micEnabled = !isAudioMuted;
      _videoTrackEnabled = isVideoEnabled;
      if (showFacecam != null) {
        _camEnabled = showFacecam;
      }
    });

    if (!isRecording) {
      _statusPollTimer?.cancel();
      _timerController.stop();
      _navigateToCompleted(path: lastPath);
    }
  }

  Future<void> _initializeRecording() async {
    try {
      await _recordingService.initialize(requireCamera: widget.settings.showFacecam);
      
      // Start recording with the selected settings
      await _recordingService.startRecording(
        settings: widget.settings,
        enableAudio: true,
        enableVideo: true,
      );
      
      if (mounted) {
        setState(() => _isInitialized = true);
        _startStatusPolling();
      }
    } catch (e) {
      RecordingAuthService.resetSessionAuth();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start recording: $e')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  Timer? _statusPollTimer;

  void _startStatusPolling() {
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      if (!_isInitialized || !mounted) return;
      final status = await _recordingService.getRecordingStatus();
      if (status != null && mounted) {
        final isRec = status['isRecording'] as bool? ?? false;
        final isP = status['isPaused'] as bool? ?? false;
        final isM = status['isAudioMuted'] as bool? ?? false;
        final isV = status['isVideoEnabled'] as bool? ?? true;
        
        setState(() {
          _state = isP ? RecordingState.paused : RecordingState.recording;
          _micEnabled = !isM;
          _videoTrackEnabled = isV;
        });

        if (!isRec) {
          _statusPollTimer?.cancel();
          _timerController.stop();
          final path = status['lastRecordingPath'] as String?;
          _navigateToCompleted(path: path);
        }
      }
    });
  }

  @override
  void dispose() {
    RecordingService.stateNotifier.removeListener(_onNativeStateChanged);
    _statusPollTimer?.cancel();
    _timerController.dispose();
    _liveGlowController.dispose();
    _rippleController.dispose();
    _recordingService.dispose();
    if (!kIsWeb && !Platform.isWindows) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    super.dispose();
  }

  String _formatTime(int seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  void _togglePause() async {
    if (!_isInitialized) return;
    
    setState(() {
      _state = _state == RecordingState.recording ? RecordingState.paused : RecordingState.recording;
    });
    
    if (_state == RecordingState.paused) {
      await _recordingService.pauseRecording();
    } else {
      await _recordingService.resumeRecording();
    }
  }

  void _toggleMic() {
    setState(() => _micEnabled = !_micEnabled);
    _recordingService.setMicMuted(!_micEnabled);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_micEnabled ? 'Microphone commentary: UNMUTED' : 'Microphone commentary: MUTED (System audio continuing)'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _toggleVideoTrack() {
    setState(() => _videoTrackEnabled = !_videoTrackEnabled);
    _recordingService.setVideoEnabled(_videoTrackEnabled);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_videoTrackEnabled
            ? 'Screen Video capture resumed.'
            : 'Screen Video capture paused (Dual-track audio continuing).'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _toggleNoiseCancellation() {
    setState(() => _noiseCancellation = !_noiseCancellation);
    _recordingService.setNoiseCancellation(_noiseCancellation);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_noiseCancellation
            ? 'Real-Time Noise Cancellation: ACTIVE (Filtering background noise)'
            : 'Noise Cancellation Filter: BYPASS (Capturing raw ambient sound)'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _toggleCam() {
    setState(() => _camEnabled = !_camEnabled);
    _recordingService.setFacecamEnabled(_camEnabled, shape: widget.settings.facecamShape);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_camEnabled ? 'Facecam overlay: ACTIVE' : 'Facecam overlay: HIDDEN'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _stopRecording() async {
    if (!_isInitialized) return;
    
    // Play stop chime + haptic immediately (before await) for snappy UX
    AppNotificationService.playStopChime();

    // Snapshot user's real face from live camera before stopping
    try {
      final snapshot = await _facecamKey.currentState?.takeSnapshot();
      if (snapshot != null) {
        _recordingService.setFacecamSnapshot(path: snapshot.path);
      }
    } catch (_) {}

    _timerController.stop();
    final path = await _recordingService.stopRecording();
    if (!mounted) return;
    _navigateToCompleted(path: path);
  }

  double _calculateFacecamSize(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final screenHeight = media.size.height;
    final minDim = screenWidth < screenHeight ? screenWidth : screenHeight;
    // Noticeably larger facecam preview: ~28% of screen width (135 - 220 px)
    return (minDim * 0.28).clamp(135.0, 220.0);
  }

  Widget _buildDraggableFacecam(BuildContext context) {
    if (!widget.settings.showFacecam || !_camEnabled) return const SizedBox.shrink();

    final size = _calculateFacecamSize(context);
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final screenHeight = media.size.height;
    final topPadding = media.padding.top;
    final bottomPadding = media.padding.bottom;

    // Boundaries: ensure facecam stays fully visible and never gets clipped off-screen
    final minX = 8.0;
    final maxX = (screenWidth - size - 8.0).clamp(minX, double.infinity);
    final minY = topPadding + 8.0;
    final maxY = (screenHeight - size - bottomPadding - 16.0).clamp(minY, double.infinity);

    // Initial position: comfortably in bottom-right corner without blocking bottom nav
    _facecamPosition ??= Offset(
      (screenWidth - size - 16.0).clamp(minX, maxX),
      (screenHeight - size - bottomPadding - 110.0).clamp(minY, maxY),
    );

    final currentX = _facecamPosition!.dx.clamp(minX, maxX);
    final currentY = _facecamPosition!.dy.clamp(minY, maxY);
    if (currentX != _facecamPosition!.dx || currentY != _facecamPosition!.dy) {
      _facecamPosition = Offset(currentX, currentY);
    }

    return Positioned(
      left: currentX,
      top: currentY,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          setState(() {
            final nextX = (_facecamPosition!.dx + details.delta.dx).clamp(minX, maxX);
            final nextY = (_facecamPosition!.dy + details.delta.dy).clamp(minY, maxY);
            _facecamPosition = Offset(nextX, nextY);

            _recordingService.updateFacecamPosition(
              xRatio: nextX / (screenWidth > 0 ? screenWidth : 1.0),
              yRatio: nextY / (screenHeight > 0 ? screenHeight : 1.0),
              sizeRatio: size / (screenWidth > 0 ? screenWidth : 1.0),
            );
          });
        },
        child: FacecamWindow(
          key: _facecamKey,
          shape: widget.settings.facecamShape,
          size: size,
          isLive: true,
          showBorder: true,
          captureOrientation: widget.settings.orientation,
        ),
      ),
    );
  }

  void _navigateToCompleted({String? path}) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => RecordingCompletedScreen(
          selectedMode: widget.settings.mode, 
          duration: _secondsElapsed,
          filePath: path,
          settings: widget.settings,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return ScaleTransition(
            scale: animation.drive(Tween(begin: 0.95, end: 1.0).chain(CurveTween(curve: Curves.easeOutCubic))),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F6),
      body: Stack(
        children: [
          // Background - simulated phone screen
          _buildBackgroundScreen(),

          // Screen border glow
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFDC2626).withOpacity(0.4), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFDC2626).withOpacity(0.15),
                      blurRadius: 24,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Floating controls
          if (widget.settings.floatingBubble)
            SafeArea(
            child: Column(
              children: [
                // Top telemetry dock
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(9999),
                            border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.9)),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFDC2626)),
                              ).animate(onPlay: (c) => c.repeat())
                                  .scale(duration: 1000.ms, begin: const Offset(1, 1), end: const Offset(1.5, 1.5))
                                  .then()
                                  .fadeOut(duration: 1000.ms),
                              const SizedBox(width: 8),
                              Text(
                                'REC • ${widget.settings.resolution} ${widget.settings.fps}fps',
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF111827),
                                  letterSpacing: 0.22,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(width: 1, height: 14, color: const Color(0xFFD1D5DB)),
                              const SizedBox(width: 8),
                              Icon(
                                widget.settings.mode == RecordingMode.voiceScreen
                                    ? Icons.mic_external_on_rounded
                                    : Icons.mic,
                                size: 14,
                                color: widget.settings.mode == RecordingMode.voiceScreen
                                    ? const Color(0xFF7C3AED)
                                    : const Color(0xFF9CA3AF),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                widget.settings.mode == RecordingMode.voiceScreen
                                    ? 'Dual-Track 48k'
                                    : '48kHz',
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: widget.settings.mode == RecordingMode.voiceScreen
                                      ? const Color(0xFF7C3AED)
                                      : const Color(0xFF374151),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(9999),
                          border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.9)),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))],
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.fullscreen_exit, size: 16, color: Color(0xFF6B7280)),
                          onPressed: () {},
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Main floating widget
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildFloatingWidget(),
                ),

                const SizedBox(height: 14),

                // Audio telemetry meter (Dual track for Voice + Screen)
                _buildAudioVisualizerSection(),

                const SizedBox(height: 20),

                // Drag hint
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.drag_indicator, size: 14, color: Color(0xFF9CA3AF)),
                    const SizedBox(width: 6),
                    Text(
                      'Drag pill to relocate anywhere on screen',
                      style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w500, color: const Color(0xFF9CA3AF)),
                    ),
                  ],
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),

          // Fully draggable, larger Facecam preview showing live camera feed
          _buildDraggableFacecam(context),

          // Home indicator
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 128,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingWidget() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 344),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.9)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 32, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          // Left: Drag handle + Live indicator + Timer
          Expanded(
            child: Row(
              children: [
                // Drag handle
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (i) => Container(
                    width: 2,
                    height: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF374151).withValues(alpha: 0.5)),
                  )),
                ),
                const SizedBox(width: 6),

                // Live indicator with glow
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _liveGlowController,
                        builder: (_, __) => Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFDC2626),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFDC2626).withValues(alpha: 0.6 * _liveGlowController.value),
                                blurRadius: 6 + 4 * _liveGlowController.value,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 6),

                // Timer
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _formatTime(_secondsElapsed),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF111827),
                            letterSpacing: -0.13,
                          ),
                        ),
                      ),
                      Text(
                        _state == RecordingState.recording ? 'Recording' : 'Paused',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: _state == RecordingState.recording ? const Color(0xFF9CA3AF) : const Color(0xFFFBBF24),
                          letterSpacing: 0.18,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const VerticalDivider(width: 1, color: Color(0xFFE5E7EB)),

          // Right: Control buttons
          Row(
            children: [
              _buildControlButton(
                icon: _state == RecordingState.recording ? Icons.pause : Icons.play_arrow,
                onTap: _togglePause,
                color: const Color(0xFF374151),
                bgColor: const Color(0xFFF3F4F6),
                tooltip: _state == RecordingState.recording ? 'Pause Recording' : 'Resume Recording',
              ),
              _buildControlButton(
                icon: _micEnabled ? Icons.mic : Icons.mic_off,
                onTap: _toggleMic,
                color: _micEnabled ? const Color(0xFF374151) : Colors.white,
                bgColor: _micEnabled ? const Color(0xFFF3F4F6) : const Color(0xFFDC2626),
                badge: _micEnabled,
                tooltip: _micEnabled ? 'Mute Microphone' : 'Unmute Microphone',
              ),
              _buildControlButton(
                icon: _videoTrackEnabled ? Icons.desktop_windows_rounded : Icons.desktop_access_disabled_rounded,
                onTap: _toggleVideoTrack,
                color: _videoTrackEnabled ? const Color(0xFF374151) : Colors.white,
                bgColor: _videoTrackEnabled ? const Color(0xFFF3F4F6) : const Color(0xFFDC2626),
                badge: !_videoTrackEnabled,
                tooltip: _videoTrackEnabled ? 'Turn Off Video (Audio Continues)' : 'Resume Video Capture',
              ),
              if (widget.settings.showFacecam)
                _buildControlButton(
                  icon: Icons.videocam,
                  onTap: _toggleCam,
                  color: const Color(0xFF374151),
                  bgColor: const Color(0xFFF3F4F6),
                  badge: _camEnabled,
                  tooltip: 'Toggle Facecam',
                ),
              _buildControlButton(
                icon: Icons.stop,
                onTap: _stopRecording,
                color: Colors.white,
                bgColor: const Color(0xFFDC2626),
                isStop: true,
                tooltip: 'Stop & Save',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAudioVisualizerSection() {
    final bool isVoiceScreen = widget.settings.mode == RecordingMode.voiceScreen;

    if (isVoiceScreen) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Noise Cancellation Pill
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _noiseCancellation ? const Color(0xFF10B981) : const Color(0xFF9CA3AF),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _noiseCancellation ? 'Noise Cancellation: ACTIVE' : 'Noise Filter: BYPASS',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _noiseCancellation ? const Color(0xFF047857) : const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: _toggleNoiseCancellation,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _noiseCancellation ? const Color(0xFFECFDF5) : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(9999),
                      border: Border.all(
                        color: _noiseCancellation ? const Color(0xFFA7F3D0) : const Color(0xFFE5E7EB),
                      ),
                    ),
                    child: Text(
                      _noiseCancellation ? 'Filter ON' : 'Filter OFF',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: _noiseCancellation ? const Color(0xFF059669) : const Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Track 1: Mic Commentary
            Row(
              children: [
                Icon(Icons.mic, size: 14, color: _micEnabled ? const Color(0xFFDC2626) : const Color(0xFF9CA3AF)),
                const SizedBox(width: 6),
                SizedBox(
                  width: 68,
                  child: Text(
                    'MIC Voice',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _micEnabled ? const Color(0xFF111827) : const Color(0xFF9CA3AF),
                    ),
                  ),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(14, (i) {
                      final heights = [6, 12, 18, 14, 22, 16, 26, 18, 14, 20, 12, 16, 8, 4];
                      return AnimatedContainer(
                        duration: Duration(milliseconds: 180 + i * 25),
                        width: 3.5,
                        height: _micEnabled ? heights[i].toDouble() : 3.0,
                        decoration: BoxDecoration(
                          color: _micEnabled
                              ? (i < 8 ? const Color(0xFF10B981) : (i < 12 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444)))
                              : const Color(0xFFD1D5DB),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ).animate(onPlay: (c) => c.repeat(reverse: true))
                          .scaleY(duration: Duration(milliseconds: 500 + i * 60), begin: 0.4, end: 1.0);
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _micEnabled ? '-14dB' : 'MUTED',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _micEnabled ? const Color(0xFF111827) : const Color(0xFFEF4444),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Track 2: Internal System Audio
            Row(
              children: [
                const Icon(Icons.volume_up_rounded, size: 14, color: Color(0xFF7C3AED)),
                const SizedBox(width: 6),
                SizedBox(
                  width: 68,
                  child: Text(
                    'SYS Audio',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111827),
                    ),
                  ),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(14, (i) {
                      final heights = [10, 16, 12, 20, 14, 18, 22, 16, 14, 18, 24, 14, 10, 6];
                      return AnimatedContainer(
                        duration: Duration(milliseconds: 200 + i * 30),
                        width: 3.5,
                        height: heights[i].toDouble(),
                        decoration: BoxDecoration(
                          color: i < 9 ? const Color(0xFF7C3AED) : const Color(0xFF8B5CF6),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ).animate(onPlay: (c) => c.repeat(reverse: true))
                          .scaleY(duration: Duration(milliseconds: 550 + i * 70), begin: 0.45, end: 1.0);
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '-8dB',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF111827),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Single audio meter for other modes
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.9)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('L/R Audio', style: GoogleFonts.hankenGrotesk(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF374151))),
          const SizedBox(width: 8),
          Row(
            children: List.generate(8, (i) {
              final heights = [8, 10, 14, 16, 12, 8, 6, 4];
              return AnimatedContainer(
                duration: Duration(milliseconds: 200 + i * 50),
                curve: Curves.easeInOut,
                width: 6,
                height: heights[i].toDouble(),
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: i < 4 ? const Color(0xFF10B981) : (i < 6 ? const Color(0xFFFBBF24) : const Color(0xFFEF4444)),
                  borderRadius: BorderRadius.circular(2),
                ),
              ).animate(onPlay: (c) => c.repeat(reverse: true))
                  .scaleY(duration: Duration(milliseconds: 600 + i * 100), begin: 0.5, end: 1.0);
            }),
          ),
          const SizedBox(width: 8),
          Text('-12dB', style: GoogleFonts.hankenGrotesk(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF111827), fontFeatures: [const FontFeature.tabularFigures()])),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
    required Color bgColor,
    bool badge = false,
    bool isStop = false,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bgColor,
            border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.8)),
            boxShadow: isStop ? [BoxShadow(color: const Color(0xFFDC2626).withOpacity(0.45), blurRadius: 14)] : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: isStop ? 18 : 19, color: color),
              if (badge)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFDC2626)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundScreen() {
    if (!_videoTrackEnabled) {
      return Container(
        color: const Color(0xFF0F172A),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFDC2626).withOpacity(0.15),
                  border: Border.all(color: const Color(0xFFDC2626), width: 2),
                ),
                child: const Icon(Icons.videocam_off_rounded, color: Color(0xFFDC2626), size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                'Video Capture Paused',
                style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(
                'Dual-Track Audio Recording Active (Mic + System Sound)',
                style: GoogleFonts.hankenGrotesk(fontSize: 13, color: const Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(12, (i) {
                  final heights = [10, 18, 30, 24, 40, 28, 36, 20, 32, 16, 24, 12];
                  return AnimatedContainer(
                    duration: Duration(milliseconds: 200 + i * 40),
                    width: 4,
                    height: heights[i].toDouble(),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ).animate(onPlay: (c) => c.repeat(reverse: true))
                      .scaleY(duration: Duration(milliseconds: 500 + i * 80), begin: 0.3, end: 1.0);
                }),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE5E7EB), Color(0xFFF9FAFB), Color(0xFFE5E7EB)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Status bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('9:41', style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF111827))),
                  Row(
                    children: [
                      const Icon(Icons.signal_cellular_4_bar, size: 15, color: Color(0xFF374151)),
                      const SizedBox(width: 4),
                      const Icon(Icons.wifi, size: 15, color: Color(0xFF374151)),
                      const SizedBox(width: 4),
                      Container(
                        width: 20,
                        height: 10,
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF374151)),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Container(width: 14, height: 8, color: const Color(0xFF1F2937)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Mock app content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                border: Border.all(color: const Color(0xFFE5E7EB)),
                              ),
                              child: const Icon(Icons.graphic_eq, size: 16, color: Color(0xFFDC2626)),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(width: 112, height: 8, decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(4))),
                                const SizedBox(height: 4),
                                Container(width: 64, height: 6, decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(4))),
                              ],
                            ),
                          ],
                        ),
                        Container(width: 28, height: 28, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: const Color(0xFFE5E7EB)))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.8)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(20, (i) {
                          final heights = [16, 28, 40, 56, 40, 20, 16, 28, 44, 32, 16, 28, 48, 40, 28, 16, 28, 36, 48, 40];
                          return Container(
                            width: 6,
                            height: heights[i].toDouble(),
                            decoration: BoxDecoration(
                              color: heights[i] > 40 ? const Color(0xFFDC2626) : (heights[i] > 28 ? const Color(0xFFF87171) : (heights[i] > 20 ? const Color(0xFFFBBF24) : const Color(0xFFE5E7EB))),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.8)),
                            ),
                            child: Row(
                              children: [
                                const SizedBox(width: 12),
                                Container(width: 24, height: 24, decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(6))),
                                const SizedBox(width: 12),
                                Container(width: 80, height: 10, decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(4))),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.8)),
                            ),
                            child: Row(
                              children: [
                                const SizedBox(width: 12),
                                Container(width: 24, height: 24, decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(6))),
                                const SizedBox(width: 12),
                                Container(width: 80, height: 10, decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(4))),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(3, (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.8)),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 12),
                            Container(width: 24, height: 24, decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(6))),
                            const SizedBox(width: 12),
                            Container(width: i == 0 ? 144 : (i == 1 ? 176 : 112), height: 10, decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(4))),
                          ],
                        ),
                      ),
                    )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}