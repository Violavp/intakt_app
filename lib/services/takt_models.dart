class LegMetrics {
  final double? offsetMs;
  final double? scorePct;
  const LegMetrics({required this.offsetMs, required this.scorePct});
}

enum Gait { stehen, schritt, trab, galopp }

class TaktUiState {
  final Map<String, LegMetrics> legs;
  final double? stepFrequencySpm;
  final double? diagPhaseDeg;
  final double? lateralPhaseDeg;
  final double? intervalVarMs;
  final double? stabilityPct;
  final double? temporalScorePct;
  final double? spatialScorePct;
  final double? taktScorePct;
  final double? confidencePct;
  final bool confidence;
  final double timestampMs;
  final Gait gait;

  const TaktUiState({
    required this.legs,
    required this.stepFrequencySpm,
    required this.diagPhaseDeg,
    required this.lateralPhaseDeg,
    required this.intervalVarMs,
    required this.stabilityPct,
    required this.temporalScorePct,
    required this.spatialScorePct,
    required this.taktScorePct,
    required this.confidencePct,
    required this.confidence,
    required this.timestampMs,
    required this.gait,
  });

  factory TaktUiState.empty() => const TaktUiState(
        legs: {
          "VL": LegMetrics(offsetMs: null, scorePct: null),
          "VR": LegMetrics(offsetMs: null, scorePct: null),
          "HL": LegMetrics(offsetMs: null, scorePct: null),
          "HR": LegMetrics(offsetMs: null, scorePct: null),
        },
        stepFrequencySpm: null,
        diagPhaseDeg: null,
        lateralPhaseDeg: null,
        intervalVarMs: null,
        stabilityPct: null,
        temporalScorePct: null,
        spatialScorePct: null,
        taktScorePct: null,
        confidencePct: null,
        confidence: false,
        timestampMs: 0,
        gait: Gait.stehen,
      );
}
