import 'package:card_table_engine/card_table_engine.dart';
import 'package:test/test.dart';

BlackjackHand hand(List<String> values, {bool split = false, int bet = 100}) => BlackjackHand(
  cards: [for (final v in values) PlayingCard(value: v, suit: Suit.spades)],
  betAmount: bet,
  isSplit: split,
);

void main() {
  test('a natural 21 is blackjack', () {
    expect(hand(['K', 'A']).isBlackjack, isTrue);
    expect(hand(['K', 'A']).isFinished, isTrue);
  });

  test('21 with two cards after a split is a plain 21, not blackjack', () {
    final h = hand(['K', 'A'], split: true);
    expect(h.handValue, 21);
    expect(h.isBlackjack, isFalse);
  });

  test('three-card 21 is never blackjack', () {
    expect(hand(['7', '7', '7']).isBlackjack, isFalse);
  });

  test('split flag survives copyWith and the network round trip', () {
    final h = hand(['K', 'A'], split: true).copyWith(isDoubledDown: true);
    expect(h.isSplit, isTrue);
    expect(BlackjackHand.fromMap(h.toMap()).isSplit, isTrue);
    expect(BlackjackHand.fromMap(hand(['K', 'A']).toMap()).isSplit, isFalse);
  });
}
