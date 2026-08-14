import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sprak/models.dart';
import 'package:sprak/screens/quiz_screen.dart';
import 'package:sprak/storage.dart';
import 'package:sprak/theme.dart';

Deck _deck() => Deck(
      name: 'Norsk',
      targetLanguage: 'Norwegian',
      nativeLanguage: 'English',
      cards: [CardItem(target: 'hund', native: 'dog')],
    );

Widget _app(Deck deck) => MaterialApp(
      theme: SprakTheme.dark(),
      home: QuizScreen(
        store: DeckStore(),
        deck: deck,
        // One direction, so the single card's only question shows the
        // target side — the side the pencil sits beside.
        direction: QuizDirection.front,
      ),
    );

/// The pencil beside the question, as opposed to the one in the app bar.
final _inlineEdit = find.descendant(
  of: find.byType(SingleChildScrollView),
  matching: find.byIcon(Icons.edit_outlined),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter_tts'), (call) async => 1);
  });

  testWidgets('the question carries its own edit button', (tester) async {
    await tester.pumpWidget(_app(_deck()));
    await tester.pump();

    // One beside the question, one in the app bar.
    expect(find.byIcon(Icons.edit_outlined), findsNWidgets(2));
    expect(_inlineEdit, findsOneWidget);
  });

  testWidgets('editing from the question updates the card being asked',
      (tester) async {
    final deck = _deck();
    await tester.pumpWidget(_app(deck));
    await tester.pump();
    expect(find.text('hund'), findsOneWidget);

    // The quiz pane is short in a test-sized window, so the question can
    // sit outside the scroll viewport.
    await tester.ensureVisible(_inlineEdit);
    await tester.pumpAndSettle();
    await tester.tap(_inlineEdit);
    await tester.pumpAndSettle();
    expect(find.text('Edit card'), findsOneWidget);

    await tester.enterText(
      find.ancestor(
        of: find.text('Norwegian'),
        matching: find.byType(TextField),
      ),
      'hunden',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('hunden'), findsOneWidget);
    expect(deck.cards.single.target, 'hunden');
  });
}
