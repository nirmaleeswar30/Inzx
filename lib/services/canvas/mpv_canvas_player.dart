import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:ffi' as ffi show Size;
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

/// Plays video through libmpv's software render API, for Linux, where
/// video_player has no backend: canvases (looping, silent motion artwork)
/// and, with sound and [playback] reports, podcast episodes.
///
/// Pure Dart over FFI: no plugin, so nothing reaches the Android build.
/// libmpv decodes and scales in a background isolate and hands over RGBA
/// frames, which [MpvCanvasView] paints. Canvases are short, small loops, so
/// software rendering is cheap; the size is capped at [maxSide] pixels.
class MpvCanvasPlayer {
  MpvCanvasPlayer({this.maxSide = 1024, this.library, this.options = const {}});

  /// Largest rendered side in pixels; mpv scales larger videos down.
  final int maxSide;

  /// libmpv to load; null means the platform's usual name.
  final String? library;

  /// Extra mpv options (the test shows a still image indefinitely).
  final Map<String, String> options;

  /// The latest frame. Owned by the player: don't dispose it yourself.
  final ValueNotifier<ui.Image?> frame = ValueNotifier(null);

  /// Position, length and state, about four times a second.
  final ValueNotifier<MpvPlaybackState> playback = ValueNotifier(const MpvPlaybackState());

  Size get size => _size;
  Size _size = Size.zero;

  Isolate? _isolate;
  SendPort? _commands;
  ReceivePort? _events;
  Completer<bool>? _opened;
  bool _decoding = false;
  bool _disposed = false;

  /// Loads [url] (a file path or URL) and resolves true once the first frame
  /// is in, false if mpv can't play it or nothing arrives in [timeout].
  Future<bool> open(String? url, {Duration timeout = const Duration(seconds: 12)}) async {
    if (_disposed) return false;
    final opened = _opened = Completer<bool>();
    final events = _events = ReceivePort();
    events.listen(_onEvent);
    try {
      _isolate = await Isolate.spawn(
        _canvasWorker,
        _WorkerArgs(events.sendPort, library, maxSide, options),
        debugName: 'mpv canvas',
      );
    } catch (e) {
      debugPrint('MpvCanvasPlayer: could not start: $e');
      _complete(false);
      return false;
    }
    final ready = Completer<void>();
    _readyForCommands = ready;
    await ready.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    if (_commands == null) {
      _complete(false);
      return false;
    }
    if (url != null) _commands!.send(['load', url]);
    return opened.future.timeout(timeout, onTimeout: () => false);
  }

  Completer<void>? _readyForCommands;

  void play() => _commands?.send(['pause', false]);
  void pause() => _commands?.send(['pause', true]);
  void seek(Duration to) => _commands?.send(['seek', to.inMilliseconds / 1000.0]);


  void _complete(bool ok) {
    final o = _opened;
    if (o != null && !o.isCompleted) o.complete(ok);
  }

  void _onEvent(Object? message) {
    if (message is SendPort) {
      _commands = message;
      _readyForCommands?.complete();
      return;
    }
    if (message is! List || message.isEmpty) return;
    switch (message[0]) {
      case 'frame':
        final w = message[1] as int, h = message[2] as int;
        final data = (message[3] as TransferableTypedData).materialize().asUint8List();
        if (_disposed || _decoding) return; // drop: the last one is still going up
        _decoding = true;
        ui.decodeImageFromPixels(data, w, h, ui.PixelFormat.rgba8888, (image) {
          _decoding = false;
          if (_disposed) {
            image.dispose();
            return;
          }
          final old = frame.value;
          _size = Size(w.toDouble(), h.toDouble());
          frame.value = image;
          old?.dispose();
          _complete(true);
        });
      case 'state':
        if (_disposed) return;
        playback.value = MpvPlaybackState(
          position: Duration(milliseconds: ((message[1] as double) * 1000).round()),
          duration: Duration(milliseconds: ((message[2] as double) * 1000).round()),
          paused: message[3] as bool,
          buffering: message[4] as bool,
          ended: message[5] as bool,
        );
      case 'error':
        debugPrint('MpvCanvasPlayer: ${message[1]}');
        _complete(false);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _complete(false);
    final commands = _commands;
    if (commands != null) {
      commands.send(['dispose']);
    } else {
      _isolate?.kill(priority: Isolate.immediate);
    }
    // The worker exits by itself once mpv is torn down; the port closes
    // after a grace period either way.
    Timer(const Duration(seconds: 3), () {
      _events?.close();
      _isolate?.kill(priority: Isolate.immediate);
    });
    final old = frame.value;
    frame.value = null;
    old?.dispose();
    frame.dispose();
    playback.dispose();
  }
}

/// [MpvCanvasPlayer.playback]'s report.
@immutable
class MpvPlaybackState {
  const MpvPlaybackState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.paused = false,
    this.buffering = false,
    this.ended = false,
  });

  final Duration position;
  final Duration duration;
  final bool paused;
  final bool buffering;
  final bool ended;
}

/// Paints an [MpvCanvasPlayer]'s frames, filling its box like VideoPlayer.
class MpvCanvasView extends StatelessWidget {
  const MpvCanvasView(this.player, {super.key});

