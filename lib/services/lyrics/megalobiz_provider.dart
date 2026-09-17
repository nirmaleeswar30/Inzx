import 'package:http/http.dart' as http;
import 'package:html_unescape/html_unescape.dart';
import 'lyrics_models.dart';
import 'lyrics_cleaner.dart';

class MegalobizProvider implements LyricsProvider {
  @override
  String get name => 'Megalobiz';

  static const _base = 'https://www.megalobiz.com';
  static final http.Client _client = http.Client();
  static final _unescape = HtmlUnescape();

  static final _linkRegex = RegExp(r'''href=['"](/lrc/maker/download/[^'"]+)['"]''', caseSensitive: false);
  static final _bodyRegex = RegExp(r'''id=['"]lrc_[^'"]*_details['"][^>]*>(.*?)</span>''', caseSensitive: false, dotAll: true);
  static final _brRegex = RegExp(r"<br\s*/?>", caseSensitive: false);
  static final _tagRegex = RegExp(r"<[^>]+>");

  @override
  Future<LyricResult?> search(LyricsSearchInfo info) async {
    try {
      final query = '${info.artist} ${LyricsCleaner.cleanTitle(info.title)}'.trim();
      final searchUri = Uri.parse('$_base/searchall').replace(queryParameters: {'qry': query});
      
      final searchRes = await _client.get(searchUri).timeout(const Duration(seconds: 10));
      if (searchRes.statusCode != 200) return null;
      
      final match = _linkRegex.firstMatch(searchRes.body);
      if (match == null) return null;
      
      final path = match.group(1)!.replaceAll('&amp;', '&');
      
      final pageRes = await _client.get(Uri.parse(_base + path)).timeout(const Duration(seconds: 10));
      if (pageRes.statusCode != 200) return null;
      
      final bodyMatch = _bodyRegex.firstMatch(pageRes.body);
      if (bodyMatch == null) return null;
      
      var raw = bodyMatch.group(1)!;
      raw = raw.replaceAll(_brRegex, '\n');
      raw = raw.replaceAll(_tagRegex, '');
      raw = _unescape.convert(raw);
      
      final lines = _parseStandardLrc(raw);
      if (lines.isEmpty || !lines.any((l) => l.text.trim().isNotEmpty)) return null;

      return LyricResult(
        title: info.title,
        artists: [info.artist],
        lines: lines,
        lyrics: raw,
        source: name,
      );
    } catch (e) {
      return null;
    }
  }

  List<LyricLine> _parseStandardLrc(String lrc) {
    final RegExp lineRegex = RegExp(r'^\[(\d{1,3}):(\d{2})[.:](\d{2,3})\](.*)$');
    final lines = <LyricLine>[];
    for (var line in lrc.split('\n')) {
      final match = lineRegex.firstMatch(line.trim());
      if (match != null) {
        final m = int.parse(match.group(1)!);
        final s = int.parse(match.group(2)!);
        final frac = match.group(3)!;
        final fracMs = frac.length == 3 ? int.parse(frac) : int.parse(frac) * 10;
        final timeMs = m * 60000 + s * 1000 + fracMs;
        lines.add(LyricLine(timeInMs: timeMs, text: match.group(4)?.trim() ?? ''));
      }
    }
    return lines;
  }
}
