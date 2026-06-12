// Keyboard Shortcuts reference data — compile-time const, source of truth for
// the data-driven Keyboard Shortcuts screen (Tier-1, Pass 2b 2026-06-12).
//
// Six panels, distilled from the published Apple macOS keyboard-shortcut list,
// the Microsoft Windows keyboard-shortcut list, standard GNU readline / zsh
// line-editing bindings, the PSReadLine key bindings, the macOS Option-key
// special-symbol layer, and common RF / antenna Greek-letter notation:
//   A. macOS system shortcuts
//   B. Windows system shortcuts
//   C. macOS Terminal (zsh / bash line editing)
//   D. Windows PowerShell (PSReadLine)
//   E. Special symbols on a Mac (hold Option)
//   F. Greek letters and symbols (RF math)
//
// Glyph note: ASCII hyphen-minus only in prose; no em dash. "Wi-Fi" casing.
// The literal symbol glyphs (™, ®, λ, Ω …) are reference DATA, not chrome.

/// One key-combo -> action row. The [combo] is rendered in DM Mono as keycaps;
/// [action] is the plain-language result.
class ShortcutRow {
  const ShortcutRow(this.combo, this.action);

  /// Key combination, e.g. `Cmd Shift 4`.
  final String combo;

  /// What the combination does.
  final String action;
}

/// One Option-key special-symbol row: the key combo, the resulting glyph, and
/// its name. The glyph is the copy target.
class SymbolRow {
  const SymbolRow(this.combo, this.symbol, this.name);

  /// Key combination, e.g. `Opt 2`.
  final String combo;

  /// Resulting symbol glyph, e.g. `™`.
  final String symbol;

  /// Symbol name, e.g. `Trademark`.
  final String name;
}

/// One Greek-letter row: lower/upper glyphs, the letter name, and its common
/// use in Wi-Fi / RF math. The lowercase glyph is the copy target.
class GreekRow {
  const GreekRow(this.lower, this.upper, this.name, this.use);

  /// Lowercase glyph, e.g. `λ`.
  final String lower;

  /// Uppercase glyph, e.g. `Λ`.
  final String upper;

  /// Letter name, e.g. `lambda`.
  final String name;

  /// Common Wi-Fi / RF use, e.g. `wavelength`. Empty string when none.
  final String use;
}

/// A named group of shortcut rows (panels A-D).
class ShortcutGroup {
  const ShortcutGroup({required this.title, required this.rows});

  final String title;
  final List<ShortcutRow> rows;
}

// ── A. macOS system shortcuts ────────────────────────────────────────────────
const ShortcutGroup kMacosShortcuts = ShortcutGroup(
  title: 'macOS system',
  rows: <ShortcutRow>[
    ShortcutRow('Cmd C / X / V', 'Copy / Cut / Paste'),
    ShortcutRow('Cmd Shift V', 'Paste and match style'),
    ShortcutRow('Cmd Z / Cmd Shift Z', 'Undo / Redo'),
    ShortcutRow('Cmd A', 'Select all'),
    ShortcutRow('Cmd F / Cmd G', 'Find / Find next'),
    ShortcutRow('Cmd S / Cmd P', 'Save / Print'),
    ShortcutRow('Cmd W / Cmd Q', 'Close window / Quit app'),
    ShortcutRow('Cmd Tab / Cmd `', 'Switch app / Switch window in app'),
    ShortcutRow('Cmd Space', 'Spotlight search'),
    ShortcutRow(
      'Cmd Shift 4 / Cmd Shift 5',
      'Screenshot selection / Screenshot and record tools',
    ),
    ShortcutRow('Cmd Ctrl Space', 'Emoji and symbols viewer'),
    ShortcutRow('Cmd Ctrl Q', 'Lock screen'),
    ShortcutRow('Cmd Opt Esc', 'Force quit'),
    ShortcutRow('Cmd ,', 'Preferences'),
    ShortcutRow('Cmd H / Cmd M', 'Hide app / Minimize'),
  ],
);

