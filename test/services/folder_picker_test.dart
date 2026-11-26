import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/services/folder_picker.dart';

void main() {
  String? android(String uri, {String root = '/storage/emulated/0'}) =>
      folderPathFromUri(Uri.parse(uri), primaryStorageRoot: root);

  const provider = 'content://com.android.externalstorage.documents';

  test('internal storage folders become paths', () {
    expect(
      android('$provider/tree/primary%3AMusic'),
      '/storage/emulated/0/Music',
    );
    expect(
      android('$provider/tree/primary%3AMusic%2FRock%20%26%20Roll'),
      '/storage/emulated/0/Music/Rock & Roll',
    );
    expect(android('$provider/tree/primary%3A'), '/storage/emulated/0');
  });

  test('a document suffix after the tree id is ignored', () {
    expect(
      android('$provider/tree/primary%3AMusic/document/primary%3AMusic'),
      '/storage/emulated/0/Music',
    );
  });

  test('another user or work profile keeps its own storage root', () {
    expect(
      android('$provider/tree/primary%3AMusic', root: '/storage/emulated/10'),
      '/storage/emulated/10/Music',
    );
  });

  test('SD cards and the Documents shortcut map to their mounts', () {
    expect(
      android('$provider/tree/1A2B-3C4D%3AAlbums'),
      '/storage/1A2B-3C4D/Albums',
    );
    expect(
      android('$provider/tree/home%3AScores'),
      '/storage/emulated/0/Documents/Scores',
    );
  });

  test('folders without a path are refused', () {
    expect(
      android(
        'content://com.android.providers.downloads.documents/tree/downloads',
      ),
      isNull,
    );
    expect(
      android(
        'content://com.google.android.apps.docs.storage/tree/acc%3D1%3Bdoc%3Dabc',
      ),
      isNull,
    );
    expect(android('$provider/tree/unknownvolume%3AMusic'), isNull);
    expect(android('$provider/document/primary%3AMusic'), isNull);
  });

  test('desktop directory URIs become the path, minus the last separator', () {
    // What file_picker returns on Windows and Linux.
    String? desktop(String path, {required bool windows}) => folderPathFromUri(
      Uri.directory(path, windows: windows),
      windows: windows,
    );
    expect(desktop('/home/me/Music', windows: false), '/home/me/Music');
    expect(desktop(r'C:\Users\me\Music', windows: true), r'C:\Users\me\Music');
    expect(desktop(r'D:\', windows: true), r'D:\');
    expect(desktop('/', windows: false), '/');
  });
}
