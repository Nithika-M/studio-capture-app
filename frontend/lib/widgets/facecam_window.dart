import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

enum FacecamShapeType {
  circle,
  roundedRect,
  square,
}

FacecamShapeType parseFacecamShape(String? shape) {
  if (shape == null) return FacecamShapeType.circle;
  final s = shape.toLowerCase();
  if (s.contains('round')) return FacecamShapeType.roundedRect;
  if (s.contains('square')) return FacecamShapeType.square;
  return FacecamShapeType.circle;
}

class FacecamWindow extends StatefulWidget {
  final String shape;
  final double size;
  final bool isLive;
  final bool showBorder;
  final VoidCallback? onTap;
  final CameraController? cameraController;
  final String? previewImagePath;
  final Uint8List? previewImageBytes;
  final String? captureOrientation;

  const FacecamWindow({
    super.key,
    required this.shape,
    this.size = 140,
    this.isLive = false,
    this.showBorder = true,
    this.onTap,
    this.cameraController,
    this.previewImagePath,
    this.previewImageBytes,
    this.captureOrientation = 'Auto',
  });

  @override
  State<FacecamWindow> createState() => FacecamWindowState();
}

class FacecamWindowState extends State<FacecamWindow> {
  CameraController? _internalController;
  bool _isInitializing = false;
  String? _errorMessage;
  bool _isFrontCamera = true;

  CameraController? get activeController =>
      widget.cameraController ?? _internalController;

  @override
  void initState() {
    super.initState();
    if (widget.isLive && widget.cameraController == null) {
      _initCamera();
    }
  }

