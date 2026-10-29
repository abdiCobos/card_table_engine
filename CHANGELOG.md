## 0.1.2

- `TexasHoldemTable.startHand` throws a `StateError` while a hand is still in progress
  (before, the chips in the pot were lost).
- `BlackjackTable.removeSeat` after a settled round no longer gives the bet back a second time.
- `BotDecision.toString` prints `call` / `raise +60` instead of `BotActionKind.call`.

## 0.1.1

- Links to the GitHub repository and issue tracker.
- New README: install, examples for every table, exact rules and options.
- Code formatted with the standard Dart style.

## 0.1.0

- First release.
- Cards, decks and multi-deck shoes; `cards('As Kd')` helper.
- Texas Hold'em: `HandEvaluator`, side pots (`PotCalculator`), `TexasHoldemTable` and `PokerBotBrain`.
- Blackjack: `BlackjackHand`, `BlackjackTable` (insurance, double, split, step-by-step dealing)
  and `BlackjackBotBrain`.
