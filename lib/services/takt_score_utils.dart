import 'dart:math';

class TaktScoreTriple {
  final double temporal;
  final double spatial;
  final double takt;
  final double confidence;

  const TaktScoreTriple({
    required this.temporal,
    required this.spatial,
    required this.takt,
    required this.confidence,
  });
}

double clamp01(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);

double scoreExp(double error, {required double k}) {
  if (!error.isFinite) return 0.0;
  return 100.0 * exp(-k * max(0.0, error));
}

double scoreLinear(double error, {required double good, required double bad}) {
  if (!error.isFinite || good == bad) return 0.0;
  if (good < bad) {
    if (error <= good) return 100.0;
    if (error >= bad) return 0.0;
    return 100.0 * (1.0 - (error - good) / (bad - good));
  }
  if (error >= good) return 100.0;
  if (error <= bad) return 0.0;
  return 100.0 * (1.0 - (good - error) / (good - bad));
}

double weightedMeanPct(List<_WeightedPct> parts) {
  double ws = 0.0;
  double s = 0.0;
  for (final p in parts) {
    if (!p.value.isFinite) {
      continue;
    }
    final v = p.value;
    final w = max(0.0, p.weight);
    ws += w;
    s += w * v;
  }
  if (ws <= 1e-9) return 0.0;
  return s / ws;
}

double geoMeanPct(double aPct, double bPct) {
  return 100.0 * sqrt(clamp01(aPct / 100.0) * clamp01(bPct / 100.0));
}

double geoMean3Pct(double aPct, double bPct, double cPct) {
  final x = clamp01(aPct / 100.0) *
      clamp01(bPct / 100.0) *
      clamp01(cPct / 100.0);
  return 100.0 * pow(x, 1 / 3).toDouble();
}

double _meanFinite(List<double> values) {
  final a = values.where((x) => x.isFinite).toList();
  if (a.isEmpty) return double.nan;
  return a.reduce((p, q) => p + q) / a.length;
}

double _maxAbs(List<double> values) {
  double out = 0.0;
  for (final v in values) {
    if (!v.isFinite) continue;
    final a = v.abs();
    if (a > out) out = a;
  }
  return out;
}

TaktScoreTriple computeWalkScores({
  required double periodSec,
  required double periodStdMs,
  required double intervalVarMs,
  required double walkScore,
  required Map<String, double> legDevMs,
  required double straightnessScorePct,
  double? impactCv,
  double? swingCv,
}) {
  final periodMs = max(1.0, periodSec * 1000.0);

  final cvPeriod = periodStdMs / periodMs;
  final cvInterval = intervalVarMs / periodMs;

  final sPeriod = scoreExp(cvPeriod, k: 10.0);
  final sInterval = scoreExp(cvInterval, k: 12.0);
  final sPattern = scoreExp(walkScore, k: 7.0);

  final temporal = weightedMeanPct([
    _WeightedPct(sPattern, 0.45),
    _WeightedPct(sInterval, 0.35),
    _WeightedPct(sPeriod, 0.20),
  ]);

  final vl = legDevMs["VL"] ?? double.nan;
  final vr = legDevMs["VR"] ?? double.nan;
  final hl = legDevMs["HL"] ?? double.nan;
  final hr = legDevMs["HR"] ?? double.nan;

  final left = _meanFinite([vl, hl]);
  final right = _meanFinite([vr, hr]);
  final front = _meanFinite([vl, vr]);
  final hind = _meanFinite([hl, hr]);

  final normMs = 0.15 * periodMs;
  final imbLR = (left - right).abs();
  final imbFH = (front - hind).abs();
  final worstAbs = _maxAbs([vl, vr, hl, hr]);

  final sLR = scoreExp(imbLR / normMs, k: 4.0);
  final sFH = scoreExp(imbFH / normMs, k: 4.0);
  final sWorst = scoreExp(worstAbs / (0.20 * periodMs), k: 3.0);
  final sImpact = (impactCv == null || !impactCv.isFinite)
      ? double.nan
      : scoreExp(impactCv, k: 4.0);
  final sSwing = (swingCv == null || !swingCv.isFinite)
      ? double.nan
      : scoreExp(swingCv, k: 4.0);

  final spatial = weightedMeanPct([
    _WeightedPct(sLR, 0.25),
    _WeightedPct(sFH, 0.25),
    _WeightedPct(sWorst, 0.10),
    _WeightedPct(straightnessScorePct, 0.20),
    _WeightedPct(sImpact, 0.10),
    _WeightedPct(sSwing, 0.10),
  ]);

  final takt = geoMean3Pct(temporal, spatial, straightnessScorePct);
  final confidence = geoMeanPct(temporal, spatial);

  return TaktScoreTriple(
    temporal: temporal.clamp(0.0, 100.0),
    spatial: spatial.clamp(0.0, 100.0),
    takt: takt.clamp(0.0, 100.0),
    confidence: confidence.clamp(0.0, 100.0),
  );
}

