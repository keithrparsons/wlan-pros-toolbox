// Figure-write gate.
//
// The `capture` harnesses (book_screenshots, book3_screenshots, play_screenshots)
// RENDER app screens and WRITE PNGs into the repo. Rendering and asserting is
// cheap and valuable — it is what catches a figure whose on-screen values
// contradict its caption. WRITING is what dirties the working tree.
//
// Those two things used to be welded together, so a plain `flutter test`
// silently regenerated every figure and left the tree dirty. Four separate
// sessions stashed the resulting PNGs and moved on; one of those stashes held a
// real fix (the Book 3 "C2" loss-grade bug) that was nearly binned with them.
//
// So: the harnesses always RENDER and always ASSERT. They only WRITE when asked.
//
//   flutter test                                  → renders, asserts, writes NOTHING
//   WRITE_FIGURES=1 flutter test --tags capture   → regenerates the PNGs
//
// Keeping the harnesses in the default suite is deliberate: it means a broken
// figure fails the build the day it breaks, rather than the day someone
// regenerates.

import 'dart:io';

/// True only when the run was explicitly asked to regenerate image assets.
///
/// Gate every `File(...).writeAsBytes*` in a capture harness on this. Never gate
/// the render or the assertions — those must always run.
bool get kWriteFigures => Platform.environment['WRITE_FIGURES'] == '1';
