part of 'discord_rpc_service.dart';

class _DiscordUnavailable implements Exception {
  const _DiscordUnavailable();
}

/// Discord's IPC handshake and activity commands, shared by both desktops.
class _DesktopDiscordIpc {
  final _ready = Completer<void>();
  final _buffer = BytesBuilder(copy: false);
  late final Future<void> Function(Uint8List) _write;
  late final VoidCallback _close;
  StreamSubscription<Uint8List>? _subscription;
  Future<void> _pendingWrite = Future.value();
  int _nonce = 0;
  bool _closed = false;
  bool _lost = false;
  bool isConnected = false;
  VoidCallback? onDisconnected;

  Future<void> connect(String clientId) async {
    final Stream<Uint8List> incoming;
    if (Platform.isWindows) {
      final pipe = _DiscordWindowsPipe.open();
      incoming = pipe.stream;
      _write = pipe.write;
      _close = pipe.close;
    } else {
      final socket = await _openUnixSocket();
      if (_closed) {
        socket.destroy();
        return;
      }
      incoming = socket;
      _write = (bytes) {
        socket.add(bytes);
        return socket.flush();
      };
      _close = socket.destroy;
    }
    _ready.future.ignore();
    _subscription = incoming.listen(
      _receive,
      onError: _connectionLost,
      onDone: () => _connectionLost(StateError('Discord closed the IPC link')),
    );
    await _send(0, utf8.encode(jsonEncode({'v': 1, 'client_id': clientId})));
    await _ready.future;
  }

  Future<Socket> _openUnixSocket() async {
    final env = Platform.environment;
    final runtime = env['XDG_RUNTIME_DIR'];
    final directories = {
      runtime,
      if (runtime != null) '$runtime/app/com.discordapp.Discord',
      env['TMPDIR'],
      env['TMP'],
      env['TEMP'],
      '/tmp',
    };
    for (final directory in directories.nonNulls) {
      if (directory.isEmpty) continue;
      for (var index = 0; index < 10 && !_closed; index++) {
        try {
          return await Socket.connect(
            InternetAddress(
              '$directory/discord-ipc-$index',
              type: InternetAddressType.unix,
            ),
            0,
            timeout: const Duration(milliseconds: 500),
          );
        } on SocketException {
          // Try the next local Discord socket.
        }
      }
    }
    throw const _DiscordUnavailable();
  }

  Future<void> setActivity(Map<String, Object?>? activity) {
    final json = jsonEncode({
      'cmd': 'SET_ACTIVITY',
      'nonce': '${++_nonce}',
      'args': {'pid': pid, 'activity': activity},
    });
    return _send(1, utf8.encode(json));
  }

  Future<void> _send(int opcode, List<int> payload) {
    final frame = Uint8List(8 + payload.length);
    ByteData.sublistView(frame)
      ..setUint32(0, opcode, Endian.little)
      ..setUint32(4, payload.length, Endian.little);
    frame.setRange(8, frame.length, payload);
    return _pendingWrite = _pendingWrite.then((_) async {
      if (_closed || _lost) throw StateError('Discord IPC is closed');
      await _write(frame);
    });
  }

  void _receive(Uint8List chunk) {
    _buffer.add(chunk);
    final bytes = _buffer.takeBytes();
    var offset = 0;
    try {
      while (bytes.length - offset >= 8) {
        final header = ByteData.sublistView(bytes, offset, offset + 8);
        final opcode = header.getUint32(0, Endian.little);
        final length = header.getUint32(4, Endian.little);
        if (length > 1024 * 1024) {
          throw const FormatException('Invalid IPC frame');
        }
        final end = offset + 8 + length;
        if (end > bytes.length) break;
        final payload = Uint8List.sublistView(bytes, offset + 8, end);
        offset = end;

        if (opcode == 2) {
          _connectionLost(StateError('Discord closed the IPC link'));
          return;
        }
        if (opcode == 3) {
          unawaited(_send(4, payload).catchError(_connectionLost));
        }
        if (opcode == 1) {
          final event =
              jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
          if (event['evt'] == 'READY' && !_ready.isCompleted) {
            isConnected = true;
            _ready.complete();
          } else if (event['evt'] == 'ERROR') {
            if (!_ready.isCompleted) {
              _connectionLost(StateError('Discord rejected the IPC handshake'));
              return;
            }
            debugPrint(
              '[DiscordRpc] Discord rejected a desktop activity update',
            );
          }
        }
      }
      _buffer.add(Uint8List.sublistView(bytes, offset));
    } catch (error) {
      _connectionLost(error);
    }
  }

