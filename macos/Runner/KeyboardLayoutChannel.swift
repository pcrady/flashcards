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

    let methods = FlutterMethodChannel(
      name: "sprak/keyboard_layout/methods", binaryMessenger: messenger)
    methods.setMethodCallHandler { call, result in
      switch call.method {
      case "currentId":
        result(currentSourceId())
      case "selectByLanguage":
        result(selectByLanguage(call.arguments as? String ?? ""))
      case "selectById":
        result(selectById(call.arguments as? String ?? ""))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func stringProperty(
    _ source: TISInputSource, _ key: CFString
  ) -> String? {
    guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
  }

  private static func currentSourceId() -> String? {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    else { return nil }
    return stringProperty(source, kTISPropertyInputSourceID)
  }

  /// The user's enabled, selectable keyboard input sources.
  private static func selectableKeyboardSources() -> [TISInputSource] {
    let filter =
      [kTISPropertyInputSourceCategory as String:
         kTISCategoryKeyboardInputSource as String] as CFDictionary
    guard
      let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue()
        as? [TISInputSource]
    else { return [] }
    return list.filter { source in
      guard
        let ptr = TISGetInputSourceProperty(
          source, kTISPropertyInputSourceIsSelectCapable)
      else { return false }
      return CFBooleanGetValue(
        Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue())
    }
  }

  /// Switches to the first enabled keyboard whose language list contains
  /// [code] (e.g. "ru", "en"); false when none is installed.
  private static func selectByLanguage(_ code: String) -> Bool {
    guard !code.isEmpty else { return false }
    for source in selectableKeyboardSources() {
      guard
        let ptr = TISGetInputSourceProperty(
          source, kTISPropertyInputSourceLanguages),
        let langs = Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue()
          as? [String]
      else { continue }
      if langs.contains(where: {
        $0 == code || $0.hasPrefix("\(code)-")
      }) {
        return TISSelectInputSource(source) == noErr
      }
    }
    return false
  }

  private static func selectById(_ id: String) -> Bool {
    guard !id.isEmpty else { return false }
    for source in selectableKeyboardSources()
    where stringProperty(source, kTISPropertyInputSourceID) == id {
      return TISSelectInputSource(source) == noErr
    }
    return false
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
