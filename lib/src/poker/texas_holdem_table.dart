import 'dart:math';

import '../cards.dart';
import 'hand_evaluator.dart';
import 'pot_calculator.dart';

enum Street { preFlop, flop, turn, river, showdown }

/// What the player whose turn it is may do.
enum PokerMove { fold, check, call, raise }

/// A seat at a Texas Hold'em table.
class TexasSeat {
  final String id;
  int chips;

  /// Skips the next deals (away, busted waiting for a rebuy...). Set it between hands.
  bool sittingOut;

  List<PlayingCard> hole = [];
  bool folded = false;

  /// Chips put in during the current street / the whole hand.
  int streetBet = 0;
  int committed = 0;

  /// Acted since the last raise on this street (posting a blind is not acting).
  bool acted = false;

  TexasSeat(this.id, this.chips, {this.sittingOut = false});

  /// Dealt in this hand and not folded.
  bool get inHand => hole.isNotEmpty && !folded;
  bool get isAllIn => inHand && chips == 0;
  bool get canAct => inHand && chips > 0;

  @override
  String toString() => '$id($chips${folded ? ', folded' : ''}${isAllIn ? ', all-in' : ''})';
}

/// How a hand ended.
class HandOutcome {
  /// Everyone else folded: [winners] has the one player left and no cards were shown.
  final bool byFold;

  /// Chips each player received (main and side pots, dead money included).
  final Map<String, int> payouts;

  /// Showdown hands of the players still in (empty when [byFold]).
  final Map<String, HandResult> hands;

  /// Winner(s) of the main pot.
  final List<String> winners;

  const HandOutcome({required this.byFold, required this.payouts, required this.hands, required this.winners});

  @override
  String toString() => 'HandOutcome(${byFold ? 'fold' : 'showdown'}, winners: $winners, payouts: $payouts)';
}

/// No-limit Texas Hold'em table: dealer button, blinds, four betting streets, all-in
/// run-outs and showdown with side pots. Synchronous and UI-free: call [startHand], then
/// let the player in [currentSeat] act with [fold], [call] or [raise] until [outcome] is set.
///
/// Rules: SB/BB after the button (heads-up the button posts the small blind and acts first
/// preflop); post-flop the first player left of the button who can still bet acts first;
/// a raise reopens the action; there is no minimum raise; a short call is an all-in for less;
/// odd chips of a split pot go to the first winner left of the button.
class TexasHoldemTable {
  final List<TexasSeat> seats;
  final int smallBlind;
  final int bigBlind;
  final Random _random;

  TexasHoldemTable({required this.seats, this.smallBlind = 10, this.bigBlind = 20, Random? random})
    : _random = random ?? Random() {
    if (seats.map((s) => s.id).toSet().length != seats.length) {
      throw ArgumentError('Seat ids must be unique');
    }
  }

  int dealerIndex = -1;
  int smallBlindIndex = -1;
  int bigBlindIndex = -1;

  /// Seat whose turn it is, -1 between hands.
  int currentIndex = -1;
  Street street = Street.preFlop;
  int handNumber = 0;

  /// Highest [TexasSeat.streetBet] on this street.
  int currentBet = 0;

  /// Raises made on this street.
  int raisesThisStreet = 0;

  /// Chips in the pot that belong to nobody (house bonus); they go to the main pot.
  int deadMoney = 0;

  HandOutcome? outcome;

  /// Rest of the deck after the deal (variants may draw extra cards from it).
  Deck deck = Deck.shuffled();
  List<PlayingCard> _board = const [];

  bool get handInProgress => handNumber > 0 && outcome == null;
  TexasSeat? get currentSeat => currentIndex < 0 ? null : seats[currentIndex];
  TexasSeat seat(String id) => seats.firstWhere((s) => s.id == id);

  /// Community cards dealt so far (all five are drawn at the deal and revealed by street).
  List<PlayingCard> get board => _board.take(revealedCount).toList();

  /// All five community cards, including the ones not revealed yet.
  List<PlayingCard> get fullBoard => List.unmodifiable(_board);

