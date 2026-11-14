part of 'discord_rpc_service.dart';

/// Talks to the running Discord desktop app over local IPC, as Nivio does.
class _DesktopDiscordRpc {
  _DesktopDiscordRpc({required this.onStatus, required this.onConnected});

  final ValueChanged<DiscordRpcStatus> onStatus;
  final VoidCallback onConnected;
  String? _clientId;
  _DesktopDiscordIpc? _client;
  Timer? _retry;

  // Serialize writes and reconnects so an older connection can't clear
  // presence published by a newly enabled one.
  Future<void> _pending = Future.value();

  void _enqueue(Future<void> Function() action) {
    _pending = _pending.then((_) => action());
  }

  void enable(String clientId) {
    _clientId = clientId;
    _enqueue(_connect);
  }

  void disable() {
    _clientId = null;
    _retry?.cancel();
    onStatus(DiscordRpcStatus.disconnected);
    _enqueue(() async {
      final client = _client;
      _client = null;
      if (client == null) return;
      try {
        if (client.isConnected) await client.setActivity(null);
      } catch (error) {
        debugPrint('[DiscordRpc] Could not clear desktop presence: $error');
      }
      await _dispose(client);
    });
  }

  Future<void> _connect() async {
    final id = _clientId;
    if (id == null || _client != null) return;
    _retry?.cancel();
    final client = _client = _DesktopDiscordIpc();
    onStatus(DiscordRpcStatus.connecting);
    client.onDisconnected = () => _enqueue(() => _connectionLost(client));
    try {
      await client.connect(id).timeout(const Duration(seconds: 6));
      if (!client.isConnected) {
        await _connectionLost(client);
      } else if (_clientId != null) {
        onStatus(DiscordRpcStatus.connected);
        onConnected();
      }
    } on _DiscordUnavailable {
      await _connectionLost(client);
    } catch (error) {
      debugPrint('[DiscordRpc] Desktop connection failed: $error');
      await _connectionLost(client);
    }
  }

  void publish(Map<String, Object?>? Function() currentActivity) {
    _enqueue(() async {
      final client = _client;
      if (_clientId == null || client == null || !client.isConnected) return;
      try {
        await client.setActivity(currentActivity());
      } catch (error) {
        debugPrint('[DiscordRpc] Desktop presence update failed: $error');
        await _connectionLost(client);
      }
    });
  }

  Future<void> _connectionLost(_DesktopDiscordIpc client) async {
    if (!identical(_client, client)) return;
    _client = null;
    await _dispose(client);
    if (_clientId == null) return;
    onStatus(DiscordRpcStatus.disconnected);
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 20), () => _enqueue(_connect));
  }

  Future<void> _dispose(_DesktopDiscordIpc client) async {
    try {
      await client.dispose();
    } catch (error) {
      debugPrint('[DiscordRpc] Desktop IPC cleanup failed: $error');
    }
  }
}
