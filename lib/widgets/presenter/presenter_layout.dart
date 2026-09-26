// PresenterLayout: the full-screen, single-view layout an instructor projects
// (spec 00-presenter-layout.md §1). Stage on the left at about two-thirds of
// the width, controls in a fixed right-hand panel, both the full window
// height, and no page scroll. The controls panel scrolls internally only as a
// last resort.
//
// What the shell owns, so no tool re-implements it:
//   - the slim top bar (title, Shortcuts, theme toggle, Exit), which fades
//     out after [kPresenterBarHideDelay] without pointer movement and returns
//     on movement or keyboard focus. Its height is reserved, so nothing jumps
//     when it fades;
//   - the projector scale (PresenterScale.forWindow: 1.35x text at 1080 px
//     tall, in proportion to the window height), applied to MediaQuery's text
//     scale, and a PresenterMode ancestor painters read;
//   - the keyboard (Space, Right, R, Esc, F, Up/Down or [ ], ?) routed to the
//     tool's PresenterActions, and the "?" overlay listing only the keys the
//     tool supports;
//   - native full screen on macOS: entering presenter mode enters it, leaving
//     restores what the window was before.
//
// KEYBOARD RULES. Keys are handled on a Focus that wraps the whole layout, so
// a focused control sees a key first: a focused Slider keeps its arrows, a
// focused text field keeps every key except Esc (the first Esc leaves the
// field, the second exits). Shortcuts never fire with Cmd, Ctrl or Alt held,
// so system shortcuts (Cmd+Q, Cmd+R) are untouched.
//
// THEME: context.colors only. Motion: the bar fade is AppMotion.base, 0 with
// reduced motion (§8.8).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_color_scheme.dart';
import '../../theme/app_tokens.dart';
import '../../theme/app_typography.dart';
import '../../theme/theme_controller.dart';
import 'presenter_actions.dart';
import 'presenter_mode.dart';
import 'presenter_window.dart';

/// How long the top bar stays after the pointer last moved.
const Duration kPresenterBarHideDelay = Duration(seconds: 3);

/// Height reserved for the top bar.
const double kPresenterBarHeight = AppSpacing.xxl;

/// The controls panel is a third of the window, held inside these bounds.
/// 540 keeps a four-button transport row on one line at 1440 wide.
const double kPresenterPanelMinWidth = 540;
const double kPresenterPanelMaxWidth = 680;

class PresenterLayout extends StatefulWidget {
  const PresenterLayout({
    super.key,
    required this.title,
    required this.stage,
    required this.controls,
    this.actions = PresenterActions.none,
    this.scale,
  });

  /// Tool name for the top bar.
  final String title;

  /// The tool's stage widget (animation or plot), over the shared state.
  final Widget stage;

  /// The tool's controls widget (inputs and readouts), over the same state.
  final Widget controls;

  /// The keys this tool supports.
  final PresenterActions actions;

  /// Fixed scale. Null (the default) follows the window:
  /// PresenterScale.forWindow.
  final PresenterScale? scale;

  /// Test handles.
  static const Key stageKey = ValueKey<String>('presenter-stage');
  static const Key controlsKey = ValueKey<String>('presenter-controls');
  static const Key controlsScrollKey = ValueKey<String>(
    'presenter-controls-scroll',
  );
  static const Key barKey = ValueKey<String>('presenter-bar');
  static const Key shortcutsKey = ValueKey<String>('presenter-shortcuts');

  @override
  State<PresenterLayout> createState() => _PresenterLayoutState();
}

class _PresenterLayoutState extends State<PresenterLayout> {
  final FocusNode _keys = FocusNode(debugLabel: 'presenter-keys');
  final ScrollController _controlsScroll = ScrollController();
  Timer? _hideTimer;
  bool _pointerRecent = true;
  bool _barFocused = false;
  bool _shortcutsOpen = false;

  bool _wasFullScreen = false;
  bool _restored = false;

  PresenterWindowControl get _window => PresenterWindow.control;

  @override
  void initState() {
    super.initState();
    _armHide();
    _enterFullScreen();
  }

  @override
  void dispose() {
    _restoreWindow();
    _hideTimer?.cancel();
    _keys.dispose();
    _controlsScroll.dispose();
    super.dispose();
  }

  // ── Window ──────────────────────────────────────────────────────────────

  Future<void> _enterFullScreen() async {
    _wasFullScreen = await _window.isFullScreen();
    if (!_wasFullScreen && !_restored) await _window.setFullScreen(true);
  }

  /// Leaves full screen unless the window was already full screen before
  /// presenter mode opened. Runs once.
  void _restoreWindow() {
    if (_restored) return;
    _restored = true;
    if (!_wasFullScreen) unawaited(_window.setFullScreen(false));
  }

