import 'package:flutter/material.dart';
import 'dart:ui';
import '../../core/utils/platform_utils.dart';
import '../../services/audio_routing_service.dart';
import '../../services/inzx_connect_remote.dart';
import '../../services/inzx_connect_service.dart';
import '../../core/design_system/animations.dart';
import '../inzx_connect_screen.dart';

class AudioRoutingSheet extends StatefulWidget {
  final Color accentColor;

  const AudioRoutingSheet({super.key, required this.accentColor});

  static Future<void> show(BuildContext context, Color accentColor) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => AudioRoutingSheet(accentColor: accentColor),
    );
  }

  @override
  State<AudioRoutingSheet> createState() => _AudioRoutingSheetState();
}

class _AudioRoutingSheetState extends State<AudioRoutingSheet> {
  List<Map<dynamic, dynamic>> _allDevices = [];
  double _currentVolume = 0.5;

  @override
  void initState() {
    super.initState();
    _fetchDevice();
    _initVolume();
  }

  Future<void> _initVolume() async {
    final vol = await AudioRoutingService.getVolume();
    if (mounted) {
      setState(() {
        _currentVolume = vol;
      });
    }
  }

  Future<void> _fetchDevice() async {
    final data = await AudioRoutingService.getActiveDeviceName();
    if (mounted) {
      setState(() {
        final all = data['all'] as List<dynamic>?;
        if (all != null) {
          _allDevices = all
              .map((e) => Map<dynamic, dynamic>.from(e as Map))
              .toList();
        }
      });
    }
  }

  IconData _getIconForDevice(Map<dynamic, dynamic> device) {
    final isSpeaker = device['isSpeaker'] as bool? ?? true;
    final name = (device['name'] as String?) ?? '';
    if (isSpeaker) return Icons.speaker_group_outlined;
    final isHeadphone =
        name.toLowerCase().contains('pods') ||
        name.toLowerCase().contains('buds') ||
        name.toLowerCase().contains('headphone') ||
        name.toLowerCase().contains('wh-') ||
        name.toLowerCase().contains('wf-') ||
        name.toLowerCase().contains('ear');
    return isHeadphone ? Icons.headphones_outlined : Icons.bluetooth_audio;
  }

  @override
  Widget build(BuildContext context) {
    final remote = InzxConnectRemote.instance;
    return BackdropFilter(
      enabled: !isDesktop,
      filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
      child: Container(
        decoration: BoxDecoration(
          color: modalSheetBackground(
            context,
            Colors.black.withValues(alpha: 0.65),
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          border: Border(
            top: BorderSide(
              color: widget.accentColor.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              Text(
                'Audio Output',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              if (InzxConnectService.canScanQr) ...[
                const SizedBox(height: 16),
                ListenableBuilder(
                  listenable: remote,
                  builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final device in remote.pairedDevices)
                        ConnectDeviceCard(
                          key: ValueKey(device.id),
                          device: device,
                          remote: remote,
                        ),
                      TextButton.icon(
                        onPressed: () {
                          final navigator = Navigator.of(context);
                          navigator.pop();
                          InzxConnectScreen.open(navigator);
                        },
                        icon: const Icon(Icons.devices_rounded),
                        label: const Text('Manage paired devices'),
                        style: TextButton.styleFrom(
                          foregroundColor: widget.accentColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Phone output',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // Devices List (Horizontal Cards)
              SizedBox(
                height: 110,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _allDevices.length,
                  clipBehavior: Clip.none,
                  itemBuilder: (context, index) {
                    final device = _allDevices[index];
                    final isActive = device['isActive'] as bool? ?? false;
                    final name = device['name'] as String? ?? 'Device';
                    final icon = _getIconForDevice(device);

                    return BouncyTouch(
                      style: BouncyStyle.card,
                      onTap: () async {
                        if (!isActive) {
                          // Optimistically update UI
                          setState(() {
                            for (var d in _allDevices) {
                              d['isActive'] = (d['name'] == name);
                            }
                          });

                          // Force route natively
                          await AudioRoutingService.setAudioRoute(
                            isSpeaker: device['isSpeaker'] as bool? ?? true,
                          );

                          // Wait for android to route then fetch again
                          Future.delayed(
                            const Duration(milliseconds: 600),
                            _fetchDevice,
                          );
                        }
                      },
                      child: Container(
                        width: 110,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: isActive
                              ? widget.accentColor.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isActive
                                ? widget.accentColor.withValues(alpha: 0.5)
                                : Colors.white.withValues(alpha: 0.1),
                            width: isActive ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              icon,
                              color: isActive
                                  ? widget.accentColor
                                  : Colors.white54,
                              size: 28,
                            ),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                              ),
                              child: Text(
                                name,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isActive
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: isActive
                                      ? Colors.white
                                      : Colors.white70,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 36),

              // Premium Slider
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _currentVolume = 0.0;
                      });
                      AudioRoutingService.setVolume(0.0);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Icon(
                        _currentVolume <= 0.01
                            ? Icons.volume_off_rounded
                            : Icons.volume_down_rounded,
                        color: Colors.white.withValues(alpha: 0.4),
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 10,
                          activeTrackColor: widget.accentColor,
                          inactiveTrackColor: Colors.white.withValues(
                            alpha: 0.1,
                          ),
                          thumbColor: Colors.white,
                          overlayColor: widget.accentColor.withValues(
                            alpha: 0.2,
                          ),
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 9,
                            elevation: 4,
                          ),
                          trackShape: const RoundedRectSliderTrackShape(),
                        ),
                        child: Slider(
                          value: _currentVolume,
                          onChanged: (val) {
                            setState(() {
                              _currentVolume = val;
                            });
                            AudioRoutingService.setVolume(val);
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _currentVolume = 1.0;
                      });
                      AudioRoutingService.setVolume(1.0);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Icon(
                        Icons.volume_up_rounded,
                        color: Colors.white.withValues(alpha: 0.4),
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        ),
      ),
    );
  }
}
