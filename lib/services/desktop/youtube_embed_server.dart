import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Serves the YouTube player page to the Windows WebView from
/// `http://127.0.0.1:<port>`, as Nivio does for its trailers.
///
/// WebView2 loads inline HTML with NavigateToString, which leaves the page at
/// `about:blank`: the IFrame API then refuses the handshake and the player
/// never reports ready (the podcast screen's endless spinner). A page served
/// over HTTP has a real origin to give the embed. The server listens on the
/// loopback interface only and answers just the pages Inzx registered, under
/// unguessable paths; everything else gets a 404.
class YouTubeEmbedServer {
  YouTubeEmbedServer._();

  static HttpServer? _server;
  static Future<HttpServer>? _starting;
  static final _pages = <String, String>{};
  static final _random = Random.secure();

  /// `http://127.0.0.1:<port>`, starting the server if needed.
  static Future<String> origin() async {
    final server = await (_starting ??= _start());
    return 'http://127.0.0.1:${server.port}';
  }

  static Future<HttpServer> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_handle, onError: (_) {});
    return server;
  }

  /// Publishes [html] and returns its URL. [forget] it when done.
  static Future<String> publish(String html) async {
    final base = await origin();
    final token = List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    _pages[token] = html;
    return '$base/yt/$token';
  }

  static void forget(String url) {
    final token = Uri.tryParse(url)?.pathSegments.lastOrNull;
    if (token != null) _pages.remove(token);
  }

  static void _handle(HttpRequest request) {
    final segments = request.uri.pathSegments;
    final html = segments.length == 2 && segments[0] == 'yt' ? _pages[segments[1]] : null;
    final response = request.response;
    if (html == null || request.method != 'GET') {
      response.statusCode = HttpStatus.notFound;
      unawaited(response.close());
      return;
    }
    response.headers.contentType = ContentType.html;
    response.headers.set('Cache-Control', 'no-store');
    response.add(utf8.encode(html));
    unawaited(response.close());
  }

  static Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
    _starting = null;
    _pages.clear();
  }
}
