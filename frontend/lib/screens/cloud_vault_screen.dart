import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/app_models.dart';
import '../services/theme_service.dart';
import '../services/preferences_service.dart';
import '../services/google_drive_backup_service.dart';
import '../services/recording_service.dart';
import 'video_player_screen.dart';

typedef BackupScreen = CloudVaultScreen;

enum VaultLiveStatus {
  waiting,
  uploading,
  synced,
  failed,
}

class VaultDisplayItem {
  final String id;
  final String title;
  final String? filePath;
  final String? thumbnail;
  final String formattedSize;
  final String formattedDate;
  final VaultLiveStatus status;
  final double progress;
  final CloudDriveFile? cloudFile;
  final MediaItem? mediaItem;
  final String? errorMessage;

  const VaultDisplayItem({
    required this.id,
    required this.title,
    this.filePath,
    this.thumbnail,
    required this.formattedSize,
    required this.formattedDate,
    required this.status,
    this.progress = 0.0,
    this.cloudFile,
    this.mediaItem,
    this.errorMessage,
  });
}

/// Cloud Vault & Backup screen managing Google Drive auto-sync,
/// silent sign-in, Wi-Fi toggles, and Drive recordings list.
class CloudVaultScreen extends StatefulWidget {
  const CloudVaultScreen({super.key});

  @override
  State<CloudVaultScreen> createState() => _CloudVaultScreenState();
}

class _CloudVaultScreenState extends State<CloudVaultScreen> {
  AppColors get colors => context.appColors;
  final PreferencesService _prefs = PreferencesService();
  final GoogleDriveBackupService _backupService = GoogleDriveBackupService();

