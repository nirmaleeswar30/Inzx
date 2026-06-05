import 'dart:convert';
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  Hive.init('/home/nirmal/Development/Inzx/.dart_tool/hive');
  final box = await Hive.openBox('settings');
  final cookie = box.get('ytm_cookie') as String?;
  final authHeader = box.get('ytm_authorization') as String?;
  final visitorData = box.get('ytm_visitor_data') as String?;

  if (cookie == null) {
    print('No cookie found');
    return;
  }

  final headers = {
    'cookie': cookie,
    'content-type': 'application/json',
    if (authHeader != null) 'authorization': authHeader,
  };

  final payload = {
    'context': {
      'client': {
        'clientName': 'WEB_REMIX',
        'clientVersion': '1.20240101.01.00',
        if (visitorData != null) 'visitorData': visitorData,
      }
    },
    'browseId': 'FEmusic_library_corpus_track_artists'
  };

  final res = await http.post(
    Uri.parse('https://music.youtube.com/youtubei/v1/browse?prettyPrint=false'),
    headers: headers,
    body: jsonEncode(payload),
  );

  File('/home/nirmal/Development/Inzx/track_artists.json').writeAsStringSync(res.body);
  print('Saved track_artists.json');

  final payload2 = {
    'context': {
      'client': {
        'clientName': 'WEB_REMIX',
        'clientVersion': '1.20240101.01.00',
        if (visitorData != null) 'visitorData': visitorData,
      }
    },
    'browseId': 'FEmusic_library_corpus_artists'
  };

  final res2 = await http.post(
    Uri.parse('https://music.youtube.com/youtubei/v1/browse?prettyPrint=false'),
    headers: headers,
    body: jsonEncode(payload2),
  );

  File('/home/nirmal/Development/Inzx/corpus_artists.json').writeAsStringSync(res2.body);
  print('Saved corpus_artists.json');
  exit(0);
}
