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

  setUp(() {
    spoken.clear();
    locales.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
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

  testWidgets('a note quoting the target language switches voices mid-note',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final deck = Deck(
      name: 'Русский',
      targetLanguage: 'Russian',
      nativeLanguage: 'English',
      cards: [
        CardItem(
            target: 'собака',
            native: 'dog',
            notes: 'Any breed; пёс is the male one.'),
      ],
    );
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

    // The Cyrillic inside the note is spoken by the Russian voice instead
    // of the English one stumbling over it.
    expect(spoken, ['собака', 'Any breed;', 'пёс', 'is the male one.']);
    expect(locales, ['ru-RU', 'en-US', 'ru-RU', 'en-US']);
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
