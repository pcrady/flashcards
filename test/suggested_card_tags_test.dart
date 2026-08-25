import 'package:flutter_test/flutter_test.dart';

import 'package:sprak/models.dart';
import 'package:sprak/screens/deck_detail_screen.dart';

void main() {
  Deck deckWith(List<String> tags) => Deck(
        name: 'Swedish',
        targetLanguage: 'Swedish',
        nativeLanguage: 'English',
        tags: List.of(tags),
      );

  group('pendingCardTags', () {
    test('a suggestion the deck already has takes the deck spelling', () {
      final deck = deckWith(['Verb']);
      expect(pendingCardTags(deck, ['VERB'], []), ['Verb']);
    });

    test('a tag the deck has never seen is still offered', () {
      final deck = deckWith(['verb']);
      expect(pendingCardTags(deck, ['verb', 'motion'], []), [
        'verb',
        'motion',
      ]);
    });

    test('tags already on the card being added are not re-offered', () {
      final deck = deckWith(['verb']);
      expect(pendingCardTags(deck, ['verb', 'motion'], ['verb']), ['motion']);
    });

    test('blank and repeated suggestions are dropped', () {
      final deck = deckWith([]);
      expect(pendingCardTags(deck, ['noun', '  ', 'Noun'], []), ['noun']);
    });
  });

  group('applySuggestedTags', () {
    test('a new tag joins the deck list and the card', () {
      final deck = deckWith(['verb']);
      final applied = applySuggestedTags(deck, ['motion'], ['verb']);
      expect(applied, ['verb', 'motion']);
      expect(deck.tags, ['verb', 'motion']);
    });

    test('a known tag is applied without duplicating the deck list', () {
      final deck = deckWith(['Verb']);
      final applied = applySuggestedTags(deck, ['verb'], []);
      expect(applied, ['Verb']);
      expect(deck.tags, ['Verb']);
    });

    test('tags already on the card are left alone', () {
      final deck = deckWith(['verb']);
      final applied = applySuggestedTags(deck, ['verb'], ['verb', 'common']);
      expect(applied, ['verb', 'common']);
    });

    test('accepting nothing changes nothing', () {
      final deck = deckWith(['verb']);
      expect(applySuggestedTags(deck, [], ['verb']), ['verb']);
      expect(deck.tags, ['verb']);
    });

    test('a stale tag comes off the card but stays in the deck', () {
      final deck = deckWith(['noun', 'adjective']);
      final applied = applySuggestedTags(
        deck,
        ['adjective'],
        ['noun'],
        stale: ['noun'],
      );
      expect(applied, ['adjective']);
      expect(deck.tags, ['noun', 'adjective']);
    });

    test('a stale tag is matched regardless of case', () {
      final deck = deckWith(['Noun']);
      expect(
        applySuggestedTags(deck, [], ['Noun', 'common'], stale: ['noun']),
        ['common'],
      );
    });
  });

  group('staleCardTags', () {
    test('a carried-over tag the model flagged is dropped', () {
      expect(staleCardTags(['noun'], ['adjective'], ['noun']), ['noun']);
    });

    test('a flagged tag not on the card is ignored', () {
      expect(staleCardTags(['verb'], ['adjective'], ['noun']), isEmpty);
    });

    test('the card spelling wins over the model spelling', () {
      expect(staleCardTags(['NOUN'], [], ['Noun']), ['Noun']);
    });

    test('a tag the model also suggested is never removed', () {
      expect(staleCardTags(['noun'], ['Noun'], ['noun']), isEmpty);
    });

    test('blanks and repeats are dropped', () {
      expect(staleCardTags(['noun', ' ', 'noun'], [], ['noun']), ['noun']);
    });
  });
}
