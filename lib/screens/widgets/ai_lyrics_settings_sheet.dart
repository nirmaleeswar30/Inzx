import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import '../../services/lyrics/lyrics_translation_service.dart';
import 'lyrics_menu_sheet.dart'; // to get the providers

class AiLyricsSettingsSheet extends ConsumerStatefulWidget {
  const AiLyricsSettingsSheet({super.key});

  @override
  ConsumerState<AiLyricsSettingsSheet> createState() => _AiLyricsSettingsSheetState();
}

class _AiLyricsSettingsSheetState extends ConsumerState<AiLyricsSettingsSheet> {
  final _openRouterKeyController = TextEditingController();
  final _deepLKeyController = TextEditingController();
  final _customModelController = TextEditingController();
  bool _showCustomModelInput = false;
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

  @override
  void initState() {
    super.initState();
    _openRouterKeyController.text = ref.read(aiTranslationOpenRouterKeyProvider);
    _deepLKeyController.text = ref.read(aiTranslationDeepLKeyProvider);
    _customModelController.text = ref.read(aiTranslationModelProvider);
    
    final provider = ref.read(aiTranslationProviderKeyProvider);
    final currentModel = ref.read(aiTranslationModelProvider);
    if (currentModel.isNotEmpty && !provider.availableModels.contains(currentModel)) {
      _showCustomModelInput = true;
    }
  }

  @override
  void dispose() {
    _openRouterKeyController.dispose();
    _deepLKeyController.dispose();
    _customModelController.dispose();
    super.dispose();
  }

  Future<void> _triggerTranslation() async {
    final enabled = ref.read(aiLyricsTranslationEnabledProvider);
    if (!enabled) return;

    final provider = ref.read(aiTranslationProviderKeyProvider);
    final isDeepL = provider == TranslationProvider.deepL;
    final key = isDeepL ? _deepLKeyController.text : _openRouterKeyController.text;

    if (key.trim().isEmpty) {
      _showToast('Please enter an API Key to use AI Lyrics Translation.', Colors.red.shade800);
      ref.read(aiLyricsTranslationEnabledProvider.notifier).state = false;
      return;
    }

    final model = ref.read(aiTranslationModelProvider);

    // Check if reachable
    final isReachable = await LyricsTranslationService.instance.verifyApiKey(
      provider: provider,
      apiKey: key,
      model: model,
    );

    if (!mounted) return;

    if (!isReachable) {
      _showToast('Could not connect to ${provider.displayName} API. Check key or network.', Colors.red.shade800);
      ref.read(aiLyricsTranslationEnabledProvider.notifier).state = false;
      return;
    }

    _showToast('Connected to ${provider.displayName} API successfully!', Colors.green.shade800);
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(aiTranslationProviderKeyProvider);
    final mode = ref.watch(aiTranslationModeProvider);
    final enabled = ref.watch(aiLyricsTranslationEnabledProvider);

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
                        Text('AI Translation Settings', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 24),
                        SwitchListTile(
                          title: const Text('AI Lyrics Translation'),
                          subtitle: const Text('Translate or transliterate lyrics in real-time'),
                          secondary: const Icon(Iconsax.translate),
                          value: enabled,
                          onChanged: (val) {
                            ref.read(aiLyricsTranslationEnabledProvider.notifier).state = val;
                            if (val) {
                              _triggerTranslation();
                            }
                          },
                        ),
                        const Divider(),
                        ListTile(
                          title: const Text('Provider'),
                          trailing: DropdownButton<TranslationProvider>(
                            value: provider,
                            items: TranslationProvider.values.map((p) {
                              return DropdownMenuItem(value: p, child: Text(p.displayName));
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                ref.read(aiTranslationProviderKeyProvider.notifier).state = val;
                                ref.read(aiTranslationModelProvider.notifier).state = val.defaultModel;
                              }
                            },
                          ),
                        ),
                        if (provider == TranslationProvider.deepL)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: TextField(
                              controller: _deepLKeyController,
                              decoration: const InputDecoration(labelText: 'DeepL API Key', border: OutlineInputBorder()),
                              obscureText: true,
                              onChanged: (val) => ref.read(aiTranslationDeepLKeyProvider.notifier).state = val,
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: TextField(
                              controller: _openRouterKeyController,
                              decoration: InputDecoration(
                                labelText: '${provider.displayName} API Key',
                                border: const OutlineInputBorder(),
                              ),
                              obscureText: true,
                              onChanged: (val) => ref.read(aiTranslationOpenRouterKeyProvider.notifier).state = val,
                            ),
                          ),
                        if (provider.availableModels.isNotEmpty) ...[
                          ListTile(
                            title: const Text('Model'),
                            trailing: DropdownButton<String>(
                              value: _showCustomModelInput 
                                  ? 'custom_input' 
                                  : (provider.availableModels.contains(ref.watch(aiTranslationModelProvider)) 
                                      ? ref.watch(aiTranslationModelProvider) 
                                      : provider.defaultModel),
                              items: [
                                ...provider.availableModels.map((m) {
                                  String displayName = m;
                                  if (displayName.contains('/')) {
                                    displayName = displayName.split('/').last;
                                  }
                                  if (displayName.startsWith('models/')) {
                                    displayName = displayName.replaceFirst('models/', '');
                                  }
                                  return DropdownMenuItem(
                                    value: m,
                                    child: Text(
                                      displayName.length > 30 ? '${displayName.substring(0, 30)}...' : displayName,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }),
                                const DropdownMenuItem(value: 'custom_input', child: Text('Custom Input...')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  if (val == 'custom_input') {
                                    setState(() => _showCustomModelInput = true);
                                  } else {
                                    setState(() => _showCustomModelInput = false);
                                    ref.read(aiTranslationModelProvider.notifier).state = val;
                                    _customModelController.text = val;
                                  }
                                }
                              },
                            ),
                          ),
                          if (_showCustomModelInput)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: TextField(
                                controller: _customModelController,
                                decoration: InputDecoration(
                                  labelText: 'Custom Model ID',
                                  hintText: provider.defaultModel,
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: (val) => ref.read(aiTranslationModelProvider.notifier).state = val,
                              ),
                            ),
                        ],
                        ListTile(
                          title: const Text('Mode'),
                          trailing: DropdownButton<String>(
                            value: mode,
                            items: const [
                              DropdownMenuItem(value: 'Literal', child: Text('Literal Translation')),
                              DropdownMenuItem(value: 'Transcribed', child: Text('Romanized / Transcribed')),
                            ],
                            onChanged: (val) {
                              if (val != null) ref.read(aiTranslationModeProvider.notifier).state = val;
                            },
                          ),
                        ),
                        if (mode == 'Literal')
                          ListTile(
                            title: const Text('Target Language'),
                            trailing: DropdownButton<String>(
                              value: ref.watch(aiTranslationLanguageProvider),
                              items: const [
                                DropdownMenuItem(value: 'en', child: Text('English')),
                                DropdownMenuItem(value: 'es', child: Text('Spanish')),
                                DropdownMenuItem(value: 'fr', child: Text('French')),
                                DropdownMenuItem(value: 'ja', child: Text('Japanese')),
                                DropdownMenuItem(value: 'ko', child: Text('Korean')),
                                DropdownMenuItem(value: 'hi', child: Text('Hindi')),
                                DropdownMenuItem(value: 'pt', child: Text('Portuguese')),
                              ],
                              onChanged: (val) {
                                if (val != null) ref.read(aiTranslationLanguageProvider.notifier).state = val;
                              },
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
