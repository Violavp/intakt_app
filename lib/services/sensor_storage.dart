class SensorStorage {
  final List<Map<String, dynamic>> _data = [];

  void add(String role, String type, Map<String, double> values) {
    final now = DateTime.now().millisecondsSinceEpoch;

    _data.add({
      "timestamp": now,
      "role": role,
      "type": type,
      ...values,
    });
  }

  List<Map<String, dynamic>> get all => _data;

  void clear() => _data.clear();
}
