import 'package:flutter/services.dart';

/// Reports the OS keyboard input source (e.g. "U.S.", "Russian") via a
/// native event channel. The stream emits the current layout on subscribe
/// and again every time the user switches. On platforms without the
/// native handler it simply never emits, so UI can hide the indicator.
class KeyboardLayoutService {
  static const _channel = EventChannel('sprak/keyboard_layout');

  /// A fresh stream per call — hold on to one instance per screen so the
  /// native side is subscribed exactly while it's on stage.
  static Stream<String?> layoutName() => _channel
      .receiveBroadcastStream()
      .map<String?>((e) => e is String && e.isNotEmpty ? e : null)
      .handleError((Object _) {}, test: (e) => e is MissingPluginException);
}
