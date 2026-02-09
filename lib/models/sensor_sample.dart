class SensorSample {
  final int sampleIndex;
  final double timeSeconds;
  final double ax;
  final double ay;
  final double az;
  final double gx;
  final double gy;
  final double gz;
  final double roll;
  final double pitch;
  final double yaw;
  final double? timestampMs;

  const SensorSample({
    required this.sampleIndex,
    required this.timeSeconds,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.roll,
    required this.pitch,
    required this.yaw,
    this.timestampMs,
  });
}
