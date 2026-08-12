import 'package:flutter_test/flutter_test.dart';

import 'package:sprak/services/tts_service.dart';

void main() {
  List<Utterance> split(String text,
          {String target = 'ru-RU', String native = 'en-US'}) =>
      splitByScript(text, targetLocale: target, nativeLocale: native);

  test('a note mixing Russian and English is split per language', () {
    expect(
      split('собака — dog, any breed'),
      [
        (text: 'собака —', locale: 'ru-RU'),
        (text: 'dog, any breed', locale: 'en-US'),
      ],
    );
  });

  test('every script change starts a new utterance', () {
    expect(
      split('Formal: вы. Informal: ты.'),
      [
        (text: 'Formal:', locale: 'en-US'),
        // The period trailing each word stays with the run it sits inside:
        // only a letter of the other script closes a run.
        (text: 'вы.', locale: 'ru-RU'),
        (text: 'Informal:', locale: 'en-US'),
        (text: 'ты.', locale: 'ru-RU'),
      ],
    );
  });

  test('a single-language note stays a single utterance', () {
    expect(split('Used only in writing.'),
        [(text: 'Used only in writing.', locale: 'en-US')]);
    expect(split('Пишется только так'),
        [(text: 'Пишется только так', locale: 'ru-RU')]);
  });

  test('a Latin-script target language cannot be told apart', () {
    // Norwegian and English share an alphabet, so the note is read whole
    // in the learner's language rather than guessed at.
    expect(
      split('hunden means the dog', target: 'nb-NO'),
      [(text: 'hunden means the dog', locale: 'en-US')],
    );
  });

  test('empty and blank notes say nothing', () {
    expect(split(''), isEmpty);
    expect(split('   '), isEmpty);
  });

  test('other non-Latin scripts split too', () {
    expect(
      splitByScript('犬 means dog',
          targetLocale: 'ja-JP', nativeLocale: 'en-US'),
      [
        (text: '犬', locale: 'ja-JP'),
        (text: 'means dog', locale: 'en-US'),
      ],
    );
    expect(
      splitByScript('σκύλος is a dog',
          targetLocale: 'el-GR', nativeLocale: 'en-US'),
      [
        (text: 'σκύλος', locale: 'el-GR'),
        (text: 'is a dog', locale: 'en-US'),
      ],
    );
  });
}
