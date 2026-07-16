import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sprak/models.dart';
import 'package:sprak/screens/quiz_screen.dart';
import 'package:sprak/storage.dart';
import 'package:sprak/theme.dart';

void main() {
  testWidgets('math deck multiple choice renders 8 LaTeX options',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final deck = Deck(
      name: 'Integrals',
      kind: DeckKind.math,
      targetLanguage: 'Math',
      nativeLanguage: 'English',
      cards: [
        for (var i = 1; i <= 8; i++)
          CardItem(
              target: r'$\int x^' '$i' r' dx$',
              native: r'$x^' '${i + 1}' r'/' '${i + 1}' r' + C$'),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      theme: SprakTheme.dark(),
      home: QuizScreen(
        store: DeckStore(),
        deck: deck,
        style: QuizStyle.multipleChoice,
      ),
    ));
    await tester.pump();

    // Group size is 6, so the first group offers 8 options drawn from the
    // whole deck: 4 two-column rows.
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Press 1–8'), findsOneWidget);
  });
}
