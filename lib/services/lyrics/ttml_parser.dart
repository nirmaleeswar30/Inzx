import 'package:flutter/foundation.dart' show compute, kDebugMode;
import 'package:xml/xml.dart';
import 'lyrics_models.dart';

/// TTML (Timed Text Markup Language) parser for BetterLyrics
class TTMLParser {
  /// Parse TTML XML string into LyricLines with word-level timing.
  /// Runs in a background isolate via compute().
  static Future<List<LyricLine>> parse(String ttml) async {
    return compute(_parseTTMLIsolate, ttml);
  }
}

/// Top-level function for compute() isolate
List<LyricLine> _parseTTMLIsolate(String ttml) {
  final lines = <_ParsedLine>[];
  try {
    final doc = XmlDocument.parse(ttml);
    final root = doc.rootElement;

    double globalOffset = 0.0;
    final head = _findChild(root, 'head');
    if (head != null) {
      final meta = _findChild(head, 'metadata');
      if (meta != null) {
        final audio = _findChild(meta, 'audio');
        if (audio != null) {
          globalOffset = double.tryParse(audio.getAttribute('lyricOffset') ?? '') ?? 0.0;
        }
      }
    }

    final body = _findChild(root, 'body');
    if (body != null) {
      _walk(body, lines, globalOffset, null);
    }
  } catch (e) {
    if (kDebugMode) {
      print('TTMLParser.parseTTML: Failed to parse TTML - $e');
    }
    return [];
  }

  return lines.map(_toLyricLine).toList();
}

LyricLine _toLyricLine(_ParsedLine l) {
  return LyricLine(
    text: l.text,
    timeInMs: (l.startTime * 1000).round(),
    words: l.words
        .map((w) => LyricWord(
              text: w.text,
              startTimeMs: (w.startTime * 1000).round(),
              endTimeMs: (w.endTime * 1000).round(),
            ))
        .toList(),
    isBackground: l.isBackground,
    backgroundLines: l.backgroundLines.map(_toLyricLine).toList(),
  );
}

void _walk(XmlElement element, List<_ParsedLine> lines, double offset, String? parentAgent) {
  final name = element.name.local;
  String? currentAgent = parentAgent;

  if (name == 'div') {
    final a = _getAttr(element, 'agent');
    if (a.isNotEmpty) currentAgent = a;
  } else if (name == 'p') {
    _parseP(element, lines, offset, currentAgent);
    return;
  }

  for (var child in element.childElements) {
    _walk(child, lines, offset, currentAgent);
  }
}

void _parseP(XmlElement p, List<_ParsedLine> lines, double offset, String? divAgent) {
  String begin = p.getAttribute('begin') ?? '';
  if (begin.isEmpty) {
    begin = p.getAttribute('ttp:begin') ?? '';
  }
  if (begin.isEmpty) {
    begin = _findFirstSpanBegin(p) ?? '';
    if (begin.isEmpty) return;
  }

  final startTime = _parseTime(begin) + offset;
  final spanInfos = <_SpanInfo>[];
  final backgroundLines = <_ParsedLine>[];

  final agentAttr = _getAttr(p, 'agent');
  final agent = agentAttr.isEmpty ? divAgent : agentAttr;
  final isPBackground = _getAttr(p, 'role') == 'x-bg';

  for (var child in p.childElements) {
    if (child.name.local == 'span') {
      final role = _getAttr(child, 'role');
      if (role == 'x-bg') {
        if (isPBackground) {
          _parseWordSpan(child, offset, spanInfos);
        } else {
          final bgLine = _parseBackgroundSpan(child, startTime, offset);
          if (bgLine != null) backgroundLines.add(bgLine);
        }
      } else if (role == 'x-translation' || role == 'x-roman') {
        // Ignored roles
      } else {
        _parseWordSpan(child, offset, spanInfos);
      }
    }
  }

  final words = _mergeSpansIntoWords(spanInfos);
  final lineText = words.isEmpty ? _getDirectText(p).trim() : _buildLineText(words);

  if (lineText.isNotEmpty) {
    final bgLines = backgroundLines.isNotEmpty
        ? [
            _ParsedLine(
              text: backgroundLines.map((e) => e.text).join(" "),
              startTime: backgroundLines.map((e) => e.startTime).reduce((a, b) => a < b ? a : b),
              words: backgroundLines.expand((e) => e.words).toList(),
              isBackground: true,
            )
          ]
        : const <_ParsedLine>[];
    lines.add(_ParsedLine(
      text: lineText,
      startTime: startTime,
      words: words,
      agent: agent,
      isBackground: isPBackground,
      backgroundLines: bgLines,
    ));
  } else if (backgroundLines.isNotEmpty) {
    lines.add(_ParsedLine(
      text: backgroundLines.map((e) => e.text).join(" "),
      startTime: backgroundLines.map((e) => e.startTime).reduce((a, b) => a < b ? a : b),
      words: backgroundLines.expand((e) => e.words).toList(),
      isBackground: true,
    ));
  }
}

