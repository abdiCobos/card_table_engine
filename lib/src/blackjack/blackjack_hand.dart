import '../cards.dart';

/// One Blackjack hand and its bet. [handValue] counts aces as 11 while that does not bust.
class BlackjackHand {
  final List<PlayingCard> cards;
  final int betAmount;
  bool isStanding;
  bool isBusted;
  bool isDoubledDown;
  bool isCharlie;

  /// Hand created by a split: a 2-card 21 is a plain 21, not a natural blackjack.
  final bool isSplit;

  BlackjackHand({
    List<PlayingCard>? cards,
    this.betAmount = 0,
    this.isStanding = false,
    this.isBusted = false,
    this.isDoubledDown = false,
    this.isCharlie = false,
    this.isSplit = false,
  }) : cards = cards ?? [];

  int get handValue {
    int total = 0;
    int aces = 0;
    for (final c in cards) {
      final v = cardValue(c.value);
      total += v;
      if (v == 11) aces++;
    }
    while (total > 21 && aces > 0) {
      total -= 10;
      aces--;
    }
    return total;
  }

  bool get isBlackjack => cards.length == 2 && handValue == 21 && betAmount > 0 && !isSplit;

  /// Two-card 21 regardless of the bet (the dealer's hand has no bet).
  bool get isNatural => cards.length == 2 && handValue == 21 && !isSplit;
  bool get canSplit => cards.length == 2 && cards[0].value == cards[1].value;
  bool get isFinished => isStanding || isBusted || isBlackjack || isCharlie;

  /// True when an ace still counts as 11 without busting.
  bool get isSoft {
    var hard = 0;
    var aces = 0;
    for (final c in cards) {
      if (c.value == 'A') {
        aces++;
        hard += 1;
      } else {
        hard += cardValue(c.value);
      }
    }
    return aces > 0 && hard + 10 <= 21;
  }

  /// Ace 11, faces 10, others their number.
  static int cardValue(String v) => switch (v) {
    'A' => 11,
    'K' || 'Q' || 'J' => 10,
    _ => int.tryParse(v) ?? 0,
  };

  BlackjackHand copyWith({
    List<PlayingCard>? cards,
    int? betAmount,
    bool? isStanding,
    bool? isBusted,
    bool? isDoubledDown,
    bool? isCharlie,
    bool? isSplit,
  }) => BlackjackHand(
    cards: cards ?? this.cards,
    betAmount: betAmount ?? this.betAmount,
    isStanding: isStanding ?? this.isStanding,
    isBusted: isBusted ?? this.isBusted,
    isDoubledDown: isDoubledDown ?? this.isDoubledDown,
    isCharlie: isCharlie ?? this.isCharlie,
    isSplit: isSplit ?? this.isSplit,
  );

  Map<String, dynamic> toMap() => {
    'cards': cards.map((c) => c.toMap()).toList(),
    'betAmount': betAmount,
    'isStanding': isStanding,
    'isBusted': isBusted,
    'isDoubledDown': isDoubledDown,
    'isCharlie': isCharlie,
    'isSplit': isSplit,
  };

  factory BlackjackHand.fromMap(Map<String, dynamic> m) => BlackjackHand(
    cards: (m['cards'] as List?)?.map((c) => PlayingCard.fromJson(Map<String, dynamic>.from(c as Map))).toList() ?? [],
    betAmount: m['betAmount'] ?? 0,
    isStanding: m['isStanding'] ?? false,
    isBusted: m['isBusted'] ?? false,
    isDoubledDown: m['isDoubledDown'] ?? false,
    isCharlie: m['isCharlie'] ?? false,
    isSplit: m['isSplit'] ?? false,
  );
}
