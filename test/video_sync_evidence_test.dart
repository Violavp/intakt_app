import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('video-IMU evidence reproduces affine quality metrics', () {
    final evidenceFile = File(
      'recordings/test01/evidence/video_imu_synchronisation.json',
    );
    final evidence =
        jsonDecode(evidenceFile.readAsStringSync()) as Map<String, dynamic>;
    final anchors =
        (evidence['anchors'] as List<dynamic>).cast<Map<String, dynamic>>();

    expect(anchors, hasLength(9));
    expect(
      anchors.map((anchor) => anchor['sensor']).toSet(),
      containsAll(<String>{'SG', 'VL', 'VR', 'HL', 'HR'}),
    );

    final videoTimes = anchors
        .map((anchor) => (anchor['video_time_s'] as num).toDouble())
        .toList();
    final imuTimes = anchors
        .map((anchor) => (anchor['imu_elapsed_s'] as num).toDouble())
        .toList();

    final videoMean =
        videoTimes.reduce((left, right) => left + right) / anchors.length;
    final imuMean =
        imuTimes.reduce((left, right) => left + right) / anchors.length;
    var covariance = 0.0;
    var videoVariance = 0.0;
    for (var index = 0; index < anchors.length; index++) {
      final centeredVideo = videoTimes[index] - videoMean;
      covariance += centeredVideo * (imuTimes[index] - imuMean);
      videoVariance += centeredVideo * centeredVideo;
    }
    final slope = covariance / videoVariance;
    final intercept = imuMean - slope * videoMean;
    final residuals = <double>[
      for (var index = 0; index < anchors.length; index++)
        imuTimes[index] - (intercept + slope * videoTimes[index]),
    ];
    final residualRmseMs = math.sqrt(
          residuals
                  .map((residual) => residual * residual)
                  .reduce((left, right) => left + right) /
              residuals.length,
        ) *
        1000;
    final maximumAbsoluteResidualMs =
        residuals.map((residual) => residual.abs()).reduce(math.max) * 1000;
    final fit = evidence['fit'] as Map<String, dynamic>;

    expect(intercept, closeTo((fit['intercept_s'] as num).toDouble(), 1e-9));
    expect(slope, closeTo((fit['slope'] as num).toDouble(), 1e-9));
    expect(
      (slope - 1) * 1000000,
      closeTo((fit['estimated_drift_ppm'] as num).toDouble(), 0.001),
    );
    expect(
      residualRmseMs,
      closeTo((fit['residual_rmse_ms'] as num).toDouble(), 0.001),
    );
    expect(
      maximumAbsoluteResidualMs,
      closeTo(
        (fit['maximum_absolute_residual_ms'] as num).toDouble(),
        0.001,
      ),
    );

    for (var index = 0; index < anchors.length; index++) {
      final anchor = anchors[index];
      expect(
        (anchor['offset_s'] as num).toDouble(),
        closeTo(imuTimes[index] - videoTimes[index], 1e-6),
      );
      expect(
        (anchor['fit_residual_ms'] as num).toDouble(),
        closeTo(residuals[index] * 1000, 0.001),
      );
    }

    final assessment = evidence['assessment'] as Map<String, dynamic>;
    expect(assessment['status'], 'REVIEW_REQUIRED');
    final visualization = File(
      'recordings/test01/evidence/video_imu_synchronisation.svg',
    ).readAsStringSync();
    for (final anchor in anchors) {
      final anchorId = anchor['id'];
      expect(visualization, contains('data-anchor-id="$anchorId"'));
      expect(visualization, contains('data-anchor-label="$anchorId"'));
    }
    expect(
      File('recordings/test01/video/IMG_4012.MOV').lengthSync(),
      687365838,
    );
  });
}
