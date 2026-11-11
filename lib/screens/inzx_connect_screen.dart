import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/inzx_connect_service.dart';

class InzxConnectScreen extends StatefulWidget {
  static const title = 'Inzx Connect';
  static const subtitle = 'Pair your devices';
  static const icon = Icons.devices_rounded;

  static MaterialPageRoute<void>? _route;

  const InzxConnectScreen({super.key});

  static void open(NavigatorState? navigator) {
    if (navigator == null || _route?.isActive == true) return;
    final route = MaterialPageRoute<void>(
      builder: (_) => const InzxConnectScreen(),
    );
    _route = route;
    unawaited(
      navigator.push(route).whenComplete(() {
        if (identical(_route, route)) _route = null;
      }),
    );
  }

  @override
  State<InzxConnectScreen> createState() => _InzxConnectScreenState();
}

class _InzxConnectScreenState extends State<InzxConnectScreen> {
  final _service = InzxConnectService.instance;
  ConnectStatus? _status;
  Timer? _timer;
  bool _busy = false;
  bool _checking = false;
  int _revision = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_status == null || _busy || _checking) return;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != AppLifecycleState.resumed &&
          lifecycle != AppLifecycleState.inactive) {
        return;
      }
      if (ModalRoute.of(context)?.isCurrent == true) unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    _checking = true;
    final revision = _revision;
    try {
      final status = await _service.status();
      if (mounted && revision == _revision) setState(() => _status = status);
    } catch (_) {
      // Keep the last known state and retry on the next tick.
    } finally {
      _checking = false;
    }
  }

  Future<void> _run([Future<void> Function()? action]) async {
    if (_busy) return;
    _revision++;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action?.call();
      final status = await _service.status();
      if (mounted) setState(() => _status = status);
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _messageFor(Object error) {
    if (error is AuthException && error.code == 'anonymous_provider_disabled') {
      return 'Pairing is unavailable until Inzx Connect is enabled on the server.';
    }
    if (error is PostgrestException) {
      if (error.code == 'PGRST202' || error.code == '42883') {
        return 'Pairing is unavailable until Inzx Connect is enabled on the server.';
      }
      if (error.code == 'P0001') {
        return 'This pairing code or request is no longer available. '
            'Show a new QR code on your computer and try again.';
      }
    }
    return 'Couldn’t reach Inzx Connect. Check your connection and try again.';
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _ConnectScannerScreen()),
    );
    if (mounted && code != null) await _run(() => _service.scanInvite(code));
  }

  Future<void> _remove(ConnectDevice device) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${device.label}?'),
        content: const Text('You’ll need to pair these devices again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (mounted && remove == true) await _run(() => _service.unpair(device));
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final invite = _service.currentInvite;
    final activeInvite =
        invite != null && invite.expiresAt.isAfter(DateTime.now())
        ? invite
        : null;
    final incoming = status?.incoming;

    return Scaffold(
      appBar: AppBar(title: const Text(InzxConnectScreen.title)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    InzxConnectService.canShowQr
                        ? 'Open Inzx Connect on your phone, scan the QR code, '
                              'then approve the request here.'
                        : 'Show a QR code in Inzx Connect on your computer '
                              'and scan it here.',
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ],
                  if (_error case final error?) ...[
                    const SizedBox(height: 16),
                    Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    if (status == null)
                      TextButton(
                        onPressed: _busy ? null : () => _run(),
                        child: const Text('Retry'),
                      ),
                  ],
                  if (status != null) ...[
                    const SizedBox(height: 16),
                    if (InzxConnectService.canShowQr)
                      FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(_service.createInvite),
                        icon: const Icon(Icons.qr_code_rounded),
                        label: Text(
                          activeInvite == null
                              ? 'Show pairing QR'
                              : 'Show new QR',
                        ),
                      ),
                    if (activeInvite != null) ...[
                      const SizedBox(height: 12),
                      QrImageView(
                        data: activeInvite.qrData,
                        size: 224,
                        backgroundColor: Colors.white,
                        semanticsLabel: 'Inzx Connect pairing QR code',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        incoming == null
                            ? 'This code is valid for two minutes.'
                            : 'Allow ${incoming.label} to pair?',
                      ),
                      if (incoming != null)
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton(
                              onPressed: _busy
                                  ? null
                                  : () => _run(
                                      () => _service.decide(
                                        incoming,
                                        activeInvite,
                                        true,
                                      ),
                                    ),
                              child: const Text('Allow'),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _run(
                                      () => _service.decide(
                                        incoming,
                                        activeInvite,
                                        false,
                                      ),
                                    ),
                              child: const Text('Decline'),
                            ),
                          ],
                        ),
                    ] else if (invite != null)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'This code expired. Show a new QR to pair.',
                        ),
                      ),
                    if (InzxConnectService.canScanQr)
                      FilledButton.icon(
                        onPressed: _busy ? null : _scan,
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        label: const Text('Scan pairing QR'),
                      ),
                    if (status.waitingFor case final host?) ...[
                      const SizedBox(height: 12),
                      Text('Waiting for approval on $host.'),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'Paired devices',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (status.devices.isEmpty)
                      const Text('No devices paired yet.'),
                    for (final device in status.devices)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(InzxConnectScreen.icon),
                        title: Text(device.label),
                        trailing: TextButton(
                          onPressed: _busy ? null : () => _remove(device),
                          child: const Text('Remove'),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectScannerScreen extends StatefulWidget {
  const _ConnectScannerScreen();

  @override
  State<_ConnectScannerScreen> createState() => _ConnectScannerScreenState();
}

class _ConnectScannerScreenState extends State<_ConnectScannerScreen> {
  bool _detected = false;

  void _onDetect(BarcodeCapture capture) {
    if (_detected || !mounted || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    for (final barcode in capture.barcodes) {
      if (barcode.format != BarcodeFormat.qrCode) continue;
      final code = ConnectInvite.codeFromQr(barcode.rawValue);
      if (code == null) continue;
      _detected = true;
      Navigator.pop(context, code);
      break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan pairing QR')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Point the camera at the QR code shown in Inzx Connect.',
            ),
          ),
          Expanded(
            child: MobileScanner(
              onDetect: _onDetect,
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    error.errorCode == MobileScannerErrorCode.permissionDenied
                        ? 'Allow camera access for Inzx in Android Settings to scan the QR code.'
                        : 'The camera is unavailable. Close the scanner and try again.',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
