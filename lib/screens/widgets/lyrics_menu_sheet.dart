import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import '../../services/lyrics/lyrics_service.dart';
import '../../services/lyrics/lyrics_translation_service.dart';
import '../../providers/music_providers.dart';
import 'lyrics_provider_sheet.dart';

// Provides preferences
final aiLyricsTranslationEnabledProvider = StateProvider<bool>((ref) => false);
final aiTranslationProviderKeyProvider = StateProvider<TranslationProvider>((ref) => TranslationProvider.openRouter);
final aiTranslationModeProvider = StateProvider<String>((ref) => 'Literal');
final aiTranslationLanguageProvider = StateProvider<String>((ref) => 'en');
final aiTranslationOpenRouterKeyProvider = StateProvider<String>((ref) => '');
final aiTranslationDeepLKeyProvider = StateProvider<String>((ref) => '');
final aiTranslationModelProvider = StateProvider<String>((ref) => '');



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
          color: Theme.of(context).scaffoldBackgroundColor,
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
