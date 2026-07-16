import 'package:flutter/services.dart';

/// Reports the OS keyboard input source (e.g. "U.S.", "Russian") via a
/// native event channel. The stream emits the current layout on subscribe
/// and again every time the user switches. On platforms without the
/// native handler it simply never emits, so UI can hide the indicator.
class KeyboardLayoutService {
  static const _channel = EventChannel('sprak/keyboard_layout');
  static const _methods = MethodChannel('sprak/keyboard_layout/methods');

  /// A fresh stream per call — hold on to one instance per screen so the
  /// native side is subscribed exactly while it's on stage.
  static Stream<String?> layoutName() => _channel
      .receiveBroadcastStream()
      .map<String?>((e) => e is String && e.isNotEmpty ? e : null)
      .handleError((Object _) {}, test: (e) => e is MissingPluginException);

  /// Stable ID of the active input source (for restoring it later), or
  /// null when unavailable.
  static Future<String?> currentId() async {
    try {
      return await _methods.invokeMethod<String>('currentId');
    } on MissingPluginException {
      return null;
    }
  }

  /// Switches the OS keyboard to the first enabled layout matching the
  /// ISO language [code] (e.g. "ru", "en"). Returns false when the user
  /// has no such layout installed or switching isn't supported.
  static Future<bool> selectForLanguage(String code) async {
    try {
      return await _methods.invokeMethod<bool>('selectByLanguage', code) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Switches back to the input source with [id] (from [currentId]).
  static Future<bool> selectById(String id) async {
    try {
      return await _methods.invokeMethod<bool>('selectById', id) ?? false;
    } on MissingPluginException {
      return false;
    }
  }
}
