import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'claude_service.dart';

class LlmProvider {
  final String id;
  final String label;
  final String defaultModel;
  final bool keyRequired;
  const LlmProvider(this.id, this.label, this.defaultModel,
      {this.keyRequired = true});
}

/// Providers available for the tutor chat. "Custom" is any
/// OpenAI-compatible endpoint: Ollama, LM Studio, OpenRouter, Groq, etc.
const List<LlmProvider> kLlmProviders = [
  LlmProvider('anthropic', 'Anthropic (Claude)', 'claude-opus-4-8'),
  LlmProvider('openai', 'OpenAI', 'gpt-4o'),
  LlmProvider('gemini', 'Google Gemini', 'gemini-2.0-flash'),
  LlmProvider('custom', 'Custom (OpenAI-compatible)', 'llama3.1',
      keyRequired: false),
];

/// A reviewed-before-apply set of deck changes proposed by the LLM.
class DeckEditPlan {
  final List<({String native, String target})> additions;

  /// Target-language text of existing cards to delete.
  final List<String> removals;
  DeckEditPlan({required this.additions, required this.removals});
}

/// Dispatches AI requests (tutor chat, translation, deck editing) to
/// whichever LLM provider is configured in Settings.
class LlmService {
  static const providerPref = 'chat_provider';
  static const customBaseUrlPref = 'custom_base_url';
  static const defaultCustomBaseUrl = 'http://localhost:11434/v1';

  static String modelPref(String providerId) => 'chat_model_$providerId';
  static String keyPref(String providerId) => '${providerId}_api_key';

  static LlmProvider providerById(String id) => kLlmProviders.firstWhere(
        (p) => p.id == id,
        orElse: () => kLlmProviders.first,
      );

  static Future<LlmProvider> activeProvider() async {
    final prefs = await SharedPreferences.getInstance();
    return providerById(prefs.getString(providerPref) ?? 'anthropic');
  }

  /// Sends a chat turn for the language-tutor conversation box.
  static Future<String> chat({
    required List<ChatMessage> history,
    required String targetLanguage,
    required String nativeLanguage,
    String? currentContext,
  }) {
    return _complete(
      system: _tutorSystemPrompt(
        targetLanguage: targetLanguage,
        nativeLanguage: nativeLanguage,
        currentContext: currentContext,
      ),
      history: history,
    );
  }

  /// Analyzes [text] (a word or phrase in [from]) for the add-card flow:
  /// returns its basic dictionary form when the input is inflected
  /// (null when it already is the dictionary form) and its [to] translation.
  static Future<({String? baseForm, String translation})> suggestCard({
    required String text,
    required String from,
    required String to,
  }) async {
    final system = '''
You help build flashcards for a language-learning app. The user sends one
word or short phrase in $from.

Respond with ONLY a JSON object — no markdown fences, no commentary — in
exactly this shape:
{"base_form": "..." or null, "translation": "..."}

- "base_form": if the input is an inflected form (a conjugated verb, a
  plural or declined noun, a comparative/superlative adjective, etc.), the
  basic dictionary form (lemma) in $from, keeping the input's
  capitalization style. If the input already is the dictionary form, or is
  a phrase where a single lemma does not apply, use null.
- "translation": the $to translation of the base form when there is one,
  otherwise of the input as given. Only the translation — no explanations,
  no quotes, no transliteration.''';

    final reply = await _complete(
      system: system,
      history: [ChatMessage('user', text)],
      maxTokens: 256,
    );

    final decoded = _extractJson(reply);
    if (decoded is! Map) {
      throw LlmException('The model did not return a valid suggestion.');
    }
    final translation = (decoded['translation'] as String?)?.trim();
    if (translation == null || translation.isEmpty) {
      throw LlmException('The model did not return a translation.');
    }
    final rawBase = decoded['base_form'];
    var baseForm =
        rawBase is String && rawBase.trim().isNotEmpty ? rawBase.trim() : null;
    // Don't suggest a "correction" identical to what was typed.
    if (baseForm != null &&
        baseForm.toLowerCase() == text.trim().toLowerCase()) {
      baseForm = null;
    }
    return (baseForm: baseForm, translation: translation);
  }

