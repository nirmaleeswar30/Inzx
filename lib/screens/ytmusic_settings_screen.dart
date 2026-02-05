import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/providers.dart';
import '../providers/repository_providers.dart';
import '../services/auth/google_auth_service.dart';
import '../services/ytmusic_sync_service.dart';
import 'ytmusic_login_screen.dart';
import 'audio_settings_screen.dart';

/// Provider for sync service
final ytMusicSyncServiceProvider = Provider<YTMusicSyncService>((ref) {
  final innerTube = ref.watch(innerTubeServiceProvider);
  return YTMusicSyncService(innerTube);
});

/// YT Music account & settings screen
class YTMusicSettingsScreen extends ConsumerStatefulWidget {
  const YTMusicSettingsScreen({super.key});

  @override
  ConsumerState<YTMusicSettingsScreen> createState() =>
      _YTMusicSettingsScreenState();
}

class _YTMusicSettingsScreenState extends ConsumerState<YTMusicSettingsScreen> {
  bool _isSyncing = false;
  SyncResult? _lastSyncResult;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authState = ref.watch(ytMusicAuthStateProvider);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        title: Text(
          'Settings',
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: authState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : authState.isLoggedIn
          ? _buildLoggedInView(isDark, authState)
          : _buildLoggedOutView(isDark),
    );
  }

  Widget _buildLoggedOutView(bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Google Account section (for profile & Jams - independent of YT Music)
        _buildGoogleAccountSection(isDark),

        const SizedBox(height: 32),

        // YT Music connection section
        Center(
          child: Column(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.red.shade600, Colors.red.shade800],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.music_note,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Connect YouTube Music',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sync your liked songs, playlists, and more',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _login,
                icon: const Icon(Icons.login, size: 18),
                label: const Text('Connect YT Music'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Audio & Downloads settings (also show when logged out)
        _buildAudioDownloadsSection(isDark),
      ],
    );
  }

  Widget _buildLoggedInView(bool isDark, YTMusicAuthState authState) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Google Account section (for profile & Jams)
        _buildGoogleAccountSection(isDark),

        const SizedBox(height: 24),

        // YT Music Account card
        _buildAccountCard(isDark, authState),

        const SizedBox(height: 24),

        // Audio & Downloads settings
        _buildAudioDownloadsSection(isDark),

        const SizedBox(height: 24),

        // Sync section
        _buildSyncSection(isDark),

        const SizedBox(height: 24),

        // Cache management
        _buildCacheSection(isDark),

        const SizedBox(height: 24),

        // Cache analytics
        _buildAnalyticsSection(isDark),

        const SizedBox(height: 24),

        // Library stats
        _buildLibraryStats(isDark),

        const SizedBox(height: 24),

        // Logout button
        _buildLogoutButton(isDark),
      ],
    );
  }

  /// Google Account section - for profile picture and Jams
  Widget _buildGoogleAccountSection(bool isDark) {
    final googleAuthState = ref.watch(googleAuthStateProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Iconsax.user,
                size: 20,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              const SizedBox(width: 8),
              Text(
                'Your Profile',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (googleAuthState.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (googleAuthState.isSignedIn && googleAuthState.user != null)
            _buildGoogleSignedInRow(isDark, googleAuthState.user!)
          else
            _buildGoogleSignInButton(isDark),
        ],
      ),
    );
  }

  Widget _buildGoogleSignedInRow(bool isDark, GoogleUserProfile user) {
    return Row(
      children: [
        // Profile picture
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: user.photoUrl == null
                ? LinearGradient(
                    colors: [Colors.blue.shade400, Colors.blue.shade700],
                  )
                : null,
          ),
          child: ClipOval(
            child: user.photoUrl != null
                ? CachedNetworkImage(
                    imageUrl: user.photoUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Center(
                      child: Text(
                        user.initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Center(
                      child: Text(
                        user.initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      user.initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 16),
        // User info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.displayName ?? 'Google User',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              if (user.email != null)
                Text(
                  user.email!,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                'Used for Jams & profile',
                style: TextStyle(fontSize: 11, color: Colors.blue.shade400),
              ),
            ],
          ),
        ),
        // Sign out button
        IconButton(
          onPressed: () async {
            await ref.read(googleAuthStateProvider.notifier).signOut();
          },
          icon: Icon(
            Iconsax.logout,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
          tooltip: 'Sign out',
        ),
      ],
    );
  }

  Widget _buildGoogleSignInButton(bool isDark) {
    return Column(
      children: [
        Text(
          'Sign in with Google to get your profile picture and enable Jams',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white60 : Colors.black54,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              await ref.read(googleAuthStateProvider.notifier).signIn();
            },
            icon: Image.network(
              'https://www.google.com/favicon.ico',
              width: 18,
              height: 18,
              errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 18),
            ),
            label: const Text('Sign in with Google'),
            style: OutlinedButton.styleFrom(
              foregroundColor: isDark ? Colors.white : Colors.black87,
              side: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAccountCard(bool isDark, YTMusicAuthState authState) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.red.shade600, Colors.red.shade800],
              ),
              shape: BoxShape.circle,
            ),
            child: authState.account?.avatarUrl != null
                ? ClipOval(
                    child: Image.network(
                      authState.account!.avatarUrl!,
                      fit: BoxFit.cover,
                    ),
                  )
                : const Icon(Icons.person, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  authState.account?.name ?? 'YouTube Music',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                if (authState.account?.email != null)
                  Text(
                    authState.account!.email!,
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Connected',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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

  Widget _buildAudioDownloadsSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Audio & Downloads',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Iconsax.music, color: Colors.blue),
            ),
            title: Text(
              'Streaming Quality',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            subtitle: Text(
              'Set audio quality for streaming',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AudioSettingsScreen()),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Iconsax.folder_2, color: Colors.orange),
            ),
            title: Text(
              'Download Location',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            subtitle: Text(
              'Choose where to save downloads',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AudioSettingsScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSyncSection(bool isDark) {
    final syncService = ref.watch(ytMusicSyncServiceProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sync',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 12),
          if (syncService.lastSync != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Last synced: ${_formatDate(syncService.lastSync!)}',
                style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
            ),
          if (_lastSyncResult != null && _lastSyncResult!.success)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Synced ${_lastSyncResult!.itemsSynced} items',
                        style: const TextStyle(color: Colors.green),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ElevatedButton.icon(
            onPressed: _isSyncing ? null : _sync,
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Iconsax.refresh),
            label: Text(_isSyncing ? 'Syncing...' : 'Sync Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCacheSection(bool isDark) {
    final cacheManager = ref.watch(cacheManagementProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cache Management',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder(
            future: cacheManager.getCacheStats(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                final stats = snapshot.data!;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Items: ${stats.totalItemCount}',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 8),
                      Wrap(
                        spacing: 16,
                        runSpacing: 4,
                        children: [
                          _cacheStatChip(
                            'Streams',
                            stats.streamUrlsCount,
                            isDark,
                          ),
                          _cacheStatChip('Home', stats.homePageCount, isDark),
                          _cacheStatChip('Lyrics', stats.lyricsCount, isDark),
                          _cacheStatChip('Albums', stats.albumsCount, isDark),
                          _cacheStatChip('Artists', stats.artistsCount, isDark),
                          _cacheStatChip(
                            'Playlists',
                            stats.playlistsCount,
                            isDark,
                          ),
                          _cacheStatChip('Colors', stats.colorsCount, isDark),
                          _cacheStatChip(
                            'Searches',
                            stats.cachedSearchesCount,
                            isDark,
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Expired: ${stats.expiredEntriesCount}',
                        style: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black38,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            },
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await cacheManager.cleanupExpiredCache();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Cache cleanup complete')),
                      );
                      setState(() {}); // Refresh cache stats
                    }
                  },
                  icon: const Icon(Iconsax.refresh),
                  label: const Text('Clean Up'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Clear Cache'),
                        content: const Text(
                          'This will clear all cached music data. Continue?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await cacheManager.clearAllCache();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Cache cleared')),
                        );
                        setState(() {});
                      }
                    }
                  },
                  icon: const Icon(Iconsax.trash),
                  label: const Text('Clear All'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsSection(bool isDark) {
    final analytics = ref.watch(cacheAnalyticsProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cache Analytics',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 12),
          _AnalyticsRow(
            label: 'Cache Hits',
            value: analytics.cacheHits.toString(),
            isDark: isDark,
          ),
          const SizedBox(height: 8),
          _AnalyticsRow(
            label: 'Cache Misses',
            value: analytics.cacheMisses.toString(),
            isDark: isDark,
          ),
          const SizedBox(height: 8),
          _AnalyticsRow(
            label: 'Hit Rate',
            value: '${analytics.hitRate.toStringAsFixed(1)}%',
            isDark: isDark,
            color: analytics.hitRate > 70 ? Colors.green : Colors.orange,
          ),
          const SizedBox(height: 8),
          _AnalyticsRow(
            label: 'Network Calls',
            value: analytics.networkCalls.toString(),
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              analytics.reset();
              setState(() {});
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Analytics reset')));
            },
            icon: const Icon(Iconsax.refresh),
            label: const Text('Reset Stats'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey.shade600,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryStats(bool isDark) {
    final likedSongs = ref.watch(ytMusicLikedSongsProvider);
    final savedAlbums = ref.watch(ytMusicSavedAlbumsProvider);
    final savedPlaylists = ref.watch(ytMusicSavedPlaylistsProvider);
    final subscribedArtists = ref.watch(ytMusicSubscribedArtistsProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Library',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          _buildStatRow(
            icon: Iconsax.heart,
            label: 'Liked Songs',
            value: likedSongs.when(
              data: (songs) => '${songs.length}',
              loading: () => '...',
              error: (_, __) => '-',
            ),
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          _buildStatRow(
            icon: Iconsax.music_square,
            label: 'Saved Albums',
            value: savedAlbums.when(
              data: (albums) => '${albums.length}',
              loading: () => '...',
              error: (_, __) => '-',
            ),
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          _buildStatRow(
            icon: Iconsax.music_playlist,
            label: 'Saved Playlists',
            value: savedPlaylists.when(
              data: (playlists) => '${playlists.length}',
              loading: () => '...',
              error: (_, __) => '-',
            ),
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          _buildStatRow(
            icon: Iconsax.user,
            label: 'Subscribed Artists',
            value: subscribedArtists.when(
              data: (artists) => '${artists.length}',
              loading: () => '...',
              error: (_, __) => '-',
            ),
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.red),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
      ],
    );
  }

  Widget _buildLogoutButton(bool isDark) {
    return OutlinedButton.icon(
      onPressed: _logout,
      icon: const Icon(Iconsax.logout, color: Colors.red),
      label: const Text('Disconnect YouTube Music'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.red,
        side: const BorderSide(color: Colors.red),
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }

  Future<void> _login() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => const YTMusicLoginScreen()),
    );

    if (result == true) {
      // Refresh all data
      ref.invalidate(ytMusicLikedSongsProvider);
      ref.invalidate(ytMusicSavedAlbumsProvider);
      ref.invalidate(ytMusicSavedPlaylistsProvider);
      ref.invalidate(ytMusicSubscribedArtistsProvider);
    }
  }

  Future<void> _sync() async {
    setState(() => _isSyncing = true);

    final syncService = ref.read(ytMusicSyncServiceProvider);
    final result = await syncService.syncAll();

    setState(() {
      _isSyncing = false;
      _lastSyncResult = result;
    });

    if (result.success) {
      // Refresh providers
      ref.invalidate(ytMusicLikedSongsProvider);
      ref.invalidate(ytMusicSavedAlbumsProvider);
      ref.invalidate(ytMusicSavedPlaylistsProvider);
      ref.invalidate(ytMusicSubscribedArtistsProvider);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed: ${result.error}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect YouTube Music?'),
        content: const Text(
          'This will remove your YouTube Music account from the app. Your library data will be cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(ytMusicAuthStateProvider.notifier).logout();
      await ref.read(ytMusicSyncServiceProvider).clearCache();
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes} minutes ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours} hours ago';
    } else {
      return '${diff.inDays} days ago';
    }
  }
}

/// Helper widget for displaying analytics metrics
class _AnalyticsRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;
  final Color? color;

  const _AnalyticsRow({
    required this.label,
    required this.value,
    required this.isDark,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black87,
            fontSize: 14,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color ?? (isDark ? Colors.white : Colors.black),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Helper widget for cache stat display
Widget _cacheStatChip(String label, int count, bool isDark) {
  return Text(
    '$label: $count',
    style: TextStyle(
      color: isDark ? Colors.white54 : Colors.black54,
      fontSize: 12,
    ),
  );
}
