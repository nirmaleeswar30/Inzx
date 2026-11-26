import 'dart:async' show unawaited;
import 'dart:convert' show utf8;
import 'dart:io'
    show
        Directory,
        File,
        InternetAddress,
        Platform,
        Process,
        ServerSocket,
        Socket,
        exit;
import 'dart:ui' show AppExitResponse, AppExitType, Size;

import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, LicenseRegistry, LicenseEntryWithLineBreaks;
import 'package:flutter/services.dart'
    show MethodChannel, ServicesBinding, rootBundle;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:window_manager/window_manager.dart';

import '../deep_link_handler.dart';
import 'app_window.dart';
import 'desktop_audio_dsp.dart';
import 'desktop_updater.dart';
import 'windows_media_controls.dart';

/// Below this the sidebar, player bar and content stop fitting.
const Size kDesktopMinWindowSize = Size(720, 540);

/// Local loopback TCP port used for desktop single-instance coordination.
const int kDesktopIpcPort = 45331;

/// Message sent by a secondary instance when launched without a deep link URL,
/// bringing the primary instance's window to the foreground.
const String kFocusMessage = 'inzx-internal:focus';

/// Manages single-instance execution on desktop platforms.
///
/// If another instance of Inzx is already running, forwards any launch arguments
/// (such as deep link URLs) or a focus request to the primary instance over a
/// local loopback TCP socket, then terminates the secondary instance.
///
/// Returns `true` if this instance was a secondary instance and has forwarded
/// its payload (or completed its handoff) and should terminate immediately, or
/// `false` if this is the primary instance and should proceed with startup.
Future<bool> handleDesktopSingleInstance(
  List<String> args, {
  int port = kDesktopIpcPort,
  void Function(int code)? onSecondaryExit,
  void Function()? onFocusRequested,
  void Function(ServerSocket server)? onServerBound,
}) async {
  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
    return false;
  }

  try {
    final server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      port,
      shared: false,
    );
    onServerBound?.call(server);

    // Primary instance: listen for forwarded links or focus signals
    server.listen((Socket client) {
      utf8.decoder.bind(client).listen((data) {
        final payload = data.trim();
        final triggerFocus = onFocusRequested ??
            () {
              try {
                appWindow.show();
                appWindow.focus();
              } catch (_) {}
            };

        if (payload == kFocusMessage) {
          triggerFocus();
        } else if (payload.isNotEmpty) {
          final uri = Uri.tryParse(payload);
          if (uri != null) {
            DeepLinkHandler.instance.handleExternalUrl(uri);
          }
          triggerFocus();
        }
      });
    });

    return false;
  } catch (_) {
    // Secondary instance: forward link or focus signal and exit
    try {
      final client = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(seconds: 2),
      );

      String payloadToSend = '';
      for (final arg in args) {
        if (arg.startsWith('inzx://') ||
            arg.startsWith('https://${DeepLinkHandler.shareHost}/') ||
            arg.contains('open/') ||
            arg.contains('redirect.html')) {
          payloadToSend = arg;
          break;
        }
      }
      if (payloadToSend.isEmpty && args.isNotEmpty) {
        if (args.first.contains('://')) {
          payloadToSend = args.first;
        }
      }

      client.write(payloadToSend.isNotEmpty ? payloadToSend : kFocusMessage);
      await client.flush();
      await client.close();
    } catch (e) {
      debugPrint('Error sending link/focus to primary Inzx instance: $e');
    }

    final exitFn = onSecondaryExit ?? exit;
    exitFn(0);
    return true;
  }
}

