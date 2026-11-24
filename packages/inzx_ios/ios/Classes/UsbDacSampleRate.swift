import AVFoundation
import AudioToolbox
import CoreMedia

/// AVAudioSession has one sample rate for all players. Only request a rate when
/// one player is using the USB output, so a crossfade cannot retune it twice.
final class UsbDacSampleRate {
  private struct ObservedPlayer {
    weak var player: AVPlayer?
    let observations: [NSKeyValueObservation]
  }

  private let session = AVAudioSession.sharedInstance()
  private var players: [ObjectIdentifier: ObservedPlayer] = [:]
  private var observers: [NSObjectProtocol] = []
  private weak var currentItem: AVPlayerItem?
  private var loadFormat: Task<Void, Never>?
  private var sampleRate: Double?
  private var request: (route: String, rate: Double)?
  private var originalPreference: Double?

  var sourceRate: Int? {
    guard usbOutput != nil else { return nil }
    return sampleRate.map { Int($0.rounded()) }
  }

  private var usbOutput: AVAudioSessionPortDescription? {
    guard session.currentRoute.outputs.count == 1,
          let port = session.currentRoute.outputs.first, port.portType == .usbAudio
    else { return nil }
    return port
  }

  init() {
    let center = NotificationCenter.default
    observers.append(center.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: session, queue: .main
    ) { [weak self] _ in self?.refresh() })
    observers.append(center.addObserver(
      forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main
    ) { [weak self] _ in
      self?.request = nil
      self?.originalPreference = nil
      self?.refresh()
    })
  }

  deinit {
    loadFormat?.cancel()
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }

  func observe(_ player: AVPlayer) {
    let item = player.observe(\.currentItem) { [weak self] _, _ in
      DispatchQueue.main.async { self?.refresh() }
    }
    let status = player.observe(\.timeControlStatus) { [weak self] _, _ in
      DispatchQueue.main.async { self?.refresh() }
    }
    players[ObjectIdentifier(player)] = ObservedPlayer(player: player, observations: [item, status])
    refresh()
  }

  func remove(_ player: AVPlayer) {
    players.removeValue(forKey: ObjectIdentifier(player))
    refresh()
  }

  private func refresh() {
    guard let usb = usbOutput else {
      clearItem()
      restorePreference()
      return
    }

    let active = players.values.compactMap(\.player).filter { $0.timeControlStatus != .paused }
    guard active.count == 1, let item = active.first?.currentItem else {
      clearItem()
      return
    }
    if currentItem === item {
      applyRate(on: usb)
      return
    }

    clearItem()
    currentItem = item
    loadFormat = Task { @MainActor [weak self] in
      let rate = try? await Self.audioSampleRate(of: item.asset)
      guard !Task.isCancelled, let self, self.currentItem === item,
            let usb = self.usbOutput else { return }
      self.sampleRate = rate
      if rate != nil {
        self.applyRate(on: usb)
      } else {
        // Unknown formats and native Dolby playback use the system's rate.
        self.restorePreference()
      }
    }
  }

  private func clearItem() {
    loadFormat?.cancel()
    loadFormat = nil
    currentItem = nil
    sampleRate = nil
  }

  private func applyRate(on usb: AVAudioSessionPortDescription) {
    guard let sampleRate, request?.route != usb.uid || request?.rate != sampleRate else { return }
    request = (usb.uid, sampleRate)

    let previous = session.preferredSampleRate
    do {
      try session.setPreferredSampleRate(sampleRate)
      if originalPreference == nil { originalPreference = previous }
    } catch {
      // The DAC or the session declined the request. Playback can continue.
    }
  }

  private func restorePreference() {
    request = nil
    guard let originalPreference else { return }
    self.originalPreference = nil
    try? session.setPreferredSampleRate(originalPreference)
  }

  private static func audioSampleRate(of asset: AVAsset) async throws -> Double? {
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    guard tracks.count == 1, let track = tracks.first else { return nil }
    let formats = try await track.load(.formatDescriptions)
    guard formats.count == 1, let format = formats.first,
          let audio = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
          audio.mFormatID != kAudioFormatAC3, audio.mFormatID != kAudioFormatEnhancedAC3,
          audio.mSampleRate.isFinite, (8_000...768_000).contains(audio.mSampleRate)
    else { return nil }
    return audio.mSampleRate
  }
}
