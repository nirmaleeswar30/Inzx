import AVFoundation
import AudioToolbox
import AVKit
import Flutter
import MediaPlayer
import UIKit

/// `inzx/audio_routing` and `inzx/audio_output` on iOS, plus route change
/// events (`inzx/ios_route`) for AutoEQ's per-device profiles and loudness's
/// "off on the phone speaker".
///
/// iOS doesn't let an app list or pick outputs: the current route is read
/// from AVAudioSession and switching goes through the system route picker
/// (AVRoutePickerView), as BitChord-iOS's output sheet does.
final class AudioRouteChannel: NSObject, FlutterStreamHandler {
  let usbSampleRate = UsbDacSampleRate()
  private var sink: FlutterEventSink?
  private var routeObserver: NSObjectProtocol?
  private lazy var picker: AVRoutePickerView = {
    let view = AVRoutePickerView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    view.isHidden = true
    return view
  }()
  private lazy var volumeView: MPVolumeView = {
    let view = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 10, height: 10))
    view.isHidden = false
    view.alpha = 0.01
    return view
  }()

  // MARK: Route description

  private static func describe(_ port: AVAudioSessionPortDescription) -> [String: Any] {
    let isSpeaker = port.portType == .builtInSpeaker || port.portType == .builtInReceiver
    return ["name": port.portName, "isSpeaker": isSpeaker, "uid": port.uid,
            "type": port.portType.rawValue]
  }

  /// Windows' EndpointFormFactor numbering, which the Dart side shares with
  /// desktop: 1 speakers, 3 headphones, 0 unknown.
  private static func formFactor(_ type: AVAudioSession.Port) -> Int {
    switch type {
    case .builtInSpeaker, .builtInReceiver: return 1
    case .headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .usbAudio, .lineOut: return 3
    default: return 0
    }
  }

  static func currentOutput() -> [String: Any]? {
    guard let port = AVAudioSession.sharedInstance().currentRoute.outputs.first else { return nil }
    return ["key": "ios:\(port.uid)", "label": port.portName,
            "formFactor": formFactor(port.portType)]
  }

  // MARK: inzx/audio_routing

  func handleRouting(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let session = AVAudioSession.sharedInstance()
    switch call.method {
    case "getActiveDeviceName":
      let outputs = session.currentRoute.outputs.map(Self.describe)
      let active = outputs.first ?? ["name": UIDevice.current.name, "isSpeaker": true]
      var all = outputs.map { o -> [String: Any] in
        var row = o
        row["isActive"] = true
        return row
      }
      if all.isEmpty { all = [["name": UIDevice.current.name, "isSpeaker": true, "isActive": true]] }
      result(["active": ["name": active["name"] ?? "iPhone", "isSpeaker": active["isSpeaker"] ?? true],
              "all": all])
    case "openOutputPanel":
      result(showRoutePicker())
    case "getOutputInfo":
      let rate = session.sampleRate
      result([
        "mixerSampleRate": Int(rate.rounded()),
        "framesPerBuffer": Int((session.ioBufferDuration * rate).rounded()),
        "systemVolume": Int((session.outputVolume * 16).rounded()),
        "systemVolumeMax": 16,
      ])
    case "getVolume":
      result(Double(session.outputVolume))
    case "setVolume":
      let args = call.arguments as? [String: Any] ?? [:]
      let volume = (args["volume"] as? NSNumber)?.floatValue ?? session.outputVolume
      setSystemVolume(volume)
      result(true)
    case "setAudioRoute":
      // Playback-category audio follows the system route; the picker switches it.
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: inzx/audio_output

  func handleOutput(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "describe":
      let session = AVAudioSession.sharedInstance()
      let spatial = session.currentRoute.outputs.contains { $0.isSpatialAudioEnabled }
      var out: [String: Any] = [
        "bitPerfectSupported": false,
        "bitPerfectRequested": false,
        "hiResOutput": true,
        "outSampleRate": Int(session.sampleRate.rounded()),
        "outEncoding": "Float32",
        "atmosSupported": Self.canDecodeEac3 && spatial,
      ]
      if let port = session.currentRoute.outputs.first {
        out["device"] = port.portName
        if port.portType == .usbAudio { out["usbDac"] = port.portName }
      }
      if let sourceRate = usbSampleRate.sourceRate { out["sourceSampleRate"] = sourceRate }
      let rate = InzxDsp.shared().lastSampleRate
      if rate > 0 { out["trackSampleRate"] = Int(rate.rounded()) }
      result(out)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Route picker and volume

  private static let canDecodeEac3: Bool = {
    if AVURLAsset.isPlayableExtendedMIMEType("audio/mp4; codecs=\"ec-3\"") {
      return true
    }
    var format = kAudioFormatEnhancedAC3
    var size: UInt32 = 0
    return AudioFormatGetPropertyInfo(kAudioFormatProperty_Decoders,
      UInt32(MemoryLayout<AudioFormatID>.size), &format, &size) == noErr && size > 0
  }()

  private func showRoutePicker() -> Bool {
    guard let host = topViewController()?.view else { return false }
    if picker.superview == nil { host.addSubview(picker) }
    guard let button = picker.subviews.compactMap({ $0 as? UIButton }).first else { return false }
    button.sendActions(for: .touchUpInside)
    return true
  }

  /// iOS has no API for the system volume; MPVolumeView's own slider is the
  /// accepted way to move it from inside an app.
  private func setSystemVolume(_ value: Float) {
    if volumeView.superview == nil, let host = topViewController()?.view {
      host.addSubview(volumeView)
    }
    guard let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else { return }
    DispatchQueue.main.async {
      slider.setValue(max(0, min(1, value)), animated: false)
      slider.sendActions(for: .valueChanged)
    }
  }

  // MARK: FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    events(Self.currentOutput())
    routeObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.sink?(Self.currentOutput())
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
    routeObserver = nil
    sink = nil
    return nil
  }
}
