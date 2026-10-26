import 'dart:math';

import 'package:card_table_engine/card_table_engine.dart';
import 'package:test/test.dart';

BlackjackHand h(List<String> v) => BlackjackHand(
  cards: [for (final x in v) PlayingCard(value: x, suit: Suit.clubs)],
  betAmount: 100,
);

void main() {
  final brain = BlackjackBotBrain(difficulty: BotDifficulty.hard, random: Random(1));
  BlackjackMove play(List<String> v, int up, {bool dbl = true, bool split = true}) =>
      brain.decide(h(v), up, canDouble: dbl, canSplit: split);

  test('hard totals', () {
    expect(play(['10', '7'], 10), BlackjackMove.stand);
    expect(play(['10', '6'], 6), BlackjackMove.stand);
    expect(play(['10', '6'], 10), BlackjackMove.hit);
    expect(play(['10', '2'], 3), BlackjackMove.hit);
    expect(play(['10', '2'], 5), BlackjackMove.stand);
    expect(play(['6', '5'], 10), BlackjackMove.double);
    expect(play(['6', '5'], 11), BlackjackMove.hit);
    expect(play(['6', '4'], 10), BlackjackMove.hit);
    expect(play(['5', '4'], 4), BlackjackMove.double);
    expect(play(['5', '3'], 6), BlackjackMove.hit);
  });

  test('soft totals', () {
    expect(play(['A', '7'], 4), BlackjackMove.double);
    expect(play(['A', '7'], 8), BlackjackMove.stand);
    expect(play(['A', '7'], 10), BlackjackMove.hit);
    expect(play(['A', '6'], 2), BlackjackMove.hit);
    expect(play(['A', '8'], 6), BlackjackMove.stand);
    expect(play(['A', '2'], 5), BlackjackMove.double);
    expect(BlackjackBotBrain.isSoft(h(['A', '6'])), isTrue);
    expect(BlackjackBotBrain.isSoft(h(['A', '6', '10'])), isFalse);
  });

  test('pairs', () {
    expect(play(['8', '8'], 10), BlackjackMove.split);
    expect(play(['A', 'A'], 6), BlackjackMove.split);
    expect(play(['K', 'K'], 6), BlackjackMove.stand);
    expect(play(['9', '9'], 7), BlackjackMove.stand);
    expect(play(['5', '5'], 6), BlackjackMove.double);
  });

  test('no double or split without chips (falls back to hit/stand)', () {
    expect(play(['6', '5'], 10, dbl: false), BlackjackMove.hit);
    expect(play(['A', '7'], 4, dbl: false), BlackjackMove.stand);
    expect(play(['8', '8'], 10, split: false), BlackjackMove.hit);
  });

  test('easy bots play like a casual player', () {
    final easy = BlackjackBotBrain(difficulty: BotDifficulty.easy);
    expect(easy.decide(h(['10', '4']), 6, canDouble: true, canSplit: true), BlackjackMove.hit);
    expect(easy.decide(h(['10', '5']), 10, canDouble: true, canSplit: true), BlackjackMove.stand);
  });
}
