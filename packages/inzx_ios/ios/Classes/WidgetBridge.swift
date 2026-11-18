import Flutter
import Foundation
import WidgetKit

/// The App Group the app shares with its widget. Sideloaders re-sign with
/// their own team and may rename the group; AltStore lists the renamed ones
/// under `ALTAppGroups` in Info.plist, so that wins when present.
enum InzxAppGroup {
  static let defaultIdentifier = "group.com.nirmal.inzx"

  static var identifier: String {
    if let groups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String],
      let match = groups.first(where: { $0.contains("com.nirmal.inzx") }) ?? groups.first
    {
      return match
    }
    return defaultIdentifier
  }

  static var defaults: UserDefaults? { UserDefaults(suiteName: identifier) }

  static var container: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
  }
}

/// `inzx/widget` on iOS: the Dart side's WidgetSyncService sends the same
/// playback snapshot it sends Android's AppWidgets; this writes it where the
/// WidgetKit extension reads it (App Group defaults + an artwork file) and
/// asks WidgetKit to redraw. The widget's buttons are App Intents running in
/// this process; they post `InzxWidgetAction`, which goes back to Dart.
final class WidgetBridge: NSObject {
  static let stateKey = "inzx.widget.state"
  static let artFileName = "widget_art.jpg"
  static let actionNotification = Notification.Name("InzxWidgetAction")

  private weak var channel: FlutterMethodChannel?
  private var dartReady = false
  private var pendingActions: [String] = []
  private var state: [String: Any] = [:]
  private var lastReload = Date.distantPast
  private var reloadScheduled = false

  func attach(_ channel: FlutterMethodChannel) {
    self.channel = channel
    NotificationCenter.default.addObserver(
      self, selector: #selector(onAction(_:)), name: Self.actionNotification, object: nil)
  }

  func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "syncPlaybackState":
      if let args = call.arguments as? [String: Any] { merge(args) }
      result(true)
    case "refreshWidget":
      scheduleReload()
      result(true)
    case "actionsReady":
      dartReady = true
      let queued = pendingActions
      pendingActions.removeAll()
      queued.forEach(send)
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func merge(_ args: [String: Any]) {
    let trackChanged = (args["trackId"] as? String) != (state["trackId"] as? String)
    for (key, value) in args where key != "artBytes" {
      state[key] = value is NSNull ? nil : value
    }
    if let art = args["artBytes"] as? FlutterStandardTypedData, let dir = InzxAppGroup.container {
      try? art.data.write(to: dir.appendingPathComponent(Self.artFileName), options: .atomic)
      state["artVersion"] = Date().timeIntervalSince1970
    } else if trackChanged, args["title"] != nil, let dir = InzxAppGroup.container {
      // A new song whose cover hasn't arrived: don't show the last one's.
      try? FileManager.default.removeItem(at: dir.appendingPathComponent(Self.artFileName))
      state["artVersion"] = 0
    }
    state["updatedAt"] = Date().timeIntervalSince1970
    let snapshot = state.compactMapValues { v -> Any? in
      switch v {
      case is String, is NSNumber, is Bool, is Int, is Double: return v
      default: return nil
      }
    }
    if let data = try? JSONSerialization.data(withJSONObject: snapshot) {
      InzxAppGroup.defaults?.set(data, forKey: Self.stateKey)
    }
    scheduleReload()
  }

  /// WidgetKit budgets reloads; an app playing audio is exempt, but there's
  /// no point redrawing more than a few times a second either.
  private func scheduleReload() {
    if reloadScheduled { return }
    let wait = max(0, 0.5 - Date().timeIntervalSince(lastReload))
    reloadScheduled = true
    DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
      guard let self else { return }
      self.reloadScheduled = false
      self.lastReload = Date()
      WidgetCenter.shared.reloadAllTimelines()
    }
  }

  @objc private func onAction(_ note: Notification) {
    guard let action = note.userInfo?["action"] as? String else { return }
    DispatchQueue.main.async {
      if self.dartReady { self.send(action) } else { self.pendingActions.append(action) }
    }
  }

  private func send(_ action: String) {
    channel?.invokeMethod("widgetAction", arguments: ["action": action])
  }
}
