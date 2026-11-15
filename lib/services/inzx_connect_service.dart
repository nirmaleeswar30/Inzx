import 'dart:async';
import 'dart:io';

import 'secure_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'audio_routing_service.dart';
import 'supabase_config.dart';

class ConnectDevice {
  final String id;
  final String label;

  ConnectDevice.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      label = json['label'] as String;
}

class ConnectInvite {
  static const _prefix = 'inzx-connect:v1:';
  static final _codePattern = RegExp(r'^[0-9a-f]{64}$');

  final String code;
  final DateTime expiresAt;

  ConnectInvite.fromJson(Map<String, dynamic> json)
    : code = json['code'] as String,
      expiresAt = DateTime.parse(json['expires_at'] as String);

  String get qrData => '$_prefix$code';

  static String? codeFromQr(String? value) {
    if (value == null || !value.startsWith(_prefix)) return null;
    final code = value.substring(_prefix.length);
    return code.length == 64 && _codePattern.hasMatch(code) ? code : null;
  }
}

class ConnectStatus {
  final List<ConnectDevice> devices;
  final ConnectDevice? incoming;
  final String? waitingFor;

  ConnectStatus.fromJson(Map<String, dynamic> json)
    : devices = (json['devices'] as List)
          .map(
            (device) => ConnectDevice.fromJson(device as Map<String, dynamic>),
          )
          .toList(growable: false),
      incoming = json['incoming'] == null
          ? null
          : ConnectDevice.fromJson(json['incoming'] as Map<String, dynamic>),
      waitingFor = json['waiting_for'] as String?;
}

class InzxConnectService {
  static final instance = InzxConnectService._();

  static bool get canShowQr => Platform.isWindows || Platform.isLinux;
  static bool get canScanQr => Platform.isAndroid;
  static bool get isSupported => canShowQr || canScanQr;

  static const _sessionKey = 'inzx_connect_refresh_token';
  static final _storage = SecureStore.instance;

  SupabaseClient? _client;
  Future<void>? _opening;
  Future<void> _pendingWrite = Future<void>.value();
  String? _savedToken;
  bool _registered = false;
  ConnectInvite? currentInvite;

  InzxConnectService._();

  Future<void> _saveToken(String token) {
    // Preserve the SDK's token order even if secure storage is slow.
    return _pendingWrite = _pendingWrite.catchError((Object _) {}).then((
      _,
    ) async {
      if (_savedToken == token) return;
      await _storage.write(key: _sessionKey, value: token);
      _savedToken = token;
    });
  }

  Future<void> _ensureReady() {
    if (_registered && _client?.auth.currentSession != null) {
      return Future<void>.value();
    }
    return _opening ??= _initialize().whenComplete(() => _opening = null);
  }

  Future<void> _initialize() async {
    if (!SupabaseConfig.isAvailable) {
      throw StateError('Inzx Connect is unavailable.');
    }
    // A dedicated session keeps the existing public Jams client separate.
    if (_client == null) {
      final client = SupabaseClient(
        SupabaseConfig.supabaseUrl,
        SupabaseConfig.supabaseAnonKey,
      );
      client.auth.onAuthStateChange.listen((state) {
        final token = state.session?.refreshToken;
        if (state.event == AuthChangeEvent.tokenRefreshed && token != null) {
          // A later call retries a failed write with the current token.
          unawaited(_saveToken(token).catchError((Object _) {}));
        }
      }, onError: (Object _) {});
      _client = client;
    }

    final client = _client!;
    if (client.auth.currentSession == null) {
      final token = await _storage.read(key: _sessionKey);
      _savedToken = token;
      if (token == null) {
        await client.auth.signInAnonymously();
      } else {
        await client.auth.setSession(token);
      }
    }
    final token = client.auth.currentSession?.refreshToken;
    if (token == null) throw StateError('Inzx Connect session is unavailable.');
    await _saveToken(token);
    await client.rpc(
      'inzx_connect_register',
      params: {'device_label': await deviceLabel()},
    );
    _registered = true;
  }

  /// What this device is called on the other end: the computer's name on
  /// desktop, and on Android the phone's Bluetooth name (what the phone calls
  /// itself in Settings, e.g. "OnePlus 15"), read through the smart routing
  /// channel. Re-sent on every start, so a rename shows up on the next launch.
  static Future<String> deviceLabel() async {
    String? name;
    if (Platform.isAndroid) {
      final routing = await AudioRoutingService.getActiveDeviceName();
      final devices = routing['all'];
      if (devices is List) {
        for (final device in devices) {
          if (device is Map && device['isSpeaker'] == true) {
            name = device['name']?.toString();
            break;
          }
        }
      }
      // Without Bluetooth access the speaker keeps its placeholder name.
      if (name == 'Internal Speaker') name = null;
    } else {
      try {
        name = Platform.localHostname;
      } catch (_) {}
    }
    name = name?.trim();
    if (name == null || name.isEmpty) {
      return Platform.isWindows
          ? 'Windows PC'
          : Platform.isLinux
          ? 'Linux PC'
          : 'Android phone';
    }
    return name.length > 48 ? name.substring(0, 48) : name;
  }

  Future<dynamic> _call(String name, [Map<String, dynamic>? params]) async {
    await _ensureReady();
    final client = _client!;
    final token = client.auth.currentSession?.refreshToken;
    if (token != null && _savedToken != token) await _saveToken(token);
    return client.rpc('inzx_connect_$name', params: params);
  }

  /// The signed-in client, once this device has a Connect session.
  Future<SupabaseClient> client() async {
    await _ensureReady();
    return _client!;
  }

  /// This device's Connect id (its anonymous user id), once signed in.
  String? get deviceId => _client?.auth.currentUser?.id;

  /// Whether this install has ever opened Inzx Connect. Installs that never
  /// did stay off the server entirely.
  Future<bool> hasSession() async {
    if (_client?.auth.currentSession != null) return true;
    try {
      return await _storage.read(key: _sessionKey) != null;
    } catch (_) {
      return false;
    }
  }

  Future<ConnectStatus> status() async =>
      ConnectStatus.fromJson(await _call('status') as Map<String, dynamic>);

  Future<void> createInvite() async {
    currentInvite = ConnectInvite.fromJson(
      await _call('create_invite') as Map<String, dynamic>,
    );
  }

  Future<void> scanInvite(String code) async {
    await _call('scan_invite', {'pairing_code': code});
  }

  Future<void> decide(
    ConnectDevice device,
    ConnectInvite invite,
    bool approve,
  ) async {
    await _call('decide', {
      'peer': device.id,
      'pairing_code': invite.code,
      'approve': approve,
    });
    if (identical(currentInvite, invite)) currentInvite = null;
  }

  Future<void> unpair(ConnectDevice device) async {
    await _call('unpair', {'peer': device.id});
  }
}