void _parseWordSpan(XmlElement span, double offset, List<_SpanInfo> spanInfos) {
  final begin = _timingAttr(span, 'begin');
  final end = _timingAttr(span, 'end');
  final text = span.innerText;
  
  if (begin.isNotEmpty && end.isNotEmpty) {
    bool space = false;
    if (text.isNotEmpty && RegExp(r'\s').hasMatch(text[text.length - 1])) {
      space = true;
    } else {
      final parent = span.parent;
      if (parent != null) {
        final index = parent.children.indexOf(span);
        if (index != -1 && index + 1 < parent.children.length) {
          final next = parent.children[index + 1];
          if (next is XmlText) {
            final nextText = next.value;
            if (nextText.isNotEmpty && RegExp(r'\s').hasMatch(nextText[0])) {
              space = true;
            }
          }
        }
      }
    }
    
    spanInfos.add(_SpanInfo(
      text: text,
      startTime: _parseTime(begin) + offset,
      endTime: _parseTime(end) + offset,
      hasTrailingSpace: space,
    ));
  }
}

_ParsedLine? _parseBackgroundSpan(XmlElement span, double parentStart, double offset) {
  final begin = _timingAttr(span, 'begin');
  final start = begin.isNotEmpty ? _parseTime(begin) + offset : parentStart;
  final spanInfos = <_SpanInfo>[];

  bool hasSpans = false;
  for (var child in span.childElements) {
    if (child.name.local == 'span') {
      hasSpans = true;
      final role = _getAttr(child, 'role');
      if (role != 'x-translation' && role != 'x-roman') {
        _parseWordSpan(child, offset, spanInfos);
      }
    }
  }

  if (!hasSpans) {
    final text = span.innerText.trim();
    return _ParsedLine(text: text, startTime: start, isBackground: true);
  }

  final words = _mergeSpansIntoWords(spanInfos);
  final text = words.isEmpty ? _getDirectText(span).trim() : _buildLineText(words);
  return _ParsedLine(text: text, startTime: start, words: words, isBackground: true);
}

XmlElement? _findChild(XmlElement parent, String localName) {
  for (var child in parent.childElements) {
    if (child.name.local == localName) return child;
  }
  return null;
}

String _getAttr(XmlElement el, String localName) {
  final ttm = el.getAttribute('ttm:$localName');
  if (ttm != null && ttm.isNotEmpty) return ttm;
  final direct = el.getAttribute(localName);
  if (direct != null && direct.isNotEmpty) return direct;
  
  for (var attr in el.attributes) {
    if (attr.name.local == localName && attr.name.namespaceUri == 'http://www.w3.org/ns/ttml#metadata') {
      return attr.value;
    }
  }
  return '';
}

String _timingAttr(XmlElement el, String localName) {
  final direct = el.getAttribute(localName);
  if (direct != null && direct.isNotEmpty) return direct;
  final param = el.getAttribute('ttp:$localName');
  if (param != null && param.isNotEmpty) return param;
  
  for (var attr in el.attributes) {
    if (attr.name.local == localName && attr.name.namespaceUri == 'http://www.w3.org/ns/ttml#parameter') {
      return attr.value;
    }
  }
  return '';
}

String? _findFirstSpanBegin(XmlElement p) {
  String? best;
  double bestSeconds = double.infinity;
  for (var child in p.childElements) {
    if (child.name.local == 'span') {
      final b = _timingAttr(child, 'begin');
      if (b.isNotEmpty) {
        final s = _parseTime(b);
        if (s < bestSeconds) {
          bestSeconds = s;
          best = b;
        }
      }
    }
  }
  return best;
}

