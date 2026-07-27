import 'dart:convert';

import '../imu_import/imu_models.dart';
import 'preprocessing_models.dart';

class PreprocessedImuCsv {
  const PreprocessedImuCsv();

  String render(ImuPreprocessingResult result) {
    final labels = result.sensorQuality.keys.toList();
    final buffer = StringBuffer();
    final header = <String>['analysis_time_s'];
    for (final label in labels) {
      header.addAll([
        '$label.raw_acc_x_mps2',
        '$label.raw_acc_y_mps2',
        '$label.raw_acc_z_mps2',
        '$label.filtered_acc_x_mps2',
        '$label.filtered_acc_y_mps2',
        '$label.filtered_acc_z_mps2',
        '$label.gravity_x_mps2',
        '$label.gravity_y_mps2',
        '$label.gravity_z_mps2',
        '$label.movement_x_mps2',
        '$label.movement_y_mps2',
        '$label.movement_z_mps2',
        '$label.filtered_gyro_x_radps',
        '$label.filtered_gyro_y_radps',
        '$label.filtered_gyro_z_radps',
        '$label.outlier_replaced',
        '$label.source_uncertainty_ms',
        '$label.lower_source',
        '$label.lower_line',
        '$label.upper_source',
        '$label.upper_line',
      ]);
    }
    buffer.writeln(header.join(','));
    for (final frame in result.frames) {
      final row = <Object?>[frame.analysisTimeSeconds];
      for (final label in labels) {
        final value = frame.values[label];
        if (value == null) {
          row.addAll(List<Object?>.filled(21, null));
          continue;
        }
        row.addAll([
          ..._vector(value.raw.accelerationMps2),
          ..._vector(value.alignedAccelerationMps2),
          ..._vector(value.gravityMps2),
          ..._vector(value.movementAccelerationMps2),
          ..._vector(value.alignedAngularVelocityRadPerSecond),
          value.outlierReplaced,
          value.raw.uncertaintyMilliseconds,
          value.raw.lowerSourceName,
          value.raw.lowerSourceLine,
          value.raw.upperSourceName,
          value.raw.upperSourceLine,
        ]);
      }
      buffer.writeln(row.map(_csv).join(','));
    }
    return buffer.toString();
  }
}

List<double> _vector(Vector3 value) => [value.x, value.y, value.z];

String _csv(Object? value) {
  if (value == null) return '';
  if (value is num || value is bool) return value.toString();
  return '"${value.toString().replaceAll('"', '""')}"';
}

String preprocessingReportJson(ImuPreprocessingResult result) =>
    const JsonEncoder.withIndent('  ').convert({
      'report_version': 1,
      'preprocessing': result.toJson(),
    });
