import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sprak/models.dart';
import 'package:sprak/screens/deck_detail_screen.dart';
import 'package:sprak/storage.dart';
import 'package:sprak/theme.dart';

void main() {
  Future<Deck> pumpDetail(WidgetTester tester, Deck deck) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      theme: SprakTheme.dark(),
      home: DeckDetailScreen(store: DeckStore(), deck: deck),
    ));
    await tester.pump();
    return deck;
  }

  Deck emptyDeck({List<String> tags = const []}) => Deck(
        name: 'Swedish',
        targetLanguage: 'Swedish',
        nativeLanguage: 'English',
        tags: List.of(tags),
      );

  testWidgets('a new card carries the tags picked in the add panel',
      (tester) async {
    final deck = await pumpDetail(
        tester, emptyDeck(tags: ['verb', 'adjective']));

    await tester.enterText(find.byType(TextField).first, 'to run');
    await tester.enterText(find.byType(TextField).at(1), 'att springa');
    await tester.tap(find.text('verb'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(deck.cards, hasLength(1));
    expect(deck.cards.single.tags, ['verb']);
  });

  testWidgets('several tags can be applied to one card', (tester) async {
    final deck =
        await pumpDetail(tester, emptyDeck(tags: ['verb', 'common']));

    await tester.enterText(find.byType(TextField).first, 'to run');
    await tester.enterText(find.byType(TextField).at(1), 'att springa');
    await tester.tap(find.text('verb'));
    await tester.pump();
    await tester.tap(find.text('common'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(deck.cards.single.tags, ['verb', 'common']);
  });

  testWidgets('tapping a selected tag again clears it', (tester) async {
    final deck = await pumpDetail(tester, emptyDeck(tags: ['verb']));

    await tester.enterText(find.byType(TextField).first, 'red');
    await tester.enterText(find.byType(TextField).at(1), 'röd');
    await tester.tap(find.text('verb'));
    await tester.pump();
    await tester.tap(find.text('verb'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(deck.cards.single.tags, isEmpty);
  });

  testWidgets('the New tag chip adds a tag to the deck and applies it',
      (tester) async {
    final deck = await pumpDetail(tester, emptyDeck());

    await tester.tap(find.text('New tag'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Tag name'), 'noun');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(deck.tags, ['noun']);

    await tester.enterText(find.byType(TextField).first, 'house');
    await tester.enterText(find.byType(TextField).at(1), 'hus');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(deck.cards.single.tags, ['noun']);
  });
}
