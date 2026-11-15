import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/core/utils/open_once.dart';

void main() {
  test('a second open of the same sheet is ignored while it is open', () async {
    final closing = Completer<String>();
    var opens = 0;
    Future<String?> open() {
      opens++;
      return closing.future;
    }

    final first = openOnce('sheet', open);
    expect(isOpen('sheet'), isTrue);
    expect(await openOnce('sheet', open), isNull);
    expect(opens, 1);

    closing.complete('picked');
    expect(await first, 'picked');
    expect(isOpen('sheet'), isFalse);
  });

  test('different sheets can be open together', () async {
    final a = Completer<void>();
    final b = Completer<void>();
    final first = openOnce('a', () => a.future);
    final second = openOnce('b', () => b.future);
    expect(isOpen('a') && isOpen('b'), isTrue);
    a.complete();
    b.complete();
    await Future.wait([first, second]);
  });

  test('it can open again once closed, even if opening failed', () async {
    await expectLater(
      openOnce<void>('sheet', () => Future.error(StateError('boom'))),
      throwsStateError,
    );
    var opened = false;
    await openOnce<void>('sheet', () async => opened = true);
    expect(opened, isTrue);
  });
}
