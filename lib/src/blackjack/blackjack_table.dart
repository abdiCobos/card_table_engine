import 'dart:math';

import '../cards.dart';
import 'blackjack_hand.dart';

/// House rules of a [BlackjackTable].
class BlackjackRules {
  /// Decks in the shoe.
  final int decks;

  /// A fresh shoe is shuffled when fewer cards than this remain at a draw.
  final int reshuffleBelow;

  /// Total returned for a natural blackjack, per chip bet (2.5 = pays 3:2).
  final double blackjackReturn;

  /// Cards without busting that win automatically (0 turns the rule off).
  final int charlieCards;

  /// The dealer hits a soft 17 (false: stands on every 17).
  final bool dealerHitsSoft17;

  /// Offer insurance when the dealer shows an ace.
  final bool offerInsurance;

  /// Each pass of the deal gives the dealer a card before the players (some home games).
  final bool dealerCardsFirst;

  const BlackjackRules({
    this.decks = 6,
    this.reshuffleBelow = 20,
    this.blackjackReturn = 2.5,
    this.charlieCards = 5,
    this.dealerHitsSoft17 = false,
    this.offerInsurance = true,
    this.dealerCardsFirst = false,
  });
}

enum BlackjackRoundPhase { betting, dealing, insurance, playerTurn, dealerTurn, settled }

enum BlackjackOutcome { blackjack, charlie, win, push, lose, bust, insured }

class BlackjackSeat {
  final String id;
  int chips;
  List<BlackjackHand> hands = [];
  int handIndex = 0;
  int insurance = 0;
  bool insuranceAnswered = false;

  BlackjackSeat(this.id, this.chips);

  int get totalBet => hands.fold(0, (n, h) => n + h.betAmount);
  bool get isPlaying => hands.isNotEmpty;
  BlackjackHand? get currentHand => handIndex < hands.length ? hands[handIndex] : null;
  bool get isDone => hands.every((h) => h.isFinished);

  @override
  String toString() => '$id($chips, ${hands.map((h) => '${h.cards}=${h.handValue}').join(' | ')})';
}

/// Result of one seat when the round is settled.
class SeatResult {
  final BlackjackOutcome outcome;

  /// Chips returned (bets and insurance included).
  final int returned;

  /// [returned] minus everything the seat put in this round.
  final int net;

  const SeatResult(this.outcome, this.returned, this.net);

  @override
  String toString() => '$outcome($net)';
}

/// Blackjack against the dealer: bets, the deal, insurance and the dealer's peek, then
/// hit / stand / double / split for each seat in order, the dealer's draw and the payouts.
/// Synchronous and UI-free. With [stepByStep] the deal and the dealer's draw advance one
/// card per call ([dealNextCard], [dealerDraw]) so a UI can animate them.
///
/// Rules (see [BlackjackRules]): double on the first two cards only (one more card), one
/// split of identical values (each hand gets one card; double after split allowed; a split
/// 21 is not a blackjack), a dealer natural ends the round at once (player natural pushes),
/// insurance costs half the bet and pays 2:1, an N-card Charlie wins even against 21.
class BlackjackTable {
  final List<BlackjackSeat> seats;
  final BlackjackRules rules;
  final Random _random;
  late Deck shoe;

  /// Deal and dealer draws advance one card per call instead of all at once.
  final bool stepByStep;

  BlackjackTable({required this.seats, this.rules = const BlackjackRules(), this.stepByStep = false, Random? random})
    : _random = random ?? Random() {
    shoe = Deck.shuffled(decks: rules.decks, random: _random);
  }

  BlackjackRoundPhase phase = BlackjackRoundPhase.betting;
  BlackjackHand dealer = BlackjackHand();

  /// Seat whose turn it is (playerTurn), -1 otherwise.
  int currentIndex = -1;

  /// Fresh shoes shuffled in so far (a UI can say "new shoe").
  int shuffles = 0;

  final List<BlackjackSeat?> _dealQueue = []; // null = the dealer
  Map<String, SeatResult> results = const {};

