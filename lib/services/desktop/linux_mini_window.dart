import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// Standard GTK window operations for Linux desktops without a dedicated IPC
/// backend. Requests are asynchronous: verify configure replies before moving
/// on, and stop after a bounded wait if the compositor refuses the request.
class LinuxMiniWindow {
  Rect? _bounds;
  bool _maximized = false;
  bool? _alwaysOnTop;

  Future<void> _waitFor(Future<bool> Function() ready) async {
    for (var i = 0; i < 30; i++) {
      if (await ready()) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError('The Linux window manager did not apply the request');
  }

  Future<void> prepare() async {
    // Inspect native state: desktop shortcuts can bypass Flutter's flags.
    if (await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
      await _waitFor(() async => !await windowManager.isFullScreen());
    }
    _bounds = await windowManager.getBounds();
    _maximized = await windowManager.isMaximized();
    if (_maximized) {
      await windowManager.unmaximize();
      await _waitFor(() async => !await windowManager.isMaximized());
      _bounds = await windowManager.getBounds();
    }
    // Keep-above is optional on Wayland and must not prevent resizing.
    try {
      _alwaysOnTop = await windowManager.isAlwaysOnTop();
    } catch (_) {}
  }

  Future<void> enter() async {
    // Reissue a few times because GTK size hints may arrive after the request.
    for (var attempt = 0; attempt < 10; attempt++) {
      await windowManager.setSize(const Size(320, 340));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final size = await windowManager.getSize();
      if ((size.width - 320).abs() <= 1 && (size.height - 340).abs() <= 1) {
        if (_alwaysOnTop != null) {
          try {
            await windowManager.setAlwaysOnTop(true);
          } catch (_) {}
        }
        return;
      }
    }
    throw StateError('The compositor refused the 320 × 340 miniplayer size');
  }

  Future<void> restore() async {
    if (_bounds case final bounds?) {
      // Wayland does not support arbitrary positioning; GTK still restores
      // the size. X11 additionally restores the saved position.
      await windowManager.setBounds(bounds);
      // GTK acknowledges the request before the compositor configures it.
      // Verify size only: Wayland does not report a reliable position.
      await _waitFor(() async {
        final size = await windowManager.getSize();
        return (size.width - bounds.width).abs() <= 1 &&
            (size.height - bounds.height).abs() <= 1;
      });
    }
    if (_maximized) {
      await windowManager.maximize();
      await _waitFor(windowManager.isMaximized);
    }
    if (_alwaysOnTop case final above?) {
      try {
        await windowManager.setAlwaysOnTop(above);
      } catch (_) {}
    }
  }
}