  bool _autoSync = false;
  bool _wifiOnly = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _autoSync = _prefs.autoSync;
    _wifiOnly = _prefs.wifiOnly;
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    setState(() => _isLoading = true);
    await _backupService.init();
    if (mounted) {
      setState(() {
        _autoSync = _prefs.autoSync;
        _wifiOnly = _prefs.wifiOnly;
        _isLoading = false;
      });
    }
    if (_backupService.currentUser != null) {
      await _backupService.refreshCloudFiles();
    }
  }

  Future<void> _handleAutoSyncToggled(bool value) async {
    if (value) {
      final isAuth = await _backupService.ensureAuthorized(context: context);
      if (!mounted) return;

      if (!isAuth) {
        setState(() => _autoSync = false);
        return;
      }

      setState(() => _autoSync = true);
      await _prefs.setAutoSync(true);
      unawaited(_backupService.syncExistingRecordings());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Auto-sync enabled for ${_backupService.currentUser?.email}'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } else {
      setState(() => _autoSync = false);
      await _prefs.setAutoSync(false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Auto-sync paused. Account remembered.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleChangeAccount() async {
    final result = await _backupService.changeAccount(context: context);
    if (!mounted) return;

    if (result.status == SignInStatus.cancelled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign-in cancelled'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (result.status == SignInStatus.developerError || result.status == SignInStatus.error) {
      GoogleDriveBackupService.showErrorDialog(context, result);
      return;
    }

    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Switched to ${result.account?.email}'),
        backgroundColor: const Color(0xFF10B981),
      ),
    );
  }

  Future<void> _handleSyncNow() async {
    final isAuth = await _backupService.ensureAuthorized(context: context);
    if (!isAuth || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Checking and syncing recordings...'),
        duration: Duration(seconds: 2),
      ),
    );
    await _backupService.syncExistingRecordings();
    await _backupService.refreshCloudFiles();
  }

  Future<void> _retryUpload(VaultDisplayItem item) async {
    final filePath = item.filePath;
    if (filePath == null || (!kIsWeb && !File(filePath).existsSync())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Source recording file not found on device to retry.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Retrying upload for ${item.title}...'),
        duration: const Duration(seconds: 2),
      ),
    );
    final success = await _backupService.retryUpload(context, filePath, item.title);
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully uploaded ${item.title} to Google Drive!'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    }
  }

  List<VaultDisplayItem> _computeVaultItems({
    required List<CloudDriveFile> cloudFiles,
    required List<SyncingVideoItem> syncingItems,
    required List<MediaItem> localMedia,
  }) {
    final List<VaultDisplayItem> list = [];
    final Set<String> processedTitles = {};

    // 1. Process active syncing items (waiting, uploading, synced, failed)
    for (final syncItem in syncingItems) {
      processedTitles.add(syncItem.title);
      VaultLiveStatus st;
      if (syncItem.status == 'uploading') {
        st = VaultLiveStatus.uploading;
      } else if (syncItem.status == 'waiting') {
        st = VaultLiveStatus.waiting;
      } else if (syncItem.status == 'failed') {
        st = VaultLiveStatus.failed;
      } else {
        st = VaultLiveStatus.synced;
      }

      final localMatch = localMedia.cast<MediaItem?>().firstWhere(
        (m) => m?.title == syncItem.title || m?.filePath == syncItem.filePath,
        orElse: () => null,
      );

      final cloudMatch = cloudFiles.cast<CloudDriveFile?>().firstWhere(
        (cf) => cf?.name == syncItem.title,
        orElse: () => null,
      );

      list.add(
        VaultDisplayItem(
          id: 'sync_${syncItem.title.hashCode}',
          title: syncItem.title,
          filePath: syncItem.filePath,
          thumbnail: localMatch?.thumbnail,
          formattedSize: syncItem.formattedSize,
          formattedDate: localMatch?.date ?? 'Just now',
          status: st,
          progress: syncItem.progress,
          cloudFile: cloudMatch,
          mediaItem: localMatch,
          errorMessage: syncItem.errorMessage,
        ),
      );
    }

    // 2. Process local recordings
    for (final media in localMedia) {
      if (processedTitles.contains(media.title)) continue;
      processedTitles.add(media.title);

      final isSynced = _prefs.isCloudSynced(media.title) ||
          cloudFiles.any((cf) => cf.name == media.title);

      final cloudMatch = cloudFiles.cast<CloudDriveFile?>().firstWhere(
        (cf) => cf?.name == media.title,
        orElse: () => null,
      );

      VaultLiveStatus st;
      if (isSynced) {
        st = VaultLiveStatus.synced;
      } else if (_autoSync) {
        st = VaultLiveStatus.waiting;
      } else {
        st = VaultLiveStatus.waiting;
      }

      list.add(
        VaultDisplayItem(
          id: media.id,
          title: media.title,
          filePath: media.filePath,
          thumbnail: media.thumbnail,
          formattedSize: media.size,
          formattedDate: media.date,
          status: st,
          cloudFile: cloudMatch,
          mediaItem: media,
        ),
      );
    }

    // 3. Process any remaining cloud files from Google Drive
    for (final cf in cloudFiles) {
      if (processedTitles.contains(cf.name)) continue;
      processedTitles.add(cf.name);

      list.add(
        VaultDisplayItem(
          id: cf.id,
          title: cf.name,
          thumbnail: cf.thumbnailLink,
          formattedSize: cf.formattedSize,
          formattedDate: cf.formattedDate,
          status: VaultLiveStatus.synced,
          cloudFile: cf,
        ),
      );
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        title: Text(
          'Cloud Vault & Backup',
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.sync_rounded, color: colors.textPrimary),
            tooltip: 'Sync Now',
            onPressed: _handleSyncNow,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _backupService.refreshCloudFiles();
          if (_autoSync) {
            await _backupService.syncExistingRecordings();
          }
        },
        color: const Color(0xFFDC2626),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: [
            // ── 1. YouTube-style Account Row (at the very top when signed in) ──
            ValueListenableBuilder<AppGoogleUser?>(
              valueListenable: _backupService.accountNotifier,
              builder: (context, user, _) {
                if (user == null) return const SizedBox.shrink();
                return Column(
                  children: [
                    _buildGoogleProfileCard(user),
                    const SizedBox(height: 14),
                  ],
                );
              },
            ),

            // ── 2. Auto-Sync Toggle Card ──────────────────────────────────
            _buildAutoSyncCard(),

            const SizedBox(height: 14),

            // ── 3. Wi-Fi Only Toggle Card ─────────────────────────────────
            _buildWifiOnlyCard(),

            const SizedBox(height: 20),

            // ── 4. Cloud Vault Recordings Header ─────────────────────────
            Row(
              children: [
                Icon(Icons.cloud_done_rounded, size: 20, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  'Cloud Recordings',
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const Spacer(),
                ValueListenableBuilder<bool>(
                  valueListenable: _backupService.isSyncingNotifier,
                  builder: (context, syncing, _) {
                    if (!syncing) return const SizedBox.shrink();
                    return const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFDC2626),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Studio Capture Recordings folder in Google Drive',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),

            const SizedBox(height: 14),

            // ── 5. Unified Cloud Vault Recordings List ───────────────────
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFFDC2626)),
                ),
              )
            else
              ValueListenableBuilder<List<CloudDriveFile>>(
                valueListenable: _backupService.cloudFilesNotifier,
                builder: (context, cloudFiles, _) {
                  return ValueListenableBuilder<List<SyncingVideoItem>>(
                    valueListenable: _backupService.activeSyncingNotifier,
                    builder: (context, syncingItems, _) {
                      final localMedia = RecordingService().savedMediaItems;
                      final vaultItems = _computeVaultItems(
                        cloudFiles: cloudFiles,
                        syncingItems: syncingItems,
                        localMedia: localMedia,
                      );

                      if (vaultItems.isEmpty) {
                        return _buildEmptyState();
                      }

                      return Column(
                        children: vaultItems.map(_buildVaultItemCard).toList(),
                      );
                    },
                  );
                },
              ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoSyncCard() {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _autoSync ? const Color(0xFFDC2626).withValues(alpha: 0.3) : colors.border,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          activeColor: const Color(0xFFDC2626),
          title: Text(
            'Auto-Sync New Recordings',
            style: GoogleFonts.manrope(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Upload new recordings to "Studio Capture Recordings" in Drive in the background.',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 12.5,
                color: colors.textSecondary,
                height: 1.3,
              ),
            ),
          ),
          value: _autoSync,
          onChanged: _handleAutoSyncToggled,
        ),
      ),
    );
  }

  Widget _buildGoogleProfileCard(AppGoogleUser user) {
    final colorsList = [
      const Color(0xFF4285F4), // Google Blue
      const Color(0xFFEA4335), // Google Red
      const Color(0xFF34A853), // Google Green
      const Color(0xFFFBBC05), // Google Yellow
    ];
    final avatarColor = colorsList[user.email.hashCode.abs() % colorsList.length];
    final initial = user.displayName.isNotEmpty
        ? user.displayName[0].toUpperCase()
        : (user.email.isNotEmpty ? user.email[0].toUpperCase() : 'G');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF93C5FD).withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: avatarColor,
                    backgroundImage: user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
                    child: user.photoUrl == null
                        ? Text(
                            initial,
                            style: GoogleFonts.manrope(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                  Container(
                    width: 15,
                    height: 15,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        'G',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF4285F4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              // Name and Email
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 12.5,
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Action Buttons: Switch account & Turn off sync
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _handleChangeAccount,
                  icon: const Icon(Icons.switch_account_rounded, size: 16, color: Color(0xFF1E293B)),
                  label: Text(
                    'Switch account',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    side: BorderSide(color: _autoSync ? const Color(0xFFFECACA) : const Color(0xFFBBF7D0)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _handleAutoSyncToggled(!_autoSync),
                  icon: Icon(
                    _autoSync ? Icons.sync_disabled_rounded : Icons.sync_rounded,
                    size: 16,
                    color: _autoSync ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                  ),
                  label: Text(
                    _autoSync ? 'Turn off sync' : 'Turn on sync',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _autoSync ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surfaceSecondary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_shared_rounded, size: 16, color: Color(0xFF0284C7)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Folder: Studio Capture Recordings in Drive',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0284C7),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWifiOnlyCard() {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          activeColor: const Color(0xFFDC2626),
          title: Text(
            'Backup via Wi-Fi Only',
            style: GoogleFonts.manrope(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          subtitle: Text(
            'Prevents uploading when connected to cellular data',
            style: GoogleFonts.hankenGrotesk(
              fontSize: 12,
              color: colors.textSecondary,
            ),
          ),
          value: _wifiOnly,
          onChanged: (val) async {
            setState(() => _wifiOnly = val);
            await _backupService.setWifiOnly(val);
          },
        ),
      ),
    );
  }

  Widget _buildVaultItemCard(VaultDisplayItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: item.status == VaultLiveStatus.failed
              ? const Color(0xFFFECACA)
              : item.status == VaultLiveStatus.uploading
                  ? const Color(0xFFBAE6FD)
                  : colors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Play preview / Thumbnail
              InkWell(
                onTap: () => _playVaultItem(item),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 54,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.surfaceSecondary,
                    borderRadius: BorderRadius.circular(10),
                    image: item.thumbnail != null && item.thumbnail!.isNotEmpty
                        ? DecorationImage(
                            image: (item.thumbnail!.startsWith('http')
                                ? NetworkImage(item.thumbnail!)
                                : FileImage(File(item.thumbnail!))) as ImageProvider,
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: Center(
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Name and Metadata
              Expanded(
                child: InkWell(
                  onTap: () => _playVaultItem(item),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          _buildStatusBadge(item),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${item.formattedSize} • ${item.formattedDate}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 11.5,
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Retry button if failed
              if (item.status == VaultLiveStatus.failed) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFDC2626)),
                    foregroundColor: const Color(0xFFDC2626),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _retryUpload(item),
                  icon: const Icon(Icons.refresh_rounded, size: 14),
                  label: Text(
                    'Retry',
                    style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              // 3-dot popup menu
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: colors.textSecondary, size: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                color: colors.surface,
                onSelected: (val) {
                  if (val == 'download') {
                    _downloadVaultItem(item);
                  } else if (val == 'copy_link') {
                    _copyCloudLink(item);
                  } else if (val == 'details') {
                    _backupService.showErrorDetailsDialog(context);
                  } else if (val == 'delete') {
                    _confirmDeleteVaultItem(item);
                  }
                },
                itemBuilder: (ctx) => [
                  if (item.status == VaultLiveStatus.failed)
                    PopupMenuItem(
                      value: 'details',
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 18, color: colors.textPrimary),
                          const SizedBox(width: 10),
                          Text(
                            'Copy Error Details',
                            style: GoogleFonts.hankenGrotesk(fontSize: 13, color: colors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'download',
                    child: Row(
                      children: [
                        Icon(Icons.download_rounded, size: 18, color: colors.textPrimary),
                        const SizedBox(width: 10),
                        Text(
                          'Download to Device',
                          style: GoogleFonts.hankenGrotesk(fontSize: 13, color: colors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'copy_link',
                    child: Row(
                      children: [
                        Icon(Icons.link_rounded, size: 18, color: colors.textPrimary),
                        const SizedBox(width: 10),
                        Text(
                          'Copy Cloud Link',
                          style: GoogleFonts.hankenGrotesk(fontSize: 13, color: colors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFDC2626)),
                        const SizedBox(width: 10),
                        Text(
                          'Delete from Cloud',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 13,
                            color: const Color(0xFFDC2626),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (item.status == VaultLiveStatus.failed && item.errorMessage != null && item.errorMessage!.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _backupService.showErrorDetailsDialog(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 14, color: Color(0xFFDC2626)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.errorMessage!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.hankenGrotesk(fontSize: 11.5, color: const Color(0xFF991B1B)),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Details',
                      style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFFDC2626)),
                    ),
                    const Icon(Icons.chevron_right_rounded, size: 14, color: Color(0xFFDC2626)),
                  ],
                ),
              ),
            ),
          ],
          if (item.status == VaultLiveStatus.uploading) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: item.progress > 0 ? item.progress : null,
                minHeight: 4,
                backgroundColor: const Color(0xFFE0F2FE),
                color: const Color(0xFF0284C7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge(VaultDisplayItem item) {
    switch (item.status) {
      case VaultLiveStatus.uploading:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
          decoration: BoxDecoration(
            color: const Color(0xFFE0F2FE),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 8,
                height: 8,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF0284C7)),
              ),
              const SizedBox(width: 4),
              Text(
                'Uploading ${(item.progress * 100).toInt()}%',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0284C7),
                ),
              ),
            ],
          ),
        );

      case VaultLiveStatus.waiting:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.access_time_rounded, size: 10, color: Color(0xFFD97706)),
              const SizedBox(width: 3),
              Text(
                'Waiting',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFD97706),
                ),
              ),
            ],
          ),
        );

      case VaultLiveStatus.failed:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
          decoration: BoxDecoration(
            color: const Color(0xFFFEE2E2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 10, color: Color(0xFFDC2626)),
              const SizedBox(width: 3),
              Text(
                'Failed',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFDC2626),
                ),
              ),
            ],
          ),
        );

      case VaultLiveStatus.synced:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
          decoration: BoxDecoration(
            color: const Color(0xFFDCFCE7),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_rounded, size: 11, color: Color(0xFF16A34A)),
              const SizedBox(width: 2),
              Text(
                'Synced',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF16A34A),
                ),
              ),
            ],
          ),
        );
    }
  }

  void _playVaultItem(VaultDisplayItem item) {
    if (item.mediaItem != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(item: item.mediaItem!),
        ),
      );
      return;
    }

    if (item.cloudFile != null) {
      _playCloudFile(item.cloudFile!);
      return;
    }

    if (item.filePath != null) {
      final playable = MediaItem(
        id: item.id,
        title: item.title,
        type: 'video',
        thumbnail: item.thumbnail ?? '',
        duration: '00:00',
        resolution: '1080p',
        date: item.formattedDate,
        size: item.formattedSize,
        filePath: item.filePath,
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(item: playable),
        ),
      );
    }
  }

  Future<void> _playCloudFile(CloudDriveFile file) async {
    final localMatch = RecordingService().savedMediaItems.cast<MediaItem?>().firstWhere(
          (m) => m?.title == file.name,
          orElse: () => null,
        );
    if (localMatch != null && localMatch.filePath != null && !kIsWeb && File(localMatch.filePath!).existsSync()) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(item: localMatch),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Buffering ${file.name} from Google Drive...'),
        duration: const Duration(seconds: 2),
      ),
    );

    final cachedPath = await _backupService.cacheCloudFileForPlayback(file);
    if (!mounted) return;
    if (cachedPath != null && File(cachedPath).existsSync()) {
      final item = MediaItem(
        id: file.id,
        title: file.name,
        type: 'video',
        thumbnail: file.thumbnailLink ?? '',
        duration: '00:00',
        resolution: '1080p',
        date: file.formattedDate,
        size: file.formattedSize,
        filePath: cachedPath,
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(item: item),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not stream video from Google Drive.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
    }
  }

  Future<void> _downloadVaultItem(VaultDisplayItem item) async {
    if (item.filePath != null && !kIsWeb && File(item.filePath!).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Video already exists on device in Movies/Studio Capture!'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
      return;
    }

    if (item.cloudFile != null) {
      await _downloadFile(item.cloudFile!);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No cloud file available for download.')),
      );
    }
  }

  Future<void> _downloadFile(CloudDriveFile file) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Downloading ${file.name}...'),
        duration: const Duration(seconds: 2),
      ),
    );
    final savedPath = await _backupService.downloadCloudFile(file);
    if (!mounted) return;
    if (savedPath != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Downloaded to Movies/Studio Capture gallery!'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to download video from Drive'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
    }
  }

  void _copyCloudLink(VaultDisplayItem item) {
    final link = item.cloudFile?.webViewLink ??
        (item.cloudFile != null ? 'https://drive.google.com/file/d/${item.cloudFile!.id}/view' : null);

    if (link != null) {
      Clipboard.setData(ClipboardData(text: link));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cloud link copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cloud link will be available once video finishes syncing.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _confirmDeleteVaultItem(VaultDisplayItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete from Cloud?',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: colors.textPrimary),
        ),
        content: Text(
          'Are you sure you want to permanently delete "${item.title}" from Google Drive?',
          style: GoogleFonts.hankenGrotesk(fontSize: 14, color: colors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.hankenGrotesk(color: colors.textSecondary, fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final fileId = item.cloudFile?.id ?? item.id;
              final success = await _backupService.deleteCloudFile(fileId, item.title);
              if (!mounted) return;
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Deleted from Google Drive'),
                    backgroundColor: Color(0xFF10B981),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to delete from Google Drive'),
                    backgroundColor: Color(0xFFDC2626),
                  ),
                );
              }
            },
            child: Text(
              'Delete',
              style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceSecondary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.cloud_upload_outlined,
              size: 38,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _backupService.currentUser == null ? 'Sign In to View Cloud Recordings' : 'No Recordings Found',
            style: GoogleFonts.manrope(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _backupService.currentUser == null
                ? 'Turn ON "Auto-Sync New Recordings" above to select your Google account and upload recordings.'
                : 'Turn ON Auto-Sync or tap the sync icon above to upload your recordings to Google Drive.',
            textAlign: TextAlign.center,
            style: GoogleFonts.hankenGrotesk(
              fontSize: 12.5,
              color: colors.textSecondary,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
