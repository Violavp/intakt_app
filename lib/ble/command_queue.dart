import 'dart:async';

/// Serialisiert Schreibbefehle pro Gerät, damit BLE-Writes nicht kollidieren.
class CommandQueue {
  Future<void> _pending = Future.value();

  Future<T> enqueue<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _pending = _pending.then((_) => task()).then((value) {
      completer.complete(value);
    }).catchError((Object e, StackTrace st) {
      completer.completeError(e, st);
    });
    return completer.future;
  }
}
