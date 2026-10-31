import 'package:flutter/material.dart';
import '../../services/audio_routing_service.dart';
import '../../core/design_system/animations.dart';

import 'audio_routing_sheet.dart';

class AudioRoutingPill extends StatefulWidget {
  final Color textColor;
  final Color accentColor;

  const AudioRoutingPill({
    super.key,
    required this.textColor,
    required this.accentColor,
  });

  @override
  State<AudioRoutingPill> createState() => _AudioRoutingPillState();
}

class _AudioRoutingPillState extends State<AudioRoutingPill>
    with WidgetsBindingObserver {
  String _deviceName = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchDeviceName();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchDeviceName();
    }
  }

  Future<void> _fetchDeviceName() async {
    final data = await AudioRoutingService.getActiveDeviceName();
    if (mounted) {
      setState(() {
        final active = data['active'] as Map<dynamic, dynamic>?;
        _deviceName = (active?['name'] as String?) ?? 'Internal Speaker';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BouncyTouch(
      style: BouncyStyle.button,
      customScale: 0.95,
      onTap: () async {
        await AudioRoutingSheet.show(context, widget.accentColor);
        // Refetch in case they changed it in the sheet
        _fetchDeviceName();
      },
      // A plain bubble (never glass), matching the lyrics / queue buttons.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: widget.textColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: widget.textColor.withValues(alpha: 0.12),
                  ),
                ),
                child: _content(),
              ),
      ),
    );
  }

  Widget _content() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.speaker_group_rounded,
          size: 16,
          color: widget.textColor.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            _deviceName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: widget.textColor.withValues(alpha: 0.85),
              letterSpacing: 0.3,
            ),
          ),
        ),
      ],
    );
  }
}
