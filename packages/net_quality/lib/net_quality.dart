/// net_quality — backend-agnostic network-quality measurement layer.
///
/// The toolbox depends only on these abstractions. A measurement backend
/// (deterministic mock today; a real dart:io engine next) implements
/// [QualityClient] and is injected at the call site, so swapping in the real
/// engine never touches the UI.
///
/// Naming note: this is intentionally NOT "orb_service". Ookla/Orb expose no
/// SDK to run a measurement from a third-party app, so every number here is our
/// own computation. [QualityResult.source] records that provenance so the UI
/// never implies an Orb/Ookla result.
library net_quality;

export 'src/quality_result.dart';
export 'src/quality_client.dart';
export 'src/mock_quality_client.dart';