  void _connectionLost(Object error) {
    if (_closed || _lost) return;
    _lost = true;
    isConnected = false;
    if (!_ready.isCompleted) _ready.completeError(error);
    onDisconnected?.call();
  }

  Future<void> dispose() async {
    _closed = true;
    isConnected = false;
    if (_subscription == null) return;
    if (!_ready.isCompleted) {
      _ready.completeError(StateError('Discord IPC closed'));
    }
    await _subscription!.cancel();
    _close();
  }
}

/// Polls a nonblocking named pipe so Discord cannot stall the UI isolate.
class _DiscordWindowsPipe {
  _DiscordWindowsPipe(this._handle) {
    _poller = Timer.periodic(const Duration(milliseconds: 100), (_) => _poll());
  }

  static _DiscordWindowsPipe open() {
    for (var index = 0; index < 10; index++) {
      final handle = using((arena) {
        final path = '\\\\.\\pipe\\discord-ipc-$index'.toPcwstr(
          allocator: arena,
        );
        final handle = win32.CreateFile(
          path,
          win32.GENERIC_READ | win32.GENERIC_WRITE,
          const win32.FILE_SHARE_MODE(0),
          null,
          win32.OPEN_EXISTING,
          const win32.FILE_FLAGS_AND_ATTRIBUTES(0),
          null,
        ).value;
        if (handle == win32.INVALID_HANDLE_VALUE) return null;
        final mode = arena<win32.DWORD>()..value = win32.PIPE_NOWAIT;
        if (win32.SetNamedPipeHandleState(handle, mode, null, null).value) {
          return handle;
        }
        win32.CloseHandle(handle);
        return null;
      });
      if (handle != null) return _DiscordWindowsPipe(handle);
    }
    throw const _DiscordUnavailable();
  }

  final win32.HANDLE _handle;
  final _incoming = StreamController<Uint8List>.broadcast();
  late final Timer _poller;
  bool _closed = false;
  Stream<Uint8List> get stream => _incoming.stream;

  void _poll() {
    try {
      final bytes = using((arena) {
        final count = arena<win32.DWORD>();
        if (!win32.PeekNamedPipe(_handle, null, 0, null, count, null).value) {
          throw StateError('Discord closed the named pipe');
        }
        final size = min(count.value, 64 * 1024);
        if (size == 0) return null;
        final buffer = arena<win32.BYTE>(size);
        if (!win32.ReadFile(_handle, buffer, size, count, null).value) {
          throw StateError('Could not read from the Discord pipe');
        }
        return Uint8List.fromList(buffer.asTypedList(count.value));
      });
      if (bytes != null) _incoming.add(bytes);
    } catch (error) {
      _incoming.addError(error);
      close();
    }
  }

  Future<void> write(Uint8List bytes) async {
    var offset = 0;
    final timeout = Stopwatch()..start();
    while (offset < bytes.length) {
      if (_closed || timeout.elapsed > const Duration(seconds: 2)) {
        throw StateError('Discord pipe is unavailable');
      }
      offset += using((arena) {
        final length = bytes.length - offset;
        final buffer = arena<win32.BYTE>(length);
        buffer.asTypedList(length).setRange(0, length, bytes, offset);
        final count = arena<win32.DWORD>();
        if (!win32.WriteFile(_handle, buffer, length, count, null).value) {
          throw StateError('Could not write to the Discord pipe');
        }
        return count.value;
      });
      if (offset < bytes.length) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _poller.cancel();
    win32.CloseHandle(_handle);
    unawaited(_incoming.close());
  }
}
