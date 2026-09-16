import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:iconsax/iconsax.dart';
import 'package:marquee/marquee.dart';
import '../core/l10n/app_localizations_x.dart';
import '../core/design_system/design_system.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../services/search_service.dart';
import '../services/download_service.dart';
import '../services/local_music_scanner.dart';
import 'widgets/playlist_screen.dart';
import 'widgets/podcast_screen.dart';
import 'widgets/album_screen.dart' hide albumColorsProvider;
import 'widgets/artist_screen.dart';
import 'widgets/now_playing_screen.dart';
import 'widgets/track_options_sheet.dart';
import 'widgets/explicit_badge.dart';

// ============ PROVIDERS ============

/// Search service provider
final searchServiceProvider = Provider<SearchService>((ref) {
  final innerTube = ref.watch(innerTubeServiceProvider);
  return SearchService(innerTube);
});

/// Current search filter
final searchFilterProvider = StateProvider<SearchFilter>(
  (ref) => SearchFilter.all,
);

/// Enhanced search results provider with local + online merge
/// Uses proper debouncing and lets YouTube handle intent detection
final enhancedSearchProvider =
    FutureProvider.autoDispose<EnhancedSearchResults>((ref) async {
      final query = ref.watch(searchQueryProvider);
      final filter = ref.watch(searchFilterProvider);

      if (query.trim().isEmpty) {
        return EnhancedSearchResults.empty('');
      }

      // Debounce: 300ms delay before searching
      await Future.delayed(const Duration(milliseconds: 300));

      if (ref.read(searchQueryProvider) != query) {
        throw Exception('Query changed');
      }

      final downloadedTracks =
          ref.read(downloadedTracksProvider).valueOrNull ?? [];
      final localTracks = ref.read(localTracksProvider);
      final allLocalTracks = [...downloadedTracks, ...localTracks];

      final searchService = ref.read(searchServiceProvider);
      return searchService.search(
        query,
        filter: filter,
        localLibrary: allLocalTracks.isNotEmpty ? allLocalTracks : null,
      );
    });

/// Search suggestions provider with debouncing
final searchSuggestionsEnhancedProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
      final query = ref.watch(searchQueryProvider);

      if (query.trim().length < 2) return [];

      await Future.delayed(const Duration(milliseconds: 150));

      if (ref.read(searchQueryProvider) != query) {
        throw Exception('Query changed');
      }

      final searchService = ref.read(searchServiceProvider);
      return searchService.getSuggestions(query);
    });

// ============ SEARCH SCREEN ============

