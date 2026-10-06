import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ed_screen_recorder/ed_screen_recorder.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Screen Recorder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

// ---------------- SPLASH SCREEN ----------------

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam_rounded,
              size: 90,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
            const SizedBox(height: 16),
            Text(
              'Screen Recorder',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
            const SizedBox(height: 24),
            CircularProgressIndicator(
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- HOME SCREEN ----------------

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Screen Recorder'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: [
            _HomeTile(
              icon: Icons.fiber_manual_record,
              label: 'Start Recording',
              color: Colors.red,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RecordingScreen()),
                );
              },
            ),
            _HomeTile(
              icon: Icons.screenshot_monitor,
              label: 'Screenshot',
              color: Colors.orange,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Coming in a later step')),
                );
              },
            ),
            _HomeTile(
              icon: Icons.video_library_outlined,
              label: 'Recordings',
              color: Colors.deepPurple,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RecordingsScreen(),
                  ),
                );
              },
            ),
            _HomeTile(
              icon: Icons.settings_outlined,
              label: 'Settings',
              color: Colors.blueGrey,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _HomeTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- RECORDING SCREEN ----------------

enum _RecState { idle, recording, paused }

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  final EdScreenRecorder _recorder = EdScreenRecorder();

  _RecState _state = _RecState.idle;
  DateTime? _segmentStart;
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.microphone,
      Permission.storage,
      Permission.manageExternalStorage,
      Permission.notification,
    ].request();
  }

  Future<Directory> _recordingsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/recordings');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  void _startTimer() {
    _segmentStart = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _elapsed = _elapsed + const Duration(seconds: 1);
      });
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<void> _startRecording() async {
    try {
      final dir = await _recordingsDir();
      final size = MediaQuery.of(context).size;
      final pixelRatio = MediaQuery.of(context).devicePixelRatio;

      await _recorder.startRecordScreen(
        fileName: 'recording_${DateTime.now().millisecondsSinceEpoch}',
        dirPathToSave: dir.path,
        audioEnable: true,
        width: (size.width * pixelRatio).round(),
        height: (size.height * pixelRatio).round(),
      );

      setState(() {
        _state = _RecState.recording;
        _elapsed = Duration.zero;
      });
      _startTimer();
    } catch (e) {
      _showMessage('Error starting recording: $e');
    }
  }

  Future<void> _pauseRecording() async {
    try {
      await _recorder.pauseRecord();
      _stopTimer();
      setState(() => _state = _RecState.paused);
    } catch (e) {
      _showMessage('Error pausing recording: $e');
    }
  }

  Future<void> _resumeRecording() async {
    try {
      await _recorder.resumeRecord();
      setState(() => _state = _RecState.recording);
      _startTimer();
    } catch (e) {
      _showMessage('Error resuming recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      _stopTimer();
      final stopResponse = await _recorder.stopRecord();
      setState(() => _state = _RecState.idle);

      if (stopResponse != null) {
        _showMessage('Recording saved!');
        if (mounted) Navigator.pop(context);
      } else {
        _showMessage('Recording stopped, but no file was returned.');
      }
    } catch (e) {
      _showMessage('Error stopping recording: $e');
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final isRecording = _state == _RecState.recording;
    final isPaused = _state == _RecState.paused;
    final isActive = isRecording || isPaused;

    return Scaffold(
      appBar: AppBar(title: const Text('Recording')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              isActive ? _formatDuration(_elapsed) : 'Ready',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (isPaused)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'PAUSED',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const SizedBox(height: 32),

            if (!isActive)
              // Idle: single start button
              GestureDetector(
                onTap: _startRecording,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.deepPurple,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.fiber_manual_record,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              )
            else
              // Recording or paused: pause/resume + stop buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: isPaused ? _resumeRecording : _pauseRecording,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.orange,
                      ),
                      child: Icon(
                        isPaused ? Icons.play_arrow : Icons.pause,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  GestureDetector(
                    onTap: _stopRecording,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red,
                      ),
                      child: const Icon(
                        Icons.stop,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 12),
            Text(
              !isActive
                  ? 'Tap to start recording'
                  : isPaused
                      ? 'Paused — tap play to resume'
                      : 'Recording — pause or stop',
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- RECORDINGS SCREEN ----------------

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  List<FileSystemEntity> _recordings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  Future<Directory> _recordingsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/recordings');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _loadRecordings() async {
    setState(() => _loading = true);
    final dir = await _recordingsDir();
    final files = dir
        .listSync()
        .where((f) => f.path.endsWith('.mp4'))
        .toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    setState(() {
      _recordings = files;
      _loading = false;
    });
  }

  Future<void> _deleteRecording(FileSystemEntity file) async {
    await file.delete();
    _loadRecordings();
  }

  Future<void> _openRecording(FileSystemEntity file) async {
    await OpenFile.open(file.path);
  }

  Future<void> _shareRecording(FileSystemEntity file) async {
    await Share.shareXFiles([XFile(file.path)]);
  }

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recordings'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadRecordings),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _recordings.isEmpty
              ? const Center(child: Text('No recordings yet'))
              : ListView.builder(
                  itemCount: _recordings.length,
                  itemBuilder: (context, index) {
                    final file = _recordings[index];
                    final stat = file.statSync();
                    return ListTile(
                      leading: const Icon(Icons.videocam),
                      title: Text(
                        DateFormat('dd MMM yyyy, hh:mm a').format(stat.modified),
                      ),
                      subtitle: Text(_formatSize(stat.size)),
                      onTap: () => _openRecording(file),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.share),
                            onPressed: () => _shareRecording(file),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deleteRecording(file),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

// ---------------- SETTINGS SCREEN (placeholder for now) ----------------

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(
        child: Text('Settings options will be added in a later step'),
      ),
    );
  }
}