  final MpvCanvasPlayer player;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ui.Image?>(
      valueListenable: player.frame,
      builder: (context, image, _) => image == null
          ? const SizedBox.expand()
          : RawImage(image: image, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
    );
  }
}

// ---- The worker isolate -------------------------------------------------------

class _WorkerArgs {
  const _WorkerArgs(this.events, this.library, this.maxSide, this.options);
  final SendPort events;
  final String? library;
  final int maxSide;
  final Map<String, String> options;
}

final class _RenderParam extends Struct {
  @Int32()
  external int type;
  external Pointer<Void> data;
}

final class _MpvEvent extends Struct {
  @Int32()
  external int eventId;
  @Int32()
  external int error;
  @Uint64()
  external int replyUserdata;
  external Pointer<Void> data;
}

final class _MpvEndFile extends Struct {
  @Int32()
  external int reason;
  @Int32()
  external int error;
}

// mpv/render.h and client.h constants.
const _paramInvalid = 0;
const _paramApiType = 1;
const _paramSwSize = 17;
const _paramSwFormat = 18;
const _paramSwStride = 19;
const _paramSwPointer = 20;
const _updateFrame = 1;
const _eventShutdown = 1;
const _eventEndFile = 7;
const _endReasonError = 4;

DynamicLibrary? _openLibmpv(String? explicit) {
  final names = explicit != null
      ? [explicit]
      : Platform.isWindows
      ? [p.join(p.dirname(Platform.resolvedExecutable), 'libmpv-2.dll'), 'libmpv-2.dll']
      : [
          // The AppImage pins its bundled libmpv here (see build_appimage.sh).
          ?Platform.environment['LIBMPV_LIBRARY_PATH'],
          'libmpv.so.2',
          'libmpv.so',
          'libmpv.so.1',
        ];
  for (final name in names) {
    try {
      return DynamicLibrary.open(name);
    } catch (_) {}
  }
  return null;
}