/// Glassmorphic dynamic Search screen
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _debounceTimer;

  late final AnimationController _headerAnimationController;
  late final Animation<double> _headerAnimation;
  bool _isHeaderVisible = true;
  double _accumulatedDelta = 0.0;
  static const double _hideThreshold = 25.0;
  static const double _showThreshold = 20.0;

  @override
  void initState() {
    super.initState();
    _headerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1.0,
    );
    _headerAnimation = CurvedAnimation(
      parent: _headerAnimationController,
      curve: Curves.easeInOutCubic,
    );

    _searchFocusNode.addListener(_onFocusChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(searchQueryProvider.notifier).state = '';
      ref.read(searchFilterProvider.notifier).state = SearchFilter.all;
      _searchFocusNode.requestFocus();
    });
  }

  void _onFocusChange() {
    if (_searchFocusNode.hasFocus && !_isHeaderVisible) {
      _isHeaderVisible = true;
      _headerAnimationController.forward();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchFocusNode.removeListener(_onFocusChange);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _headerAnimationController.dispose();
    super.dispose();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    if (notification is ScrollUpdateNotification && notification.depth == 0) {
      final metrics = notification.metrics;
      final delta = notification.scrollDelta;
      if (delta == null) return false;

      // When near or at top, always reveal search bar
      if (metrics.pixels <= 10.0) {
        if (!_isHeaderVisible) {
          _isHeaderVisible = true;
          _headerAnimationController.forward();
        }
        _accumulatedDelta = 0.0;
        return false;
      }

      // Avoid toggling when overscrolling past bottom extent
      if (metrics.pixels > metrics.maxScrollExtent) return false;

      if (delta > 0) {
        // Scrolling DOWN
        if (_accumulatedDelta < 0) _accumulatedDelta = 0;
        _accumulatedDelta += delta;
        if (_accumulatedDelta > _hideThreshold && _isHeaderVisible) {
          // If keyboard is open, unfocus so results get full screen space
          if (_searchFocusNode.hasFocus) {
            _searchFocusNode.unfocus();
          }
          _isHeaderVisible = false;
          _headerAnimationController.reverse();
          _accumulatedDelta = 0;
        }
      } else if (delta < 0) {
        // Scrolling UP
        if (_accumulatedDelta > 0) _accumulatedDelta = 0;
        _accumulatedDelta += delta;
        if (_accumulatedDelta < -_showThreshold && !_isHeaderVisible) {
          _isHeaderVisible = true;
          _headerAnimationController.forward();
          _accumulatedDelta = 0;
        }
      }
    }
    return false;
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    ref.read(searchQueryProvider.notifier).state = query;
  }

  void _performSearch(String query) {
    if (query.trim().isEmpty) return;
    _searchController.text = query;
    ref.read(searchQueryProvider.notifier).state = query;
    ref.read(searchHistoryProvider.notifier).addSearch(query.trim());
    _searchFocusNode.unfocus();
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(searchQueryProvider.notifier).state = '';
    ref.read(searchFilterProvider.notifier).state = SearchFilter.all;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final query = ref.watch(searchQueryProvider);

    final albumColors = ref.watch(albumColorsProvider);
    final hasAlbumColors = !albumColors.isDefault;
    final accentColor = isDark
        ? (hasAlbumColors ? albumColors.accentLight : colorScheme.primary)
        : (hasAlbumColors ? albumColors.accent : colorScheme.primary);

    final backgroundColor = isDark
        ? (hasAlbumColors
              ? albumColors.backgroundSecondary
              : InzxColors.darkBackground)
        : InzxColors.background;

    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = textColor.withValues(alpha: 0.6);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          // Ambient dynamic top gradient
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 220,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    accentColor.withValues(alpha: isDark ? 0.30 : 0.15),
                    accentColor.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: Column(
                children: [
                  ClipRect(
                    child: SizeTransition(
                      sizeFactor: _headerAnimation,
                      alignment: Alignment.topCenter,
                      child: FadeTransition(
                        opacity: _headerAnimation,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildSearchBar(isDark, accentColor, textColor, secondaryTextColor),
                            if (query.isNotEmpty)
                              _buildFilterChips(isDark, accentColor, textColor, secondaryTextColor),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: query.isEmpty
                        ? _buildSuggestionsOrHistory(isDark, accentColor, textColor, secondaryTextColor)
                        : _buildSearchResults(isDark, accentColor, textColor, secondaryTextColor, colorScheme),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(
    bool isDark,
    Color accentColor,
    Color textColor,
    Color secondaryTextColor,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          BouncyTouch(
            style: BouncyStyle.button,
            customScale: 0.90,
            onTap: () => Navigator.of(context).pop(),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Icon(
                Icons.arrow_back_rounded,
                color: textColor,
                size: 24,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.16)
                          : Colors.black.withValues(alpha: 0.12),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Iconsax.search_normal,
                        size: 18,
                        color: isDark ? Colors.white70 : InzxColors.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onChanged: _onSearchChanged,
                          onSubmitted: _performSearch,
                          cursorColor: accentColor,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            filled: false,
                            fillColor: Colors.transparent,
                            hintText: context.l10n.searchMusicHint,
                            hintStyle: TextStyle(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.62)
                                  : Colors.black.withValues(alpha: 0.48),
                              fontSize: 15,
                            ),
                            border: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      if (_searchController.text.isNotEmpty)
                        BouncyTouch(
                          style: BouncyStyle.button,
                          customScale: 0.85,
                          onTap: _clearSearch,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: textColor.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: textColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(
    bool isDark,
    Color accentColor,
    Color textColor,
    Color secondaryTextColor,
  ) {
    final currentFilter = ref.watch(searchFilterProvider);

    final filters = [
      (SearchFilter.all, context.l10n.all),
      (SearchFilter.songs, context.l10n.songs),
      (SearchFilter.albums, context.l10n.albums),
      (SearchFilter.artists, context.l10n.artists),
      (SearchFilter.playlists, context.l10n.playlists),
      (SearchFilter.podcasts, 'Podcasts'),
    ];

    return SizedBox(
      height: 42,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final (filter, label) = filters[index];
          final isSelected = currentFilter == filter;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: BouncyTouch(
              style: BouncyStyle.button,
              customScale: 0.92,
              onTap: () {
                ref.read(searchFilterProvider.notifier).state = filter;
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? accentColor.withValues(alpha: 0.22)
                      : textColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? accentColor.withValues(alpha: 0.60)
                        : Colors.transparent,
                    width: 1.0,
                  ),
                ),
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? accentColor : secondaryTextColor,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSuggestionsOrHistory(
    bool isDark,
    Color accentColor,
    Color textColor,
    Color secondaryTextColor,
  ) {
    final history = ref.watch(searchHistoryProvider);
    final suggestionsAsync = ref.watch(searchSuggestionsEnhancedProvider);

    if (_searchController.text.trim().length >= 2) {
      return suggestionsAsync.when(
        data: (suggestions) {
          if (suggestions.isEmpty) {
            return _buildEmptyState(
              context.l10n.searchForMusic,
              Iconsax.search_normal,
              textColor,
              secondaryTextColor,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: suggestions.length,
            itemBuilder: (context, index) {
              return ListTile(
                leading: Icon(
                  Iconsax.search_normal_1,
                  size: 18,
                  color: secondaryTextColor,
                ),
                title: Text(
                  suggestions[index],
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                trailing: IconButton(
                  onPressed: () {
                    _searchController.text = suggestions[index];
                    _searchController.selection = TextSelection.fromPosition(
                      TextPosition(offset: suggestions[index].length),
                    );
                    _onSearchChanged(suggestions[index]);
                  },
                  icon: Icon(
                    Icons.north_west_rounded,
                    size: 18,
                    color: secondaryTextColor,
                  ),
                ),
                onTap: () => _performSearch(suggestions[index]),
              );
            },
          );
        },
        loading: () => Skeletonizer(
          enabled: true,
          enableSwitchAnimation: true,
          child: ListView(
            padding: EdgeInsets.zero,
            children: List.generate(6, (index) => ListTile(
              leading: const Icon(Icons.search),
              title: Text(BoneMock.words(3)),
            )),
          ),
        ),
        error: (_, _) => _buildEmptyState(
          context.l10n.searchForMusic,
          Iconsax.search_normal,
          textColor,
          secondaryTextColor,
        ),
      );
    }

    if (history.isEmpty) {
      return _buildEmptyState(
        context.l10n.searchForMusic,
        Iconsax.search_favorite,
        textColor,
        secondaryTextColor,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.l10n.recentSearches,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: textColor,
                ),
              ),
              TextButton(
                onPressed: () {
                  ref.read(searchHistoryProvider.notifier).clearHistory();
                },
                child: Text(
                  context.l10n.clearAll,
                  style: TextStyle(color: accentColor, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: history.length,
            itemBuilder: (context, index) {
              final query = history[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: BouncyTouch(
                  style: BouncyStyle.card,
                  customScale: 0.98,
                  onTap: () => _performSearch(query),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: textColor.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(Iconsax.clock, size: 18, color: secondaryTextColor),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            query,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded, size: 18, color: secondaryTextColor),
                          onPressed: () {
                            ref
                                .read(searchHistoryProvider.notifier)
                                .removeSearch(query);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResults(
    bool isDark,
    Color accentColor,
    Color textColor,
    Color secondaryTextColor,
    ColorScheme colorScheme,
  ) {
    final resultsAsync = ref.watch(enhancedSearchProvider);
    final filter = ref.watch(searchFilterProvider);

    return resultsAsync.when(
      data: (results) {
        if (results.isEmpty) {
          return _buildEmptyState(
            context.l10n.noResultsFound,
            Iconsax.search_status,
            textColor,
            secondaryTextColor,
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            // Local results section (if any)
            if (results.localTracks.isNotEmpty && filter == SearchFilter.all)
              _buildLocalResultsSection(
                results.localTracks,
                accentColor,
                textColor,
                secondaryTextColor,
                colorScheme,
              ),

            // HERO TOP RESULT (YouTube Music Best Result)
            if (results.topResult != null && filter == SearchFilter.all)
              _buildTopResult(results.topResult!, accentColor, textColor, secondaryTextColor, colorScheme),

            // Songs section
            if ((filter == SearchFilter.all || filter == SearchFilter.songs) &&
                results.onlineTracks.isNotEmpty)
              _buildSongsSection(
                results.onlineTracks,
                accentColor,
                textColor,
                secondaryTextColor,
                colorScheme,
                filter,
              ),

            // Artists section
            if ((filter == SearchFilter.all || filter == SearchFilter.artists) &&
                results.onlineArtists.isNotEmpty)
              _buildArtistsSection(
                results.onlineArtists,
                accentColor,
                textColor,
                secondaryTextColor,
                colorScheme,
                filter,
              ),

            // Albums section
            if ((filter == SearchFilter.all || filter == SearchFilter.albums) &&
                results.onlineAlbums.isNotEmpty)
              _buildAlbumsSection(
                results.onlineAlbums,
                accentColor,
                textColor,
                secondaryTextColor,
                colorScheme,
                filter,
              ),

            // Playlists section
            if ((filter == SearchFilter.all || filter == SearchFilter.playlists) &&
                results.onlinePlaylists.isNotEmpty)
              _buildPlaylistsSection(
                results.onlinePlaylists,
                accentColor,
                textColor,
                secondaryTextColor,
                colorScheme,
                filter,
              ),

            // Podcasts section
            if ((filter == SearchFilter.all || filter == SearchFilter.podcasts) &&
                results.onlinePodcasts.isNotEmpty)
              _buildPodcastsSection(
                results.onlinePodcasts,
                accentColor,
                textColor,
                secondaryTextColor,
                colorScheme,
                filter,
              ),
          ],
        );
      },
      loading: () => Skeletonizer(
        enabled: true,
        enableSwitchAnimation: true,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Fake top result card
            Padding(
              padding: const EdgeInsets.all(16),
              child: ListTile(
                leading: Skeleton.replace(
                  width: 56,
                  height: 56,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                title: Text(BoneMock.name),
                subtitle: Text(BoneMock.words(2)),
              ),
            ),
            // Fake track results
            ...List.generate(5, (index) => ListTile(
              leading: Skeleton.replace(
                width: 48,
                height: 48,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              title: Text(BoneMock.name),
              subtitle: Text(BoneMock.words(2)),
              trailing: const Icon(Icons.more_vert),
            )),
          ],
        ),
      ),
      error: (e, _) {
        if (e.toString().contains('Query changed')) {
          return Skeletonizer(
            enabled: true,
            enableSwitchAnimation: true,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Fake top result card
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ListTile(
                    leading: Skeleton.replace(
                      width: 56,
                      height: 56,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    title: Text(BoneMock.name),
                    subtitle: Text(BoneMock.words(2)),
                  ),
                ),
                // Fake track results
                ...List.generate(5, (index) => ListTile(
                  leading: Skeleton.replace(
                    width: 48,
                    height: 48,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  title: Text(BoneMock.name),
                  subtitle: Text(BoneMock.words(2)),
                  trailing: const Icon(Icons.more_vert),
                )),
              ],
            ),
          );
        }
        return _buildEmptyState(
          context.l10n.noResultsFound,
          Iconsax.search_status,
          textColor,
          secondaryTextColor,
        );
      },
    );
  }

  Widget _buildEmptyState(
    String message,
    IconData icon,
    Color textColor,
    Color secondaryTextColor,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: secondaryTextColor.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: secondaryTextColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalResultsSection(
    List<Track> tracks,
    Color accentColor,
    Color textColor,
    Color secondaryTextColor,
    ColorScheme colorScheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Icon(Iconsax.folder_connection, size: 20, color: accentColor),
              const SizedBox(width: 8),
              Text(
                context.l10n.downloadedSection,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
        ...tracks.take(3).map(
              (track) => _buildTrackTile(track, accentColor, textColor, secondaryTextColor, colorScheme),
            ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// REDESIGNED HERO TOP RESULT CARD
  Widget _buildTopResult(
    TopResult topResult,
    Color accentColor,
    Color textColor,
    Color secondaryTextColor,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.45),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Iconsax.star5, size: 14, color: accentColor),
                    const SizedBox(width: 6),
                    Text(
                      context.l10n.topResult.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: accentColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildTopResultCard(topResult, accentColor, textColor, secondaryTextColor, colorScheme),
        ],
      ),
    );
  }

  Widget _buildTopResultCard(
    TopResult topResult,
    Color accentColor,
    Color textColor,
    Color secondaryTextColor,
    ColorScheme colorScheme,
  ) {
    Widget imageWidget;
    String title;
    String subtitle;
    VoidCallback onTap;
    IconData actionIcon;

    switch (topResult.type) {
      case SearchResultType.artist:
        final artist = topResult.artist!;
        title = artist.name;
        subtitle = context.artistSubtitle(artist.formattedSubscribers);
        actionIcon = Icons.chevron_right_rounded;
        onTap = () => ArtistScreen.open(
          context,
          artistId: artist.id,
          name: artist.name,
          thumbnailUrl: artist.thumbnailUrl,
        );
        imageWidget = ClipOval(
          child: _buildImage(artist.thumbnailUrl, 76, Icons.person_rounded),
        );
        break;

      case SearchResultType.track:
        final track = topResult.track!;
        title = track.title;
        subtitle = context.trackSubtitle(track.artist, track.formattedDuration);
        actionIcon = Icons.play_arrow_rounded;
        onTap = () async {
          final playerService = ref.read(audioPlayerServiceProvider);
          await playerService.playTrack(track, enableRadio: true);
          ref.read(recentlyPlayedProvider.notifier).addTrack(track);
          if (mounted) NowPlayingScreen.show(context);
        };
        imageWidget = ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: _buildImage(track.thumbnailUrl, 76, Icons.music_note_rounded),
        );
        break;

      case SearchResultType.album:
        final album = topResult.album!;
        title = album.title;
        subtitle = context.l10n.albumByArtist(album.artist);
        actionIcon = Icons.chevron_right_rounded;
        onTap = () => AlbumScreen.open(
          context,
          albumId: album.id,
          title: album.title,
          thumbnailUrl: album.thumbnailUrl,
        );
        imageWidget = ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: _buildImage(album.thumbnailUrl, 76, Icons.album_rounded),
        );
        break;

      case SearchResultType.playlist:
        final playlist = topResult.playlist!;
        title = playlist.title;
        subtitle = context.l10n.playlistByAuthor(
          playlist.author ?? context.l10n.youtubeMusicLabel,
        );
        actionIcon = Icons.chevron_right_rounded;
        onTap = () {
          if (playlist.isPodcast || playlist.id.startsWith('MPSP')) {
            PodcastScreen.open(
              context,
              podcastId: playlist.id,
              title: playlist.title,
              thumbnailUrl: playlist.thumbnailUrl,
            );
          } else {
            PlaylistScreen.open(
              context,
              playlistId: playlist.id,
              title: playlist.title,
              thumbnailUrl: playlist.thumbnailUrl,
            );
          }
        };
        imageWidget = ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: _buildImage(
            playlist.thumbnailUrl,
            76,
            playlist.isPodcast || playlist.id.startsWith('MPSP')
                ? Icons.podcasts_rounded
                : Icons.queue_music_rounded,
          ),
        );
        break;
    }

    return BouncyTouch(
      style: BouncyStyle.card,
      customScale: 0.97,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accentColor.withValues(alpha: 0.16),
                  textColor.withValues(alpha: 0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: accentColor.withValues(alpha: 0.35),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.15),
                  blurRadius: 24,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                // Artwork with ambient glow
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: 76,
                    height: 76,
                    child: imageWidget,
                  ),
                ),
                const SizedBox(width: 16),
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final titleStyle = TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          );
                          final textPainter = TextPainter(
                            text: TextSpan(text: title, style: titleStyle),
                            maxLines: 1,
                            textDirection: TextDirection.ltr,
                          )..layout();

                          if (textPainter.width > constraints.maxWidth) {
                            return SizedBox(
                              height: 24,
                              child: Marquee(
                                text: title,
                                style: titleStyle,
                                scrollAxis: Axis.horizontal,
                                blankSpace: 36.0,
                                velocity: 28.0,
                                pauseAfterRound: const Duration(seconds: 2),
                                startPadding: 0.0,
                                accelerationDuration: const Duration(seconds: 1),
                                accelerationCurve: Curves.linear,
                                decelerationDuration: const Duration(milliseconds: 500),
                              ),
                            );
                          }
                          return Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
                          );
                        },
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Action Circular Button
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.40),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      actionIcon,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSongsSection(
    List<Track> tracks,
    Color accentColor,
    Color textColor,
    Color secondaryTextColor,
    ColorScheme colorScheme,
    SearchFilter filter,
  ) {
    final displayTracks = filter == SearchFilter.songs
        ? tracks
        : tracks.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (filter == SearchFilter.all)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 18, bottom: 10),
            child: Text(
              context.l10n.songs,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: textColor,
              ),
            ),
          ),
        ...displayTracks.map(
          (track) => _buildTrackTile(track, accentColor, textColor, secondaryTextColor, colorScheme),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildTrackTile(
    Track track,
    Color accentColor,
    Color textColor,
    Color secondaryTextColor,
    ColorScheme colorScheme,
  ) {
    final playerService = ref.watch(audioPlayerServiceProvider);
    final playbackState = ref.watch(playbackStateProvider);
    final isCurrentTrack =
        playbackState.whenOrNull(data: (s) => s.currentTrack?.id == track.id) ??
        false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: BouncyTouch(
        style: BouncyStyle.card,
        customScale: 0.98,
        onTap: () async {
          await playerService.playTrack(track, enableRadio: true);
          ref.read(recentlyPlayedProvider.notifier).addTrack(track);
          if (mounted) NowPlayingScreen.show(context);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isCurrentTrack
                ? accentColor.withValues(alpha: 0.12)
                : textColor.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: isCurrentTrack
                ? Border.all(color: accentColor.withValues(alpha: 0.40), width: 1.0)
                : null,
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _buildImage(track.thumbnailUrl, 48, Icons.music_note_rounded),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildScrollableTitle(
                      track.title,
                      TextStyle(
                        fontSize: 14.5,
                        fontWeight: isCurrentTrack ? FontWeight.bold : FontWeight.w600,
                        color: isCurrentTrack ? accentColor : textColor,
                      ),
                      isCurrentTrack,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (track.isExplicit)
                          ExplicitBadge(
                            color: isCurrentTrack
                                ? accentColor.withValues(alpha: 0.8)
                                : secondaryTextColor,
                          ),
                        Expanded(
                          child: Text(
                            context.trackSubtitle(track.artist, track.formattedDuration),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isCurrentTrack
                                  ? accentColor.withValues(alpha: 0.8)
                                  : secondaryTextColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              BouncyTouch(
                style: BouncyStyle.button,
                customScale: 0.85,
                onTap: () => TrackOptionsSheet.show(context, track),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Icon(
                    Icons.more_vert_rounded,
                    color: secondaryTextColor,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArtistsSection(
    List<Artist> artists,
    Color accentColor,
    Color textColor,
    Color secondaryTextColor,
    ColorScheme colorScheme,
    SearchFilter filter,
  ) {
    final displayArtists = filter == SearchFilter.artists
        ? artists
        : artists.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (filter == SearchFilter.all)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 18, bottom: 10),
            child: Text(
              context.l10n.artists,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: textColor,
              ),
            ),
          ),
        if (filter == SearchFilter.artists)
          ...displayArtists.map(
            (artist) => _buildArtistTile(artist, accentColor, textColor, secondaryTextColor),
          )
        else
          SizedBox(
            height: 190,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: displayArtists.length,
              itemBuilder: (context, index) =>
                  _buildArtistCard(displayArtists[index], accentColor, textColor, secondaryTextColor),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildArtistTile(
    Artist artist,
    Color accentColor,
    Color textColor,
    Color secondaryTextColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: BouncyTouch(
        style: BouncyStyle.card,
        customScale: 0.98,
        onTap: () => ArtistScreen.open(
          context,
          artistId: artist.id,
          name: artist.name,
          thumbnailUrl: artist.thumbnailUrl,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: textColor.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              ClipOval(
                child: _buildImage(artist.thumbnailUrl, 48, Icons.person_rounded),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      artist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.artistSubtitle(artist.formattedSubscribers),
                      style: TextStyle(
                        fontSize: 12,
                        color: secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: secondaryTextColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArtistCard(
    Artist artist,
    Color accentColor,
    Color textColor,
    Color secondaryTextColor,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: BouncyTouch(
        style: BouncyStyle.card,
        customScale: 0.95,
        onTap: () => ArtistScreen.open(
          context,
          artistId: artist.id,
          name: artist.name,
          thumbnailUrl: artist.thumbnailUrl,
        ),
        child: Container(
          width: 120,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: textColor.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              ClipOval(
                child: _buildImage(artist.thumbnailUrl, 84, Icons.person_rounded),
              ),
              const SizedBox(height: 8),
              Text(
                artist.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumsSection(
    List<Album> albums,
    Color accentColor,
    Color textColor,
    Color secondaryTextColor,
    ColorScheme colorScheme,
    SearchFilter filter,
  ) {
    final displayAlbums = filter == SearchFilter.albums
        ? albums
        : albums.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (filter == SearchFilter.all)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 18, bottom: 10),
            child: Text(
              context.l10n.albums,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: textColor,
              ),
            ),
          ),
        if (filter == SearchFilter.albums)
          ...displayAlbums.map(
            (album) => _buildAlbumTile(album, accentColor, textColor, secondaryTextColor),
          )
        else
          SizedBox(
            height: 220,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: displayAlbums.length,
              itemBuilder: (context, index) =>
                  _buildAlbumCard(displayAlbums[index], accentColor, textColor, secondaryTextColor),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildAlbumTile(
    Album album,
    Color accentColor,
    Color textColor,
    Color secondaryTextColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: BouncyTouch(
        style: BouncyStyle.card,
        customScale: 0.98,
        onTap: () => AlbumScreen.open(
          context,
          albumId: album.id,
          title: album.title,
          thumbnailUrl: album.thumbnailUrl,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: textColor.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _buildImage(album.thumbnailUrl, 48, Icons.album_rounded),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.albumSubtitle(album.artist, album.year),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: secondaryTextColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumCard(
    Album album,
    Color accentColor,
    Color textColor,
    Color secondaryTextColor,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: BouncyTouch(
        style: BouncyStyle.card,
        customScale: 0.95,
        onTap: () => AlbumScreen.open(
          context,
          albumId: album.id,
          title: album.title,
          thumbnailUrl: album.thumbnailUrl,
        ),
        child: Container(
          width: 135,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: textColor.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildImage(album.thumbnailUrl, 115, Icons.album_rounded),
              ),
              const SizedBox(height: 8),
              Text(
                album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              Text(
                album.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: secondaryTextColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaylistsSection(
    List<Playlist> playlists,
    Color accentColor,
    Color textColor,
    Color secondaryTextColor,
    ColorScheme colorScheme,
    SearchFilter filter,
  ) {
    final displayPlaylists = filter == SearchFilter.playlists
        ? playlists
        : playlists.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (filter == SearchFilter.all)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 18, bottom: 10),
            child: Text(
              context.l10n.playlists,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: textColor,
              ),
            ),
          ),
        ...displayPlaylists.map(
          (playlist) => _buildPlaylistTile(playlist, accentColor, textColor, secondaryTextColor),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildPodcastsSection(
    List<Playlist> podcasts,
    Color accentColor,
    Color textColor,
    Color secondaryTextColor,
    ColorScheme colorScheme,
    SearchFilter filter,
  ) {
    final displayPodcasts = filter == SearchFilter.podcasts
        ? podcasts
        : podcasts.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (filter == SearchFilter.all)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 18, bottom: 10),
            child: Text(
              'Podcasts',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: textColor,
              ),
            ),
          ),
        ...displayPodcasts.map(
          (podcast) => _buildPlaylistTile(podcast, accentColor, textColor, secondaryTextColor),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildPlaylistTile(
    Playlist playlist,
    Color accentColor,
    Color textColor,
    Color secondaryTextColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: BouncyTouch(
        style: BouncyStyle.card,
        customScale: 0.98,
        onTap: () {
          if (playlist.isPodcast || playlist.id.startsWith('MPSP')) {
            PodcastScreen.open(
              context,
              podcastId: playlist.id,
              title: playlist.title,
              thumbnailUrl: playlist.thumbnailUrl,
            );
          } else {
            PlaylistScreen.open(
              context,
              playlistId: playlist.id,
              title: playlist.title,
              thumbnailUrl: playlist.thumbnailUrl,
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: textColor.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _buildImage(
                  playlist.thumbnailUrl,
                  52,
                  playlist.isPodcast ? Iconsax.microphone : Iconsax.music_playlist,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      playlist.isPodcast
                          ? (playlist.author ?? 'Podcast')
                          : context.playlistSubtitle(
                              playlist.author ?? context.l10n.playlist,
                              (playlist.trackCount != null && playlist.trackCount! > 0)
                                  ? playlist.trackCount
                                  : null,
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: secondaryTextColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage(String? url, double size, IconData fallbackIcon) {
    if (url == null) {
      return Container(
        width: size,
        height: size,
        color: Colors.grey[800],
        child: Icon(fallbackIcon, color: Colors.white54, size: size * 0.4),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      placeholder: (_, _) => Container(
        width: size,
        height: size,
        color: Colors.grey[800],
        child: Icon(fallbackIcon, color: Colors.white54, size: size * 0.4),
      ),
      errorWidget: (_, _, _) => Container(
        width: size,
        height: size,
        color: Colors.grey[800],
        child: Icon(fallbackIcon, color: Colors.white54, size: size * 0.4),
      ),
    );
  }

  Widget _buildScrollableTitle(String title, TextStyle style, bool isPlaying) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: title, style: style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);

        if (isPlaying && (textPainter.didExceedMaxLines || textPainter.width >= constraints.maxWidth - 2)) {
          return SizedBox(
            height: style.fontSize != null ? style.fontSize! * 1.5 : 20,
            child: Marquee(
              text: title,
              style: style,
              scrollAxis: Axis.horizontal,
              blankSpace: 40.0,
              velocity: 30.0,
              pauseAfterRound: const Duration(seconds: 2),
              startPadding: 0,
              accelerationDuration: const Duration(milliseconds: 500),
              accelerationCurve: Curves.linear,
              decelerationDuration: const Duration(milliseconds: 500),
              decelerationCurve: Curves.easeOut,
            ),
          );
        }

        return Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      },
    );
  }
}
