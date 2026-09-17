import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'lyrics_models.dart';

enum TranslationProvider {
  openRouter,
  openAI,
  perplexity,
  claude,
  gemini,
  xAi,
  mistral,
  inception,
  deepL,
  custom,
}

extension TranslationProviderExt on TranslationProvider {
  String get displayName {
    switch (this) {
      case TranslationProvider.openRouter: return 'OpenRouter';
      case TranslationProvider.openAI: return 'OpenAI';
      case TranslationProvider.perplexity: return 'Perplexity';
      case TranslationProvider.claude: return 'Claude';
      case TranslationProvider.gemini: return 'Gemini';
      case TranslationProvider.xAi: return 'XAi';
      case TranslationProvider.mistral: return 'Mistral';
      case TranslationProvider.inception: return 'Inception';
      case TranslationProvider.deepL: return 'DeepL';
      case TranslationProvider.custom: return 'Custom';
    }
  }

  String get defaultBaseUrl {
    switch (this) {
      case TranslationProvider.openRouter: return 'https://openrouter.ai/api/v1/chat/completions';
      case TranslationProvider.openAI: return 'https://api.openai.com/v1/chat/completions';
      case TranslationProvider.perplexity: return 'https://api.perplexity.ai/chat/completions';
      case TranslationProvider.claude: return 'https://api.anthropic.com/v1/messages';
      case TranslationProvider.gemini: return 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions';
      case TranslationProvider.xAi: return 'https://api.x.ai/v1/chat/completions';
      case TranslationProvider.mistral: return 'https://api.mistral.ai/v1/chat/completions';
      case TranslationProvider.inception: return 'https://api.inceptionlabs.ai/v1/chat/completions';
      case TranslationProvider.deepL: return 'https://api-free.deepl.com/v2/translate';
      case TranslationProvider.custom: return '';
    }
  }

  String get defaultModel {
    switch (this) {
      case TranslationProvider.openRouter: return 'inception/mercury-2.5-preview';
      case TranslationProvider.openAI: return 'gpt-5.6-sol';
      case TranslationProvider.perplexity: return 'sonar';
      case TranslationProvider.claude: return 'claude-opus-5';
      case TranslationProvider.gemini: return 'gemini-flash-lite-latest';
      case TranslationProvider.xAi: return 'grok-3-mini';
      case TranslationProvider.mistral: return 'open-mistral-nemo';
      case TranslationProvider.inception: return 'inception-base';
      case TranslationProvider.deepL: return '';
      case TranslationProvider.custom: return '';
    }
  }

  List<String> get availableModels {
    switch (this) {
      case TranslationProvider.openRouter:
        return [
          'inception/mercury-2.5-preview',
          'meta/muse-spark-1.3',
          'z-ai/glm-5.3-flash',
          'qwen/qwen3.8-flash',
          '~deepseek/deepseek-v4-flash-latest',
          '~openai/gpt-mini-latest',
          'openai/gpt-oss-120b',
          '~google/gemini-flash-latest',
        ];
      case TranslationProvider.openAI:
        return [
          'gpt-5.6-sol',
          'gpt-5.6-terra',
          'gpt-5.6-luna',
          'gpt-5.5-2026-04-23',
          'gpt-5.4-2026-03-05',
        ];
      case TranslationProvider.claude:
        return [
          'claude-opus-5',
          'claude-sonnet-5',
          'claude-haiku-4-5-20251001',
          'claude-fable-5-1',
        ];
      case TranslationProvider.gemini:
        return [
          'gemini-flash-lite-latest',
          'gemini-pro-latest',
          'gemini-flash-latest',
          'gemini-3.8-flash',
        ];
      case TranslationProvider.perplexity:
        return [
          'sonar',
          'sonar-pro',
          'sonar-reasoning-pro',
        ];
      case TranslationProvider.xAi:
        return ['grok-3-mini', 'grok-3'];
      case TranslationProvider.mistral:
        return ['open-mistral-nemo', 'mistral-large-latest'];
      case TranslationProvider.inception:
        return ['inception-base', 'inception-large'];
      case TranslationProvider.deepL:
        return [];
      case TranslationProvider.custom:
        return [];
    }
  }
}

class LyricsTranslationService {
  static final LyricsTranslationService instance = LyricsTranslationService._();
  LyricsTranslationService._();