  BlackjackSeat seat(String id) => seats.firstWhere((s) => s.id == id);
  BlackjackSeat? get currentSeat => currentIndex < 0 ? null : seats[currentIndex];

  /// The dealer's face-up card.
  PlayingCard? get dealerUpCard => dealer.cards.isEmpty ? null : dealer.cards.first;

  /// Replaces the shoe (tests, replays).
  void useShoe(Deck deck) => shoe = deck;

  PlayingCard _draw() {
    if (shoe.length < rules.reshuffleBelow) {
      shoe = Deck.shuffled(decks: rules.decks, random: _random);
      shuffles++;
    }
    return shoe.draw();
  }

  // --- Betting and the deal -------------------------------------------------------------------

  /// Takes [amount] from the seat's chips (one bet per seat and round).
  void placeBet(String id, int amount) {
    if (phase != BlackjackRoundPhase.betting) throw StateError('Bets are closed');
    final s = seat(id);
    if (s.hands.isNotEmpty) throw StateError('$id already bet');
    if (amount <= 0 || amount > s.chips) throw ArgumentError.value(amount, 'amount');
    s.chips -= amount;
    s.hands = [BlackjackHand(betAmount: amount)];
  }

  /// Deals two cards to every seat with a bet and to the dealer, then offers insurance or
  /// lets the dealer peek. With [stepByStep], call [dealNextCard] until it returns null.
  void deal() {
    if (phase != BlackjackRoundPhase.betting) throw StateError('Not betting');
    final players = seats.where((s) => s.isPlaying).toList();
    if (players.isEmpty) throw StateError('Nobody bet');
    dealer = BlackjackHand();
    _dealQueue.clear();
    for (var pass = 0; pass < 2; pass++) {
      if (rules.dealerCardsFirst) _dealQueue.add(null);
      _dealQueue.addAll(players);
      if (!rules.dealerCardsFirst) _dealQueue.add(null);
    }
    phase = BlackjackRoundPhase.dealing;
    if (!stepByStep) {
      while (dealNextCard() != null) {}
    }
  }

  /// Deals the next card of the deal; null when the deal is over (the round moved on).
  PlayingCard? dealNextCard() {
    if (phase != BlackjackRoundPhase.dealing || _dealQueue.isEmpty) return null;
    final to = _dealQueue.removeAt(0);
    final card = _draw();
    (to == null ? dealer : to.hands.first).cards.add(card);
    if (_dealQueue.isEmpty) _afterDeal();
    return card;
  }

  void _afterDeal() {
    final players = seats.where((s) => s.isPlaying).toList();
    final insurable = rules.offerInsurance && dealer.cards.first.value == 'A';
    if (insurable && players.any(canInsure)) {
      phase = BlackjackRoundPhase.insurance;
      for (final s in players) {
        s.insuranceAnswered = !canInsure(s);
      }
      return;
    }
    _peek();
  }

  // --- Insurance ------------------------------------------------------------------------------

  static int insuranceCost(BlackjackSeat s) => s.totalBet ~/ 2;

  bool canInsure(BlackjackSeat s) =>
      s.isPlaying &&
      !s.hands.first.isNatural &&
      insuranceCost(s) >= 1 &&
      s.chips >= insuranceCost(s) &&
      (phase != BlackjackRoundPhase.insurance || !s.insuranceAnswered);

  /// Answers the insurance offer. When everyone answered, the dealer peeks.
  void insure(String id, {required bool take}) {
    if (phase != BlackjackRoundPhase.insurance) throw StateError('No insurance offered');
    final s = seat(id);
    if (s.insuranceAnswered) throw StateError('$id already answered');
    if (take) {
      final cost = insuranceCost(s);
      s.chips -= cost;
      s.insurance = cost;
    }
    s.insuranceAnswered = true;
    if (seats.where((x) => x.isPlaying).every((x) => x.insuranceAnswered)) _peek();
  }

