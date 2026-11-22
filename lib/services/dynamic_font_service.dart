import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Descriptor for a dynamic font script.
class FontScriptDef {
  const FontScriptDef({
    required this.family,
    required this.pattern,
    required this.url,
    required this.fileName,
  });

  /// The standard font family name registered in Flutter and font fallback.
  final String family;

  /// Regex pattern matching characters belonging to this script.
  final RegExp pattern;

  /// High-availability CDN URL for the font binary.
  final String url;

  /// Local filename stored in cache directory.
  final String fileName;
}

/// Service that dynamically downloads, caches, and registers language fonts at
/// runtime via Flutter's [FontLoader] for any script missing on the host OS.
///
/// Fully compatible with Shorebird OTA patches since it requires only pure Dart.
class DynamicFontService extends ChangeNotifier {
  DynamicFontService._();
  static final DynamicFontService instance = DynamicFontService._();

  final Set<String> _loadedFamilies = <String>{};
  final Set<String> _pendingDownloads = <String>{};
  Directory? _fontsDirectory;

  /// Global list of major non-Latin world writing systems and their Noto fonts.
  static final List<FontScriptDef> allScripts = [
    // ─── South Asian (Indic) ──────────────────────────────────────────
    FontScriptDef(
      family: 'Noto Sans Tamil',
      pattern: RegExp(r'[\u0B80-\u0BFF]'),
      url: 'https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@master/hinted/ttf/NotoSansTamil/NotoSansTamil-Regular.ttf',
      fileName: 'NotoSansTamil-Regular.ttf',
    ),
    FontScriptDef(
      family: 'Noto Sans Devanagari',
      pattern: RegExp(r'[\u0900-\u097F]'),
      url: 'https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@master/hinted/ttf/NotoSansDevanagari/NotoSansDevanagari-Regular.ttf',
      fileName: 'NotoSansDevanagari-Regular.ttf',
    ),
    FontScriptDef(
      family: 'Noto Sans Telugu',
      pattern: RegExp(r'[\u0C00-\u0C7F]'),
      url: 'https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@master/hinted/ttf/NotoSansTelugu/NotoSansTelugu-Regular.ttf',
      fileName: 'NotoSansTelugu-Regular.ttf',
    ),
    FontScriptDef(
      family: 'Noto Sans Malayalam',
      pattern: RegExp(r'[\u0D00-\u0D7F]'),
      url: 'https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@master/hinted/ttf/NotoSansMalayalam/NotoSansMalayalam-Regular.ttf',
      fileName: 'NotoSansMalayalam-Regular.ttf',
    ),
    FontScriptDef(
      family: 'Noto Sans Kannada',
      pattern: RegExp(r'[\u0C80-\u0CFF]'),
      url: 'https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@master/hinted/ttf/NotoSansKannada/NotoSansKannada-Regular.ttf',
      fileName: 'NotoSansKannada-Regular.ttf',
    ),
    FontScriptDef(
      family: 'Noto Sans Bengali',
      pattern: RegExp(r'[\u0980-\u09FF]'),
      url: 'https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@master/hinted/ttf/NotoSansBengali/NotoSansBengali-Regular.ttf',
      fileName: 'NotoSansBengali-Regular.ttf',
    ),
    FontScriptDef(
      family: 'Noto Sans Gujarati',
      pattern: RegExp(r'[\u0A80-\u0AFF]'),
      url: 'https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@master/hinted/ttf/NotoSansGujarati/NotoSansGujarati-Regular.ttf',
      fileName: 'NotoSansGujarati-Regular.ttf',
    ),
    FontScriptDef(
      family: 'Noto Sans Gurmukhi',
      pattern: RegExp(r'[\u0A00-\u0A7F]'),
      url: 'https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@master/hinted/ttf/NotoSansGurmukhi/NotoSansGurmukhi-Regular.ttf',
      fileName: 'NotoSansGurmukhi-Regular.ttf',
    ),
    FontScriptDef(
      family: 'Noto Sans Oriya',
      pattern: RegExp(r'[\u0B00-\u0B7F]'),
      url: 'https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@master/hinted/ttf/NotoSansOriya/NotoSansOriya-Regular.ttf',
      fileName: 'NotoSansOriya-Regular.ttf',
    ),
    FontScriptDef(
      family: 'Noto Sans Sinhala',
      pattern: RegExp(r'[\u0D80-\u0DFF]'),
      url: 'https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@master/hinted/ttf/NotoSansSinhala/NotoSansSinhala-Regular.ttf',
      fileName: 'NotoSansSinhala-Regular.ttf',
    ),

    // ─── Southeast Asian ──────────────────────────────────────────────
    FontScriptDef(
      family: 'Noto Sans Thai',
      pattern: RegExp(r'[\u0E00-\u0E7F]'),
      url: 'https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@master/hinted/ttf/NotoSansThai/NotoSansThai-Regular.ttf',
      fileName: 'NotoSansThai-Regular.ttf',
    ),
    FontScriptDef(
      family: 'Noto Sans Myanmar',
      pattern: RegExp(r'[\u1000-\u109F]'),
      url: 'https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@master/hinted/ttf/NotoSansMyanmar/NotoSansMyanmar-Regular.ttf',
      fileName: 'NotoSansMyanmar-Regular.ttf',
    ),
    FontScriptDef(
      family: 'Noto Sans Khmer',
      pattern: RegExp(r'[\u1780-\u17FF]'),
      url: 'https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@master/hinted/ttf/NotoSansKhmer/NotoSansKhmer-Regular.ttf',
      fileName: 'NotoSansKhmer-Regular.ttf',
    ),
    FontScriptDef(
      family: 'Noto Sans Lao',
      pattern: RegExp(r'[\u0E80-\u0EFF]'),
      url: 'https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@master/hinted/ttf/NotoSansLao/NotoSansLao-Regular.ttf',
      fileName: 'NotoSansLao-Regular.ttf',
    ),

    // ─── Middle Eastern ───────────────────────────────────────────────
    FontScriptDef(
      family: 'Noto Sans Arabic',
      pattern: RegExp(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]'),
      url: 'https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@master/hinted/ttf/NotoSansArabic/NotoSansArabic-Regular.ttf',
      fileName: 'NotoSansArabic-Regular.ttf',
    ),
    FontScriptDef(
      family: 'Noto Sans Hebrew',
      pattern: RegExp(r'[\u0590-\u05FF]'),
      url: 'https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@master/hinted/ttf/NotoSansHebrew/NotoSansHebrew-Regular.ttf',
      fileName: 'NotoSansHebrew-Regular.ttf',
    ),

    // ─── Caucasian & African ──────────────────────────────────────────
    FontScriptDef(
      family: 'Noto Sans Georgian',
      pattern: RegExp(r'[\u10A0-\u10FF\u2D00-\u2D2F]'),
      url: 'https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@master/hinted/ttf/NotoSansGeorgian/NotoSansGeorgian-Regular.ttf',
      fileName: 'NotoSansGeorgian-Regular.ttf',
    ),
    FontScriptDef(
      family: 'Noto Sans Armenian',
      pattern: RegExp(r'[\u0530-\u058F]'),
      url: 'https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@master/hinted/ttf/NotoSansArmenian/NotoSansArmenian-Regular.ttf',
      fileName: 'NotoSansArmenian-Regular.ttf',
    ),
    FontScriptDef(
      family: 'Noto Sans Ethiopic',
      pattern: RegExp(r'[\u1200-\u137F]'),
      url: 'https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@master/hinted/ttf/NotoSansEthiopic/NotoSansEthiopic-Regular.ttf',
      fileName: 'NotoSansEthiopic-Regular.ttf',
    ),

    // ─── East Asian (CJK) ─────────────────────────────────────────────
    FontScriptDef(
      family: 'Noto Sans CJK SC',
      pattern: RegExp(r'[\u4E00-\u9FFF\u3400-\u4DBF]'),
      url: 'https://cdn.jsdelivr.net/gh/googlefonts/noto-cjk@main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf',
      fileName: 'NotoSansCJKsc-Regular.otf',
    ),
    FontScriptDef(
      family: 'Noto Sans CJK JP',
      pattern: RegExp(r'[\u3000-\u303F\u3040-\u30FF\u31F0-\u31FF\uFF00-\uFFEF]'),
      url: 'https://cdn.jsdelivr.net/gh/googlefonts/noto-cjk@main/Sans/OTF/Japanese/NotoSansCJKjp-Regular.otf',
      fileName: 'NotoSansCJKjp-Regular.otf',
    ),
    FontScriptDef(
      family: 'Noto Sans CJK KR',
      pattern: RegExp(r'[\uAC00-\uD7AF\u1100-\u11FF\u3130-\u318F]'),
      url: 'https://cdn.jsdelivr.net/gh/googlefonts/noto-cjk@main/Sans/OTF/Korean/NotoSansCJKkr-Regular.otf',
      fileName: 'NotoSansCJKkr-Regular.otf',
    ),
  ];

