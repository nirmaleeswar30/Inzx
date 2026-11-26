import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/providers/theme_provider.dart'
    show ProgressBarStyle, getProgressBarStyleName, progressBarStyleProvider;
import '../../core/utils/platform_utils.dart';
import '../../services/lyrics/lyrics_service.dart';
import '../../services/lyrics/lyrics_translation_service.dart';
import '../../providers/music_providers.dart';
import 'lyrics_provider_sheet.dart';

// AI translation preferences. These are persisted to SharedPreferences so the
// user's API keys and settings survive app restarts. Update them via the
// notifier's `set(...)` method (e.g. `ref.read(provider.notifier).set(value)`).

/// Persists a [String] preference (e.g. an API key) under [_key].
class _PersistedStringNotifier extends Notifier<String> {
  _PersistedStringNotifier(this._key, this._initial);

  final String _key;
  final String _initial;

  @override
  String build() {
    _load();
    return _initial;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_key);
      if (value != null) state = value;
    } catch (_) {}
  }

  Future<void> set(String value) async {
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, value);
    } catch (_) {}
  }
}

/// Persists a [bool] preference under [_key].
class _PersistedBoolNotifier extends Notifier<bool> {
  _PersistedBoolNotifier(this._key, this._initial);

  final String _key;
  final bool _initial;

  @override
  bool build() {
    _load();
    return _initial;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getBool(_key);
      if (value != null) state = value;
    } catch (_) {}
  }

  Future<void> set(bool value) async {
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (_) {}
  }
}

/// Persists the selected [TranslationProvider] (by enum index) under [_key].
class _PersistedTranslationProviderNotifier
    extends Notifier<TranslationProvider> {
  static const String _key = 'inzx_ai_translation_provider';

  @override
  TranslationProvider build() {
    _load();
    return TranslationProvider.openRouter;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getInt(_key);
      if (index != null &&
          index >= 0 &&
          index < TranslationProvider.values.length) {
        state = TranslationProvider.values[index];
      }
    } catch (_) {}
  }

  Future<void> set(TranslationProvider value) async {
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, value.index);
    } catch (_) {}
  }
}

// Provides preferences
final aiLyricsTranslationEnabledProvider =
    NotifierProvider<_PersistedBoolNotifier, bool>(
    () => _PersistedBoolNotifier('inzx_ai_translation_enabled', false));
final aiTranslationProviderKeyProvider = NotifierProvider<_PersistedTranslationProviderNotifier, TranslationProvider>(
    () => _PersistedTranslationProviderNotifier());
final aiTranslationModeProvider =
    NotifierProvider<_PersistedStringNotifier, String>(
    () => _PersistedStringNotifier('inzx_ai_translation_mode', 'Literal'));
final aiTranslationLanguageProvider =
    NotifierProvider<_PersistedStringNotifier, String>(
    () => _PersistedStringNotifier('inzx_ai_translation_language', 'en'));
final aiTranslationOpenRouterKeyProvider =
    NotifierProvider<_PersistedStringNotifier, String>(
    () => _PersistedStringNotifier('inzx_ai_translation_openrouter_key', ''));
final aiTranslationDeepLKeyProvider =
    NotifierProvider<_PersistedStringNotifier, String>(
    () => _PersistedStringNotifier('inzx_ai_translation_deepl_key', ''));
final aiTranslationModelProvider =
    NotifierProvider<_PersistedStringNotifier, String>(
    () => _PersistedStringNotifier('inzx_ai_translation_model', ''));



class LyricsMenuSheet extends ConsumerStatefulWidget {
  const LyricsMenuSheet({super.key});

  @override
  ConsumerState<LyricsMenuSheet> createState() => _LyricsMenuSheetState();
}

class _LyricsMenuSheetState extends ConsumerState<LyricsMenuSheet> {
  String? _toastMessage;
  Color? _toastColor;

