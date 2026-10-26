import 'dart:math';

import 'package:card_table_engine/card_table_engine.dart';
import 'package:test/test.dart';

HandResult eval(String hole, String board) => HandEvaluator.evaluate(cards(hole), cards(board));

void main() {
  group('cards', () {
    test('parse and print', () {
      expect(PlayingCard.parse('As'), PlayingCard(value: 'A', suit: Suit.spades));
      expect(PlayingCard.parse('10h').code, '10h');
      expect(PlayingCard.parse('Td'), PlayingCard(value: '10', suit: Suit.diamonds));
      expect(PlayingCard.parse('qc').rank, 12);
      expect(() => PlayingCard.parse('1x'), throwsFormatException);
    });

    test('json round trip keeps the same shape', () {
      final c = PlayingCard.parse('Kd');
      expect(c.toJson(), {'value': 'K', 'suit': 'diamonds'});
      expect(PlayingCard.fromJson(c.toJson()), c);
    });

    test('a deck has 52 different cards, a shoe several decks', () {
      expect(Deck.shuffled(random: Random(1)).cards.toSet(), hasLength(52));
      expect(Deck.shuffled(decks: 6).length, 312);
    });

    test('a stacked deck deals the chosen cards first and never twice', () {
      final d = Deck.stacked(cards('As Ks Qs'));
      expect([d.draw(), d.draw(), d.draw()], cards('As Ks Qs'));
      expect(d.length, 49);
      expect(d.cards, isNot(contains(PlayingCard.parse('As'))));
    });
  });

  group('hand evaluator', () {
    test('ranks every category', () {
      expect(eval('As Ks', 'Qs Js 10s 2d 3c').rank, HandRank.royalFlush);
      expect(eval('9s Ks', 'Qs Js 10s 2d 3c').rank, HandRank.straightFlush);
      expect(eval('9s 9h', '9d 9c 2s 3d 4c').rank, HandRank.fourOfAKind);
      expect(eval('9s 9h', '9d 2c 2s 3d 4c').rank, HandRank.fullHouse);
      expect(eval('As 3s', 'Qs 8s 2s 3d 4c').rank, HandRank.flush);
      expect(eval('6h 7d', '8s 9c 10d 2c Kh').rank, HandRank.straight);
      expect(eval('9s 9h', '9d 2c Js 3d 4c').rank, HandRank.threeOfAKind);
      expect(eval('9s 9h', 'Jd 2c Js 3d 4c').rank, HandRank.twoPair);
      expect(eval('9s 9h', 'Kd 2c Js 3d 4c').rank, HandRank.onePair);
      expect(eval('9s 8h', 'Kd 2c Js 3d 4c').rank, HandRank.highCard);
    });

    test('A-2-3-4-5 is the lowest straight', () {
      final wheel = eval('As 2d', '3c 4h 5s Kd Qc');
      final six = eval('6s 2d', '3c 4h 5s Kd Qc');
      expect(wheel.rank, HandRank.straight);
      expect(six.power, greaterThan(wheel.power));
    });

    test('kickers decide, equal hands tie', () {
      expect(eval('Ah Kd', 'As 7c 5d 3h 2s').power, greaterThan(eval('Ac Qd', 'As 7c 5d 3h 2s').power));
      expect(
        eval('Ah 4d', 'Ks Kc Qd Qh Js').power,
        eval('Ac 3d', 'Ks Kc Qd Qh Js').power,
        reason: 'same two pair, same ace kicker',
      );
      expect(
        eval('2h 3d', 'As Ks Qd Jh 9c').power,
        eval('4h 5d', 'As Ks Qd Jh 9c').power,
        reason: 'both play the board',
      );
    });

    test('english labels', () {
      expect(eval('9s 9h', '9d 2c 2s 3d 4c').rank.label, 'Full house');
    });
  });
}
