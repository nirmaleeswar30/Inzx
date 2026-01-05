import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import '../../providers/search_history_provider.dart';
import '../../providers/providers.dart'
    hide searchHistoryProvider, recentlyPlayedProvider;
import '../../models/models.dart';

/// Enhanced search bar with suggestions and history
class EnhancedSearchBar extends ConsumerStatefulWidget {
  final Function(String) onSearch;
  final String? initialQuery;

  const EnhancedSearchBar({
    super.key,
    required this.onSearch,
    this.initialQuery,
  });

  @override
  ConsumerState<EnhancedSearchBar> createState() => _EnhancedSearchBarState();
}

class _EnhancedSearchBarState extends ConsumerState<EnhancedSearchBar> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _showSuggestions = false;
  List<String> _suggestions = [];
  bool _isLoadingSuggestions = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _showSuggestions = _focusNode.hasFocus;
    });
  }

  Future<void> _loadSuggestions(String query) async {
    if (query.length < 2) {
      setState(() => _suggestions = []);
      return;
    }

    setState(() => _isLoadingSuggestions = true);

    try {
      final innerTube = ref.read(innerTubeServiceProvider);
      final suggestions = await innerTube.getSearchSuggestions(query);
      if (mounted) {
        setState(() {
          _suggestions = suggestions.take(5).toList();
          _isLoadingSuggestions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _suggestions = [];
          _isLoadingSuggestions = false;
        });
      }
    }
  }

  void _performSearch(String query) {
    if (query.trim().isEmpty) return;

    _focusNode.unfocus();
    ref.read(searchHistoryProvider.notifier).addSearch(query);
    widget.onSearch(query);
    setState(() => _showSuggestions = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final history = ref.watch(searchHistoryProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Search field
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(
              hintText: 'Search songs, albums, artists...',
              hintStyle: TextStyle(
                color: isDark ? Colors.white54 : Colors.black45,
              ),
              prefixIcon: Icon(
                Iconsax.search_normal,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.clear,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _suggestions = []);
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            onChanged: (value) {
              setState(() {});
              _loadSuggestions(value);
            },
            onSubmitted: _performSearch,
            textInputAction: TextInputAction.search,
          ),
        ),

        // Suggestions/History dropdown
        if (_showSuggestions)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            constraints: const BoxConstraints(maxHeight: 300),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Suggestions
                  if (_isLoadingSuggestions)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (_suggestions.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        'Suggestions',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ),
                    ..._suggestions.map(
                      (s) =>
                          _buildSuggestionItem(s, isDark, isSuggestion: true),
                    ),
                  ],

                  // Search history
                  if (_controller.text.isEmpty && history.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Recent Searches',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                          ),
                          TextButton(
                            onPressed: () => ref
                                .read(searchHistoryProvider.notifier)
                                .clearHistory(),
                            child: const Text(
                              'Clear',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...history
                        .take(5)
                        .map(
                          (h) =>
                              _buildSuggestionItem(h, isDark, isHistory: true),
                        ),
                  ],

                  if (_suggestions.isEmpty &&
                      history.isEmpty &&
                      !_isLoadingSuggestions)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Start typing to search...',
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSuggestionItem(
    String text,
    bool isDark, {
    bool isSuggestion = false,
    bool isHistory = false,
  }) {
    return InkWell(
      onTap: () {
        _controller.text = text;
        _performSearch(text);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              isHistory ? Iconsax.clock : Iconsax.search_normal,
              size: 18,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
            ),
            if (isHistory)
              GestureDetector(
                onTap: () =>
                    ref.read(searchHistoryProvider.notifier).removeSearch(text),
                child: Icon(
                  Icons.close,
                  size: 18,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            if (isSuggestion)
              Icon(
                Icons.north_west,
                size: 16,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
          ],
        ),
      ),
    );
  }
}

/// Recently played section widget
class RecentlyPlayedSection extends ConsumerWidget {
  const RecentlyPlayedSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentlyPlayed = ref.watch(recentlyPlayedProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final playerService = ref.watch(audioPlayerServiceProvider);

    if (recentlyPlayed.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recently Played',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(recentlyPlayedProvider.notifier).clearHistory(),
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: recentlyPlayed.length.clamp(0, 10),
            itemBuilder: (context, index) {
              final track = recentlyPlayed[index];
              return _buildRecentTrackCard(
                context,
                track,
                isDark,
                playerService,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecentTrackCard(
    BuildContext context,
    Track track,
    bool isDark,
    dynamic playerService,
  ) {
    return GestureDetector(
      onTap: () => playerService.playTrack(track),
      child: Container(
        width: 120,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 1,
                child: track.thumbnailUrl != null
                    ? Image.network(track.thumbnailUrl!, fit: BoxFit.cover)
                    : Container(
                        color: isDark ? Colors.white12 : Colors.grey.shade200,
                        child: const Icon(Iconsax.music, size: 32),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
