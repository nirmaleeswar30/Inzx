import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;

/// Signature cipher decryption utility
///
/// YouTube encrypts some stream URLs with a signature cipher.
/// This requires fetching their player.js and extracting the
/// decryption function to transform the signature.
///
/// Based on NewPipe's signature decryption implementation.
class SignatureCipherDecryptor {
  static SignatureCipherDecryptor? _instance;
  static SignatureCipherDecryptor get instance =>
      _instance ??= SignatureCipherDecryptor._();

  SignatureCipherDecryptor._();

  final http.Client _client = http.Client();

  /// Cached decryption steps
  List<_TransformStep>? _cachedSteps;
  String? _cachedPlayerJsUrl;

  /// Decrypt a signature cipher to get the final URL
  Future<String?> decrypt(String cipher) async {
    try {
      // Parse cipher parameters
      final params = Uri.splitQueryString(cipher);
      final encodedUrl = params['url'];
      final signature = params['s'];
      final signatureParam = params['sp'] ?? 'signature';

      if (encodedUrl == null || signature == null) {
        if (kDebugMode) {
          print('SignatureCipher: Missing url or signature');
        }
        return null;
      }

      // Decode URL
      final url = Uri.decodeFull(encodedUrl);

      // Get or fetch decryption steps
      final steps = await _getDecryptionSteps();
      if (steps == null || steps.isEmpty) {
        if (kDebugMode) {
          print('SignatureCipher: Could not get decryption steps');
        }
        return null;
      }

      // Transform signature
      final decryptedSig = _transformSignature(signature, steps);

      // Build final URL
      return '$url&$signatureParam=${Uri.encodeComponent(decryptedSig)}';
    } catch (e) {
      if (kDebugMode) {
        print('SignatureCipher: Decryption failed: $e');
      }
      return null;
    }
  }

