import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sprak/models.dart';
import 'package:sprak/screens/quiz_screen.dart';
import 'package:sprak/storage.dart';
import 'package:sprak/theme.dart';
import 'package:sprak/widgets/card_note.dart';

Deck _deck({String notes = ''}) => Deck(
      name: 'Norsk',
      targetLanguage: 'Norwegian',
      nativeLanguage: 'English',
      cards: [CardItem(target: 'hund', native: 'dog', notes: notes)],
    );

/// A deck whose target language is written in another script, so the
/// target-language words in a note can be told from the English around
/// them.
Deck _russian(String notes) => Deck(
      name: 'Русский',
      targetLanguage: 'Russian',
      nativeLanguage: 'English',
      cards: [CardItem(target: 'собака', native: 'dog', notes: notes)],
    );

Widget _app(Deck deck) => MaterialApp(
      theme: SprakTheme.dark(),
      home: QuizScreen(
        store: DeckStore(),
        deck: deck,
        // One direction, so the single card's only question shows the
        // target side — the side auto-play reads.
        direction: QuizDirection.front,
      ),
    );

/// Finds the answer field by its hint (the tutor chat has a text field
/// too).
final _answerField = find.ancestor(
  of: find.text('English'),
  matching: find.byType(TextField),
);

void main() {
  // What flutter_tts was asked to say, in order, and the locale each
  // utterance was set to.
  final spoken = <String>[];
  final locales = <String>[];
  // Every call the engine got, so silencing (a bare "stop") is visible
  // too, not just speech.
  final calls = <String>[];

  setUp(() {
    spoken.clear();
    locales.clear();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      calls.add(call.method);
      if (call.method == 'speak') spoken.add(call.arguments as String);
      if (call.method == 'setLanguage') locales.add(call.arguments as String);
      return 1;
    });
  });

  testWidgets('auto-play reads the target-language question aloud',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app(_deck()));
    // The toggle's saved value loads asynchronously; nothing is spoken
    // until it lands.
    await tester.pumpAndSettle();

    expect(spoken, ['hund']);
  });

  testWidgets('toggling auto-play off silences the quiz and is remembered',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app(_deck()));
    await tester.pumpAndSettle();
    spoken.clear();

    // The app bar toggle is the filled speaker; the outlined one under the
    // prompt plays on demand.
    await tester.tap(find.byIcon(Icons.volume_up));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.volume_off_outlined), findsOneWidget);

    // Answering no longer plays the word either.
    await tester.enterText(_answerField, 'dog');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Correct!'), findsOneWidget);
    expect(spoken, isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('auto_speak'), false);
  });

  testWidgets('a saved-off toggle keeps the first question silent',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_speak': false});
    await tester.pumpWidget(_app(_deck()));
    await tester.pumpAndSettle();

    expect(spoken, isEmpty);
    expect(find.byIcon(Icons.volume_off_outlined), findsOneWidget);
  });

  testWidgets('answering reads the word and then its note',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester
        .pumpWidget(_app(_deck(notes: r'Any dog; the breed is a $rase$.')));
    await tester.pumpAndSettle();
    // The question itself is read without the note — that comes with the
    // answer.
    expect(spoken, ['hund']);
    spoken.clear();
    locales.clear();

    await tester.enterText(_answerField, 'dog');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // The note is read in the learner's language, with the LaTeX
    // delimiters dropped.
    expect(spoken, ['hund', 'Any dog; the breed is a rase .']);
    expect(locales, ['nb-NO', 'en-US']);
  });

  testWidgets('only the target-language words of a note are read',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final deck = _russian('Any breed; пёс is the male one.');
    await tester.pumpWidget(MaterialApp(
      theme: SprakTheme.dark(),
      home: QuizScreen(
          store: DeckStore(), deck: deck, direction: QuizDirection.front),
    ));
    await tester.pumpAndSettle();
    spoken.clear();
    locales.clear();

    await tester.enterText(
      find.ancestor(
          of: find.text('English'), matching: find.byType(TextField)),
      'dog',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // The English explanation around the Cyrillic is skipped: the learner
    // hears the word and the note's Russian, nothing they already know.
    expect(spoken, ['собака', 'пёс']);
    expect(locales, ['ru-RU', 'ru-RU']);
  });

  testWidgets('a note with no target language in it has no speaker',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_speak': false});
    final deck = _russian('Any breed, big or small.');
    await tester.pumpWidget(MaterialApp(
      theme: SprakTheme.dark(),
      home: QuizScreen(
          store: DeckStore(), deck: deck, direction: QuizDirection.front),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.ancestor(
          of: find.text('English'), matching: find.byType(TextField)),
      'dog',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // The note is still shown — there is just nothing in it to hear.
    expect(find.byType(CardNote), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CardNote),
        matching: find.byIcon(Icons.volume_up_outlined),
      ),
      findsNothing,
    );
  });

  testWidgets('the note has its own speaker button', (tester) async {
    SharedPreferences.setMockInitialValues({'auto_speak': false});
    await tester.pumpWidget(_app(_deck(notes: 'Any breed, big or small.')));
    await tester.pumpAndSettle();

    await tester.enterText(_answerField, 'dog');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(spoken, isEmpty);

    final noteSpeaker = find.descendant(
      of: find.byType(CardNote),
      matching: find.byIcon(Icons.volume_up_outlined),
    );
    // The 800x600 test window puts the note below the fold, under the
    // tutor chat panel.
    await tester.ensureVisible(noteSpeaker);
    await tester.pumpAndSettle();
    await tester.tap(noteSpeaker);
    await tester.pumpAndSettle();

    // Just the note — the word has its own button.
    expect(spoken, ['Any breed, big or small.']);
  });

  testWidgets('a card without a note has no note speaker', (tester) async {
    SharedPreferences.setMockInitialValues({'auto_speak': false});
    await tester.pumpWidget(_app(_deck()));
    await tester.pumpAndSettle();

    await tester.enterText(_answerField, 'dog');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byType(CardNote), findsNothing);
  });

  testWidgets('moving to the next card cuts off the last one being read',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    // A taller window, so the Next button sits clear of the tutor chat
    // panel and can be clicked.
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final deck = Deck(
      name: 'Norsk',
      targetLanguage: 'Norwegian',
      nativeLanguage: 'English',
      cards: [
        CardItem(target: 'hund', native: 'dog', notes: 'A long note to read.'),
        CardItem(target: 'katt', native: 'cat'),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      theme: SprakTheme.dark(),
      home: QuizScreen(
        store: DeckStore(),
        deck: deck,
        // Questions show the English side, so no new question is read
        // over the answer still being spoken.
        direction: QuizDirection.back,
      ),
    ));
    await tester.pumpAndSettle();

    final field = find.ancestor(
        of: find.text('Norwegian'), matching: find.byType(TextField));
    await tester.enterText(field, 'hund');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    // The answer plays the word and its note.
    expect(spoken, isNotEmpty);
    calls.clear();

    // Moving on silences the card that was talking, and the new question
    // — asked in English — is not read.
    await tester.tap(find.text('Next  ⏎'));
    await tester.pumpAndSettle();
    expect(calls, contains('stop'));
    expect(calls, isNot(contains('speak')));
  });

  testWidgets('the speaker button still plays on demand with auto-play off',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_speak': false});
    await tester.pumpWidget(_app(_deck()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.volume_up_outlined));
    await tester.pumpAndSettle();
    expect(spoken, ['hund']);
  });
}
