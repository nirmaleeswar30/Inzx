import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/core/utils/platform_utils.dart';

void main() {
  const home = '/var/mobile/Containers/Data/Application/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE';
  const old = '/var/mobile/Containers/Data/Application/11111111-2222-3333-4444-555555555555';

  test('moves a path from an old container to the current one', () {
    expect(
      rebaseContainerPath('$old/Documents/Downloads/a b.m4a', home),
      '$home/Documents/Downloads/a b.m4a',
    );
  });

  test('handles the /private prefix iOS sometimes reports', () {
    expect(
      rebaseContainerPath('/private$old/Library/Caches/x.flac', home),
      '$home/Library/Caches/x.flac',
    );
  });

  test('leaves current-container and outside paths alone', () {
    expect(rebaseContainerPath('$home/Documents/x.mp3', home), '$home/Documents/x.mp3');
    const shared = '/private/var/mobile/Containers/Shared/AppGroup/'
        '99999999-8888-7777-6666-555555555555/File Provider Storage/Music/x.mp3';
    expect(rebaseContainerPath(shared, home), shared);
    expect(rebaseContainerPath(r'C:\Music\x.mp3', home), r'C:\Music\x.mp3');
  });
}
