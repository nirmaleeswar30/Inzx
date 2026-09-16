import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioRoutingService {
  static const MethodChannel _channel = MethodChannel('inzx/audio_routing');
  static bool? lastRoutedIsSpeaker;

  static Future<Map<String, dynamic>> getActiveDeviceName() async {
    try {
      if (await Permission.bluetoothConnect.status.isDenied) {
        await Permission.bluetoothConnect.request();
      }
      
      final data = await _channel.invokeMapMethod<String, dynamic>('getActiveDeviceName');
      if (data != null) {
        return data;
      }
      return {
        'active': {'name': 'Internal Speaker', 'isSpeaker': true},
        'all': [{'name': 'Internal Speaker', 'isSpeaker': true, 'isActive': true}]
      };
    } catch (e) {
      return {
        'active': {'name': 'Internal Speaker', 'isSpeaker': true},
        'all': [{'name': 'Internal Speaker', 'isSpeaker': true, 'isActive': true}]
      };
    }
  }

  static Future<bool> openOutputPanel() async {
    try {
      final result = await _channel.invokeMethod<bool>('openOutputPanel');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<double> getVolume() async {
    try {
      final vol = await _channel.invokeMethod<double>('getVolume');
      return vol ?? 0.5;
    } catch (e) {
      return 0.5;
    }
  }

  static Future<void> setVolume(double volume) async {
    try {
      await _channel.invokeMethod('setVolume', {'volume': volume});
    } catch (e) {
      // Ignore
    }
  }

  static Future<void> setAudioRoute({required bool isSpeaker}) async {
    try {
      lastRoutedIsSpeaker = isSpeaker;
      await _channel.invokeMethod('setAudioRoute', {'isSpeaker': isSpeaker});
    } catch (e) {
      // Ignore
    }
  }

  static Future<void> reapplyAudioRoute() async {
    if (lastRoutedIsSpeaker != null) {
      await setAudioRoute(isSpeaker: lastRoutedIsSpeaker!);
    }
  }
}
