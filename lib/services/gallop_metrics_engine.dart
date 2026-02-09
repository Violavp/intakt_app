import 'dart:collection';
import 'dart:math';

class GallopLiveMetrics {
  final bool isGallop;
  final String lead; // "links", "rechts", "unbekannt"
  final double periodSec;
  final double cyclesPerMin;
  final double hoofbeatsPerMin;
  final double diagonalPairTightMs;
  final double otherDiagonalMs;
  final double gallopScorePct;
  final double confidencePct;
  final Map<String, double> legDevMs;
  final String worstLeg;
  final double impactCv;
  final double swingCv;
  final Map<String, double> impactPerLeg;
  final Map<String, double> swingPerLeg;

  GallopLiveMetrics({
    required this.isGallop,
    required this.lead,
    required this.periodSec,
    required this.cyclesPerMin,
    required this.hoofbeatsPerMin,
    required this.diagonalPairTightMs,
    required this.otherDiagonalMs,
    required this.gallopScorePct,
    required this.confidencePct,
    required this.legDevMs,
    required this.worstLeg,
    required this.impactCv,
    required this.swingCv,
    required this.impactPerLeg,
    required this.swingPerLeg,
  });
}

class GallopMetricsEngine {
  static const _legs = ["VL", "VR", "HL", "HR"];

  final double windowSec;
  final double stepSec;
  final double peakZ;
  final double maxSyncDiagMs;
  final double minOtherDiagMs;
  final double maxScoreForGallop;

  final Map<String, ListQueue<_AccSample>> _buf = {
    for (final l in _legs) l: ListQueue<_AccSample>(),
  };

  int? _lastEmitMs;

  GallopMetricsEngine({
    this.windowSec = 8.0,
    this.stepSec = 2.0,
    this.peakZ = 1.0,
    this.maxSyncDiagMs = 300.0,
    this.minOtherDiagMs = 80.0,
    this.maxScoreForGallop = 0.40,
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
    required double pitch,
  }) {
    final b = _buf[leg];
    if (b == null) return;
    final tMs = timestampMs.round();
    b.add(_AccSample(tMs, accZ, pitch));

    final cutoffMs = tMs - (windowSec * 1000).round() - 2000;
    while (b.isNotEmpty && b.first.tMs < cutoffMs) {
      b.removeFirst();
    }
  }

  GallopLiveMetrics? poll() {
    final last = <int>[];
    for (final leg in _legs) {
      final b = _buf[leg]!;
      if (b.isEmpty) return null;
      last.add(b.last.tMs);
    }
    final nowMs = last.reduce(min);

    if (_lastEmitMs != null) {
      final dt = (nowMs - _lastEmitMs!) / 1000.0;
      if (dt < stepSec) return null;
    }

    final startMs = nowMs - (windowSec * 1000).round();
    final win = <String, List<_AccSample>>{};
    for (final leg in _legs) {
      final src = _buf[leg]!;
      final slice =
          src.where((s) => s.tMs >= startMs && s.tMs <= nowMs).toList()
            ..sort((a, b) => a.tMs.compareTo(b.tMs));
      if (slice.length < 80) return null;
      win[leg] = slice;
    }

    final metrics = _compute(win);
    _lastEmitMs = nowMs;
    return metrics;
  }

