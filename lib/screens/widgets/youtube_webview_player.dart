import 'dart:io' show Directory, Platform;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../services/desktop/youtube_embed_server.dart';
import 'desktop_podcast_player.dart' show PodcastPlayerHandle;

/// Plays a public YouTube video via the official IFrame Player API inside an
/// [InAppWebView]. The key trick is giving the page a real YouTube origin
/// (`baseUrl` = youtube-nocookie.com + a matching `origin` param), which is what
/// `enablejsapi=1` requires — without it the embed errors out (e.g. 152).
///
/// Windows (WebView2) loads inline HTML with NavigateToString, which ignores
/// the base URL: the page would sit at about:blank, the IFrame API would
/// refuse the handshake and the player never report ready. There the same
/// page is served from 127.0.0.1 instead (YouTubeEmbedServer), as Nivio does.
///
/// Exposes play/pause/seek/mute via a [GlobalKey] to its state, and reports
/// ready/state/error back through callbacks.
class YouTubeWebViewPlayer extends StatefulWidget {
  final String videoId;
  final bool autoPlay;
  final bool showControls;
  final ValueChanged<int>? onStateChanged; // -1,0,1,2,3,5
  final VoidCallback? onReady;
  final ValueChanged<int>? onError;

  /// The player's own fullscreen button was pressed (true) or fullscreen
  /// was left (false). The embed lives in an iframe, so the page sees it as
  /// its iframe entering fullscreen; on desktop that only fills the web
  /// view, and the screen makes the window fullscreen around it.
  final ValueChanged<bool>? onFullscreenChanged;

  /// Desktop: Inzx's own volume (0..1, the player bar's slider), applied
  /// when the embed unmutes; 0 keeps it muted. Android plays at full volume.
  final double volume;

  const YouTubeWebViewPlayer({
    super.key,
    required this.videoId,
    this.autoPlay = true,
    this.showControls = true,
    this.onStateChanged,
    this.onReady,
    this.onError,
    this.onFullscreenChanged,
    this.volume = 1.0,
  });

  @override
  State<YouTubeWebViewPlayer> createState() => YouTubeWebViewPlayerState();
}

