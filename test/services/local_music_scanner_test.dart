import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:inzx/services/local_music_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUpAll(() async {
    // The scanner looks downloads up in Hive; an empty box is enough here.
    Hive.init((await Directory.systemTemp.createTemp('inzx_hive_')).path);
  });

  setUp(() async {
    root = await Directory.systemTemp.createTemp('inzx_scan_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  void touch(String relative) {
    final file = File('${root.path}${Platform.pathSeparator}$relative');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(const []);
  }

  test('finds audio in nested folders and skips trash and other files', () async {
    touch('Artist - Song.mp3');
    touch('Album/01 - Track.flac');
    touch('Album/Disc 2/02 - Track.m4a');
    touch('Album/cover.jpg');
    touch('notes.txt');
    touch(r'$RECYCLE.BIN/deleted.mp3');
    touch('System Volume Information/x.mp3');
    touch('.Trash-1000/files/old.mp3');

    final tracks = await LocalMusicScanner.scanDirectory(root.path);
    final names = tracks
        .map((t) => t.localFilePath!.split(RegExp(r'[\\/]')).last)
        .toSet();
    expect(names, {'Artist - Song.mp3', '01 - Track.flac', '02 - Track.m4a'});
  });

  test('desktop formats are scanned off Android', () async {
    touch('a.aiff');
    touch('b.wma');
    touch('c.ape');
    final tracks = await LocalMusicScanner.scanDirectory(root.path);
    expect(tracks, hasLength(Platform.isAndroid ? 0 : 3));
  });

  test('a folder that is not there finds nothing and does not throw', () async {
    final tracks = await LocalMusicScanner.scanDirectory(
      '${root.path}${Platform.pathSeparator}missing',
    );
    expect(tracks, isEmpty);
  });

  test('folder keys ignore slashes, a trailing slash and Windows case', () {
    expect(
      LocalMusicFoldersNotifier.folderKey(r'C:\Music\'),
      LocalMusicFoldersNotifier.folderKey('C:/Music'),
    );
    if (Platform.isWindows) {
      expect(
        LocalMusicFoldersNotifier.folderKey(r'c:\music'),
        LocalMusicFoldersNotifier.folderKey(r'C:\Music'),
      );
    }
  });
}
