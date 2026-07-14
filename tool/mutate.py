#!/usr/bin/env python3
"""Mutation harness: break one fixing line, run its guard tests, restore.

A test that stays GREEN when the line it guards is broken is not coverage.
Round 3 shipped two such lines. Every fixing line in round 4 goes through here.

Usage: python3 tool/mutate.py
"""
import shutil
import subprocess
import sys

# (label, file, old, new, test target)
MUTATIONS = [
    (
        "M1  wifi_connection_service: native onWifi (usesWifi disjunct)",
        "lib/services/network/wifi_connection_service.dart",
        "      if (path.usesWifi || path.wifiSatisfied) {",
        "      if (false || path.wifiSatisfied) { // MUTANT",
        "test/services/network/wifi_connection_service_test.dart",
    ),
    (
        "M2  wifi_connection_service: native onWifi (wifiSatisfied disjunct)",
        "lib/services/network/wifi_connection_service.dart",
        "      if (path.usesWifi || path.wifiSatisfied) {",
        "      if (path.usesWifi || false) { // MUTANT",
        "test/services/network/wifi_connection_service_test.dart",
    ),
    (
        "M3  wifi_connection_service: ambiguous-shape guard -> unknown",
        "lib/services/network/wifi_connection_service.dart",
        "      if (path.wifiInterfacePresent) {",
        "      if (false) { // MUTANT",
        "test/services/network/wifi_connection_service_test.dart",
    ),
    (
        "M4  wifi_connection_service: native notOnWifi verdict",
        "lib/services/network/wifi_connection_service.dart",
        "      return WifiConnectionStatus.notOnWifi;\n    }\n\n    // ====",
        "      return WifiConnectionStatus.unknown; // MUTANT\n    }\n\n    // ====",
        "test/services/network/wifi_connection_service_test.dart",
    ),
    (
        "M5  wifi_connection_service: the native path is consulted AT ALL",
        "lib/services/network/wifi_connection_service.dart",
        "    final WifiPathFacts? path =\n"
        "        _platform == TargetPlatform.iOS ? await _pathProbe.read() : null;",
        "    final WifiPathFacts? path = null; // MUTANT",
        "test/services/network/wifi_connection_service_test.dart",
    ),
    (
        "M15 wifi_connection_service: the iOS gate on the native read",
        "lib/services/network/wifi_connection_service.dart",
        "        _platform == TargetPlatform.iOS ? await _pathProbe.read() : null;",
        "        _platform == TargetPlatform.macOS ? await _pathProbe.read() : null;",
        "test/services/network/wifi_connection_service_test.dart",
    ),
    (
        "M6  wifi_connection_service: `::` all-zeros IPv6 normalization",
        "lib/services/network/wifi_connection_service.dart",
        "      if (t.isEmpty || _isUnspecifiedIpv6(t)) {",
        "      if (t.isEmpty) { // MUTANT",
        "test/services/network/wifi_connection_service_test.dart",
    ),
    (
        "M7  test_my_connection: _recomputeVerdict notOnWifi (ROUND-3 BLOCKER)",
        "lib/screens/tools/network/test_my_connection_screen.dart",
        "      notOnWifi: _resultNotOnWifi,\n      // The RUN's consent decision",
        "      notOnWifi: false, // MUTANT\n      // The RUN's consent decision",
        "test/screens/tools/network/test_my_connection_offwifi_e2e_test.dart",
    ),
    (
        "M8  test_my_connection: _buildAnalysisReport notOnWifi wiring",
        "lib/screens/tools/network/test_my_connection_screen.dart",
        "        notOnWifi: _resultNotOnWifi,\n        speedTestSkipped:",
        "        notOnWifi: false, // MUTANT\n        speedTestSkipped:",
        "test/screens/tools/network/test_my_connection_offwifi_e2e_test.dart",
    ),
    (
        "M9  test_my_connection: the run's notOnWifi GATE (linkAp suppression)",
        "lib/screens/tools/network/test_my_connection_screen.dart",
        "        final ConnectedAp? linkAp = notOnWifi ? null : ap;",
        "        final ConnectedAp? linkAp = ap; // MUTANT",
        "test/screens/tools/network/test_my_connection_offwifi_e2e_test.dart",
    ),
    (
        "M10 consumer_verdict: sameRealTier whitelist (notApplicable)",
        "lib/services/network/consumer_verdict.dart",
        "      case AxisStatus.unknown:\n      case AxisStatus.notApplicable:\n"
        "      case AxisStatus.notMeasured:\n        return null;",
        "      case AxisStatus.unknown:\n        return null;\n"
        "      case AxisStatus.notApplicable:\n      case AxisStatus.notMeasured:\n"
        "        return wifiStatus; // MUTANT",
        "test/services/consumer_verdict_test.dart",
    ),
    (
        "M11 interface_info_screen: the copy report's notOnWifi status line",
        "lib/screens/tools/network/interface_info_screen.dart",
        "    if (w.notOnWifi) {\n      // The copy report must say what the screen says",
        "    if (false) { // MUTANT\n      // The copy report must say what the screen says",
        "test/screens/tools/network/interface_info_notonwifi_test.dart",
    ),
    (
        "M12 interface_info_screen: the copy report's MAC-type block skip",
        "lib/screens/tools/network/interface_info_screen.dart",
        "    if (!w.notOnWifi) {\n      line('IPv4', w.wifiIPv4);",
        "    if (true) { // MUTANT\n      line('IPv4', w.wifiIPv4);",
        "test/screens/tools/network/interface_info_notonwifi_test.dart",
    ),
    (
        "M13 interface_info_screen: the Wi-Fi CARD's notOnWifi branch",
        "lib/screens/tools/network/interface_info_screen.dart",
        "    if (w.notOnWifi) {\n      final AppColorScheme colors = context.colors;",
        "    if (false) { // MUTANT\n      final AppColorScheme colors = context.colors;",
        "test/screens/tools/network/interface_info_notonwifi_test.dart",
    ),
    (
        "M14 interface_info_service: the connectivity gate itself",
        "lib/services/network/interface_info_service.dart",
        "    if (await _isNotOnWifi()) {",
        "    if (false) { // MUTANT",
        "test/screens/tools/network/interface_info_notonwifi_test.dart",
    ),
]


def run(target):
    r = subprocess.run(
        ["flutter", "test", target],
        capture_output=True, text=True, timeout=900,
    )
    return r.returncode == 0


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else None
    results = []
    for label, path, old, new, target in MUTATIONS:
        if only and not label.startswith(only):
            continue
        src = open(path).read()
        if src.count(old) != 1:
            results.append((label, "ANCHOR-MISS", f"found {src.count(old)}x"))
            print(f"!! {label}: ANCHOR NOT UNIQUE ({src.count(old)}x)")
            continue
        backup = path + ".mutbak"
        shutil.copy2(path, backup)
        try:
            open(path, "w").write(src.replace(old, new))
            green = run(target)
            verdict = "SURVIVED (NO COVERAGE)" if green else "KILLED"
            results.append((label, verdict, target))
            mark = "!!" if green else "OK"
            print(f"{mark} {label}\n     -> mutant {verdict}")
        finally:
            shutil.move(backup, path)

    print("\n" + "=" * 78)
    print("MUTATION REPORT")
    print("=" * 78)
    bad = 0
    for label, verdict, _ in results:
        flag = " <-- FIX THE TEST" if verdict != "KILLED" else ""
        if verdict != "KILLED":
            bad += 1
        print(f"  [{verdict:22}] {label}{flag}")
    print("=" * 78)
    print(f"{len(results) - bad}/{len(results)} mutants killed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
