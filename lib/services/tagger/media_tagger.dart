import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../../models/track.dart';
import 'flac_tagger.dart';
import 'mp4_tagger.dart';
import 'id3_tagger.dart';
import 'webm_tagger.dart';

/// Orchestrates in-file metadata tagging (title, artist, album, synced lyrics, cover art)
/// across FLAC, M4A, MP3, and WebM/Opus audio files.
class MediaTagger {
  static const int maxCoverDimension = 1000;

  /// Whether [bytes] begin like an image file. A cheap check that catches an
  /// error page or stray bytes before they get treated as artwork.
  static bool isImageBytes(List<int> bytes) {
    if (bytes.length < 12) return false;
    return _isJpeg(bytes) ||
        _isPng(bytes) ||
        // GIF8
        (bytes[0] == 0x47 &&
            bytes[1] == 0x49 &&
            bytes[2] == 0x46 &&
            bytes[3] == 0x38) ||
        // RIFF....WEBP
        (bytes[0] == 0x52 &&
            bytes[1] == 0x49 &&
            bytes[2] == 0x46 &&
            bytes[3] == 0x46 &&
            bytes[8] == 0x57 &&
            bytes[9] == 0x45 &&
            bytes[10] == 0x42 &&
            bytes[11] == 0x50);
  }

  static bool _isJpeg(List<int> bytes) =>
      bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;

  static bool _isPng(List<int> bytes) =>
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47;

  /// Gets cover art ready to embed: at most 1000px on the longest side so it
  /// doesn't bloat the audio file, and JPEG or PNG, the only types the tag
  /// formats reliably carry. Null if [rawBytes] isn't an image.
  static Uint8List? optimizeCoverArt(Uint8List? rawBytes) {
    if (rawBytes == null || !isImageBytes(rawBytes)) return null;
    final isEmbeddable = _isJpeg(rawBytes) || _isPng(rawBytes);
    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) return isEmbeddable ? rawBytes : null;

      final fits =
          decoded.width <= maxCoverDimension &&
          decoded.height <= maxCoverDimension;
      if (isEmbeddable && fits) return rawBytes;

      final resized = fits
          ? decoded
          : decoded.width >= decoded.height
          ? img.copyResize(decoded, width: maxCoverDimension)
          : img.copyResize(decoded, height: maxCoverDimension);

      return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
    } catch (e) {
      if (kDebugMode) {
        print('MediaTagger: Cover optimization error: $e');
      }
      return isEmbeddable ? rawBytes : null;
    }
  }

  /// Embeds metadata, lyrics, and cover art into the audio file in-place
  static Future<bool> tagFile({
    required File audioFile,
    required Track track,
    String? lyrics,
    Uint8List? coverArtBytes,
  }) async {
    try {
      if (!await audioFile.exists()) return false;

      final path = audioFile.path.toLowerCase();

      // Decoding a large cover is too slow for the UI isolate.
      final optimizedCover = await compute(optimizeCoverArt, coverArtBytes);
      final coverIsPng = optimizedCover != null && _isPng(optimizedCover);

      // FLAC works on the file itself: it can be too big to hold in memory.
      if (path.endsWith('.flac')) {
        return await FlacTagger.tagFile(
          audioFile,
          title: track.title,
          artist: track.artist,
          album: track.album,
          lyrics: lyrics,
          coverBytes: optimizedCover,
          coverIsPng: coverIsPng,
        );
      }

      final bytes = await audioFile.readAsBytes();
      if (bytes.isEmpty) return false;

      Uint8List? taggedBytes;

      if (path.endsWith('.m4a') || path.endsWith('.mp4')) {
        taggedBytes = Mp4Tagger.tag(
          bytes,
          title: track.title,
          artist: track.artist,
          album: track.album,
          lyrics: lyrics,
          coverBytes: optimizedCover,
          coverIsPng: coverIsPng,
        );
      } else if (path.endsWith('.mp3')) {
        taggedBytes = Id3Tagger.tag(
          bytes,
          title: track.title,
          artist: track.artist,
          album: track.album,
          lyrics: lyrics,
          coverBytes: optimizedCover,
          coverIsPng: coverIsPng,
        );
      } else if (path.endsWith('.opus') || path.endsWith('.webm')) {
        taggedBytes = WebmTagger.tag(
          bytes,
          title: track.title,
          artist: track.artist,
          album: track.album,
          lyrics: lyrics,
          coverBytes: optimizedCover,
          coverIsPng: coverIsPng,
        );
      }

      if (taggedBytes != null && !identical(taggedBytes, bytes)) {
        // Atomic rewrite: write to .tagged temporary file then rename
        final tempFile = File('${audioFile.path}.tagged');
        await tempFile.writeAsBytes(taggedBytes, flush: true);
        if (await tempFile.exists() && await tempFile.length() > 0) {
          await tempFile.rename(audioFile.path);
          if (kDebugMode) {
            print(
              'MediaTagger: Successfully embedded tags & artwork into ${audioFile.path}',
            );
          }
          return true;
        }
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('MediaTagger: Failed to tag ${audioFile.path}: $e');
      }
      // Never fail the download because tagging failed
      return false;
    }
  }
}
