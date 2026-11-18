import 'package:flutter/widgets.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'ios_native.dart';

/// iPadOS shows the share sheet as a popover, which needs an anchor:
/// share_plus fails a share with no `sharePositionOrigin` there. The app's
/// share calls don't pass one (phones don't need it), so on an iPad this
/// fills it in with a point at the middle of the screen.
class IpadAnchoredShare extends SharePlatform {
  IpadAnchoredShare(this._inner);

  final SharePlatform _inner;

  /// Installs the wrapper; call before the first share.
  static void install() {
    if (!IosNative.isPad) return;
    final inner = SharePlatform.instance;
    if (inner is IpadAnchoredShare) return;
    SharePlatform.instance = IpadAnchoredShare(inner);
  }

  @override
  Future<ShareResult> share(ShareParams params) {
    if (params.sharePositionOrigin != null) return _inner.share(params);
    return _inner.share(
      ShareParams(
        text: params.text,
        subject: params.subject,
        title: params.title,
        previewThumbnail: params.previewThumbnail,
        sharePositionOrigin: _screenCentre(),
        uri: params.uri,
        files: params.files,
        fileNameOverrides: params.fileNameOverrides,
        downloadFallbackEnabled: params.downloadFallbackEnabled,
        mailToFallbackEnabled: params.mailToFallbackEnabled,
        excludedCupertinoActivities: params.excludedCupertinoActivities,
      ),
    );
  }

  static Rect _screenCentre() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return const Rect.fromLTWH(0, 0, 1, 1);
    final view = views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    return Rect.fromLTWH(size.width / 2, size.height / 2, 1, 1);
  }
}
