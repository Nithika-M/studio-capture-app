enum RecordingMode { screen, voiceScreen, facecam, game, gif }

class MediaItem {
  final String id;
  final String title;
  final String type;
  final String thumbnail;
  final String? duration;
  final String resolution;
  final String date;
  final String size;
  final String? filePath;
  final bool isVoiceScreen;
  final bool hasFacecam;
  final String? facecamShape;
  final double? facecamNormalizedX;
  final double? facecamNormalizedY;
  final double? facecamSizeRatio;
  final String? facecamSnapshotPath;

  MediaItem({
    required this.id,
    required this.title,
    required this.type,
    required this.thumbnail,
    this.duration,
    required this.resolution,
    required this.date,
    required this.size,
    this.filePath,
    this.isVoiceScreen = false,
    this.hasFacecam = false,
    this.facecamShape,
    this.facecamNormalizedX,
    this.facecamNormalizedY,
    this.facecamSizeRatio,
    this.facecamSnapshotPath,
  });
}

class RecordingSettings {
  final RecordingMode mode;
  final String resolution;
  final int fps;
  final double bitrate;
  final String orientation;
  final String audioSource;
  final bool showFacecam;
  final String facecamShape;
  final String countdown;
  final bool showTouches;
  final bool floatingBubble;
  final bool shakeToStop;
  final String? sourceId;
  final String? sourceTitle;

  RecordingSettings({
    required this.mode,
    required this.resolution,
    required this.fps,
    required this.bitrate,
    required this.orientation,
    required this.audioSource,
    required this.showFacecam,
    required this.facecamShape,
    required this.countdown,
    required this.showTouches,
    required this.floatingBubble,
    required this.shakeToStop,
    this.sourceId,
    this.sourceTitle,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'mode': mode.name,
      'resolution': resolution,
      'fps': fps,
      'bitrate': bitrate,
      'orientation': orientation,
      'audioSource': audioSource,
      'showFacecam': showFacecam,
      'facecamShape': facecamShape,
      'countdown': countdown,
      'showTouches': showTouches,
      'floatingBubble': floatingBubble,
      'shakeToStop': shakeToStop,
    };
    if (sourceId != null) map['sourceId'] = sourceId;
    if (sourceTitle != null) map['sourceTitle'] = sourceTitle;
    return map;
  }
}