  final _httpClient = http.Client();

  /// Verify if the provided API key is valid and the API is reachable
  Future<bool> verifyApiKey({
    required TranslationProvider provider,
    required String apiKey,
    String? baseUrl,
    String? model,
  }) async {
    final effectiveBaseUrl = (baseUrl != null && baseUrl.isNotEmpty) 
        ? baseUrl 
        : provider.defaultBaseUrl;

    if (effectiveBaseUrl.isEmpty || apiKey.trim().isEmpty) return false;
    
    try {
      final request = http.Request('POST', Uri.parse(effectiveBaseUrl));
      request.headers['Content-Type'] = 'application/json';

      if (provider == TranslationProvider.claude) {
        request.headers['x-api-key'] = apiKey.trim();
        request.headers['anthropic-version'] = '2023-06-01';
      } else if (provider == TranslationProvider.deepL) {
        request.headers['Authorization'] = 'DeepL-Auth-Key ${apiKey.trim()}';
      } else {
        request.headers['Authorization'] = 'Bearer ${apiKey.trim()}';
      }

      final body = (provider == TranslationProvider.deepL) 
        ? {
            'text': ['hi'],
            'target_lang': 'EN-US'
          }
        : {
            'model': (model != null && model.isNotEmpty) ? model : provider.defaultModel,
            'messages': [{'role': 'user', 'content': 'hi'}],
            'max_tokens': 1,
          };

      request.body = jsonEncode(body);
      final response = await _httpClient.send(request);

      if (response.statusCode == 401 || response.statusCode == 403) {
        return false;
      }
      return true;
    } catch (e) {
      return false; 
    }
  }

