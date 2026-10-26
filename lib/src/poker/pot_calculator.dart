/// Splits a poker pot into main and side pots and pays each one.
///
class PotCalculator {
  /// Returns the chips each player wins.
  ///
  /// - [contributions]: chips every player put in this hand, folded players included.
  /// - [strength]: hand power of the players still in at showdown; only they can win.
  /// - [seatOrder]: player ids clockwise starting left of the dealer. Odd chips of a
  ///   split pot go to the winners in this order (standard casino rule).
  /// - [deadMoney]: chips in the pot that belong to nobody (e.g. a house bonus);
  ///   they go to the main pot.
  ///
  /// The sum of the result always equals the sum of [contributions] + [deadMoney].
  static Map<String, int> distribute({
    required Map<String, int> contributions,
    required Map<String, int> strength,
    required List<String> seatOrder,
    int deadMoney = 0,
  }) {
    final payouts = <String, int>{};
    final contenders = strength.keys.where((id) => (contributions[id] ?? 0) > 0 || contributions.isEmpty).toList();
    if (contenders.isEmpty) contenders.addAll(strength.keys);
    if (contenders.isEmpty) return payouts;

    // One pot per distinct amount a contender has put in (the all-in "levels").
    final levels = {for (final id in contenders) contributions[id] ?? 0}.toList()..sort();
    final topLevel = contributions.values.fold<int>(0, (a, b) => a > b ? a : b);
    if (levels.isEmpty || levels.last < topLevel) {
      // Money above every contender's level (a folded player who put in more):
      // it belongs to the biggest pot.
      levels.add(topLevel);
    }

    var previous = 0;
    var extra = deadMoney;
    for (final level in levels) {
      if (level <= previous) continue;
      var amount = extra;
      extra = 0;
      for (final c in contributions.values) {
        final upTo = c < level ? c : level;
        final from = c < previous ? c : previous;
        amount += upTo - from;
      }
      var eligible = contenders.where((id) => (contributions[id] ?? 0) >= level).toList();
      // Nobody still in reached this level (only folded money): highest contenders take it.
      if (eligible.isEmpty) {
        final best = contenders.map((id) => contributions[id] ?? 0).reduce((a, b) => a > b ? a : b);
        eligible = contenders.where((id) => (contributions[id] ?? 0) == best).toList();
      }
      previous = level;
      if (amount <= 0) continue;
      _pay(amount, eligible, strength, seatOrder, payouts);
    }
    if (extra > 0) _pay(extra, contenders, strength, seatOrder, payouts);
    return payouts;
  }

  static void _pay(
    int amount,
    List<String> eligible,
    Map<String, int> strength,
    List<String> seatOrder,
    Map<String, int> payouts,
  ) {
    final best = eligible.map((id) => strength[id] ?? 0).reduce((a, b) => a > b ? a : b);
    final winners = eligible.where((id) => (strength[id] ?? 0) == best).toList()
      ..sort((a, b) => _seat(seatOrder, a).compareTo(_seat(seatOrder, b)));
    final share = amount ~/ winners.length;
    var odd = amount - share * winners.length;
    for (final w in winners) {
      payouts[w] = (payouts[w] ?? 0) + share + (odd > 0 ? 1 : 0);
      if (odd > 0) odd--;
    }
  }

  static int _seat(List<String> order, String id) {
    final i = order.indexOf(id);
    return i < 0 ? order.length : i;
  }
}
