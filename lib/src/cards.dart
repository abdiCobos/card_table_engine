import 'dart:math';

enum Suit { hearts, diamonds, clubs, spades }

/// A playing card. [value] is one of '2'..'10', 'J', 'Q', 'K', 'A'.
class PlayingCard {
  final String value;
  final Suit suit;

  PlayingCard({required this.value, required this.suit});

  static const values = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];

  /// 2..14 (ace high).
  int get rank => switch (value) {
    'A' => 14,
    'K' => 13,
    'Q' => 12,
    'J' => 11,
    _ => int.tryParse(value) ?? 0,
  };

  /// Short form: 'As', '10h', 'Qd', '7c'.
  String get code => '$value${suit.name[0]}';

  /// Parses [code] ('As', '10h', 'td' for ten, case-insensitive suit letter).
  factory PlayingCard.parse(String code) {
    final c = code.trim();
    if (c.length < 2) throw FormatException('Not a card: $code');
    var v = c.substring(0, c.length - 1).toUpperCase();
    if (v == 'T') v = '10';
    final s = switch (c[c.length - 1].toLowerCase()) {
      'h' => Suit.hearts,
      'd' => Suit.diamonds,
      'c' => Suit.clubs,
      's' => Suit.spades,
      _ => throw FormatException('Not a suit: $code'),
    };
    if (!values.contains(v)) throw FormatException('Not a card value: $code');
    return PlayingCard(value: v, suit: s);
  }

  Map<String, dynamic> toJson() => {'value': value, 'suit': suit.name};

  Map<String, dynamic> toMap() => toJson();

  factory PlayingCard.fromJson(Map<String, dynamic> json) =>
      PlayingCard(value: json['value'] as String, suit: Suit.values.byName(json['suit'] as String));

  factory PlayingCard.fromMap(Map<String, dynamic> map) => PlayingCard.fromJson(map);

  @override
  bool operator ==(Object other) => other is PlayingCard && other.value == value && other.suit == suit;

  @override
  int get hashCode => Object.hash(value, suit);

  @override
  String toString() => code;
}

/// Parses several cards: `cards('As Kd 10h')`.
List<PlayingCard> cards(String codes) =>
    codes.split(RegExp(r'[\s,]+')).where((s) => s.isNotEmpty).map(PlayingCard.parse).toList();

/// A deck or a multi-deck shoe. Cards are drawn from the end of [cards].
class Deck {
  final List<PlayingCard> cards;

  Deck._(this.cards);

  /// [decks] standard 52-card decks, shuffled with [random].
  factory Deck.shuffled({int decks = 1, Random? random}) => Deck._(standard(decks: decks)..shuffle(random ?? Random()));

  /// A deck whose first draws are [top] (in that order), then the rest of a shuffled deck.
  /// Handy for tests and replays.
  factory Deck.stacked(List<PlayingCard> top, {int decks = 1, Random? random}) {
    final rest = standard(decks: decks)..shuffle(random ?? Random());
    for (final c in top) {
      rest.remove(c);
    }
    return Deck._([...rest, ...top.reversed]);
  }

  /// Unshuffled cards of [decks] standard decks.
  static List<PlayingCard> standard({int decks = 1}) => [
    for (var d = 0; d < decks; d++)
      for (final s in Suit.values)
        for (final v in PlayingCard.values) PlayingCard(value: v, suit: s),
  ];

  int get length => cards.length;
  bool get isEmpty => cards.isEmpty;

  PlayingCard draw() {
    if (cards.isEmpty) throw StateError('The deck is empty');
    return cards.removeLast();
  }
}