TaktScoreTriple computeTrotScores({
  required double periodSec,
  required double trotScore,
  required bool isTrot,
  required Map<String, double> legDevMs,
  required double diagPhaseDeg,
  required double diagPhaseDeg2,
  required double lateralFrontDeg,
  required double lateralHindDeg,
  required double straightnessScorePct,
  required double stabilityPct,
  double? impactCv,
  double? swingCv,
}) {
  final periodMs = max(1.0, periodSec * 1000.0);

  final sTrot = scoreExp(trotScore, k: 7.0);
  final sDiag = scoreLinear(max(diagPhaseDeg, diagPhaseDeg2), good: 10, bad: 50);
  final latErr = max((180 - lateralFrontDeg).abs(), (180 - lateralHindDeg).abs());
  final sLat = scoreLinear(latErr, good: 15, bad: 70);

  final temporal = weightedMeanPct([
    _WeightedPct(sTrot, 0.55),
    _WeightedPct(sDiag, 0.25),
    _WeightedPct(sLat, 0.20),
  ]);

  final vl = legDevMs["VL"] ?? double.nan;
  final vr = legDevMs["VR"] ?? double.nan;
  final hl = legDevMs["HL"] ?? double.nan;
  final hr = legDevMs["HR"] ?? double.nan;

  final left = _meanFinite([vl, hl]);
  final right = _meanFinite([vr, hr]);
  final imbLR = (left - right).abs();

  final normMs = 0.12 * periodMs;
  final sLR = scoreExp(imbLR / normMs, k: 4.5);
  final sImpact = (impactCv == null || !impactCv.isFinite)
      ? double.nan
      : scoreExp(impactCv, k: 4.5);
  final sSwing = (swingCv == null || !swingCv.isFinite)
      ? double.nan
      : scoreExp(swingCv, k: 4.5);

  final spatial = weightedMeanPct([
    _WeightedPct(sLR, 0.35),
    _WeightedPct(straightnessScorePct, 0.30),
    _WeightedPct(stabilityPct, 0.15),
    _WeightedPct(sImpact, 0.10),
    _WeightedPct(sSwing, 0.10),
  ]);

  final takt = geoMean3Pct(temporal, spatial, straightnessScorePct);
  final baseConfidence = geoMeanPct(temporal, spatial);
  final confidence = isTrot ? baseConfidence : baseConfidence * 0.6;

  return TaktScoreTriple(
    temporal: temporal.clamp(0.0, 100.0),
    spatial: spatial.clamp(0.0, 100.0),
    takt: takt.clamp(0.0, 100.0),
    confidence: confidence.clamp(0.0, 100.0),
  );
}

