# Test-only formula-glyph fallback font

`FormulaFallback.ttf` is a small subset of **STIX Two Text** (SIL Open Font
License 1.1, Copyright 2001–2021 The STIX Fonts Project Authors,
https://github.com/stipub/stixfonts). It carries only the glyphs the shipped
typefaces (DM Mono, IBM Plex Sans) lack in the headless test render:

- Greek lambda U+03BB (and mu U+03BC, defensive)
- Subscript digits and signs U+2080–U+208B
- Superscript digits and signs U+2070–U+207B
- Middle dot U+00B7, multiply U+00D7, degree U+00B0, minus U+2212, U+00B2/U+00B3

## Why it exists

The book-figure capture harness (`test/book_screenshots/`) renders formula
cards (`dBm = 10·log₁₀(mW)`, `λ(m) = 300 / f`, `10⁻²³`) headless via
`RepaintBoundary.toImage`. The headless engine has no OS font-fallback chain, so
codepoints missing from the FontLoader-registered families render as `.notdef`
boxes. `test/flutter_test_config.dart` appends this subset LAST to the `DM Mono`
and `IBM Plex Sans` families so missing glyphs fall through to it, while every
glyph the primary faces own still renders from the primary face.

## Scope

Test path only. This asset is listed under `flutter: assets:` (so
`rootBundle.load` can reach it) but deliberately NOT under `flutter: fonts:`, so
it is not part of the shipped app binary. On a real device the OS font-fallback
chain supplies these glyphs from a system font, so no app-side change is needed.

The SIL OFL 1.1 permits subsetting and bundling; the subset retains the upstream
license name records. Full license: https://scripts.sil.org/OFL
