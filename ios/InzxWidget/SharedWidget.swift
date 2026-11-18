import AppIntents
import Foundation

// Compiled into both the app and the InzxWidget extension (configure_xcode.rb
// adds files named Shared* to Runner too). The playback intents must live in
// the app as well: iOS runs an AudioPlaybackIntent in the app's own process,
// where inzx_ios's WidgetBridge passes it on to the Dart side.

/// The App Group the app and the widget share. Sideloaders may rename it
/// when they re-sign; AltStore lists the renamed groups in Info.plist.
enum InzxShared {
  static let defaultGroup = "group.com.nirmal.inzx"
  static let stateKey = "inzx.widget.state"
  static let artFileName = "widget_art.jpg"
  static let actionNotification = Notification.Name("InzxWidgetAction")

  /// The group this bundle is really entitled to. Sideloaders re-sign with
  /// their own team and rename the group (AltStore lists the new name under
  /// `ALTAppGroups`, often only in the app's Info.plist, not the widget's).
  /// The signing profile names the groups each bundle actually has, so it's
  /// read first; a candidate counts only if iOS gives a container for it.
  static let group: String = {
    var candidates = provisionedGroups()
    candidates += altGroups(Bundle.main.infoDictionary)
    let bundle = Bundle.main.bundleURL
    if bundle.pathExtension == "appex" {
      // The widget: also the containing app's Info.plist.
      let app = bundle.deletingLastPathComponent().deletingLastPathComponent()
      candidates += altGroups(NSDictionary(contentsOf: app.appendingPathComponent("Info.plist")) as? [String: Any])
    }
    candidates.append(defaultGroup)
    for candidate in candidates
    where FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: candidate) != nil {
      return candidate
    }
    return candidates.first ?? defaultGroup
  }()

  private static func altGroups(_ info: [String: Any]?) -> [String] {
    guard let groups = info?["ALTAppGroups"] as? [String] else { return [] }
    return groups.filter { $0.contains("com.nirmal.inzx") } + groups.filter { !$0.contains("com.nirmal.inzx") }
  }

  /// `com.apple.security.application-groups` from embedded.mobileprovision,
  /// a CMS envelope around a plain XML plist.
  private static func provisionedGroups() -> [String] {
    guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
      let data = try? Data(contentsOf: url),
      let start = data.range(of: Data("<?xml".utf8)),
      let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
      let plist = try? PropertyListSerialization.propertyList(
        from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil) as? [String: Any],
      let entitlements = plist["Entitlements"] as? [String: Any],
      let groups = entitlements["com.apple.security.application-groups"] as? [String]
    else { return [] }
    return groups
  }

  static var container: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
  }

  /// Hands a widget button to the app (see WidgetBridge in inzx_ios).
  static func send(_ action: String) {
    NotificationCenter.default.post(name: actionNotification, object: nil, userInfo: ["action": action])
  }
}

/// What the app last told the widget (WidgetSyncService's snapshot).
struct InzxWidgetState: Codable {
  var trackId: String?
  var title: String?
  var artist: String?
  var isPlaying: Bool?
  var hasTrack: Bool?
  var isLiked: Bool?
  var shuffle: Bool?
  var positionMs: Double?
  var durationMs: Double?
  var statusLabel: String?
  var artVersion: Double?
  var updatedAt: Double?

  /// Read leniently, field by field: one value of an unexpected type must
  /// not blank the whole widget.
  static func load() -> InzxWidgetState {
    guard let data = UserDefaults(suiteName: InzxShared.group)?.data(forKey: InzxShared.stateKey),
      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return InzxWidgetState() }
    func string(_ key: String) -> String? { json[key] as? String }
    func bool(_ key: String) -> Bool? { (json[key] as? NSNumber)?.boolValue }
    func double(_ key: String) -> Double? { (json[key] as? NSNumber)?.doubleValue }
    return InzxWidgetState(
      trackId: string("trackId"),
      title: string("title"),
      artist: string("artist"),
      isPlaying: bool("isPlaying"),
      hasTrack: bool("hasTrack"),
      isLiked: bool("isLiked"),
      shuffle: bool("shuffle"),
      positionMs: double("positionMs"),
      durationMs: double("durationMs"),
      statusLabel: string("statusLabel"),
      artVersion: double("artVersion"),
      updatedAt: double("updatedAt"))
  }
}

// MARK: - Playback intents

struct InzxPlayPauseIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Play or Pause"
  static let description = IntentDescription("Plays or pauses Inzx.")

  init() {}

  func perform() async throws -> some IntentResult {
    InzxShared.send("playPause")
    return .result()
  }
}

struct InzxNextIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Next Song"
  static let description = IntentDescription("Skips to the next song in Inzx.")

  init() {}

  func perform() async throws -> some IntentResult {
    InzxShared.send("next")
    return .result()
  }
}

struct InzxPreviousIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Previous Song"
  static let description = IntentDescription("Goes back to the previous song in Inzx.")

  init() {}

  func perform() async throws -> some IntentResult {
    InzxShared.send("previous")
    return .result()
  }
}

struct InzxLikeIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Like Song"
  static let description = IntentDescription("Likes or unlikes the song Inzx is playing.")

  init() {}

  func perform() async throws -> some IntentResult {
    InzxShared.send("like")
    return .result()
  }
}

struct InzxShuffleIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Shuffle"
  static let description = IntentDescription("Turns shuffle on or off in Inzx.")

  init() {}

  func perform() async throws -> some IntentResult {
    InzxShared.send("shuffle")
    return .result()
  }
}
