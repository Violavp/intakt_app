import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'imu_models.dart';

const double _standardGravityMps2 = 9.80665;

class ImuSource {
  const ImuSource({
    required this.file,
    this.hardwareId,
  });

  final File file;

  /// Required only for an individual sensor file without a device column.
  final String? hardwareId;
}

/// Imports BitMotion-style delimited exports without modifying source files.
class ImuTextImporter {
  ImuTextImporter({
    required this.catalog,
    this.unitOverrides = const {},
  });

  final SensorCatalog catalog;

  /// Explicit source-unit overrides keyed by acceleration/angular_velocity/
  /// magnetic_field. Overrides are never inferred from values.
  final Map<String, String> unitOverrides;

  Future<ImuImportResult> importFiles(List<ImuSource> sources) async {
    if (sources.isEmpty) {
      throw const ImuImportException(
        code: 'empty_input',
        message: 'Mindestens eine Sensordatei ist erforderlich.',
      );
    }
    final state = _ImportState(catalog);
    for (final source in sources) {
      if (!await source.file.exists()) {
        throw ImuImportException(
          code: 'file_not_found',
          message: 'Die Datei wurde nicht gefunden.',
          sourceName: source.file.path,
        );
      }
      final lines = source.file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      try {
        await _importLines(
          lines,
          sourceName: source.file.path,
          sourceHardwareId: source.hardwareId,
          state: state,
        );
      } on FormatException catch (error) {
        throw ImuImportException(
          code: 'invalid_text_encoding',
          message: 'Die Datei ist kein gültiger UTF-8-Text: ${error.message}.',
          sourceName: source.file.path,
        );
      }
    }
    return state.finish();
  }

  Future<ImuImportResult> importText(
    String text, {
    String sourceName = '<memory>',
    String? sourceHardwareId,
  }) async {
    final state = _ImportState(catalog);
    await _importLines(
      Stream<String>.fromIterable(const LineSplitter().convert(text)),
      sourceName: sourceName,
      sourceHardwareId: sourceHardwareId,
      state: state,
    );
    return state.finish();
  }

  Future<void> _importLines(
    Stream<String> lines, {
    required String sourceName,
    required String? sourceHardwareId,
    required _ImportState state,
  }) async {
    _ColumnLayout? layout;
    var lineNumber = 0;
    var rows = 0;

    await for (final rawLine in lines) {
      lineNumber++;
      final line = rawLine.endsWith('\r')
          ? rawLine.substring(0, rawLine.length - 1)
          : rawLine;
      if (lineNumber == 1 && line.trim().isEmpty) {
        continue;
      }
      if (layout == null) {
        layout = _ColumnLayout.fromHeader(
          line,
          sourceName: sourceName,
          sourceHardwareId: sourceHardwareId,
          unitOverrides: unitOverrides,
        );
        state.registerUnits(layout);
        continue;
      }
      if (line.trim().isEmpty) {
        state.messages.add(
          ImportMessage(
            code: 'blank_line',
            message: 'Leere Zeile wurde als fehlender Datensatz gemeldet.',
            severity: ImportMessageSeverity.warning,
            sourceName: sourceName,
            line: lineNumber,
          ),
        );
        continue;
      }
      final fields = line.split(layout.delimiter);
      if (fields.length < layout.minimumFieldCount) {
        throw ImuImportException(
          code: 'malformed_row',
          message: 'Die Zeile enthält ${fields.length} statt mindestens '
              '${layout.minimumFieldCount} Felder.',
          sourceName: sourceName,
          line: lineNumber,
        );
      }

      final hardwareId = sourceHardwareId ??
          _extractHardwareId(
            fields[layout.deviceIndex!],
            sourceName: sourceName,
            line: lineNumber,
          );
      final identity = catalog.byHardwareId(hardwareId);
      if (identity == null) {
        throw ImuImportException(
          code: 'unknown_sensor',
          message: 'Hardware-ID "$hardwareId" ist keiner konfigurierten '
              'Sensorposition zugeordnet.',
          sourceName: sourceName,
          line: lineNumber,
          column: layout.headers[layout.deviceIndex ?? 0],
        );
      }

      final timestampText = fields[layout.timestampIndex].trim();
      if (layout.timestampKind == _TimestampKind.iso8601 &&
          !RegExp(r'(?:Z|[+-]\d\d:\d\d)$').hasMatch(timestampText)) {
        state.timestampWithoutOffset = true;
      }
      final timestamp = layout.parseTimestamp(
        timestampText,
        sourceName: sourceName,
        line: lineNumber,
      );
      final acceleration = layout.parseVector(
        fields,
        layout.accelerationIndices,
        quantity: 'Beschleunigung',
        sourceName: sourceName,
        line: lineNumber,
        multiplier: layout.accelerationMultiplier,
      );
      final angularVelocity = layout.parseVector(
        fields,
        layout.angularVelocityIndices,
        quantity: 'Winkelgeschwindigkeit',
        sourceName: sourceName,
        line: lineNumber,
        multiplier: layout.angularVelocityMultiplier,
      );
      final magnetometerIndices = layout.magnetometerIndices;
      final magneticField = magnetometerIndices == null
          ? null
          : layout.parseOptionalVector(
              fields,
              magnetometerIndices,
              quantity: 'Magnetfeld',
              sourceName: sourceName,
              line: lineNumber,
              multiplier: layout.magnetometerMultiplier!,
            );
      final orientationIndices = layout.orientationAngleIndices;
      final orientationAngles = orientationIndices == null
          ? null
          : layout.parseOptionalVector(
              fields,
              orientationIndices,
              quantity: 'Orientierungswinkel',
              sourceName: sourceName,
              line: lineNumber,
              multiplier: 1,
            );

      final recording = state.recordings.putIfAbsent(
        identity.label,
        () => SensorRecording(identity),
      );
      recording.sourceNames.add(sourceName);
      recording.samples.add(
        ImuSample(
          timestamp: timestamp,
          rawTimestamp: timestampText,
          accelerationMps2: acceleration,
          angularVelocityRadPerSecond: angularVelocity,
          magneticFieldMicrotesla: magneticField,
          orientationAnglesDegrees: orientationAngles,
          sourceName: sourceName,
          sourceLine: lineNumber,
        ),
      );
      rows++;
    }

    if (layout == null) {
      throw ImuImportException(
        code: 'empty_file',
        message: 'Die Datei enthält keine Kopfzeile.',
        sourceName: sourceName,
      );
    }
    if (rows == 0) {
      throw ImuImportException(
        code: 'no_data_rows',
        message: 'Die Datei enthält nach der Kopfzeile keine Messwerte.',
        sourceName: sourceName,
      );
    }
  }
}

