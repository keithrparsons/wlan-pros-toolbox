#!/usr/bin/env bash
# Capture the Book 3 ("Fix Your Own Wi-Fi") in-app screenshots S1–S15.
#
# Runs the deterministic fixture-capture harness
# (test/book3_screenshots/capture_book3_figures_test.dart), which renders each
# real registered screen at iPhone-class width (393 logical px) × 3× DPI under
# the brand AppTheme.dark(), with prose-matching injected fixtures, and writes
# 3× PNGs to book3_screenshots/raw/.
#
# Honesty (GL-005 / GL-008): every on-screen verdict/grade is the app's OWN
# computed output, asserted on screen before each PNG is written — never a
# painted-on string, never fabricated data.
#
# S16 (the copied reading pasted into a Messages/email draft) is NOT an app
# screen and is intentionally NOT produced here — it needs a Charta mockup.
#
# Usage:  tool/capture_book3_screenshots.sh
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Capturing Book 3 screenshots S1–S15…"
flutter test --tags capture test/book3_screenshots/capture_book3_figures_test.dart

echo
echo "Wrote 3× PNGs to: book3_screenshots/raw/"
ls -1 book3_screenshots/raw/S*.png
