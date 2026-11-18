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

  static var group: String {
    if let groups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String],
      let match = groups.first(where: { $0.contains("com.nirmal.inzx") }) ?? groups.first
    {
      return match
    }
    return defaultGroup
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

  static func load() -> InzxWidgetState {
    guard let data = UserDefaults(suiteName: InzxShared.group)?.data(forKey: InzxShared.stateKey),
      let state = try? JSONDecoder().decode(InzxWidgetState.self, from: data)
    else { return InzxWidgetState() }
    return state
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
