import 'package:flutter/material.dart';
import '../utils/theme.dart';

class VideoEditorScreen extends StatefulWidget {
  const VideoEditorScreen({Key? key}) : super(key: key);

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen> {
  double _startTrim = 0.1;
  double _endTrim = 0.9;
  String _activeTool = 'Trim';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Video Editor', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pushReplacementNamed('/media-library');
            },
            child: const Text('Export', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Editor Video Canvas
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(Icons.movie_creation_rounded, size: 64, color: Colors.white.withOpacity(0.3)),
                      const CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.white24,
                        child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Timeline & Waveform Scrubber Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Timeline Trim Slider
                  Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary, width: 2),
                    ),
                    child: RangeSlider(
                      values: RangeValues(_startTrim, _endTrim),
                      activeColor: AppColors.primary,
                      inactiveColor: Colors.grey.shade800,
                      onChanged: (values) {
                        setState(() {
                          _startTrim = values.start;
                          _endTrim = values.end;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('00:04:32', style: TextStyle(color: Colors.grey, fontSize: 10, fontFamily: 'monospace')),
                      Text('00:12:08', style: TextStyle(color: Colors.grey, fontSize: 10, fontFamily: 'monospace')),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Editing Toolbar (Trim, Split, Crop, Rotate, Speed, Audio)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildToolButton(Icons.content_cut_rounded, 'Trim'),
                      _buildToolButton(Icons.call_split_rounded, 'Split'),
                      _buildToolButton(Icons.crop_rounded, 'Crop'),
                      _buildToolButton(Icons.rotate_right_rounded, 'Rotate'),
                      _buildToolButton(Icons.speed_rounded, 'Speed'),
                      _buildToolButton(Icons.volume_up_rounded, 'Audio'),
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

  Widget _buildToolButton(IconData icon, String label) {
    final isSelected = _activeTool == label;
    return InkWell(
      onTap: () {
        setState(() {
          _activeTool = label;
        });
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary : Colors.grey.shade800,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? AppColors.primary : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