class _ImportState {
  _ImportState(this.catalog);

  final SensorCatalog catalog;
  final Map<String, SensorRecording> recordings = {};
  final List<ImportMessage> messages = [];
  final Map<String, String> sourceUnits = {};
  bool timestampWithoutOffset = false;

  void registerUnits(_ColumnLayout layout) {
    for (final entry in layout.sourceUnits.entries) {
      final previous = sourceUnits[entry.key];
      if (previous != null && previous != entry.value) {
        throw ImuImportException(
          code: 'mixed_units',
          message:
              'Mehrere Dateien verwenden für ${entry.key} unterschiedliche '
              'Einheiten: "$previous" und "${entry.value}".',
        );
      }
      sourceUnits[entry.key] = entry.value;
    }
  }

  ImuImportResult finish() {
    final ordered = <String, SensorRecording>{};
    for (final identity in catalog.sensors) {
      final recording = recordings[identity.label];
      if (recording != null) ordered[identity.label] = recording;
    }
    return ImuImportResult(
      catalog: catalog,
      recordings: ordered,
      messages: messages,
      sourceUnits: sourceUnits,
      timestampUncertainty: timestampWithoutOffset
          ? 'Zeitstempel ohne UTC-Offset werden als lokale Empfangszeit '
              'interpretiert. Mehrere aufeinanderfolgende Messwerte können '
              'denselben Empfangszeitstempel tragen; eine individuelle '
              'Messzeit darf daraus nicht erfunden werden.'
          : 'Zeitstempel beschreiben Export-/Empfangszeiten; die individuelle '
              'Sensorabtastzeit ist nur so genau wie die Quelle.',
    );
  }
}

class _ColumnLayout {
  _ColumnLayout({
    required this.headers,
    required this.delimiter,
    required this.timestampIndex,
    required this.deviceIndex,
    required this.accelerationIndices,
    required this.angularVelocityIndices,
    required this.magnetometerIndices,
    required this.orientationAngleIndices,
    required this.accelerationMultiplier,
    required this.angularVelocityMultiplier,
    required this.magnetometerMultiplier,
    required this.sourceUnits,
    required this.timestampKind,
  });

