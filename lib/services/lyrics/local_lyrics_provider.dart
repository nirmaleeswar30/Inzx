import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'lyrics_models.dart';

/// Local LRC file provider
/// Reads .lrc files from the same directory as the audio file
/// Note: This provider requires a local file path passed via extension info
class LocalLyricsProvider implements LyricsProvider {
  @override
  String get name => 'Local File';

  @override
  Future<LyricResult?> search(LyricsSearchInfo info) async {
    // This provider can only work if we have a local file path
    // For now, it's a placeholder for future local file lyrics support
    // Local file paths would need to be passed through a different mechanism
    return null;
  }

  /// Search for lyrics given a local audio file path
  Future<LyricResult?> searchWithPath(
    LyricsSearchInfo info,
    String localFilePath,
  ) async {
    try {
      final audioFile = File(localFilePath);
      final dir = audioFile.parent;
      final baseName = audioFile.uri.pathSegments.last.replaceAll(
        RegExp(r'\.[^.]+$'),
        '',
      ); // Remove extension

      // Try different naming conventions
      final lrcPaths = [
        '${dir.path}/$baseName.lrc',
        '${dir.path}/$baseName.LRC',
        '${dir.path}/${info.title} - ${info.artist}.lrc',
        '${dir.path}/${info.artist} - ${info.title}.lrc',
      ];

      for (final path in lrcPaths) {
        final lrcFile = File(path);
        if (await lrcFile.exists()) {
          final content = await lrcFile.readAsString();
          return _parseLrcFile(content, info);
        }
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error reading local lyrics: $e');
      }
      return null;
    }
  }

  LyricResult? _parseLrcFile(String content, LyricsSearchInfo info) {
    final lines = content.split('\n');
    final lyricLines = <LyricLine>[];
    String? plainText;

    for (final line in lines) {
      // Skip metadata tags
      if (RegExp(r'^\[[a-z]+:').hasMatch(line)) continue;

      // Parse timed lyrics: [mm:ss.xx]text or [mm:ss]text
      final match = RegExp(r'\[(\d+):(\d+)\.?(\d+)?\](.*)').firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final ms = match.group(3) != null
            ? int.parse(match.group(3)!.padRight(3, '0').substring(0, 3))
            : 0;
        final text = match.group(4)?.trim() ?? '';

        if (text.isNotEmpty) {
          lyricLines.add(
            LyricLine(
              timeInMs: minutes * 60000 + seconds * 1000 + ms,
              text: text,
            ),
          );
        }
      }
    }

    if (lyricLines.isEmpty) {
      // Return as plain text
      plainText = lines
          .where((l) => !l.startsWith('[') && l.trim().isNotEmpty)
          .join('\n');

      if (plainText.isEmpty) return null;
    }

    return LyricResult(
      title: info.title,
      artists: [info.artist],
      lines: lyricLines.isNotEmpty ? lyricLines : null,
      lyrics: plainText,
      source: 'Local .lrc file',
    );
  }
}

/// LRC file writer for lyrics editing
class LrcFileWriter {
  /// Generate LRC file content from lyrics
  static String generateLrcContent({
    required List<LyricLine> lyrics,
    String? title,
    String? artist,
    String? album,
  }) {
    final buffer = StringBuffer();

    // Write metadata
    if (title != null) buffer.writeln('[ti:$title]');
    if (artist != null) buffer.writeln('[ar:$artist]');
    if (album != null) buffer.writeln('[al:$album]');
    buffer.writeln('[by:Inzx Music App]');
    buffer.writeln();

    // Write lyrics
    for (final line in lyrics) {
      final minutes = line.timeInMs ~/ 60000;
      final seconds = (line.timeInMs % 60000) ~/ 1000;
      final centiseconds = (line.timeInMs % 1000) ~/ 10;

      buffer.writeln(
        '[${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${centiseconds.toString().padLeft(2, '0')}]${line.text}',
      );
    }

    return buffer.toString();
  }

  /// Save LRC file next to audio file
  static Future<bool> saveLrcFile({
    required String audioFilePath,
    required List<LyricLine> lyrics,
    String? title,
    String? artist,
    String? album,
  }) async {
    try {
      final audioFile = File(audioFilePath);
      final baseName = audioFile.uri.pathSegments.last.replaceAll(
        RegExp(r'\.[^.]+$'),
        '',
      );
      final lrcPath = '${audioFile.parent.path}/$baseName.lrc';

      final content = generateLrcContent(
        lyrics: lyrics,
        title: title,
        artist: artist,
        album: album,
      );

      await File(lrcPath).writeAsString(content);
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error saving LRC file: $e');
      }
      return false;
    }
  }
}