  Future<void> _toggleFullScreen() async {
    final bool now = await _window.isFullScreen();
    await _window.setFullScreen(!now);
  }

  void _exit() {
    _restoreWindow();
    Navigator.of(context).maybePop();
  }

  // ── Bar visibility ──────────────────────────────────────────────────────

  bool get _barVisible => _pointerRecent || _barFocused || _shortcutsOpen;

  void _armHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(kPresenterBarHideDelay, () {
      if (mounted) setState(() => _pointerRecent = false);
    });
  }

  void _onPointerMove() {
    if (!_pointerRecent) setState(() => _pointerRecent = true);
    _armHide();
  }

  void _setShortcuts(bool open) {
    if (open == _shortcutsOpen) return;
    setState(() => _shortcutsOpen = open);
    _keys.requestFocus();
  }

  // ── Keyboard ────────────────────────────────────────────────────────────

  bool _focusInTextField() {
    final BuildContext? c = FocusManager.instance.primaryFocus?.context;
    if (c == null) return false;
    return c.widget is EditableText ||
        c.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final bool repeat = event is KeyRepeatEvent;
    final LogicalKeyboardKey key = event.logicalKey;
    final HardwareKeyboard hw = HardwareKeyboard.instance;
    if (hw.isMetaPressed || hw.isControlPressed || hw.isAltPressed) {
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.escape) {
      if (repeat) return KeyEventResult.handled;
      if (_shortcutsOpen) {
        _setShortcuts(false);
      } else if (_focusInTextField()) {
        _keys.requestFocus();
      } else {
        _exit();
      }
      return KeyEventResult.handled;
    }
    if (_focusInTextField()) return KeyEventResult.ignored;

    final String? ch = event.character;
    final PresenterActions a = widget.actions;

    KeyEventResult run(VoidCallback? action, {bool allowRepeat = false}) {
      if (action == null) return KeyEventResult.ignored;
      if (repeat && !allowRepeat) return KeyEventResult.handled;
      action();
      return KeyEventResult.handled;
    }

    if (ch == '?' ||
        key == LogicalKeyboardKey.question ||
        (key == LogicalKeyboardKey.slash && hw.isShiftPressed)) {
      return run(() => _setShortcuts(!_shortcutsOpen));
    }
    if (key == LogicalKeyboardKey.space) return run(a.playPause);
    if (key == LogicalKeyboardKey.arrowRight) {
      return run(a.step, allowRepeat: true);
    }
    if (key == LogicalKeyboardKey.keyR) return run(a.reset);
    if (key == LogicalKeyboardKey.keyF) return run(_toggleFullScreen);
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.bracketRight ||
        ch == ']') {
      return run(a.sliderUp, allowRepeat: true);
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.bracketLeft ||
        ch == '[') {
      return run(a.sliderDown, allowRepeat: true);
    }
    for (final PresenterExtraKey x in a.extra) {
      if (key == x.key) return run(x.onPressed);
    }
    return KeyEventResult.ignored;
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    final double base =
        mq.textScaler.scale(AppTextSize.body) / AppTextSize.body;
    final AppColorScheme colors = context.colors;
    final bool reduceMotion = mq.disableAnimations;
    final PresenterScale scale =
        widget.scale ?? PresenterScale.forWindow(mq.size);

    return PopScope(
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) _restoreWindow();
      },
      child: MediaQuery(
        data: mq.copyWith(textScaler: TextScaler.linear(base * scale.text)),
        child: PresenterMode(
          scale: scale,
          child: Scaffold(
            backgroundColor: colors.surface0,
            body: Focus(
              focusNode: _keys,
              autofocus: true,
              onKeyEvent: _onKey,
              child: MouseRegion(
                onHover: (_) => _onPointerMove(),
                child: Stack(
                  children: <Widget>[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _bar(context, reduceMotion),
                        Expanded(child: _panes(context)),
                      ],
                    ),
                    if (_shortcutsOpen) _shortcutsOverlay(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panes(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double panel = (box.maxWidth / 3).clamp(
          kPresenterPanelMinWidth,
          kPresenterPanelMaxWidth,
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: Listener(
                // Clicking the stage takes the keys back from a text field.
                onPointerDown: (_) {
                  if (_focusInTextField()) _keys.requestFocus();
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: KeyedSubtree(
                    key: PresenterLayout.stageKey,
                    child: widget.stage,
                  ),
                ),
              ),
            ),
            VerticalDivider(width: 1, thickness: 1, color: colors.border),
            SizedBox(
              width: panel,
              child: Scrollbar(
                controller: _controlsScroll,
                child: SingleChildScrollView(
                  key: PresenterLayout.controlsScrollKey,
                  controller: _controlsScroll,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: KeyedSubtree(
                    key: PresenterLayout.controlsKey,
                    child: widget.controls,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Top bar ─────────────────────────────────────────────────────────────

  Widget _bar(BuildContext context, bool reduceMotion) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final ThemeController? theme = ThemeControllerScope.maybeOf(context);
    final bool isLight = colors.isLight;

    ButtonStyle barButton() => TextButton.styleFrom(
      foregroundColor: colors.textAccent,
      minimumSize: const Size(
        AppSpacing.minTouchTarget,
        AppSpacing.minTouchTarget,
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (bool f) => setState(() => _barFocused = f),
      child: AnimatedOpacity(
        key: PresenterLayout.barKey,
        opacity: _barVisible ? 1 : 0,
        duration: reduceMotion ? Duration.zero : AppMotion.base,
        curve: AppMotion.standardEase,
        child: Container(
          height: kPresenterBarHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: colors.surface1,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.present_to_all, color: colors.textAccent),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Tooltip(
                message: 'Keyboard shortcuts (?)',
                child: TextButton.icon(
                  onPressed: () => _setShortcuts(!_shortcutsOpen),
                  style: barButton(),
                  icon: const Icon(Icons.keyboard_outlined),
                  label: const Text('Shortcuts'),
                ),
              ),
              if (theme != null) ...<Widget>[
                const SizedBox(width: AppSpacing.xs),
                Tooltip(
                  message: isLight
                      ? 'Switch to the dark theme'
                      : 'Switch to the light theme',
                  child: TextButton.icon(
                    onPressed: () => theme.setMode(
                      isLight ? ThemeMode.dark : ThemeMode.light,
                    ),
                    style: barButton(),
                    icon: Icon(
                      isLight
                          ? Icons.dark_mode_outlined
                          : Icons.light_mode_outlined,
                    ),
                    label: Text(isLight ? 'Dark' : 'Light'),
                  ),
                ),
              ],
              const SizedBox(width: AppSpacing.xs),
              Tooltip(
                message: 'Exit presenter mode (Esc)',
                child: TextButton.icon(
                  onPressed: _exit,
                  style: barButton(),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Exit'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Shortcut overlay ────────────────────────────────────────────────────

  List<(String, String)> _shortcutRows() {
    final PresenterActions a = widget.actions;
    final String slider = a.sliderLabel ?? 'Main slider';
    return <(String, String)>[
      if (a.playPause != null) ('Space', 'Play or pause'),
      if (a.step != null) ('Right arrow', 'Step'),
      if (a.reset != null) ('R', 'Reset'),
      if (a.hasSlider) ('Up arrow or ]', '$slider up'),
      if (a.hasSlider) ('Down arrow or [', '$slider down'),
      for (final PresenterExtraKey x in a.extra) (x.keyLabel, x.description),
      if (_window.supportsFullScreen) ('F', 'Full screen on or off'),
      ('?', 'Show or hide this list'),
      ('Esc', 'Exit presenter mode (the first press leaves a text field)'),
      ('Tab', 'Move between controls; Enter presses the one in focus'),
    ];
  }

  Widget _shortcutsOverlay(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Positioned.fill(
      child: Stack(
        children: <Widget>[
          ModalBarrier(
            color: colors.scrim,
            dismissible: true,
            onDismiss: () => _setShortcuts(false),
            semanticsLabel: 'Close keyboard shortcuts',
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Semantics(
                key: PresenterLayout.shortcutsKey,
                container: true,
                explicitChildNodes: true,
                label: 'Keyboard shortcuts',
                child: Container(
                  margin: const EdgeInsets.all(AppSpacing.md),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: colors.surface2,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: colors.borderStrong),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text(
                                'Keyboard shortcuts',
                                style: text.titleMedium?.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _setShortcuts(false),
                            tooltip: 'Close shortcuts',
                            icon: const Icon(Icons.close_rounded),
                            color: colors.textSecondary,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      for (final (String key, String does) in _shortcutRows())
                        MergeSemantics(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.xxs,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                SizedBox(
                                  width: 240,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.xs,
                                        vertical: AppSpacing.xxs,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colors.inputFill,
                                        borderRadius: BorderRadius.circular(
                                          AppRadius.control,
                                        ),
                                        border: Border.all(
                                          color: colors.borderStrong,
                                        ),
                                      ),
                                      child: Text(
                                        key,
                                        style: mono.inlineCode.copyWith(
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    does,
                                    style: text.bodyMedium?.copyWith(
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
