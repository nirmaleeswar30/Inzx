import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:flutter/services.dart';

/// audio_service's backend on Windows: drives the System Media Transport
/// Controls (media keys and the volume flyout) through the C++ runner.
class WindowsMediaControls extends AudioServicePlatform {
  static const _channel = MethodChannel('inzx/windows_media');

  AudioHandlerCallbacks? _callbacks;

  @override
  void setHandlerCallbacks(AudioHandlerCallbacks callbacks) {
    _callbacks = callbacks;
    _channel.setMethodCallHandler(_onNativeCall);
  }

  Future<void> _onNativeCall(MethodCall call) async {
    final callbacks = _callbacks;
    if (callbacks == null) return;
    switch (call.method) {
      case 'play':
        await callbacks.play(const PlayRequest());
      case 'pause':
        await callbacks.pause(const PauseRequest());
      case 'stop':
        await callbacks.stop(const StopRequest());
      case 'next':
        await callbacks.skipToNext(const SkipToNextRequest());
      case 'previous':
        await callbacks.skipToPrevious(const SkipToPreviousRequest());
      case 'seek':
        await callbacks.seek(
          SeekRequest(position: Duration(milliseconds: call.arguments as int)),
        );
    }
  }

  @override
  Future<void> configure(ConfigureRequest request) async {}

  @override
  Future<void> setState(SetStateRequest request) async {
    final state = request.state;
    final actions = state.controls.map((c) => c.action).toSet();
    await _channel.invokeMethod('setState', {
      'playing': state.playing,
      'active': state.processingState != AudioProcessingStateMessage.idle,
      'positionMs': state.updatePosition.inMilliseconds,
      'canNext': actions.contains(MediaActionMessage.skipToNext),
      'canPrevious': actions.contains(MediaActionMessage.skipToPrevious),
    });
  }

  @override
  Future<void> setMediaItem(SetMediaItemRequest request) async {
    final item = request.mediaItem;
    await _channel.invokeMethod('setMediaItem', {
      'title': item.title,
      'artist': item.artist ?? '',
      'album': item.album ?? '',
      'artUri': item.artUri?.toString() ?? '',
      'durationMs': item.duration?.inMilliseconds ?? 0,
    });
  }

  @override
  Future<void> setQueue(SetQueueRequest request) async {}

  @override
  Future<void> stopService(StopServiceRequest request) async {
    await _channel.invokeMethod('clear');
  }
}