  /// Runs one completion against whichever provider is configured.
  static Future<String> _complete({
    required String system,
    required List<ChatMessage> history,
    int maxTokens = 1024,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final provider = providerById(prefs.getString(providerPref) ?? 'anthropic');
    final storedModel = prefs.getString(modelPref(provider.id))?.trim();
    final model = (storedModel == null || storedModel.isEmpty)
        ? provider.defaultModel
        : storedModel;

    switch (provider.id) {
      case 'anthropic':
        return ClaudeService.complete(
          system: system,
          model: model,
          maxTokens: maxTokens,
          messages: [
            for (final m in history) {'role': m.role, 'content': m.text},
          ],
        );
      case 'gemini':
        return _gemini(
          apiKey: prefs.getString(keyPref('gemini'))?.trim(),
          model: model,
          system: system,
          history: history,
        );
      case 'openai':
        return _openAiCompatible(
          baseUrl: 'https://api.openai.com/v1',
          apiKey: prefs.getString(keyPref('openai'))?.trim(),
          keyRequired: true,
          providerLabel: 'OpenAI',
          model: model,
          system: system,
          history: history,
        );
      case 'custom':
      default:
        return _openAiCompatible(
          baseUrl: (prefs.getString(customBaseUrlPref)?.trim().isNotEmpty ??
                  false)
              ? prefs.getString(customBaseUrlPref)!.trim()
              : defaultCustomBaseUrl,
          apiKey: prefs.getString(keyPref('custom'))?.trim(),
          keyRequired: false,
          providerLabel: 'the custom endpoint',
          model: model,
          system: system,
          history: history,
        );
    }
  }

  /// Asks the LLM to plan changes to a deck from a natural-language
  /// instruction, e.g. "create the cards for the numbers 1-10".
  static Future<DeckEditPlan> editDeck({
    required String instruction,
    required String targetLanguage,
    required String nativeLanguage,
    required List<Map<String, String>> existingCards,
  }) async {
    final system = '''
You edit a flashcard deck for a language-learning app. The learner speaks
$nativeLanguage and is learning $targetLanguage.

The deck currently contains these cards (JSON):
${jsonEncode(existingCards)}

The user gives an instruction describing changes to make. Respond with ONLY a
JSON object — no markdown fences, no commentary — in exactly this shape:
{"add": [{"native": "...", "target": "..."}], "remove": ["...", "..."]}

- "add": new cards to create. "native" is the $nativeLanguage side, "target"
  is the $targetLanguage side. Do not duplicate cards already in the deck.
- "remove": the exact "target" text of existing cards that should be deleted.
Use an empty array for whichever does not apply.''';

    final reply = await _complete(
      system: system,
      history: [ChatMessage('user', instruction)],
      maxTokens: 4096,
    );

    final decoded = _extractJson(reply);
    if (decoded is! Map) {
      throw LlmException('The model did not return a valid change plan.');
    }
    final additions = <({String native, String target})>[];
    for (final a in decoded['add'] as List<dynamic>? ?? []) {
      if (a is Map) {
        final native = (a['native'] as String?)?.trim() ?? '';
        final target = (a['target'] as String?)?.trim() ?? '';
        if (native.isNotEmpty && target.isNotEmpty) {
          additions.add((native: native, target: target));
        }
      }
    }
    final removals = <String>[
      for (final r in decoded['remove'] as List<dynamic>? ?? [])
        if (r is String && r.trim().isNotEmpty) r.trim(),
    ];
    if (additions.isEmpty && removals.isEmpty) {
      throw LlmException(
          'The model suggested no changes for that instruction.');
    }
    return DeckEditPlan(additions: additions, removals: removals);
  }

  /// Pulls the first JSON object out of a model reply, tolerating markdown
  /// fences and surrounding prose.
  static dynamic _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw LlmException('The model did not return valid JSON.');
    }
    try {
      return jsonDecode(text.substring(start, end + 1));
    } catch (_) {
      throw LlmException('The model did not return valid JSON.');
    }
  }

  /// Lists model IDs available from a provider, using the (possibly
  /// unsaved) key/URL values passed in from the settings screen.
  static Future<List<String>> listModels({
    required String providerId,
    String? apiKey,
    String? baseUrl,
  }) async {
    final key = apiKey?.trim();
    switch (providerId) {
      case 'anthropic':
        final k = (key == null || key.isEmpty)
            ? await ClaudeService.apiKey()
            : key;
        if (k == null) {
          throw LlmException('Enter an Anthropic API key first.');
        }
        final body = await _getJson(
          Uri.parse('https://api.anthropic.com/v1/models?limit=100'),
          headers: {'x-api-key': k, 'anthropic-version': '2023-06-01'},
        );
        return [
          for (final m in body['data'] as List<dynamic>) m['id'] as String,
        ];
      case 'gemini':
        if (key == null || key.isEmpty) {
          throw LlmException('Enter a Gemini API key first.');
        }
        final body = await _getJson(
          Uri.parse('https://generativelanguage.googleapis.com/'
              'v1beta/models?pageSize=200'),
          headers: {'x-goog-api-key': key},
        );
        return [
          for (final m in body['models'] as List<dynamic>)
            if ((m['supportedGenerationMethods'] as List<dynamic>? ?? [])
                .contains('generateContent'))
              (m['name'] as String).replaceFirst('models/', ''),
        ];
      case 'openai':
      case 'custom':
      default:
        if (providerId == 'openai' && (key == null || key.isEmpty)) {
          throw LlmException('Enter an OpenAI API key first.');
        }
        final base = providerId == 'openai'
            ? 'https://api.openai.com/v1'
            : ((baseUrl == null || baseUrl.trim().isEmpty)
                ? defaultCustomBaseUrl
                : baseUrl.trim());
        final body = await _getJson(
          Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/models'),
          headers: {
            if (key != null && key.isNotEmpty) 'authorization': 'Bearer $key',
          },
        );
        return [
          for (final m in body['data'] as List<dynamic>) m['id'] as String,
        ];
    }
  }

  static Future<dynamic> _getJson(Uri uri,
      {required Map<String, String> headers}) async {
    final http.Response resp;
    try {
      resp = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 30));
    } on SocketException {
      throw LlmException('Could not reach ${uri.host} — check the URL and '
          'your connection.');
    }
    final dynamic body;
    try {
      body = jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (_) {
      throw LlmException(
          'Unexpected response from ${uri.host} (HTTP ${resp.statusCode}).');
    }
    if (resp.statusCode != 200) {
      final msg = (body is Map && body['error'] is Map)
          ? body['error']['message'] as String? ?? 'Unknown API error'
          : 'API error (HTTP ${resp.statusCode})';
      throw LlmException(msg);
    }
    return body;
  }

  static String _tutorSystemPrompt({
    required String targetLanguage,
    required String nativeLanguage,
    String? currentContext,
  }) {
    final system = StringBuffer()
      ..writeln('You are a friendly, expert $targetLanguage language tutor '
          'inside a flashcard app called språk. The learner speaks '
          '$nativeLanguage and is learning $targetLanguage.')
      ..writeln('Answer questions about vocabulary, grammar, pronunciation, '
          'and usage. Keep answers short and practical, and include '
          '$targetLanguage examples with $nativeLanguage glosses where '
          'helpful.');
    if (currentContext != null && currentContext.isNotEmpty) {
      system.writeln('The learner is currently studying: $currentContext');
    }
    return system.toString();
  }

  static Future<String> _openAiCompatible({
    required String baseUrl,
    required String? apiKey,
    required bool keyRequired,
    required String providerLabel,
    required String model,
    required String system,
    required List<ChatMessage> history,
  }) async {
    if (keyRequired && (apiKey == null || apiKey.isEmpty)) {
      throw LlmException(
          'No $providerLabel API key set. Add one in Settings (gear icon).');
    }

    final uri = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions');
    final http.Response resp;
    try {
      resp = await http
          .post(
            uri,
            headers: {
              'content-type': 'application/json',
              if (apiKey != null && apiKey.isNotEmpty)
                'authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': model,
              'messages': [
                {'role': 'system', 'content': system},
                for (final m in history)
                  {'role': m.role, 'content': m.text},
              ],
            }),
          )
          .timeout(const Duration(seconds: 120));
    } on SocketException {
      throw LlmException(
          'Could not reach $providerLabel at $baseUrl — check the URL and '
          'your connection.');
    }

    final dynamic body;
    try {
      body = jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (_) {
      throw LlmException(
          'Unexpected response from $providerLabel (HTTP ${resp.statusCode}).');
    }
    if (resp.statusCode != 200) {
      final msg = (body is Map && body['error'] is Map)
          ? body['error']['message'] as String? ?? 'Unknown API error'
          : 'API error (HTTP ${resp.statusCode})';
      throw LlmException(msg);
    }

    final content = body['choices']?[0]?['message']?['content'];
    if (content is! String || content.trim().isEmpty) {
      throw LlmException('Empty response from $providerLabel.');
    }
    return content.trim();
  }

  static Future<String> _gemini({
    required String? apiKey,
    required String model,
    required String system,
    required List<ChatMessage> history,
  }) async {
    if (apiKey == null || apiKey.isEmpty) {
      throw LlmException(
          'No Gemini API key set. Add one in Settings (gear icon).');
    }

    final uri = Uri.parse('https://generativelanguage.googleapis.com/'
        'v1beta/models/$model:generateContent');
    final http.Response resp;
    try {
      resp = await http
          .post(
            uri,
            headers: {
              'content-type': 'application/json',
              'x-goog-api-key': apiKey,
            },
            body: jsonEncode({
              'system_instruction': {
                'parts': [
                  {'text': system},
                ],
              },
              'contents': [
                for (final m in history)
                  {
                    'role': m.role == 'assistant' ? 'model' : 'user',
                    'parts': [
                      {'text': m.text},
                    ],
                  },
              ],
            }),
          )
          .timeout(const Duration(seconds: 120));
    } on SocketException {
      throw LlmException('Network error — check your connection.');
    }

    final dynamic body;
    try {
      body = jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (_) {
      throw LlmException(
          'Unexpected response from Gemini (HTTP ${resp.statusCode}).');
    }
    if (resp.statusCode != 200) {
      final msg = (body is Map && body['error'] is Map)
          ? body['error']['message'] as String? ?? 'Unknown API error'
          : 'API error (HTTP ${resp.statusCode})';
      throw LlmException(msg);
    }

    final parts = body['candidates']?[0]?['content']?['parts'];
    if (parts is! List) throw LlmException('Empty response from Gemini.');
    final text = parts
        .map((p) => p is Map ? (p['text'] as String? ?? '') : '')
        .join()
        .trim();
    if (text.isEmpty) throw LlmException('Empty response from Gemini.');
    return text;
  }
}