// ── B. Windows system shortcuts ──────────────────────────────────────────────
const ShortcutGroup kWindowsShortcuts = ShortcutGroup(
  title: 'Windows system',
  rows: <ShortcutRow>[
    ShortcutRow('Ctrl C / X / V', 'Copy / Cut / Paste'),
    ShortcutRow('Ctrl Z / Ctrl Y', 'Undo / Redo'),
    ShortcutRow('Ctrl A', 'Select all'),
    ShortcutRow('Ctrl F / F3', 'Find / Find next'),
    ShortcutRow('Ctrl S / Ctrl P', 'Save / Print'),
    ShortcutRow('Alt F4', 'Close app'),
    ShortcutRow('Alt Tab / Win Tab', 'Switch window / Task view'),
    ShortcutRow('Win D / Win L', 'Show desktop / Lock screen'),
    ShortcutRow('Win E', 'Open File Explorer'),
    ShortcutRow('Win .', 'Emoji panel'),
    ShortcutRow(
      'Win Shift S / PrtScn',
      'Screenshot snip / Screenshot to clipboard',
    ),
    ShortcutRow('Win V', 'Clipboard history'),
    ShortcutRow('Ctrl Shift Esc', 'Task Manager'),
    ShortcutRow('Win I', 'Settings'),
    ShortcutRow('Win Arrow', 'Snap window'),
    ShortcutRow('Win + number', 'Launch the nth taskbar app'),
  ],
);

// ── C. macOS Terminal (zsh / bash line editing) ──────────────────────────────
const ShortcutGroup kMacosTerminal = ShortcutGroup(
  title: 'macOS Terminal (zsh / bash)',
  rows: <ShortcutRow>[
    ShortcutRow('Ctrl C', 'Stop the current command'),
    ShortcutRow('Ctrl D', 'Exit / send EOF'),
    ShortcutRow('Ctrl Z', 'Suspend to background (fg to resume)'),
    ShortcutRow('Ctrl A / Ctrl E', 'Jump to line start / end'),
    ShortcutRow('Ctrl U / Ctrl K', 'Clear line before / after the cursor'),
    ShortcutRow('Ctrl W', 'Delete the word before the cursor'),
    ShortcutRow('Ctrl R', 'Reverse-search command history'),
    ShortcutRow('Ctrl L', 'Clear the screen'),
    ShortcutRow('Tab', 'Autocomplete'),
    ShortcutRow('Up / Down', 'Previous / next command'),
    ShortcutRow('Opt + click', 'Move the cursor to the click point'),
    ShortcutRow('Cmd K', 'Clear the scrollback (Terminal.app)'),
    ShortcutRow('Cmd T / Cmd N', 'New tab / New window'),
  ],
);

// ── D. Windows PowerShell (PSReadLine) ───────────────────────────────────────
const ShortcutGroup kWindowsPowershell = ShortcutGroup(
  title: 'Windows PowerShell (PSReadLine)',
  rows: <ShortcutRow>[
    ShortcutRow('Ctrl C', 'Stop / cancel the running command'),
    ShortcutRow('Tab', 'Autocomplete'),
    ShortcutRow('Up / Down', 'Scroll command history'),
    ShortcutRow('F7', 'Command-history popup'),
    ShortcutRow('F8', 'Search history by the typed prefix'),
    ShortcutRow('Ctrl R', 'Reverse history search (PSReadLine)'),
    ShortcutRow('Ctrl Space', 'Show all completions'),
    ShortcutRow('Ctrl L', 'Clear the screen (clear)'),
    ShortcutRow('Home / End', 'Line start / end'),
    ShortcutRow('Ctrl + Left / Right', 'Move by word'),
    ShortcutRow('Esc', 'Clear the current line'),
    ShortcutRow('Ctrl C / Ctrl V', 'Copy / paste (Windows Terminal)'),
    ShortcutRow('Get-Help name', 'Full help for a cmdlet'),
    ShortcutRow('name -?', 'Quick syntax'),
  ],
);