  GallopLiveMetrics? _compute(Map<String, List<_AccSample>> win) {
    final zSig = <String, List<double>>{};
    final tSig = <String, List<int>>{};
    for (final leg in _legs) {
      final s = win[leg]!;
      final x = s.map((e) => e.accZ.abs()).toList();
      final z = _zscore(_smooth3(x));
      zSig[leg] = z;
      tSig[leg] = s.map((e) => e.tMs).toList();
    }

    final refLeg = _selectRefLeg(zSig);
    if (refLeg == null) return null;
    final dtMs = _medianDiffMs(win[refLeg]!);
    if (dtMs <= 0) return null;
    final dtSec = dtMs / 1000.0;

    final impactPerLeg = <String, double>{};
    final swingPerLeg = <String, double>{};
    final impactAmps = <double>[];
    final swingAmps = <double>[];
    for (final leg in _legs) {
      final samples = win[leg]!;
      final impact = _impactAmplitude(samples);
      final swing = _swingAmplitude(samples);
      impactPerLeg[leg] = impact;
      swingPerLeg[leg] = swing;
      impactAmps.add(impact);
      swingAmps.add(swing);
    }
    final impactCv = _cv(impactAmps);
    final swingCv = _cv(swingAmps);

    final periodSec = _estimatePeriodSec(
          zSig[refLeg]!,
          dtSec,
          minT: 0.7,
          maxT: 1.8,
        ) ??
        1.1;

    final refractoryMs =
        _clampInt((0.65 * periodSec * 1000).round(), 300, 1200);
    final peaks = <String, List<int>>{};
    for (final leg in _legs) {
      peaks[leg] = _detectPeaksMs(
        tSig[leg]!,
        zSig[leg]!,
        zTh: peakZ,
        refractoryMs: refractoryMs,
      );
      if (peaks[leg]!.length < 4) return null;
    }

    final left = _template(
      peaks,
      trailing: "HR",
      diag1: "HL",
      diag2: "VR",
      lead: "VL",
      other1: "HR",
      other2: "VL",
    );
    final right = _template(
      peaks,
      trailing: "HL",
      diag1: "HR",
      diag2: "VL",
      lead: "VR",
      other1: "HL",
      other2: "VR",
    );

    if (left == null && right == null) return null;

    String lead;
    _Tpl best;
    _Tpl? second;
    if (right == null || (left != null && left.score < right.score)) {
      lead = "links";
      best = left!;
      second = right;
    } else {
      lead = "rechts";
      best = right!;
      second = left;
    }

    final rolePhase = <String, double>{};
    if (lead == "links") {
      rolePhase["HR"] = 0.0;
      rolePhase["HL"] = best.phiDiagMed;
      rolePhase["VR"] = best.phiDiagMed;
      rolePhase["VL"] = best.phiLeadMed;
    } else {
      rolePhase["HL"] = 0.0;
      rolePhase["HR"] = best.phiDiagMed;
      rolePhase["VL"] = best.phiDiagMed;
      rolePhase["VR"] = best.phiLeadMed;
    }

    final legDevMs = <String, double>{};
    for (final leg in _legs) {
      final target = rolePhase[leg];
      if (target == null) {
        legDevMs[leg] = double.nan;
        continue;
      }
      final phis = best.phiLeg[leg]!.where((v) => v.isFinite).toList();
      if (phis.isEmpty) {
        legDevMs[leg] = double.nan;
        continue;
      }
      final devMs = _median(
        phis.map((p) => (p - target) * best.durMedMs).toList(),
      );
      legDevMs[leg] = devMs;
    }

    String worstLeg = "unbekannt";
    double worstAbs = -1;
    for (final leg in _legs) {
      final v = legDevMs[leg]!;
      if (!v.isFinite) continue;
      final a = v.abs();
      if (a > worstAbs) {
        worstAbs = a;
        worstLeg = leg;
      }
    }

    final score = best.score;
    final scorePct =
        100.0 * (1.0 - _clamp(score / maxScoreForGallop, 0.0, 1.0));
    final sep = (second != null && second.score.isFinite && second.score > 1e-9)
        ? ((second.score - best.score) / second.score).clamp(0.0, 1.0)
        : 0.0;
    final usedScore = (best.usedCount / 6.0).clamp(0.0, 1.0);
    final confidencePct =
        ((0.7 * usedScore + 0.3 * sep).clamp(0.0, 1.0)) * 100.0;

    final diagMs = best.pairMedMs;
    final otherMs = best.otherMedMs;
    final isGallop = (score <= maxScoreForGallop) &&
        (diagMs <= maxSyncDiagMs) &&
        (otherMs >= minOtherDiagMs);

    final cyclesPerMin = 60.0 / max(1e-6, best.durMedMs / 1000.0);
    final hoofbeatsPerMin = 3.0 * cyclesPerMin;

    return GallopLiveMetrics(
      isGallop: isGallop,
      lead: isGallop ? lead : "unbekannt",
      periodSec: best.durMedMs / 1000.0,
      cyclesPerMin: cyclesPerMin,
      hoofbeatsPerMin: hoofbeatsPerMin,
      diagonalPairTightMs: diagMs,
      otherDiagonalMs: otherMs,
      gallopScorePct: scorePct,
      confidencePct: confidencePct,
      legDevMs: legDevMs,
      worstLeg: worstLeg,
      impactCv: impactCv,
      swingCv: swingCv,
      impactPerLeg: impactPerLeg,
      swingPerLeg: swingPerLeg,
    );
  }

