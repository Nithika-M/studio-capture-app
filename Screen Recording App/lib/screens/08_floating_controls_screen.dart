import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/theme.dart';

class FloatingControlsScreen extends StatefulWidget {
  const FloatingControlsScreen({Key? key}) : super(key: key);

  @override
  State<FloatingControlsScreen> createState() => _FloatingControlsScreenState();
}

class _FloatingControlsScreenState extends State<FloatingControlsScreen> {
  int _seconds = 0;
  Timer? _timer;
  bool _isMicOn = true;
  bool _isCamOn = true;

  // Draggable widget positions
  Offset _pillOffset = const Offset(20, 100);
  Offset _facecamOffset = const Offset(200, 200);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _seconds++;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _formattedTime {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Background phone wallpaper simulation
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade900, Colors.indigo.shade900],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Center(
              child: Text(
                'Active Screen Recording Overlay\n(Simulated Home Screen)',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 16),
              ),
            ),
          ),

          // Floating Controls Pill (Draggable Widget)
          Positioned(
            left: _pillOffset.dx,
            top: _pillOffset.dy,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _pillOffset += details.delta;
                });
              },
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(30),
                color: Colors.black.withOpacity(0.85),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Pulsing REC Dot
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Timer
                      Text(
                        _formattedTime,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 12),
                      const SizedBox(
                        height: 16,
                        child: VerticalDivider(color: Colors.white30, width: 1),
                      ),
                      const SizedBox(width: 8),
                      // Mic toggle
                      IconButton(
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                        icon: Icon(
                          _isMicOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                          color: _isMicOn ? Colors.white : Colors.red,
                          size: 18,
                        ),
                        onPressed: () {
                          setState(() {
                            _isMicOn = !_isMicOn;
                          });
                        },
                      ),
                      const SizedBox(width: 6),
                      // Cam toggle
                      IconButton(
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                        icon: Icon(
                          _isCamOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                          color: _isCamOn ? Colors.white : Colors.red,
                          size: 18,
                        ),
                        onPressed: () {
                          setState(() {
                            _isCamOn = !_isCamOn;
                          });
                        },
                      ),
                      const SizedBox(width: 6),
                      // Stop Recording Button
                      GestureDetector(
                        onTap: () {
                          _timer?.cancel();
                          Navigator.of(context).pushReplacementNamed('/recording-completed');
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Icon(Icons.stop_rounded, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // PiP Facecam Bubble (Draggable)
          if (_isCamOn)
            Positioned(
              left: _facecamOffset.dx,
              top: _facecamOffset.dy,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _facecamOffset += details.delta;
                  });
                },
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.person_rounded, size: 48, color: Colors.white70),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
