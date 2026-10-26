// A Texas Hold'em hand with three bots, then a Blackjack round, printed to the console.
// Run: dart run example/main.dart
import 'package:card_table_engine/card_table_engine.dart';

void main() {
  // --- Texas Hold'em ---------------------------------------------------------------------
  final table = TexasHoldemTable(seats: [TexasSeat('Ana', 1000), TexasSeat('Luis', 1000), TexasSeat('Carla', 1000)])
    ..startHand();
  final brain = PokerBotBrain(difficulty: BotDifficulty.normal);

  while (table.outcome == null) {
    final seat = table.currentSeat!;
    final decision = brain.decide(
      BotSituation(
        hole: seat.hole,
        board: table.board,
        toCall: table.toCall(seat.id),
        pot: table.pot,
        chips: seat.chips,
        opponents: table.seats.where((s) => s.inHand).length - 1,
        bigBlind: table.bigBlind,
      ),
      BotPersonality.forSeat(table.seats.indexOf(seat)),
    );
    print('${table.street.name.padRight(7)} ${seat.id}: $decision');
    switch (decision.kind) {
      case BotActionKind.fold:
        table.fold(seat.id);
      case BotActionKind.call:
        table.call(seat.id);
      case BotActionKind.raise:
        table.raise(seat.id, decision.raiseBy);
    }
  }
  print('Board: ${table.fullBoard}');
  print(table.outcome);

  // --- Blackjack -------------------------------------------------------------------------
  final bj = BlackjackTable(seats: [BlackjackSeat('Ana', 1000)])
    ..placeBet('Ana', 100)
    ..deal();
  if (bj.phase == BlackjackRoundPhase.insurance) bj.insure('Ana', take: false);
  final bot = BlackjackBotBrain(difficulty: BotDifficulty.hard);
  while (bj.phase == BlackjackRoundPhase.playerTurn) {
    final hand = bj.seat('Ana').currentHand!;
    final up = BlackjackHand.cardValue(bj.dealerUpCard!.value);
    switch (bot.decide(hand, up, canDouble: bj.canDouble('Ana'), canSplit: bj.canSplit('Ana'))) {
      case BlackjackMove.hit:
        bj.hit('Ana');
      case BlackjackMove.stand:
        bj.stand('Ana');
      case BlackjackMove.double:
        bj.double('Ana');
      case BlackjackMove.split:
        bj.split('Ana');
    }
  }
  print('Ana ${bj.seat('Ana').hands.map((h) => h.cards)} vs dealer ${bj.dealer.cards}: ${bj.results['Ana']}');
}
