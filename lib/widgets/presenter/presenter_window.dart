// PresenterWindow: native full screen for presenter mode.
//
// macOS: a MethodChannel handled in macos/Runner/MainFlutterWindow.swift,
// which calls NSWindow.toggleFullScreen(nil) and reports the state. No package
// dependency. Every other platform (Windows, Linux, web, iOS, Android) gets a
// no-op: presenter mode still works in whatever window it has (spec §1).
//
// Tests swap [PresenterWindow.control] for a fake and restore it after.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Full-screen control for the app's window.
abstract class PresenterWindowControl {
  /// Whether this platform has a native full screen to toggle (F key).
  bool get supportsFullScreen;

  /// Whether the window is full screen now.
  Future<bool> isFullScreen();

  /// Enters or leaves full screen. Returns the state asked for (the macOS
  /// transition animates, so the state reported right away would be stale).
  Future<bool> setFullScreen(bool fullScreen);
}

/// The macOS channel. Unsupported platforms answer false and do nothing.
class MethodChannelPresenterWindow implements PresenterWindowControl {
  const MethodChannelPresenterWindow();

  static const MethodChannel channel = MethodChannel(
    'com.wlanpros.toolbox/window',
  );

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  @override
  bool get supportsFullScreen => supported;

  @override
  Future<bool> isFullScreen() async {
    if (!supported) return false;
    try {
      return await channel.invokeMethod<bool>('isFullScreen') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> setFullScreen(bool fullScreen) async {
    if (!supported) return false;
    try {
      return await channel.invokeMethod<bool>('setFullScreen', fullScreen) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

/// The app-wide handle. Replace in tests.
class PresenterWindow {
  PresenterWindow._();

  static PresenterWindowControl control = const MethodChannelPresenterWindow();
}
