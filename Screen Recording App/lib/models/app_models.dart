enum CaptureModeType {
  screen,
  voiceAndScreen,
  facecam,
  game,
  screenshot,
  drawOnScreen,
  gif,
}

class CaptureMode {
  final CaptureModeType type;
  final String title;
  final String subtitle;
  final String iconName;
  final String? badgeText;
  final bool isPrimary;

  const CaptureMode({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.iconName,
    this.badgeText,
    this.isPrimary = false,
  });
}

class MediaItem {
  final String id;
  final String title;
  final String duration;
  final String resolution;
  final int fps;
  final String fileSize;
  final String timeAgo;
  final bool isSynced;
  final String type; // 'video', 'screenshot', 'gif'
  final String thumbnailUrl;

  const MediaItem({
    required this.id,
    required this.title,
    required this.duration,
    required this.resolution,
    required this.fps,
    required this.fileSize,
    required this.timeAgo,
    required this.isSynced,
    required this.type,
    required this.thumbnailUrl,
  });
}
