import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/services/addons/dash_manifest.dart';
import 'package:inzx/services/lyrics/ttml_parser.dart';

/// The two places the app reads XML: synced lyrics (TTML) and DASH manifests
/// from addons. Both look attributes up by prefixed name (`ttm:role`) and
/// elements by local name inside a default namespace, which is what package
/// xml's namespace handling has to keep working.
void main() {
  group('TTML lyrics', () {
    const body = '''
  <body>
    <div ttm:agent="v1">
      <p begin="00:01.000" end="00:03.000">
        <span begin="00:01.000" end="00:01.500">Hello</span> <span begin="00:01.500" end="00:02.000">world</span>
        <span ttm:role="x-bg"><span begin="00:02.000" end="00:02.500">(ooh)</span></span>
        <span ttm:role="x-translation">Hallo Welt</span>
      </p>
      <p begin="1:00:04.5" end="1:00:06">Plain line</p>
    </div>
  </body>''';

    void expectLyrics(List lines) {
      expect(lines, hasLength(2));
      final first = lines[0];
      expect(first.text, 'Hello world');
      expect(first.timeInMs, 1000);
      // Two words: the space between the spans is its own text node.
      expect(first.words.map((w) => w.text).join('|'), 'Hello|world');
      expect(first.words.last.endTimeMs, 2000);
      expect(first.backgroundLines.single.text, '(ooh)');
      expect(first.backgroundLines.single.isBackground, true);
      expect(lines[1].text, 'Plain line');
      expect(lines[1].timeInMs, 3604500);
    }

    test('with its namespaces declared', () async {
      final lines = await TTMLParser.parse('''
<tt xmlns="http://www.w3.org/ns/ttml"
    xmlns:ttm="http://www.w3.org/ns/ttml#metadata"
    xmlns:itunes="http://music.apple.com/lyric-ttml-internal"
    itunes:timing="Word" xml:lang="en">
  <head><metadata><audio lyricOffset="0"/></metadata></head>
$body
</tt>''');
      expectLyrics(lines);
    });

    test('with the ttm prefix never declared', () async {
      // Lyrics providers don't all declare the prefixes they use.
      final lines = await TTMLParser.parse(
        '<tt xmlns="http://www.w3.org/ns/ttml">$body</tt>',
      );
      expectLyrics(lines);
    });

    test('applies the lyric offset', () async {
      final lines = await TTMLParser.parse('''
<tt xmlns="http://www.w3.org/ns/ttml">
  <head><metadata><audio lyricOffset="0.25"/></metadata></head>
  <body><p begin="2s" end="3s">Late</p></body>
</tt>''');
      expect(lines.single.timeInMs, 2250);
    });
  });

  group('DASH manifest', () {
    test('a namespaced segment timeline picks the lossless set', () {
      final track = DashManifest.parse('''<?xml version="1.0" encoding="UTF-8"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011"
     xmlns:cenc="urn:mpeg:cenc:2013"
     type="static" mediaPresentationDuration="PT10S">
  <Period>
    <AdaptationSet mimeType="audio/mp4">
      <Representation id="aac" codecs="mp4a.40.2" bandwidth="320000">
        <SegmentTemplate initialization="aac/init.mp4" media="aac/\$Number\$.mp4" timescale="1000">
          <SegmentTimeline><S d="4000" r="-1"/></SegmentTimeline>
        </SegmentTemplate>
      </Representation>
    </AdaptationSet>
    <AdaptationSet mimeType="audio/mp4">
      <BaseURL>hifi/</BaseURL>
      <Representation id="flac" codecs="flac" bandwidth="900000">
        <SegmentTemplate initialization="init-\$RepresentationID\$.mp4"
                         media="seg-\$Number%03d\$.mp4" timescale="1000" startNumber="0">
          <SegmentTimeline><S t="0" d="4000" r="1"/><S d="2000"/></SegmentTimeline>
        </SegmentTemplate>
      </Representation>
    </AdaptationSet>
    <AdaptationSet mimeType="audio/mp4">
      <cenc:ContentProtection schemeIdUri="urn:mpeg:dash:mp4protection:2011"/>
      <Representation id="drm" codecs="flac" bandwidth="5000000"/>
    </AdaptationSet>
  </Period>
</MPD>''', baseUri: Uri.parse('https://cdn.example/track/manifest.mpd'));

      expect(track.codecs, 'flac');
      expect(track.hasInit, true);
      expect(track.segments.map((u) => u.toString()), [
        'https://cdn.example/track/hifi/init-flac.mp4',
        'https://cdn.example/track/hifi/seg-000.mp4',
        'https://cdn.example/track/hifi/seg-001.mp4',
        'https://cdn.example/track/hifi/seg-002.mp4',
      ]);
    });

    test('a self-indexed single file', () {
      final track = DashManifest.parse('''
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" mediaPresentationDuration="PT3M">
  <Period>
    <AdaptationSet contentType="audio">
      <Representation id="a" codecs="opus" bandwidth="160000">
        <BaseURL>https://media.example/a.webm</BaseURL>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>''');
      expect(track.singleFile, true);
      expect(track.segments.single.toString(), 'https://media.example/a.webm');
    });

    test('rejects something that is not a manifest', () {
      expect(
        () => DashManifest.parse('<html><body/></html>'),
        throwsFormatException,
      );
      expect(() => DashManifest.parse('<MPD'), throwsFormatException);
    });
  });
}