  void _showToast(String message, Color color) {
    if (!mounted) return;
    setState(() {
      _toastMessage = message;
      _toastColor = color;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _toastMessage == message) {
        setState(() => _toastMessage = null);
      }
    });
  }

  // initState removed

  @override
  void dispose() {
    super.dispose();
  }

  bool _isTranslating = false;

  Future<void> _triggerTranslation() async {
    final provider = ref.read(aiTranslationProviderKeyProvider);
    final isDeepL = provider == TranslationProvider.deepL;
    final key = isDeepL 
        ? ref.read(aiTranslationDeepLKeyProvider) 
        : ref.read(aiTranslationOpenRouterKeyProvider);

    if (key.trim().isEmpty) {
      _showToast('Please configure an API Key in Settings first.', Colors.red.shade800);
      return;
    }

    final model = ref.read(aiTranslationModelProvider);

    setState(() {
      _isTranslating = true;
    });
    _showToast('Connecting to API...', Colors.blue.shade800);

    // Check if reachable
    final isReachable = await LyricsTranslationService.instance.verifyApiKey(
      provider: provider,
      apiKey: key,
      model: model,
    );

    if (!mounted) return;

    if (!isReachable) {
      _showToast('Could not connect to ${provider.displayName} API. Check key or network.', Colors.red.shade800);
      setState(() {
        _isTranslating = false;
      });
      return;
    }

    _showToast('Translating lyrics...', Colors.blue.shade800);

    final mode = ref.read(aiTranslationModeProvider);
    final targetLang = ref.read(aiTranslationLanguageProvider);

    final currentLyrics = ref.read(lyricsProvider).currentLyrics;
    if (currentLyrics?.lines == null || currentLyrics!.lines!.isEmpty) {
      setState(() {
        _isTranslating = false;
      });
      return;
    }

    final lines = currentLyrics.lines!;

    LyricsTranslationService.instance.translateLines(
      lines,
      provider: provider,
      apiKey: key,
      model: model,
      targetLanguage: targetLang,
      mode: mode,
      onLineTranslated: (index, translation) {
        if (!mounted) return;
        final currentState = ref.read(lyricsProvider).currentLyrics;
        if (currentState == null || currentState.lines == null) return;
        if (index >= 0 && index < currentState.lines!.length) {
          final updatedLine = currentState.lines![index].copyWith(translatedText: translation);
          ref.read(lyricsProvider.notifier).updateLine(index, updatedLine);
        }
      },
      onComplete: () {
        if (mounted) {
          setState(() {
            _isTranslating = false;
          });
          _showToast('Translation applied successfully!', Colors.green.shade800);
        }
      },
      onError: (err) {
        if (mounted) {
          setState(() {
            _isTranslating = false;
          });
          _showToast('Translation Error: $err', Colors.red.shade800);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final globalEnabled = ref.watch(aiLyricsTranslationEnabledProvider);
    final currentLyrics = ref.watch(lyricsProvider).currentLyrics;
    final hasTranslations = currentLyrics?.lines?.any((l) => l.translatedText != null && l.translatedText!.isNotEmpty) ?? false;

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Material(
          color: modalSheetBackground(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Stack(
            children: [
              Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    height: 4,
                    width: 40,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text('Lyrics Options', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 24),
                        if (globalEnabled)
                          ListTile(
                            title: const Text('Translate Song Lyrics'),
                            subtitle: const Text('Apply AI translation for this track'),
                            leading: const Icon(Iconsax.translate),
                            trailing: _isTranslating
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Switch(
                                    value: hasTranslations,
                                    onChanged: (val) {
                                      if (val) {
                                        _triggerTranslation();
                                      } else {
                                        ref.read(lyricsProvider.notifier).refetchLyrics();
                                      }
                                    },
                                  ),
                          ),
                        if (ref.watch(showNerdStatsProvider))
                          ListTile(
                            title: const Text('Lyrics Providers'),
                            subtitle: const Text('Change the source of the lyrics'),
                            leading: const Icon(Iconsax.music_library_2),
                            trailing: const Icon(Iconsax.arrow_right_3, size: 16),
                            onTap: () {
                              Navigator.pop(context);
                              LyricsProviderSheet.show(context, ref);
                            },
                          ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Iconsax.refresh),
                      title: const Text('Refetch Lyrics'),
                      subtitle: const Text('Force reload lyrics for this track'),
                      onTap: () {
                        ref.read(lyricsProvider.notifier).refetchLyrics();
                        _showToast('Refetching lyrics...', Colors.green.shade800);
                        Future.delayed(const Duration(milliseconds: 1500), () {
                          if (context.mounted) Navigator.pop(context);
                        });
                      },
                    ),
                    ListTile(
                      leading: const Icon(Iconsax.copy),
                      title: const Text('Copy Lyrics'),
                      subtitle: const Text('Copy plain text to clipboard'),
                      onTap: () {
                        final lyricsText = ref.read(lyricsProvider).currentLyrics?.lyrics ?? '';
                        if (lyricsText.isNotEmpty) {
                          Clipboard.setData(ClipboardData(text: lyricsText));
                          _showToast('Copied to clipboard', Colors.green.shade800);
                        } else {
                          _showToast('No plain lyrics available', Colors.red.shade800);
                        }
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Iconsax.timer_1),
                      title: const Text('Sync Offset'),
                      subtitle: Text('${ref.watch(lyricsSyncOffsetProvider)} ms'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove),
                            onPressed: () {
                              ref.read(lyricsSyncOffsetProvider.notifier).update((s) => s - 250);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: () {
                              ref.read(lyricsSyncOffsetProvider.notifier).update((s) => s + 250);
                            },
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    // The same setting as Player appearance > Progress bar
                    // style: it changes the seek bar everywhere it's drawn.
                    const ListTile(
                      leading: Icon(Icons.graphic_eq_rounded),
                      title: Text('Progress Bar Style'),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final style in ProgressBarStyle.values)
                            ChoiceChip(
                              label: Text(getProgressBarStyleName(style)),
                              selected:
                                  ref.watch(progressBarStyleProvider) == style,
                              onSelected: (_) => ref
                                  .read(progressBarStyleProvider.notifier)
                                  .setStyle(style),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_toastMessage != null)
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: AnimatedOpacity(
                opacity: 1.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _toastColor ?? Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    _toastMessage!,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  },
);
  }
}
