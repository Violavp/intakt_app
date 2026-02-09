import 'dart:collection';
import 'dart:math';

class WalkScoreResult {
  final double score; // smaller = more walk-like
  final bool isWalk;
  final String template; // "S1" or "S2"
  final double periodSec;
  final double confidencePct;
  final bool trotLike;

  WalkScoreResult({
    required this.score,
    required this.isWalk,
    required this.template,
    required this.periodSec,
    required this.confidencePct,
    required this.trotLike,
  });
}

class WalkScoreEngine {
  final double windowSec;
  final double stepSec;
  final double walkThreshold;
  final double trotDiagThreshold;

  final Map<_WalkLeg, ListQueue<_WalkSample>> _buf = {
    _WalkLeg.VL: ListQueue<_WalkSample>(),
    _WalkLeg.VR: ListQueue<_WalkSample>(),
    _WalkLeg.HL: ListQueue<_WalkSample>(),
    _WalkLeg.HR: ListQueue<_WalkSample>(),
  };

  int? _lastEmitMs;

  WalkScoreEngine({
    this.windowSec = 6.0,
    this.stepSec = 2.0,
    this.walkThreshold = 0.10,
    this.trotDiagThreshold = 0.10,
  });

  void reset() {
    for (final b in _buf.values) {
      b.clear();
    }
    _lastEmitMs = null;
  }

  void addSample({
    required String leg,
    required double timestampMs,
    required double accZ,
    required double gyroZ,
    required double roll,
    required double pitch,
  }) {
    final walkLeg = _parseLeg(leg);
    if (walkLeg == null) return;
    final tMs = timestampMs.round();
    final b = _buf[walkLeg]!;
    b.add(_WalkSample(
      tMs: tMs,
      accZ: accZ,
      gyroZ: gyroZ,
      roll: roll,
      pitch: pitch,
    ));

    final cutoffMs = tMs - (windowSec * 1000).round() - 2000;
    while (b.isNotEmpty && b.first.tMs < cutoffMs) {
      b.removeFirst();
    }
  }

  WalkScoreResult? poll() {
    final lastTs = <int>[];
    for (final leg in _WalkLeg.values) {
      final b = _buf[leg]!;
      if (b.isEmpty) return null;
      lastTs.add(b.last.tMs);
    }
    final nowMs = lastTs.reduce(min);

    if (_lastEmitMs != null) {
      final dt = (nowMs - _lastEmitMs!) / 1000.0;
      if (dt < stepSec) return null;
    }

    final startMs = nowMs - (windowSec * 1000).round();
    final win = <_WalkLeg, List<_WalkSample>>{};
    for (final leg in _WalkLeg.values) {
      final b = _buf[leg]!;
      final w = b.where((s) => s.tMs >= startMs && s.tMs <= nowMs).toList();
      if (w.length < 30) return null;
      win[leg] = w;
    }

    final res = _walkScore(
      win,
      walkThreshold: walkThreshold,
      trotDiagThreshold: trotDiagThreshold,
    );
    _lastEmitMs = nowMs;
    return res;
  }

  _WalkLeg? _parseLeg(String leg) {
    switch (leg) {
      case "VL":
        return _WalkLeg.VL;
      case "VR":
        return _WalkLeg.VR;
      case "HL":
        return _WalkLeg.HL;
      case "HR":
        return _WalkLeg.HR;
      default:
        return null;
    }
  }
}

enum _WalkLeg { VL, VR, HL, HR }

class _WalkSample {
  final int tMs;
  final double accZ;
  final double gyroZ;
  final double roll;
  final double pitch;

  _WalkSample({
    required this.tMs,
    required this.accZ,
    required this.gyroZ,
    required this.roll,
    required this.pitch,
  });
}

