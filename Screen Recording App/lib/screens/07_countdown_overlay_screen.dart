import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/theme.dart';

class CountdownOverlayScreen extends StatefulWidget {
  const CountdownOverlayScreen({Key? key}) : super(key: key);

  @override
  State<CountdownOverlayScreen> createState() => _CountdownOverlayScreenState();
}

class _CountdownOverlayScreenState extends State<CountdownOverlayScreen> {
  int _countdown = 3;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 1) {
        setState(() {
          _countdown--;
        });
      } else {
        _timer?.cancel();
        Navigator.of(context).pushReplacementNamed('/floating-controls');
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.85),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Recording starts in...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 32),
              // Glowing REC Circle Countdown
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.6),
                      blurRadius: 30,
                      spreadRadius: 6,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '$_countdown',
                    style: const TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 48),
              OutlinedButton.icon(
                onPressed: () {
                  _timer?.cancel();
                  Navigator.of(context).pop();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Cancel Countdown', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
