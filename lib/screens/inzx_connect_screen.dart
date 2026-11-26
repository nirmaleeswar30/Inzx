import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/audio_player_service.dart';
import '../services/inzx_connect_remote.dart';
import '../services/inzx_connect_service.dart';

class InzxConnectScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: const InzxConnectPanel(),
    );
  }
}

/// Pairing and playback for paired devices.
class InzxConnectPanel extends StatefulWidget {
  const InzxConnectPanel({super.key, this.compact = false});

  final bool compact;

  @override
  State<InzxConnectPanel> createState() => _InzxConnectPanelState();
}

class _InzxConnectPanelState extends State<InzxConnectPanel> {
  final _service = InzxConnectService.instance;
  final _remote = InzxConnectRemote.instance;
  ConnectStatus? _status;
  Timer? _timer;
  bool _busy = false;
  bool _checking = false;
  int _revision = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _remote.resumeFollowing();
    unawaited(_run());
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_status == null) return;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != AppLifecycleState.resumed &&
          lifecycle != AppLifecycleState.inactive) {
        return;
      }
      if (ModalRoute.of(context)?.isCurrent != true) return;
      // Connection status can expire even if the pairing request is pending.
      if (_status!.devices.isNotEmpty) setState(() {});
      if (!_busy && !_checking) unawaited(_refresh());
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
      if (mounted && revision == _revision) {
        setState(() => _status = status);
        unawaited(_remote.watch(status.devices));
      }
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
      if (mounted) {
        setState(() => _status = status);
        unawaited(_remote.watch(status.devices));
      }
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
    final mobile = InzxConnectService.canScanQr;

    return ListenableBuilder(
      listenable: _remote,
      builder: (context, _) => ListView(
        padding: EdgeInsets.all(widget.compact ? 16 : 24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!mobile)
                    const Text(
                      'Open Inzx Connect on your phone, scan the QR code, '
                      'then approve the request here.',
                    ),
                  if (mobile && status == null)
                    _MobilePairingCard(
                      waitingFor: null,
                      hasDevices: false,
                      onScan: _busy ? null : _scan,
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
                    if (!mobile && status.waitingFor != null) ...[
                      const SizedBox(height: 12),
                      Text('Waiting for approval on ${status.waitingFor}.'),
                    ],
                    if (!mobile || status.devices.isNotEmpty) ...[
                      if (!mobile) const SizedBox(height: 24),
                      Text(
                        'Paired devices',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      if (status.devices.isEmpty)
                        const Text('No devices paired yet.'),
                    ],
                    for (final device in status.devices)
                      ConnectDeviceCard(
                        key: ValueKey(device.id),
                        device: device,
                        remote: _remote,
                        busy: _busy,
                        onRemove: () => _remove(device),
                      ),
                    if (mobile) ...[
                      if (status.devices.isNotEmpty) const SizedBox(height: 8),
                      _MobilePairingCard(
                        waitingFor: status.waitingFor,
                        hasDevices: status.devices.isNotEmpty,
                        onScan: _busy ? null : _scan,
                      ),
                    ],
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

class _MobilePairingCard extends StatelessWidget {
  const _MobilePairingCard({
    required this.waitingFor,
    required this.hasDevices,
    required this.onScan,
  });

  final String? waitingFor;
  final bool hasDevices;
  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final waiting = waitingFor;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primaryContainer, colors.surfaceContainerHigh],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              waiting == null ? Icons.devices_rounded : Icons.pending_outlined,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            waiting != null
                ? 'Waiting for approval'
                : hasDevices
                ? 'Pair another computer'
                : 'Pair a computer',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            waiting != null
                ? 'Approve the pairing request on $waiting.'
                : 'Open Inzx Connect on your computer, show its pairing QR, and scan it with this phone.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurface,
            ),
          ),
          if (waiting == null) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan pairing QR'),
            ),
          ],
        ],
      ),
    );
  }
}

/// One paired device: whether it's around, what it's playing, and the
/// controls to steer it or move playback between it and this device.
class ConnectDeviceCard extends StatefulWidget {
  const ConnectDeviceCard({
    super.key,
    required this.device,
    required this.remote,
    this.busy = false,
    this.onRemove,
  });

  final ConnectDevice device;
  final InzxConnectRemote remote;
  final bool busy;
  final VoidCallback? onRemove;

  @override
  State<ConnectDeviceCard> createState() => _ConnectDeviceCardState();
}

class _ConnectDeviceCardState extends State<ConnectDeviceCard> {
  bool _startingBoth = false;

  // The volume slider while it's moved, and for a moment after, until the
  // device's own report catches up (so it doesn't jump back meanwhile).
  double? _volume;
  DateTime _volumeHeldUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _volumeSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _moveVolume(double value, {bool done = false}) {
    final now = DateTime.now();
    setState(() {
      _volume = value;
      _volumeHeldUntil = now.add(const Duration(seconds: 2));
    });
    if (done ||
        now.difference(_volumeSentAt) >= const Duration(milliseconds: 120)) {
      _volumeSentAt = now;
      unawaited(widget.remote.setVolume(widget.device.id, value));
    }
  }

