import 'package:flutter_test/flutter_test.dart';

import 'package:sprak/models.dart';
import 'package:sprak/services/llm_service.dart';
import 'package:sprak/widgets/ai_deck_edit_dialog.dart';

void main() {
  Deck deckWith(List<String> tags, List<CardItem> cards) => Deck(
        name: 'Swedish',
        targetLanguage: 'Swedish',
        nativeLanguage: 'English',
        tags: List.of(tags),
        cards: cards,
      );

  test('added cards keep the deck tags the model picked', () {
    final deck = deckWith(['verb', 'adjective'], []);
    final plan = canonicalizePlan(
      deck,
      DeckEditPlan(
        additions: [(native: 'to run', target: 'springa', tags: ['verb'])],
        removals: [],
      ),
    );
    expect(plan.additions.single.tags, ['verb']);
  });

  test('a tag the model invented is dropped from an addition', () {
    final deck = deckWith(['verb'], []);
    final plan = canonicalizePlan(
      deck,
      DeckEditPlan(
        additions: [
          (native: 'to run', target: 'springa', tags: ['verb', 'motion']),
        ],
        removals: [],
      ),
    );
    expect(plan.additions.single.tags, ['verb']);
  });

  test('model tags take the deck spelling', () {
    final deck = deckWith(['Verb'], []);
    final plan = canonicalizePlan(
      deck,
      DeckEditPlan(
        additions: [(native: 'to run', target: 'springa', tags: ['VERB'])],
        removals: [],
      ),
    );
    expect(plan.additions.single.tags, ['Verb']);
  });

  test('a retag of an existing card survives', () {
    final card = CardItem(native: 'to run', target: 'springa');
    final deck = deckWith(['verb'], [card]);
    final plan = canonicalizePlan(
      deck,
      DeckEditPlan(
        additions: [],
        removals: [],
        retags: [(target: 'springa', tags: ['verb'])],
      ),
    );
    expect(plan.retags.single.target, 'springa');
    expect(plan.retags.single.tags, ['verb']);
  });

  test('a retag naming no card in the deck is dropped', () {
    final deck = deckWith(['verb'], [CardItem(native: 'red', target: 'röd')]);
    final plan = canonicalizePlan(
      deck,
      DeckEditPlan(
        additions: [],
        removals: [],
        retags: [(target: 'springa', tags: ['verb'])],
      ),
    );
    expect(plan.retags, isEmpty);
    expect(plan.isEmpty, isTrue);
  });

  test('a retag that changes nothing is dropped', () {
    final card = CardItem(native: 'to run', target: 'springa', tags: ['verb']);
    final deck = deckWith(['verb'], [card]);
    final plan = canonicalizePlan(
      deck,
      DeckEditPlan(
        additions: [],
        removals: [],
        retags: [(target: 'springa', tags: ['verb'])],
      ),
    );
    expect(plan.retags, isEmpty);
  });

  test('a retag that only drops an invented tag is dropped too', () {
    final card = CardItem(native: 'to run', target: 'springa', tags: ['verb']);
    final deck = deckWith(['verb'], [card]);
    final plan = canonicalizePlan(
      deck,
      DeckEditPlan(
        additions: [],
        removals: [],
        retags: [
          (target: 'springa', tags: ['verb', 'motion']),
        ],
      ),
    );
    expect(plan.retags, isEmpty);
  });

  test('clearing a card\'s tags is kept as a change', () {
    final card = CardItem(native: 'to run', target: 'springa', tags: ['verb']);
    final deck = deckWith(['verb'], [card]);
    final plan = canonicalizePlan(
      deck,
      DeckEditPlan(
        additions: [],
        removals: [],
        retags: [(target: 'springa', tags: [])],
      ),
    );
    expect(plan.retags.single.tags, isEmpty);
  });
}
