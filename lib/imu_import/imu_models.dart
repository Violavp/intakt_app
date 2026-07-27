import 'dart:convert';

/// A three-axis value in the unit documented by the containing field.
class Vector3 {
  const Vector3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  double get magnitudeSquared => x * x + y * y + z * z;

  Map<String, double> toJson() => {'x': x, 'y': y, 'z': z};
}

/// One imported row. Source order and the unmodified timestamp text are kept.
class ImuSample {
  const ImuSample({
    required this.timestamp,
    required this.rawTimestamp,
    required this.accelerationMps2,
    required this.angularVelocityRadPerSecond,
    required this.sourceName,
    required this.sourceLine,
    this.magneticFieldMicrotesla,
    this.orientationAnglesDegrees,
  });

  final DateTime timestamp;
  final String rawTimestamp;
  final Vector3 accelerationMps2;
  final Vector3 angularVelocityRadPerSecond;
  final Vector3? magneticFieldMicrotesla;

  /// Device-provided orientation angles. Kept in degrees because the source
  /// uses the documented circular interval [-180, 180].
  final Vector3? orientationAnglesDegrees;
  final String sourceName;
  final int sourceLine;
}

class SensorIdentity {
  const SensorIdentity({
    required this.label,
    required this.hardwareId,
    required this.position,
    this.required = true,
  });

  final String label;
  final String hardwareId;
  final String position;
  final bool required;

  Map<String, Object> toJson() => {
        'label': label,
        'hardware_id': hardwareId,
        'position': position,
        'required': required,
      };
}

/// Explicit hardware-ID assignment. Unknown IDs are never guessed.
class SensorCatalog {
  SensorCatalog(Iterable<SensorIdentity> sensors)
      : sensorsByHardwareId = {
          for (final sensor in sensors) sensor.hardwareId.toUpperCase(): sensor,
        } {
    if (sensorsByHardwareId.length != sensors.length) {
      throw ArgumentError('Sensor-Hardware-IDs müssen eindeutig sein.');
    }
  }

  final Map<String, SensorIdentity> sensorsByHardwareId;

  Iterable<SensorIdentity> get sensors => sensorsByHardwareId.values;

  Iterable<SensorIdentity> get requiredSensors =>
      sensors.where((sensor) => sensor.required);

  SensorIdentity? byHardwareId(String hardwareId) =>
      sensorsByHardwareId[hardwareId.toUpperCase()];

  factory SensorCatalog.fromConfigurationJson(String jsonText) {
    final root = jsonDecode(jsonText);
    if (root is! Map<String, dynamic> || root['sensors'] is! List) {
      throw const FormatException(
        'Messkonfiguration muss ein JSON-Objekt mit "sensors" enthalten.',
      );
    }
    final sensors = <SensorIdentity>[];
    for (final value in root['sensors'] as List) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException(
            'Ungültiger Sensoreintrag in der Konfiguration.');
      }
      final label = value['label'];
      final hardwareId = value['hardware_id'];
      final position = value['position'];
      if (label is! String ||
          hardwareId is! String ||
          position is! String ||
          hardwareId.isEmpty) {
        throw const FormatException(
          'Jeder Sensor benötigt label, hardware_id und position.',
        );
      }
      sensors.add(
        SensorIdentity(
          label: label,
          hardwareId: hardwareId,
          position: position,
          // The current goal requires the four limb sensors. SG remains optional.
          required: const {'VL', 'VR', 'HL', 'HR'}.contains(label),
        ),
      );
    }
    return SensorCatalog(sensors);
  }
}

class SensorRecording {
  SensorRecording(this.identity);

  final SensorIdentity identity;
  final List<ImuSample> samples = [];
  final Set<String> sourceNames = {};

  Map<String, Object> summaryJson() => {
        ...identity.toJson(),
        'rows': samples.length,
        'source_files': sourceNames.toList()..sort(),
        'magnetometer_rows': samples
            .where((sample) => sample.magneticFieldMicrotesla != null)
            .length,
        'orientation_angle_rows': samples
            .where((sample) => sample.orientationAnglesDegrees != null)
            .length,
      };
}

enum ImportMessageSeverity { warning, error }

class ImportMessage {
  const ImportMessage({
    required this.code,
    required this.message,
    required this.severity,
    this.sourceName,
    this.line,
    this.sensorLabel,
  });

  final String code;
  final String message;
  final ImportMessageSeverity severity;
  final String? sourceName;
  final int? line;
  final String? sensorLabel;

  Map<String, Object?> toJson() => {
        'severity': severity.name,
        'code': code,
        'message': message,
        if (sourceName != null) 'source_file': sourceName,
        if (line != null) 'line': line,
        if (sensorLabel != null) 'sensor': sensorLabel,
      };
}

class ImuImportResult {
  ImuImportResult({
    required this.catalog,
    required this.recordings,
    required this.messages,
    required this.sourceUnits,
    required this.timestampUncertainty,
  });

  final SensorCatalog catalog;
  final Map<String, SensorRecording> recordings;
  final List<ImportMessage> messages;

  /// Units detected from headers before conversion.
  final Map<String, String> sourceUnits;

  /// Explicit limitation of the source timestamp semantics.
  final String timestampUncertainty;

  int get totalRows => recordings.values
      .fold(0, (sum, recording) => sum + recording.samples.length);

  Map<String, Object> toSummaryJson() => {
        'internal_units': {
          'acceleration': 'm/s^2',
          'angular_velocity': 'rad/s',
          'magnetic_field': 'uT',
          'orientation_angle': 'degree',
        },
        'source_units': sourceUnits,
        'timestamp_uncertainty': timestampUncertainty,
        'total_rows': totalRows,
        'sensors': recordings.values
            .map((recording) => recording.summaryJson())
            .toList(),
        'import_messages': messages.map((message) => message.toJson()).toList(),
      };
}

class ImuImportException implements Exception {
  const ImuImportException({
    required this.code,
    required this.message,
    this.sourceName,
    this.line,
    this.column,
  });

  final String code;
  final String message;
  final String? sourceName;
  final int? line;
  final String? column;

  @override
  String toString() {
    final location = [
      if (sourceName != null) sourceName,
      if (line != null) 'Zeile $line',
      if (column != null) 'Spalte "$column"',
    ].join(', ');
    return 'IMU-Importfehler [$code]${location.isEmpty ? '' : ' ($location)'}: '
        '$message';
  }
}
