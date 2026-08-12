import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sprak/models.dart';
import 'package:sprak/screens/deck_detail_screen.dart';
import 'package:sprak/storage.dart';
import 'package:sprak/theme.dart';
import 'package:sprak/widgets/card_note.dart';

void main() {
  Deck deckWith(List<CardItem> cards) => Deck(
        name: 'Swedish',
        targetLanguage: 'Swedish',
        nativeLanguage: 'English',
        cards: cards,
      );

  Future<void> pumpDetail(WidgetTester tester, Deck deck) async {
    SharedPreferences.setMockInitialValues({});
    // Taller than the default test surface so the card list below the
    // add panel is actually on screen.
    await tester.binding.setSurfaceSize(const Size(1000, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: SprakTheme.dark(),
      home: DeckDetailScreen(store: DeckStore(), deck: deck),
    ));
    await tester.pump();
  }

  test('notes survive a JSON round trip', () {
    final card = CardItem(
      native: 'to run',
      target: 'att springa',
      notes: 'Jag springer varje morgon. — I run every morning.',
    );
    final restored = CardItem.fromJson(card.toJson());
    expect(restored.notes, card.notes);
  });

  test('a card with no notes stays out of the saved JSON', () {
    final card = CardItem(native: 'house', target: 'hus');
    expect(card.notes, '');
    expect(card.toJson().containsKey('notes'), isFalse);
  });

  test('cards saved before notes existed load with empty notes', () {
    final card = CardItem.fromJson({
      'id': 'abc',
      'native': 'house',
      'target': 'hus',
      'timesCorrect': 2,
      'timesWrong': 1,
    });
    expect(card.notes, '');
  });

  testWidgets('a new card carries the note typed in the add panel',
      (tester) async {
    final deck = deckWith([]);
    await pumpDetail(tester, deck);

    await tester.enterText(find.byType(TextField).first, 'to run');
    await tester.enterText(find.byType(TextField).at(1), 'att springa');
    await tester.enterText(
        find.byType(TextField).at(2), 'Jag springer varje morgon.');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(deck.cards.single.notes, 'Jag springer varje morgon.');
  });

  testWidgets('the note shows under the card in the deck list',
      (tester) async {
    await pumpDetail(
      tester,
      deckWith([
        CardItem(
          native: 'to run',
          target: 'att springa',
          notes: 'Used for the activity, not for machines.',
        ),
        CardItem(native: 'house', target: 'hus'),
      ]),
    );

    expect(find.byType(CardNote), findsOneWidget);
    expect(find.text('Used for the activity, not for machines.'),
        findsOneWidget);
  });

  testWidgets('editing a card saves its note', (tester) async {
    final deck = deckWith([CardItem(native: 'house', target: 'hus')]);
    await pumpDetail(tester, deck);

    await tester.tap(find.byTooltip('Edit card'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Notes'), 'Neuter: ett hus.');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // Only the model is checked here: the list redraws after the store
    // save returns, and DeckStore.save never completes under flutter_test
    // (path_provider has no plugin registered).
    expect(deck.cards.single.notes, 'Neuter: ett hus.');
  });
}
