import Flutter
import UIKit
import UniformTypeIdentifiers

/// Music folders outside the app's sandbox (On My iPhone, iCloud Drive, a
/// USB drive). A picked folder is only readable while its security scope is
/// open, and only until the app quits, so each pick is kept as a bookmark and
/// reopened on every launch (`restoreAll`). file_picker's own folder picker
/// does neither.
final class FolderAccess: NSObject, UIDocumentPickerDelegate {
  private static let defaultsKey = "inzx.folderBookmarks"
  private var pending: FlutterResult?
  private var open: [String: URL] = [:]

  private var bookmarks: [String: Data] {
    get { UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: Data] ?? [:] }
    set { UserDefaults.standard.set(newValue, forKey: Self.defaultsKey) }
  }

  func pick(_ result: @escaping FlutterResult) {
    guard pending == nil, let host = topViewController() else { return result(nil) }
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
    picker.delegate = self
    picker.allowsMultipleSelection = false
    pending = result
    host.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = pending else { return }
    pending = nil
    guard let url = urls.first else { return result(nil) }
    guard url.startAccessingSecurityScopedResource() else { return result(nil) }
    let path = url.path
    open[path] = url
    if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
      var all = bookmarks
      all[path] = data
      bookmarks = all
    }
    result(path)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pending?(nil)
    pending = nil
  }

  /// Reopens every saved folder. Returns `[{from, to}]`: the path a folder
  /// was saved under and where it resolves now (they differ when the volume
  /// or container moved), so the Dart side can update its records.
  func restoreAll() -> [[String: String]] {
    var all = bookmarks
    var moved: [[String: String]] = []
    for (saved, data) in all {
      var stale = false
      guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil,
                               bookmarkDataIsStale: &stale)
      else { continue }
      guard url.startAccessingSecurityScopedResource() else { continue }
      open[url.path] = url
      if stale || url.path != saved {
        all.removeValue(forKey: saved)
        if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
          all[url.path] = fresh
        }
      }
      moved.append(["from": saved, "to": url.path])
    }
    bookmarks = all
    return moved
  }

  func forget(_ path: String) {
    open.removeValue(forKey: path)?.stopAccessingSecurityScopedResource()
    var all = bookmarks
    all.removeValue(forKey: path)
    bookmarks = all
  }
}
