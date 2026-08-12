import 'package:flutter_test/flutter_test.dart';
import 'package:sprak/models.dart';

void main() {
  Deck deckWith(List<String> tags, {List<CardItem>? cards}) => Deck(
        name: 'Test',
        targetLanguage: 'Swedish',
        nativeLanguage: 'English',
        tags: tags,
        cards: cards,
      );

  test('addTag trims and returns the canonical name', () {
    final deck = deckWith([]);
    expect(deck.addTag('  verb '), 'verb');
    expect(deck.tags, ['verb']);
  });

  test('addTag reuses an existing tag differing only in case', () {
    final deck = deckWith(['Verb']);
    expect(deck.addTag('verb'), 'Verb');
    expect(deck.tags, ['Verb']);
  });

  test('addTag ignores a blank name', () {
    final deck = deckWith([]);
    expect(deck.addTag('   '), isNull);
    expect(deck.tags, isEmpty);
  });

  test('renameTag renames on the deck and on its cards', () {
    final card = CardItem(native: 'run', target: 'springa', tags: ['verb']);
    final other = CardItem(native: 'red', target: 'röd', tags: ['adjective']);
    final deck = deckWith(['verb', 'adjective'], cards: [card, other]);

    deck.renameTag('verb', 'action word');

    expect(deck.tags, ['action word', 'adjective']);
    expect(card.tags, ['action word']);
    expect(other.tags, ['adjective']);
  });

  test('renaming onto an existing tag merges the two', () {
    final card = CardItem(native: 'run', target: 'springa', tags: ['verb']);
    final both = CardItem(
        native: 'fast', target: 'snabb', tags: ['verb', 'adjective']);
    final deck = deckWith(['verb', 'adjective'], cards: [card, both]);

    deck.renameTag('verb', 'adjective');

    expect(deck.tags, ['adjective']);
    expect(card.tags, ['adjective']);
    // The card that already had the kept tag doesn't end up with it twice.
    expect(both.tags, ['adjective']);
  });

  test('removeTag strips the tag from every card', () {
    final card = CardItem(
        native: 'run', target: 'springa', tags: ['verb', 'common']);
    final deck = deckWith(['verb', 'common'], cards: [card]);

    deck.removeTag('verb');

    expect(deck.tags, ['common']);
    expect(card.tags, ['common']);
  });

  test('tagUseCount counts the cards carrying a tag', () {
    final deck = deckWith(['verb'], cards: [
      CardItem(native: 'run', target: 'springa', tags: ['verb']),
      CardItem(native: 'walk', target: 'gå', tags: ['verb']),
      CardItem(native: 'red', target: 'röd'),
    ]);
    expect(deck.tagUseCount('verb'), 2);
    expect(deck.tagUseCount('noun'), 0);
  });

  test('tags survive a save/load round trip', () {
    final deck = deckWith(['verb', 'adjective'], cards: [
      CardItem(native: 'run', target: 'springa', tags: ['verb']),
      CardItem(native: 'red', target: 'röd'),
    ]);

    final restored = Deck.fromJson(deck.toJson());

    expect(restored.tags, ['verb', 'adjective']);
    expect(restored.cards[0].tags, ['verb']);
    expect(restored.cards[1].tags, isEmpty);
  });

  test('a tag found only on a card is restored to the deck list', () {
    final json = {
      'name': 'Test',
      'targetLanguage': 'Swedish',
      'nativeLanguage': 'English',
      'cards': [
        {'native': 'run', 'target': 'springa', 'tags': ['verb']},
      ],
    };

    final deck = Deck.fromJson(json);

    expect(deck.tags, ['verb']);
  });
}
