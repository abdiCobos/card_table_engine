import 'dart:math';

import 'package:card_table_engine/card_table_engine.dart';
import 'package:test/test.dart';

TexasHoldemTable table(Map<String, int> stacks) =>
    TexasHoldemTable(seats: [for (final e in stacks.entries) TexasSeat(e.key, e.value)], random: Random(3));

/// Chips on the table: stacks plus the pot while a hand is running (it is paid out at the end).
int chips(TexasHoldemTable t) => t.seats.fold(0, (n, s) => n + s.chips) + (t.outcome == null ? t.pot : 0);

/// First hand: the button is the first seat. Hole cards go out in two passes starting
/// left of the button, then the five community cards.
Deck dealing(String codes) => Deck.stacked(cards(codes), random: Random(9));

void main() {
  test('three players: blinds after the button, the next one acts first', () {
    final t = table({'a': 1000, 'b': 1000, 'c': 1000})..startHand();
    expect(t.dealerIndex, 0);
    expect(t.seat('b').streetBet, 10);
    expect(t.seat('c').streetBet, 20);
    expect(t.currentSeat!.id, 'a');
    expect(t.toCall('a'), 20);
    expect(t.legalMoves('a'), [PokerMove.fold, PokerMove.call, PokerMove.raise]);
    expect(t.pot, 30);
    expect(t.seats.every((s) => s.hole.length == 2), isTrue);
    expect(t.board, isEmpty);
  });

  test('heads-up: the button posts the small blind, acts first preflop and last after', () {
    final t = table({'a': 1000, 'b': 1000})..startHand();
    expect(t.seat('a').streetBet, 10, reason: 'button = small blind');
    expect(t.currentSeat!.id, 'a');
    t.call('a');
    expect(t.currentSeat!.id, 'b', reason: 'the big blind still has the option');
    expect(t.legalMoves('b'), contains(PokerMove.check));
    t.call('b'); // check
    expect(t.street, Street.flop);
    expect(t.board, hasLength(3));
    expect(t.currentSeat!.id, 'b', reason: 'post-flop the big blind acts first heads-up');
  });

  test('everyone folds: the last player takes the pot without a showdown', () {
    final t = table({'a': 1000, 'b': 1000, 'c': 1000})..startHand();
    t.fold('a');
    t.fold('b');
    expect(t.outcome!.byFold, isTrue);
    expect(t.outcome!.winners, ['c']);
    expect(t.seat('c').chips, 1010);
    expect(t.currentSeat, isNull);
    expect(chips(t), 3000);
  });

  test('a raise reopens the action for players who already acted', () {
    final t = table({'a': 1000, 'b': 1000, 'c': 1000})..startHand();
    t.call('a');
    t.raise('b', 40); // calls 10 more, raises 40: 60 in
    expect(t.currentBet, 60);
    expect(t.currentSeat!.id, 'c');
    t.call('c');
    expect(t.currentSeat!.id, 'a', reason: 'a called 20 before the raise');
    expect(t.toCall('a'), 40);
    t.call('a');
    expect(t.street, Street.flop);
    expect(t.pot, 180);
  });

  test('checked down to the river: the best hand wins at showdown', () {
    // b, c, a get their cards in this order (two passes), then the board.
    final t = table({'a': 1000, 'b': 1000, 'c': 1000})..startHand(deck: dealing('Ah 2c 7d Ad 3c 8s  Kc Ks 4h 9d Jc'));
    t
      ..call('a')
      ..call('b')
      ..call('c');
    for (final street in [Street.flop, Street.turn, Street.river]) {
      expect(t.street, street);
      expect(t.currentSeat!.id, 'b', reason: 'first left of the button acts first');
      t
        ..call('b')
        ..call('c')
        ..call('a');
    }
    expect(t.street, Street.showdown);
    expect(t.outcome!.winners, ['b'], reason: 'aces up beat kings');
    expect(t.outcome!.hands['b']!.rank, HandRank.twoPair);
    expect(t.seat('b').chips, 1040);
    expect(chips(t), 3000);
  });

  test('a short all-in only wins the main pot; the side pot goes to the best of the rest', () {
    final t = table({'a': 100, 'b': 1000, 'c': 1000})
      // b: Q Q, c: J J, a: A A; board without help.
      ..startHand(deck: dealing('Qh Jh Ah Qd Jd Ad  2c 5s 8d 9c 3h'));
    t.allIn('a');
    expect(t.seat('a').isAllIn, isTrue);
    t
      ..call('b')
      ..call('c');
    expect(t.street, Street.flop);
    t.raise('b', 200);
    t.call('c');
    t
      ..call('b')
      ..call('c'); // turn
    t
      ..call('b')
      ..call('c'); // river
    expect(t.outcome!.byFold, isFalse);
    expect(t.outcome!.payouts['a'], 300, reason: 'main pot: 100 from each');
    expect(t.outcome!.payouts['b'], 400, reason: 'side pot: 200 from b and c');
    expect(t.outcome!.winners, ['a']);
    expect(chips(t), 2100);
  });

  test('all-in and called preflop: the board is dealt out at once', () {
    final t = table({'a': 500, 'b': 500})..startHand();
    t.allIn('a');
    t.call('b');
    expect(t.street, Street.showdown);
    expect(t.board, hasLength(5));
    expect(t.outcome, isNotNull);
    expect(chips(t), 1000);
  });

  test('blinds that put everyone all-in go straight to showdown', () {
    final t = table({'a': 5, 'b': 15})..startHand();
    expect(t.outcome, isNotNull, reason: 'nobody can bet against anybody');
    expect(chips(t), 20);
  });

  test('a short big blind all-in still makes the others call the full blind', () {
    final t = table({'a': 1000, 'b': 1000, 'c': 15})..startHand();
    expect(t.seat('c').isAllIn, isTrue);
    expect(t.toCall('a'), 20);
  });

  test('the button moves every hand and skips seats without chips', () {
    final t = table({'a': 1000, 'b': 0, 'c': 1000, 'd': 1000});
    t.startHand();
    expect(t.dealerIndex, 0);
    expect(t.seat('b').hole, isEmpty);
    t.fold(t.currentSeat!.id);
    t.fold(t.currentSeat!.id);
    t.startHand();
    expect(t.dealerIndex, 2, reason: 'b has no chips');
  });

  test('only the player in turn may act, and raises must be positive', () {
    final t = table({'a': 1000, 'b': 1000, 'c': 1000})..startHand();
    expect(() => t.call('b'), throwsStateError);
    expect(() => t.raise('a', 0), throwsArgumentError);
    expect(() => table({'a': 1000}).startHand(), throwsStateError);
  });

  test('a new hand cannot start before the current one ends', () {
    final t = table({'a': 1000, 'b': 1000})..startHand();
    t.raise(t.currentSeat!.id, 200);
    expect(() => t.startHand(), throwsStateError);
    expect(chips(t), 2000, reason: 'the pot is still on the table');
    t.fold(t.currentSeat!.id);
    t.startHand();
    expect(chips(t), 2000);
  });

  test('variants: dead money joins the main pot, hole cards can be swapped', () {
    final t = table({'a': 1000, 'b': 1000})..startHand(deck: dealing('2c Ah 3d Ad  Kc Ks 4h 9d Jc'));
    t.addDeadMoney(50);
    expect(t.pot, 80);
    t.setHoleCards('a', cards('Kh Kd'));
    t.call('a');
    t.call('b');
    for (var i = 0; i < 3; i++) {
      t
        ..call('b')
        ..call('a');
    }
    expect(t.outcome!.winners, ['a'], reason: 'four kings after the swap');
    expect(t.outcome!.payouts['a'], 90);
  });

  test('chips are never created or lost over many random hands', () {
    final rng = Random(42);
    final t = TexasHoldemTable(
      seats: [for (var i = 0; i < 6; i++) TexasSeat('p$i', 200 + rng.nextInt(800))],
      random: rng,
    );
    final total = t.seats.fold(0, (n, s) => n + s.chips);
    for (var hand = 0; hand < 400; hand++) {
      if (t.seats.where((s) => s.chips > 0).length < 2) break;
      t.startHand();
      var guard = 0;
      while (t.outcome == null) {
        final s = t.currentSeat!;
        final moves = t.legalMoves(s.id);
        final pick = moves[rng.nextInt(moves.length)];
        switch (pick) {
          case PokerMove.fold:
            if (rng.nextDouble() < 0.5) {
              t.call(s.id);
            } else {
              t.fold(s.id);
            }
          case PokerMove.check || PokerMove.call:
            t.call(s.id);
          case PokerMove.raise:
            t.raise(s.id, 10 + rng.nextInt(120));
        }
        expect(++guard, lessThan(500), reason: 'a hand must end');
      }
      expect(t.seats.fold(0, (n, s) => n + s.chips), total, reason: 'hand ${t.handNumber}');
    }
  });
}
