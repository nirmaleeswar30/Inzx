import 'dart:convert';
import 'dart:io';

/// A snapshot of this process's window, never the currently focused window.
/// Wayland clients cannot position/resize themselves reliably under a tiling
/// compositor, so the mini-player button asks Hyprland to do that explicitly.
class HyprlandMiniWindow {
  HyprlandMiniWindow._(this._run, this._window, this._lua);

  final Future<ProcessResult> Function(List<String>) _run;
  final Map<String, dynamic> _window;
  final bool _lua;
  static const _maximizedBit = 1;
  int _maximizedInternal = 0;
  int _maximizedClient = 0;

  static Future<HyprlandMiniWindow?> capture({
    Map<String, String>? environment,
    int? processId,
    Future<ProcessResult> Function(List<String>)? run,
  }) async {
    final env = environment ?? Platform.environment;
    if (env['HYPRLAND_INSTANCE_SIGNATURE']?.isNotEmpty != true) return null;
    final execute =
        run ??
        (List<String> args) =>
            Process.run('hyprctl', args).timeout(const Duration(seconds: 2));
    final result = await execute(['clients', '-j']);
    if (result.exitCode != 0) throw StateError('Cannot read Hyprland windows');
    final clients = jsonDecode(result.stdout as String) as List;
    final matches = clients.where(
      (c) =>
          c['pid'] == (processId ?? pid) &&
          c['mapped'] == true &&
          (c['class'] as String? ?? '').toLowerCase() == 'com.inzx.inzx',
    );
    if (matches.length != 1) {
      throw StateError('Cannot uniquely identify the INZX window');
    }
    final window = Map<String, dynamic>.from(matches.single as Map);
    // Addresses come from the compositor but are still validated before being
    // placed in a Lua expression. No shell or window-title interpolation.
    if (!RegExp(r'^0x[0-9a-fA-F]+$').hasMatch(window['address'] as String)) {
      throw StateError('Invalid Hyprland window address');
    }
    final version = await execute(['version']);
    final match = RegExp(
      r'Hyprland (\d+)\.(\d+)',
    ).firstMatch('${version.stdout}');
    if (version.exitCode != 0 || match == null) {
      throw StateError('Cannot identify the Hyprland dispatcher API');
    }
    final lua = int.parse(match[1]!) > 0 || int.parse(match[2]!) >= 57;
    return HyprlandMiniWindow._(execute, window, lua);
  }

  String get _selector => 'address:${_window['address']}';

  Future<void> _command(String lua, [List<String>? legacy]) async {
    final args = _lua ? ['eval', 'hl.dispatch($lua)'] : legacy;
    if (args == null) {
      // Legacy fullscreenstate always affects the focused window.
      throw StateError(
        'Leave fullscreen before entering miniplayer on Hyprland older than 0.57',
      );
    }
    final result = await _run(args);
    // Some hyprctl Lua errors are printed with a successful process exit code.
    if (result.exitCode != 0 ||
        RegExp(
          r'(^|\n)error:',
          caseSensitive: false,
        ).hasMatch('${result.stdout}\n${result.stderr}')) {
      throw StateError('Hyprland rejected the miniplayer window operation');
    }
  }

  Future<void> _float(bool value) => _command(
    'hl.dsp.window.float({action = "${value ? 'on' : 'off'}", '
    'window = "$_selector"})',
    ['dispatch', value ? 'setfloating' : 'settiled', _selector],
  );

  Future<void> _resize(int width, int height) => _command(
    'hl.dsp.window.resize({x = $width, y = $height, relative = false, '
    'window = "$_selector"})',
    ['dispatch', 'resizewindowpixel', 'exact $width $height,$_selector'],
  );

  Future<Map<String, dynamic>> _current() async {
    final result = await _run(['clients', '-j']);
    if (result.exitCode != 0) throw StateError('Cannot read Hyprland windows');
    final clients = jsonDecode(result.stdout as String) as List;
    return Map<String, dynamic>.from(
      clients.singleWhere(
            (c) =>
                c['address'] == _window['address'] &&
                c['pid'] == _window['pid'],
          )
          as Map,
    );
  }

  Future<void> _leaveFullscreen(Map<String, dynamic> current) async {
    if ((current['fullscreen'] ?? 0) == 0 &&
        (current['fullscreenClient'] ?? 0) == 0) {
      return;
    }
    await _setFullscreenState(0, 0);
  }

  Future<void> _setFullscreenState(int internal, int client) async {
    // Leaving fullscreen can briefly restore client maximization. Reissue
    // the exact state if the first request did not clear both flags.
    for (var attempt = 0; attempt < 20; attempt++) {
      await _command(
        'hl.dsp.window.fullscreen_state({internal = $internal, client = $client, '
        'window = "$_selector"})',
      );
      final state = await _current();
      if ((state['fullscreen'] ?? 0) == internal &&
          (state['fullscreenClient'] ?? 0) == client) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    throw StateError('Hyprland did not apply the requested fullscreen state');
  }

  /// Keep maximization separate from the normal bounds used during restore.
  Future<void> prepare() async {
    final original = await _current();
    await _leaveFullscreen(original);
    _window.addAll(await _current());
    // Each flag can contain both bits. Expand restores only maximization.
    _maximizedInternal = (original['fullscreen'] as int? ?? 0) & _maximizedBit;
    _maximizedClient =
        (original['fullscreenClient'] as int? ?? 0) & _maximizedBit;
  }

  Future<void> _resizeSettled(int width, int height) async {
    // GTK's minimum-size hint can arrive after the first IPC request. Retry
    // briefly, and verify the actual geometry rather than treating "ok" as it.
    for (var attempt = 0; attempt < 20; attempt++) {
      await _resize(width, height);
      final state = await _current();
      final size = state['size'] as List;
      if (size[0] == width && size[1] == height) return;
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    throw StateError('Hyprland did not apply the requested window size');
  }

  Future<void> enter() async {
    await _leaveFullscreen(await _current());
    await _float(true);
    await _resizeSettled(320, 340);
  }

  Future<void> restore() async {
    await _leaveFullscreen(await _current());
    if (_window['floating'] == true) {
      final size = (_window['size'] as List).cast<int>();
      final at = (_window['at'] as List).cast<int>();
      await _float(true);
      await _resizeSettled(size[0], size[1]);
      await _command(
        'hl.dsp.window.move({x = ${at[0]}, y = ${at[1]}, relative = false, '
        'window = "$_selector"})',
        ['dispatch', 'movewindowpixel', 'exact ${at[0]} ${at[1]},$_selector'],
      );
    } else {
      await _float(false);
    }
    if (_maximizedInternal != 0 || _maximizedClient != 0) {
      await _setFullscreenState(_maximizedInternal, _maximizedClient);
    }
  }
}
