import 'home_shelf.dart';

/// A button that opens another browse page: the big buttons at the top of
/// Explore and the colour-striped mood and genre tiles.
class ExploreLink {
  const ExploreLink({
    required this.title,
    required this.browseId,
    this.params,
    this.stripeColor,
    this.iconType,
  });

  final String title;
  final String browseId;
  final String? params;

  /// ARGB colour of a mood tile's left edge.
  final int? stripeColor;

  /// YouTube's icon name, such as `MUSIC_NEW_RELEASE`.
  final String? iconType;
}

/// One section of a browse page.
class ExploreSection {
  const ExploreSection({
    required this.title,
    this.browseId,
    this.items = const [],
    this.links = const [],
    this.isGrid = false,
  });

  final String title;

  /// Where the section's "More" button goes, if it has one.
  final String? browseId;
  final List<HomeShelfItem> items;
  final List<ExploreLink> links;

  /// A full page of items that wraps, rather than a row that scrolls.
  final bool isGrid;
}

/// YouTube Music's Explore page, or a page linked from it.
class ExplorePage {
  const ExplorePage({required this.topLinks, required this.sections});

  final List<ExploreLink> topLinks;
  final List<ExploreSection> sections;
}
