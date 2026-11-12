import 'package:flutter_test/flutter_test.dart';
import 'package:sprak/models.dart';

Deck _deck(int n) => Deck(
      name: 'd',
      targetLanguage: 'Swedish',
      nativeLanguage: 'English',
      cards: [for (var i = 0; i < n; i++) CardItem(native: 'n$i', target: 't$i')],
    );

void main() {
  test('cards fill groups of 25 in the order they were added', () {
    final deck = _deck(113);
    expect(deck.cardGroups, [1, 2, 3, 4, 5]);
    expect(deck.cardsInGroup(1).length, 25);
    expect(deck.cardsInGroup(5).length, 13);
    expect(deck.cards[24].group, 1);
    expect(deck.cards[25].group, 2);
  });

  test('a new card joins the incomplete group', () {
    final deck = _deck(113);
    deck.addCard(CardItem(native: 'x', target: 'y'));
    expect(deck.cards.last.group, 5);
    expect(deck.cardsInGroup(5).length, 14);
  });

  test('a full last group starts a new one', () {
    final deck = _deck(50);
    deck.addCard(CardItem(native: 'x', target: 'y'));
    expect(deck.cards.last.group, 3);
  });

  test('deleting keeps groups stable and the gap is filled first', () {
    final deck = _deck(60);
    final removed = deck.cardsInGroup(1).first;
    deck.cards.remove(removed);
    expect(deck.cards.first.group, 1);
    expect(deck.cardsInGroup(2).length, 25);
    deck.addCard(CardItem(native: 'x', target: 'y'));
    expect(deck.cards.last.group, 1);
  });

  test('groups survive a save and load', () {
    final deck = _deck(30);
    final loaded = Deck.fromJson(deck.toJson());
    expect([for (final c in loaded.cards) c.group],
        [for (final c in deck.cards) c.group]);
  });

  test('legacy decks without groups are grouped on load', () {
    final json = _deck(30).toJson();
    for (final c in json['cards'] as List) {
      (c as Map).remove('group');
    }
    final loaded = Deck.fromJson(json);
    expect(loaded.cardGroups, [1, 2]);
    expect(loaded.cardsInGroup(2).length, 5);
  });

  test('tag filter can be narrowed to one group', () {
    final deck = _deck(30);
    deck.cards[0].tags.add('verb');
    deck.cards[27].tags.add('verb');
    expect(deck.cardsWithAnyTag(['verb'], group: 2), [deck.cards[27]]);
    expect(deck.cardsWithAnyTag([], group: 2).length, 5);
  });

  test('mastery counts per group', () {
    final deck = _deck(30);
    deck.cards[26].addReview(true);
    final counts = Deck.masteryCountsOf(deck.cardsInGroup(2));
    expect(counts[Mastery.learning], 1);
    expect(counts[Mastery.newCard], 4);
  });
}