  /// Everyone who has not answered declines (a timeout).
  void closeInsurance() {
    if (phase != BlackjackRoundPhase.insurance) return;
    for (final s in seats.where((x) => x.isPlaying && !x.insuranceAnswered)) {
      s.insuranceAnswered = true;
    }
    _peek();
  }

  void _peek() {
    if (dealer.isNatural) {
      _settle();
      return;
    }
    phase = BlackjackRoundPhase.playerTurn;
    currentIndex = -1;
    _nextSeat();
  }

  // --- Playing --------------------------------------------------------------------------------

  bool canDouble(String id) {
    final s = seat(id);
    final h = s.currentHand;
    return h != null && h.cards.length == 2 && s.chips >= h.betAmount;
  }

  bool canSplit(String id) {
    final s = seat(id);
    final h = s.currentHand;
    return h != null && s.hands.length == 1 && h.canSplit && s.chips >= h.betAmount;
  }

  void hit(String id) {
    final s = _turnOf(id);
    final h = s.currentHand!;
    h.cards.add(_draw());
    _review(h);
    _afterMove(s);
  }

  void stand(String id) {
    final s = _turnOf(id);
    s.currentHand!.isStanding = true;
    _afterMove(s);
  }

  /// Doubles the bet, takes exactly one card and stands.
  void double(String id) {
    final s = _turnOf(id);
    if (!canDouble(id)) throw StateError('$id cannot double');
    final h = s.currentHand!;
    s.chips -= h.betAmount;
    final doubled = h.copyWith(betAmount: h.betAmount * 2, isDoubledDown: true, cards: [...h.cards, _draw()]);
    _review(doubled);
    if (!doubled.isBusted) doubled.isStanding = true;
    s.hands[s.handIndex] = doubled;
    _afterMove(s);
  }

  /// Splits a pair into two hands with the same bet; each one gets a second card.
  void split(String id) {
    final s = _turnOf(id);
    if (!canSplit(id)) throw StateError('$id cannot split');
    final h = s.currentHand!;
    s.chips -= h.betAmount;
    final first = BlackjackHand(betAmount: h.betAmount, isSplit: true, cards: [h.cards[0], _draw()]);
    final second = BlackjackHand(betAmount: h.betAmount, isSplit: true, cards: [h.cards[1], _draw()]);
    _review(first);
    _review(second);
    s
      ..hands = [first, second]
      ..handIndex = 0;
    _afterMove(s);
  }

  BlackjackSeat _turnOf(String id) {
    if (phase != BlackjackRoundPhase.playerTurn) throw StateError('Not the players\' turn');
    final s = currentSeat;
    if (s == null || s.id != id) throw StateError('It is not the turn of $id');
    return s;
  }

  void _review(BlackjackHand h) {
    if (h.handValue > 21) {
      h.isBusted = true;
    } else if (rules.charlieCards > 0 && h.cards.length >= rules.charlieCards) {
      h.isCharlie = true;
    } else if (h.handValue == 21) {
      h.isStanding = true;
    }
  }

  void _afterMove(BlackjackSeat s) {
    _skipFinished(s);
    if (s.handIndex >= s.hands.length) _nextSeat();
  }

  void _skipFinished(BlackjackSeat s) {
    while (s.handIndex < s.hands.length && s.hands[s.handIndex].isFinished) {
      s.handIndex++;
    }
  }

  void _nextSeat() {
    for (var i = currentIndex + 1; i < seats.length; i++) {
      final s = seats[i];
      if (!s.isPlaying) continue;
      s.handIndex = 0;
      for (final h in s.hands) {
        _review(h);
      }
      _skipFinished(s);
      if (s.handIndex < s.hands.length) {
        currentIndex = i;
        return;
      }
    }
    currentIndex = -1;
    _dealerPlays();
  }

  void _dealerPlays() {
    phase = BlackjackRoundPhase.dealerTurn;
    if (!stepByStep) {
      while (dealerDraw() != null) {}
    }
  }

  bool get _dealerMustDraw =>
      dealer.handValue < 17 || (rules.dealerHitsSoft17 && dealer.handValue == 17 && dealer.isSoft);

