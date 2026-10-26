import 'dart:math';

import '../cards.dart';
import '../bot_difficulty.dart';
import 'hand_evaluator.dart';

/// Playing style. Each bot gets one so the table does not feel like clones.
class BotPersonality {
  final String name;

  /// 0 = plays almost any hand, 1 = only strong hands.
  final double tightness;

  /// 0 = calls/checks, 1 = bets and raises.
  final double aggression;

  /// Chance factor of betting with a weak hand when the spot is right.
  final double bluffing;

  const BotPersonality(this.name, {required this.tightness, required this.aggression, required this.bluffing});

  static const rock = BotPersonality('Rock', tightness: 0.85, aggression: 0.35, bluffing: 0.05);
  static const shark = BotPersonality('Shark', tightness: 0.6, aggression: 0.75, bluffing: 0.35);
  static const maniac = BotPersonality('Maniac', tightness: 0.2, aggression: 0.9, bluffing: 0.55);
  static const calculator = BotPersonality('Calculator', tightness: 0.55, aggression: 0.5, bluffing: 0.15);
  static const fish = BotPersonality('Fish', tightness: 0.15, aggression: 0.2, bluffing: 0.1);

  static const all = [shark, rock, calculator, maniac, fish];

  /// Stable personality for a seat (bots keep their style across hands).
  static BotPersonality forSeat(int seat) => all[seat % all.length];
}

enum BotActionKind { fold, call, raise }

/// What the bot does. [raiseBy] is added on top of the amount to call
/// (same meaning as `TexasHoldemTable.raise`).
class BotDecision {
  final BotActionKind kind;
  final int raiseBy;
  final double equity;

  const BotDecision(this.kind, {this.raiseBy = 0, this.equity = 0});

  @override
  String toString() => '$kind${kind == BotActionKind.raise ? ' +$raiseBy' : ''} (eq ${(equity * 100).round()}%)';
}

/// Everything the bot is allowed to know at its turn (never other players' cards).
class BotSituation {
  final List<PlayingCard> hole;
  final List<PlayingCard> board; // revealed community cards only
  final int toCall;
  final int pot;
  final int chips;
  final int bigBlind;
  final int opponents; // players still in the hand, excluding the bot

  /// Bets are rounded to this (the smallest chip on the table).
  final int chipUnit;

  const BotSituation({
    required this.hole,
    required this.board,
    required this.toCall,
    required this.pot,
    required this.chips,
    required this.opponents,
    this.bigBlind = 20,
    this.chipUnit = 10,
  });
}

/// Poker decisions from hand equity (Monte Carlo against random hands),
/// pot odds, the bot's personality and the difficulty level.
class PokerBotBrain {
  final Random _rng;
  final BotDifficulty difficulty;

  PokerBotBrain({this.difficulty = BotDifficulty.normal, Random? random}) : _rng = random ?? Random();

