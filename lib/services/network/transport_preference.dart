// TransportPreference — the app-wide answer to "which path should the tools
// use", and the honest report of what actually happened to that choice.
//
// WHY APP-WIDE (Keith, 2026-09-01): "I agree the transport chooser should be
// app-wide." His original framing on 2026-08-31 was already this shape: "How do
// we TELL the toolbox to use Ethernet or Wi-Fi on those 26 tools." One choice,
// every tool honours it. The alternative — a chooser on each of the seven
// screens that prefill a target — would have been seven edits, seven places to
// drift, and a user answering the same question seven times.
//
// WHAT IS STORED IS A KIND, NOT AN INTERFACE NAME. `en5` is not a concept a
// user holds, it is not stable across reboots or dock changes, and Phase 0
// established that selecting by name is the defect this whole area exists to
// fix (network_info_plus matched the literal string `en0`, which on a MacBook
// is Wi-Fi). The user thinks "use the wired connection"; that is what we store.
//
// THE HONESTY THIS FILE OWES, and it is the whole reason [TransportResolution]
// exists rather than a bare `LinkInfo?` return. A preference can go stale in
// four different ways and they are NOT the same event:
//
//   - the cable was unplugged           -> the choice is unavailable
//   - the platform refuses this scope   -> the choice is impossible, not absent
//   - we have never tested this machine -> unanswered, not refused
//   - nothing was ever chosen           -> the OS decides, which is correct
//
// Collapsing those into "fall back to the active link" would make a tool
// silently measure a path the user did not pick, which is exactly the class of
// defect that put a wired Mac's own subnet at 192.168.8.134 on the Wi-Fi.
// So this file ALWAYS returns something usable AND ALWAYS says what it did.

import 'package:shared_preferences/shared_preferences.dart';

import 'link_info.dart';
import 'transport_chooser.dart';

/// What happened to the user's choice on this device, right now.
enum TransportResolution {
  /// Nothing is chosen. The operating system's routing table decides, which is
  /// the correct default and is not a degraded state.
  followingSystem,

  /// The chosen kind is present and usable, and it is what the tools will use.
  honouringChoice,

  /// A kind is chosen but no interface of that kind has a usable link right
  /// now. The cable is out, the radio is off, or the hardware is gone.
  chosenUnavailable,

  /// The interface is there and working, but this platform will not let an
  /// unprivileged app send this scope over it. A refusal, not an absence.
  chosenNotSelectable,

  /// The interface is there and whether we can pin traffic to it has never been
  /// established on THIS machine. An unanswered question, not a refusal.
  chosenUntested,
}

/// The resolved transport, plus what became of the preference.
class ResolvedTransport {
  const ResolvedTransport({
    required this.resolution,
    required this.chosen,
    this.link,
    this.reason,
  });

  final TransportResolution resolution;

  /// What the user asked for, or null when nothing is chosen.
  final TransportKind? chosen;

  /// The interface the tools should actually use. May be the active link rather
  /// than the chosen one — [resolution] says which.
  final LinkInfo? link;

  /// The chooser's own plain-words explanation, carried through unchanged when
  /// the choice could not be honoured. Never invented here.
  final String? reason;

  /// True only when the tools are using the interface the user picked.
  bool get isHonoured => resolution == TransportResolution.honouringChoice;

  /// True when a choice exists and is NOT being used. The UI must say so;
  /// silence here is the defect this class exists to prevent.
  bool get isStale =>
      chosen != null && resolution != TransportResolution.honouringChoice;
}

/// Names the transport a COMPLETED measurement actually ran over.
///
/// THE DEFECT THIS CLOSES (Keith, 2026-09-06): "Nothing names which transport a
/// result used. Now that a user can choose one, this matters." Before the
/// chooser existed the answer was always "whatever the OS picked", so the
/// question never arose. It arises now, and a result that does not say what it
/// measured is a number without a subject.
///
/// It is deliberately built from what the RESULT carries, not from the live
/// link table: attributing a frozen result to the interface that happens to
/// hold the default route NOW would re-introduce the freeze defect the result
/// card already guards against, where a phone that moved after the check
/// rewrites what the check was about.
///
/// No em dash, per GL-004: this is user-facing product copy.
String measurementAttribution({
  required bool notOnWifi,
  String? interfaceName,
  String? ssid,
}) {
  final String? iface =
      (interfaceName != null && interfaceName.trim().isNotEmpty)
      ? interfaceName.trim()
      : null;
  if (notOnWifi) {
    return iface == null
        ? 'Measured over your wired or cellular connection, not Wi-Fi.'
        : 'Measured over $iface, not Wi-Fi.';
  }
  final String? name = (ssid != null && ssid.trim().isNotEmpty)
      ? ssid.trim()
      : null;
  if (name != null && iface != null)
    return 'Measured over Wi-Fi: $name ($iface).';
  if (name != null) return 'Measured over Wi-Fi: $name.';
  if (iface != null) return 'Measured over Wi-Fi ($iface).';
  return 'Measured over Wi-Fi.';
}