/// Panels A-D in display order.
const List<ShortcutGroup> kShortcutGroups = <ShortcutGroup>[
  kMacosShortcuts,
  kWindowsShortcuts,
  kMacosTerminal,
  kWindowsPowershell,
];

// ── E. Special symbols on a Mac (hold Option) ────────────────────────────────
const List<SymbolRow> kMacSymbols = <SymbolRow>[
  SymbolRow('Opt 2', '™', 'Trademark'),
  SymbolRow('Opt R', '®', 'Registered'),
  SymbolRow('Opt G', '©', 'Copyright'),
  SymbolRow('Opt Shift 2', '€', 'Euro'),
  SymbolRow('Opt 3', '£', 'Pound'),
  SymbolRow('Opt Y', '¥', 'Yen'),
  SymbolRow('Opt 8', '•', 'Bullet'),
  SymbolRow('Opt ;', '…', 'Ellipsis'),
  SymbolRow('Opt -', '–', 'En dash'),
  SymbolRow('Opt Shift -', '—', 'Em dash'),
  SymbolRow('Opt [ / Opt Shift [', '“ ”', 'Curly double quotes'),
  SymbolRow('Opt e, then e', 'é', 'Acute accent'),
  SymbolRow('Opt n, then n', 'ñ', 'Tilde'),
  SymbolRow('Opt u, then u', 'ü', 'Umlaut'),
  SymbolRow('Opt =', '≠', 'Not equal'),
  SymbolRow('Opt < / Opt >', '≤ ≥', 'Less / greater than or equal'),
  SymbolRow('Opt v', '√', 'Square root'),
  SymbolRow('Opt p', 'π', 'Pi'),
  SymbolRow('Opt m', 'µ', 'Micro sign'),
  SymbolRow('Opt w', '∑', 'Summation'),
  SymbolRow('Opt /', '÷', 'Division'),
  SymbolRow('Opt 0', 'º', 'Masculine ordinal (degree-like)'),
];

/// The degree-vs-ordinal caveat carried on-screen (true degree is Opt Shift 8).
const String kMacSymbolsNote =
    'The true degree sign (Opt Shift 8) gives the degree symbol; Opt 0 gives '
    'the ordinal, which looks similar. On Windows the same symbols come from the '
    'emoji panel (Win .) or a numeric Alt code; the Mac Option layer is the fast '
    'path.';

// ── F. Greek letters and symbols (RF math) ───────────────────────────────────
const List<GreekRow> kGreekLetters = <GreekRow>[
  GreekRow('α', 'Α', 'alpha', 'attenuation coefficient, angle'),
  GreekRow('β', 'Β', 'beta', 'phase constant'),
  GreekRow('γ', 'Γ', 'gamma', 'propagation constant'),
  GreekRow('δ', 'Δ', 'delta', 'change / difference'),
  GreekRow('ε', 'Ε', 'epsilon', 'permittivity'),
  GreekRow('ζ', 'Ζ', 'zeta', ''),
  GreekRow('η', 'Η', 'eta', 'efficiency'),
  GreekRow('θ', 'Θ', 'theta', 'angle'),
  GreekRow('λ', 'Λ', 'lambda', 'wavelength'),
  GreekRow('μ', 'Μ', 'mu', 'micro, permeability'),
  GreekRow('π', 'Π', 'pi', '3.14159'),
  GreekRow('ρ', 'Ρ', 'rho', 'reflection coefficient'),
  GreekRow('σ', 'Σ', 'sigma', 'sum, conductivity'),
  GreekRow('τ', 'Τ', 'tau', 'time constant'),
  GreekRow('φ', 'Φ', 'phi', 'phase, flux'),
  GreekRow('ω', 'Ω', 'omega', 'ohms, angular frequency'),
];
