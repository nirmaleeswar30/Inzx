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

class _AudioRoutingPillState extends State<AudioRoutingPill> with WidgetsBindingObserver {
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          _deviceName,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: widget.textColor.withValues(alpha: 0.7),
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}
