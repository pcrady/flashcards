import 'dart:async';
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

/// What the add-card flow's AI pass proposes for one typed word: the
/// dictionary form of an inflected input (null when there is nothing to
/// correct, and always for non-language decks), the text for the card's
/// other side, the tags that fit the card — which may include labels the
/// deck does not define yet — and, out of the tags already sitting on the
/// card being typed, the ones that are wrong for it.
typedef CardSuggestion = ({
  String? baseForm,
  String otherSide,
  List<String> tags,
  List<String> removeTags,
});

/// A card the model proposes to create.
typedef CardAddition = ({
  String native,
  String target,
  String notes,
  List<String> tags,
});

/// The complete new tag list for one card already in the deck.
typedef CardRetag = ({String target, List<String> tags});

/// The replacement note for one card already in the deck (empty clears it).
typedef CardNoteEdit = ({String target, String notes});

/// A reviewed-before-apply set of deck changes proposed by the LLM.
class DeckEditPlan {
  final List<CardAddition> additions;

  /// Target-language text of existing cards to delete.
  final List<String> removals;

  /// Retags for cards already in the deck: the target text of the card and
  /// the complete new tag list it should end up with.
  final List<CardRetag> retags;

  /// Note rewrites for cards already in the deck.
  final List<CardNoteEdit> noteEdits;

  DeckEditPlan({
    required this.additions,
    required this.removals,
    List<CardRetag>? retags,
    List<CardNoteEdit>? noteEdits,
  })  : retags = retags ?? [],
        noteEdits = noteEdits ?? [];

  bool get isEmpty =>
      additions.isEmpty &&
      removals.isEmpty &&
      retags.isEmpty &&
      noteEdits.isEmpty;
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

  /// Completes the other side of a math/general flashcard: given the
  /// question, produce the answer, or vice versa, plus the tags that suit
  /// the finished card.
  static Future<CardSuggestion> completeCard({
    required String text,
    required bool fromQuestion,
    required String subject,
    List<String> existingTags = const [],
    List<String> appliedTags = const [],
  }) async {
    final from = fromQuestion ? 'prompt' : 'answer';
    final to = fromQuestion ? 'answer' : 'prompt';
    final system = '''
You complete flashcards for studying ${subject.toLowerCase()}. The user
sends the $from side of a card.

Respond with ONLY a JSON object — no markdown fences, no commentary — in
exactly this shape:
{"$to": "...", "tags": ["..."]${_removeShape(appliedTags)}}

- "$to": the text of the $to side — short, no explanations, and no
  unnecessary punctuation such as a trailing period or surrounding quotes.
  A prompt side is a bare concept, term, or expression ("Coulomb's law"),
  never phrased as a question. Inline LaTeX between \$ signs is rendered,
  so use it for mathematical notation, with backslashes escaped for JSON
  ("\$\\\\frac{a}{b}\$").
${_tagRules(existingTags, appliedTags)}''';

    final reply = await _complete(
      system: system,
      history: [ChatMessage('user', text)],
      maxTokens: 512,
    );

    // A model that answered in plain prose (easy to slip into when the
    // answer is one LaTeX expression) is still perfectly usable — take the
    // whole reply as the completion and skip the tags.
    Map<dynamic, dynamic>? decoded;
    try {
      final json = _extractJson(reply);
      if (json is Map) decoded = json;
    } on LlmException {
      decoded = null;
    }
    if (decoded == null) {
      final plain = reply.trim();
      if (plain.isEmpty) {
        throw LlmException('The model did not return a suggestion.');
      }
      return (
        baseForm: null,
        otherSide: plain,
        tags: const <String>[],
        removeTags: const <String>[],
      );
    }
    final otherSide = (decoded[to] as String?)?.trim() ?? '';
    if (otherSide.isEmpty) {
      throw LlmException('The model did not return a suggestion.');
    }
    final tags = _tagList(decoded['tags']);
    return (
      baseForm: null,
      otherSide: otherSide,
      tags: tags,
      removeTags: _removals(decoded['remove'], appliedTags, tags),
    );
  }