  int get revealedCount => switch (street) {
    Street.preFlop => 0,
    Street.flop => 3,
    Street.turn => 4,
    Street.river || Street.showdown => 5,
  };

  int get pot => seats.fold(deadMoney, (n, s) => n + s.committed);

  int toCall(String id) {
    final s = seat(id);
    return max(0, currentBet - s.streetBet);
  }

  List<PokerMove> legalMoves(String id) {
    final s = seat(id);
    if (!handInProgress || currentSeat?.id != id) return const [];
    final owe = toCall(id);
    return [PokerMove.fold, owe == 0 ? PokerMove.check : PokerMove.call, if (s.chips > owe) PokerMove.raise];
  }

  /// Seat ids clockwise starting left of the button.
  List<String> get seatOrderFromDealer => [
    for (var i = 1; i <= seats.length; i++) seats[(max(0, dealerIndex) + i) % seats.length].id,
  ];

  // --- Dealing --------------------------------------------------------------------------------

  /// Moves the button, posts the blinds and deals. Seats that are [TexasSeat.sittingOut] or
  /// have no chips are skipped. [deck] lets tests (or replays) choose the cards.
  void startHand({Deck? deck}) {
    final eligible = [
      for (var i = 0; i < seats.length; i++)
        if (!seats[i].sittingOut && seats[i].chips > 0) i,
    ];
    if (eligible.length < 2) throw StateError('A hand needs at least two players with chips');
    for (final s in seats) {
      s
        ..hole = []
        ..folded = false
        ..streetBet = 0
        ..committed = 0
        ..acted = false;
    }
    outcome = null;
    deadMoney = 0;
    currentBet = 0;
    raisesThisStreet = 0;
    street = Street.preFlop;
    handNumber++;
    this.deck = deck ?? Deck.shuffled(random: _random);

    dealerIndex = _nextEligible(dealerIndex, eligible);
    if (eligible.length == 2) {
      smallBlindIndex = dealerIndex;
      bigBlindIndex = _nextEligible(dealerIndex, eligible);
    } else {
      smallBlindIndex = _nextEligible(dealerIndex, eligible);
      bigBlindIndex = _nextEligible(smallBlindIndex, eligible);
    }

    // Two passes, starting left of the button, then the five community cards.
    final order = [
      for (var k = 1; k <= seats.length; k++) (dealerIndex + k) % seats.length,
    ].where(eligible.contains).toList();
    for (var pass = 0; pass < 2; pass++) {
      for (final i in order) {
        seats[i].hole = [...seats[i].hole, this.deck.draw()];
      }
    }
    _board = [for (var k = 0; k < 5; k++) this.deck.draw()];

    _put(seats[smallBlindIndex], min(smallBlind, seats[smallBlindIndex].chips));
    _put(seats[bigBlindIndex], min(bigBlind, seats[bigBlindIndex].chips));
    // A big blind short of chips (all-in for less) still sets the price: the others call the full blind.
    currentBet = max(bigBlind, seats.map((s) => s.streetBet).fold(0, max));

    currentIndex = bigBlindIndex;
    _advance();
  }

  int _nextEligible(int from, List<int> eligible) {
    for (var k = 1; k <= seats.length; k++) {
      final i = (from + k) % seats.length;
      if (eligible.contains(i)) return i;
    }
    return eligible.first;
  }

  void _put(TexasSeat s, int amount) {
    s.chips -= amount;
    s.streetBet += amount;
    s.committed += amount;
  }

  // --- Actions --------------------------------------------------------------------------------

  void fold(String id) {
    final s = _turnOf(id);
    s
      ..folded = true
      ..acted = true;
    _advance();
  }

  /// Check when nothing is owed, otherwise call (all-in for less if short).
  void call(String id) {
    final s = _turnOf(id);
    _put(s, min(toCall(id), s.chips));
    s.acted = true;
    _advance();
  }

