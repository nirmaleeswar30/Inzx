import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inzx/data/repositories/music_repository.dart';
import 'package:inzx/data/sources/music_local_source.dart';
import 'package:inzx/data/sources/music_remote_source.dart';
import 'package:inzx/services/cache_warming_service.dart';
import 'package:inzx/providers/providers.dart';

export 'package:inzx/data/repositories/music_repository.dart'
    show CacheAnalytics;

/// Provides MusicLocalSource singleton
final musicLocalSourceProvider = Provider<MusicLocalSource>((ref) {
  return MusicLocalSource();
});

/// Provides MusicRemoteSource singleton
final musicRemoteSourceProvider = Provider<MusicRemoteSource>((ref) {
  final innerTube = ref.watch(innerTubeServiceProvider);
  final ytMusic = ref.watch(youtubeServiceProvider);
  final authService = ref.watch(ytMusicAuthServiceProvider);

  return MusicRemoteSource(
    innerTube: innerTube,
    ytMusic: ytMusic,
    authService: authService,
  );
});

/// Provides MusicRepository singleton
/// This is the main entry point for all music business logic
final musicRepositoryProvider = Provider<MusicRepository>((ref) {
  final localSource = ref.watch(musicLocalSourceProvider);
  final remoteSource = ref.watch(musicRemoteSourceProvider);

  return MusicRepository(localSource: localSource, remoteSource: remoteSource);
});

/// Provides CacheWarmingService for pre-loading cache on startup
final cacheWarmingServiceProvider = Provider<CacheWarmingService>((ref) {
  final repository = ref.watch(musicRepositoryProvider);
  return CacheWarmingService(repository);
});

/// Provides cache analytics for UI display with reactive updates
final cacheAnalyticsProvider = ChangeNotifierProvider<CacheAnalytics>((ref) {
  final repository = ref.watch(musicRepositoryProvider);
  return repository.analytics;
});