  Future<void> _playBoth() async {
    setState(() => _startingBoth = true);
    var started = false;
    try {
      started = await widget.remote.playOnBoth(widget.device.id);
    } catch (error) {
      debugPrint('Inzx Connect: could not start both devices: $error');
    } finally {
      if (mounted) {
        setState(() => _startingBoth = false);
        if (!started) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Couldn’t start playback on both devices.'),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final remote = widget.remote;
    final theme = Theme.of(context);
    final online = remote.isOnline(device.id);
    final playback = online ? remote.playbackOf(device.id) : null;
    final track = playback?.track;
    final hasLocal = AudioPlayerService.instance.currentTrack != null;
    final mobile = InzxConnectService.canScanQr;
    final both = remote.isGroupedWith(device.id);
    final active = remote.isOutputSelected(device.id);
    final colors = theme.colorScheme;
    final secondary = theme.colorScheme.onSurface.withValues(alpha: 0.65);
    final volume = DateTime.now().isBefore(_volumeHeldUntil)
        ? _volume
        : playback?.volume;

    final String status;
    if (!online) {
      status = remote.isLookingFor(device.id) ? 'Looking for it…' : 'Offline';
    } else if (track == null) {
      status = 'Nothing playing';
    } else {
      status = playback!.isPlaying ? 'Playing' : 'Paused';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: mobile ? colors.surfaceContainer : null,
      shape: mobile
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
              side: BorderSide(
                color: active
                    ? colors.primary.withValues(alpha: 0.55)
                    : colors.outlineVariant,
              ),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: mobile ? const EdgeInsets.all(10) : EdgeInsets.zero,
                  decoration: mobile
                      ? BoxDecoration(
                          color: online
                              ? colors.primaryContainer
                              : colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        )
                      : null,
                  child: Icon(
                    // Desktop shows the QR and Android scans it, so each
                    // supported pairing has one device of each type.
                    InzxConnectService.canShowQr
                        ? Icons.android
                        : Icons.computer_rounded,
                    size: 20,
                    color: online
                        ? mobile
                              ? colors.onPrimaryContainer
                              : colors.primary
                        : secondary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mobile
                            ? theme.textTheme.titleMedium
                            : theme.textTheme.titleSmall,
                      ),
                      Text(
                        both
                            ? '$status on both devices'
                            : active
                            ? '$status on ${device.label}'
                            : status,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.onRemove case final remove?)
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    enabled: !widget.busy,
                    onSelected: (_) => remove(),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'remove', child: Text('Remove')),
                    ],
                  ),
              ],
            ),
            if (track != null && playback != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(mobile ? 12 : 6),
                    child: SizedBox.square(
                      dimension: mobile ? 64 : 48,
                      child: track.thumbnailUrl == null
                          ? ColoredBox(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.music_note_rounded),
                            )
                          : CachedNetworkImage(
                              imageUrl: track.thumbnailUrl!,
                              fit: BoxFit.cover,
                              memCacheWidth: 144,
                              errorWidget: (_, _, _) =>
                                  const Icon(Icons.music_note_rounded),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Previous',
                    onPressed: () => remote.previous(device.id),
                    icon: const Icon(Icons.skip_previous_rounded),
                  ),
                  IconButton.filledTonal(
                    tooltip: playback.isPlaying ? 'Pause' : 'Play',
                    onPressed: () => remote.togglePlay(device.id),
                    icon: Icon(
                      playback.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next',
                    onPressed: () => remote.next(device.id),
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                ],
              ),
            ],
            if (volume != null)
              Semantics(
                label: 'Volume on ${device.label}',
                child: Row(
                  children: [
                    Icon(
                      volume <= 0.01
                          ? Icons.volume_off_rounded
                          : Icons.volume_down_rounded,
                      size: 20,
                      color: secondary,
                    ),
                    Expanded(
                      child: Slider(
                        value: volume,
                        onChanged: _moveVolume,
                        onChangeEnd: (value) => _moveVolume(value, done: true),
                        semanticFormatterCallback: (value) =>
                            '${(value * 100).round()}%',
                      ),
                    ),
                    Icon(Icons.volume_up_rounded, size: 20, color: secondary),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            if (online && (track != null || hasLocal)) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (track != null && !remote.isLocalOutputSelected)
                    FilledButton.icon(
                      onPressed: () => remote.playHere(device.id),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Play here'),
                    ),
                  if (both || (hasLocal && !active))
                    OutlinedButton.icon(
                      onPressed: () async {
                        final sent = await remote.playOn(device.id);
                        if (!sent && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Couldn’t move playback to this device.',
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.cast_rounded, size: 18),
                      label: Text('Play on ${device.label}'),
                    ),
                  if (!both)
                    OutlinedButton.icon(
                      onPressed: _startingBoth ? null : _playBoth,
                      icon: const Icon(Icons.speaker_group_rounded, size: 18),
                      label: Text(_startingBoth ? 'Starting…' : 'Play on both'),
                    ),
                ],
              ),
            ],
          ],
        ),
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
