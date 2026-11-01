import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/design_system.dart';
import '../../providers/providers.dart';
import '../../services/audio_player_service.dart';
import '../../services/audio_routing_service.dart';
import '../../services/audio_output_service.dart';
import '../../services/playback/playback_data.dart';

/// "Stats for nerds", opened: the path the audio takes from the stream to
/// the speaker, stage by stage, and how healthy the stream is.
///
/// Everything here is read, not assumed. Inzx plays through Android's
/// shared mixer, so the verdict never claims "bit-perfect"; it says whether
/// the source is lossless and whether Android resamples it on the way out.
class SignalPathSheet extends ConsumerStatefulWidget {
  const SignalPathSheet({super.key, required this.accentColor});

  final Color accentColor;

  static Future<void> show(BuildContext context, {required Color accentColor}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF141414) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SignalPathSheet(accentColor: accentColor),
    );
  }

  @override
  ConsumerState<SignalPathSheet> createState() => _SignalPathSheetState();
}

class _SignalPathSheetState extends ConsumerState<SignalPathSheet> {
  Timer? _tick;
  int _ticks = 0;
  int? _mixerRate;
  int? _framesPerBuffer;
  int? _systemVolume;
  int? _systemVolumeMax;
  String? _deviceName;
  bool _deviceIsSpeaker = true;
  AudioOutputStatus? _output;

