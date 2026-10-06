import '../services/preferences_service.dart';
import '../services/recording_auth_service.dart';
import 'main_wrapper_screen.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/app_models.dart';
import 'video_player_screen.dart';
import 'profile_options_screens.dart';
import '../services/theme_service.dart';
import '../services/recording_service.dart';
import '../services/app_notification_service.dart';
import '../widgets/app_drawer.dart';

enum MediaFilter { all, videos, screenshots, gifs }
enum ViewMode { grid, list }
enum SortOption { newestFirst, oldestFirst, largestFirst, smallestFirst, durationLongest, durationShortest }

class RecordingsLibraryScreen extends StatefulWidget {
  const RecordingsLibraryScreen({super.key});

  @override
  State<RecordingsLibraryScreen> createState() => _RecordingsLibraryScreenState();
}

class _RecordingsLibraryScreenState extends State<RecordingsLibraryScreen>
    with WidgetsBindingObserver {
  AppColors get colors => context.appColors;

  MediaFilter _selectedFilter = MediaFilter.all;
  ViewMode _viewMode = ViewMode.grid;
  SortOption _currentSort = SortOption.newestFirst;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  /// Whether the biometric prompt has passed in this session.
  bool _authenticated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (PreferencesService().biometricLock) {
      _authenticated = false;
      // Only auto-prompt if this screen is active or standalone (e.g. tests or direct navigation).
      // Never prompt if in recording session or if running hidden in background tab.
      if (MainWrapperScreen.isLibraryTabActive || MainWrapperScreen.isStandalone) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !RecordingService().isRecording && !RecordingAuthService.isSessionAuthenticated) {
            _authenticate();
          }
        });
      }
    } else {
      _authenticated = true;
      _scanDiskRecordings();
    }
  }

  Future<void> _authenticate() async {
    if (!PreferencesService().biometricLock) {
      if (mounted) {
        setState(() => _authenticated = true);
        _scanDiskRecordings();
      }
      return;
    }
    final granted = await AppNotificationService.authenticateForLibraryAccess(context);
    if (!mounted) return;
    if (!granted) {
      setState(() => _authenticated = false);
      return;
    }
    setState(() => _authenticated = true);
    _scanDiskRecordings();
    if (mounted) {
      AppNotificationService.checkAndWarnLowStorage(context);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Intentionally avoid repeated auto-prompt loops on resume to prevent loops
    // when system permission/biometric prompts dismiss or during recording sessions.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _scanDiskRecordings() async {
    if (kIsWeb) return;
    try {
      await AppNotificationService.runAutoDeleteIfEnabled();
      final files = await RecordingService().getRecordings();
      // Remove any saved items whose files no longer exist on disk
      final existingPaths = files.map((f) => f.path).toSet();
      RecordingService().clearOrphanedMedia(existingPaths);

      for (final f in files) {
        final filename = f.path.split(Platform.pathSeparator).last;
        final alreadyInSaved = RecordingService().savedMediaItems.any((item) => item.filePath == f.path);
        final stat = f.statSync();
        final sizeStr = RecordingService().formatSize(stat.size);
        final isVoice = filename.contains('VoiceScreen');
        final isGif = filename.endsWith('.gif');
        final isPng = filename.endsWith('.png');

        int durationMs = 0;
        String res = '1080p';
        String? thumbPath;
        if (!isGif && !isPng) {
          final meta = await RecordingService().getVideoMetadata(f.path);
          if (meta != null) {
            durationMs = (meta['durationMs'] as num?)?.toInt() ?? 0;
            final w = (meta['width'] as num?)?.toInt() ?? 0;
            final h = (meta['height'] as num?)?.toInt() ?? 0;
            if (w > 0 && h > 0) res = '${w}x$h';
            thumbPath = meta['thumbnailPath'] as String?;
          }
        }

        final dur = isPng
            ? 'Screenshot'
            : (durationMs > 0
                ? '${(durationMs ~/ 60000).toString().padLeft(2, '0')}:${((durationMs % 60000) ~/ 1000).toString().padLeft(2, '0')}'
                : '00:00');

        final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        final dateStr = '${monthNames[stat.modified.month - 1]} ${stat.modified.day}, ${stat.modified.year}';

        if (!alreadyInSaved) {
          RecordingService().addSavedRecording(
            MediaItem(
              id: stat.modified.millisecondsSinceEpoch.toString(),
              title: filename,
              date: dateStr,
              duration: dur,
              size: sizeStr,
              resolution: res,
              type: isPng ? 'screenshot' : (isGif ? 'gif' : 'video'),
              thumbnail: isPng ? f.path : (thumbPath ?? ''),
              filePath: f.path,
              isVoiceScreen: isVoice,
            ),
          );
        } else {
          final idx = RecordingService().savedMediaItems.indexWhere((i) => i.filePath == f.path);
          if (idx != -1) {
            final cur = RecordingService().savedMediaItems[idx];
            if (cur.thumbnail.isEmpty || cur.size == '0 KB' || cur.duration == '00:00' || cur.title != filename) {
              RecordingService().savedMediaItems[idx] = MediaItem(
                id: cur.id,
                title: filename,
                date: dateStr,
                duration: dur != '00:00' ? dur : cur.duration,
                size: sizeStr,
                resolution: res != '1080p' ? res : cur.resolution,
                type: cur.type,
                thumbnail: isPng ? f.path : (thumbPath ?? cur.thumbnail),
                filePath: cur.filePath,
                isVoiceScreen: cur.isVoiceScreen,
                hasFacecam: cur.hasFacecam,
                facecamShape: cur.facecamShape,
              );
            }
          }
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error scanning disk recordings: $e');
    }
  }

  int get _allCount => RecordingService().savedMediaItems.where((i) => i.filePath == null || File(i.filePath!).existsSync()).length;
  int get _videoCount => RecordingService().savedMediaItems.where((i) => i.type == 'video' && (i.filePath == null || File(i.filePath!).existsSync())).length;
  int get _screenshotCount => RecordingService().savedMediaItems.where((i) => i.type == 'screenshot' && (i.filePath == null || File(i.filePath!).existsSync())).length;
  int get _gifCount => RecordingService().savedMediaItems.where((i) => i.type == 'gif' && (i.filePath == null || File(i.filePath!).existsSync())).length;

  int get _totalStorageBytes {
    int total = 0;
    for (final item in RecordingService().savedMediaItems) {
      if (item.filePath != null) {
        try {
          final f = File(item.filePath!);
          if (f.existsSync()) total += f.statSync().size;
        } catch (_) {}
      }
    }
    return total;
  }

  DateTime _getItemDate(MediaItem item) {
    if (item.filePath != null) {
      try {
        final f = File(item.filePath!);
        if (f.existsSync()) return f.statSync().modified;
      } catch (_) {}
    }
    final match = RegExp(r'\d+').firstMatch(item.id);
    if (match != null) {
      final ms = int.tryParse(match.group(0)!);
      if (ms != null && ms > 100000000000) {
        return DateTime.fromMillisecondsSinceEpoch(ms);
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  int _getItemSize(MediaItem item) {
    if (item.filePath != null) {
      try {
        final f = File(item.filePath!);
        if (f.existsSync()) return f.statSync().size;
      } catch (_) {}
    }
    return 0;
  }

  int _getItemDurationSeconds(MediaItem item) {
    final dur = item.duration;
    if (dur == null || dur.isEmpty || dur == 'Screenshot') return 0;
    final parts = dur.split(':').map((p) => int.tryParse(p) ?? 0).toList();
    if (parts.length == 2) {
      return parts[0] * 60 + parts[1];
    } else if (parts.length == 3) {
      return parts[0] * 3600 + parts[1] * 60 + parts[2];
    }
    return 0;
  }

  List<MediaItem> get _filteredItems {
    final allItems = List<MediaItem>.from(RecordingService().savedMediaItems);
    final filtered = allItems.where((item) {
      if (item.filePath != null && !kIsWeb) {
        final file = File(item.filePath!);
        if (!file.existsSync()) return false;
      }
      if (_selectedFilter == MediaFilter.videos && item.type != 'video') return false;
      if (_selectedFilter == MediaFilter.screenshots && item.type != 'screenshot') return false;
      if (_selectedFilter == MediaFilter.gifs && item.type != 'gif') return false;
      if (_searchQuery.isNotEmpty && !item.title.toLowerCase().contains(_searchQuery.toLowerCase())) return false;
      return true;
    }).toList();

    filtered.sort((a, b) {
      switch (_currentSort) {
        case SortOption.newestFirst:
          return _getItemDate(b).compareTo(_getItemDate(a));
        case SortOption.oldestFirst:
          return _getItemDate(a).compareTo(_getItemDate(b));
        case SortOption.largestFirst:
          return _getItemSize(b).compareTo(_getItemSize(a));
        case SortOption.smallestFirst:
          return _getItemSize(a).compareTo(_getItemSize(b));
        case SortOption.durationLongest:
          return _getItemDurationSeconds(b).compareTo(_getItemDurationSeconds(a));
        case SortOption.durationShortest:
          return _getItemDurationSeconds(a).compareTo(_getItemDurationSeconds(b));
      }
    });

    return filtered;
  }

  void _renameItem(MediaItem item) {
    final oldFilename = item.title;
    final ext = oldFilename.contains('.') ? '.${oldFilename.split('.').last}' : '';
    final nameWithoutExt = oldFilename.contains('.') ? oldFilename.substring(0, oldFilename.lastIndexOf('.')) : oldFilename;
    final controller = TextEditingController(text: nameWithoutExt);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Rename Recording', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: colors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            labelText: 'File Name',
            suffixText: ext,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final newBase = controller.text.trim();
              if (newBase.isNotEmpty && item.filePath != null) {
                final newFilename = '$newBase$ext';
                final oldFile = File(item.filePath!);
                if (await oldFile.exists()) {
                  final newPath = '${oldFile.parent.path}/$newFilename';
                  await oldFile.rename(newPath);
                  RecordingService().renameSavedItem(item.id, newFilename, newFilePath: newPath);
                  await RecordingService().scanFile(newPath);
                  await RecordingService().scanFile(oldFile.path);
                }
                if (mounted) setState(() {});
              }
              if (mounted) Navigator.pop(dialogCtx);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _deleteItem(MediaItem item) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Recording?', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: colors.textPrimary)),
        content: Text(
          'Are you sure you want to permanently delete "${item.title}"? This will remove the file from local storage and cloud vault.',
          style: GoogleFonts.hankenGrotesk(fontSize: 14, color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              if (item.filePath != null) {
                final f = File(item.filePath!);
                if (await f.exists()) {
                  await f.delete();
                  await RecordingService().scanFile(item.filePath!);
                }
                PreferencesService().removeCloudFile(item.filePath!);
              }
              PreferencesService().removeCloudFile(item.title);
              RecordingService().deleteSavedItem(item.id);
              if (mounted) {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Permanently deleted "${item.title}"')),
                );
              }
              if (mounted) Navigator.pop(dialogCtx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _shareItem(MediaItem item) async {
    if (item.filePath == null) return;
    final f = File(item.filePath!);
    if (await f.exists()) {
      final mimeType = item.type == 'screenshot'
          ? 'image/png'
          : (item.type == 'gif' ? 'image/gif' : 'video/mp4');
      await Share.shareXFiles(
        [XFile(item.filePath!, mimeType: mimeType)],
        text: 'Sharing recording: ${item.title}',
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File not found on disk.')),
      );
    }
  }

  String _getSortLabel() {
    switch (_currentSort) {
      case SortOption.newestFirst:
        return 'Newest';
      case SortOption.oldestFirst:
        return 'Oldest';
      case SortOption.largestFirst:
        return 'Largest';
      case SortOption.smallestFirst:
        return 'Smallest';
      case SortOption.durationLongest:
        return 'Longest';
      case SortOption.durationShortest:
        return 'Shortest';
    }
  }

  void _showSortBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Sort Recordings',
                style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: colors.textPrimary),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.arrow_downward_rounded),
              title: const Text('Newest First'),
              trailing: _currentSort == SortOption.newestFirst ? const Icon(Icons.check, color: Color(0xFFDC2626)) : null,
              onTap: () {
                setState(() => _currentSort = SortOption.newestFirst);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_upward_rounded),
              title: const Text('Oldest First'),
              trailing: _currentSort == SortOption.oldestFirst ? const Icon(Icons.check, color: Color(0xFFDC2626)) : null,
              onTap: () {
                setState(() => _currentSort = SortOption.oldestFirst);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.data_usage_rounded),
              title: const Text('Largest Size First'),
              trailing: _currentSort == SortOption.largestFirst ? const Icon(Icons.check, color: Color(0xFFDC2626)) : null,
              onTap: () {
                setState(() => _currentSort = SortOption.largestFirst);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.storage_rounded),
              title: const Text('Smallest Size First'),
              trailing: _currentSort == SortOption.smallestFirst ? const Icon(Icons.check, color: Color(0xFFDC2626)) : null,
              onTap: () {
                setState(() => _currentSort = SortOption.smallestFirst);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.hourglass_top_rounded),
              title: const Text('Longest Duration First'),
              trailing: _currentSort == SortOption.durationLongest ? const Icon(Icons.check, color: Color(0xFFDC2626)) : null,
              onTap: () {
                setState(() => _currentSort = SortOption.durationLongest);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.hourglass_bottom_rounded),
              title: const Text('Shortest Duration First'),
              trailing: _currentSort == SortOption.durationShortest ? const Icon(Icons.check, color: Color(0xFFDC2626)) : null,
              onTap: () {
                setState(() => _currentSort = SortOption.durationShortest);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (PreferencesService().biometricLock && !_authenticated) {
      return Scaffold(
        backgroundColor: colors.bg,
        drawer: const AppDrawer(currentRoute: 'recordings'),
        appBar: AppBar(
          backgroundColor: colors.surface,
          elevation: 0,
          title: Text('Recordings Library', style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: colors.textPrimary)),
          leading: Builder(
            builder: (ctx) => IconButton(
              icon: Icon(Icons.menu, color: colors.iconColor),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.fingerprint_rounded, size: 52, color: Color(0xFFDC2626)),
                ),
                const SizedBox(height: 24),
                Text(
                  'Recordings Locked',
                  style: GoogleFonts.manrope(fontSize: 22, fontWeight: FontWeight.w800, color: colors.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Biometric authentication or device passcode is required before accessing saved recordings.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.hankenGrotesk(fontSize: 14, color: colors.textSecondary),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.lock_open_rounded, size: 20),
                    label: Text('Unlock Recordings', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700)),
                    onPressed: _authenticate,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    MainWrapperScreen.navigateToTab(context, 0);
                  },
                  child: Text('Return to Home', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: colors.textSecondary)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.bg,
      drawer: const AppDrawer(currentRoute: 'recordings'),
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              decoration: BoxDecoration(
                color: colors.surface.withOpacity(0.95),
                border: Border(bottom: BorderSide(color: colors.borderLight)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.surfaceSecondary,
                        ),
                        child: Builder(
                          builder: (context) {
                            return IconButton(
                              icon: Icon(Icons.menu, color: colors.iconColor, size: 24),
                              onPressed: () {
                                Scaffold.of(context).openDrawer();
                              },
                            );
                          },
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text('My Recordings', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: colors.textPrimary, letterSpacing: -0.17)),
                            Text('$_allCount files • ${RecordingService().formatSize(_totalStorageBytes)}', style: TextStyle(fontSize: 11, color: colors.textSecondary, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.refresh_rounded, color: colors.iconColor, size: 22),
                        tooltip: 'Scan Disk',
                        onPressed: _scanDiskRecordings,
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Filter tabs
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip(MediaFilter.all, Icons.auto_awesome, 'ALL', '$_allCount'),
                        _buildFilterChip(MediaFilter.videos, Icons.videocam, 'Videos', '$_videoCount'),
                        _buildFilterChip(MediaFilter.screenshots, Icons.screenshot_monitor, 'Screenshots', '$_screenshotCount'),
                        _buildFilterChip(MediaFilter.gifs, Icons.gif_box, 'GIFs', '$_gifCount'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Search & controls
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(9999),
                            border: Border.all(color: colors.border),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.04), blurRadius: 4, offset: const Offset(0, 2))],
                          ),
                          child: TextField(
                            controller: _searchController,
                            style: TextStyle(color: colors.textPrimary),
                            decoration: InputDecoration(
                              hintText: 'Search recordings by filename...',
                              hintStyle: GoogleFonts.hankenGrotesk(fontSize: 12, color: colors.textSecondary),
                              prefixIcon: Icon(Icons.search, color: colors.textSecondary, size: 20),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(Icons.cancel, color: colors.textSecondary, size: 18),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onChanged: (v) => setState(() => _searchQuery = v),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildControlButton(
                        icon: Icons.swap_vert,
                        label: _getSortLabel(),
                        onTap: _showSortBottomSheet,
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(9999),
                          border: Border.all(color: colors.border),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.04), blurRadius: 4, offset: const Offset(0, 2))],
                        ),
                        child: Row(
                          children: [
                            _buildViewButton(Icons.grid_view, _viewMode == ViewMode.grid),
                            _buildViewButton(Icons.view_agenda, _viewMode == ViewMode.list),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Storage banner
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.border),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.04), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: colors.primaryBg, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.folder_special, color: Color(0xFFDC2626), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Local Storage Allocation', style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w700, color: colors.textPrimary)),
                        Text('${RecordingService().formatSize(_totalStorageBytes)} used by recordings', style: GoogleFonts.hankenGrotesk(fontSize: 11, color: colors.textSecondary)),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const StorageDataScreen()),
                      ).then((_) => _scanDiskRecordings());
                    },
                    child: Row(
                      children: [
                        Text('Manage', style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFFDC2626))),
                        const Icon(Icons.arrow_forward, size: 14, color: Color(0xFFDC2626)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Media Grid / List
            Expanded(
              child: _viewMode == ViewMode.grid ? _buildGridView() : _buildListView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(MediaFilter filter, IconData icon, String label, String count) {
    final isSelected = _selectedFilter == filter;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = filter),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFDC2626) : colors.surface,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(color: isSelected ? const Color(0xFFDC2626) : colors.border),
          boxShadow: isSelected ? [BoxShadow(color: const Color(0xFFDC2626).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))] : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : colors.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : colors.textPrimary)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withOpacity(0.2) : colors.surfaceSecondary,
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Text(count, style: GoogleFonts.jetBrainsMono(fontSize: 10, fontWeight: FontWeight.w700, color: isSelected ? Colors.white : colors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(color: colors.border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.04), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: colors.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w500, color: colors.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _buildViewButton(IconData icon, bool isSelected) {
    return GestureDetector(
      onTap: () => setState(() => _viewMode = icon == Icons.grid_view ? ViewMode.grid : ViewMode.list),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? colors.primaryBg : Colors.transparent,
        ),
        child: Icon(icon, size: 18, color: isSelected ? const Color(0xFFDC2626) : colors.textSecondary),
      ),
    );
  }

  Widget _buildEmptyState() {
    if (_searchQuery.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(shape: BoxShape.circle, color: colors.surfaceSecondary),
                child: Icon(Icons.search_off_rounded, size: 36, color: colors.textSecondary),
              ),
              const SizedBox(height: 16),
              Text(
                'No recordings found',
                style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.w600, color: colors.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                'No files match your search query "$_searchQuery".',
                textAlign: TextAlign.center,
                style: GoogleFonts.hankenGrotesk(fontSize: 13, color: colors.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                child: const Text('Clear Search'),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.surfaceSecondary,
              ),
              child: Icon(Icons.video_library_outlined, size: 36, color: colors.textSecondary),
            ),
            const SizedBox(height: 16),
            Text(
              'No recordings yet',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your recorded screen captures will appear here once saved.',
              textAlign: TextAlign.center,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridView() {
    if (_filteredItems.isEmpty) return _buildEmptyState();
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: _filteredItems.length,
      itemBuilder: (context, index) {
        final item = _filteredItems[index];
        return _MediaCard(
          item: item,
          onTap: () => _openPlayer(item),
          onRename: () => _renameItem(item),
          onDelete: () => _deleteItem(item),
          onShare: () => _shareItem(item),
        ).animate().fadeIn(duration: 300.ms, delay: (40 * index).ms).slideY(begin: 0.15, end: 0);
      },
    );
  }

  Widget _buildListView() {
    if (_filteredItems.isEmpty) return _buildEmptyState();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredItems.length,
      itemBuilder: (context, index) {
        final item = _filteredItems[index];
        return _MediaListItem(
          item: item,
          onTap: () => _openPlayer(item),
          onRename: () => _renameItem(item),
          onDelete: () => _deleteItem(item),
          onShare: () => _shareItem(item),
        ).animate().fadeIn(duration: 300.ms, delay: (40 * index).ms).slideX(begin: 0.15, end: 0);
      },
    );
  }

  void _openPlayer(MediaItem item) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => VideoPlayerScreen(item: item),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onShare;

  const _MediaCard({
    required this.item,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.04), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail / Icon container
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    child: _buildThumbnail(),
                  ),
                  // Gradient overlay
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withOpacity(0.8), Colors.black.withOpacity(0.3)],
                        ),
                      ),
                    ),
                  ),
                  // Duration badge
                  if (item.duration != null && item.type != 'screenshot')
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.75), borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          children: [
                            Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFDC2626))),
                            const SizedBox(width: 4),
                            Text(item.duration!, style: GoogleFonts.hankenGrotesk(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: 0.2)),
                          ],
                        ),
                      ),
                    ),
                  // Quality badge
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(8)),
                      child: Text(item.resolution, style: GoogleFonts.hankenGrotesk(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.white)),
                    ),
                  ),
                  // Cloud Synced badge
                  if (PreferencesService().isCloudSynced(item.filePath ?? item.title))
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.95),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cloud_done_rounded, size: 11, color: Colors.white),
                            SizedBox(width: 4),
                            Text('SYNCED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.2)),
                          ],
                        ),
                      ),
                    ),
                  // Screenshot badge
                  if (item.type == 'screenshot')
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(8)),
                        child: const Row(
                          children: [
                            Icon(Icons.photo, size: 11, color: Colors.white),
                            SizedBox(width: 4),
                            Text('PHOTO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  // Play button icon
                  if (item.type == 'video')
                    Positioned.fill(
                      child: Center(
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withOpacity(0.6)),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Metadata & 3-dot Menu
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, size: 18, color: colors.textTertiary),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onSelected: (val) {
                          if (val == 'rename') onRename();
                          if (val == 'share') onShare();
                          if (val == 'delete') onDelete();
                        },
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                            value: 'rename',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Rename'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'share',
                            child: Row(
                              children: [
                                Icon(Icons.share_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Share'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Delete', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('${item.date} • ${item.size}', style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w500, color: colors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    if (item.filePath != null && item.type == 'screenshot') {
      final f = File(item.filePath!);
      if (f.existsSync()) {
        return Image.file(f, width: double.infinity, height: double.infinity, fit: BoxFit.cover);
      }
    }
    if (item.thumbnail.isNotEmpty && !item.thumbnail.startsWith('http')) {
      final tf = File(item.thumbnail);
      if (tf.existsSync()) {
        return Image.file(tf, width: double.infinity, height: double.infinity, fit: BoxFit.cover);
      }
    }
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
      ),
      child: Center(
        child: Icon(
          item.type == 'screenshot' ? Icons.image_rounded : Icons.videocam_rounded,
          color: Colors.white30,
          size: 36,
        ),
      ),
    );
  }
}

class _MediaListItem extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onShare;

  const _MediaListItem({
    required this.item,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(colors.isDark ? 0.2 : 0.04), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 96,
                height: 54,
                child: Stack(
                  children: [
                    item.filePath != null && item.type == 'screenshot' && File(item.filePath!).existsSync()
                        ? Image.file(File(item.filePath!), width: 96, height: 54, fit: BoxFit.cover)
                        : (item.thumbnail.isNotEmpty && !item.thumbnail.startsWith('http') && File(item.thumbnail).existsSync()
                            ? Image.file(File(item.thumbnail), width: 96, height: 54, fit: BoxFit.cover)
                            : Container(
                                width: 96,
                                height: 54,
                                color: const Color(0xFF1E293B),
                                child: Icon(item.type == 'screenshot' ? Icons.image_rounded : Icons.videocam_rounded, color: Colors.white70, size: 24),
                              )),
                    if (item.duration != null && item.type != 'screenshot')
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.black.withOpacity(0.75), borderRadius: BorderRadius.circular(6)),
                          child: Text(item.duration!, style: GoogleFonts.hankenGrotesk(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, size: 18, color: colors.textTertiary),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onSelected: (val) {
                          if (val == 'rename') onRename();
                          if (val == 'share') onShare();
                          if (val == 'delete') onDelete();
                        },
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                            value: 'rename',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Rename'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'share',
                            child: Row(
                              children: [
                                Icon(Icons.share_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Share'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Delete', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text('${item.date} • ${item.size} • ${item.resolution}', style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w500, color: colors.textSecondary)),
                      ),
                      if (PreferencesService().isCloudSynced(item.filePath ?? item.title))
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cloud_done_rounded, size: 10, color: Color(0xFF10B981)),
                              SizedBox(width: 3),
                              Text('SYNCED', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFF10B981), letterSpacing: 0.2)),
                            ],
                          ),
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