  final List<String> headers;
  final String delimiter;
  final int timestampIndex;
  final int? deviceIndex;
  final List<int> accelerationIndices;
  final List<int> angularVelocityIndices;
  final List<int>? magnetometerIndices;
  final List<int>? orientationAngleIndices;
  final double accelerationMultiplier;
  final double angularVelocityMultiplier;
  final double? magnetometerMultiplier;
  final Map<String, String> sourceUnits;
  final _TimestampKind timestampKind;

  int get minimumFieldCount {
    final used = <int>[
      timestampIndex,
      if (deviceIndex != null) deviceIndex!,
      ...accelerationIndices,
      ...angularVelocityIndices,
      ...?magnetometerIndices,
      ...?orientationAngleIndices,
    ];
    return used.reduce(math.max) + 1;
  }

  static _ColumnLayout fromHeader(
    String headerLine, {
    required String sourceName,
    required String? sourceHardwareId,
    required Map<String, String> unitOverrides,
  }) {
    if (headerLine.trim().isEmpty) {
      throw ImuImportException(
        code: 'empty_header',
        message: 'Die Kopfzeile ist leer.',
        sourceName: sourceName,
      );
    }
    final delimiter = _detectDelimiter(headerLine, sourceName);
    final headers = headerLine.split(delimiter);
    final normalized = headers.map(_normalizeHeader).toList();

    int requireIndex(String description, bool Function(String) matches) {
      final index = normalized.indexWhere(matches);
      if (index < 0) {
        throw ImuImportException(
          code: 'missing_column',
          message: 'Pflichtspalte für $description fehlt.',
          sourceName: sourceName,
          column: description,
        );
      }
      return index;
    }

    final timestampIndex = requireIndex(
      'Zeitstempel',
      (value) =>
          value == 'time' ||
          value.startsWith('time(') ||
          value == 'timestamp' ||
          value.startsWith('timestamp('),
    );
    final deviceIndex = normalized.indexWhere(
      (value) =>
          value == 'devicename' ||
          value == 'device' ||
          value == 'sensorid' ||
          value == 'hardwareid',
    );
    if (deviceIndex < 0 && sourceHardwareId == null) {
      throw ImuImportException(
        code: 'missing_column',
        message: 'Spalte für Sensor-ID fehlt. Bei Einzelsensordateien muss die '
            'Hardware-ID explizit als Dateimetadatum übergeben werden.',
        sourceName: sourceName,
        column: 'DeviceName/Sensor-ID',
      );
    }

    List<int> axisIndices(String quantity, List<String> prefixes) {
      return ['x', 'y', 'z'].map((axis) {
        return requireIndex(
          '$quantity $axis',
          (value) => prefixes.any(
            (prefix) =>
                value == '$prefix$axis' || value.startsWith('$prefix$axis('),
          ),
        );
      }).toList();
    }

    final acceleration =
        axisIndices('Beschleunigung', ['acc', 'acceleration', 'a']);
    final angularVelocity = axisIndices(
      'Winkelgeschwindigkeit',
      ['as', 'gyro', 'angularvelocity', 'omega'],
    );

    final magnetometerCandidates = ['x', 'y', 'z'].map((axis) {
      return normalized.indexWhere(
        (value) => ['h', 'mag', 'magneticfield'].any(
          (prefix) =>
              value == '$prefix$axis' || value.startsWith('$prefix$axis('),
        ),
      );
    }).toList();
    final magnetometerCount =
        magnetometerCandidates.where((index) => index >= 0).length;
    if (magnetometerCount != 0 && magnetometerCount != 3) {
      throw ImuImportException(
        code: 'partial_magnetometer_columns',
        message:
            'Magnetometerdaten sind optional, müssen aber als vollständiges '
            'X/Y/Z-Triplett vorliegen.',
        sourceName: sourceName,
        column: 'HX/HY/HZ',
      );
    }
    final magnetometer = magnetometerCount == 3 ? magnetometerCandidates : null;
    final orientationCandidates = ['x', 'y', 'z'].map((axis) {
      return normalized.indexWhere(
        (value) => value == 'angle$axis' || value.startsWith('angle$axis('),
      );
    }).toList();
    final orientationCount =
        orientationCandidates.where((index) => index >= 0).length;
    if (orientationCount != 0 && orientationCount != 3) {
      throw ImuImportException(
        code: 'partial_orientation_angle_columns',
        message: 'Orientierungswinkel sind optional, müssen aber als '
            'vollständiges AngleX/AngleY/AngleZ-Triplett vorliegen.',
        sourceName: sourceName,
        column: 'AngleX/AngleY/AngleZ',
      );
    }
    final orientation = orientationCount == 3 ? orientationCandidates : null;

    String sourceUnit(
      String quantity,
      List<int> indices,
      Set<String> allowed,
    ) {
      final override = unitOverrides[quantity];
      final units = override == null
          ? indices.map((index) => _unitFromHeader(headers[index])).toSet()
          : {override};
      units.removeWhere((unit) => unit == null);
      if (units.length != 1) {
        throw ImuImportException(
          code: 'unknown_or_mixed_unit',
          message: 'Einheit für $quantity ist nicht eindeutig in allen drei '
              'Achsspalten dokumentiert.',
          sourceName: sourceName,
        );
      }
      final unit = _canonicalUnit(units.single!);
      if (!allowed.contains(unit)) {
        throw ImuImportException(
          code: 'unsupported_unit',
          message: 'Einheit "${units.single}" für $quantity wird nicht '
              'stillschweigend interpretiert. Zulässig: ${allowed.join(', ')}.',
          sourceName: sourceName,
        );
      }
      return unit;
    }

    final accelerationUnit = sourceUnit(
      'acceleration',
      acceleration,
      {'g', 'm/s^2'},
    );
    final angularVelocityUnit = sourceUnit(
      'angular_velocity',
      angularVelocity,
      {'degree/s', 'rad/s'},
    );
    final magnetometerUnit = magnetometer == null
        ? null
        : sourceUnit(
            'magnetic_field',
            magnetometer,
            {'uT'},
          );
    final orientationUnit = orientation == null
        ? null
        : sourceUnit(
            'orientation_angle',
            orientation,
            {'degree'},
          );
    final timestampKind = _timestampKind(headers[timestampIndex]);

    return _ColumnLayout(
      headers: headers,
      delimiter: delimiter,
      timestampIndex: timestampIndex,
      deviceIndex: deviceIndex < 0 ? null : deviceIndex,
      accelerationIndices: acceleration,
      angularVelocityIndices: angularVelocity,
      magnetometerIndices: magnetometer,
      orientationAngleIndices: orientation,
      accelerationMultiplier:
          accelerationUnit == 'g' ? _standardGravityMps2 : 1,
      angularVelocityMultiplier:
          angularVelocityUnit == 'degree/s' ? math.pi / 180 : 1,
      magnetometerMultiplier: magnetometer == null ? null : 1,
      sourceUnits: {
        'acceleration': accelerationUnit,
        'angular_velocity': angularVelocityUnit,
        if (magnetometerUnit != null) 'magnetic_field': magnetometerUnit,
        if (orientationUnit != null) 'orientation_angle': orientationUnit,
      },
      timestampKind: timestampKind,
    );
  }