  _Tpl? _template(
    Map<String, List<int>> peaks, {
    required String trailing,
    required String diag1,
    required String diag2,
    required String lead,
    required String other1,
    required String other2,
  }) {
    final trail = peaks[trailing]!;
    if (trail.length < 4) return null;

    final strideDursMs = <double>[];
    final pairDiffMs = <double>[];
    final otherDiffMs = <double>[];
    final phiDiag = <double>[];
    final phiLead = <double>[];

    final phiLeg = <String, List<double>>{
      for (final l in _legs) l: <double>[],
    };

    int used = 0;

    for (int i = 0; i < trail.length - 1; i++) {
      final t0 = trail[i];
      final t1 = trail[i + 1];
      final durMs = (t1 - t0).toDouble();
      if (durMs < 700 || durMs > 1800) continue;

      int? first(String leg) => _firstInInterval(peaks[leg]!, t0, t1);

      final td1 = first(diag1);
      final td2 = first(diag2);
      final tl = first(lead);
      if (td1 == null || td2 == null || tl == null) continue;

      used++;

      final to1 = first(other1);
      final to2 = first(other2);

      strideDursMs.add(durMs);
      pairDiffMs.add((td1 - td2).abs().toDouble());
      otherDiffMs.add((to1 != null && to2 != null)
          ? (to1 - to2).abs().toDouble()
          : double.nan);

      final phiD = (((td1 + td2) / 2.0) - t0) / durMs;
      final phiL = (tl - t0) / durMs;
      phiDiag.add(phiD);
      phiLead.add(phiL);

      for (final leg in _legs) {
        final te = first(leg);
        phiLeg[leg]!.add(te == null ? double.nan : (te - t0) / durMs);
      }
    }

    if (used < 3) return null;

    final durMedMs = _nanMedian(strideDursMs);
    final pairMedMs = _nanMedian(pairDiffMs);
    final otherMedMs = _nanMedian(otherDiffMs);
    final phiDiagMed = _nanMedian(phiDiag);
    final phiLeadMed = _nanMedian(phiLead);

    final madDiag = _mad(phiDiag, phiDiagMed);
    final madLead = _mad(phiLead, phiLeadMed);

    final pairRatio = pairMedMs / max(1.0, durMedMs);
    final otherRatio =
        otherMedMs.isFinite ? otherMedMs / max(1.0, durMedMs) : double.nan;

    const minDiagPhase = 0.20;
    const maxDiagPhase = 0.65;
    const minLeadPhase = 0.55;
    const maxLeadPhase = 0.92;
    const minLeadAfterDiag = 0.10;
    const minFloat = 0.03;
    const maxFloat = 0.20;

    double penalty = 0.0;
    penalty += 1.2 * _distToRange(phiDiagMed, minDiagPhase, maxDiagPhase);
    penalty += 1.6 * _distToRange(phiLeadMed, minLeadPhase, maxLeadPhase);

    final orderGap = (phiLeadMed - phiDiagMed);
    if (orderGap.isFinite && orderGap < minLeadAfterDiag) {
      penalty += 2.0 * (minLeadAfterDiag - orderGap);
    }

    final floatFrac = 1.0 - phiLeadMed;
    penalty += 1.0 * _distToRange(floatFrac, minFloat, maxFloat);

    if (otherRatio.isFinite && otherRatio < 0.18) {
      penalty += (0.18 - otherRatio) * 0.8;
    }

    final score = 0.50 * pairRatio +
        0.20 * madDiag +
        0.15 * madLead +
        1.00 * penalty;

    return _Tpl(
      score: score,
      durMedMs: durMedMs,
      pairMedMs: pairMedMs,
      otherMedMs: otherMedMs.isFinite ? otherMedMs : double.nan,
      phiDiagMed: phiDiagMed,
      phiLeadMed: phiLeadMed,
      phiLeg: phiLeg,
      usedCount: used,
    );
  }

  List<int> _detectPeaksMs(
    List<int> tMs,
    List<double> z, {
    required double zTh,
    required int refractoryMs,
  }) {
    final peaks = <int>[];
    int last = -1 << 60;

    for (int i = 1; i < z.length - 1; i++) {
      if (z[i] < zTh) continue;
      if (z[i] < z[i - 1]) continue;
      if (z[i] < z[i + 1]) continue;

      final t = tMs[i];
      if (t - last >= refractoryMs) {
        peaks.add(t);
        last = t;
      }
    }
    return peaks;
  }

  int _medianDiffMs(List<_AccSample> s) {
    if (s.length < 3) return 0;
    final diffs = <int>[];
    for (int i = 1; i < s.length; i++) {
      diffs.add(s[i].tMs - s[i - 1].tMs);
    }
    if (diffs.isEmpty) return 0;
    diffs.sort();
    return diffs[diffs.length ~/ 2];
  }