  /// Initialize the service: loads any previously downloaded fonts into the engine,
  /// and warms up common scripts on Linux desktop where missing.
  Future<void> init() async {
    try {
      final baseDir = await getApplicationSupportDirectory();
      _fontsDirectory = Directory(p.join(baseDir.path, 'fonts'));
      if (!await _fontsDirectory!.exists()) {
        await _fontsDirectory!.create(recursive: true);
      }

      // 1. Immediately load any previously cached fonts from disk
      final cachedFiles = await _fontsDirectory!.list().toList();
      var anyCachedLoaded = false;
      for (final entity in cachedFiles) {
        if (entity is! File) continue;
        final baseName = p.basename(entity.path);
        for (final script in allScripts) {
          if (script.fileName == baseName && !_loadedFamilies.contains(script.family)) {
            final bytes = await entity.readAsBytes();
            if (bytes.isNotEmpty) {
              await _registerBytes(script.family, bytes, script.fileName);
              anyCachedLoaded = true;
            }
          }
        }
      }
      if (anyCachedLoaded) {
        notifyListeners();
      }

      // 2. On Linux desktop, warm up Tamil immediately (only 72 KB)
      // to avoid any initial tofu on Linux installs lacking Indic fonts.
      if (!kIsWeb && Platform.isLinux) {
        final tamil = allScripts.firstWhere((s) => s.family == 'Noto Sans Tamil');
        if (!_loadedFamilies.contains(tamil.family)) {
          unawaited(_downloadAndLoad(tamil));
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('DynamicFontService.init error: $e');
      }
    }
  }

  /// Scans [text] for any non-Latin characters and triggers background font
  /// loading for any matching writing system not yet active.
  void ensureFontsFor(String? text) {
    if (text == null || text.isEmpty) return;

    for (final script in allScripts) {
      if (_loadedFamilies.contains(script.family) ||
          _pendingDownloads.contains(script.family)) {
        continue;
      }

      if (script.pattern.hasMatch(text)) {
        unawaited(_downloadAndLoad(script));
      }
    }
  }

  /// Scans multiple strings (e.g. title, artist, album, lyrics).
  void ensureFontsForList(Iterable<String?> texts) {
    for (final text in texts) {
      ensureFontsFor(text);
    }
  }

  Future<void> _downloadAndLoad(FontScriptDef script) async {
    if (_loadedFamilies.contains(script.family) ||
        _pendingDownloads.contains(script.family)) {
      return;
    }

    _pendingDownloads.add(script.family);

    try {
      if (_fontsDirectory == null) {
        final baseDir = await getApplicationSupportDirectory();
        _fontsDirectory = Directory(p.join(baseDir.path, 'fonts'));
        if (!await _fontsDirectory!.exists()) {
          await _fontsDirectory!.create(recursive: true);
        }
      }

      final fontFile = File(p.join(_fontsDirectory!.path, script.fileName));
      Uint8List bytes;

      if (await fontFile.exists() && await fontFile.length() > 0) {
        bytes = await fontFile.readAsBytes();
      } else {
        if (kDebugMode) {
          debugPrint('DynamicFontService: Downloading font for ${script.family}...');
        }
        final response = await http
            .get(Uri.parse(script.url))
            .timeout(const Duration(seconds: 30));

        if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
          if (kDebugMode) {
            debugPrint('DynamicFontService: Failed to download ${script.family} (status: ${response.statusCode})');
          }
          return;
        }

        bytes = response.bodyBytes;
        await fontFile.writeAsBytes(bytes);
      }

      await _registerBytes(script.family, bytes, script.fileName);
      if (kDebugMode) {
        debugPrint('DynamicFontService: Successfully loaded ${script.family}');
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('DynamicFontService: Error loading ${script.family}: $e');
      }
    } finally {
      _pendingDownloads.remove(script.family);
    }
  }

  Future<void> _registerBytes(String familyName, Uint8List bytes, [String? fileName]) async {
    try {
      final byteData = ByteData.sublistView(bytes);

      // Register with the standard name (e.g. 'Noto Sans Tamil', 'Noto Sans CJK JP')
      final loader = FontLoader(familyName);
      loader.addFont(Future.value(byteData));
      await loader.load();

      // Also register aliases (e.g. 'NotoSansTamil', 'NotoSansCJKjp', 'NotoSansCJKJP')
      final aliases = <String>{
        familyName.replaceAll(' ', ''),
        if (fileName != null && fileName.contains('-'))
          fileName.split('-').first,
      };
      for (final alias in aliases) {
        if (alias != familyName) {
          try {
            final aliasLoader = FontLoader(alias);
            aliasLoader.addFont(Future.value(byteData));
            await aliasLoader.load();
          } catch (_) {}
        }
      }

      _loadedFamilies.add(familyName);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('DynamicFontService: _registerBytes error for $familyName: $e');
      }
    }
  }
}