  /// The shared "tags" instructions for the add-card suggestions. Unlike
  /// [editDeck], which may only pick from the deck's list, this flow lets
  /// the model coin a label — the deck gains it when the user accepts the
  /// suggestion.
  ///
  /// [appliedTags] are the tags already sitting on the card being typed.
  /// They carry over from the previously added card, so some of them can
  /// be plain wrong for this one (a "noun" left over from a run of nouns
  /// on a card that turns out to be an adjective); the model reports those
  /// in "remove".
  static String _tagRules(
    List<String> existingTags,
    List<String> appliedTags,
  ) {
    final known = existingTags.isEmpty
        ? 'The deck defines no tags yet, so any tag you use will be a new '
            'one.'
        : 'Tags this deck already uses, to be reused verbatim (matching '
            'their capitalization) whenever one of them fits: '
            '${jsonEncode(existingTags)}.';
    final removeRule = appliedTags.isEmpty
        ? ''
        : '''
- "remove": which of the tags already on this card, ${jsonEncode(appliedTags)},
  are wrong for it. They were carried over from the card added before this
  one, so a category label may contradict this card — a part-of-speech tag
  for a different part of speech, a topic the card has nothing to do with.
  List those, copied verbatim from that array. Leave alone every tag that
  still fits and every tag you cannot judge from the card alone (a lesson,
  chapter, or difficulty label), and never list a tag you also put in
  "tags". Use an empty array when they all still fit.''';
    return '''
- "tags": the labels that classify this card so it can be filtered and
  studied by category — part of speech, topic, register, difficulty, and
  the like. $known
  Coin a new tag only when no existing one fits and the label is general
  enough that other cards in the deck would share it — never something
  specific to this one card. Prefer one or two tags, never more than
  three, and use an empty array when nothing clearly applies. Judge this
  card on its own — do not carry over a label just because it is already
  there.$removeRule''';
  }

  /// The `"remove"` field of the JSON shape, present only when there are
  /// [appliedTags] for the model to judge.
  static String _removeShape(List<String> appliedTags) =>
      appliedTags.isEmpty ? '' : ', "remove": ["..."]';

  /// The model's "remove" list, kept to tags actually on the card (in the
  /// card's own spelling) and never to one it simultaneously suggested.
  static List<String> _removals(
    dynamic raw,
    List<String> appliedTags,
    List<String> suggested,
  ) {
    final removals = <String>[];
    for (final name in _tagList(raw)) {
      final match = appliedTags.firstWhere(
        (t) => t.toLowerCase() == name.toLowerCase(),
        orElse: () => '',
      );
      if (match.isEmpty || removals.contains(match)) continue;
      if (suggested.any((t) => t.toLowerCase() == match.toLowerCase())) {
        continue;
      }
      removals.add(match);
    }
    return removals;
  }

  /// Judges whether a typed [answer] is equivalent to the [expected] one
  /// (different notation, formatting, or wording still counts).
  static Future<bool> gradeAnswer({
    required String question,
    required String expected,
    required String answer,
    required String subject,
  }) async {
    final reply = await _complete(
      system: 'You grade flashcard answers for studying '
          '${subject.toLowerCase()}. Decide whether the learner\'s answer '
          'is equivalent to the expected answer for the given prompt. '
          'Accept equivalent notation, formatting, or wording (e.g. '
          '\$2x\$ vs \$2*x\$, "1/2" vs "0.5", reordered terms, missing '
          'LaTeX markup); reject answers with wrong or missing content. '
          'Respond with ONLY one word: CORRECT or WRONG.',
      history: [
        ChatMessage(
            'user',
            'Prompt: $question\n'
            'Expected answer: $expected\n'
            'Learner\'s answer: $answer'),
      ],
      maxTokens: 16,
    );
    return reply.trim().toUpperCase().startsWith('CORRECT');
  }

