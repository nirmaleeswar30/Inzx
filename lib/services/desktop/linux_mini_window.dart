import 'package:flutter/widgets.dart';

import 'app_window.dart';

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
    final window = desktopWindow;
    // Inspect native state: desktop shortcuts can bypass Flutter's flags.
    if (await window.isFullScreen()) {
      await window.setFullScreen(false);
      await _waitFor(() async => !await window.isFullScreen());
    }
    _bounds = await window.getBounds();
    _maximized = await window.isMaximized();
    if (_maximized) {
      await window.unmaximize();
      await _waitFor(() async => !await window.isMaximized());
      _bounds = await window.getBounds();
    }
    // Keep-above is optional on Wayland and must not prevent resizing.
    try {
      _alwaysOnTop = await window.isAlwaysOnTop();
    } catch (_) {}
  }

  Future<void> enter() async {
    final window = desktopWindow;
    // Reissue a few times because GTK size hints may arrive after the request.
    for (var attempt = 0; attempt < 10; attempt++) {
      await window.setSize(const Size(320, 340));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final size = await window.getSize();
      if ((size.width - 320).abs() <= 1 && (size.height - 340).abs() <= 1) {
        if (_alwaysOnTop != null) {
          try {
            await window.setAlwaysOnTop(true);
          } catch (_) {}
        }
        return;
      }
    }
    throw StateError('The compositor refused the 320 × 340 miniplayer size');
  }

  Future<void> restore() async {
    final window = desktopWindow;
    if (_bounds case final bounds?) {
      // Wayland does not support arbitrary positioning; GTK still restores
      // the size. X11 additionally restores the saved position.
      await window.setBounds(bounds);
      // GTK acknowledges the request before the compositor configures it.
      // Verify size only: Wayland does not report a reliable position.
      await _waitFor(() async {
        final size = await window.getSize();
        return (size.width - bounds.width).abs() <= 1 &&
            (size.height - bounds.height).abs() <= 1;
      });
    }
    if (_maximized) {
      await window.maximize();
      await _waitFor(window.isMaximized);
    }
    if (_alwaysOnTop case final above?) {
      try {
        await window.setAlwaysOnTop(above);
      } catch (_) {}
    }
  }
}