/// Reads and writes the app-wide transport choice.
///
/// Persistence mirrors [LiveOnboardingService]: shared_preferences, one key, an
/// injectable store so it is unit-testable without a platform channel, and a
/// read failure degrades to "nothing chosen" rather than throwing. A storage
/// fault must never stop a tool running; it may only lose a preference.
class TransportPreference {
  TransportPreference({Future<SharedPreferences> Function()? getStore})
    : _getStore = getStore ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _getStore;

  /// Versioned, so a future change of what is stored cannot be silently
  /// misread as the old shape.
  static const String prefsKey = 'transport_preference_kind_v1';

  /// The chosen kind, or null for "let the OS decide".
  ///
  /// A read failure returns null. That is the safe direction: the tools behave
  /// exactly as they did before this feature existed.
  Future<TransportKind?> read() async {
    try {
      final SharedPreferences store = await _getStore();
      final String? raw = store.getString(prefsKey);
      if (raw == null) return null;
      for (final TransportKind k in TransportKind.values) {
        if (k.name == raw) return k;
      }
      // An unrecognised value is a forward-compatibility case, not corruption.
      // Treat it as "nothing chosen" rather than guessing which kind was meant.
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Persists [kind], or clears the preference when null.
  ///
  /// Returns whether the write actually landed, so a caller can tell the user
  /// their choice did not stick instead of showing a selected radio button that
  /// will be gone next launch.
  Future<bool> write(TransportKind? kind) async {
    try {
      final SharedPreferences store = await _getStore();
      if (kind == null) return store.remove(prefsKey);
      return store.setString(prefsKey, kind.name);
    } catch (_) {
      return false;
    }
  }
}

/// Resolves a stored preference against what the machine can actually do.
///
/// [options] comes from [buildTransportOptions], so every reason string on a
/// non-choosable row is the chooser's own words. **This function never writes a
/// reason of its own** — inventing one here would put two authors on the same
/// sentence and let them drift.
///
/// [activeLink] is what the routing table says is in use, and is the fallback
/// whenever the choice cannot be honoured. The fallback is never silent: the
/// returned [TransportResolution] always names what happened.
ResolvedTransport resolveTransport({
  required TransportKind? chosen,
  required List<TransportOption> options,
  required LinkInfo? activeLink,
}) {
  if (chosen == null) {
    return ResolvedTransport(
      resolution: TransportResolution.followingSystem,
      chosen: null,
      link: activeLink,
    );
  }

  TransportOption? match;
  for (final TransportOption o in options) {
    if (o.kind == chosen) {
      match = o;
      break;
    }
  }

  // A kind that is not in the options list at all is the same user-visible
  // event as one that is present with no link: what you picked is not usable.
  if (match == null) {
    return ResolvedTransport(
      resolution: TransportResolution.chosenUnavailable,
      chosen: chosen,
      link: activeLink,
    );
  }

  if (match.isChoosable && match.link != null) {
    return ResolvedTransport(
      resolution: TransportResolution.honouringChoice,
      chosen: chosen,
      link: match.link,
      reason: match.reason.isEmpty ? null : match.reason,
    );
  }

  final TransportResolution why = switch (match.state) {
    TransportState.presentNotSelectable =>
      TransportResolution.chosenNotSelectable,
    TransportState.presentUntested => TransportResolution.chosenUntested,
    _ => TransportResolution.chosenUnavailable,
  };

  return ResolvedTransport(
    resolution: why,
    chosen: chosen,
    link: activeLink,
    reason: match.reason.isEmpty ? null : match.reason,
  );
}