  /// Streams a chat turn for the tutor conversation box as text deltas,
  /// so the reply can be rendered as it is generated. [subject] switches
  /// the tutor persona for non-language decks (e.g. "Math").
  static Stream<String> chatStream({
    required List<ChatMessage> history,
    required String targetLanguage,
    required String nativeLanguage,
    String? subject,
    String? currentContext,
  }) async* {
    final system = _tutorSystemPrompt(
      targetLanguage: targetLanguage,
      nativeLanguage: nativeLanguage,
      subject: subject,
      currentContext: currentContext,
    );
    final prefs = await SharedPreferences.getInstance();
    final provider = providerById(prefs.getString(providerPref) ?? 'anthropic');
    final storedModel = prefs.getString(modelPref(provider.id))?.trim();
    final model = (storedModel == null || storedModel.isEmpty)
        ? provider.defaultModel
        : storedModel;

    switch (provider.id) {
      case 'anthropic':
        final key = await ClaudeService.apiKey();
        if (key == null) {
          throw LlmException(
              'No Anthropic API key set. Add one in Settings (gear icon).');
        }
        yield* _anthropicStream(
            apiKey: key, model: model, system: system, history: history);
      case 'gemini':
        yield* _geminiStream(
          apiKey: prefs.getString(keyPref('gemini'))?.trim(),
          model: model,
          system: system,
          history: history,
        );
      case 'openai':
        yield* _openAiCompatibleStream(
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
        yield* _openAiCompatibleStream(
          baseUrl:
              (prefs.getString(customBaseUrlPref)?.trim().isNotEmpty ?? false)
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

  /// POSTs [body] to an SSE endpoint and yields each `data:` payload
  /// (minus the `[DONE]` sentinel used by OpenAI-style APIs).
  static Stream<String> _sse({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, dynamic> body,
    required String providerLabel,
  }) async* {
    final client = http.Client();
    try {
      final request = http.Request('POST', uri)
        ..headers.addAll({
          'content-type': 'application/json',
          'accept': 'text/event-stream',
          ...headers,
        })
        ..body = jsonEncode(body);
      final http.StreamedResponse resp;
      try {
        resp = await client.send(request).timeout(const Duration(seconds: 30));
      } on SocketException {
        throw LlmException('Could not reach $providerLabel — check the URL '
            'and your connection.');
      } on TimeoutException {
        throw LlmException('$providerLabel did not respond — try again.');
      }
      if (resp.statusCode != 200) {
        final text = await resp.stream.bytesToString();
        var msg = 'API error (HTTP ${resp.statusCode})';
        try {
          final decoded = jsonDecode(text);
          if (decoded is Map && decoded['error'] is Map) {
            msg = decoded['error']['message'] as String? ?? msg;
          }
        } catch (_) {}
        throw LlmException(msg);
      }
      await for (final line in resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data.isEmpty || data == '[DONE]') continue;
        yield data;
      }
    } finally {
      client.close();
    }
  }

  static Stream<String> _anthropicStream({
    required String apiKey,
    required String model,
    required String system,
    required List<ChatMessage> history,
  }) async* {
    await for (final data in _sse(
      uri: Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {'x-api-key': apiKey, 'anthropic-version': '2023-06-01'},
      body: {
        'model': model,
        'max_tokens': 1024,
        'stream': true,
        'system': system,
        'messages': [
          for (final m in history) {'role': m.role, 'content': m.text},
        ],
      },
      providerLabel: 'Anthropic',
    )) {
      final dynamic event;
      try {
        event = jsonDecode(data);
      } catch (_) {
        continue;
      }
      if (event is! Map) continue;
      if (event['type'] == 'error') {
        throw LlmException(
            (event['error'] as Map?)?['message'] as String? ?? 'API error');
      }
      if (event['type'] == 'content_block_delta') {
        final delta = event['delta'];
        if (delta is Map && delta['type'] == 'text_delta') {
          final text = delta['text'] as String? ?? '';
          if (text.isNotEmpty) yield text;
        }
      }
    }
  }

  static Stream<String> _openAiCompatibleStream({
    required String baseUrl,
    required String? apiKey,
    required bool keyRequired,
    required String providerLabel,
    required String model,
    required String system,
    required List<ChatMessage> history,
  }) async* {
    if (keyRequired && (apiKey == null || apiKey.isEmpty)) {
      throw LlmException(
          'No $providerLabel API key set. Add one in Settings (gear icon).');
    }
    await for (final data in _sse(
      uri: Uri.parse(
          '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions'),
      headers: {
        if (apiKey != null && apiKey.isNotEmpty)
          'authorization': 'Bearer $apiKey',
      },
      body: {
        'model': model,
        'stream': true,
        'messages': [
          {'role': 'system', 'content': system},
          for (final m in history) {'role': m.role, 'content': m.text},
        ],
      },
      providerLabel: providerLabel,
    )) {
      final dynamic event;
      try {
        event = jsonDecode(data);
      } catch (_) {
        continue;
      }
      final content = event?['choices']?[0]?['delta']?['content'];
      if (content is String && content.isNotEmpty) yield content;
    }
  }

  static Stream<String> _geminiStream({
    required String? apiKey,
    required String model,
    required String system,
    required List<ChatMessage> history,
  }) async* {
    if (apiKey == null || apiKey.isEmpty) {
      throw LlmException(
          'No Gemini API key set. Add one in Settings (gear icon).');
    }
    await for (final data in _sse(
      uri: Uri.parse('https://generativelanguage.googleapis.com/'
          'v1beta/models/$model:streamGenerateContent?alt=sse'),
      headers: {'x-goog-api-key': apiKey},
      body: {
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
      },
      providerLabel: 'Gemini',
    )) {
      final dynamic event;
      try {
        event = jsonDecode(data);
      } catch (_) {
        continue;
      }
      if (event is Map && event['error'] is Map) {
        throw LlmException(
            event['error']['message'] as String? ?? 'API error');
      }
      final parts = event?['candidates']?[0]?['content']?['parts'];
      if (parts is! List) continue;
      for (final p in parts) {
        final text = p is Map ? p['text'] as String? ?? '' : '';
        if (text.isNotEmpty) yield text;
      }
    }
  }

  /// Analyzes [text] (a word or phrase in [from]) for the add-card flow:
  /// returns its basic dictionary form when the input is inflected (null
  /// when it already is the dictionary form), its [to] translation, and the
  /// tags that fit the card. [existingTags] are the deck's current tags,
  /// which the model reuses when one applies.
  static Future<CardSuggestion> suggestCard({
    required String text,
    required String from,
    required String to,
    List<String> existingTags = const [],
    List<String> appliedTags = const [],
  }) async {
    final system = '''
You help build flashcards for a language-learning app. The user sends one
word or short phrase in $from.

Respond with ONLY a JSON object — no markdown fences, no commentary — in
exactly this shape:
{"base_form": "..." or null, "translation": "...", "tags": ["..."]${_removeShape(appliedTags)}}

- "base_form": if the input is an inflected form (a conjugated verb, a
  plural or declined noun, a comparative/superlative adjective, etc.), the
  basic dictionary form (lemma) in $from, keeping the input's
  capitalization style. If the input already is the dictionary form, or is
  a phrase where a single lemma does not apply, use null.
- "translation": the $to translation of the base form when there is one,
  otherwise of the input as given. Only the translation — no explanations,
  no quotes, no transliteration, and no unnecessary punctuation such as a
  trailing period.
${_tagRules(existingTags, appliedTags)}''';

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
    final tags = _tagList(decoded['tags']);
    return (
      baseForm: baseForm,
      otherSide: translation,
      tags: tags,
      removeTags: _removals(decoded['remove'], appliedTags, tags),
    );
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
    String? subject,
    required List<Map<String, dynamic>> existingCards,
    List<String> availableTags = const [],
  }) async {
    final intro = subject != null
        ? '''
You edit a flashcard deck for studying ${subject.toLowerCase()}. Each card
has a "target" side (the prompt) and a "native" side (the answer). Phrase
the prompt side as the bare concept, term, or name itself — "Coulomb's
law", NOT "What is Coulomb's law?". Never phrase it as a question unless
the user explicitly asks for question-style cards. Inline LaTeX between
\$ signs is rendered, so use it for mathematical notation.'''
        : '''
You edit a flashcard deck for a language-learning app. The learner speaks
$nativeLanguage and is learning $targetLanguage.''';
    final sides = subject != null
        ? '"native" is the answer side, "target" is the prompt side '
            '(a bare concept, term, or expression — not a question).'
        : '"native" is the $nativeLanguage side, "target" is the '
            '$targetLanguage side.';
    // Tagging is only offered when the deck defines tags — the model picks
    // from that list and never invents new ones.
    final hasTags = availableTags.isNotEmpty;
    final shape = hasTags
        ? '{"add": [{"native": "...", "target": "...", "notes": "...", '
            '"tags": ["..."]}], '
            '"remove": ["...", "..."], '
            '"tag": [{"target": "...", "tags": ["..."]}], '
            '"note": [{"target": "...", "notes": "..."}]}'
        : '{"add": [{"native": "...", "target": "...", "notes": "..."}], '
            '"remove": ["...", "..."], '
            '"note": [{"target": "...", "notes": "..."}]}';
    final tagRules = hasTags
        ? '''

This deck's cards can be labelled with these tags, and only these:
${jsonEncode(availableTags)}
- "tags" on an added card: the tags that apply to it, copied exactly from
  the list above. Use an empty array when none fit. Never invent a tag.
- "tag": tag changes for cards ALREADY in the deck. "target" is the exact
  existing "target" text, and "tags" is the complete new tag list for that
  card — include the tags it already has and should keep. List a card only
  when its tags actually change.'''
        : '';
    final system = '''
$intro

The deck currently contains these cards (JSON):
${jsonEncode(existingCards)}

The user gives an instruction describing changes to make. Respond with ONLY a
JSON object — no markdown fences, no commentary — in exactly this shape:
$shape

- "add": new cards to create. $sides Do not duplicate cards already in the
  deck. Do not add unnecessary punctuation to card text — no trailing
  periods, no surrounding quotation marks; only punctuation that is
  genuinely part of the word or phrase (e.g. a question mark on an actual
  question).
- "remove": the exact "target" text of existing cards that should be deleted.
- "notes" on an added card: an optional one- or two-sentence note that
  clarifies the card — a shade of meaning, a usage restriction, a register,
  or a short example sentence with its translation. It is never asked as an
  answer. Use "" when the card needs no explanation.
- "note": note changes for cards ALREADY in the deck. "target" is the exact
  existing "target" text, and "notes" is the complete replacement note (""
  clears it). List a card only when its note actually changes.$tagRules
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
    final additions = <CardAddition>[];
    for (final a in decoded['add'] as List<dynamic>? ?? []) {
      if (a is Map) {
        final native = (a['native'] as String?)?.trim() ?? '';
        final target = (a['target'] as String?)?.trim() ?? '';
        if (native.isNotEmpty && target.isNotEmpty) {
          additions.add((
            native: native,
            target: target,
            notes: (a['notes'] as String?)?.trim() ?? '',
            tags: _tagList(a['tags']),
          ));
        }
      }
    }
    final removals = <String>[
      for (final r in decoded['remove'] as List<dynamic>? ?? [])
        if (r is String && r.trim().isNotEmpty) r.trim(),
    ];
    final retags = <CardRetag>[];
    for (final t in decoded['tag'] as List<dynamic>? ?? []) {
      if (t is Map) {
        final target = (t['target'] as String?)?.trim() ?? '';
        if (target.isNotEmpty) {
          retags.add((target: target, tags: _tagList(t['tags'])));
        }
      }
    }
    final noteEdits = <CardNoteEdit>[];
    for (final n in decoded['note'] as List<dynamic>? ?? []) {
      if (n is Map) {
        final target = (n['target'] as String?)?.trim() ?? '';
        if (target.isNotEmpty) {
          noteEdits
              .add((target: target, notes: (n['notes'] as String?)?.trim() ?? ''));
        }
      }
    }
    final plan = DeckEditPlan(
      additions: additions,
      removals: removals,
      retags: retags,
      noteEdits: noteEdits,
    );
    if (plan.isEmpty) {
      throw LlmException(
          'The model suggested no changes for that instruction.');
    }
    return plan;
  }

  /// The non-empty strings out of a model-supplied "tags" value.
  static List<String> _tagList(dynamic raw) => [
        if (raw is List)
          for (final t in raw)
            if (t is String && t.trim().isNotEmpty) t.trim(),
      ];

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
    String? subject,
    String? currentContext,
  }) {
    final system = StringBuffer();
    if (subject != null) {
      system
        ..writeln('You are a friendly, expert '
            '${subject.toLowerCase()} tutor inside a flashcard app called '
            'språk. The learner is studying flashcards on this subject.')
        ..writeln('Answer questions about the material. Keep answers '
            'short, practical, and step-by-step where that helps.')
        ..writeln('Plain text only — no markdown. Inline LaTeX between \$ '
            'signs is rendered, so use it for mathematical or technical '
            'notation; never use it for ordinary text.');
    } else {
      system
        ..writeln('You are a friendly, expert $targetLanguage language '
            'tutor inside a flashcard app called språk. The learner speaks '
            '$nativeLanguage and is learning $targetLanguage.')
        ..writeln('Answer questions about vocabulary, grammar, '
            'pronunciation, and usage. Keep answers short and practical, '
            'and include $targetLanguage examples with $nativeLanguage '
            'glosses where helpful.')
        ..writeln('Plain text only — no markdown. Inline LaTeX between \$ '
            'signs is rendered, so you may use it where real notation '
            'helps (e.g. IPA or stress marks); never use it for ordinary '
            'text.');
    }
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
