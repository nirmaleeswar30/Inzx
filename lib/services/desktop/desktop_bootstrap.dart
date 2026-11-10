import 'dart:async' show unawaited;
import 'dart:io' show Platform;
import 'dart:ui' show Size;

import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:flutter/foundation.dart' show LicenseRegistry, LicenseEntryWithLineBreaks;
import 'package:flutter/services.dart' show rootBundle;
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_audio_dsp.dart';
import 'desktop_updater.dart';
import 'windows_media_controls.dart';

/// Below this the sidebar, player bar and content stop fitting.
const Size kDesktopMinWindowSize = Size(720, 540);

/// Everything that has to be in place on Windows and Linux before the app
/// touches audio, the image cache or its window.
Future<void> initDesktopPlatform() async {
  // An update downloaded last session that didn't get installed on close is
  // installed now, before anything opens (this process then exits and the
  // new version starts).
  await DesktopUpdater.instance.applyPendingOnStartup();

  // The SIL Open Font License asks for its text to ship with the font.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Poppins',
    ], await rootBundle.loadString('assets/fonts/poppins/OFL.txt'));
  });

  // just_audio has no desktop backend of its own; this one is libmpv.
  JustAudioMediaKit.title = 'Inzx';
  // Every mpv player gets the equaliser / AutoEQ chain and exclusive output.
  DesktopAudioDsp.instance.install();
  JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
  unawaited(DesktopAudioDsp.instance.start());

  // Linux gets MPRIS from audio_service_mpris, which registers itself.
  if (Platform.isWindows) {
    AudioServicePlatform.instance = WindowsMediaControls();
  }

  await windowManager.ensureInitialized();
  // Closing goes through _CloseHandler, which installs a downloaded update
  // on the way out.
  await windowManager.setPreventClose(true);
  windowManager.addListener(_CloseHandler());
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      title: 'Inzx',
      size: Size(1280, 800),
      minimumSize: kDesktopMinWindowSize,
      center: true,
      // The app draws its own title bar and window buttons.
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
}

class _CloseHandler with WindowListener {
  bool _closing = false;

  @override
  Future<void> onWindowClose() async {
    if (_closing) return;
    _closing = true;
    try {
      await DesktopUpdater.instance.applyOnExit().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Never keep the window from closing over an update.
    }
    await windowManager.destroy();
  }
}