  /// Dealer's turn: draws one card, or settles the round and returns null when done.
  /// The dealer only draws when some hand still has to be compared with it.
  PlayingCard? dealerDraw() {
    if (phase != BlackjackRoundPhase.dealerTurn) return null;
    final open = seats.expand((s) => s.hands).any((h) => !h.isBusted && !h.isBlackjack && !h.isCharlie);
    if (open && _dealerMustDraw) {
      final card = _draw();
      dealer.cards.add(card);
      if (dealer.handValue > 21) dealer.isBusted = true;
      return card;
    }
    _settle();
    return null;
  }

  // --- Payouts --------------------------------------------------------------------------------

  /// Chips returned for [h] against the final dealer hand (0 = lost).
  int handReturn(BlackjackHand h) {
    final dealerNatural = dealer.isNatural;
    final dv = dealer.handValue;
    if (h.isBusted) return 0;
    if (dealerNatural) return h.isNatural ? h.betAmount : 0;
    if (h.isBlackjack) return (h.betAmount * rules.blackjackReturn).round();
    if (h.isCharlie) return h.betAmount * 2;
    if (dv > 21 || h.handValue > dv) return h.betAmount * 2;
    if (h.handValue == dv) return h.betAmount;
    return 0;
  }

  void _settle() {
    final dealerNatural = dealer.isNatural;
    // The round is over: hands that never got to play (dealer natural) are closed too.
    for (final h in seats.expand((s) => s.hands)) {
      if (!h.isFinished) h.isStanding = true;
    }
    final out = <String, SeatResult>{};
    for (final s in seats.where((x) => x.isPlaying)) {
      var returned = 0;
      for (final h in s.hands) {
        returned += handReturn(h);
      }
      if (s.insurance > 0 && dealerNatural) returned += s.insurance * 3;
      final net = returned - s.totalBet - s.insurance;
      s.chips += returned;
      final BlackjackOutcome outcome;
      if (s.insurance > 0 && dealerNatural) {
        outcome = BlackjackOutcome.insured;
      } else if (net > 0) {
        outcome = s.hands.length == 1 && s.hands.first.isBlackjack
            ? BlackjackOutcome.blackjack
            : (s.hands.any((h) => h.isCharlie) ? BlackjackOutcome.charlie : BlackjackOutcome.win);
      } else if (net == 0) {
        outcome = BlackjackOutcome.push;
      } else {
        outcome = s.hands.every((h) => h.isBusted) ? BlackjackOutcome.bust : BlackjackOutcome.lose;
      }
      out[s.id] = SeatResult(outcome, returned, net);
    }
    results = out;
    currentIndex = -1;
    phase = BlackjackRoundPhase.settled;
  }

  /// Adds a seat (it plays from the next bets).
  void addSeat(BlackjackSeat s) {
    if (seats.any((x) => x.id == s.id)) throw ArgumentError('Seat ${s.id} already exists');
    seats.add(s);
  }

  /// Removes a seat that has nothing on the table this round. A bet placed before the deal
  /// goes back to the seat; once the round is settled its payouts are already in its chips.
  void removeSeat(String id) {
    final i = seats.indexWhere((s) => s.id == id);
    if (i < 0) return;
    final active = phase != BlackjackRoundPhase.betting && phase != BlackjackRoundPhase.settled;
    if (active && seats[i].isPlaying) throw StateError('$id is playing this round');
    if (phase == BlackjackRoundPhase.betting) seats[i].chips += seats[i].totalBet; // a pending bet goes back
    seats.removeAt(i);
    if (currentIndex > i) currentIndex--;
  }

  /// Clears the hands for the next round of bets.
  void newRound() {
    for (final s in seats) {
      s
        ..hands = []
        ..handIndex = 0
        ..insurance = 0
        ..insuranceAnswered = false;
    }
    dealer = BlackjackHand();
    _dealQueue.clear();
    results = const {};
    currentIndex = -1;
    phase = BlackjackRoundPhase.betting;
  }
}
