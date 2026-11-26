import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/services/desktop/app_window.dart';

/// Answers the app's window operations from [handler], one [MethodCall] per
/// operation with window_manager 0.5's method names and arguments, so a test
/// can play a window manager that answers late, refuses or fails.
///
/// As in 0.5, sizes go through `getBounds` and `setBounds` (without a
/// position when only the size changes).
class FakeDesktopWindow implements DesktopWindow {
  FakeDesktopWindow(this.handler);

  final Future<Object?> Function(MethodCall call) handler;

  Future<Object?> _call(String method, [Map<String, Object?>? arguments]) =>
      handler(MethodCall(method, arguments));

  @override
  Future<bool> isFullScreen() async => await _call('isFullScreen') as bool;
  @override
  Future<void> setFullScreen(bool value) =>
      _call('setFullScreen', {'isFullScreen': value});

  @override
  Future<bool> isMaximized() async => await _call('isMaximized') as bool;
  @override
  Future<void> maximize() => _call('maximize');
  @override
  Future<void> unmaximize() => _call('unmaximize');

  @override
  Future<bool> isAlwaysOnTop() async => await _call('isAlwaysOnTop') as bool;
  @override
  Future<void> setAlwaysOnTop(bool value) =>
      _call('setAlwaysOnTop', {'isAlwaysOnTop': value});

  @override
  Future<Rect> getBounds() async {
    final bounds = await _call('getBounds') as Map;
    return Rect.fromLTWH(
      bounds['x'] as double,
      bounds['y'] as double,
      bounds['width'] as double,
      bounds['height'] as double,
    );
  }

  @override
  Future<void> setBounds(Rect bounds) => _call('setBounds', {
    'x': bounds.left,
    'y': bounds.top,
    'width': bounds.width,
    'height': bounds.height,
  });

  @override
  Future<Size> getSize() async => (await getBounds()).size;
  @override
  Future<void> setSize(Size size) =>
      _call('setBounds', {'width': size.width, 'height': size.height});

  @override
  Future<void> setMinimumSize(Size size) =>
      _call('setMinimumSize', {'width': size.width, 'height': size.height});
}

/// Routes the app's window operations to [handler] until the test ends.
void fakeDesktopWindow(Future<Object?> Function(MethodCall call) handler) {
  desktopWindow = FakeDesktopWindow(handler);
  addTearDown(() => desktopWindow = const DesktopWindow());
}