String _getDirectText(XmlElement el) {
  final sb = StringBuffer();
  for (var child in el.children) {
    if (child is XmlText) {
      sb.write(child.value);
    } else if (child is XmlElement) {
      final name = child.name.local;
      final role = _getAttr(child, 'role');
      if (name == 'span' && role != 'x-bg' && role != 'x-translation' && role != 'x-roman') {
        sb.write(child.innerText);
      }
    }
  }
  return sb.toString();
}

String _buildLineText(List<_ParsedWord> words) {
  final sb = StringBuffer();
  for (int i = 0; i < words.length; i++) {
    final w = words[i];
    sb.write(w.text);
    if (w.hasTrailingSpace && !w.text.endsWith('-') && i < words.length - 1) {
      sb.write(' ');
    }
  }
  return sb.toString().trim();
}

List<_ParsedWord> _mergeSpansIntoWords(List<_SpanInfo> spanInfos) {
  if (spanInfos.isEmpty) return [];
  final words = <_ParsedWord>[];
  var text = StringBuffer(spanInfos[0].text);
  var start = spanInfos[0].startTime;
  var end = spanInfos[0].endTime;

  for (int i = 1; i < spanInfos.length; i++) {
    final prev = spanInfos[i - 1];
    final curr = spanInfos[i];
    if (prev.hasTrailingSpace && !prev.text.endsWith('-')) {
      words.add(_ParsedWord(
        text: text.toString(),
        startTime: start,
        endTime: end,
        hasTrailingSpace: true,
      ));
      text = StringBuffer(curr.text);
      start = curr.startTime;
      end = curr.endTime;
    } else {
      text.write(curr.text);
      end = curr.endTime;
    }
  }
  
  words.add(_ParsedWord(
    text: text.toString(),
    startTime: start,
    endTime: end,
    hasTrailingSpace: spanInfos.last.hasTrailingSpace,
  ));
  
  return words
      .map((w) => _ParsedWord(
            text: w.text.trim(),
            startTime: w.startTime,
            endTime: w.endTime,
            hasTrailingSpace: w.hasTrailingSpace,
          ))
      .where((w) => w.text.isNotEmpty)
      .toList();
}

double _parseTime(String time) {
  final t = time.trim();
  final c1 = t.indexOf(':');
  if (c1 != -1) {
    final c2 = t.lastIndexOf(':');
    if (c1 == c2) {
      return (int.tryParse(t.substring(0, c1)) ?? 0) * 60.0 + (double.tryParse(t.substring(c1 + 1)) ?? 0.0);
    } else {
      return (int.tryParse(t.substring(0, c1)) ?? 0) * 3600.0 +
          (int.tryParse(t.substring(c1 + 1, c2)) ?? 0) * 60.0 +
          (double.tryParse(t.substring(c2 + 1)) ?? 0.0);
    }
  }
  if (t.endsWith('ms')) {
    return (double.tryParse(t.substring(0, t.length - 2)) ?? 0.0) / 1000.0;
  }
  final s = (t.endsWith('s') || t.endsWith('m') || t.endsWith('h')) ? t.substring(0, t.length - 1) : t;
  final v = double.tryParse(s) ?? 0.0;
  if (t.endsWith('m')) return v * 60.0;
  if (t.endsWith('h')) return v * 3600.0;
  return v;
}

// ---------------------------------------------------------------------------
// Private Helper Classes
// ---------------------------------------------------------------------------

class _ParsedLine {
  final String text;
  final double startTime;
  final List<_ParsedWord> words;
  final String? agent;
  final bool isBackground;
  final List<_ParsedLine> backgroundLines;

  _ParsedLine({
    required this.text,
    required this.startTime,
    this.words = const [],
    this.agent,
    this.isBackground = false,
    this.backgroundLines = const [],
  });
}

class _ParsedWord {
  final String text;
  final double startTime;
  final double endTime;
  final bool hasTrailingSpace;

  _ParsedWord({
    required this.text,
    required this.startTime,
    required this.endTime,
    this.hasTrailingSpace = true,
  });
}

class _SpanInfo {
  final String text;
  final double startTime;
  final double endTime;
  final bool hasTrailingSpace;

  _SpanInfo({
    required this.text,
    required this.startTime,
    required this.endTime,
    required this.hasTrailingSpace,
  });
}
