import 'package:flutter/material.dart';
import '../utils/theme.dart';

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({Key? key}) : super(key: key);

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  bool _isPlaying = true;
  double _progress = 0.35;
  double _playbackSpeed = 1.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Apex_Battle_S6_Clip.mp4', style: TextStyle(color: Colors.white, fontSize: 16)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: Colors.white),
            onPressed: () {
              Navigator.of(context).pushNamed('/video-editor');
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Video Viewport Area
            Expanded(
              child: Stack(
                children: [
                  Center(
                    child: Icon(Icons.movie_rounded, size: 80, color: Colors.white.withOpacity(0.3)),
                  ),
                  Center(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _isPlaying = !_isPlaying;
                        });
                      },
                      child: CircleAvatar(
                        radius: 32,
                        backgroundColor: Colors.white.withOpacity(0.85),
                        child: Icon(
                          _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: AppColors.primary,
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Controls & Telemetry Panel
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF111827),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Timeline Scrubber
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppColors.primary,
                      thumbColor: AppColors.primary,
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: _progress,
                      onChanged: (val) {
                        setState(() {
                          _progress = val;
                        });
                      },
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('01:28', style: TextStyle(color: Colors.grey, fontSize: 11)),
                        Text('04:12', style: TextStyle(color: Colors.grey, fontSize: 11)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Playback Controls Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 28),
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: Icon(
                          _isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                          color: AppColors.primary,
                          size: 54,
                        ),
                        onPressed: () {
                          setState(() {
                            _isPlaying = !_isPlaying;
                          });
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 28),
                        onPressed: () {},
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Speed & Telemetry Info Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _playbackSpeed = _playbackSpeed == 1.0 ? 1.5 : 1.0;
                          });
                        },
                        icon: const Icon(Icons.speed_rounded, size: 16, color: Colors.grey),
                        label: Text('${_playbackSpeed}x', style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                      const Text(
                        '1080p • 60 FPS • Lossless Audio',
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
