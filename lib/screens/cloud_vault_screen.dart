import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/theme_service.dart';
import '../services/preferences_service.dart';
import '../services/cloud_vault_service.dart';
import '../services/recording_service.dart';

class CloudVaultScreen extends StatefulWidget {
  const CloudVaultScreen({super.key});

  @override
  State<CloudVaultScreen> createState() => _CloudVaultScreenState();
}

class _CloudVaultScreenState extends State<CloudVaultScreen> {
  AppColors get colors => context.appColors;
  final PreferencesService _prefs = PreferencesService();

  bool _autoSync = false;
  bool _wifiOnly = true;
  bool _isSyncing = false;
  bool _isLoading = false;

  final Map<String, double> _downloadingFiles = {};

  final List<Map<String, dynamic>> _cloudFiles = [
    {
      'title': 'SCR_20250518_Gameplay_HQ.mp4',
      'size': '148.4 MB',
      'date': 'May 18, 2025 • 22:45',
      'duration': '12:37',
      'status': 'Synced',
      'provider': 'Google Drive',
      'resolution': '1080p 60fps',
      'uploadedAt': 1747589100000,
    },
    {
      'title': 'VoiceScreen_Tutorial_Draft.mp4',
      'size': '86.2 MB',
      'date': 'May 17, 2025 • 15:20',
      'duration': '08:14',
      'status': 'Synced',
      'provider': 'Google Drive',
      'resolution': '1080p Dual Audio',
      'uploadedAt': 1747476000000,
    },
    {
      'title': 'Bug_Repro_StepByStep.mp4',
      'size': '34.0 MB',
      'date': 'May 16, 2025 • 11:05',
      'duration': '02:50',
      'status': 'Synced',
      'provider': 'Cloud Vault',
      'resolution': '720p 30fps',
      'uploadedAt': 1747389900000,
    },
    {
      'title': 'Gaming_Highlights_Clutch.mp4',
      'size': '210.5 MB',
      'date': 'May 15, 2025 • 19:30',
      'duration': '18:22',
      'status': 'Synced',
      'provider': 'Google Drive',
      'resolution': '1440p 60fps',
      'uploadedAt': 1747333800000,
    },
  ];

  List<Map<String, dynamic>> get _activeCloudFiles {
    final deleted = _prefs.deletedCloudTitles;
    final List<Map<String, dynamic>> list = [];
    for (final f in _prefs.cloudVaultRecords) {
      if (!deleted.contains(f['title'])) {
        list.add(Map<String, dynamic>.from(f));
      }
    }
    for (final f in _cloudFiles) {
      if (!deleted.contains(f['title']) && !list.any((x) => x['title'] == f['title'])) {
        list.add(Map<String, dynamic>.from(f));
      }
    }
    // Newest first: sort by uploadedAt timestamp descending
    list.sort((a, b) {
      final timeA = (a['uploadedAt'] as num?)?.toInt() ?? 0;
      final timeB = (b['uploadedAt'] as num?)?.toInt() ?? 0;
      return timeB.compareTo(timeA);
    });
    return list;
  }

  @override
  void initState() {
    super.initState();
    _autoSync = _prefs.autoSync;
  }