WalkScoreResult _walkScore(
  Map<_WalkLeg, List<_WalkSample>> window, {
  double walkThreshold = 0.10,
  double trotDiagThreshold = 0.10,
}) {
  final signals = <_WalkLeg, List<double>>{};
  final times = <_WalkLeg, List<int>>{};

  for (final leg in _WalkLeg.values) {
    final w = window[leg]!..sort((a, b) => a.tMs.compareTo(b.tMs));
    times[leg] = w.map((e) => e.tMs).toList();

    final acc = _zscore(w.map((e) => e.accZ).toList());
    final gyro = _zscore(w.map((e) => e.gyroZ).toList());
    final dRoll = _zscore(_diff(w.map((e) => e.roll).toList()));
    final dPitch = _zscore(_diff(w.map((e) => e.pitch).toList()));

    final n = min(min(acc.length, gyro.length), min(dRoll.length, dPitch.length));
    final s = List<double>.filled(n, 0.0);
    for (int i = 0; i < n; i++) {
      s[i] = 0.20 * acc[i] + 0.50 * gyro[i] + 0.15 * dRoll[i] + 0.15 * dPitch[i];
    }
    signals[leg] = s;
  }

  final refLeg = _selectRefLeg(signals, times);
  if (refLeg == null) {
    return WalkScoreResult(
      score: 1.0,
      isWalk: false,
      template: "S1",
      periodSec: 0,
      confidencePct: 0.0,
      trotLike: false,
    );
  }
  final refTimes = times[refLeg]!;
  final dtSec = _medianDiffSec(refTimes);
  if (dtSec <= 0) {
    return WalkScoreResult(
      score: 1.0,
      isWalk: false,
      template: "S1",
      periodSec: 0,
      confidencePct: 0.0,
      trotLike: false,
    );
  }

  final periodSec = _estimatePeriodSec(
    signals[refLeg]!,
    dtSec,
    minPeriodSec: 0.7,
    maxPeriodSec: 2.0,
  );
  if (periodSec == null) {
    return WalkScoreResult(
      score: 1.0,
      isWalk: false,
      template: "S1",
      periodSec: 0,
      confidencePct: 0.0,
      trotLike: false,
    );
  }

  double phase(_WalkLeg a, _WalkLeg b) {
    final pa = signals[a]!;
    final pb = signals[b]!;
    final n = min(pa.length, pb.length);
    final aa = pa.sublist(pa.length - n);
    final bb = pb.sublist(pb.length - n);
    final tau = _bestLagSecAbsCorr(aa, bb, dtSec, maxLagSec: periodSec / 2);
    return _mod1(tau / periodSec);
  }

  double qual(_WalkLeg a, _WalkLeg b) {
    final pa = signals[a]!;
    final pb = signals[b]!;
    final n = min(pa.length, pb.length);
    final aa = pa.sublist(pa.length - n);
    final bb = pb.sublist(pb.length - n);
    return _bestAbsCorrValue(aa, bb, dtSec, maxLagSec: periodSec / 2);
  }

  final pHLVL = phase(_WalkLeg.HL, _WalkLeg.VL);
  final qHLVL = qual(_WalkLeg.HL, _WalkLeg.VL);
  final pVLHR = phase(_WalkLeg.VL, _WalkLeg.HR);
  final qVLHR = qual(_WalkLeg.VL, _WalkLeg.HR);
  final pHRVR = phase(_WalkLeg.HR, _WalkLeg.VR);
  final qHRVR = qual(_WalkLeg.HR, _WalkLeg.VR);
  final pVRHL = phase(_WalkLeg.VR, _WalkLeg.HL);
  final qVRHL = qual(_WalkLeg.VR, _WalkLeg.HL);

  final pHLHR = phase(_WalkLeg.HL, _WalkLeg.HR);
  final qHLHR = qual(_WalkLeg.HL, _WalkLeg.HR);
  final pVLVR = phase(_WalkLeg.VL, _WalkLeg.VR);
  final qVLVR = qual(_WalkLeg.VL, _WalkLeg.VR);

  final diag1 = _wrap01(pVLHR - 0.0);
  final diag2 = _wrap01(pVRHL - 0.0);
  final isTrotLike = (diag1 < trotDiagThreshold && qVLHR > 0.2) ||
      (diag2 < trotDiagThreshold && qVRHL > 0.2);

  _ScoreQuality scoreTemplateS1() {
    final items = <_Item>[
      _Item(pHLVL, 0.25, qHLVL),
      _Item(pVLHR, 0.25, qVLHR),
      _Item(pHRVR, 0.25, qHRVR),
      _Item(pVRHL, 0.25, qVRHL),
      _Item(pHLHR, 0.50, qHLHR),
      _Item(pVLVR, 0.50, qVLVR),
    ];
    return _scoreWithQuality(items);
  }

  _ScoreQuality scoreTemplateS2() {
    final pHRVR_ = pHRVR;
    final qHRVR_ = qHRVR;
    final pVRHL_ = pVRHL;
    final qVRHL_ = qVRHL;
    final pHLVL_ = pHLVL;
    final qHLVL_ = qHLVL;
    final pVLHR_ = pVLHR;
    final qVLHR_ = qVLHR;

    final pHRHL_ = phase(_WalkLeg.HR, _WalkLeg.HL);
    final qHRHL_ = qual(_WalkLeg.HR, _WalkLeg.HL);
    final pVRVL_ = phase(_WalkLeg.VR, _WalkLeg.VL);
    final qVRVL_ = qual(_WalkLeg.VR, _WalkLeg.VL);

    final items = <_Item>[
      _Item(pHRVR_, 0.25, qHRVR_),
      _Item(pVRHL_, 0.25, qVRHL_),
      _Item(pHLVL_, 0.25, qHLVL_),
      _Item(pVLHR_, 0.25, qVLHR_),
      _Item(pHRHL_, 0.50, qHRHL_),
      _Item(pVRVL_, 0.50, qVRVL_),
    ];
    return _scoreWithQuality(items);
  }

  final s1 = scoreTemplateS1();
  final s2 = scoreTemplateS2();
  final bestScore = min(s1.score, s2.score);
  final secondScore = max(s1.score, s2.score);
  final bestTemplate = (s1.score <= s2.score) ? "S1" : "S2";
  final bestQuality = (s1.score <= s2.score) ? s1.avgQuality : s2.avgQuality;

  final separation =
      (secondScore - bestScore) / max(secondScore, 1e-6);
  final confidencePct =
      ((0.7 * bestQuality) + (0.3 * separation)).clamp(0.0, 1.0) * 100.0;
  final isWalk = !isTrotLike && bestScore < walkThreshold;

  return WalkScoreResult(
    score: bestScore,
    isWalk: isWalk,
    template: bestTemplate,
    periodSec: periodSec,
    confidencePct: confidencePct,
    trotLike: isTrotLike,
  );
}

