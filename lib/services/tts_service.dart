import 'package:flutter_tts/flutter_tts.dart';

/// One thing to say, in one language.
typedef Utterance = ({String text, String locale});

/// The letters each locale's writing system uses, for the locales whose
/// script sets them apart from the Latin alphabet. Everything absent here
/// (Spanish, Norwegian, Turkish…) is written in Latin letters, which no
/// amount of character inspection can tell apart from English.
const _scriptRanges = <String, String>{
  'ru': r'Ѐ-ԯ',
  'uk': r'Ѐ-ԯ',
  'el': r'Ͱ-Ͽἀ-῿',
  'hi': r'ऀ-ॿ',
  'ar': r'؀-ۿݐ-ݿ',
  'he': r'֐-׿',
  'th': r'฀-๿',
  'ja': r'぀-ヿ一-鿿',
  'zh': r'㐀-䶿一-鿿',
  'ko': r'ᄀ-ᇿ㄰-㆏가-힯',
};

final _scriptPatterns = {
  for (final e in _scriptRanges.entries)
    e.key: RegExp('[${e.value}]', unicode: true),
};

/// Any letter, so text can be split on script changes without treating
/// spaces, digits, or punctuation as a language of their own.
final _letter = RegExp(r'\p{L}', unicode: true);

/// Splits text that mixes two writing systems into one utterance per run,
/// so each part is read by a voice that can pronounce it — a note like
/// "собака — dog, any breed" is said half in Russian and half in English
/// instead of an English voice stumbling through the Cyrillic.
///
/// Only the script tells the two apart, so this helps exactly when
/// [targetLocale] is written in something other than Latin letters; a
/// Latin-script target (Spanish, Norwegian…) comes back as one utterance
/// in [nativeLocale], the same as before.
List<Utterance> splitByScript(
  String text, {
  required String targetLocale,
  required String nativeLocale,
}) {
  final script = _scriptPatterns[targetLocale.split('-').first];
  if (text.trim().isEmpty) return const [];
  if (script == null || !script.hasMatch(text)) {
    return [(text: text, locale: nativeLocale)];
  }

  final runs = <Utterance>[];
  // Which language the current run belongs to, unknown until its first
  // letter: punctuation and spaces stay with the run they are inside.
  bool? inTarget;
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (!_letter.hasMatch(char)) continue;
    final isTarget = script.hasMatch(char);
    if (inTarget == null) {
      inTarget = isTarget;
      continue;
    }
    if (isTarget == inTarget) continue;
    // A script change: close the run before this letter.
    final run = text.substring(start, i).trim();
    if (run.isNotEmpty) {
      runs.add((text: run, locale: inTarget ? targetLocale : nativeLocale));
    }
    inTarget = isTarget;
    start = i;
  }
  final tail = text.substring(start).trim();
  if (tail.isNotEmpty) {
    runs.add(
        (text: tail, locale: inTarget == true ? targetLocale : nativeLocale));
  }
  return runs;
}

/// Thin wrapper around flutter_tts for speaking words in the deck's
/// target language.
class TtsService {
  static final TtsService _instance = TtsService._();
  factory TtsService() => _instance;
  TtsService._();

  final FlutterTts _tts = FlutterTts();

  /// Whether the engine has been told to complete [FlutterTts.speak] when
  /// the utterance finishes rather than when it starts — what lets
  /// [speakAll] queue instead of cutting itself off. Sent once.
  bool _awaitsCompletion = false;

  /// Bumped by every new request, so a queue that has been superseded
  /// stops rather than talking over its replacement.
  int _generation = 0;

  Future<void> speak(String text, String ttsLocale) =>
      speakAll([(text: text, locale: ttsLocale)]);

  /// Says each utterance in turn, in its own language, replacing whatever
  /// was being said.
  Future<void> speakAll(List<Utterance> utterances) async {
    final generation = ++_generation;
    if (!_awaitsCompletion) {
      _awaitsCompletion = true;
      // Not awaited: calls on the channel arrive in the order they are
      // made, so the flag is set before the speaking below.
      _tts.awaitSpeakCompletion(true);
    }
    await _tts.stop();
    for (final u in utterances) {
      if (generation != _generation) return;
      if (u.text.trim().isEmpty) continue;
      await _tts.setLanguage(u.locale);
      await _tts.setSpeechRate(0.45);
      await _tts.speak(u.text);
    }
  }

  Future<void> stop() {
    _generation++;
    return _tts.stop();
  }
}