  Future<void> _handleRefresh() async {
    setState(() => _isLoading = true);
    if (_autoSync) {
      await CloudVaultService().syncAllUnsynced();
    }
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _triggerSync() async {
    setState(() => _isSyncing = true);
    if (_autoSync) {
      final savedItems = RecordingService().savedMediaItems;
      for (final item in savedItems) {
        if (item.filePath != null && !_prefs.isCloudSynced(item.filePath!)) {
          await CloudVaultService().syncRecording(
            filePath: item.filePath!,
            title: item.title,
            size: item.size,
            duration: item.duration,
            resolution: item.resolution,
          );
        }
      }
    }
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      setState(() => _isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cloud Vault synchronized! All recordings up to date.'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }
  }

  // ── 1. Download to Device ────────────────────────────────────────────────
  Future<void> _downloadVideo(Map<String, dynamic> file) async {
    final title = (file['title'] as String? ?? '').trim();
    if (title.isEmpty) return;

    // Check if the file already exists locally
    bool alreadyExistsLocally = false;
    final originalPath = file['filePath'] as String?;
    if (originalPath != null && File(originalPath).existsSync()) {
      alreadyExistsLocally = true;
    } else if (!kIsWeb) {
      try {
        final extDirs = await getExternalStorageDirectories(type: StorageDirectory.movies);
        if (extDirs != null && extDirs.isNotEmpty) {
          final cand1 = File('${extDirs.first.path}/ConsolidatedRecorder/$title');
          final cand2 = File('${extDirs.first.path}/ScreenRecordingApp/$title');
          final cand3 = File('${extDirs.first.path}/$title');
          if (cand1.existsSync() || cand2.existsSync() || cand3.existsSync()) {
            alreadyExistsLocally = true;
          }
        }
      } catch (_) {}
    }

    if (alreadyExistsLocally) {
      if (!mounted) return;
      final bool? proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'File Already Exists',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: colors.textPrimary),
          ),
          content: Text(
            'A local copy of "$title" already exists on your device.\n\nDo you want to download again?',
            style: GoogleFonts.hankenGrotesk(color: colors.textSecondary, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Download Again', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    // Check Internet Connection
    final hasInternet = await CloudVaultService().checkInternetConnection();
    if (!hasInternet) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No internet connection. Cannot download from cloud.'),
            backgroundColor: const Color(0xFFDC2626),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _downloadVideo(file),
            ),
          ),
        );
      }
      return;
    }

    // Check Storage Capacity
    final storageInfo = await RecordingService().getDeviceStorageInfo();
    final freeBytes = (storageInfo?['availableDeviceBytes'] as num?)?.toInt() ?? 1000000000;
    if (freeBytes < 50 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Low device storage. Please free up space before downloading.'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
      }
      return;
    }

    // Check Storage Permission on Android
    if (!kIsWeb && Platform.isAndroid) {
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
      if (!status.isGranted && (await Permission.videos.status).isDenied) {
        await Permission.videos.request();
      }
    }

    // Progress state
    setState(() => _downloadingFiles[title] = 0.05);

    try {
      final downloadedFile = await CloudVaultService().downloadCloudVideo(
        fileData: file,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _downloadingFiles[title] = progress);
          }
        },
      );

      if (mounted) {
        setState(() => _downloadingFiles.remove(title));
        if (downloadedFile != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Downloaded successfully: $title')),
                ],
              ),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to download $title'),
              backgroundColor: const Color(0xFFDC2626),
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () => _downloadVideo(file),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloadingFiles.remove(title));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: const Color(0xFFDC2626),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _downloadVideo(file),
            ),
          ),
        );
      }
    }
  }

  // ── 2. Copy Cloud Link ──────────────────────────────────────────────────
  Future<void> _copyCloudLink(Map<String, dynamic> file) async {
    final link = CloudVaultService().getShareableLink(file);
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Link copied: $link'),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Open',
            textColor: Colors.white,
            onPressed: () async {
              try {
                await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
              } catch (_) {}
            },
          ),
        ),
      );
    }
  }

  // ── 3. Delete from Cloud ────────────────────────────────────────────────
  Future<void> _deleteFromCloud(Map<String, dynamic> file) async {
    final title = (file['title'] as String? ?? '').trim();
    if (title.isEmpty) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete from cloud?',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: colors.textPrimary),
        ),
        content: Text(
          'Delete this video from cloud? This cannot be undone.\n\nYour local recording on this device will NOT be deleted.',
          style: GoogleFonts.hankenGrotesk(color: colors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Check internet connection
    final hasInternet = await CloudVaultService().checkInternetConnection();
    if (!hasInternet) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete from cloud: No internet connection.'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
      }
      return;
    }

    // Remove from cloud database & mark deleted so auto-sync never re-uploads it
    await _prefs.removeCloudFile(title);
    if (mounted) {
      setState(() {
        _cloudFiles.removeWhere((item) => item['title'] == title);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$title deleted from cloud'),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeFiles = _activeCloudFiles;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Cloud Vault & Backup',
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: _isSyncing || _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFDC2626)),
                  )
                : const Icon(Icons.sync_rounded, color: Color(0xFFDC2626)),
            tooltip: 'Sync now',
            onPressed: (_isSyncing || _isLoading) ? null : _triggerSync,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFFDC2626),
        onRefresh: _handleRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Quota & Storage Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: colors.isDark ? 0.25 : 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: colors.primaryBg,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.cloud_done_rounded, color: Color(0xFFDC2626), size: 24),
                            ),
                            const SizedBox(width: 14),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Cloud Storage Quota',
                                  style: GoogleFonts.manrope(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                Text(
                                  'Google Drive: user@example.com',
                                  style: GoogleFonts.hankenGrotesk(
                                    fontSize: 12,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(9999),
                          ),
                          child: Text(
                            'Online',
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF10B981),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9999),
                      child: LinearProgressIndicator(
                        value: 0.124, // 12.4 GB / 100 GB
                        minHeight: 8,
                        backgroundColor: colors.surfaceSecondary,
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFDC2626)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '12.4 GB Used',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          '100 GB Total (12.4% Used)',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Backup Settings
              Text(
                'Backup Settings',
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.border),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Column(
                    children: [
                      SwitchListTile(
                        activeThumbColor: const Color(0xFFDC2626),
                        value: _autoSync,
                        onChanged: (val) async {
                          setState(() => _autoSync = val);
                          await _prefs.setAutoSync(val);
                          if (val) {
                            await CloudVaultService().enableAutoSync();
                          } else {
                            await CloudVaultService().disableAutoSync();
                          }
                          if (mounted) setState(() {});
                        },
                        title: Text(
                          'Auto-Sync New Recordings',
                          style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: colors.textPrimary),
                        ),
                        subtitle: Text(
                          'Automatically upload completed screen recordings to cloud',
                          style: GoogleFonts.hankenGrotesk(fontSize: 12, color: colors.textSecondary),
                        ),
                      ),
                      Divider(color: colors.border, height: 1),
                      SwitchListTile(
                        activeThumbColor: const Color(0xFFDC2626),
                        value: _wifiOnly,
                        onChanged: (val) => setState(() => _wifiOnly = val),
                        title: Text(
                          'Backup via Wi-Fi Only',
                          style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: colors.textPrimary),
                        ),
                        subtitle: Text(
                          'Avoid mobile data charges during large 4K / 60FPS uploads',
                          style: GoogleFonts.hankenGrotesk(fontSize: 12, color: colors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Cloud Recordings Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Cloud Recordings (${activeFiles.length})',
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _isSyncing || _isLoading ? null : _handleRefresh,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFDC2626)),
                          )
                        : const Icon(Icons.refresh, size: 16, color: Color(0xFFDC2626)),
                    label: Text(
                      'Refresh',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFDC2626),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Loading indicator if fetching
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFFDC2626)),
                  ),
                ),

              // Empty State
              if (!_isLoading && activeFiles.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.border),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: colors.primaryBg,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.cloud_off_rounded, color: Color(0xFFDC2626), size: 28),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'No videos in Cloud Vault yet',
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Turn on Auto-Sync to Cloud to back up all your screen recordings automatically.',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

              // Video List (Newest first)
              if (!_isLoading && activeFiles.isNotEmpty)
                ...activeFiles.map((file) => _buildVideoItem(file)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoItem(Map<String, dynamic> file) {
    final title = (file['title'] as String? ?? 'Untitled.mp4').trim();
    final duration = file['duration'] as String? ?? '00:00';
    final size = file['size'] as String? ?? '0 MB';
    final date = file['date'] as String? ?? '';
    final thumbnailPath = file['thumbnail'] as String?;
    final isDownloading = _downloadingFiles.containsKey(title);
    final downloadProgress = _downloadingFiles[title] ?? 0.0;

    final hasLocalThumbnail = !kIsWeb && thumbnailPath != null && File(thumbnailPath).existsSync();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: colors.isDark ? 0.2 : 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Video Thumbnail with Duration badge
              Container(
                width: 76,
                height: 56,
                decoration: BoxDecoration(
                  color: colors.primaryBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.borderLight),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (hasLocalThumbnail)
                        Positioned.fill(
                          child: Image.file(
                            File(thumbnailPath),
                            fit: BoxFit.cover,
                          ),
                        )
                      else
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFFDC2626).withValues(alpha: 0.15),
                                  const Color(0xFF991B1B).withValues(alpha: 0.35),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                          ),
                        ),
                      // Play icon overlay
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                      ),
                      // Duration badge
                      Positioned(
                        bottom: 3,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            duration,
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // File Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$size • $duration • ${file['resolution'] ?? '1080p'}',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          date,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 10,
                            color: colors.textTertiary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // "Synced" Status
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.cloud_done_rounded, color: Color(0xFF10B981), size: 10),
                              const SizedBox(width: 3),
                              Text(
                                'Synced',
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // More Options Three-Dot Menu
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: colors.textSecondary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                color: colors.surface,
                elevation: 4,
                onSelected: (val) {
                  if (val == 'download') {
                    _downloadVideo(file);
                  } else if (val == 'link') {
                    _copyCloudLink(file);
                  } else if (val == 'delete') {
                    _deleteFromCloud(file);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'download',
                    child: Row(
                      children: [
                        const Icon(Icons.download_rounded, size: 18, color: Color(0xFFDC2626)),
                        const SizedBox(width: 10),
                        Text(
                          'Download to device',
                          style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: colors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'link',
                    child: Row(
                      children: [
                        Icon(Icons.link_rounded, size: 18, color: colors.textSecondary),
                        const SizedBox(width: 10),
                        Text(
                          'Copy cloud link',
                          style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: colors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                        const SizedBox(width: 10),
                        Text(
                          'Delete from cloud',
                          style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Download Progress Bar if downloading
          if (isDownloading) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: downloadProgress > 0 ? downloadProgress : null,
                minHeight: 4,
                backgroundColor: colors.surfaceSecondary,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFDC2626)),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Downloading to device...',
                  style: GoogleFonts.hankenGrotesk(fontSize: 10, color: colors.textSecondary),
                ),
                Text(
                  '${(downloadProgress * 100).toInt()}%',
                  style: GoogleFonts.hankenGrotesk(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFFDC2626)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