class _Item {
  final double phase;
  final double target;
  final double weight;
  _Item(this.phase, this.target, this.weight);
}

double _weightedPhaseError(List<_Item> items) {
  double wSum = 0.0;
  double eSum = 0.0;
  for (final it in items) {
    final w = max(0.0, it.weight);
    final e = _wrap01(it.phase - it.target);
    wSum += w;
    eSum += w * e;
  }
  if (wSum <= 1e-9) return 1.0;
  return eSum / wSum;
}

_ScoreQuality _scoreWithQuality(List<_Item> items) {
  final score = _weightedPhaseError(items);
  if (items.isEmpty) {
    return const _ScoreQuality(score: 1.0, avgQuality: 0.0);
  }
  double qSum = 0.0;
  for (final it in items) {
    qSum += max(0.0, it.weight);
  }
  final avgQuality = (qSum / items.length).clamp(0.0, 1.0);
  return _ScoreQuality(score: score, avgQuality: avgQuality);
}

double _wrap01(double d) {
  final x = d.abs();
  return min(x, 1.0 - x);
}

double _mod1(double x) {
  var y = x % 1.0;
  if (y < 0) y += 1.0;
  return y;
}

List<double> _diff(List<double> x) {
  if (x.length < 2) return [];
  final out = List<double>.filled(x.length - 1, 0.0);
  for (int i = 1; i < x.length; i++) {
    out[i - 1] = x[i] - x[i - 1];
  }
  return out;
}

List<double> _zscore(List<double> x) {
  if (x.isEmpty) return [];
  double mean = 0.0;
  for (final v in x) mean += v;
  mean /= x.length;

  double varSum = 0.0;
  for (final v in x) {
    final d = v - mean;
    varSum += d * d;
  }
  varSum /= max(1, x.length);
  final std = sqrt(varSum);
  final denom = std < 1e-9 ? 1.0 : std;

  return x.map((v) => (v - mean) / denom).toList();
}

double _medianDiffSec(List<int> tMs) {
  if (tMs.length < 3) return 0.0;
  final diffs = <double>[];
  for (int i = 1; i < tMs.length; i++) {
    final dMs = (tMs[i] - tMs[i - 1]).toDouble();
    if (dMs > 0) diffs.add(dMs / 1000.0);
  }
  if (diffs.isEmpty) return 0.0;
  diffs.sort();
  return diffs[diffs.length ~/ 2];
}

