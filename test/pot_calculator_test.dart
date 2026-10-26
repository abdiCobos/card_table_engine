import 'dart:math';

import 'package:card_table_engine/card_table_engine.dart';
import 'package:test/test.dart';

int total(Map<String, int> m) => m.values.fold(0, (a, b) => a + b);

void main() {
  const order = ['a', 'b', 'c', 'd'];

  test('one winner takes everything', () {
    final r = PotCalculator.distribute(
      contributions: {'a': 100, 'b': 100, 'c': 100},
      strength: {'a': 5, 'b': 9, 'c': 1},
      seatOrder: order,
    );
    expect(r, {'b': 300});
  });

  test('a short all-in only wins what it could cover (side pot)', () {
    // a all-in for 50 with the best hand; b and c put 200 each.
    final r = PotCalculator.distribute(
      contributions: {'a': 50, 'b': 200, 'c': 200},
      strength: {'a': 9, 'b': 5, 'c': 3},
      seatOrder: order,
    );
    expect(r['a'], 150); // main pot: 50 x 3
    expect(r['b'], 300); // side pot: 150 x 2
    expect(total(r), 450);
  });

  test('three levels of all-in', () {
    final r = PotCalculator.distribute(
      contributions: {'a': 30, 'b': 80, 'c': 200, 'd': 200},
      strength: {'a': 9, 'b': 8, 'c': 1, 'd': 2},
      seatOrder: order,
    );
    expect(r['a'], 120); // 30 x 4
    expect(r['b'], 150); // 50 x 3
    expect(r['d'], 240); // 120 x 2
    expect(total(r), 510);
  });

  test('folded money stays in the pot but folded players never win', () {
    final r = PotCalculator.distribute(
      contributions: {'a': 100, 'b': 100, 'c': 40},
      strength: {'a': 3, 'b': 2}, // c folded
      seatOrder: order,
    );
    expect(r, {'a': 240});
  });

  test('a folded player who put in more than every contender still pays the pot', () {
    final r = PotCalculator.distribute(
      contributions: {'a': 50, 'b': 50, 'c': 120},
      strength: {'a': 3, 'b': 7}, // c bet more, then folded
      seatOrder: order,
    );
    expect(total(r), 220);
    expect(r['b'], 220);
  });

  test('uncalled excess goes back to the bettor', () {
    final r = PotCalculator.distribute(
      contributions: {'a': 40, 'b': 300},
      strength: {'a': 9, 'b': 1},
      seatOrder: order,
    );
    expect(r['a'], 80);
    expect(r['b'], 260);
  });

  test('ties split, odd chip goes to the first winner left of the dealer', () {
    final r = PotCalculator.distribute(
      contributions: {'a': 35, 'b': 35, 'c': 35},
      strength: {'a': 5, 'b': 1, 'c': 5},
      seatOrder: ['c', 'a', 'b'],
    );
    expect(r['c'], 53);
    expect(r['a'], 52);
    expect(total(r), 105);
  });

  test('dead money (house bonus) goes to the main pot winner', () {
    final r = PotCalculator.distribute(
      contributions: {'a': 20, 'b': 100, 'c': 100},
      strength: {'a': 9, 'b': 5, 'c': 1},
      seatOrder: order,
      deadMoney: 30,
    );
    expect(r['a'], 90);
    expect(r['b'], 160);
    expect(total(r), 250);
  });

  test('random hands never create or lose chips', () {
    final rng = Random(3);
    for (var round = 0; round < 3000; round++) {
      final n = 2 + rng.nextInt(7);
      final ids = [for (var i = 0; i < n; i++) 'p$i'];
      final contributions = {for (final id in ids) id: rng.nextInt(6) * 25 + rng.nextInt(2) * rng.nextInt(400)};
      final live = ids.where((_) => rng.nextBool()).toList();
      if (live.isEmpty) live.add(ids.first);
      final strength = {for (final id in live) id: rng.nextInt(4)};
      final dead = rng.nextInt(3) * 10;
      final r = PotCalculator.distribute(
        contributions: contributions,
        strength: strength,
        seatOrder: ids,
        deadMoney: dead,
      );
      expect(total(r), total(contributions) + dead, reason: 'round $round $contributions $strength');
      for (final id in r.keys) {
        expect(live, contains(id), reason: 'a folded player won chips');
      }
    }
  });
}
