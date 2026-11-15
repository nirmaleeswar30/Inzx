import 'dart:async';

final Set<Object> _open = {};

/// Opens a sheet or dialog unless the same one ([key]) is already open, and
/// returns what it returns (null when it was already open).
///
/// A second tap could otherwise stack a second copy: on desktop the player
/// bar and top bar sit above the app's Navigator, so a sheet's barrier
/// doesn't cover them and their buttons stay clickable under it; anywhere, a
/// quick double tap lands before the first sheet's barrier is up.
Future<T?> openOnce<T>(Object key, Future<T?> Function() open) async {
  if (!_open.add(key)) return null;
  try {
    return await open();
  } finally {
    _open.remove(key);
  }
}

/// Whether the sheet or dialog for [key] is open right now.
bool isOpen(Object key) => _open.contains(key);
