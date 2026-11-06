import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:iconsax/iconsax.dart';
import '../../models/models.dart';
import '../../services/local_artwork_service.dart';

/// Unified widget for displaying track artwork (embedded from local files or network URLs).
class TrackArtworkView extends StatelessWidget {
  final Track track;
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final Widget? fallback;
  final Color? fallbackColor;
  final IconData fallbackIcon;

  const TrackArtworkView({
    super.key,
    required this.track,
    required this.width,
    required this.height,
    this.borderRadius,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.fallback,
    this.fallbackColor,
    this.fallbackIcon = Iconsax.music,
  });

  @override
  Widget build(BuildContext context) {
    Widget content;

    final localPath = track.localFilePath?.trim();
    if (localPath != null && localPath.isNotEmpty) {
      // 1. Check synchronous in-memory cached bytes
      final cached = LocalArtworkService.getCachedBytes(localPath);
      if (cached != null && cached.isNotEmpty) {
        content = Image.memory(
          cached,
          width: width,
          height: height,
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _buildFallback(),
        );
      } else {
        // 2. Check legacy .cover.jpg file if present
        final legacyCover = File('$localPath.cover.jpg');
        if (legacyCover.existsSync()) {
          content = Image.file(
            legacyCover,
            width: width,
            height: height,
            fit: fit,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _buildFallback(),
          );
        } else {
          // 3. Asynchronously load embedded artwork with fallback to network
          content = FutureBuilder<Uint8List?>(
            future: LocalArtworkService.getArtworkBytes(localPath, track: track),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done &&
                  snapshot.hasData &&
                  snapshot.data != null &&
                  snapshot.data!.isNotEmpty) {
                return Image.memory(
                  snapshot.data!,
                  width: width,
                  height: height,
                  fit: fit,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) =>
                      track.thumbnailUrl?.trim().isNotEmpty == true
                      ? _buildNetworkImage()
                      : _buildFallback(),
                );
              }
              if (track.thumbnailUrl != null &&
                  track.thumbnailUrl!.trim().isNotEmpty) {
                return _buildNetworkImage();
              }
              if (snapshot.connectionState == ConnectionState.waiting &&
                  placeholder != null) {
                return placeholder!;
              }
              return _buildFallback();
            },
          );
        }
      }
    } else if (track.thumbnailUrl != null &&
        track.thumbnailUrl!.trim().isNotEmpty) {
      content = _buildNetworkImage();
    } else {
      content = _buildFallback();
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: SizedBox(width: width, height: height, child: content),
      );
    }

    return SizedBox(width: width, height: height, child: content);
  }

  Widget _buildNetworkImage() {
    return CachedNetworkImage(
      imageUrl: track.thumbnailUrl!,
      width: width,
      height: height,
      fit: fit,
      placeholder: (_, _) => placeholder ?? _buildFallback(),
      errorWidget: (_, _, _) => _buildFallback(),
    );
  }

  Widget _buildFallback() {
    if (fallback != null) return fallback!;
    if (errorWidget != null) return errorWidget!;
    return Container(
      width: width,
      height: height,
      color: fallbackColor ?? Colors.white.withValues(alpha: 0.1),
      child: Center(
        child: Icon(
          fallbackIcon,
          size: width * 0.45,
          color: Colors.white70,
        ),
      ),
    );
  }
}
