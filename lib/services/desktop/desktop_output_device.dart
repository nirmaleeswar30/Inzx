import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../automix/desktop/automix_native.dart' show AutomixPaths;

/// The audio output in use. [key] identifies the device across runs.
class OutputDevice {
  const OutputDevice(this.key, this.label, {this.formFactor = 0});
  final String key;
  final String label;

  /// Windows' EndpointFormFactor: 1 speakers, 3 headphones, 5 headset,
  /// 9 display audio, 0 when unknown.
  final int formFactor;

  bool get isSpeakers => formFactor == 1;
}

/// Follows the default audio output (Windows: inzx_automix's
/// ax_default_output, polled every few seconds). Linux reports nothing, so
/// per-device features there simply stay off.
class DesktopOutputDevice extends ChangeNotifier {
  DesktopOutputDevice._();
  static final DesktopOutputDevice instance = DesktopOutputDevice._();

  OutputDevice? _current;
  Timer? _poll;

  OutputDevice? get current {
    _start();
    return _current;
  }

  void _start() {
    if (_poll != null) return;
    _current = _read();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      final next = _read();
      if (next?.key == _current?.key && next?.formFactor == _current?.formFactor) return;
      _current = next;
      notifyListeners();
    });
  }

  static Pointer<Utf8> Function()? _query;
  static void Function(Pointer<Void>)? _free;
  static bool _tried = false;

  static OutputDevice? _read() {
    if (!_tried) {
      _tried = true;
      if (Platform.isWindows && AutomixPaths.available) {
        try {
          final lib = DynamicLibrary.open(AutomixPaths.library);
          _query = lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'ax_default_output',
          );
          _free = lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
            'ax_free',
          );
        } catch (_) {}
      }
    }
    final query = _query;
    if (query == null) return null;
    final raw = query();
    if (raw == nullptr) return null;
    final String text;
    try {
      text = raw.toDartString();
    } finally {
      _free?.call(raw.cast());
    }
    final parts = text.split('\n');
    if (parts.length < 4 || parts[0].isEmpty) return null;
    final label = parts[1].isNotEmpty ? parts[1] : (parts[2].isNotEmpty ? parts[2] : 'Output');
    return OutputDevice('win:${parts[0]}', label, formFactor: int.tryParse(parts[3]) ?? 0);
  }
}
