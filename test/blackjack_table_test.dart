import 'dart:math';

import 'package:card_table_engine/card_table_engine.dart';
import 'package:test/test.dart';

/// One player 'p' with 1000 chips. Deal order: p, dealer, p, dealer, then hits.
BlackjackTable table(String shoe, {BlackjackRules rules = const BlackjackRules(), int bet = 100}) {
  final t = BlackjackTable(seats: [BlackjackSeat('p', 1000)], rules: rules, random: Random(5))
    ..useShoe(Deck.stacked(cards(shoe), decks: 6, random: Random(8)))
    ..placeBet('p', bet);
  return t;
}

void main() {
  test('a natural pays 3:2', () {
    final t = table('As 9c Kd 7h')..deal();
    expect(t.phase, BlackjackRoundPhase.settled);
    expect(t.results['p']!.outcome, BlackjackOutcome.blackjack);
    expect(t.results['p']!.returned, 250);
    expect(t.seat('p').chips, 1150);
  });

  test('a dealer natural ends the round before anyone plays; natural against natural pushes', () {
    final lose = table('9s Kc 7d Ah')..deal(); // ten up: no insurance, the dealer peeks
    expect(lose.phase, BlackjackRoundPhase.settled);
    expect(lose.results['p']!.outcome, BlackjackOutcome.lose);
    expect(lose.seat('p').hands.first.isFinished, isTrue, reason: 'every hand is closed when the round ends');
    expect(lose.seat('p').chips, 900);

    final push = table('As Kc Kd Ah', rules: const BlackjackRules(offerInsurance: false))..deal();
    expect(push.results['p']!.outcome, BlackjackOutcome.push);
    expect(push.seat('p').chips, 1000);
  });

  test('insurance: offered on an ace, pays 2:1 against a dealer natural', () {
    final ins = table('9s Ac 7d Kh')..deal();
    expect(ins.phase, BlackjackRoundPhase.insurance);
    expect(ins.canInsure(ins.seat('p')), isTrue);
    ins.insure('p', take: true);
    expect(ins.phase, BlackjackRoundPhase.settled);
    expect(ins.results['p']!.outcome, BlackjackOutcome.insured);
    expect(ins.results['p']!.net, 0, reason: 'lost 100, insurance 50 paid 2:1');
    expect(ins.seat('p').chips, 1000);
  });

  test('declined insurance and no dealer natural: the hand goes on', () {
    final t = table('9s Ac 7d 6h')..deal();
    expect(t.phase, BlackjackRoundPhase.insurance);
    t.closeInsurance();
    expect(t.phase, BlackjackRoundPhase.playerTurn);
    expect(t.currentSeat!.id, 'p');
  });

  test('hit, stand and the dealer standing on 17', () {
    final t = table('10s 10c 5d 7h 4c')..deal();
    expect(t.dealer.handValue, 17);
    t.hit('p'); // 10+5+4 = 19
    expect(t.seat('p').hands.first.handValue, 19);
    t.stand('p');
    expect(t.phase, BlackjackRoundPhase.settled);
    expect(t.dealer.cards, hasLength(2), reason: 'stands on 17');
    expect(t.results['p']!.outcome, BlackjackOutcome.win);
    expect(t.seat('p').chips, 1100);
  });

  test('soft 17: stands by default, hits with dealerHitsSoft17', () {
    final stand = table('10s Ac 9d 6h')..deal();
    stand.closeInsurance();
    stand.stand('p');
    expect(stand.dealer.cards, hasLength(2));

    final hit = table('10s Ac 9d 6h 2c', rules: const BlackjackRules(dealerHitsSoft17: true))..deal();
    hit.closeInsurance();
    hit.stand('p');
    expect(hit.dealer.cards, hasLength(3));
    expect(hit.dealer.handValue, 19);
  });

  test('double: twice the bet, exactly one card, then stands', () {
    final t = table('6s 10c 5d 7h 9c')..deal();
    expect(t.canDouble('p'), isTrue);
    t.double('p');
    final h = t.seat('p').hands.first;
    expect(h.cards, hasLength(3));
    expect(h.betAmount, 200);
    expect(t.results['p']!.outcome, BlackjackOutcome.win, reason: '20 against 17');
    expect(t.seat('p').chips, 1200);
  });

  test('split: two hands with the same bet, a split 21 is not a blackjack', () {
    final t = table('8s 10c 8d 7h As 3c 10h')..deal();
    expect(t.canSplit('p'), isTrue);
    t.split('p');
    final hands = t.seat('p').hands;
    expect(hands, hasLength(2));
    expect(hands.map((h) => h.betAmount), [100, 100]);
    expect(hands.first.cards.map((c) => c.code), ['8s', 'As']);
    t.stand('p'); // 19
    t.hit('p'); // 8+3+10 = 21
    expect(t.phase, BlackjackRoundPhase.settled);
    expect(t.results['p']!.net, 200);
    expect(t.canSplit('p'), isFalse);

    final ace21 = table('As 10c Ad 7h Kh 2c')..deal();
    ace21.closeInsurance();
    ace21.split('p');
    expect(ace21.seat('p').hands.first.isBlackjack, isFalse);
  });

  test('a 5-card Charlie wins even against 20', () {
    final t = table('2s 10c 3d Kh 2c 2h 3c')..deal();
    t
      ..hit('p')
      ..hit('p')
      ..hit('p');
    expect(t.seat('p').hands.first.isCharlie, isTrue);
    expect(t.results['p']!.outcome, BlackjackOutcome.charlie);
    expect(t.seat('p').chips, 1100);
  });

  test('when every hand busted the dealer does not draw', () {
    final t = table('10s 6c 6d 5h Kc')..deal();
    t.hit('p');
    expect(t.results['p']!.outcome, BlackjackOutcome.bust);
    expect(t.dealer.cards, hasLength(2));
  });

  test('turn order and errors', () {
    final t = BlackjackTable(seats: [BlackjackSeat('a', 500), BlackjackSeat('b', 500)], random: Random(3));
    expect(() => t.deal(), throwsStateError);
    expect(() => t.placeBet('a', 600), throwsArgumentError);
    t.placeBet('a', 50);
    t.placeBet('b', 50);
    expect(() => t.placeBet('b', 50), throwsStateError);
    t.deal();
    if (t.phase == BlackjackRoundPhase.insurance) t.closeInsurance();
    if (t.phase == BlackjackRoundPhase.playerTurn) {
      final other = t.currentSeat!.id == 'a' ? 'b' : 'a';
      expect(() => t.stand(other), throwsStateError);
    }
  });

  test('a fresh shoe comes in when it runs low; bots can play hundreds of rounds', () {
    final rng = Random(11);
    final t = BlackjackTable(
      seats: [for (var i = 0; i < 4; i++) BlackjackSeat('s$i', 1000)],
      rules: const BlackjackRules(decks: 1, reshuffleBelow: 15),
      random: rng,
    );
    final bot = BlackjackBotBrain(difficulty: BotDifficulty.hard, random: rng);
    for (var round = 0; round < 300; round++) {
      for (final s in t.seats) {
        if (s.chips < 10) s.chips = 1000;
        t.placeBet(s.id, 10 + rng.nextInt(min(90, s.chips - 9)));
      }
      t.deal();
      if (t.phase == BlackjackRoundPhase.insurance) t.closeInsurance();
      var guard = 0;
      while (t.phase == BlackjackRoundPhase.playerTurn) {
        final s = t.currentSeat!;
        final up = BlackjackHand.cardValue(t.dealerUpCard!.value);
        switch (bot.decide(s.currentHand!, up, canDouble: t.canDouble(s.id), canSplit: t.canSplit(s.id))) {
          case BlackjackMove.hit:
            t.hit(s.id);
          case BlackjackMove.stand:
            t.stand(s.id);
          case BlackjackMove.double:
            t.double(s.id);
          case BlackjackMove.split:
            t.split(s.id);
        }
        expect(++guard, lessThan(100));
      }
      expect(t.phase, BlackjackRoundPhase.settled);
      for (final r in t.results.values) {
        expect(r.returned, greaterThanOrEqualTo(0));
      }
      t.newRound();
    }
  });

  test('step by step: one card per call, so a UI can animate the deal and the dealer', () {
    final t = BlackjackTable(seats: [BlackjackSeat('p', 1000)], stepByStep: true, random: Random(1))
      ..useShoe(Deck.stacked(cards('10s 6c 9d 5h 2c 3d'), decks: 6, random: Random(2)))
      ..placeBet('p', 100)
      ..deal();
    expect(t.phase, BlackjackRoundPhase.dealing);
    expect(t.dealNextCard()!.code, '10s');
    expect(t.seat('p').hands.first.cards, hasLength(1));
    t
      ..dealNextCard()
      ..dealNextCard()
      ..dealNextCard();
    expect(t.phase, BlackjackRoundPhase.playerTurn);
    expect(t.dealNextCard(), isNull);
    t.stand('p'); // 19 against 11
    expect(t.phase, BlackjackRoundPhase.dealerTurn);
    expect(t.dealerDraw()!.code, '2c'); // 13
    expect(t.dealerDraw()!.code, '3d'); // 16
    expect(t.dealerDraw(), isNotNull); // still below 17
    while (t.dealerDraw() != null) {}
    expect(t.phase, BlackjackRoundPhase.settled);
  });

  test('dealerCardsFirst deals the dealer first in each pass', () {
    final t = table('7d 10s 6h 9c', rules: const BlackjackRules(dealerCardsFirst: true))..deal();
    expect(t.dealer.cards.map((c) => c.code), ['7d', '6h']);
    expect(t.seat('p').hands.first.cards.map((c) => c.code), ['10s', '9c']);
  });

  test('seats can join any time and leave when they have nothing on the table', () {
    final t = BlackjackTable(seats: [BlackjackSeat('a', 500), BlackjackSeat('b', 500)], random: Random(4))
      ..useShoe(Deck.stacked(cards('10s 10c 9d 7h 6c'), decks: 6, random: Random(5)))
      ..placeBet('a', 50)
      ..deal();
    t.addSeat(BlackjackSeat('c', 500));
    t.removeSeat('b'); // no bet this round
    expect(t.seats.map((s) => s.id), ['a', 'c']);
    expect(() => t.removeSeat('a'), throwsStateError);
    expect(t.currentSeat!.id, 'a');
  });

  test('counts fresh shoes', () {
    final t = BlackjackTable(
      seats: [BlackjackSeat('p', 100000)],
      rules: const BlackjackRules(decks: 1, reshuffleBelow: 30),
      random: Random(6),
    );
    for (var i = 0; i < 20; i++) {
      t.placeBet('p', 10);
      t.deal();
      if (t.phase == BlackjackRoundPhase.insurance) t.closeInsurance();
      while (t.phase == BlackjackRoundPhase.playerTurn) {
        t.stand(t.currentSeat!.id);
      }
      t.newRound();
    }
    expect(t.shuffles, greaterThan(0));
  });
}
