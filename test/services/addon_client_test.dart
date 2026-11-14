import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/services/addons/addon_client.dart';
import 'package:inzx/services/addons/addon_models.dart';

void main() {
  group('AddonTrack lossless detection', () {
    test('recognises lossless when quality is LOSSLESS or HI_RES', () {
      final t1 = AddonTrack.fromJson({
        'id': '1',
        'title': 'Test Song',
        'audioQuality': 'LOSSLESS',
      });
      expect(t1.isLossless, isTrue);

      final t2 = AddonTrack.fromJson({
        'id': '2',
        'title': 'Test Song',
        'audioQuality': 'HI_RES_LOSSLESS',
      });
      expect(t2.isLossless, isTrue);
    });

    test('recognises format: flac even if audioQuality is HIGH or empty', () {
      final t1 = AddonTrack.fromJson({
        'id': '1',
        'title': 'Test Song',
        'audioQuality': 'HIGH',
        'format': 'flac',
      });
      expect(t1.isLossless, isTrue);

      final t2 = AddonTrack.fromJson({
        'id': '2',
        'title': 'Test Song',
        'codec': 'flac',
      });
      expect(t2.isLossless, isTrue);
    });

    test('rejects lossy format like mp3 when quality is HIGH', () {
      final t = AddonTrack.fromJson({
        'id': '1',
        'title': 'Test Song',
        'audioQuality': 'HIGH',
        'format': 'mp3',
      });
      expect(t.isLossless, isFalse);
    });

    test('handles duration in both seconds and milliseconds', () {
      final inSec = AddonTrack.fromJson({
        'id': '1',
        'title': 'Test',
        'duration': 215.5,
      });
      expect(inSec.duration.inMilliseconds, 215500);

      final inMs = AddonTrack.fromJson({
        'id': '2',
        'title': 'Test',
        'duration': 215500,
      });
      expect(inMs.duration.inMilliseconds, 215500);
    });
  });

  group('AddonStream and parseStream', () {
    test('infers flac when assumeFlac is true (LastWave addon)', () {
      final stream = AddonClient.parseStream({
        'url': 'https://example.com/stream/12345',
      }, assumeFlac: true);

      expect(stream.codec, 'flac');
      expect(stream.isLossless, isTrue);
    });

    test('does not infer flac when assumeFlac is false (Generic addon with no codec)', () {
      final stream = AddonClient.parseStream({
        'url': 'https://example.com/stream/12345',
      }, assumeFlac: false);

      expect(stream.codec, '');
      expect(stream.isLossless, isFalse);
    });

    test('infers codec from format or url extension for generic addons', () {
      final stream1 = AddonClient.parseStream({
        'url': 'https://example.com/audio/song.flac?token=abc',
      }, assumeFlac: false);
      expect(stream1.codec, 'flac');
      expect(stream1.isLossless, isTrue);

      final stream2 = AddonClient.parseStream({
        'url': 'https://example.com/stream/123',
        'format': 'flac',
      }, assumeFlac: false);
      expect(stream2.codec, 'flac');
      expect(stream2.isLossless, isTrue);

      final stream3 = AddonClient.parseStream({
        'url': 'https://example.com/stream/123',
        'codec': 'mp3',
      }, assumeFlac: false);
      expect(stream3.codec, 'mp3');
      expect(stream3.isLossless, isFalse);
    });

    test('refuses DRM-protected streams with AddonMiss', () {
      expect(
        () => AddonClient.parseStream({
          'url': 'https://example.com/stream/123',
          'drm': true,
        }, assumeFlac: false),
        throwsA(isA<AddonMiss>()),
      );

      expect(
        () => AddonClient.parseStream({
          'url': 'https://example.com/stream/123',
          'encrypted': true,
        }, assumeFlac: false),
        throwsA(isA<AddonMiss>()),
      );

      expect(
        () => AddonClient.parseStream({
          'url': 'https://example.com/stream/123',
          'licenseUrl': 'https://license.server/widevine',
        }, assumeFlac: false),
        throwsA(isA<AddonMiss>()),
      );
    });

    test('throws AddonMiss on empty URL or success: false', () {
      expect(
        () => AddonClient.parseStream({
          'url': '',
          'error': 'Track unavailable',
        }, assumeFlac: false),
        throwsA(isA<AddonMiss>()),
      );

      expect(
        () => AddonClient.parseStream({
          'success': false,
          'message': 'Not found',
        }, assumeFlac: false),
        throwsA(isA<AddonMiss>()),
      );
    });
  });

  group('AddonManifest and matchQuality', () {
    test('matches quality options from addon manifest', () {
      final options = ['lossless', 'high', 'medium', 'low'];
      expect(AddonClient.matchQuality(AddonQuality.lossless, options), 'lossless');
      expect(AddonClient.matchQuality(AddonQuality.hiRes, options), 'lossless');

      final flacOptions = ['FLAC', 'MP3_320', 'MP3_128'];
      expect(AddonClient.matchQuality(AddonQuality.lossless, flacOptions), 'FLAC');

      final hiResOptions = ['24bit', '16bit', 'standard'];
      expect(AddonClient.matchQuality(AddonQuality.hiRes, hiResOptions), '24bit');
      expect(AddonClient.matchQuality(AddonQuality.lossless, hiResOptions), '16bit');
    });

    test('parses manifest settings whether list or map or root qualities', () {
      final m1 = AddonManifest.fromJson({
        'id': 'test1',
        'name': 'Test 1',
        'version': '1.0.0',
        'resources': ['search', 'stream'],
        'settings': [
          {
            'key': 'quality',
            'options': ['flac', 'mp3'],
          }
        ],
      });
      expect(m1.isPlayable, isTrue);
      expect(m1.setting('quality')?.options, ['flac', 'mp3']);

      final m2 = AddonManifest.fromJson({
        'id': 'test2',
        'name': 'Test 2',
        'version': '1.0.0',
        'resources': [{'name': 'search'}, {'name': 'stream'}],
        'settings': {
          'quality': {
            'options': ['lossless', 'high'],
          }
        },
      });
      expect(m2.isPlayable, isTrue);
      expect(m2.setting('quality')?.options, ['lossless', 'high']);

      final m3 = AddonManifest.fromJson({
        'id': 'test3',
        'name': 'Test 3',
        'version': '1.0.0',
        'resources': ['tracks'],
        'qualities': ['flac', 'mp3'],
      });
      expect(m3.isPlayable, isTrue);
      expect(m3.setting('quality')?.options, ['flac', 'mp3']);
    });
  });

  group('LastWave request signing', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000);
    // HMAC-SHA256 over "1700000000\nGET\n/a/tok123/stream/42\ntok123", keyed
    // with the secret's UTF-8 text (not hex-decoded), as LastWave's client.
    const expected =
        '9cb48c1e52d357894c914e905a1c8c984f79c7f20be908c04adf03bf0d2a3039';

    test('signs with the secret as UTF-8 text', () {
      final headers = AddonClient.signatureHeaders(
        secret:
            '83f0d38ce35653ef70743cd8ca4ea9044d154af938c93cb64a616f2b1e9531ba',
        path: '/a/tok123/stream/42',
        token: 'tok123',
        now: now,
      );
      expect(headers, {'X-LW-TS': '1700000000', 'X-LW-Sign': expected});
    });

    test('signs the path without its query or fragment', () {
      final client = AddonClient('https://addon.example.com/a/tok123');
      final plain = client.requestHeaders(
        Uri.parse('https://addon.example.com/a/tok123/stream/42'),
        download: false,
        now: now,
      );
      final withQuery = client.requestHeaders(
        Uri.parse(
          'https://addon.example.com/a/tok123/stream/42'
          '?quality=lossless&atmos=none#x',
        ),
        download: false,
        now: now,
      );
      expect(withQuery['X-LW-Sign'], plain['X-LW-Sign']);
      expect(withQuery['X-LW-Intent'], 'stream');
      expect(withQuery['User-Agent'], 'LastWave-Player/1.0');
      if (kAddonClientSecret ==
          '83f0d38ce35653ef70743cd8ca4ea9044d154af938c93cb64a616f2b1e9531ba') {
        expect(withQuery['X-LW-Sign'], expected);
      }
    });
  });
}
