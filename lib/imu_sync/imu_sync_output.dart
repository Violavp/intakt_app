import 'imu_synchronization.dart';

class ImuSynchronizationCsv {
  const ImuSynchronizationCsv();

  String render(ImuSynchronizationResult result) {
    if (!result.hasSynchronizedDataset) {
      throw StateError(
        'Ohne gültigen gemeinsamen Datensatz kann keine CSV erzeugt werden.',
      );
    }
    final labels = result.sensorQuality.keys.toList();
    final output = StringBuffer('timestamp_utc,elapsed_s');
    for (final label in labels) {
      output.write(
        ',$label.acc_x_mps2,$label.acc_y_mps2,$label.acc_z_mps2'
        ',$label.gyro_x_radps,$label.gyro_y_radps,$label.gyro_z_radps'
        ',$label.mag_x_uT,$label.mag_y_uT,$label.mag_z_uT'
        ',$label.angle_x_deg,$label.angle_y_deg,$label.angle_z_deg'
        ',$label.lower_source,$label.lower_line'
        ',$label.upper_source,$label.upper_line',
      );
    }
    output.writeln();

    for (final frame in result.frames) {
      output.write(
        '${frame.timestamp.toIso8601String()},'
        '${frame.elapsedSeconds.toStringAsFixed(6)}',
      );
      for (final label in labels) {
        final value = frame.values[label];
        if (value == null) {
          output.write(List.filled(16, '').map((field) => ',$field').join());
          continue;
        }
        final acceleration = value.accelerationMps2;
        final gyro = value.angularVelocityRadPerSecond;
        final magnetometer = value.magneticFieldMicrotesla;
        final orientation = value.orientationAnglesDegrees;
        output
          ..write(
            ',${acceleration.x},${acceleration.y},${acceleration.z}'
            ',${gyro.x},${gyro.y},${gyro.z}',
          )
          ..write(
            magnetometer == null
                ? ',,,'
                : ',${magnetometer.x},${magnetometer.y},${magnetometer.z}',
          )
          ..write(
            orientation == null
                ? ',,,'
                : ',${orientation.x},${orientation.y},${orientation.z}',
          )
          ..write(
            ',${_csv(value.lowerSourceName)},${value.lowerSourceLine}'
            ',${_csv(value.upperSourceName)},${value.upperSourceLine}',
          );
      }
      output.writeln();
    }
    return output.toString();
  }
}

String _csv(String value) => '"${value.replaceAll('"', '""')}"';
