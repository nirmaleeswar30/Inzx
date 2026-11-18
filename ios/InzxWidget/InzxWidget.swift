import ImageIO
import SwiftUI
import UIKit
import WidgetKit

// Inzx's Home Screen widgets: the iOS counterparts of Android's 2x2 square
// and 4x2 wide AppWidgets. They show what WidgetSyncService last sent and
// drive playback through the intents in SharedWidget.swift.

struct InzxEntry: TimelineEntry {
  let date: Date
  let state: InzxWidgetState
  let art: UIImage?
}

struct InzxProvider: TimelineProvider {
  func placeholder(in context: Context) -> InzxEntry {
    InzxEntry(date: Date(), state: InzxWidgetState(title: "Inzx", artist: "Not playing"), art: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (InzxEntry) -> Void) {
    completion(entry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<InzxEntry>) -> Void) {
    // The app reloads the timeline whenever the song or play state changes.
    completion(Timeline(entries: [entry()], policy: .never))
  }

  private func entry() -> InzxEntry {
    InzxEntry(date: Date(), state: InzxWidgetState.load(), art: Self.loadArt())
  }

  /// The cover, decoded small: widgets have a tight memory budget and a
  /// full-size cover can exceed it.
  static func loadArt() -> UIImage? {
    guard let url = InzxShared.container?.appendingPathComponent(InzxShared.artFileName),
      let source = CGImageSourceCreateWithURL(url as CFURL, nil)
    else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 420,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      return nil
    }
    return UIImage(cgImage: image)
  }
}

// MARK: - Views

private let openPlayerURL = URL(string: "inzx://open/player")

private struct Artwork: View {
  let image: UIImage?

  var body: some View {
    if let image {
      Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
    } else {
      ZStack {
        LinearGradient(colors: [Color(white: 0.18), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
        Image(systemName: "music.note").font(.system(size: 28, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
      }
    }
  }
}

private struct ControlButton<I: AppIntent>: View {
  let intent: I
  let symbol: String
  var size: CGFloat = 18

  var body: some View {
    Button(intent: intent) {
      Image(systemName: symbol)
        .font(.system(size: size, weight: .semibold))
        .frame(maxWidth: .infinity, minHeight: 28)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(.white)
  }
}

struct InzxSquareView: View {
  let entry: InzxEntry

  var body: some View {
    let s = entry.state
    VStack(alignment: .leading, spacing: 6) {
      Spacer(minLength: 0)
      Text(s.title ?? "Not playing")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
      Text(s.artist ?? "Open Inzx to start music")
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.75))
        .lineLimit(1)
      ControlButton(intent: InzxPlayPauseIntent(), symbol: (s.isPlaying ?? false) ? "pause.fill" : "play.fill", size: 20)
        .frame(width: 44, height: 32)
        .background(.white.opacity(0.18), in: Capsule())
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    .containerBackground(for: .widget) {
      ZStack {
        Artwork(image: entry.art)
        LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
      }
    }
    .widgetURL(openPlayerURL)
  }
}

struct InzxWideView: View {
  let entry: InzxEntry

  var body: some View {
    let s = entry.state
    HStack(spacing: 14) {
      Artwork(image: entry.art)
        .frame(width: 112, height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      VStack(alignment: .leading, spacing: 4) {
        if let status = s.statusLabel, !status.isEmpty {
          Text(status).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
        }
        Text(s.title ?? "Not playing")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(.white)
          .lineLimit(2)
        Text(s.artist ?? "Open Inzx to start music")
          .font(.system(size: 13))
          .foregroundStyle(.white.opacity(0.75))
          .lineLimit(1)
        Spacer(minLength: 4)
        HStack(spacing: 0) {
          ControlButton(intent: InzxLikeIntent(), symbol: (s.isLiked ?? false) ? "heart.fill" : "heart", size: 16)
          ControlButton(intent: InzxPreviousIntent(), symbol: "backward.fill")
          ControlButton(intent: InzxPlayPauseIntent(), symbol: (s.isPlaying ?? false) ? "pause.fill" : "play.fill", size: 22)
          ControlButton(intent: InzxNextIntent(), symbol: "forward.fill")
          ControlButton(intent: InzxShuffleIntent(), symbol: "shuffle", size: 15)
            .opacity((s.shuffle ?? false) ? 1 : 0.5)
        }
      }
    }
    .containerBackground(for: .widget) {
      ZStack {
        Artwork(image: entry.art).blur(radius: 24).scaleEffect(1.3)
        Color.black.opacity(0.55)
      }
    }
    .widgetURL(openPlayerURL)
  }
}

struct InzxSquareWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "InzxSquare", provider: InzxProvider()) { entry in
      InzxSquareView(entry: entry)
    }
    .configurationDisplayName("Now Playing")
    .description("The song Inzx is playing, with play and pause.")
    .supportedFamilies([.systemSmall])
  }
}

struct InzxWideWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "InzxWide", provider: InzxProvider()) { entry in
      InzxWideView(entry: entry)
    }
    .configurationDisplayName("Now Playing")
    .description("The song Inzx is playing, with full controls.")
    .supportedFamilies([.systemMedium])
  }
}

@main
struct InzxWidgetBundle: WidgetBundle {
  var body: some Widget {
    InzxSquareWidget()
    InzxWideWidget()
  }
}
