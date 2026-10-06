import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_models.dart';

// Current active bottom nav index
final bottomNavIndexProvider = StateProvider<int>((ref) => 0);

// Selected capture mode
final selectedCaptureModeProvider = StateProvider<CaptureModeType>((ref) => CaptureModeType.screen);

// Recording state
final isRecordingActiveProvider = StateProvider<bool>((ref) => false);
final recordingDurationSecondsProvider = StateProvider<int>((ref) => 0);

// Audio & Video Config Settings
final resolutionProvider = StateProvider<String>((ref) => '1080p');
final fpsProvider = StateProvider<int>((ref) => 60);
final bitrateProvider = StateProvider<String>((ref) => '12 Mbps');
final isInternalAudioOnProvider = StateProvider<bool>((ref) => true);
final isMicOnProvider = StateProvider<bool>((ref) => false);
final isFacecamOnProvider = StateProvider<bool>((ref) => false);
final isCloudBackupOnProvider = StateProvider<bool>((ref) => true);

// Mock Media Items list
final mediaItemsProvider = StateProvider<List<MediaItem>>((ref) => [
  const MediaItem(
    id: '1',
    title: 'Apex_Battle_S6_Clip',
    duration: '04:12',
    resolution: '1080p',
    fps: 60,
    fileSize: '142 MB',
    timeAgo: '2 hrs ago',
    isSynced: true,
    type: 'video',
    thumbnailUrl: 'https://picsum.photos/300/200?random=1',
  ),
  const MediaItem(
    id: '2',
    title: 'App_Tutorial_v2',
    duration: '01:45',
    resolution: '1080p',
    fps: 30,
    fileSize: '48 MB',
    timeAgo: 'Yesterday',
    isSynced: false,
    type: 'video',
    thumbnailUrl: 'https://picsum.photos/300/200?random=2',
  ),
  const MediaItem(
    id: '3',
    title: 'Dev_Walkthrough_Refactor',
    duration: '12:08',
    resolution: '1080p',
    fps: 60,
    fileSize: '390 MB',
    timeAgo: '3 days ago',
    isSynced: true,
    type: 'video',
    thumbnailUrl: 'https://picsum.photos/300/200?random=3',
  ),
]);
