import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/models/explore_page.dart';
import 'package:inzx/models/models.dart';
import 'package:inzx/screens/tabs/desktop_explore_tab.dart';

ExplorePage _page() {
  HomeShelfItem item(int i, HomeShelfItemType type) => HomeShelfItem(
    id: 'id$i',
    title: 'A fairly long title number $i that runs on',
    subtitle: 'Some Artist • Another Artist • 12M views',
    itemType: type,
    videoId: type == HomeShelfItemType.song || type == HomeShelfItemType.video ? 'v$i' : null,
  );
  ExploreLink link(String title, [String? icon]) =>
      ExploreLink(title: title, browseId: 'FE$title', stripeColor: 0xFFE91E63, iconType: icon);
  return ExplorePage(
    topLinks: [
      link('New releases', 'MUSIC_NEW_RELEASE'),
      link('Charts', 'TRENDING_UP'),
      link('Moods and genres', 'STICKER_EMOTICON'),
      link('Podcasts', 'BROADCAST'),
    ],
    sections: [
      ExploreSection(
        title: 'New albums and singles',
        browseId: 'FEmusic_new_releases_albums',
        items: [for (var i = 0; i < 8; i++) item(i, HomeShelfItemType.album)],
      ),
      ExploreSection(
        title: 'Moods and genres',
        browseId: 'FEmusic_moods_and_genres',
        links: [for (var i = 0; i < 16; i++) link('Mood with a long name $i')],
      ),
      ExploreSection(
        title: 'Trending',
        browseId: 'VLtrending',
        items: [for (var i = 0; i < 20; i++) item(i, HomeShelfItemType.song)],
      ),
      ExploreSection(
        title: 'New music videos',
        items: [for (var i = 0; i < 6; i++) item(i, HomeShelfItemType.video)],
      ),
      ExploreSection(
        title: 'All moods',
        isGrid: true,
        links: [for (var i = 0; i < 9; i++) link('Grid mood $i')],
      ),
    ],
  );
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('Explore lays out at phone width (${brightness.name})', (tester) async {
      tester.view.physicalSize = const Size(375 * 3, 812 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(body: ExplorePageView(page: _page())),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Scroll the whole page through; any overflow throws.
      for (var i = 0; i < 12; i++) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -500));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }

      // Top links two to a row, inside the phone's gutters.
      await tester.drag(find.byType(ListView).first, const Offset(0, 20000));
      await tester.pump();
      final charts = tester.getRect(find.text('Charts'));
      final releases = tester.getRect(find.text('New releases'));
      final moods = tester.getRect(find.text('Moods and genres').first);
      expect(charts.top, releases.top);
      expect(moods.top, greaterThan(releases.bottom));
      expect(charts.right, lessThanOrEqualTo(375 - 16));
      // No scroll arrows on a phone.
      expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
    });
  }
}