  @override
  void didUpdateWidget(FacecamWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLive && !oldWidget.isLive && activeController == null) {
      _initCamera();
    } else if (!widget.isLive && oldWidget.isLive && _internalController != null) {
      _disposeInternalController();
    } else if (widget.captureOrientation != oldWidget.captureOrientation && activeController != null) {
      _applyOrientation(activeController!);
    }
  }

  Future<void> _applyOrientation(CameraController controller) async {
    final mode = widget.captureOrientation?.toLowerCase() ?? 'auto';
    try {
      if (mode.contains('portrait')) {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } else if (mode.contains('landscape')) {
        await controller.lockCaptureOrientation(DeviceOrientation.landscapeLeft);
      } else {
        await controller.unlockCaptureOrientation();
      }
    } catch (_) {}
  }

  Future<void> _initCamera() async {
    if (!mounted || _isInitializing) return;

    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    try {
      if (!kIsWeb) {
        try {
          final status = await Permission.camera.request().timeout(
            const Duration(milliseconds: 250),
            onTimeout: () => PermissionStatus.denied,
          );
          if (!status.isGranted) {
            if (mounted) {
              setState(() {
                _isInitializing = false;
                _errorMessage = 'Camera permission required';
              });
            }
            return;
          }
        } catch (_) {
          // Fallback if permission plugin is not registered
        }
      }

      final cameras = await availableCameras().timeout(
        const Duration(milliseconds: 300),
        onTimeout: () => <CameraDescription>[],
      );
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _isInitializing = false;
            _errorMessage = 'No camera found';
          });
        }
        return;
      }

      // Prioritize front-facing camera for natural facecam view
      CameraDescription? selectedCam;
      for (final cam in cameras) {
        if (cam.lensDirection == CameraLensDirection.front) {
          selectedCam = cam;
          break;
        }
      }
      selectedCam ??= cameras.first;
      _isFrontCamera = selectedCam.lensDirection == CameraLensDirection.front;

      final controller = CameraController(
        selectedCam,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();
      await _applyOrientation(controller);

      if (mounted) {
        setState(() {
          _internalController = controller;
          _isInitializing = false;
          _errorMessage = null;
        });
      } else {
        await controller.dispose();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = 'Camera unavailable';
        });
      }
    }
  }

  Future<XFile?> takeSnapshot() async {
    final controller = activeController;
    if (controller != null && controller.value.isInitialized) {
      try {
        return await controller.takePicture();
      } catch (e) {
        debugPrint('Failed to take facecam snapshot: $e');
      }
    }
    return null;
  }

  void _disposeInternalController() {
    _internalController?.dispose();
    _internalController = null;
  }

  @override
  void dispose() {
    _disposeInternalController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shapeType = parseFacecamShape(widget.shape);

    Widget content = _buildCameraContent(shapeType);

    Widget clippedContent;
    BoxDecoration frameDecoration;

    switch (shapeType) {
      case FacecamShapeType.circle:
        clippedContent = ClipOval(child: content);
        frameDecoration = BoxDecoration(
          shape: BoxShape.circle,
          border: widget.showBorder
              ? Border.all(color: const Color(0xFFDC2626), width: 2.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        );
        break;

      case FacecamShapeType.roundedRect:
        final r = BorderRadius.circular(20);
        clippedContent = ClipRRect(borderRadius: r, child: content);
        frameDecoration = BoxDecoration(
          borderRadius: r,
          border: widget.showBorder
              ? Border.all(color: const Color(0xFFDC2626), width: 2.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        );
        break;

      case FacecamShapeType.square:
        final r = BorderRadius.circular(8);
        clippedContent = ClipRRect(borderRadius: r, child: content);
        frameDecoration = BoxDecoration(
          borderRadius: r,
          border: widget.showBorder
              ? Border.all(color: const Color(0xFFDC2626), width: 2.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        );
        break;
    }

    final window = Container(
      width: widget.size,
      height: widget.size,
      decoration: frameDecoration,
      child: clippedContent,
    );

    if (widget.onTap != null) {
      return GestureDetector(onTap: widget.onTap, child: window);
    }
    return window;
  }

  Widget _buildCameraContent(FacecamShapeType shapeType) {
    return Container(
      width: widget.size,
      height: widget.size,
      color: const Color(0xFF111827),
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          // ── Main Video / Snapshot Content ──────────────────────────────────
          Positioned.fill(
            child: _buildFeedView(),
          ),

          // ── Camera lens reflection highlight (top corner) ────────────────
          Positioned(
            top: 4,
            left: 4,
            child: Container(
              width: widget.size * 0.2,
              height: widget.size * 0.2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom LIVE / PiP Indicator Badge ────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    const Color(0xFFDC2626).withValues(alpha: 0.95),
                  ],
                ),
              ),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      widget.isLive ? '● LIVE' : 'PiP',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: (widget.size * 0.08).clamp(8.0, 11.0),
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedView() {
    // 1. If we have an active, initialized CameraController, render live feed
    final controller = activeController;
    if (widget.isLive && controller != null && controller.value.isInitialized) {
      final double targetSize = widget.size;
      final orientation = MediaQuery.of(context).orientation;
      final bool isLandscape = orientation == Orientation.landscape;

      // In Flutter camera plugin:
      // controller.value.aspectRatio is typically width/height of camera sensor buffer (> 1.0, e.g. 4/3 or 16/9).
      final double rawAspect = controller.value.aspectRatio > 0 ? controller.value.aspectRatio : (4.0 / 3.0);

      // Determine effective preview aspect ratio based on device orientation:
      // In portrait, camera preview has aspect ratio 1 / rawAspect (e.g. 3/4 = 0.75, taller than wide).
      // In landscape, camera preview has aspect ratio rawAspect (e.g. 4/3 = 1.33, wider than tall).
      final double previewAspect = isLandscape ? rawAspect : (1.0 / rawAspect);

      // Centered cover-crop inside a square of targetSize x targetSize:
      // If previewAspect < 1.0 (portrait): width = targetSize, height = targetSize / previewAspect (taller)
      // If previewAspect >= 1.0 (landscape): height = targetSize, width = targetSize * previewAspect (wider)
      final double w = previewAspect >= 1.0 ? targetSize * previewAspect : targetSize;
      final double h = previewAspect >= 1.0 ? targetSize : targetSize / previewAspect;

      // Natural selfie mirror: front camera is mirrored horizontally
      final mirrorTransform = _isFrontCamera
          ? (Matrix4.identity()..scale(-1.0, 1.0, 1.0))
          : Matrix4.identity();

      return ClipRect(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(
            width: w,
            height: h,
            child: Transform(
              alignment: Alignment.center,
              transform: mirrorTransform,
              child: Center(
                child: AspectRatio(
                  aspectRatio: previewAspect,
                  child: CameraPreview(controller),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 2. Loading state while camera initializes
    if (widget.isLive && _isInitializing) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: (widget.size * 0.2).clamp(16.0, 28.0),
              height: (widget.size * 0.2).clamp(16.0, 28.0),
              child: const CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Color(0xFFDC2626),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Starting camera...',
              style: GoogleFonts.hankenGrotesk(
                fontSize: (widget.size * 0.07).clamp(8.0, 11.0),
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    // 3. Clear error state if camera permission or initialization failed
    if (widget.isLive && _errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.videocam_off_rounded,
                  size: (widget.size * 0.24).clamp(18.0, 36.0),
                  color: const Color(0xFFEF4444),
                ),
                const SizedBox(height: 2),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: (widget.size * 0.075).clamp(8.0, 11.0),
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: _initCamera,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Retry Camera',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: (widget.size * 0.07).clamp(8.0, 10.0),
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 4. Saved Snapshot Image (for playback or completed recordings)
    if (widget.previewImageBytes != null) {
      return Image.memory(
        widget.previewImageBytes!,
        fit: BoxFit.cover,
        width: widget.size,
        height: widget.size,
      );
    }

    if (widget.previewImagePath != null && widget.previewImagePath!.isNotEmpty) {
      if (!kIsWeb && File(widget.previewImagePath!).existsSync()) {
        return Image.file(
          File(widget.previewImagePath!),
          fit: BoxFit.cover,
          width: widget.size,
          height: widget.size,
        );
      }
    }

    // 5. Default styled presenter camera view (gradient backdrop with active lens indicator)
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 0.85,
          colors: [
            Color(0xFF374151),
            Color(0xFF111827),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.camera_front_rounded,
              size: (widget.size * 0.35).clamp(24.0, 48.0),
              color: Colors.white.withValues(alpha: 0.85),
            ),
            const SizedBox(height: 2),
            Text(
              'Facecam Feed',
              style: GoogleFonts.hankenGrotesk(
                fontSize: (widget.size * 0.07).clamp(8.0, 10.0),
                color: Colors.white60,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
