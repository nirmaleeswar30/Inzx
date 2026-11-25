import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/services/desktop/hyprland_mini_window.dart';

void main() {
  const env = {'HYPRLAND_INSTANCE_SIGNATURE': 'test'};
  late List<List<String>> calls;
  late Map<String, dynamic> current;
  late String version;
  late String response;
  late int delayedResizes;
  late bool restoreClientMaxOnClear;

  Future<ProcessResult> run(List<String> args) async {
    calls.add(args);
    if (args.first == 'clients') {
      return ProcessResult(
        0,
        0,
        jsonEncode([
          {'pid': 999, 'mapped': true, 'class': 'other'},
          current,
        ]),
        '',
      );
    }
    if (args.first == 'version') {
      return ProcessResult(0, 0, 'Hyprland $version', '');
    }
    final command = args.join(' ');
    if (response == 'ok') {
      if (command.contains('window.float')) {
        current['floating'] = command.contains('action = "on"');
      } else if (args.contains('setfloating')) {
        current['floating'] = true;
      } else if (args.contains('settiled')) {
        current['floating'] = false;
      }
      if (command.contains('fullscreen_state')) {
        final state = RegExp(
          r'internal = (\d+), client = (\d+)',
        ).firstMatch(command)!;
        final internal = int.parse(state[1]!);
        final client = int.parse(state[2]!);
        current['fullscreen'] = internal;
        current['fullscreenClient'] = restoreClientMaxOnClear ? 1 : client;
        restoreClientMaxOnClear = false;
        current['size'] = internal == 0 ? [1280, 800] : [1920, 1040];
      }
      if (command.contains('window.resize') ||
          args.contains('resizewindowpixel')) {
        if (delayedResizes > 0) {
          delayedResizes--;
        } else {
          final match =
              RegExp(r'x = (\d+), y = (\d+)').firstMatch(command) ??
              RegExp(r'exact (\d+) (\d+)').firstMatch(command)!;
          current['size'] = [int.parse(match[1]!), int.parse(match[2]!)];
        }
      }
    }
    return ProcessResult(0, 0, response, '');
  }

  Future<HyprlandMiniWindow?> capture() =>
      HyprlandMiniWindow.capture(environment: env, processId: 42, run: run);

  List<String> commands() => calls
      .where((c) => c.first == 'eval' || c.first == 'dispatch')
      .map((c) => c.join(' '))
      .toList();

  setUp(() {
    calls = [];
    current = {
      'pid': 42,
      'mapped': true,
      'class': 'Com.inzx.inzx',
      'address': '0x123abc',
      'floating': false,
      'size': [1280, 800],
      'at': [50, 70],
      'fullscreen': 0,
      'fullscreenClient': 0,
    };
    version = '0.57.2';
    response = 'ok';
    delayedResizes = 0;
    restoreClientMaxOnClear = false;
  });

  test('other desktops do not call hyprctl', () async {
    expect(await HyprlandMiniWindow.capture(environment: {}, run: run), isNull);
    expect(calls, isEmpty);
  });

  test(
    'repeated mini/normal cycles preserve tiling and use 320x340 every time',
    () async {
      for (var cycle = 0; cycle < 3; cycle++) {
        final window = (await capture())!;
        await window.prepare();
        await window.enter();
        expect(current['floating'], isTrue);
        expect(current['size'], [320, 340]);
        await window.restore();
        expect(current['floating'], isFalse);
      }
      expect(commands().every((c) => c.contains('address:0x123abc')), isTrue);
    },
  );

  test(
    'mini/fullscreen/normal/mini does not retain fullscreen geometry',
    () async {
      current['floating'] = true;
      for (var cycle = 0; cycle < 3; cycle++) {
        current['fullscreen'] = 2;
        current['fullscreenClient'] = 2;
        current['size'] = [1920, 1080];
        final window = (await capture())!;
        await window.prepare();
        await window.enter();
        expect(current['fullscreen'], 0);
        expect(current['size'], [320, 340]);
        // A compositor keybind can make the mini window fullscreen too.
        current['fullscreen'] = 1;
        await window.restore();
        expect(current['fullscreen'], 0);
        expect(current['size'], [1280, 800]);
        expect(commands().last, contains('x = 50, y = 70'));
      }
    },
  );

  test(
    'retries resize when GTK still reports the full-window minimum',
    () async {
      delayedResizes = 2;
      final window = (await capture())!;
      await window.enter();
      expect(current['size'], [320, 340]);
      expect(commands().where((c) => c.contains('window.resize')).length, 3);
    },
  );

  test(
    'expanding restores Hyprland maximization after normal geometry',
    () async {
      for (final floating in [false, true]) {
        current
          ..['floating'] = floating
          ..['fullscreen'] = 1
          ..['fullscreenClient'] = 1
          ..['size'] = [1920, 1040];
        final window = (await capture())!;
        await window.prepare();
        await window.enter();
        expect(current['size'], [320, 340]);
        expect(current['fullscreen'], 0);
        expect(current['fullscreenClient'], 0);
        await window.restore();
        expect(current['floating'], floating);
        expect(current['fullscreen'], 1);
        expect(current['fullscreenClient'], 1);
        expect(current['size'], [1920, 1040]);
        expect(commands().last, contains('internal = 1, client = 1'));
        if (floating) {
          expect(
            commands().any((c) => c.contains('x = 1280, y = 800')),
            isTrue,
          );
        }
      }
    },
  );

  test('clears client maximization restored when leaving fullscreen', () async {
    current['fullscreen'] = 2;
    current['fullscreenClient'] = 2;
    restoreClientMaxOnClear = true;
    final window = (await capture())!;
    await window.prepare();
    await window.enter();
    expect(current['fullscreenClient'], 0);
    expect(current['size'], [320, 340]);
    expect(
      commands().where((c) => c.contains('internal = 0, client = 0')),
      hasLength(2),
    );
  });

  test('older Hyprland uses legacy dispatchers', () async {
    version = '0.54.0';
    final window = (await capture())!;
    await window.enter();
    await window.restore();
    expect(commands(), [
      'dispatch setfloating address:0x123abc',
      'dispatch resizewindowpixel exact 320 340,address:0x123abc',
      'dispatch settiled address:0x123abc',
    ]);
  });

  test(
    'legacy fullscreen never targets the focused unrelated window',
    () async {
      version = '0.54.0';
      current['fullscreen'] = 2;
      current['fullscreenClient'] = 2;
      final window = (await capture())!;
      await expectLater(window.prepare(), throwsStateError);
      expect(commands(), isEmpty);
    },
  );

  test('missing own window fails without changing another app', () async {
    current['pid'] = 100;
    await expectLater(capture(), throwsStateError);
    expect(calls.length, 1);
  });

  test('Lua errors with exit code zero are failures', () async {
    final window = (await capture())!;
    response = 'error: invalid dispatcher';
    await expectLater(window.enter(), throwsStateError);
  });
}
