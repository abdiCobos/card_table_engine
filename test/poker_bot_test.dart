import 'dart:math';

import 'package:card_table_engine/card_table_engine.dart';
import 'package:test/test.dart';

PlayingCard c(String s) {
  final value = s.substring(0, s.length - 1);
  final suit = switch (s[s.length - 1]) {
    'h' => Suit.hearts,
    'd' => Suit.diamonds,
    'c' => Suit.clubs,
    _ => Suit.spades,
  };
  return PlayingCard(value: value, suit: suit);
}

List<PlayingCard> cards(String s) => s.split(' ').map(c).toList();

void main() {
  group('equity', () {
    final brain = PokerBotBrain(random: Random(7));

    test('pocket aces are a big favourite heads-up', () {
      final e = brain.estimateEquity(cards('As Ah'), const [], 1, iterations: 1500);
      expect(e, inInclusiveRange(0.78, 0.92));
    });

    test('7-2 offsuit is an underdog', () {
      final e = brain.estimateEquity(cards('7d 2c'), const [], 1, iterations: 1500);
      expect(e, inInclusiveRange(0.25, 0.42));
    });

    test('a made royal flush always wins', () {
      final e = brain.estimateEquity(cards('As Ks'), cards('Qs Js 10s 2d 3c'), 3, iterations: 300);
      expect(e, 1.0);
    });

    test('equity drops against more opponents', () {
      final one = brain.estimateEquity(cards('Kd Qd'), const [], 1, iterations: 1200);
      final five = brain.estimateEquity(cards('Kd Qd'), const [], 5, iterations: 1200);
      expect(five, lessThan(one - 0.2));
    });
  });

  group('decisions', () {
    BotSituation spot(String hole, {String board = '', int toCall = 20, int pot = 30, int chips = 1000, int opp = 3}) =>
        BotSituation(
          hole: cards(hole),
          board: board.isEmpty ? const [] : cards(board),
          toCall: toCall,
          pot: pot,
          chips: chips,
          opponents: opp,
        );

    Map<BotActionKind, int> sample(BotSituation s, BotPersonality p, {BotDifficulty d = BotDifficulty.normal}) {
      final counts = {for (final k in BotActionKind.values) k: 0};
      for (var seed = 0; seed < 60; seed++) {
        final dec = PokerBotBrain(difficulty: d, random: Random(seed)).decide(s, p);
        counts[dec.kind] = counts[dec.kind]! + 1;
      }
      return counts;
    }

    test('strong hands are never folded to a small bet', () {
      for (final p in BotPersonality.all) {
        final r = sample(spot('As Ah'), p);
        expect(r[BotActionKind.fold], 0, reason: '${p.name} folded aces');
      }
    });

    test('trash facing a huge bet is folded most of the time', () {
      final r = sample(spot('7d 2c', board: 'Kh Qs 9c', toCall: 600, pot: 300, opp: 2), BotPersonality.calculator);
      expect(r[BotActionKind.fold]!, greaterThan(45));
    });

    test('a monster on the river bets or raises', () {
      final r = sample(spot('Ah Kh', board: 'Qh Jh 10h 2c 3d', toCall: 0, pot: 200, opp: 2), BotPersonality.shark);
      expect(r[BotActionKind.raise]!, greaterThan(40));
    });

    test('bots check rather than fold when nobody bet', () {
      final r = sample(spot('7d 2c', board: 'Kh Qs 9c', toCall: 0, pot: 100), BotPersonality.rock);
      expect(r[BotActionKind.fold], 0);
    });

    test('raises never exceed the stack and respect the big blind', () {
      for (var seed = 0; seed < 200; seed++) {
        final chips = 50 + seed * 7;
        final s = spot('As Kd', board: 'Ah Kc 4s', toCall: seed % 3 * 20, pot: 120, chips: chips);
        final dec = PokerBotBrain(
          difficulty: BotDifficulty.hard,
          random: Random(seed),
        ).decide(s, BotPersonality.maniac);
        if (dec.kind == BotActionKind.raise) {
          expect(dec.raiseBy, greaterThan(0));
          expect(s.toCall + dec.raiseBy, lessThanOrEqualTo(chips));
        }
      }
    });

    test('easy bots call more loosely than hard bots', () {
      final s = spot('9d 6c', board: 'Kh Qs 2c', toCall: 120, pot: 160, opp: 2);
      final easy = sample(s, BotPersonality.calculator, d: BotDifficulty.easy);
      final hard = sample(s, BotPersonality.calculator, d: BotDifficulty.hard);
      expect(easy[BotActionKind.fold]!, lessThan(hard[BotActionKind.fold]!));
    });

    test('a decision is fast enough for a phone (7 opponents, hard)', () {
      final sw = Stopwatch()..start();
      PokerBotBrain(
        difficulty: BotDifficulty.hard,
        random: Random(1),
      ).decide(spot('Jc 10c', opp: 7), BotPersonality.shark);
      expect(sw.elapsedMilliseconds, lessThan(400));
    });
  });
}