TaktScoreTriple computeGallopScores({
  required bool isGallop,
  required String lead,
  required double periodSec,
  required double diagonalPairTightMs,
  required double otherDiagonalMs,
  required double gallopScorePct,
  required Map<String, double> legDevMs,
  required double straightnessScorePct,
  double? impactCv,
  double? swingCv,
}) {
  final periodMs = max(1.0, periodSec * 1000.0);

  final sTight = scoreLinear(diagonalPairTightMs, good: 90, bad: 230);
  final sOther = scoreLinear(otherDiagonalMs, good: 260, bad: 140);
  final temporal = weightedMeanPct([
    _WeightedPct(gallopScorePct, 0.55),
    _WeightedPct(sTight, 0.25),
    _WeightedPct(sOther, 0.20),
  ]);

  final vl = legDevMs["VL"] ?? double.nan;
  final vr = legDevMs["VR"] ?? double.nan;
  final hl = legDevMs["HL"] ?? double.nan;
  final hr = legDevMs["HR"] ?? double.nan;

  final left = _meanFinite([vl, hl]);
  final right = _meanFinite([vr, hr]);
  final imbLR = (left - right).abs();

  final normMs = 0.18 * periodMs;
  final sLR = scoreExp(imbLR / normMs, k: 3.5);
  final sImpact = (impactCv == null || !impactCv.isFinite)
      ? double.nan
      : scoreExp(impactCv, k: 3.5);
  final sSwing = (swingCv == null || !swingCv.isFinite)
      ? double.nan
      : scoreExp(swingCv, k: 3.5);

  final leadOk = (lead == "links" || lead == "rechts") ? 100.0 : 50.0;

  final spatial = weightedMeanPct([
    _WeightedPct(sLR, 0.25),
    _WeightedPct(straightnessScorePct, 0.35),
    _WeightedPct(leadOk, 0.20),
    _WeightedPct(sImpact, 0.10),
    _WeightedPct(sSwing, 0.10),
  ]);

  final takt = geoMean3Pct(temporal, spatial, straightnessScorePct);
  final baseConfidence = geoMeanPct(temporal, spatial);
  final confidence = isGallop ? baseConfidence : baseConfidence * 0.6;

  return TaktScoreTriple(
    temporal: temporal.clamp(0.0, 100.0),
    spatial: spatial.clamp(0.0, 100.0),
    takt: takt.clamp(0.0, 100.0),
    confidence: confidence.clamp(0.0, 100.0),
  );
}

Map<String, double> computeLegScores({
  required double periodSec,
  required Map<String, double> legDevMs,
  required Map<String, double> impactPerLeg,
  required Map<String, double> swingPerLeg,
}) {
  final periodMs = max(1.0, periodSec * 1000.0);
  final timingNormMs = 0.20 * periodMs;

  final impactMedian = _median(impactPerLeg.values.toList());
  final swingMedian = _median(swingPerLeg.values.toList());
  final impactDenom = impactMedian.abs() < 1e-9 ? double.nan : impactMedian.abs();
  final swingDenom = swingMedian.abs() < 1e-9 ? double.nan : swingMedian.abs();

  final out = <String, double>{};
  for (final entry in legDevMs.entries) {
    final leg = entry.key;
    final dev = entry.value;
    if (!dev.isFinite) continue;

    final timingScore = scoreExp(dev.abs() / timingNormMs, k: 3.2);
    double impactScore = double.nan;
    final impact = impactPerLeg[leg];
    if (impact != null && impactDenom.isFinite && impactDenom > 0) {
      final err = (impact - impactMedian).abs() / impactDenom;
      impactScore = scoreExp(err, k: 3.0);
    }
    double swingScore = double.nan;
    final swing = swingPerLeg[leg];
    if (swing != null && swingDenom.isFinite && swingDenom > 0) {
      final err = (swing - swingMedian).abs() / swingDenom;
      swingScore = scoreExp(err, k: 3.0);
    }

    final legScore = weightedMeanPct([
      _WeightedPct(timingScore, 0.6),
      _WeightedPct(impactScore, 0.2),
      _WeightedPct(swingScore, 0.2),
    ]);
    out[leg] = legScore.clamp(0.0, 100.0);
  }
  return out;
}

double _median(List<double> values) {
  final a = values.where((v) => v.isFinite).toList();
  if (a.isEmpty) return double.nan;
  a.sort();
  final m = a.length ~/ 2;
  return a.length.isOdd ? a[m] : (a[m - 1] + a[m]) / 2.0;
}

class _WeightedPct {
  final double value;
  final double weight;
  const _WeightedPct(this.value, this.weight);
}