/// Registers or updates the `inzx-url-handler.desktop` file in the user's
/// XDG data directory (~/.local/share/applications) pointing to the running
/// binary or AppImage so that `inzx://` deep links correctly open Inzx.
Future<void> registerLinuxUrlScheme() async {
  if (!Platform.isLinux) return;
  try {
    final env = Platform.environment;
    final home = env['HOME'];
    if (home == null || home.isEmpty) return;
    final xdgDataHome = env['XDG_DATA_HOME'];
    final dataHome = (xdgDataHome != null && xdgDataHome.isNotEmpty)
        ? xdgDataHome
        : '$home/.local/share';
    final appImage = env['APPIMAGE'];
    final exec =
        (appImage != null && appImage.isNotEmpty && File(appImage).existsSync())
            ? appImage
            : Platform.resolvedExecutable;

    // Desktop Entry quoting: string-level escape first, then quoted-arg escape.
    final quotedExec = exec
        .replaceAll(r'\', r'\\\\')
        .replaceAll('"', r'\\"')
        .replaceAll('`', r'\\`')
        .replaceAll(r'$', r'\\$')
        .replaceAll('%', '%%');

    const fileName = 'inzx-url-handler.desktop';
    final appsDir = Directory('$dataHome/applications');
    final file = File('${appsDir.path}/$fileName');
    final content = '[Desktop Entry]\n'
        'Type=Application\n'
        'Name=Inzx\n'
        'Comment=Opens inzx:// links (shared links)\n'
        'Exec="$quotedExec" %u\n'
        'Icon=inzx\n'
        'Terminal=false\n'
        'NoDisplay=true\n'
        'MimeType=x-scheme-handler/inzx;\n'
        'StartupWMClass=com.inzx.inzx\n';

    final current = await file.exists() ? await file.readAsString() : null;
    if (current != content) {
      await appsDir.create(recursive: true);
      await file.writeAsString(content, flush: true);
      try {
        await Process.run('update-desktop-database', [appsDir.path]);
      } catch (_) {}
    }

    final query = await Process.run(
        'xdg-mime', ['query', 'default', 'x-scheme-handler/inzx']);
    if (query.stdout.toString().trim() != fileName) {
      await Process.run(
          'xdg-mime', ['default', fileName, 'x-scheme-handler/inzx']);
    }
  } catch (e) {
    debugPrint('Error registering Linux inzx:// handler: $e');
  }
}

/// Registers the `inzx://` protocol scheme in HKCU for development or
/// portable executions where the Inno Setup installer did not run.
Future<void> registerWindowsUrlScheme() async {
  if (!Platform.isWindows) return;
  try {
    final exePath = Platform.resolvedExecutable;
    await Process.run('reg', [
      'add',
      r'HKCU\Software\Classes\inzx',
      '/ve',
      '/d',
      'URL:inzx Protocol',
      '/f',
    ]);
    await Process.run('reg', [
      'add',
      r'HKCU\Software\Classes\inzx',
      '/v',
      'URL Protocol',
      '/d',
      '',
      '/f',
    ]);
    await Process.run('reg', [
      'add',
      r'HKCU\Software\Classes\inzx\shell\open\command',
      '/ve',
      '/d',
      '"$exePath" "%1"',
      '/f',
    ]);
  } catch (e) {
    debugPrint('Error registering Windows inzx:// protocol: $e');
  }
}

/// Everything that has to be in place on Windows and Linux before the app
/// touches audio, the image cache or its window.
Future<void> initDesktopPlatform() async {
  if (Platform.isLinux) {
    unawaited(registerLinuxUrlScheme());
  } else if (Platform.isWindows) {
    unawaited(registerWindowsUrlScheme());
  }
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

  // However the window is closed (its close button, the title bar, the
  // taskbar or the system), it ends in closeDesktopApp: on Windows the runner
  // hands every WM_CLOSE over (windows/runner/flutter_window.cpp), and on
  // Linux the engine asks the app whether to exit.
  const MethodChannel('inzx/window').setMethodCallHandler((call) async {
    if (call.method == 'closeRequested') unawaited(closeDesktopApp());
  });
  AppLifecycleListener(onExitRequested: _onExitRequested);
  final window = appWindow;
  window.title = 'Inzx';
  // The app draws its own title bar and window buttons.
  window.titleBarStyle = TitleBarStyle.hidden;
  window.isWindowControlButtonsVisible = false;
  window.minimumSize = kDesktopMinWindowSize.toNative();
  window.setSize(const Size(1280, 800).toNative(), false);
  window.center();
  window.show();
  window.focus();
}

bool _closing = false;

Future<AppExitResponse> _onExitRequested() async {
  unawaited(closeDesktopApp());
  return AppExitResponse.cancel;
}

/// Ends the app, installing a downloaded update on the way out.
Future<void> closeDesktopApp() async {
  if (_closing) return;
  _closing = true;
  // Hide the window before the updater or native teardown can hold it open.
  try {
    appWindow.hide();
  } catch (_) {
    // Continue closing if the window is already gone.
  }
  try {
    await DesktopUpdater.instance.applyOnExit().timeout(
      const Duration(seconds: 5),
    );
  } catch (_) {
    // Never keep the window from closing over an update.
  }
  // Ends the message loop (Windows) or the GTK application (Linux) without
  // asking again.
  await ServicesBinding.instance.exitApplication(AppExitType.required);
}
