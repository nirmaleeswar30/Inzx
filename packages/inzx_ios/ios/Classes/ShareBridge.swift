import Flutter
import Photos
import UIKit

/// `inzx/share` on iOS: the share sheet's direct targets, as ShareBridge.kt
/// gives them on Android.
///
/// - Instagram: the card goes into Photos and Instagram opens on it
///   (`instagram://library`), on its new-post screen where Story, Post or
///   Reel is picked, much as Android's send lands in Instagram's chooser.
///   Its Stories-only link needs a registered Facebook App ID, which Inzx
///   doesn't have. The link, if any, is left on the clipboard to paste.
/// - Snapchat: sending straight into Snapchat needs Snap's Creative Kit and
///   a registered client ID, so the card opens in the system share sheet,
///   where Snapchat's own share extension takes it.
/// - Save: adds the card to Photos (add-only access).
final class ShareBridge {
  private static let schemes = ["instagram": "instagram://", "snapchat": "snapchat://"]

  func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "installedTargets":
      result(
        Self.schemes.compactMap { (name, scheme) -> String? in
          guard let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) else { return nil }
          return name
        })
    case "shareImage":
      guard let target = args["target"] as? String, let path = args["path"] as? String else {
        result(false)
        return
      }
      let text = args["text"] as? String
      switch target {
      case "instagram": shareToInstagram(path, text: text, result)
      case "snapchat": presentShareSheet(path, text: text, result)
      default: result(false)
      }
    case "saveImage":
      guard let path = args["path"] as? String else {
        result(false)
        return
      }
      saveToPhotos(path) { id in result(id != nil) }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func shareToInstagram(_ path: String, text: String?, _ result: @escaping FlutterResult) {
    saveToPhotos(path) { id in
      guard let id,
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
        let url = URL(string: "instagram://library?LocalIdentifier=\(encoded)")
      else {
        result(false)
        return
      }
      if let text, !text.isEmpty { UIPasteboard.general.string = text }
      UIApplication.shared.open(url) { opened in result(opened) }
    }
  }

  private func presentShareSheet(_ path: String, text: String?, _ result: @escaping FlutterResult) {
    guard let image = UIImage(contentsOfFile: path), let top = topViewController() else {
      result(false)
      return
    }
    var items: [Any] = [image]
    if let text, !text.isEmpty { items.append(text) }
    let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
    if let popover = sheet.popoverPresentationController {
      // iPad: anchored mid-screen, as share_plus is (see IpadAnchoredShare).
      popover.sourceView = top.view
      popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
      popover.permittedArrowDirections = []
    }
    top.present(sheet, animated: true)
    result(true)
  }

  /// Adds the image at [path] to Photos; the new asset's identifier, or nil.
  private func saveToPhotos(_ path: String, _ done: @escaping (String?) -> Void) {
    let finish: (String?) -> Void = { id in DispatchQueue.main.async { done(id) } }
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else {
        finish(nil)
        return
      }
      var identifier: String?
      PHPhotoLibrary.shared().performChanges({
        let request = PHAssetChangeRequest.creationRequestForAssetFromImage(
          atFileURL: URL(fileURLWithPath: path))
        identifier = request?.placeholderForCreatedAsset?.localIdentifier
      }) { ok, _ in
        finish(ok ? identifier : nil)
      }
    }
  }
}