  DateTime parseTimestamp(
    String value, {
    required String sourceName,
    required int line,
  }) {
    try {
      switch (timestampKind) {
        case _TimestampKind.iso8601:
          final parsed = DateTime.parse(value);
          return parsed;
        case _TimestampKind.epochSeconds:
          final microseconds = (double.parse(value) * 1000000).round();
          return DateTime.fromMicrosecondsSinceEpoch(microseconds, isUtc: true);
        case _TimestampKind.epochMilliseconds:
          return DateTime.fromMillisecondsSinceEpoch(
            double.parse(value).round(),
            isUtc: true,
          );
        case _TimestampKind.epochMicroseconds:
          return DateTime.fromMicrosecondsSinceEpoch(
            double.parse(value).round(),
            isUtc: true,
          );
      }
    } on FormatException {
      // Converted into the domain-specific message below.
    }
    throw ImuImportException(
      code: 'invalid_timestamp',
      message:
          'Zeitstempel "$value" ist für das dokumentierte Format ungültig.',
      sourceName: sourceName,
      line: line,
      column: headers[timestampIndex],
    );
  }

  Vector3 parseVector(
    List<String> fields,
    List<int> indices, {
    required String quantity,
    required String sourceName,
    required int line,
    required double multiplier,
  }) {
    final values = indices.map((index) {
      return _parseFinite(
        fields[index],
        sourceName: sourceName,
        line: line,
        column: headers[index],
      );
    }).toList();
    return Vector3(
      values[0] * multiplier,
      values[1] * multiplier,
      values[2] * multiplier,
    );
  }

