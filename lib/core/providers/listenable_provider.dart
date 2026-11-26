import 'package:flutter/foundation.dart' show Listenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A provider for a long-lived [Listenable] (an app-wide singleton such as a
/// [ChangeNotifier] service): whatever watches it rebuilds each time it
/// notifies.
///
/// It only listens. The object outlives the provider, so the provider never
/// disposes it.
Provider<T> listenableProvider<T extends Listenable>(
  T Function(Ref ref) create,
) => Provider<T>((ref) {
  final listenable = create(ref);
  // The value stays the same object, so notify the watchers outright.
  void notify() => ref.notifyListeners();
  listenable.addListener(notify);
  ref.onDispose(() => listenable.removeListener(notify));
  return listenable;
});
