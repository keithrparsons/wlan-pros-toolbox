// Wi-Fi Classroom presenter layout: one import for a tool that adopts it.
//
// HOW A TOOL ADOPTS PRESENTER MODE (worked example: Modulation Simulator;
// the long form is myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/
// 00-presenter-ADOPTION.md).
//
//  1. ONE STATE OBJECT. Every input, every run value and every timer lives in
//     a ChangeNotifier the screen's State creates and disposes. Timers and
//     Tickers belong to that object (construct `Ticker(onTick)` directly, not
//     via a TickerProvider: a route under the presenter is muted, and the run
//     must keep going). View-local objects stay in the views: a
//     ScrollController or a TextPainter cache can attach to only one view,
//     and the normal screen stays mounted underneath the presenter.
//
//  2. TWO WIDGETS. `<Tool>Stage(controller:)` is the picture;
//     `<Tool>Controls(controller:)` is inputs and readouts. Each wraps its
//     build in a ListenableBuilder on the controller. The phone screen stacks
//     them in its scroll view; nothing else changes on the phone.
//
//  3. PRESENTER ARRANGEMENT. Inside a PresenterLayout the stage gets a BOUNDED
//     box (about two-thirds of the window, full height) and the controls a
//     fixed-width panel. `PresenterMode.isActive(context)` tells a widget
//     which arrangement to build: the stage fills its box (fit plots to the
//     height with a LayoutBuilder; never a page scroll), and the controls
//     drop phone-only prose and put rarely used settings behind a disclosure
//     until they fit at 1920x1080 and 1440x900.
//
//  4. SCALE. Text grows by itself (the layout raises MediaQuery's text
//     scale). Painters read `PresenterMode.scaleOf(context)` where they are
//     built and pass it in: `strokeWidth(w)`, `markerSize(r)`, `paintFont(px)`
//     for their own TextPainters, `headlineStyle(style)` for the one number
//     the lesson is about. Outside presenter mode the scale is 1.0, so no
//     branch is needed.
//
//  5. KEYS. Expose `PresenterActions get presenterActions` on the controller
//     (play/pause, step, reset, and the main slider down/up with its label);
//     leave out what the tool does not have.
//
//  6. ENTRY. Add `PresentButton(toolRoute:, builder:)` to the AppBar actions;
//     the builder returns `PresenterLayout(title:, stage:, controls:,
//     actions:)` over the screen's controller. Add one line to the tool's
//     help (howToUse) naming the Present button and the keys.
//
//  7. TEST. One presenter test at 1920x1080: no overflow, no page scroll,
//     and play/step by keyboard where the tool has them. Keep every existing
//     test green.

export 'present_button.dart';
export 'presenter_actions.dart';
export 'presenter_disclosure.dart';
export 'presenter_layout.dart';
export 'presenter_mode.dart';
export 'presenter_window.dart';