  Vector3? parseOptionalVector(
    List<String> fields,
    List<int> indices, {
    required String quantity,
    required String sourceName,
    required int line,
    required double multiplier,
  }) {
    final raw = indices.map((index) => fields[index].trim()).toList();
    final missing = raw.map(_isMissing).toList();
    if (missing.every((value) => value)) return null;
    if (missing.any((value) => value)) {
      throw ImuImportException(
        code: 'partial_vector',
        message: '$quantity ist in dieser Zeile nur teilweise vorhanden. '
            'Der Messwert wird nicht ergänzt.',
        sourceName: sourceName,
        line: line,
      );
    }
    return parseVector(
      fields,
      indices,
      quantity: quantity,
      sourceName: sourceName,
      line: line,
      multiplier: multiplier,
    );
  }
}

enum _TimestampKind {
  iso8601,
  epochSeconds,
  epochMilliseconds,
  epochMicroseconds,
}

_TimestampKind _timestampKind(String header) {
  final unit = _unitFromHeader(header);
  if (unit == null || unit.trim().isEmpty) return _TimestampKind.iso8601;
  switch (_canonicalUnit(unit)) {
    case 's':
      return _TimestampKind.epochSeconds;
    case 'ms':
      return _TimestampKind.epochMilliseconds;
    case 'us':
      return _TimestampKind.epochMicroseconds;
    default:
      throw ImuImportException(
        code: 'unsupported_timestamp_unit',
        message: 'Zeitstempeleinheit "$unit" ist nicht unterstützt. '
            'Zulässig sind ISO-8601, s, ms oder us.',
        column: header,
      );
  }
}

String _detectDelimiter(String header, String sourceName) {
  final counts = {
    '\t': '\t'.allMatches(header).length,
    ';': ';'.allMatches(header).length,
    ',': ','.allMatches(header).length,
  };
  final best = counts.entries.reduce(
    (left, right) => left.value >= right.value ? left : right,
  );
  if (best.value == 0) {
    throw ImuImportException(
      code: 'unknown_delimiter',
      message:
          'Kein unterstütztes Trennzeichen (Tab, Semikolon, Komma) erkannt.',
      sourceName: sourceName,
    );
  }
  return best.key;
}

String _normalizeHeader(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll('ω', 'omega')
    .replaceAll(RegExp(r'[\s_\-]'), '');

String? _unitFromHeader(String header) {
  final match = RegExp(r'\(([^()]*)\)\s*$').firstMatch(header.trim());
  return match?.group(1)?.trim();
}

String _canonicalUnit(String unit) {
  final value = unit
      .trim()
      .toLowerCase()
      .replaceAll('µ', 'u')
      .replaceAll('μ', 'u')
      .replaceAll('²', '^2')
      .replaceAll('sec', 's')
      .replaceAll(' ', '');
  if (value == 'g') return 'g';
  if (value == 'm/s^2' || value == 'm/s2') return 'm/s^2';
  if (value == '°/s' || value == 'deg/s' || value == 'degree/s') {
    return 'degree/s';
  }
  if (value == 'rad/s') return 'rad/s';
  if (value == '°' || value == 'deg' || value == 'degree') return 'degree';
  if (value == 'ut') return 'uT';
  if (value == 's') return 's';
  if (value == 'ms') return 'ms';
  if (value == 'us') return 'us';
  return unit;
}

String _extractHardwareId(
  String deviceValue, {
  required String sourceName,
  required int line,
}) {
  final match = RegExp(r'\(([0-9A-Fa-f]{12})\)').firstMatch(deviceValue);
  if (match != null) return match.group(1)!.toUpperCase();
  final plain = deviceValue.trim();
  if (RegExp(r'^[0-9A-Fa-f]{12}$').hasMatch(plain)) {
    return plain.toUpperCase();
  }
  throw ImuImportException(
    code: 'invalid_sensor_id',
    message:
        'Aus "$deviceValue" konnte keine 12-stellige Hardware-ID gelesen werden.',
    sourceName: sourceName,
    line: line,
    column: 'DeviceName/Sensor-ID',
  );
}

double _parseFinite(
  String raw, {
  required String sourceName,
  required int line,
  required String column,
}) {
  final value = double.tryParse(raw.trim());
  if (value == null || !value.isFinite) {
    throw ImuImportException(
      code: 'invalid_numeric_value',
      message: 'Wert "$raw" ist keine endliche Zahl. NaN/Infinity und fehlende '
          'Pflichtmesswerte werden nicht importiert.',
      sourceName: sourceName,
      line: line,
      column: column,
    );
  }
  return value;
}

bool _isMissing(String value) =>
    value.isEmpty ||
    value.toLowerCase() == 'null' ||
    value.toLowerCase() == 'nan';
