import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inzx/models/models.dart';
import 'package:inzx/services/addons/addon_client.dart';
import 'package:inzx/services/addons/addon_models.dart';
import 'package:inzx/services/addons/addon_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  group('AddonEntry', () {
    test('serializes to and from JSON correctly', () {
      final entry = AddonEntry(
        id: 'entry_1',
        name: 'LastWave Server',
        baseUrl: 'https://addon.example.com/a/secret-token',
        enabled: true,
        quality: AddonQuality.hiRes,
      );

      final json = entry.toJson();
      expect(json['id'], 'entry_1');
      expect(json['name'], 'LastWave Server');
      expect(json['baseUrl'], 'https://addon.example.com/a/secret-token');
      expect(json['enabled'], isTrue);
      expect(json['quality'], 'hi_res');

      final restored = AddonEntry.fromJson(json);
      expect(restored.id, entry.id);
      expect(restored.name, entry.name);
      expect(restored.baseUrl, entry.baseUrl);
      expect(restored.enabled, entry.enabled);
      expect(restored.quality, entry.quality);
      expect(restored.host, 'addon.example.com');
    });

    test('parses host correctly from various URLs', () {
      final e1 = AddonEntry(
        id: '1',
        name: 'Test',
        baseUrl: 'https://lossless.myserver.org:8080/path',
      );
      expect(e1.host, 'lossless.myserver.org');
    });
  });

  group('AddonService management', () {
    late AddonService service;

    setUp(() {
      service = AddonService.instance;
      service.resetForTesting();
    });

    tearDown(() {
      service.resetForTesting();
    });

    test('isInstalled and isEnabled reflect installed addon states', () async {
      expect(service.isInstalled, isFalse);
      expect(service.isEnabled, isFalse);

      final e1 = AddonEntry(
        id: '1',
        name: 'Primary Addon',
        baseUrl: 'https://first.com',
        enabled: true,
      );
      final e2 = AddonEntry(
        id: '2',
        name: 'Secondary Addon',
        baseUrl: 'https://second.com',
        enabled: false,
      );

      service.resetForTesting(addons: [e1, e2]);

      expect(service.isInstalled, isTrue);
      expect(service.isEnabled, isTrue);
      expect(service.name, 'Primary Addon');
      expect(service.addons.length, 2);

      // Disable e1: now all are disabled
      await service.setAddonEnabled(0, false);
      expect(service.isEnabled, isFalse);

      // Enable e2: now enabled again
      await service.setAddonEnabled(1, true);
      expect(service.isEnabled, isTrue);
    });

    test('setAddonQuality updates the quality for that specific addon', () async {
      final e1 = AddonEntry(
        id: '1',
        name: 'Addon 1',
        baseUrl: 'https://first.com',
        quality: AddonQuality.lossless,
      );
      final e2 = AddonEntry(
        id: '2',
        name: 'Addon 2',
        baseUrl: 'https://second.com',
        quality: AddonQuality.lossless,
      );

      service.resetForTesting(addons: [e1, e2]);

      await service.setAddonQuality(1, AddonQuality.hiRes);

      expect(service.addons[0].quality, AddonQuality.lossless);
      expect(service.addons[1].quality, AddonQuality.hiRes);
    });

    test('reorder changes priority sequence', () async {
      final e1 = AddonEntry(id: '1', name: 'Alpha', baseUrl: 'https://alpha.com');
      final e2 = AddonEntry(id: '2', name: 'Beta', baseUrl: 'https://beta.com');
      final e3 = AddonEntry(id: '3', name: 'Gamma', baseUrl: 'https://gamma.com');

      service.resetForTesting(addons: [e1, e2, e3]);

      expect(service.addons.map((a) => a.name).toList(), ['Alpha', 'Beta', 'Gamma']);

      // Move Gamma to top (index 2 -> 0)
      await service.reorder(2, 0);
      expect(service.addons.map((a) => a.name).toList(), ['Gamma', 'Alpha', 'Beta']);

      // Move Gamma down (index 0 -> 1)
      await service.reorder(0, 1);
      expect(service.addons.map((a) => a.name).toList(), ['Alpha', 'Gamma', 'Beta']);
    });

    test('removeAt removes only targeted addon', () async {
      final e1 = AddonEntry(id: '1', name: 'Alpha', baseUrl: 'https://alpha.com');
      final e2 = AddonEntry(id: '2', name: 'Beta', baseUrl: 'https://beta.com');

      service.resetForTesting(addons: [e1, e2]);

      await service.removeAt(0);

      expect(service.addons.length, 1);
      expect(service.addons.first.name, 'Beta');
    });
  });

  group('AddonService multi-addon fallback resolution', () {
    late AddonService service;

    setUp(() {
      service = AddonService.instance;
      service.resetForTesting();
    });

    tearDown(() {
      service.resetForTesting();
    });

    final testTrack = Track(
      id: 'song_123',
      title: 'Starboy',
      artist: 'The Weeknd',
      album: 'Starboy',
      duration: const Duration(seconds: 230),
    );

    test('falls back to Addon #2 when Addon #1 has no search candidates', () async {
      // Mock Client 1: returns empty search results
      final mockHttp1 = MockClient((request) async {
        if (request.url.path.contains('/search')) {
          return http.Response(jsonEncode({'tracks': []}), 200);
        }
        return http.Response('Not found', 404);
      });

      // Mock Client 2: returns a matching candidate and lossless stream
      final mockHttp2 = MockClient((request) async {
        if (request.url.path.contains('/search')) {
          return http.Response(
            jsonEncode({
              'tracks': [
                {
                  'id': 'cand_weeknd_starboy',
                  'title': 'Starboy',
                  'artist': 'The Weeknd',
                  'album': 'Starboy',
                  'duration': 230,
                  'audioQuality': 'LOSSLESS',
                }
              ]
            }),
            200,
          );
        }
        if (request.url.path.contains('/stream/cand_weeknd_starboy')) {
          return http.Response(
            jsonEncode({
              'url': 'https://second.com/stream/cand_weeknd_starboy.flac',
              'format': 'flac',
              'bitDepth': 16,
              'sampleRate': 44100,
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final addon1 = AddonEntry(
        id: 'addon_1',
        name: 'Empty Source',
        baseUrl: 'https://first.com',
        client: AddonClient('https://first.com', httpClient: mockHttp1),
      );

      final addon2 = AddonEntry(
        id: 'addon_2',
        name: 'Fallback Source',
        baseUrl: 'https://second.com',
        client: AddonClient('https://second.com', httpClient: mockHttp2),
      );

      service.resetForTesting(addons: [addon1, addon2]);

      final match = await service.matchFor(testTrack);

      expect(match, isNotNull);
      expect(match!.addonName, 'Fallback Source');
      expect(match.track.id, 'cand_weeknd_starboy');
      expect(match.stream.isLossless, isTrue);
    });

    test('falls back to Addon #2 when Addon #1 throws AddonMiss on stream', () async {
      // Mock Client 1: finds candidate but stream returns 404
      final mockHttp1 = MockClient((request) async {
        if (request.url.path.contains('/search')) {
          return http.Response(
            jsonEncode({
              'tracks': [
                {
                  'id': 'cand_1',
                  'title': 'Starboy',
                  'artist': 'The Weeknd',
                  'album': 'Starboy',
                  'duration': 230,
                  'audioQuality': 'LOSSLESS',
                }
              ]
            }),
            200,
          );
        }
        if (request.url.path.contains('/stream/cand_1')) {
          return http.Response(jsonEncode({'error': 'Track not found in catalogue'}), 404);
        }
        return http.Response('Not found', 404);
      });

      // Mock Client 2: succeeds
      final mockHttp2 = MockClient((request) async {
        if (request.url.path.contains('/search')) {
          return http.Response(
            jsonEncode({
              'tracks': [
                {
                  'id': 'cand_2',
                  'title': 'Starboy',
                  'artist': 'The Weeknd',
                  'album': 'Starboy',
                  'duration': 230,
                  'audioQuality': 'LOSSLESS',
                }
              ]
            }),
            200,
          );
        }
        if (request.url.path.contains('/stream/cand_2')) {
          return http.Response(
            jsonEncode({
              'url': 'https://second.com/stream/cand_2.flac',
              'format': 'flac',
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final addon1 = AddonEntry(
        id: 'addon_1',
        name: 'Missing Stream Source',
        baseUrl: 'https://first.com',
        client: AddonClient('https://first.com', httpClient: mockHttp1),
      );

      final addon2 = AddonEntry(
        id: 'addon_2',
        name: 'Working Source',
        baseUrl: 'https://second.com',
        client: AddonClient('https://second.com', httpClient: mockHttp2),
      );

      service.resetForTesting(addons: [addon1, addon2]);

      final match = await service.matchFor(testTrack);

      expect(match, isNotNull);
      expect(match!.addonName, 'Working Source');
      expect(match.track.id, 'cand_2');
    });

    test('skips disabled Addon #1 and uses Addon #2 directly', () async {
      var addon1Queried = false;

      final mockHttp1 = MockClient((request) async {
        addon1Queried = true;
        return http.Response('{"tracks":[]}', 200);
      });

      final mockHttp2 = MockClient((request) async {
        if (request.url.path.contains('/search')) {
          return http.Response(
            jsonEncode({
              'tracks': [
                {
                  'id': 'cand_2',
                  'title': 'Starboy',
                  'artist': 'The Weeknd',
                  'album': 'Starboy',
                  'duration': 230,
                  'audioQuality': 'LOSSLESS',
                }
              ]
            }),
            200,
          );
        }
        if (request.url.path.contains('/stream/cand_2')) {
          return http.Response(
            jsonEncode({
              'url': 'https://second.com/stream/cand_2.flac',
              'format': 'flac',
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final addon1 = AddonEntry(
        id: 'addon_1',
        name: 'Disabled Source',
        baseUrl: 'https://first.com',
        enabled: false,
        client: AddonClient('https://first.com', httpClient: mockHttp1),
      );

      final addon2 = AddonEntry(
        id: 'addon_2',
        name: 'Enabled Source',
        baseUrl: 'https://second.com',
        enabled: true,
        client: AddonClient('https://second.com', httpClient: mockHttp2),
      );

      service.resetForTesting(addons: [addon1, addon2]);

      final match = await service.matchFor(testTrack);

      expect(addon1Queried, isFalse, reason: 'Disabled addon should not be queried');
      expect(match, isNotNull);
      expect(match!.addonName, 'Enabled Source');
    });

    test('marks as settled miss when all enabled addons fail', () async {
      final mockHttp1 = MockClient((request) async {
        return http.Response(jsonEncode({'tracks': []}), 200);
      });

      final mockHttp2 = MockClient((request) async {
        return http.Response(jsonEncode({'tracks': []}), 200);
      });

      final addon1 = AddonEntry(
        id: 'addon_1',
        name: 'Source 1',
        baseUrl: 'https://first.com',
        client: AddonClient('https://first.com', httpClient: mockHttp1),
      );

      final addon2 = AddonEntry(
        id: 'addon_2',
        name: 'Source 2',
        baseUrl: 'https://second.com',
        client: AddonClient('https://second.com', httpClient: mockHttp2),
      );

      service.resetForTesting(addons: [addon1, addon2]);

      expect(service.isSettledMiss(testTrack), isFalse);

      final match = await service.matchFor(testTrack);
      expect(match, isNull);
      expect(service.isSettledMiss(testTrack), isTrue);
    });
  });
}