  Future<void> translateLines(
    List<LyricLine> lines, {
    required TranslationProvider provider,
    required String apiKey,
    required String targetLanguage,
    required String mode,
    String? baseUrl,
    String? model,
    String? customSystemPrompt,
    required void Function(int index, String translation) onLineTranslated,
    required VoidCallback onComplete,
    required void Function(String error) onError,
  }) async {
    if (lines.isEmpty || apiKey.trim().isEmpty) {
      onError('Lines or API key is empty');
      return;
    }

    final effectiveBaseUrl = (baseUrl != null && baseUrl.isNotEmpty) 
        ? baseUrl 
        : provider.defaultBaseUrl;

    final fullText = lines.map((l) => l.text).join('\n');
    final lineCount = lines.length;

    final defaultSystemPrompt = mode == 'Literal'
        ? 'Translate the following $lineCount lines to $targetLanguage. Output MUST be a JSON object {"lines": [...]} with EXACTLY $lineCount strings.'
        : 'Romanize/transliterate the following $lineCount lines into simple Latin script. Output MUST be a JSON object {"lines": [...]} with EXACTLY $lineCount strings.';

    final systemPrompt = (customSystemPrompt != null && customSystemPrompt.isNotEmpty)
        ? customSystemPrompt.replaceAll('{lineCount}', lineCount.toString())
        : defaultSystemPrompt;

    try {
      final request = http.Request('POST', Uri.parse(effectiveBaseUrl));
      request.headers['Content-Type'] = 'application/json';

      final String resolvedModel = (model != null && model.isNotEmpty) ? model : provider.defaultModel;
      Map<String, dynamic> body;

      if (provider == TranslationProvider.claude) {
        request.headers['x-api-key'] = apiKey.trim();
        request.headers['anthropic-version'] = '2023-06-01';
        
        body = {
          'model': resolvedModel,
          'system': systemPrompt,
          'messages': [
            {'role': 'user', 'content': fullText},
            {'role': 'assistant', 'content': '{"lines": ['}
          ],
          'max_tokens': 2000,
          'temperature': 0.3,
          'stream': true,
        };
      } else if (provider == TranslationProvider.deepL) {
        request.headers['Authorization'] = 'DeepL-Auth-Key ${apiKey.trim()}';
        
        String deepLTargetLang = targetLanguage.toUpperCase();
        if (deepLTargetLang == 'EN') deepLTargetLang = 'EN-US';
        if (deepLTargetLang == 'PT') deepLTargetLang = 'PT-BR';
        
        body = {
          'text': lines.map((l) => l.text).toList(),
          'target_lang': deepLTargetLang,
        };
      } else {
        request.headers['Authorization'] = 'Bearer ${apiKey.trim()}';
        
        body = {
          'model': resolvedModel,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': fullText},
          ],
          'temperature': 0.3,
          'stream': true,
          'response_format': {
            'type': 'json_schema',
            'json_schema': {
              'name': 'translated_lyrics',
              'strict': true,
              'schema': {
                'type': 'object',
                'properties': {
                  'lines': {
                    'type': 'array',
                    'items': {'type': 'string'},
                    'description': 'Translated lines, one per input line',
                  },
                },
                'required': ['lines'],
                'additionalProperties': false,
              },
            },
          },
        };
      }

      debugPrint('🎵 LyricsTranslationService: Sending request to $effectiveBaseUrl');
      
      request.body = jsonEncode(body);

      final response = await _httpClient.send(request);
      if (response.statusCode >= 400) {
        final err = await response.stream.bytesToString();
        debugPrint('🎵 LyricsTranslationService Error: ${response.statusCode} $err');
        onError('API Error: ${response.statusCode} $err');
        return;
      }

      debugPrint('🎵 LyricsTranslationService: Stream connected (Status 200)');
      
      if (provider == TranslationProvider.deepL) {
        final resStr = await response.stream.bytesToString();
        try {
          final json = jsonDecode(resStr);
          final translations = json['translations'] as List?;
          if (translations != null) {
            for (int i = 0; i < translations.length && i < lines.length; i++) {
              final text = translations[i]['text'] as String?;
              if (text != null) {
                onLineTranslated(i, text);
              }
            }
          }
          onComplete();
        } catch (e) {
          onError('DeepL Parse Error: $e');
        }
        return;
      }

      final buffer = StringBuffer();
      
      if (provider == TranslationProvider.claude) {
        buffer.write('{"lines": [');
      }
      
      response.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(
        (line) {
          if (line.startsWith('event: ')) return;
          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            if (data == '[DONE]') {
              debugPrint('🎵 LyricsTranslationService: Stream [DONE] received');
              return;
            }
            try {
              final json = jsonDecode(data);
              String? delta;
              
              if (provider == TranslationProvider.claude) {
                if (json['type'] == 'content_block_delta') {
                  delta = json['delta']?['text'] as String?;
                }
              } else {
                delta = json['choices']?[0]?['delta']?['content'] as String?;
              }
              
              if (delta != null) {
                buffer.write(delta);
                final parsed = _tryParsePartialLines(buffer.toString());
                if (parsed != null) {
                  for (int i = 0; i < parsed.length && i < lines.length; i++) {
                    onLineTranslated(i, parsed[i]);
                  }
                }
              }
            } catch (e) {
              // Ignore partial json parse errors
            }
          }
        },
        onDone: () {
          debugPrint('🎵 LyricsTranslationService: Stream completely done');
          final parsed = _tryParsePartialLines(buffer.toString());
          if (parsed != null) {
            for (int i = 0; i < parsed.length && i < lines.length; i++) {
              onLineTranslated(i, parsed[i]);
            }
          }
          onComplete();
        },
        onError: (e) {
          debugPrint('🎵 LyricsTranslationService Stream Error: $e');
          onError(e.toString());
        },
      );
    } catch (e) {
      debugPrint('🎵 LyricsTranslationService Exception: $e');
      onError(e.toString());
    }
  }

  List<String>? _tryParsePartialLines(String content) {
    try {
      final match = RegExp(r'"lines"\s*:\s*\[(.*)', dotAll: true).firstMatch(content);
      if (match != null) {
        final arrayContent = '[${match.group(1)}';
        var validArrayStr = arrayContent;
        if (!validArrayStr.endsWith(']')) {
          final lastQuote = validArrayStr.lastIndexOf('"');
          if (lastQuote > 0) {
             validArrayStr = '${validArrayStr.substring(0, lastQuote + 1)}]';
          } else {
             validArrayStr = '$validArrayStr]';
          }
        }
        final List<dynamic> parsed = jsonDecode(validArrayStr);
        return parsed.map((e) => e.toString()).toList();
      }
    } catch (e) {
       // Ignore partial parse errors silently
    }
    return null;
  }
}
