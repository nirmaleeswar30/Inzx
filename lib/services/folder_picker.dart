import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

/// The folder the user picked is not on the device's own storage (a cloud
/// folder, or the Downloads shortcut), so it has no path to read or write.
class UnsupportedFolderException implements Exception {
  const UnsupportedFolderException();

  @override
  String toString() =>
      "That folder can't be used. Pick one on your phone's storage or SD card; "
      'cloud folders and the Downloads shortcut have no file path.';
}

/// Lets the user pick a folder and returns its filesystem path, or null if
/// they cancel.
///
/// The app reads music folders and writes downloads with dart:io, so it needs
/// a path. Android hands the pick back as a `content://` tree URI; for a folder
/// on the device's storage that URI names the path, which the app may read
/// audio from by path (READ_MEDIA_AUDIO). Throws [UnsupportedFolderException]
/// for any other folder.
Future<String?> pickFolderPath({String? dialogTitle}) async {
  final uri = await FilePicker.pickDirectory(dialogTitle: dialogTitle);
  if (uri == null) return null;
  final path = folderPathFromUri(
    uri,
    primaryStorageRoot: Platform.isAndroid ? await _primaryStorageRoot() : null,
  );
  if (path == null) throw const UnsupportedFolderException();
  return path;
}

/// The filesystem path [uri] names, or null if it names none.
///
/// A `file` URI (Windows, Linux) is the path itself. On Android, a tree URI
/// from the external storage provider carries a document id like
/// `primary:Music/Rock`: the volume, then the path within it.
@visibleForTesting
String? folderPathFromUri(
  Uri uri, {
  String? primaryStorageRoot,
  bool? windows,
}) {
  if (uri.scheme == 'file') {
    // Desktop builds a directory URI, whose path ends in a separator. Saved
    // folders don't, so a repeat pick must not differ by it.
    final path = uri.toFilePath(windows: windows);
    final trimmed = path.replaceFirst(RegExp(r'[\\/]+$'), '');
    final isRoot = trimmed.isEmpty || RegExp(r'^[A-Za-z]:$').hasMatch(trimmed);
    return isRoot ? path : trimmed;
  }
  if (uri.scheme != 'content' ||
      uri.host != 'com.android.externalstorage.documents') {
    return null;
  }
  // /tree/<document id>, sometimes followed by /document/<document id>.
  final segments = uri.pathSegments;
  final tree = segments.indexOf('tree');
  if (tree < 0 || tree + 1 >= segments.length) return null;
  final documentId = segments[tree + 1];
  final colon = documentId.indexOf(':');
  if (colon <= 0) return null;
  final volume = documentId.substring(0, colon);
  final relative = documentId.substring(colon + 1);

  final primary = primaryStorageRoot ?? '/storage/emulated/0';
  final String root;
  if (volume == 'primary') {
    root = primary;
  } else if (volume == 'home') {
    // The Documents folder, offered on its own by some Android versions.
    root = '$primary/Documents';
  } else if (RegExp(r'^[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}$').hasMatch(volume)) {
    // A removable volume (SD card, USB drive), mounted by its id.
    root = '/storage/$volume';
  } else {
    return null;
  }
  return relative.isEmpty ? root : '$root/$relative';
}

/// The shared storage root of the current user: `/storage/emulated/0`, or
/// another number under a work profile or a second user.
Future<String> _primaryStorageRoot() async {
  // This app's external files folder lies inside that root:
  // <root>/Android/data/<package>/files.
  final path = (await getExternalStorageDirectory())?.path;
  if (path != null) {
    final android = path.indexOf('/Android/');
    if (android > 0) return path.substring(0, android);
  }
  return '/storage/emulated/0';
}
