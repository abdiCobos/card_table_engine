# card_table_engine

[![pub package](https://img.shields.io/pub/v/card_table_engine.svg)](https://pub.dev/packages/card_table_engine)
[![test](https://github.com/abdiCobos/card_table_engine/actions/workflows/test.yml/badge.svg)](https://github.com/abdiCobos/card_table_engine/actions/workflows/test.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Texas Hold'em and Blackjack rules in pure Dart**, ready to put behind any UI, server or
network layer: hand evaluation, side pots, a complete no-limit betting table, a Blackjack
table with insurance and splits, and bots for both games.

No Flutter and no dependencies, so it runs anywhere Dart runs: Flutter apps (mobile,
desktop, web), Dart servers (an online table where the server enforces the rules),
command-line tools and simulations.

Extracted from [Poker Dice Dash](https://github.com/abdiCobos/pokerDiceDash), a Flutter
card game that plays these tables against bots and over the local network.

## Features

| | |
|---|---|
| **Cards** | `PlayingCard`, `Suit`, `Deck` (shuffled decks, multi-deck shoes, stacked decks for tests), `cards('As Kd 10h')` |
| **Hand evaluator** | Best 5 of any number of cards, every category up to a royal flush, the A-2-3-4-5 straight, kickers and ties |
| **Side pots** | `PotCalculator.distribute`: one pot per all-in level, folded chips stay in the pot, odd chips left of the button |
| **Texas Hold'em table** | `TexasHoldemTable`: button, blinds (heads-up rules too), four streets, raises that reopen the action, all-in run-outs, showdown and fold wins |
| **Poker bot** | `PokerBotBrain`: Monte Carlo equity, pot odds, five personalities, three difficulty levels |
| **Blackjack hand** | `BlackjackHand`: soft and hard totals, naturals, busts, split hands |
| **Blackjack table** | `BlackjackTable`: bets, deal, insurance and the dealer's peek, hit / stand / double / split, the dealer's draw and payouts |
| **Blackjack bot** | `BlackjackBotBrain`: multi-deck basic strategy (or a casual player on easy) |

Every table is synchronous: you call an action and the table is updated. Timers,
animations, networking and saving stay in your code.

## Install

```sh
dart pub add card_table_engine
```

or, in a Flutter project:

```sh
flutter pub add card_table_engine
```

```dart
import 'package:card_table_engine/card_table_engine.dart';
```

## Texas Hold'em

```dart
final table = TexasHoldemTable(
  seats: [TexasSeat('ana', 1000), TexasSeat('luis', 1000), TexasSeat('carla', 1000)],
  smallBlind: 10,
  bigBlind: 20,
)..startHand();

while (table.outcome == null) {
  final seat = table.currentSeat!;
  // Ask your player (or a bot) what to do:
  //   table.legalMoves(seat.id)  -> [fold, check or call, raise]
  //   table.toCall(seat.id)      -> chips needed to stay in
  table.call(seat.id); // or fold(id), raise(id, by), allIn(id)
}

print(table.board);            // community cards dealt so far
print(table.outcome!.winners); // main pot winners
print(table.outcome!.payouts); // chips won by each player, side pots included
print(table.outcome!.hands);   // showdown hands (rank and best five cards)
```

**Rules.** No-limit. `raise(id, by)` calls and puts `by` more on top; there is no minimum
raise. A short call is an all-in for less, and a big blind short of chips still makes the
others call the full blind. Heads-up, the button posts the small blind, acts first before the
flop and last after it. After the flop, the first player left of the button who can still
bet acts first. When nobody can bet against anybody any more, the rest of the board is dealt
and the hand goes to showdown.

**Between hands** you can change `TexasSeat.chips` (rebuys) or `sittingOut` freely;
`startHand()` moves the button and skips seats without chips. House rules can add chips that
belong to nobody to the pot with `addDeadMoney` or replace a player's hole cards with
`setHoleCards`.

### Hands and side pots on their own

```dart
final hand = HandEvaluator.evaluate(cards('As Ad'), cards('Ah Kc Kd 7s 2h'));
print(hand.rank.label); // Full house

final payouts = PotCalculator.distribute(
  contributions: {'ana': 100, 'luis': 300, 'carla': 300}, // chips each player put in
  strength: {'ana': 900, 'luis': 500, 'carla': 400},      // hand power of players still in
  seatOrder: ['luis', 'carla', 'ana'],                     // clockwise from the button
);
print(payouts); // {ana: 300, luis: 400}
```

## Blackjack

```dart
final bj = BlackjackTable(seats: [BlackjackSeat('ana', 1000)])
  ..placeBet('ana', 100)
  ..deal();

if (bj.phase == BlackjackRoundPhase.insurance) bj.insure('ana', take: false);

while (bj.phase == BlackjackRoundPhase.playerTurn) {
  final id = bj.currentSeat!.id;
  bj.stand(id); // or hit(id), double(id), split(id): check canDouble / canSplit first
}

print(bj.results['ana']); // for example BlackjackOutcome.win(100)
bj.newRound();
```

House rules live in `BlackjackRules`:

| Option | Default |
|---|---|
| `decks` | 6 |
| `reshuffleBelow` | 20 (a fresh shoe below 20 cards) |
| `blackjackReturn` | 2.5 (pays 3:2) |
| `charlieCards` | 5 (5-card Charlie wins; 0 turns it off) |
| `dealerHitsSoft17` | false (the dealer stands on every 17) |
| `offerInsurance` | true (half the bet, pays 2:1) |
| `dealerCardsFirst` | false |

Doubling is allowed on the first two cards of a hand (also after a split). A pair of identical
values can be split once; a split 21 is not a blackjack. A dealer blackjack ends the round
before anyone plays, and blackjack against blackjack is a push.

**Animating.** With `BlackjackTable(stepByStep: true)` the deal and the dealer's draw move one
card per call (`dealNextCard()`, `dealerDraw()`), so a UI can show each card arrive.
`addSeat` and `removeSeat` let players join and leave between rounds.

## Bots

```dart
final brain = PokerBotBrain(difficulty: BotDifficulty.hard);
final decision = brain.decide(
  BotSituation(
    hole: seat.hole,
    board: table.board,
    toCall: table.toCall(seat.id),
    pot: table.pot,
    chips: seat.chips,
    opponents: table.seats.where((s) => s.inHand).length - 1,
  ),
  BotPersonality.shark, // rock, shark, maniac, calculator, fish
);
// decision.kind (fold, call, raise), decision.raiseBy, decision.equity

final move = BlackjackBotBrain(difficulty: BotDifficulty.normal)
    .decide(hand, dealerUpCardValue, canDouble: true, canSplit: true); // hit, stand, double, split
```

Bots only see what a player at the table would see: their own cards and the revealed board.

See [`example/main.dart`](example/main.dart) for a full Texas Hold'em hand played by three
bots and a Blackjack round:

```sh
dart run example/main.dart
```

## Tests

```sh
dart test
```

The suite includes 400 random Texas Hold'em hands that check no chip is ever created or
lost, and 300 Blackjack rounds played by the bot.

## License

[MIT](LICENSE) © abdiCobos
