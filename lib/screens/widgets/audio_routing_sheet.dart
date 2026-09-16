import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui';
import '../../services/audio_routing_service.dart';
import '../../core/design_system/animations.dart';

class AudioRoutingSheet extends ConsumerStatefulWidget {
  final Color accentColor;
  
  const AudioRoutingSheet({
    super.key,
    required this.accentColor,
  });

  static Future<void> show(BuildContext context, Color accentColor) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => AudioRoutingSheet(accentColor: accentColor),
    );
  }

  @override
  ConsumerState<AudioRoutingSheet> createState() => _AudioRoutingSheetState();
}

class _AudioRoutingSheetState extends ConsumerState<AudioRoutingSheet> {
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
          _allDevices = all.map((e) => Map<dynamic, dynamic>.from(e as Map)).toList();
        }
      });
    }
  }

  IconData _getIconForDevice(Map<dynamic, dynamic> device) {
    final isSpeaker = device['isSpeaker'] as bool? ?? true;
    final name = (device['name'] as String?) ?? '';
    if (isSpeaker) return Icons.speaker_group_outlined;
    final isHeadphone = name.toLowerCase().contains('pods') ||
        name.toLowerCase().contains('buds') ||
        name.toLowerCase().contains('headphone') ||
        name.toLowerCase().contains('wh-') ||
        name.toLowerCase().contains('wf-') ||
        name.toLowerCase().contains('ear');
    return isHeadphone ? Icons.headphones_outlined : Icons.bluetooth_audio;
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          border: Border(
            top: BorderSide(
              color: widget.accentColor.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
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
                        await AudioRoutingService.setAudioRoute(isSpeaker: device['isSpeaker'] as bool? ?? true);
                        
                        // Wait for android to route then fetch again
                        Future.delayed(const Duration(milliseconds: 600), _fetchDevice);
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
                            color: isActive ? widget.accentColor : Colors.white54,
                            size: 28,
                          ),
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text(
                              name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                                color: isActive ? Colors.white : Colors.white70,
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
                      _currentVolume <= 0.01 ? Icons.volume_off_rounded : Icons.volume_down_rounded, 
                      color: Colors.white.withValues(alpha: 0.4), 
                      size: 24
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
                        inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                        thumbColor: Colors.white,
                        overlayColor: widget.accentColor.withValues(alpha: 0.2),
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9, elevation: 4),
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
                      size: 24
                    ),
                  ),
                ),
              ],
            ),
            
            /* 
            const SizedBox(height: 36),
            
            // Open Settings button Apple style
            BouncyTouch(
              style: BouncyStyle.button,
              onTap: () async {
                final nav = Navigator.of(context);
                await AudioRoutingService.openOutputPanel();
                nav.pop();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'AirPlay & Bluetooth Settings',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            */
            
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }
}