double? _estimatePeriodSec(
  List<double> x,
  double dtSec, {
  required double minPeriodSec,
  required double maxPeriodSec,
}) {
  final n = x.length;
  if (n < 50) return null;

  final minLag = max(1, (minPeriodSec / dtSec).round());
  final maxLag = min(n - 2, (maxPeriodSec / dtSec).round());
  if (maxLag <= minLag) return null;

  double best = -1e9;
  int bestLag = minLag;
  final corr = List<double>.filled(maxLag - minLag + 1, 0.0);

  for (int lag = minLag; lag <= maxLag; lag++) {
    double s = 0.0;
    final m = n - lag;
    for (int i = 0; i < m; i++) {
      s += x[i] * x[i + lag];
    }
    s /= max(1, m);
    corr[lag - minLag] = s;
    if (s > best) {
      best = s;
      bestLag = lag;
    }
  }
  final threshold = best * 0.35;
  int? peakLag;
  for (int i = 1; i < corr.length - 1; i++) {
    final v = corr[i];
    if (v >= corr[i - 1] && v >= corr[i + 1] && v >= threshold) {
      peakLag = minLag + i;
      break;
    }
  }
  final chosenLag = peakLag ?? bestLag;
  return chosenLag * dtSec;
}

double _bestLagSecAbsCorr(
  List<double> a,
  List<double> b,
  double dtSec, {
  required double maxLagSec,
}) {
  final n = min(a.length, b.length);
  if (n < 30) return 0.0;

  final maxLag = min(n - 2, (maxLagSec / dtSec).round());
  int bestLag = 0;
  double best = -1e9;

  for (int lag = -maxLag; lag <= maxLag; lag++) {
    double s = 0.0;
    int cnt = 0;
    final iStart = max(0, -lag);
    final iEnd = min(n, n - lag);
    for (int i = iStart; i < iEnd; i++) {
      s += a[i] * b[i + lag];
      cnt++;
    }
    if (cnt < 10) continue;

    final corr = (s / cnt).abs();
    if (corr > best) {
      best = corr;
      bestLag = lag;
    }
  }
  return bestLag * dtSec;
}

double _bestAbsCorrValue(
  List<double> a,
  List<double> b,
  double dtSec, {
  required double maxLagSec,
}) {
  final n = min(a.length, b.length);
  if (n < 30) return 0.0;

  final maxLag = min(n - 2, (maxLagSec / dtSec).round());
  double best = 0.0;

  for (int lag = -maxLag; lag <= maxLag; lag++) {
    double s = 0.0;
    int cnt = 0;
    final iStart = max(0, -lag);
    final iEnd = min(n, n - lag);
    for (int i = iStart; i < iEnd; i++) {
      s += a[i] * b[i + lag];
      cnt++;
    }
    if (cnt < 10) continue;

    final corr = (s / cnt).abs();
    if (corr > best) best = corr;
  }
  return best;
}

_WalkLeg? _selectRefLeg(
  Map<_WalkLeg, List<double>> signals,
  Map<_WalkLeg, List<int>> times,
) {
  _WalkLeg? bestLeg;
  double bestScore = -1e9;
  for (final leg in _WalkLeg.values) {
    final s = signals[leg] ?? const <double>[];
    final t = times[leg] ?? const <int>[];
    if (s.length < 30 || t.length < 3) continue;
    final energy = _robustEnergy(s);
    final score = energy * sqrt(s.length.toDouble());
    if (score > bestScore) {
      bestScore = score;
      bestLeg = leg;
    }
  }
  return bestLeg;
}

double _std(List<double> values) {
  if (values.isEmpty) return 0.0;
  double mean = 0.0;
  for (final v in values) {
    mean += v;
  }
  mean /= values.length;
  double varSum = 0.0;
  for (final v in values) {
    final d = v - mean;
    varSum += d * d;
  }
  varSum /= values.length;
  return sqrt(varSum);
}

double _robustEnergy(List<double> values) {
  if (values.isEmpty) return 0.0;
  double mean = 0.0;
  for (final v in values) {
    mean += v;
  }
  mean /= values.length;
  final s = _std(values);
  if (s <= 1e-9) return 0.0;
  final lo = mean - 5 * s;
  final hi = mean + 5 * s;
  final clipped = values.map((v) => v.clamp(lo, hi).toDouble()).toList();
  return _std(clipped);
}

class _ScoreQuality {
  final double score;
  final double avgQuality;
  const _ScoreQuality({required this.score, required this.avgQuality});
}
