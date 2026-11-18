import AVFoundation
import Flutter
import UIKit

/// Inzx's iOS native side. Channel names match the Android ones where the
/// Dart code already talks to them (`inzx/audio_routing`, `inzx/audio_output`,
/// `inzx/widget`); the rest are iOS-only (`inzx/ios`, `inzx/ios_dsp`).
public final class InzxIosPlugin: NSObject, FlutterPlugin {
  private let route = AudioRouteChannel()
  private let folders = FolderAccess()
  private let widget = WidgetBridge()
  private var observers: [NSObjectProtocol] = []

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = InzxIosPlugin()
    let messenger = registrar.messenger()

    let ios = FlutterMethodChannel(name: "inzx/ios", binaryMessenger: messenger)
    ios.setMethodCallHandler { call, result in instance.handleIos(call, result) }

    let dsp = FlutterMethodChannel(name: "inzx/ios_dsp", binaryMessenger: messenger)
    dsp.setMethodCallHandler { call, result in instance.handleDsp(call, result) }

    let routing = FlutterMethodChannel(name: "inzx/audio_routing", binaryMessenger: messenger)
    routing.setMethodCallHandler { call, result in instance.route.handleRouting(call, result) }

    let output = FlutterMethodChannel(name: "inzx/audio_output", binaryMessenger: messenger)
    output.setMethodCallHandler { call, result in instance.route.handleOutput(call, result) }

    let routeEvents = FlutterEventChannel(name: "inzx/ios_route", binaryMessenger: messenger)
    routeEvents.setStreamHandler(instance.route)

    let widgetChannel = FlutterMethodChannel(name: "inzx/widget", binaryMessenger: messenger)
    instance.widget.attach(widgetChannel)
    widgetChannel.setMethodCallHandler { call, result in instance.widget.handle(call, result) }

    instance.observeJustAudio()
    registrar.publish(instance)
  }

  /// just_audio (our fork) announces every AVPlayerItem it builds; each gets
  /// the DSP tap for its player.
  private func observeJustAudio() {
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(forName: Notification.Name("JustAudioPlayerItemCreated"), object: nil, queue: nil) {
        note in
        guard let item = note.object as? AVPlayerItem,
          let playerId = note.userInfo?["playerId"] as? String
        else { return }
        InzxDsp.shared().attach(to: item, playerId: playerId)
      })
  }

  // MARK: - inzx/ios

  private func handleIos(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "excludeFromBackup":
      guard let path = args["path"] as? String else { return result(false) }
      var url = URL(fileURLWithPath: path)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      do {
        try url.setResourceValues(values)
        result(true)
      } catch {
        result(false)
      }
    case "pickFolder":
      folders.pick(result)
    case "restoreFolders":
      result(folders.restoreAll())
    case "forgetFolder":
      if let path = args["path"] as? String { folders.forget(path) }
      result(nil)
    case "isPad":
      result(UIDevice.current.userInterfaceIdiom == .pad)
    case "homeDirectory":
      result(NSHomeDirectory())
    case "holdBackgroundTime":
      let seconds = (args["seconds"] as? NSNumber)?.doubleValue ?? 20
      holdBackgroundTime(seconds)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  /// A background-task window, so the Dart side can finish starting the
  /// next song after one ended with the app in the background.
  private func holdBackgroundTime(_ seconds: Double) {
    let app = UIApplication.shared
    if backgroundTask != .invalid { app.endBackgroundTask(backgroundTask) }
    backgroundTask = app.beginBackgroundTask(withName: "inzx.next-track") { [weak self] in
      guard let self else { return }
      app.endBackgroundTask(self.backgroundTask)
      self.backgroundTask = .invalid
    }
    let task = backgroundTask
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
      guard let self, self.backgroundTask == task, task != .invalid else { return }
      app.endBackgroundTask(task)
      self.backgroundTask = .invalid
    }
  }

  // MARK: - inzx/ios_dsp

  private func handleDsp(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "setChain":
      let filters = args["filters"] as? [[AnyHashable: Any]] ?? []
      let preamp = (args["preampDb"] as? NSNumber)?.doubleValue ?? 0
      InzxDsp.shared().setFilters(filters, preampDb: preamp)
      result(nil)
    case "setTrackGain":
      if let id = args["playerId"] as? String {
        let gain = (args["gain"] as? NSNumber)?.doubleValue ?? 1
        InzxDsp.shared().setGain(gain, forPlayer: id)
      }
      result(nil)
    case "stats":
      result([
        "framesProcessed": InzxDsp.shared().framesProcessed,
        "sampleRate": InzxDsp.shared().lastSampleRate,
      ])
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

/// The key window's top view controller, for presenting pickers.
func topViewController() -> UIViewController? {
  let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
  let window =
    scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
  var top = window?.rootViewController
  while let presented = top?.presentedViewController { top = presented }
  return top
}
