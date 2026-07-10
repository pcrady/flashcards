import 'package:flutter_tts/flutter_tts.dart';

/// Thin wrapper around flutter_tts for speaking words in the deck's
/// target language.
class TtsService {
  static final TtsService _instance = TtsService._();
  factory TtsService() => _instance;
  TtsService._();

  final FlutterTts _tts = FlutterTts();

  Future<void> speak(String text, String ttsLocale) async {
    await _tts.stop();
    await _tts.setLanguage(ttsLocale);
    await _tts.setSpeechRate(0.45);
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
}
