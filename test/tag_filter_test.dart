import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sprak/models.dart';
import 'package:sprak/screens/deck_detail_screen.dart';
import 'package:sprak/screens/quiz_screen.dart';
import 'package:sprak/storage.dart';
import 'package:sprak/theme.dart';
import 'package:sprak/widgets/tag_chips.dart';

void main() {
  CardItem card(String native, String target, List<String> tags) =>
      CardItem(native: native, target: target, tags: tags);

  Deck swedish() => Deck(
        name: 'Swedish',
        targetLanguage: 'Swedish',
        nativeLanguage: 'English',
        tags: ['verb', 'noun'],
        cards: [
          card('to run', 'springa', ['verb']),
          card('to eat', 'äta', ['verb']),
          card('house', 'hus', ['noun']),
          card('red', 'röd', []),
        ],
      );

  // "verb" also names a chip in the add panel and a pill on each card, so
  // filter taps are scoped to the filter bar.
  Finder filterChip(String label) => find.descendant(
        of: find.byType(TagFilterBar),
        matching: find.text(label),
      );

  Future<void> pumpDetail(WidgetTester tester, Deck deck) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: SprakTheme.dark(),
      home: DeckDetailScreen(store: DeckStore(), deck: deck),
    ));
    await tester.pump();
  }

  group('Deck.cardsWithAnyTag', () {
    test('no tags selects every card', () {
      final deck = swedish();
      expect(deck.cardsWithAnyTag([]), hasLength(4));
    });

    test('one tag selects only its cards', () {
      final deck = swedish();
      expect(
        deck.cardsWithAnyTag(['verb']).map((c) => c.target),
        ['springa', 'äta'],
      );
    });

    test('several tags select cards carrying any of them', () {
      final deck = swedish();
      expect(
        deck.cardsWithAnyTag(['verb', 'noun']).map((c) => c.target),
        ['springa', 'äta', 'hus'],
      );
    });

    test('a tag no card carries selects nothing', () {
      final deck = swedish();
      deck.addTag('adverb');
      expect(deck.cardsWithAnyTag(['adverb']), isEmpty);
    });
  });

  test('keepKnownTags drops tags the deck no longer defines', () {
    final deck = swedish();
    deck.removeTag('noun');
    expect(deck.keepKnownTags(['verb', 'noun']), ['verb']);
  });

  testWidgets('tapping a filter chip narrows the card list', (tester) async {
    await pumpDetail(tester, swedish());

    expect(find.text('hus'), findsOneWidget);
    expect(find.text('4 cards'), findsOneWidget);

    await tester.tap(filterChip('verb'));
    await tester.pumpAndSettle();

    expect(find.text('springa'), findsOneWidget);
    expect(find.text('äta'), findsOneWidget);
    expect(find.text('hus'), findsNothing);
    expect(find.text('röd'), findsNothing);
    expect(find.text('2 of 4 cards'), findsOneWidget);
  });

  testWidgets('a second chip widens the filter to either tag',
      (tester) async {
    await pumpDetail(tester, swedish());

    await tester.tap(filterChip('verb'));
    await tester.pumpAndSettle();
    await tester.tap(filterChip('noun'));
    await tester.pumpAndSettle();

    expect(find.text('springa'), findsOneWidget);
    expect(find.text('hus'), findsOneWidget);
    expect(find.text('röd'), findsNothing);
    expect(find.text('3 of 4 cards'), findsOneWidget);
  });

  testWidgets('the All chip clears the filter', (tester) async {
    await pumpDetail(tester, swedish());

    await tester.tap(filterChip('verb'));
    await tester.pumpAndSettle();
    await tester.tap(filterChip('All'));
    await tester.pumpAndSettle();

    expect(find.text('röd'), findsOneWidget);
    expect(find.text('4 cards'), findsOneWidget);
  });

  testWidgets('search applies on top of the tag filter', (tester) async {
    await pumpDetail(tester, swedish());

    await tester.tap(filterChip('verb'));
    await tester.pumpAndSettle();
    // The search box is the field after the two card sides and the note.
    await tester.enterText(find.byType(TextField).at(3), 'spring');
    await tester.pumpAndSettle();

    expect(find.text('springa'), findsOneWidget);
    expect(find.text('äta'), findsNothing);
    expect(find.text('1 of 4 cards'), findsOneWidget);
  });

  testWidgets('a filter matching no card says so', (tester) async {
    final deck = swedish();
    deck.addTag('adverb');
    await pumpDetail(tester, deck);

    await tester.tap(filterChip('adverb'));
    await tester.pumpAndSettle();

    expect(find.text('No cards carry those tags.'), findsOneWidget);
  });

  testWidgets('the quiz studies only the cards carrying the filtered tag',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final deck = swedish();
    await tester.pumpWidget(MaterialApp(
      theme: SprakTheme.dark(),
      home: QuizScreen(
        store: DeckStore(),
        deck: deck,
        direction: QuizDirection.front,
        tags: const ['noun'],
      ),
    ));
    await tester.pump();

    // "hus" is the only noun, so the session is that one card asked once
    // — and it is the card on screen.
    expect(find.textContaining('Group 1 of 1'), findsOneWidget);
    expect(find.textContaining('0 of 1'), findsOneWidget);
    expect(find.text('hus'), findsOneWidget);
    expect(find.text('springa'), findsNothing);
  });

  testWidgets('an unfiltered quiz still studies the whole deck',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final deck = swedish();
    await tester.pumpWidget(MaterialApp(
      theme: SprakTheme.dark(),
      home: QuizScreen(
        store: DeckStore(),
        deck: deck,
        direction: QuizDirection.front,
      ),
    ));
    await tester.pump();

    // All four cards, asked once each in this direction.
    expect(find.textContaining('0 of 4'), findsOneWidget);
  });
}
