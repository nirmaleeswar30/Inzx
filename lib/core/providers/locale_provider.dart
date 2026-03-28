import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const supportedAppLocales = <Locale>[
  Locale('en'),
  Locale('tr'),
  Locale('ru'),
  Locale('hi'),
  Locale('ta'),
  Locale('kn'),
  Locale('te'),
  Locale('es'),
  Locale('fr'),
  Locale('de'),
  Locale('id'),
  Locale('ja'),
  Locale('ko'),
  Locale('ar'),
  Locale('uk'),
  Locale('th'),
  Locale.fromSubtags(languageCode: 'pt', countryCode: 'BR'),
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
];

enum AppLanguageOption {
  system,
  english,
  turkish,
  russian,
  hindi,
  tamil,
  kannada,
  telugu,
  spanish,
  french,
  german,
  indonesian,
  japanese,
  korean,
  arabic,
  ukrainian,
  thai,
  portugueseBrazil,
  chineseSimplified,
  chineseTraditional,
}

enum AppContentLocationOption { system, unitedStates, india, turkey, russia }

String appLocaleStorageKey(Locale locale) {
  final parts = <String>[locale.languageCode];
  if ((locale.scriptCode ?? '').isNotEmpty) parts.add(locale.scriptCode!);
  if ((locale.countryCode ?? '').isNotEmpty) parts.add(locale.countryCode!);
  return parts.join('-');
}

bool _isSameLocale(Locale a, Locale b) =>
    a.languageCode == b.languageCode &&
    (a.scriptCode ?? '') == (b.scriptCode ?? '') &&
    (a.countryCode ?? '') == (b.countryCode ?? '');

Locale? supportedAppLocaleFromCode(String? code) {
  final normalized = code?.trim().replaceAll('_', '-');
  if (normalized == null || normalized.isEmpty) return null;

  for (final locale in supportedAppLocales) {
    if (appLocaleStorageKey(locale).toLowerCase() == normalized.toLowerCase()) {
      return locale;
    }
  }

  final lower = normalized.toLowerCase();
  if (lower.startsWith('zh')) {
    if (lower.contains('hant') ||
        lower.endsWith('-tw') ||
        lower.endsWith('-hk') ||
        lower.endsWith('-mo')) {
      return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
    }
    return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
  }

  if (lower.startsWith('pt')) {
    return const Locale.fromSubtags(languageCode: 'pt', countryCode: 'BR');
  }

  for (final locale in supportedAppLocales) {
    if (locale.languageCode == normalized) return locale;
  }

  return null;
}

Locale? supportedAppLocaleFromLocale(Locale? locale) {
  if (locale == null) return null;

  for (final candidate in supportedAppLocales) {
    if (_isSameLocale(candidate, locale)) return candidate;
  }

  if (locale.languageCode == 'zh') {
    final script = locale.scriptCode?.toLowerCase();
    final country = locale.countryCode?.toUpperCase();
    if (script == 'hant' ||
        country == 'TW' ||
        country == 'HK' ||
        country == 'MO') {
      return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
    }
    return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
  }

  if (locale.languageCode == 'pt') {
    return const Locale.fromSubtags(languageCode: 'pt', countryCode: 'BR');
  }

  for (final candidate in supportedAppLocales) {
    if (candidate.languageCode == locale.languageCode) return candidate;
  }

  return null;
}

Locale resolveEffectiveAppLocale({String? storedCode, Locale? systemLocale}) {
  return supportedAppLocaleFromCode(storedCode) ??
      supportedAppLocaleFromLocale(
        systemLocale ?? ui.PlatformDispatcher.instance.locale,
      ) ??
      const Locale('en');
}

String requestLanguageCodeForLocale(Locale locale) {
  if (locale.languageCode == 'pt' && locale.countryCode == 'BR') {
    return 'pt-BR';
  }
  if (locale.languageCode == 'zh' && locale.scriptCode == 'Hans') {
    return 'zh-CN';
  }
  if (locale.languageCode == 'zh' && locale.scriptCode == 'Hant') {
    return 'zh-TW';
  }
  return locale.languageCode;
}

class AppLocaleNotifier extends StateNotifier<Locale?> {
  static const String localePrefKey = 'inzx_locale_code';

  AppLocaleNotifier() : super(null) {
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = supportedAppLocaleFromCode(prefs.getString(localePrefKey));
    } catch (_) {
      state = null;
    }
  }

  Future<void> setLocale(Locale? locale) async {
    state = locale;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (locale == null) {
        await prefs.remove(localePrefKey);
      } else {
        await prefs.setString(localePrefKey, appLocaleStorageKey(locale));
      }
    } catch (_) {
      // Non-fatal: language still updates in memory.
    }
  }
}

final appLocaleProvider = StateNotifierProvider<AppLocaleNotifier, Locale?>((
  ref,
) {
  return AppLocaleNotifier();
});

class AppContentLocationNotifier extends StateNotifier<String?> {
  static const String contentLocationPrefKey = 'inzx_content_country_code';

  AppContentLocationNotifier() : super(null) {
    _loadCountryCode();
  }