  /// Calls and puts [by] more on top (all-in if the stack is shorter). Reopens the action.
  void raise(String id, int by) {
    if (by <= 0) throw ArgumentError.value(by, 'by', 'A raise must be greater than zero');
    final s = _turnOf(id);
    _put(s, min(toCall(id) + by, s.chips));
    if (s.streetBet > currentBet) {
      currentBet = s.streetBet;
      raisesThisStreet++;
      for (final o in seats) {
        if (!identical(o, s) && o.canAct) o.acted = false;
      }
    }
    s.acted = true;
    _advance();
  }

  /// Puts the whole stack in.
  void allIn(String id) {
    final s = _turnOf(id);
    final owe = toCall(id);
    if (s.chips > owe) {
      raise(id, s.chips - owe);
    } else {
      call(id);
    }
  }

  TexasSeat _turnOf(String id) {
    if (!handInProgress) throw StateError('No hand in progress');
    final s = currentSeat;
    if (s == null || s.id != id) throw StateError('It is not the turn of $id');
    return s;
  }

  // --- Flow -----------------------------------------------------------------------------------

  void _advance() {
    final live = seats.where((s) => s.inHand).toList();
    if (live.length == 1) {
      _winByFold(live.single);
      return;
    }
    // Nobody can bet against anybody any more (everyone else all-in and nothing owed):
    // deal the rest of the board and show down.
    final actors = seats.where((s) => s.canAct).toList();
    if (actors.isEmpty || (actors.length == 1 && actors.single.streetBet >= currentBet)) {
      street = Street.showdown;
      _showdown();
      return;
    }
    if (!_streetComplete) {
      currentIndex = _nextToAct(currentIndex);
      return;
    }
    if (street == Street.river) {
      street = Street.showdown;
      _showdown();
      return;
    }
    street = Street.values[street.index + 1];
    for (final s in seats) {
      s
        ..streetBet = 0
        ..acted = false;
    }
    currentBet = 0;
    raisesThisStreet = 0;
    currentIndex = _nextToAct(dealerIndex);
  }

  bool get _streetComplete =>
      seats.where((s) => s.inHand).every((s) => s.isAllIn || (s.acted && s.streetBet == currentBet));

  int _nextToAct(int from) {
    for (var k = 1; k <= seats.length; k++) {
      final i = (from + k) % seats.length;
      final s = seats[i];
      if (s.canAct && (!s.acted || s.streetBet < currentBet)) return i;
    }
    return -1;
  }

  void _winByFold(TexasSeat winner) {
    final amount = pot;
    winner.chips += amount;
    currentIndex = -1;
    outcome = HandOutcome(byFold: true, payouts: {winner.id: amount}, hands: const {}, winners: [winner.id]);
  }

  void _showdown() {
    currentIndex = -1;
    final live = seats.where((s) => s.inHand).toList();
    final hands = {for (final s in live) s.id: HandEvaluator.evaluate(s.hole, _board)};
    final payouts = PotCalculator.distribute(
      contributions: {
        for (final s in seats)
          if (s.committed > 0) s.id: s.committed,
      },
      strength: {for (final e in hands.entries) e.key: e.value.power},
      seatOrder: seatOrderFromDealer,
      deadMoney: deadMoney,
    );
    for (final e in payouts.entries) {
      seat(e.key).chips += e.value;
    }
    final best = hands.values.map((h) => h.power).fold(0, max);
    outcome = HandOutcome(
      byFold: false,
      payouts: payouts,
      hands: hands,
      winners: [
        for (final e in hands.entries)
          if (e.value.power == best) e.key,
      ],
    );
  }

  // --- Variants (house rules on top of plain Hold'em) -----------------------------------------

  /// Adds chips that belong to nobody to the pot (for example a house bonus).
  void addDeadMoney(int chips) {
    if (chips < 0) throw ArgumentError.value(chips, 'chips');
    deadMoney += chips;
  }

  /// Replaces a live player's hole cards (card-swap variants).
  void setHoleCards(String id, List<PlayingCard> cards) {
    final s = seat(id);
    if (!s.inHand) throw StateError('$id is not in the hand');
    s.hole = List.of(cards);
  }
}
