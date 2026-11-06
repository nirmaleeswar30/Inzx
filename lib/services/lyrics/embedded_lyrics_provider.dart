import 'dart:io';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import '../tagger/webm_tagger.dart';
import 'lyrics_models.dart';
import 'enhanced_lrc_parser.dart';
import 'background_vocals.dart';
import 'instrumental_gaps.dart';

/// Embedded & Local Lyrics Provider - reads sidecar .lrc files and embedded audio container tags
class EmbeddedLyricsProvider implements LyricsProvider {
  @override
  String get name => 'Embedded';

  @override
  Future<LyricResult?> search(LyricsSearchInfo info) async {
    final filePath = info.localFilePath;
    if (filePath == null || filePath.trim().isEmpty) return null;

    try {
      final audioFile = File(filePath);
      if (!await audioFile.exists()) return null;

      // 1. Check sidecar .lrc files first
      final sidecarLyrics = await _readSidecarLrc(audioFile, info);
      if (sidecarLyrics != null && sidecarLyrics.trim().isNotEmpty) {
        final parsed = _parseRawLyrics(sidecarLyrics, info);
        if (parsed != null) return parsed;
      }

      // 2. WebM/Opus downloads, which the metadata reader below can't parse
      final lowerPath = filePath.toLowerCase();
      if (lowerPath.endsWith('.opus') || lowerPath.endsWith('.webm')) {
        final webmLyrics = WebmTagger.readEmbedded(
          await audioFile.readAsBytes(),
        ).lyrics;
        if (webmLyrics != null) {
          final parsed = _parseRawLyrics(webmLyrics, info);
          if (parsed != null) return parsed;
        }
      }

      // 3. Read embedded lyrics from file metadata
      try {
        final metadata = readMetadata(audioFile, getImage: false);
        final rawLyrics = metadata.lyrics;
        if (rawLyrics != null && rawLyrics.trim().isNotEmpty) {
          final parsed = _parseRawLyrics(rawLyrics, info);
          if (parsed != null) return parsed;
        }
      } catch (e) {
        if (kDebugMode) {
          print('EmbeddedLyrics: Metadata read failed for $filePath: $e');
        }
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('EmbeddedLyricsProvider error: $e');
      }
      return null;
    }
  }

  Future<String?> _readSidecarLrc(File audioFile, LyricsSearchInfo info) async {
    try {
      final dir = audioFile.parent;
      final fileName = audioFile.uri.pathSegments.last;
      final baseName = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');

      final candidates = [
        '${dir.path}/$baseName.lrc',
        '${dir.path}/$baseName.LRC',
        '${dir.path}/lyrics.lrc',
        '${dir.path}/${info.title} - ${info.artist}.lrc',
        '${dir.path}/${info.artist} - ${info.title}.lrc',
      ];

      for (final candidate in candidates) {
        final file = File(candidate);
        if (await file.exists()) {
          return await file.readAsString();
        }
      }
    } catch (_) {}
    return null;
  }

  LyricResult? _parseRawLyrics(String raw, LyricsSearchInfo info) {
    // 1. Try word-synced enhanced LRC
    final enhanced = EnhancedLrcParser.parse(raw);
    if (enhanced.isNotEmpty) {
      final processed = enhanced.withBackgroundVocals().withInstrumentalGaps();
      return LyricResult(
        title: info.title,
        artists: [info.artist],
        lines: processed,
        source: name,
      );
    }

    // 2. Try standard line-synced LRC
    final standardLines = _parseStandardLrc(raw);
    if (standardLines.isNotEmpty) {
      final processed = standardLines.withBackgroundVocals().withInstrumentalGaps();
      return LyricResult(
        title: info.title,
        artists: [info.artist],
        lines: processed,
        source: name,
      );
    }

    // 3. Plain text fallback
    final plainText = raw.split('\n')
        .where((l) => !l.trim().startsWith('[') && l.trim().isNotEmpty)
        .join('\n')
        .trim();

    if (plainText.isNotEmpty) {
      return LyricResult(
        title: info.title,
        artists: [info.artist],
        lyrics: plainText,
        source: name,
      );
    }

    return null;
  }

  static List<LyricLine> _parseStandardLrc(String lrc) {
    final regex = RegExp(r'^\[(\d{1,3}):(\d{2})[.:](\d{2,3})\](.*)$');
    final result = <LyricLine>[];

    for (final raw in lrc.split('\n')) {
      final line = raw.trim();
      final match = regex.firstMatch(line);
      if (match != null) {
        final m = int.parse(match.group(1)!);
        final s = int.parse(match.group(2)!);
        final frac = match.group(3)!;
        final fracMs = frac.length == 3 ? int.parse(frac) : int.parse(frac) * 10;
        final text = EnhancedLrcParser.decodeEntities(match.group(4) ?? '').trim();
        if (text.isNotEmpty) {
          result.add(LyricLine(
            timeInMs: m * 60000 + s * 1000 + fracMs,
            text: text,
          ));
        }
      }
    }

    result.sort((a, b) => a.timeInMs.compareTo(b.timeInMs));
    return result;
  }
}
