import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds one value that any code may replace.
///
/// Riverpod 3 keeps a notifier's `state` to the notifier itself, so outside
/// code changes the value through [set] and [update]. Listeners hear of a
/// change only when the new value is not `==` the current one.
class SettableNotifier<T> extends Notifier<T> {
  SettableNotifier(this._initial);

  final T _initial;

  @override
  T build() => _initial;

  void set(T value) => state = value;

  void update(T Function(T current) change) => state = change(state);
}

/// A provider for a value any code may replace, starting at [initial].
NotifierProvider<SettableNotifier<T>, T> settableProvider<T>(T initial) =>
    NotifierProvider<SettableNotifier<T>, T>(() => SettableNotifier(initial));