  @override
  void initState() {
    super.initState();
    _readOutput();
    // Buffer and volume move while the sheet is open; device info rarely.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _ticks++;
      if (_ticks % 3 == 0) _readOutput();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _readOutput() async {
    final info = await AudioRoutingService.getOutputInfo();
    final device = await AudioRoutingService.getActiveDeviceName();
    final output = await AudioOutputService.describe();
    if (!mounted) return;
    final active = device['active'];
    setState(() {
      _output = output;
      _mixerRate = info?['mixerSampleRate'] as int?;
      _framesPerBuffer = info?['framesPerBuffer'] as int?;
      _systemVolume = info?['systemVolume'] as int?;
      _systemVolumeMax = info?['systemVolumeMax'] as int?;
      if (active is Map) {
        _deviceName = active['name']?.toString();
        _deviceIsSpeaker = active['isSpeaker'] == true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(currentPlaybackDataProvider);
    final quality = ref.watch(audioQualityProvider);
    final player = AudioPlayerService.instance;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? Colors.white : InzxColors.textPrimary;
    final secondary = isDark ? Colors.white54 : InzxColors.textSecondary;
    final accent = widget.accentColor;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: secondary.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Signal path',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: primary,
                ),
              ),
              const SizedBox(height: 10),
              if (data == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Nothing is playing.',
                    style: TextStyle(color: secondary),
                  ),
                )
              else ...[
                _verdict(data, player, accent, primary, secondary, isDark),
                const SizedBox(height: 20),
                ..._stages(data, player, accent, primary, secondary, isDark),
                const SizedBox(height: 22),
                _health(data, player, quality, primary, secondary, isDark),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---- Verdict --------------------------------------------------------

  Widget _verdict(
    PlaybackData data,
    AudioPlayerService player,
    Color accent,
    Color primary,
    Color secondary,
    bool isDark,
  ) {
    final format = data.format;
    final source = format.sampleRate;
    final mixer = _mixerRate;
    final resampled = source != null && mixer != null && source != mixer;
    final tier = format.losslessTier;
    final output = _output;

    final String badge;
    final String line;
    final bool good;
    if (tier != null && output != null && output.bitPerfectActive) {
      badge = 'BIT-PERFECT';
      line = 'Sent to ${output.bitPerfectDevice ?? 'your USB DAC'} unchanged '
          'at ${_khz(output.trackSampleRate ?? source ?? 0)}, '
          '${output.trackEncoding ?? 'PCM'} — Android\'s mixer is bypassed';
      good = true;
    } else if (tier != null && !resampled && mixer != null) {
      badge = tier.toUpperCase();
      line = 'Lossless all the way to Android\'s mixer, at the track\'s own '
          '${_khz(source!)}';
      good = true;
    } else if (tier != null && resampled) {
      badge = '$tier · RESAMPLED'.toUpperCase();
      line = 'Lossless source; Android resamples ${_khz(source)} → '
          '${_khz(mixer)} for this output';
      good = true;
    } else if (tier != null) {
      badge = tier.toUpperCase();
      line = 'Lossless source';
      good = true;
    } else {
      badge = 'LOSSY STREAM';
      line = '${data.codecName} at ${data.bitrateKbps} kbps from '
          '${data.audioSource}';
      good = false;
    }

    final color = good ? accent : secondary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            badge,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: good ? _readable(accent, isDark) : primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            line,
            style: TextStyle(fontSize: 13.5, color: primary, height: 1.3),
          ),
          if (player.isUpgradingStream) ...[
            const SizedBox(height: 6),
            Text(
              'Switching to a better copy…',
              style: TextStyle(fontSize: 12.5, color: secondary),
            ),
          ],
        ],
      ),
    );
  }

  // ---- Pipeline -------------------------------------------------------

  List<Widget> _stages(
    PlaybackData data,
    AudioPlayerService player,
    Color accent,
    Color primary,
    Color secondary,
    bool isDark,
  ) {
    final format = data.format;
    final speed = player.currentSpeed;
    final volume = player.currentVolume;
    final crossfadeMs = player.crossfadeDurationMs;
    final source = format.sampleRate;
    final mixer = _mixerRate;
    final output = _output;
    final bitPerfect = output?.bitPerfectActive == true;

    final stages = <_Stage>[
      _Stage(
        icon: Icons.graphic_eq_rounded,
        title: 'Source',
        value: format.losslessTier ?? data.codecName,
        rows: [
          ('Codec', data.codecName),
          if (format.resolutionLabel != null)
            ('Resolution', format.resolutionLabel!),
          ('Bitrate', '${data.bitrateKbps} kbps'),
          ('From', data.audioSource),
          ('Delivery', data.isManifestStream ? 'Adaptive (DASH/HLS)' : 'Direct file'),
        ],
      ),
      _Stage(
        icon: Icons.tune_rounded,
        title: 'Processing',
        value: speed == 1.0 && volume >= 0.999 ? 'Untouched' : 'Adjusted',
        rows: [
          (
            'Speed',
            speed == 1.0
                ? '1.00x — no time-stretching'
                : '${speed.toStringAsFixed(2)}x — time-stretched',
          ),
          (
            'App volume',
            volume >= 0.999
                ? '0.0 dB — unity gain'
                : '${(volume * 100).round()}% — scaled (fade in progress?)',
          ),
          (
            'Crossfade',
            crossfadeMs > 0
                ? '${(crossfadeMs / 1000).toStringAsFixed(0)} s, only between songs'
                : 'Off',
          ),
        ],
      ),
      _Stage(
        icon: Icons.merge_type_rounded,
        title: 'Android mixer',
        value: bitPerfect
            ? 'Bypassed'
            : (mixer == null ? 'Unknown' : _khz(mixer)),
        rows: [
          if (output?.trackSampleRate != null)
            (
              'Sent to Android',
              '${output!.trackEncoding ?? 'PCM'} • '
                  '${_khz(output.trackSampleRate!)}',
            ),
          if (bitPerfect)
            (
              'Bit-perfect',
              'On — locked to the track\'s own format for '
                  '${output!.bitPerfectDevice ?? 'the USB DAC'}',
            )
          else ...[
            (
              'Resampling',
              source == null || mixer == null
                  ? 'Can\'t tell (rate unknown)'
                  : source == mixer
                  ? 'None — ${_khz(source)} in and out'
                  : '${_khz(source)} → ${_khz(mixer)}',
            ),
            if (output != null &&
                output.bitPerfectRequested &&
                output.bitPerfectReason != null)
              ('Bit-perfect', 'Not active: ${output.bitPerfectReason}'),
          ],
          if (_framesPerBuffer != null && mixer != null)
            (
              'Buffer',
              '$_framesPerBuffer frames '
                  '(${(_framesPerBuffer! / mixer * 1000).toStringAsFixed(1)} ms)',
            ),
          (
            'Mode',
            bitPerfect
                ? 'Exclusive to Inzx — other sounds are muted'
                : 'Shared output — other apps\' sounds mix in',
          ),
        ],
      ),
      _Stage(
        icon: _deviceIsSpeaker ? Icons.speaker_rounded : Icons.headphones_rounded,
        title: 'Output',
        value: _deviceName ?? 'This phone',
        rows: [
          if (_systemVolume != null && _systemVolumeMax != null)
            (
              'System volume',
              _systemVolume == _systemVolumeMax
                  ? 'Max — no attenuation'
                  : '$_systemVolume / $_systemVolumeMax',
            ),
          if (!_deviceIsSpeaker)
            (
              'Note',
              'Bluetooth re-encodes audio (SBC/AAC/LDAC…), so what reaches '
                  'your ears is lossy unless the link itself is lossless',
            ),
        ],
      ),
    ];

    return [
      for (var i = 0; i < stages.length; i++)
        _StageTile(
          stage: stages[i],
          isLast: i == stages.length - 1,
          accent: accent,
          primary: primary,
          secondary: secondary,
          isDark: isDark,
        ),
    ];
  }

  // ---- Health ---------------------------------------------------------

  Widget _health(
    PlaybackData data,
    AudioPlayerService player,
    AudioQuality quality,
    Color primary,
    Color secondary,
    bool isDark,
  ) {
    final ahead = player.bufferedAhead;
    final rows = <(String, String)>[
      ('Buffered ahead', '${ahead.inSeconds} s'),
      ('Network', player.isOnUnmeteredNetwork ? 'Wi-Fi' : 'Mobile data'),
      ('Quality setting', _qualityName(quality)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'STREAM HEALTH',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: secondary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              for (final (label, value) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Text(label, style: TextStyle(color: secondary, fontSize: 13.5)),
                      const Spacer(),
                      Text(
                        value,
                        style: TextStyle(
                          color: primary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _qualityName(AudioQuality q) => switch (q) {
    AudioQuality.auto => 'Auto',
    AudioQuality.low => 'Low',
    AudioQuality.medium => 'Medium',
    AudioQuality.high => 'High',
    AudioQuality.max => 'Max',
  };

  static String _khz(int hz) {
    final k = hz / 1000;
    return '${k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1)} kHz';
  }

  /// The accent as text: black accents read as white on a dark sheet.
  static Color _readable(Color accent, bool isDark) {
    final l = accent.computeLuminance();
    if (isDark && l < 0.08) return Colors.white;
    if (!isDark && l > 0.7) return Colors.black;
    return accent;
  }
}

class _Stage {
  const _Stage({
    required this.icon,
    required this.title,
    required this.value,
    required this.rows,
  });
  final IconData icon;
  final String title;
  final String value;
  final List<(String, String)> rows;
}

/// One stage of the pipeline: a node on a vertical line, its headline value,
/// and its detail rows.
class _StageTile extends StatelessWidget {
  const _StageTile({
    required this.stage,
    required this.isLast,
    required this.accent,
    required this.primary,
    required this.secondary,
    required this.isDark,
  });

  final _Stage stage;
  final bool isLast;
  final Color accent;
  final Color primary;
  final Color secondary;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final nodeColor = SignalPathColors.node(accent, isDark);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: nodeColor.withValues(alpha: 0.14),
                    border: Border.all(color: nodeColor.withValues(alpha: 0.5)),
                  ),
                  child: Icon(stage.icon, size: 17, color: nodeColor),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: nodeColor.withValues(alpha: 0.25),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18, top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        stage.title.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: secondary,
                        ),
                      ),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          stage.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final (label, value) in stage.rows)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 104,
                            child: Text(
                              label,
                              style: TextStyle(fontSize: 12.5, color: secondary),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              value,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: primary,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Node colour: the accent, unless it would vanish on the sheet (black on
/// dark), then a neutral.
class SignalPathColors {
  static Color node(Color accent, bool isDark) {
    final l = accent.computeLuminance();
    if (isDark && l < 0.08) return Colors.white70;
    if (!isDark && l > 0.7) return Colors.black87;
    return accent;
  }
}