/// Owns the mpv handle and its render context for the player's lifetime.
void _canvasWorker(_WorkerArgs args) {
  final out = args.events;
  final lib = _openLibmpv(args.library);
  if (lib == null) {
    out.send(['error', 'libmpv not found']);
    return;
  }
  final create = lib.lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>('mpv_create');
  final setOption = lib.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
    int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)
  >('mpv_set_option_string');
  final setProperty = lib.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
    int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)
  >('mpv_set_property_string');
  final getProperty = lib.lookupFunction<
    Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
    Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)
  >('mpv_get_property_string');
  final free = lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('mpv_free');
  final initialize = lib.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
    'mpv_initialize',
  );
  final command = lib.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<Pointer<Utf8>>),
    int Function(Pointer<Void>, Pointer<Pointer<Utf8>>)
  >('mpv_command');
  final waitEvent = lib.lookupFunction<
    Pointer<_MpvEvent> Function(Pointer<Void>, Double),
    Pointer<_MpvEvent> Function(Pointer<Void>, double)
  >('mpv_wait_event');
  final renderCreate = lib.lookupFunction<
    Int32 Function(Pointer<Pointer<Void>>, Pointer<Void>, Pointer<_RenderParam>),
    int Function(Pointer<Pointer<Void>>, Pointer<Void>, Pointer<_RenderParam>)
  >('mpv_render_context_create');
  final renderUpdate = lib.lookupFunction<Uint64 Function(Pointer<Void>), int Function(Pointer<Void>)>(
    'mpv_render_context_update',
  );
  final render = lib.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<_RenderParam>),
    int Function(Pointer<Void>, Pointer<_RenderParam>)
  >('mpv_render_context_render');
  final renderFree = lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
    'mpv_render_context_free',
  );
  final destroy = lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
    'mpv_terminate_destroy',
  );

  final handle = create();
  if (handle == nullptr) {
    out.send(['error', 'mpv_create failed']);
    return;
  }
  void option(String k, String v) {
    final kk = k.toNativeUtf8(), vv = v.toNativeUtf8();
    setOption(handle, kk, vv);
    calloc.free(kk);
    calloc.free(vv);
  }

  // Video only, looping, decoded in software (the frames are read back on
  // the CPU anyway), nothing printed.
  for (final (k, v) in const [
    ('vo', 'libmpv'),
    ('aid', 'no'),
    ('loop-file', 'inf'),
    ('hwdec', 'no'),
    ('ytdl', 'no'),
    ('terminal', 'no'),
    ('idle', 'yes'),
    ('keep-open', 'yes'),
  ]) {
    option(k, v);
  }
  args.options.forEach(option);
  if (initialize(handle) < 0) {
    destroy(handle);
    out.send(['error', 'mpv_initialize failed']);
    return;
  }

  final ctxOut = calloc<Pointer<Void>>();
  final apiType = 'sw'.toNativeUtf8();
  final createParams = calloc<_RenderParam>(2);
  createParams[0]
    ..type = _paramApiType
    ..data = apiType.cast();
  createParams[1]
    ..type = _paramInvalid
    ..data = nullptr;
  final created = renderCreate(ctxOut, handle, createParams);
  calloc.free(createParams);
  final ctx = ctxOut.value;
  calloc.free(ctxOut);
  if (created < 0 || ctx == nullptr) {
    calloc.free(apiType);
    destroy(handle);
    out.send(['error', 'no software render context ($created)']);
    return;
  }

  final format = 'rgb0'.toNativeUtf8();
  final size = calloc<Int32>(2);
  final stride = calloc<ffi.Size>();
  final renderParams = calloc<_RenderParam>(5);
  Pointer<Uint8> buffer = nullptr;
  var w = 0, h = 0;

  String? prop(String name) {
    final n = name.toNativeUtf8();
    final r = getProperty(handle, n);
    calloc.free(n);
    if (r == nullptr) return null;
    final s = r.toDartString();
    free(r.cast());
    return s;
  }

  void run(List<String> argv) {
    final arr = calloc<Pointer<Utf8>>(argv.length + 1);
    for (var i = 0; i < argv.length; i++) {
      arr[i] = argv[i].toNativeUtf8();
    }
    arr[argv.length] = nullptr;
    command(handle, arr);
    for (var i = 0; i < argv.length; i++) {
      calloc.free(arr[i]);
    }
    calloc.free(arr);
  }

  bool sized() {
    final vw = int.tryParse(prop('dwidth') ?? '') ?? 0;
    final vh = int.tryParse(prop('dheight') ?? '') ?? 0;
    if (vw <= 0 || vh <= 0) return false; // not loaded yet
    final scale = vw > vh
        ? (vw > args.maxSide ? args.maxSide / vw : 1.0)
        : (vh > args.maxSide ? args.maxSide / vh : 1.0);
    final nw = (vw * scale).round(), nh = (vh * scale).round();
    if (nw == w && nh == h && buffer != nullptr) return true;
    if (buffer != nullptr) calloc.free(buffer);
    w = nw;
    h = nh;
    buffer = calloc<Uint8>(w * h * 4);
    size[0] = w;
    size[1] = h;
    stride.value = w * 4;
    renderParams[0]
      ..type = _paramSwSize
      ..data = size.cast();
    renderParams[1]
      ..type = _paramSwFormat
      ..data = format.cast();
    renderParams[2]
      ..type = _paramSwStride
      ..data = stride.cast();
    renderParams[3]
      ..type = _paramSwPointer
      ..data = buffer.cast();
    renderParams[4]
      ..type = _paramInvalid
      ..data = nullptr;
    return true;
  }

  final commands = ReceivePort();
  late final Timer ticker;
  var closed = false;

  void close() {
    if (closed) return;
    closed = true;
    ticker.cancel();
    commands.close();
    renderFree(ctx);
    destroy(handle);
    if (buffer != nullptr) calloc.free(buffer);
    calloc.free(renderParams);
    calloc.free(size);
    calloc.free(stride);
    calloc.free(format);
    calloc.free(apiType);
    Isolate.exit();
  }

  commands.listen((message) {
    if (message is! List || message.isEmpty) return;
    switch (message[0]) {
      case 'load':
        run(['loadfile', message[1] as String]);
      case 'pause':
        final k = 'pause'.toNativeUtf8(), v = ((message[1] as bool) ? 'yes' : 'no').toNativeUtf8();
        setProperty(handle, k, v);
        calloc.free(k);
        calloc.free(v);
      case 'seek':
        run(['seek', '${message[1]}', 'absolute']);
      case 'dispose':
        close();
    }
  });
  out.send(commands.sendPort);

  var lastState = 0;
  bool flag(String name) => prop(name) == 'yes';

  // ~120 Hz poll: mpv says when a new frame is due; render only then.
  ticker = Timer.periodic(const Duration(milliseconds: 8), (_) {
    if (closed) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - lastState >= 250) {
      lastState = now;
      out.send([
        'state',
        double.tryParse(prop('time-pos') ?? '') ?? 0.0,
        double.tryParse(prop('duration') ?? '') ?? 0.0,
        flag('pause'),
        flag('paused-for-cache'),
        flag('eof-reached'),
      ]);
    }
    while (true) {
      final ev = waitEvent(handle, 0);
      final id = ev.ref.eventId;
      if (id == 0) break;
      if (id == _eventShutdown) {
        close();
        return;
      }
      if (id == _eventEndFile && ev.ref.data != nullptr) {
        final end = ev.ref.data.cast<_MpvEndFile>().ref;
        if (end.reason == _endReasonError) out.send(['error', 'mpv could not play it (${end.error})']);
      }
    }
    if (renderUpdate(ctx) & _updateFrame == 0) return;
    if (!sized()) return;
    render(ctx, renderParams);
    // rgb0 leaves the fourth byte at zero; it's alpha to Flutter.
    final pixels = buffer.cast<Uint32>().asTypedList(w * h);
    for (var i = 0; i < pixels.length; i++) {
      pixels[i] |= 0xFF000000;
    }
    out.send(['frame', w, h, TransferableTypedData.fromList([buffer.asTypedList(w * h * 4)])]);
  });
}
