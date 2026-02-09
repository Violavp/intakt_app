import 'dart:typed_data';

/// Baut vollständige Frames (20 Byte) aus beliebigen Notification-Chunks auf.
class FrameAssembler {
  FrameAssembler({this.frameLength = 20, this.acceptedTypes = const {0x61}});

  final int frameLength;
  final Set<int> acceptedTypes;

  final List<int> _buffer = [];

  /// Fügt einen eingehenden Chunk hinzu und liefert alle vollständigen Frames.
  List<Uint8List> add(Uint8List chunk) {
    _buffer.addAll(chunk);
    final frames = <Uint8List>[];

    while (true) {
      final start = _findHeader();
      if (start == -1) {
        _buffer.clear();
        break;
      }
      if (start > 0) {
        _buffer.removeRange(0, start);
      }
      if (_buffer.length < frameLength) break;

      if (acceptedTypes.isNotEmpty &&
          (_buffer.length < 2 || !acceptedTypes.contains(_buffer[1]))) {
        _buffer.removeAt(0); // falscher Typ, weiter suchen
        continue;
      }

      final frame = Uint8List.fromList(_buffer.sublist(0, frameLength));
      frames.add(frame);
      _buffer.removeRange(0, frameLength);
    }

    return frames;
  }

  int _findHeader() {
    for (int i = 0; i < _buffer.length; i++) {
      if (_buffer[i] == 0x55) return i;
    }
    return -1;
  }
}
