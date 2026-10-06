import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_models.dart';
import '../providers/app_providers.dart';
import '../utils/theme.dart';
import '../widgets/bottom_nav_bar.dart';

class MediaLibraryScreen extends ConsumerStatefulWidget {
  const MediaLibraryScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<MediaLibraryScreen> createState() => _MediaLibraryScreenState();
}

class _MediaLibraryScreenState extends ConsumerState<MediaLibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaItems = ref.watch(mediaItemsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const CustomBottomNavBar(),
      appBar: AppBar(
        title: const Text('My Recordings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Videos'),
            Tab(text: 'Screenshots'),
            Tab(text: 'GIFs'),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              children: [
                // Search Bar & Storage allocation bar
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Search Box
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search recordings...',
                          prefixIcon: const Icon(Icons.search_rounded, color: Colors.grey),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Storage Allocation Bar
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Storage Used', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                Text('580 MB / 64 GB', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: const LinearProgressIndicator(
                                value: 0.15,
                                backgroundColor: Color(0xFFF1F5F9),
                                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                                minHeight: 6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Media Grid
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: mediaItems.length,
                    itemBuilder: (context, index) {
                      final item = mediaItems[index];
                      return _buildMediaGridCard(context, item);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaGridCard(BuildContext context, MediaItem item) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pushNamed('/video-player');
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail Box
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade800,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Icon(Icons.movie_rounded, size: 40, color: Colors.white.withOpacity(0.5)),
                    ),
                    Center(
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.white.withOpacity(0.9),
                        child: const Icon(Icons.play_arrow_rounded, color: AppColors.primary, size: 20),
                      ),
                    ),
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.duration,
                          style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.resolution} • ${item.fileSize}',
                    style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
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