  /// Get decryption steps, fetching from YouTube if needed
  Future<List<_TransformStep>?> _getDecryptionSteps() async {
    if (_cachedSteps != null) {
      return _cachedSteps;
    }

    try {
      // First, get the player.js URL from YouTube
      final playerJsUrl = await _getPlayerJsUrl();
      if (playerJsUrl == null) {
        if (kDebugMode) {
          print('SignatureCipher: Could not find player.js URL');
        }
        return null;
      }

      // Check if we already have steps for this player version
      if (playerJsUrl == _cachedPlayerJsUrl && _cachedSteps != null) {
        return _cachedSteps;
      }

      // Fetch player.js
      final response = await _client
          .get(Uri.parse(playerJsUrl))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        if (kDebugMode) {
          print('SignatureCipher: Failed to fetch player.js');
        }
        return null;
      }

      // Extract decryption steps
      final steps = _extractDecryptionSteps(response.body);
      if (steps != null) {
        _cachedSteps = steps;
        _cachedPlayerJsUrl = playerJsUrl;
      }

      return steps;
    } catch (e) {
      if (kDebugMode) {
        print('SignatureCipher: Error getting decryption steps: $e');
      }
      return null;
    }
  }

  /// Get the player.js URL from YouTube embed page
  Future<String?> _getPlayerJsUrl() async {
    try {
      final response = await _client
          .get(
            Uri.parse(
              'https://www.youtube.com/embed/dQw4w9WgXcQ',
            ), // Any valid video
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      // Look for player.js URL in the page
      // Pattern: /s/player/{version}/player_ias.vflset/en_US/base.js
      final match = RegExp(
        r'(/s/player/[^"]+/base\.js)',
      ).firstMatch(response.body);
      if (match != null) {
        return 'https://www.youtube.com${match.group(1)}';
      }

      // Alternative pattern
      final altMatch = RegExp(r'"jsUrl":"([^"]+)"').firstMatch(response.body);
      if (altMatch != null) {
        final jsUrl = altMatch.group(1)!.replaceAll(r'\/', '/');
        if (jsUrl.startsWith('/')) {
          return 'https://www.youtube.com$jsUrl';
        }
        return jsUrl;
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('SignatureCipher: Error getting player.js URL: $e');
      }
      return null;
    }
  }

  /// Extract decryption steps from player.js
  List<_TransformStep>? _extractDecryptionSteps(String playerJs) {
    try {
      // Find the decryption function
      // It typically looks like: function(a){a=a.split("");XY.AB(a,N);...return a.join("")}

      // Step 1: Find the initial function name
      // Look for pattern: .set("sig",encodeURIComponent(XX(decodeURIComponent(
      final funcNameMatch = RegExp(
        r'\.set\s*\([^,]+,\s*encodeURIComponent\s*\(\s*([a-zA-Z0-9$_]+)\s*\(',
      ).firstMatch(playerJs);

      String? funcName;
      if (funcNameMatch != null) {
        funcName = funcNameMatch.group(1);
      }

      // Alternative: Look for signature decryption function pattern
      if (funcName == null) {
        final altMatch = RegExp(
          r'([a-zA-Z0-9$_]+)\s*=\s*function\s*\([a-zA-Z]\)\s*\{\s*[a-zA-Z]\s*=\s*[a-zA-Z]\.split\s*\(\s*""\s*\)',
        ).firstMatch(playerJs);
        funcName = altMatch?.group(1);
      }

      if (funcName == null) {
        if (kDebugMode) {
          print('SignatureCipher: Could not find decryption function name');
        }
        return null;
      }

      if (kDebugMode) {
        print('SignatureCipher: Found function: $funcName');
      }

      // Step 2: Find the function body
      final funcBodyMatch = RegExp(
        '${RegExp.escape(funcName)}\\s*=\\s*function\\s*\\([a-zA-Z]\\)\\s*\\{([^}]+)\\}',
      ).firstMatch(playerJs);

      if (funcBodyMatch == null) {
        if (kDebugMode) {
          print('SignatureCipher: Could not find function body');
        }
        return null;
      }

      final funcBody = funcBodyMatch.group(1)!;
      if (kDebugMode) {
        print(
          'SignatureCipher: Found function body (${funcBody.length} chars)',
        );
      }

      // Step 3: Find the helper object name
      final helperMatch = RegExp(
        r'([a-zA-Z0-9$_]+)\.[a-zA-Z0-9$_]+\s*\(',
      ).firstMatch(funcBody);

      if (helperMatch == null) {
        if (kDebugMode) {
          print('SignatureCipher: Could not find helper object');
        }
        return null;
      }

      final helperName = helperMatch.group(1)!;
      if (kDebugMode) {
        print('SignatureCipher: Found helper: $helperName');
      }

      // Step 4: Find the helper object definition
      final helperDefMatch = RegExp(
        'var ${RegExp.escape(helperName)}\\s*=\\s*\\{([\\s\\S]*?)\\};',
      ).firstMatch(playerJs);

      if (helperDefMatch == null) {
        if (kDebugMode) {
          print('SignatureCipher: Could not find helper definition');
        }
        return null;
      }

      final helperDef = helperDefMatch.group(1)!;

      // Step 5: Parse helper methods
      final methodMap = <String, _TransformType>{};

      // Reverse: function(a){a.reverse()}
      final reverseMatch = RegExp(
        r'([a-zA-Z0-9$_]+)\s*:\s*function\s*\([a-zA-Z]\)\s*\{[^}]*reverse',
      ).allMatches(helperDef);
      for (final m in reverseMatch) {
        methodMap[m.group(1)!] = _TransformType.reverse;
      }

      // Splice: function(a,b){a.splice(0,b)}
      final spliceMatch = RegExp(
        r'([a-zA-Z0-9$_]+)\s*:\s*function\s*\([a-zA-Z],[a-zA-Z]\)\s*\{[^}]*splice',
      ).allMatches(helperDef);
      for (final m in spliceMatch) {
        methodMap[m.group(1)!] = _TransformType.splice;
      }

      // Swap: function(a,b){var c=a[0];a[0]=a[b%a.length];a[b%a.length]=c}
      final swapMatch = RegExp(
        r'([a-zA-Z0-9$_]+)\s*:\s*function\s*\([a-zA-Z],[a-zA-Z]\)\s*\{[^}]*\[0\]',
      ).allMatches(helperDef);
      for (final m in swapMatch) {
        if (!methodMap.containsKey(m.group(1)!)) {
          methodMap[m.group(1)!] = _TransformType.swap;
        }
      }

      if (kDebugMode) {
        print('SignatureCipher: Found ${methodMap.length} helper methods');
      }

      // Step 6: Parse function calls in order
      final steps = <_TransformStep>[];
      final callPattern = RegExp(
        '${RegExp.escape(helperName)}\\.([a-zA-Z0-9\$_]+)\\s*\\([a-zA-Z]\\s*,\\s*(\\d+)\\)',
      );

      for (final match in callPattern.allMatches(funcBody)) {
        final methodName = match.group(1)!;
        final param = int.tryParse(match.group(2)!) ?? 0;
        final type = methodMap[methodName];

        if (type != null) {
          steps.add(_TransformStep(type, param));
        }
      }

      // Also check for reverse without parameter
      if (funcBody.contains('.reverse()') || funcBody.contains('.reverse(a)')) {
        // Find position and insert
        final reversePattern = RegExp(
          '${RegExp.escape(helperName)}\\.([a-zA-Z0-9\$_]+)\\s*\\([a-zA-Z]\\)',
        );
        for (final match in reversePattern.allMatches(funcBody)) {
          final methodName = match.group(1)!;
          if (methodMap[methodName] == _TransformType.reverse) {
            steps.add(_TransformStep(_TransformType.reverse, 0));
          }
        }
      }

      if (kDebugMode) {
        print('SignatureCipher: Extracted ${steps.length} transform steps');
      }
      return steps.isEmpty ? null : steps;
    } catch (e) {
      if (kDebugMode) {
        print('SignatureCipher: Error extracting steps: $e');
      }
      return null;
    }
  }

  /// Apply transformation steps to signature
  String _transformSignature(String signature, List<_TransformStep> steps) {
    var chars = signature.split('');

    for (final step in steps) {
      switch (step.type) {
        case _TransformType.reverse:
          chars = chars.reversed.toList();
          break;

        case _TransformType.splice:
          if (step.param < chars.length) {
            chars = chars.sublist(step.param);
          }
          break;

        case _TransformType.swap:
          if (step.param < chars.length) {
            final temp = chars[0];
            final swapIndex = step.param % chars.length;
            chars[0] = chars[swapIndex];
            chars[swapIndex] = temp;
          }
          break;
      }
    }

    return chars.join('');
  }

  /// Clear cached data
  void clearCache() {
    _cachedSteps = null;
    _cachedPlayerJsUrl = null;
  }

  void dispose() {
    _client.close();
  }
}

/// Types of signature transformations
enum _TransformType { reverse, splice, swap }

/// A single transformation step
class _TransformStep {
  final _TransformType type;
  final int param;

  const _TransformStep(this.type, this.param);

  @override
  String toString() => '${type.name}($param)';
}
