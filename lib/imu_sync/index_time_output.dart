import 'index_time_reconstruction.dart';

class IndexTimeSamplesCsv {
  const IndexTimeSamplesCsv();

  String render(IndexTimeReconstructionResult result) {
    if (result.sensors.values.any((sensor) => !sensor.valid)) {
      throw StateError(
        'Ohne gültige Sensorrekonstruktion kann keine Sample-CSV entstehen.',
      );
    }
    final output = StringBuffer(
      'time_basis,sensor,sample_index,packet_index,index_time_s,'
      'analysis_time_s,uncertainty_ms,reception_timestamp,raw_timestamp,'
      'source_name,source_line,acc_x_mps2,acc_y_mps2,acc_z_mps2,'
      'gyro_x_radps,gyro_y_radps,gyro_z_radps,'
      'mag_x_uT,mag_y_uT,mag_z_uT,'
      'angle_x_deg,angle_y_deg,angle_z_deg\n',
    );
    for (final sensor in result.sensors.values) {
      for (final sample in sensor.samples) {
        final raw = sample.rawSample;
        final acceleration = raw.accelerationMps2;
        final gyro = raw.angularVelocityRadPerSecond;
        final magnetic = raw.magneticFieldMicrotesla;
        final orientation = raw.orientationAnglesDegrees;
        output
          ..write(
            'RECONSTRUCTED_INDEX_TIME,${_csv(sensor.sensorLabel)},'
            '${sample.sampleIndex},${sample.packetIndex},'
            '${sample.indexTimeSeconds.toStringAsFixed(9)},'
            '${sample.analysisTimeSeconds.toStringAsFixed(9)},'
            '${sample.uncertaintyMilliseconds.toStringAsFixed(3)},'
            '${raw.timestamp.toIso8601String()},${_csv(raw.rawTimestamp)},'
            '${_csv(raw.sourceName)},${raw.sourceLine},'
            '${acceleration.x},${acceleration.y},${acceleration.z},'
            '${gyro.x},${gyro.y},${gyro.z},',
          )
          ..write(
            magnetic == null
                ? ',,'
                : '${magnetic.x},${magnetic.y},${magnetic.z}',
          )
          ..write(
            orientation == null
                ? ',,,'
                : ',${orientation.x},${orientation.y},${orientation.z}',
          )
          ..writeln();
      }
    }
    return output.toString();
  }
}

class IndexTimeGridCsv {
  const IndexTimeGridCsv();

  String render(IndexTimeReconstructionResult result) {
    if (!result.hasReconstructedDataset) {
      throw StateError(
        'Ohne gemeinsames rekonstruiertes Raster kann keine CSV entstehen.',
      );
    }
    final labels = result.sensors.keys.toList();
    final output = StringBuffer('time_basis,analysis_time_s');
    for (final label in labels) {
      output.write(
        ',$label.acc_x_mps2,$label.acc_y_mps2,$label.acc_z_mps2'
        ',$label.gyro_x_radps,$label.gyro_y_radps,$label.gyro_z_radps'
        ',$label.mag_x_uT,$label.mag_y_uT,$label.mag_z_uT'
        ',$label.angle_x_deg,$label.angle_y_deg,$label.angle_z_deg'
        ',$label.uncertainty_ms'
        ',$label.lower_sample_index,$label.upper_sample_index'
        ',$label.lower_source,$label.lower_line'
        ',$label.upper_source,$label.upper_line',
      );
    }
    output.writeln();
    for (final frame in result.frames) {
      output.write(
        'RECONSTRUCTED_INDEX_TIME,'
        '${frame.analysisTimeSeconds.toStringAsFixed(9)}',
      );
      for (final label in labels) {
        final value = frame.values[label];
        if (value == null) {
          output.write(List.filled(20, '').map((field) => ',$field').join());
          continue;
        }
        final acceleration = value.accelerationMps2;
        final gyro = value.angularVelocityRadPerSecond;
        final magnetic = value.magneticFieldMicrotesla;
        final orientation = value.orientationAnglesDegrees;
        output
          ..write(
            ',${acceleration.x},${acceleration.y},${acceleration.z}'
            ',${gyro.x},${gyro.y},${gyro.z}',
          )
          ..write(
            magnetic == null
                ? ',,,'
                : ',${magnetic.x},${magnetic.y},${magnetic.z}',
          )
          ..write(
            orientation == null
                ? ',,,'
                : ',${orientation.x},${orientation.y},${orientation.z}',
          )
          ..write(
            ',${value.uncertaintyMilliseconds.toStringAsFixed(3)}'
            ',${value.lowerSampleIndex},${value.upperSampleIndex}'
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