  Future<void> _loadCountryCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = normalizeContentCountryCode(
        prefs.getString(contentLocationPrefKey),
      );
    } catch (_) {
      state = null;
    }
  }

  Future<void> setCountryCode(String? countryCode) async {
    final normalizedCode = normalizeContentCountryCode(countryCode);
    state = normalizedCode;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (normalizedCode == null) {
        await prefs.remove(contentLocationPrefKey);
      } else {
        await prefs.setString(contentLocationPrefKey, normalizedCode);
      }
    } catch (_) {
      // Non-fatal: location still updates in memory.
    }
  }
}

final appContentCountryProvider =
    StateNotifierProvider<AppContentLocationNotifier, String?>((ref) {
      return AppContentLocationNotifier();
    });

AppLanguageOption appLanguageOptionFromLocale(Locale? locale) {
  final normalized = locale == null
      ? null
      : supportedAppLocaleFromLocale(locale);
  switch (appLocaleStorageKey(normalized ?? const Locale('en'))) {
    case 'en':
      return locale == null
          ? AppLanguageOption.system
          : AppLanguageOption.english;
    case 'tr':
      return AppLanguageOption.turkish;
    case 'ru':
      return AppLanguageOption.russian;
    case 'hi':
      return AppLanguageOption.hindi;
    case 'ta':
      return AppLanguageOption.tamil;
    case 'kn':
      return AppLanguageOption.kannada;
    case 'te':
      return AppLanguageOption.telugu;
    case 'es':
      return AppLanguageOption.spanish;
    case 'fr':
      return AppLanguageOption.french;
    case 'de':
      return AppLanguageOption.german;
    case 'id':
      return AppLanguageOption.indonesian;
    case 'ja':
      return AppLanguageOption.japanese;
    case 'ko':
      return AppLanguageOption.korean;
    case 'ar':
      return AppLanguageOption.arabic;
    case 'uk':
      return AppLanguageOption.ukrainian;
    case 'th':
      return AppLanguageOption.thai;
    case 'pt-BR':
      return AppLanguageOption.portugueseBrazil;
    case 'zh-Hans':
      return AppLanguageOption.chineseSimplified;
    case 'zh-Hant':
      return AppLanguageOption.chineseTraditional;
    default:
      return AppLanguageOption.system;
  }
}

Locale? localeForAppLanguageOption(AppLanguageOption option) {
  switch (option) {
    case AppLanguageOption.system:
      return null;
    case AppLanguageOption.english:
      return const Locale('en');
    case AppLanguageOption.turkish:
      return const Locale('tr');
    case AppLanguageOption.russian:
      return const Locale('ru');
    case AppLanguageOption.hindi:
      return const Locale('hi');
    case AppLanguageOption.tamil:
      return const Locale('ta');
    case AppLanguageOption.kannada:
      return const Locale('kn');
    case AppLanguageOption.telugu:
      return const Locale('te');
    case AppLanguageOption.spanish:
      return const Locale('es');
    case AppLanguageOption.french:
      return const Locale('fr');
    case AppLanguageOption.german:
      return const Locale('de');
    case AppLanguageOption.indonesian:
      return const Locale('id');
    case AppLanguageOption.japanese:
      return const Locale('ja');
    case AppLanguageOption.korean:
      return const Locale('ko');
    case AppLanguageOption.arabic:
      return const Locale('ar');
    case AppLanguageOption.ukrainian:
      return const Locale('uk');
    case AppLanguageOption.thai:
      return const Locale('th');
    case AppLanguageOption.portugueseBrazil:
      return const Locale.fromSubtags(languageCode: 'pt', countryCode: 'BR');
    case AppLanguageOption.chineseSimplified:
      return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
    case AppLanguageOption.chineseTraditional:
      return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
  }
}

String? normalizeContentCountryCode(String? code) {
  final trimmed = code?.trim().toUpperCase();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

String resolveSystemContentCountryCode([Locale? locale]) {
  final countryCode =
      locale?.countryCode ?? ui.PlatformDispatcher.instance.locale.countryCode;
  return normalizeContentCountryCode(countryCode) ?? 'US';
}

String resolveAppContentCountryCode({
  String? storedCountryCode,
  Locale? systemLocale,
}) {
  return normalizeContentCountryCode(storedCountryCode) ??
      resolveSystemContentCountryCode(systemLocale);
}

AppContentLocationOption appContentLocationOptionFromCountryCode(
  String? countryCode,
) {
  switch (normalizeContentCountryCode(countryCode)) {
    case 'US':
      return AppContentLocationOption.unitedStates;
    case 'IN':
      return AppContentLocationOption.india;
    case 'TR':
      return AppContentLocationOption.turkey;
    case 'RU':
      return AppContentLocationOption.russia;
    default:
      return AppContentLocationOption.system;
  }
}

String? countryCodeForContentLocationOption(AppContentLocationOption option) {
  switch (option) {
    case AppContentLocationOption.system:
      return null;
    case AppContentLocationOption.unitedStates:
      return 'US';
    case AppContentLocationOption.india:
      return 'IN';
    case AppContentLocationOption.turkey:
      return 'TR';
    case AppContentLocationOption.russia:
      return 'RU';
  }
}