  static const _values = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];

  int get _iterations => switch (difficulty) {
    BotDifficulty.easy => 120,
    BotDifficulty.normal => 260,
    BotDifficulty.hard => 450,
  };

  /// How much an easy bot misjudges its hand (it "feels" stronger or weaker).
  double get _noise => switch (difficulty) {
    BotDifficulty.easy => 0.14,
    BotDifficulty.normal => 0.05,
    BotDifficulty.hard => 0.0,
  };

  /// Probability of winning the pot at showdown against [opponents] random hands.
  /// Ties count as a share of the pot.
  double estimateEquity(List<PlayingCard> hole, List<PlayingCard> board, int opponents, {int? iterations}) {
    if (hole.length < 2) return 0;
    final opp = opponents.clamp(1, 8);
    // Fewer samples in big multiway pots keep the bot's "thinking" cheap on phones.
    final its = max(60, ((iterations ?? _iterations) / (1 + 0.35 * (opp - 1))).round());
    final known = {
      for (final c in [...hole, ...board]) _key(c),
    };
    final deck = <PlayingCard>[
      for (final s in Suit.values)
        for (final v in _values)
          if (!known.contains('$v${s.index}')) PlayingCard(value: v, suit: s),
    ];
    var score = 0.0;
    for (var i = 0; i < its; i++) {
      // Partial Fisher-Yates: only shuffle the cards we need.
      final need = (5 - board.length) + 2 * opp;
      for (var k = 0; k < need; k++) {
        final j = k + _rng.nextInt(deck.length - k);
        final t = deck[k];
        deck[k] = deck[j];
        deck[j] = t;
      }
      var p = 0;
      final fullBoard = [...board, for (var k = board.length; k < 5; k++) deck[p++]];
      final mine = HandEvaluator.evaluate(hole, fullBoard).power;
      var best = true;
      var ties = 0;
      for (var o = 0; o < opp; o++) {
        final theirs = HandEvaluator.evaluate([deck[p++], deck[p++]], fullBoard).power;
        if (theirs > mine) {
          best = false;
          break;
        }
        if (theirs == mine) ties++;
      }
      if (best) score += 1 / (1 + ties);
    }
    return score / its;
  }

  static String _key(PlayingCard c) => '${c.value}${c.suit.index}';

  BotDecision decide(BotSituation s, BotPersonality p) {
    final opp = max(1, s.opponents);
    final raw = estimateEquity(s.hole, s.board, opp);
    final equity = (raw + (_rng.nextDouble() * 2 - 1) * _noise).clamp(0.0, 1.0);

    // Equity a hand needs to be "good" shrinks with more opponents (fair share = 1/(n+1)).
    final fair = 1 / (opp + 1);
    final strong = fair + (1 - fair) * (0.42 + 0.18 * p.tightness);
    final playable = fair * (0.75 + 0.7 * p.tightness);

    final potAfterCall = s.pot + s.toCall;
    final potOdds = s.toCall <= 0 ? 0.0 : s.toCall / potAfterCall;
    final canRaise = s.chips > s.toCall;
    final roll = _rng.nextDouble();

    BotDecision raise(double potFraction) {
      if (!canRaise) return BotDecision(BotActionKind.call, equity: equity);
      final maxBy = s.chips - s.toCall;
      var by = max(s.bigBlind, (potAfterCall * potFraction).round());
      // Round to the table's chip unit so bets look like real bets.
      final unit = max(1, s.chipUnit);
      by = (by / unit).round() * unit;
      // Shove when the bet would commit most of the stack anyway, or with a monster.
      if (by >= maxBy * 0.6 || (equity > 0.85 && maxBy <= potAfterCall)) by = maxBy;
      return BotDecision(BotActionKind.raise, raiseBy: by.clamp(1, maxBy), equity: equity);
    }

    final sizing = 0.45 + 0.45 * p.aggression + (equity > strong ? 0.15 : 0);
    final bluffSpot = s.board.isNotEmpty && opp <= 2;
    final bluffChance = p.bluffing * (bluffSpot ? 0.5 : 0.15) * (difficulty == BotDifficulty.easy ? 0.5 : 1);

    if (s.toCall <= 0) {
      // Nobody bet: bet strong hands, sometimes bluff, otherwise check.
      if (equity >= strong && roll < 0.45 + 0.5 * p.aggression) return raise(sizing);
      if (equity < playable && roll < bluffChance) return raise(0.5);
      return BotDecision(BotActionKind.call, equity: equity); // check
    }

    // Facing a bet.
    final cheap = s.toCall <= max(s.bigBlind, (s.pot * 0.08).round());
    if (equity >= strong + 0.1 && roll < 0.35 + 0.55 * p.aggression) return raise(sizing);
    final margin = 0.02 + 0.08 * p.tightness - (difficulty == BotDifficulty.easy ? 0.05 : 0);
    if (equity >= potOdds + margin || (cheap && equity >= playable * 0.6)) {
      return BotDecision(BotActionKind.call, equity: equity);
    }
    if (roll < bluffChance * 0.6) return raise(0.6); // semi-bluff / steal
    // Easy bots call too often ("calling stations").
    if (difficulty == BotDifficulty.easy && roll < 0.2) return BotDecision(BotActionKind.call, equity: equity);
    return BotDecision(BotActionKind.fold, equity: equity);
  }
}
