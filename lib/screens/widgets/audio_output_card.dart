import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../core/design_system/design_system.dart';
import '../../services/audio_output_service.dart';

/// Audio settings → Output: Hi-Res output and bit-perfect USB DAC.
class AudioOutputCard extends StatefulWidget {
  const AudioOutputCard({
    super.key,
    required this.isDark,
    required this.accentColor,
    required this.switchBuilder,
  });

  final bool isDark;
  final Color accentColor;
  final Widget Function(bool value, ValueChanged<bool>? onChanged)
  switchBuilder;

  @override
  State<AudioOutputCard> createState() => _AudioOutputCardState();
}

class _AudioOutputCardState extends State<AudioOutputCard> {
  bool _hiRes = true;
  bool _bitPerfect = false;
  bool _hiResChanged = false;
  bool _loudness = true;
  bool _loudnessOffOnSpeaker = true;
  AudioOutputStatus? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final hiRes = await AudioOutputService.hiResOutput();
    final bitPerfect = await AudioOutputService.bitPerfectUsb();
    final loudness = await AudioOutputService.loudnessNormalization();
    final offOnSpeaker = await AudioOutputService.loudnessOffOnSpeaker();
    final status = await AudioOutputService.describe();
    if (!mounted) return;
    setState(() {
      _hiRes = hiRes;
      _bitPerfect = bitPerfect;
      _loudness = loudness;
      _loudnessOffOnSpeaker = offOnSpeaker;
      _status = status;
    });
  }

  Color get _primary => widget.isDark ? Colors.white : InzxColors.textPrimary;
  Color get _secondary =>
      widget.isDark ? Colors.white54 : InzxColors.textSecondary;

  @override
  Widget build(BuildContext context) {
    final supported = _status?.bitPerfectSupported ?? true;
    final dac = _status?.usbDac;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isDark
              ? Colors.white12
              : widget.accentColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          // BitChord's loudness normalization (its wording).
          _row(
            icon: Iconsax.volume_high,
            title: 'Loudness normalization',
            subtitle: 'Levels every track to the same loudness',
            value: _loudness,
            onChanged: (v) async {
              setState(() => _loudness = v);
              await AudioOutputService.setLoudnessNormalization(v);
            },
          ),
          if (_loudness) ...[
            const SizedBox(height: 12),
            _row(
              icon: Iconsax.mobile,
              title: 'Disable on Phone Speaker',
              subtitle: 'Plays at the song\'s own level on the built-in speaker',
              value: _loudnessOffOnSpeaker,
              onChanged: (v) async {
                setState(() => _loudnessOffOnSpeaker = v);
                await AudioOutputService.setLoudnessOffOnSpeaker(v);
              },
            ),
          ],
          Divider(
            height: 24,
            color: widget.isDark ? Colors.white10 : Colors.grey.shade300,
          ),
          _row(
            icon: Iconsax.sound,
            title: 'Hi-Res output',
            subtitle: _hiResChanged
                ? 'Applies after you restart Inzx'
                : 'Keeps 24-bit FLAC at full depth instead of cutting it to '
                      '16-bit',
            value: _hiRes,
            onChanged: (v) async {
              setState(() {
                _hiRes = v;
                _hiResChanged = true;
              });
              await AudioOutputService.setHiResOutput(v);
            },
          ),
          Divider(
            height: 24,
            color: widget.isDark ? Colors.white10 : Colors.grey.shade300,
          ),
          _row(
            icon: Iconsax.cpu,
            title: 'Bit-perfect USB DAC',
            subtitle: !supported
                ? 'Needs Android 14 or newer'
                : dac != null
                ? 'Sends $dac each track unchanged, at its own sample rate. '
                      'Other apps\' sounds are muted while it plays.'
                : 'With a USB DAC plugged in, each track reaches it unchanged '
                      'at its own sample rate. Android 14+.',
            value: supported && _bitPerfect,
            onChanged: supported
                ? (v) async {
                    setState(() => _bitPerfect = v);
                    await AudioOutputService.setBitPerfectUsb(v);
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    final active = value && onChanged != null;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: active
                ? widget.accentColor.withValues(alpha: 0.2)
                : (widget.isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.grey.shade200),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 22,
            color: active ? widget.accentColor : _secondary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w600, color: _primary),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 13, color: _secondary, height: 1.3),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        widget.switchBuilder(value, onChanged),
      ],
    );
  }
}
