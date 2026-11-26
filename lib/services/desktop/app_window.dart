import 'dart:ffi' hide Size;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';
import 'package:flutter/widgets.dart' show Rect, Size;
import 'package:win32/win32.dart' as win32;
import 'package:window_manager/window_manager.dart';

/// The window operations behind the miniplayer and full screen.
///
/// The native calls answer at once, but the window manager applies them
/// later, so callers verify the result rather than trust it. Async, so tests
/// can stand in for a window manager that takes its time.
class DesktopWindow {
  const DesktopWindow();

  Future<bool> isFullScreen() async => appWindow.isFullScreen;
  Future<void> setFullScreen(bool value) async =>
      appWindow.isFullScreen = value;

  Future<bool> isMaximized() async => appWindow.isMaximized;
  Future<void> maximize() async => appWindow.maximize();
  Future<void> unmaximize() async => appWindow.unmaximize();

  Future<bool> isAlwaysOnTop() async => appWindow.isAlwaysOnTop;
  Future<void> setAlwaysOnTop(bool value) async =>
      appWindow.isAlwaysOnTop = value;

  Future<Rect> getBounds() async => appWindow.bounds.toRect();
  Future<void> setBounds(Rect bounds) async =>
      appWindow.bounds = bounds.toNative();

  Future<Size> getSize() async => appWindow.size.toSize();
  Future<void> setSize(Size size) async =>
      appWindow.setSize(size.toNative(), false);

  Future<void> setMinimumSize(Size size) async =>
      appWindow.minimumSize = size.toNative();
}

/// The app window's [DesktopWindow]. Tests replace it with a fake.
DesktopWindow desktopWindow = const DesktopWindow();

Window? _appWindow;

/// The app's one native window.
///
/// Throws when there is none to address yet, which can only happen on a
/// platform this app does not run on: Linux reports its window while it is
/// hidden, and on Windows it is looked up by the runner's window class.
Window get appWindow => _appWindow ??= _findAppWindow();

/// [appWindow], or null where there is no native window (widget tests).
Window? get maybeAppWindow {
  try {
    return appWindow;
  } on StateError {
    return null;
  }
}

Window _findAppWindow() {
  final current = WindowManager.instance.getCurrent();
  if (current != null) return current;
  // Windows reports only its active window as current, and the runner keeps
  // ours hidden until Flutter's first frame, after the startup setup ran.
  if (Platform.isWindows) {
    final hwnd = _findRunnerWindow();
    if (hwnd != 0) {
      final window = Window.createWithNativeWindow(
        Pointer<Void>.fromAddress(hwnd),
      );
      if (window != null) return window;
    }
  }
  throw StateError('The app window is not available');
}

/// This process's top-level window of the runner's class
/// (`kWindowClassName` in `windows/runner/win32_window.cpp`), hidden or not.
int _findRunnerWindow() {
  final className = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
  final processId = calloc<Uint32>();
  try {
    final self = win32.GetCurrentProcessId();
    var hwnd = 0;
    while (true) {
      hwnd = win32.FindWindowEx(0, hwnd, className, nullptr);
      if (hwnd == 0) return 0;
      win32.GetWindowThreadProcessId(hwnd, processId);
      if (processId.value == self) return hwnd;
    }
  } finally {
    calloc.free(processId);
    malloc.free(className);
  }
}
