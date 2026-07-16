import Carbon
import Cocoa
import FlutterMacOS

/// Streams the localized name of the active keyboard input source
/// (e.g. "U.S.", "Russian") to Flutter over the "sprak/keyboard_layout"
/// event channel, emitting the current value on listen and again whenever
/// the user switches input sources.
class KeyboardLayoutChannel: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterEventChannel(
      name: "sprak/keyboard_layout", binaryMessenger: messenger)
    channel.setStreamHandler(KeyboardLayoutChannel())
  }

  private static func currentLayoutName() -> String {
    guard
      let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
      let ptr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName)
    else { return "" }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    DistributedNotificationCenter.default().addObserver(
      self,
      selector: #selector(layoutChanged),
      name: NSNotification.Name(
        kTISNotifySelectedKeyboardInputSourceChanged as String),
      object: nil,
      suspensionBehavior: .deliverImmediately)
    events(Self.currentLayoutName())
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    DistributedNotificationCenter.default().removeObserver(self)
    eventSink = nil
    return nil
  }

  @objc private func layoutChanged() {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(Self.currentLayoutName())
    }
  }
}