  double? _estimatePeriodSec(
    List<double> x,
    double dtSec, {
    required double minT,
    required double maxT,
  }) {
    if (x.length < 100) return null;
    final minLag = max(1, (minT / dtSec).round());
    final maxLag = min(x.length - 2, (maxT / dtSec).round());
    if (maxLag <= minLag) return null;

    double best = -1e300;
    int bestLag = minLag;
    final corr = List<double>.filled(maxLag - minLag + 1, 0.0);

    for (int lag = minLag; lag <= maxLag; lag++) {
      double s = 0.0;
      final n = x.length - lag;
      for (int i = 0; i < n; i++) {
        s += x[i] * x[i + lag];
      }
      s /= max(1, n);
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

  int? _firstInInterval(List<int> sortedPeaks, int start, int end) {
    int lo = 0, hi = sortedPeaks.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (sortedPeaks[mid] < start) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo >= sortedPeaks.length) return null;
    final v = sortedPeaks[lo];
    return (v < end) ? v : null;
  }

  List<double> _smooth3(List<double> x) {
    if (x.length < 3) return x;
    final y = List<double>.from(x);
    for (int i = 1; i < x.length - 1; i++) {
      y[i] = (x[i - 1] + x[i] + x[i + 1]) / 3.0;
    }
    return y;
  }

  double _impactAmplitude(List<_AccSample> samples) {
    final acc = samples.map((s) => s.accZ.abs()).toList();
    if (acc.length < 3) return 0.0;
    final smooth = _smooth3(acc);
    final mean = smooth.reduce((a, b) => a + b) / smooth.length;
    final std = _std(smooth);
    final threshold = mean + 0.5 * std;
    final peaks = <double>[];
    for (int i = 1; i < smooth.length - 1; i++) {
      final v = smooth[i];
      if (v < threshold) continue;
      if (v >= smooth[i - 1] && v >= smooth[i + 1]) {
        peaks.add(v);
      }
    }
    if (peaks.isEmpty) {
      return _median(smooth);
    }
    return _median(peaks);
  }

  double _swingAmplitude(List<_AccSample> samples) {
    final pitch = samples.map((s) => s.pitch).toList();
    if (pitch.length < 3) return 0.0;
    final dPitch = <double>[];
    for (int i = 1; i < pitch.length; i++) {
      dPitch.add(pitch[i] - pitch[i - 1]);
    }
    return _rms(dPitch);
  }

  double _rms(List<double> values) {
    if (values.isEmpty) return 0.0;
    double sum = 0.0;
    for (final v in values) {
      sum += v * v;
    }
    return sqrt(sum / values.length);
  }

  double _cv(List<double> values) {
    final finite = values.where((v) => v.isFinite && v > 0).toList();
    if (finite.length < 2) return double.nan;
    double mean = 0.0;
    for (final v in finite) {
      mean += v;
    }
    mean /= finite.length;
    if (mean <= 1e-9) return double.nan;
    double varSum = 0.0;
    for (final v in finite) {
      final d = v - mean;
      varSum += d * d;
    }
    varSum /= finite.length;
    return sqrt(varSum) / mean;
  }

  List<double> _zscore(List<double> x) {
    final n = x.length;
    if (n == 0) return <double>[];
    double sum = 0.0;
    for (final v in x) {
      sum += v;
    }
    final mean = sum / n;

    double ss = 0.0;
    for (final v in x) {
      final d = v - mean;
      ss += d * d;
    }
    final std = sqrt(ss / max(1, n - 1));
    final s = (std.isFinite && std > 1e-9) ? std : 1.0;

    return x.map((v) => (v - mean) / s).toList();
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

String? _selectRefLeg(Map<String, List<double>> signals) {
  String? bestLeg;
  double bestEnergy = -1.0;
  for (final entry in signals.entries) {
    final energy = _robustEnergy(entry.value);
    if (energy > bestEnergy) {
      bestEnergy = energy;
      bestLeg = entry.key;
    }
  }
  return bestLeg;
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

  double _median(List<double> x) {
    final a = List<double>.from(x)..sort();
    final m = a.length ~/ 2;
    return a.length.isOdd ? a[m] : (a[m - 1] + a[m]) / 2.0;
  }

  double _nanMedian(List<double> x) {
    final a = x.where((v) => v.isFinite).toList();
    if (a.isEmpty) return double.nan;
    a.sort();
    final m = a.length ~/ 2;
    return a.length.isOdd ? a[m] : (a[m - 1] + a[m]) / 2.0;
  }

double _mad(List<double> x, double med) {
  final a =
      x.where((v) => v.isFinite).map((v) => (v - med).abs()).toList();
  if (a.isEmpty) return 0.0;
  a.sort();
  return a[a.length ~/ 2];
}

double _distToRange(double x, double lo, double hi) {
  if (!x.isFinite) return 0.0;
  if (x < lo) return lo - x;
  if (x > hi) return x - hi;
  return 0.0;
}

double _clamp(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);
  int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
}

class _AccSample {
  final int tMs;
  final double accZ;
  final double pitch;
  _AccSample(this.tMs, this.accZ, this.pitch);
}

class _Tpl {
  final double score;
  final double durMedMs;
  final double pairMedMs;
  final double otherMedMs;
  final double phiDiagMed;
  final double phiLeadMed;
  final Map<String, List<double>> phiLeg;
  final int usedCount;

  _Tpl({
    required this.score,
    required this.durMedMs,
    required this.pairMedMs,
    required this.otherMedMs,
    required this.phiDiagMed,
    required this.phiLeadMed,
    required this.phiLeg,
    required this.usedCount,
  });
}