class YouTubeWebViewPlayerState extends State<YouTubeWebViewPlayer>
    implements PodcastPlayerHandle {
  InAppWebViewController? _controller;
  bool _isReady = false;

  static const String _origin = 'https://www.youtube-nocookie.com';

  /// The player page. [origin] is the page's own origin, which the embed
  /// must be told; [embedHost] serves the player.
  String _buildHtml({String origin = _origin, String embedHost = _origin}) {
    final autoplay = widget.autoPlay ? 1 : 0;
    final controls = widget.showControls ? 1 : 0;
    final id = widget.videoId;
    // Always start muted for autoplay; unmute after the 'playing' event.
    return '''
<!DOCTYPE html><html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<meta name="referrer" content="strict-origin-when-cross-origin">
<style>*{margin:0;padding:0;overflow:hidden}html,body{width:100%;height:100%;background:#000}
#player{position:absolute;inset:0;width:100%;height:100%;border:0}</style>
</head><body>
<iframe id="player" width="100%" height="100%"
  src="$embedHost/embed/$id?enablejsapi=1&autoplay=$autoplay&mute=1&controls=$controls&playsinline=1&fs=1&iv_load_policy=3&rel=0&modestbranding=1&origin=$origin"
  frameborder="0"
  allow="autoplay; encrypted-media; fullscreen; picture-in-picture; accelerometer; clipboard-write; gyroscope"
  referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>
<script>
  var tag=document.createElement('script');tag.src='https://www.youtube.com/iframe_api';
  var s=document.getElementsByTagName('script')[0];s.parentNode.insertBefore(tag,s);
  function inzxFullscreen(){
    if(window.flutter_inappwebview)window.flutter_inappwebview.callHandler('onFullscreen',
      !!(document.fullscreenElement||document.webkitFullscreenElement));
  }
  document.addEventListener('fullscreenchange',inzxFullscreen);
  document.addEventListener('webkitfullscreenchange',inzxFullscreen);
  var player;
  function onYouTubeIframeAPIReady(){
    player=new YT.Player('player',{events:{
      onReady:function(e){if(window.flutter_inappwebview)window.flutter_inappwebview.callHandler('onReady');},
      onStateChange:function(e){if(window.flutter_inappwebview)window.flutter_inappwebview.callHandler('onStateChange', e.data);},
      onError:function(e){if(window.flutter_inappwebview)window.flutter_inappwebview.callHandler('onError', e.data);}
    }});
  }
</script></body></html>
''';
  }

  /// WebView2's profile lives in the app's local data, not beside inzx.exe
  /// (a program folder may not be writable, and it isn't the place for it).
  /// Null when the WebView2 runtime isn't installed.
  static Future<WebViewEnvironment?>? _environment;

  static Future<WebViewEnvironment?> _windowsEnvironment() => _environment ??= () async {
    try {
      if (await WebViewEnvironment.getAvailableVersion() == null) {
        debugPrint('YouTubeWebViewPlayer: no WebView2 runtime');
        return null;
      }
      final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'webview2_data'));
      await dir.create(recursive: true);
      return await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(userDataFolder: dir.path),
      );
    } catch (e) {
      debugPrint('YouTubeWebViewPlayer: WebView2 environment failed: $e');
      return null;
    }
  }();

  /// Windows: the page comes from YouTubeEmbedServer on 127.0.0.1, so it has
  /// a real origin to hand the embed (Nivio's approach for its trailers).
  String? _pageUrl;

  Future<(WebViewEnvironment?, String)> _windowsPage() async {
    final environment = await _windowsEnvironment();
    final origin = await YouTubeEmbedServer.origin();
    final url = _pageUrl ??= await YouTubeEmbedServer.publish(
      _buildHtml(origin: origin, embedHost: 'https://www.youtube.com'),
    );
    return (environment, url);
  }

  late final Future<(WebViewEnvironment?, String)>? _windowsSetup =
      Platform.isWindows ? _windowsPage() : null;

  @override
  Widget build(BuildContext context) {
    final setup = _windowsSetup;
    if (setup != null) {
      return FutureBuilder<(WebViewEnvironment?, String)>(
        future: setup,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) return const ColoredBox(color: Colors.black);
          return _webView(
            environment: data.$1,
            request: URLRequest(url: WebUri(data.$2)),
          );
        },
      );
    }
    return _webView();
  }

  Widget _webView({WebViewEnvironment? environment, URLRequest? request}) {
    return InAppWebView(
      webViewEnvironment: environment,
      initialUrlRequest: request,
      initialData: request != null
          ? null
          : InAppWebViewInitialData(
              data: _buildHtml(),
              baseUrl: WebUri(_origin), // <-- the origin trick
            ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        transparentBackground: true,
        supportMultipleWindows: false,
        javaScriptCanOpenWindowsAutomatically: false,
      ),
      onWebViewCreated: (c) {
        _controller = c;
        c.addJavaScriptHandler(
          handlerName: 'onReady',
          callback: (_) {
            _isReady = true;
            widget.onReady?.call();
          },
        );
        c.addJavaScriptHandler(
          handlerName: 'onStateChange',
          callback: (args) {
            if (args.isEmpty) return;
            final state = (args[0] as num).toInt();
            // Unmute once actually playing (still counts as a user gesture).
            if (state == 1 && widget.autoPlay) {
              Future.delayed(const Duration(milliseconds: 300), () {
                if (!mounted || _controller == null) return;
                // The music players' volume is mpv's, which is cubic: the
                // same slider position gives the same loudness here.
                final v = widget.volume.clamp(0.0, 1.0);
                if (v <= 0) return; // muted in Inzx: stay muted
                final level = (v * v * v * 100).round().clamp(1, 100);
                _controller!.evaluateJavascript(source: '''
                  var mp=document.getElementById('movie_player');
                  if(mp&&mp.unMute){mp.unMute();mp.setVolume($level);}
                  else{var f=document.getElementById('player');
                    if(f){f.contentWindow.postMessage('{"event":"command","func":"unMute","args":""}','*');
                          f.contentWindow.postMessage('{"event":"command","func":"setVolume","args":[$level]}','*');}}
                ''');
              });
            }
            widget.onStateChanged?.call(state);
          },
        );
        c.addJavaScriptHandler(
          handlerName: 'onFullscreen',
          callback: (args) {
            if (args.isNotEmpty) widget.onFullscreenChanged?.call(args[0] == true);
          },
        );
        c.addJavaScriptHandler(
          handlerName: 'onError',
          callback: (args) {
            if (args.isNotEmpty) widget.onError?.call((args[0] as num).toInt());
          },
        );
      },
    );
  }

  Future<void> play() => _eval('player.playVideo()', 'mp.playVideo()', 'v.play()');
  Future<void> pause() =>
      _eval('player.pauseVideo()', 'mp.pauseVideo()', 'v.pause()');

  @override
  Future<void> seekTo(int seconds) => _eval(
        'player.seekTo($seconds,true);player.playVideo()',
        'mp.seekTo($seconds,true)',
        'v.currentTime=$seconds',
      );

  bool get isReady => _isReady;

  /// Leaves the page's own fullscreen (the embed's), if it's in it.
  Future<void> exitFullscreen() async {
    await _controller?.evaluateJavascript(
      source: 'if(document.fullscreenElement&&document.exitFullscreen)document.exitFullscreen();',
    );
  }

  Future<void> _eval(String api, String mp, String raw) async {
    await _controller?.evaluateJavascript(source:
        'try{if(typeof player!=="undefined"&&player&&player.seekTo){$api;}'
        'else{var mp=document.getElementById("movie_player");if(mp){$mp;}'
        'else{var v=document.querySelector("video");if(v){$raw;}}}}catch(e){}');
  }

  @override
  void dispose() {
    final controller = _controller;
    _controller = null;
    // Only on mobile: on desktop the native view is destroyed as the route
    // pops, and in release builds that races ahead of this, so a call into
    // the half-destroyed controller crashes the app (Nivio hit this). The
    // view stops playback itself when it goes.
    if (controller != null && !Platform.isWindows && !Platform.isLinux) {
      controller.evaluateJavascript(source:
          'var mp=document.getElementById("movie_player");if(mp&&mp.stopVideo)mp.stopVideo();'
          'else{var v=document.querySelector("video");if(v)v.pause();}');
    }
    final page = _pageUrl;
    if (page != null) YouTubeEmbedServer.forget(page);
    super.dispose();
  }
}
