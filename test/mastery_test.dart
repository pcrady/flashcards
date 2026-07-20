import 'package:flutter_test/flutter_test.dart';
import 'package:sprak/models.dart';

void main() {
  // One sitting = reviews less than 12h apart; a sitting counts toward the
  // streak only if every first attempt in it was correct.
  CardItem cardWith(List<List<bool>> sittings) {
    final card = CardItem(native: 'hello', target: 'hej');
    var at = DateTime.now()
        .subtract(Duration(days: sittings.length));
    for (final sitting in sittings) {
      for (final correct in sitting) {
        card.reviews.add(CardReview(at, correct));
        at = at.add(const Duration(minutes: 5));
      }
      at = at.add(const Duration(days: 1));
    }
    return card;
  }

  test('new card has no streak and is New', () {
    final card = CardItem(native: 'a', target: 'b');
    expect(card.streak, 0);
    expect(card.mastery, Mastery.newCard);
  });

  test('both sides correct in one sitting count as one', () {
    final card = cardWith([
      [true, true],
    ]);
    expect(card.streak, 1);
  });

  test('one wrong side keeps the whole sitting from counting', () {
    final card = cardWith([
      [true, true],
      [true, false],
    ]);
    expect(card.streak, 0);
    expect(card.mastery, Mastery.learning);
  });

  test('single-side sittings count one each', () {
    final card = cardWith([
      [true],
      [true],
      [true],
    ]);
    expect(card.streak, 3);
    expect(card.mastery, Mastery.strong);
  });

  test('two fully-correct sittings are still Learning', () {
    final card = cardWith([
      [true, true],
      [true, true],
    ]);
    expect(card.streak, 2);
    expect(card.mastery, Mastery.learning);
  });

  test('three fully-correct sittings make the card Strong', () {
    final card = cardWith([
      [true, true],
      [true, true],
      [true, true],
    ]);
    expect(card.streak, 3);
    expect(card.mastery, Mastery.strong);
  });

  test('a wrong sitting resets credit from earlier sittings', () {
    final card = cardWith([
      [true, true],
      [true, true],
      [false, true],
      [true, true],
    ]);
    expect(card.streak, 1);
  });

  test('a strong card left idle 14+ days is Fading', () {
    final card = CardItem(native: 'a', target: 'b');
    var at = DateTime.now().subtract(const Duration(days: 20));
    for (var i = 0; i < 3; i++) {
      card.reviews.add(CardReview(at, true));
      at = at.add(const Duration(days: 1));
    }
    expect(card.streak, 3);
    expect(card.mastery, Mastery.fading);
  });
}
