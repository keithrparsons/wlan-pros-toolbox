# Tests

CI runs `flutter test --exclude-tags "capture || golden"`. Golden tests run locally with `flutter test --tags golden`.

## Golden source: the M2

Golden images are rendered by Flutter's test engine, and text rasterization differs slightly from one Mac to the next. A golden made on one machine can miss by a fraction of a percent on another with no code change (`test/flutter_test_config.dart` allows 0.5%).

**The M2 is the golden source** (Keith, 18 OCT 2026). Regenerate goldens on the M2 only, for example:

    flutter test test/screens/reference/reference_goldens_test.dart --update-goldens --plain-name "batteries @ 320w"

then run `flutter test --tags golden` on the M2 and review the image diff before committing. On any other machine, a golden failure under about 1% with no change to that screen is host jitter, not a regression.

Last regenerated on the M2 on 18 OCT 2026: `batteries_320w`, `roaming_320w`, `sd_cards_320w`. Roaming's was also stale: a 25 SEP text change had refreshed only the 800 px image.
