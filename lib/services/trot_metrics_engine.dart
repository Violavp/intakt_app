import 'dart:collection';
import 'dart:math';

class TrotLiveMetrics {
  final double periodSec;
  final double freqCyclesPerMin;
  final double diagBeatsPerMin;
  final double trotScore;
  final bool isTrot;
  final String bestMode;
  final Map<String, double> legDevMs;
  final String worstLeg;
  final double diagPhaseDeg;
  final double diagPhaseDeg2;
  final double lateralFrontDeg;
  final double lateralHindDeg;
  final double stabilityPct;
  final double confidencePct;
  final double impactCv;
  final double swingCv;
  final Map<String, double> impactPerLeg;
  final Map<String, double> swingPerLeg;

  TrotLiveMetrics({
    required this.periodSec,
    required this.freqCyclesPerMin,
    required this.diagBeatsPerMin,
    required this.trotScore,
    required this.isTrot,
    required this.bestMode,
    required this.legDevMs,
    required this.worstLeg,
    required this.diagPhaseDeg,
    required this.diagPhaseDeg2,
    required this.lateralFrontDeg,
    required this.lateralHindDeg,
    required this.stabilityPct,
    required this.confidencePct,
    required this.impactCv,
    required this.swingCv,
    required this.impactPerLeg,
    required this.swingPerLeg,
  });
}

class TrotMetricsEngine {
  final double windowSec;
  final double stepSec;
  final double scoreThreshold;
  final double diagPhaseThreshold;
  final double lateralPhaseThreshold;
  final double minDiagQuality;
  final bool debug;

  final Map<_TrotLeg, ListQueue<_TrotSample>> _buf = {
    _TrotLeg.VL: ListQueue<_TrotSample>(),
    _TrotLeg.VR: ListQueue<_TrotSample>(),
    _TrotLeg.HL: ListQueue<_TrotSample>(),
    _TrotLeg.HR: ListQueue<_TrotSample>(),
  };

  int? _lastEmitMs;

  TrotMetricsEngine({
    this.windowSec = 6.0,
    this.stepSec = 2.0,
    this.scoreThreshold = 0.85,
    this.diagPhaseThreshold = 0.25,
    this.lateralPhaseThreshold = 0.35,
    this.minDiagQuality = 0.15,
    this.debug = true,
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
    final trotLeg = _parseLeg(leg);
    if (trotLeg == null) return;
    final tMs = timestampMs.round();
    final b = _buf[trotLeg]!;
    b.add(_TrotSample(
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

  TrotLiveMetrics? poll() {
    final last = <int>[];
    for (final leg in _TrotLeg.values) {
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
    final win = <_TrotLeg, List<_TrotSample>>{};
    for (final leg in _TrotLeg.values) {
      final w = _buf[leg]!
          .where((s) => s.tMs >= startMs && s.tMs <= nowMs)
          .toList()
        ..sort((a, b) => a.tMs.compareTo(b.tMs));
      if (w.length < 120) return null;
      win[leg] = w;
    }

    final m = _computeTrot(win);
    _lastEmitMs = nowMs;
    return m;
  }

  _TrotLeg? _parseLeg(String leg) {
    switch (leg) {
      case "VL":
        return _TrotLeg.VL;
      case "VR":
        return _TrotLeg.VR;
      case "HL":
        return _TrotLeg.HL;
      case "HR":
        return _TrotLeg.HR;
      default:
        return null;
    }
  }

  TrotLiveMetrics _computeTrot(Map<_TrotLeg, List<_TrotSample>> w) {
    final rel = _computeRelational(w);
    if (rel == null) {
      return TrotLiveMetrics(
        periodSec: 1.0,
        freqCyclesPerMin: 0.0,
        diagBeatsPerMin: 0.0,
        trotScore: 1.0,
        isTrot: false,
        bestMode: 'accZ+pitch',
        legDevMs: const {
          'VL': 0.0,
          'VR': 0.0,
          'HL': 0.0,
          'HR': 0.0,
        },
        worstLeg: 'VL',
        diagPhaseDeg: 0.0,
        diagPhaseDeg2: 0.0,
        lateralFrontDeg: 0.0,
        lateralHindDeg: 0.0,
        stabilityPct: 0.0,
        confidencePct: 0.0,
        impactCv: double.nan,
        swingCv: double.nan,
        impactPerLeg: const {
          'VL': 0.0,
          'VR': 0.0,
          'HL': 0.0,
          'HR': 0.0,
        },
        swingPerLeg: const {
          'VL': 0.0,
          'VR': 0.0,
          'HL': 0.0,
          'HR': 0.0,
        },
      );
    }

    final periodSec = rel.periodSec;
    final trotScoreRel = rel.trotScore;
    final trotScore = (1.0 - trotScoreRel).clamp(0.0, 1.0);
    final confidencePct = (rel.confidence * 100.0).clamp(0.0, 100.0);

    final pVLHR = _phaseFracFromLag(rel.vlHr.lag, rel.periodSamples);
    final pVRHL = _phaseFracFromLag(rel.vrHl.lag, rel.periodSamples);
    final pVLVR = _phaseFracFromLag(rel.vlVr.lag, rel.periodSamples);
    final pHLHR = _phaseFracFromLag(rel.hlHr.lag, rel.periodSamples);
    final pVLHL = _phaseFracFromLag(rel.vlHl.lag, rel.periodSamples);

    final phi = <_TrotLeg, double>{
      _TrotLeg.VL: 0.0,
      _TrotLeg.HR: pVLHR,
      _TrotLeg.VR: pVLVR,
      _TrotLeg.HL: pVLHL,
    };

    const target = <_TrotLeg, double>{
      _TrotLeg.VL: 0.0,
      _TrotLeg.HR: 0.0,
      _TrotLeg.VR: 0.5,
      _TrotLeg.HL: 0.5,
    };

    final devMs = <_TrotLeg, double>{};
    for (final leg in target.keys) {
      final d =
          _signedWrap(phi[leg]! - target[leg]!) * periodSec * 1000.0;
      devMs[leg] = d;
    }

    _TrotLeg worst = _TrotLeg.HL;
    double worstAbs = -1;
    for (final e in devMs.entries) {
      final a = e.value.abs();
      if (a > worstAbs) {
        worstAbs = a;
        worst = e.key;
      }
    }

    final diagDeg1 = _wrapDeg(pVLHR);
    final diagDeg2 = _wrapDeg(pVRHL);
    final latFrontDeg = _wrapDeg(pVLVR);
    final latHindDeg = _wrapDeg(pHLHR);

    final minTrotScore = (1.0 - scoreThreshold).clamp(0.0, 1.0);
    final isTrot = trotScoreRel >= minTrotScore &&
        rel.confidence >= minDiagQuality;

    final cyclesPerMin = periodSec > 0 ? 60.0 / periodSec : 0.0;
    final diagBeatsPerMin = periodSec > 0 ? 120.0 / periodSec : 0.0;
    final stability = (rel.stability * 100.0).clamp(0.0, 100.0);

    if (debug) {
      print(
        '[trot] score=${trotScoreRel.toStringAsFixed(3)} '
        'conf=${rel.confidence.toStringAsFixed(3)} '
        'T=${periodSec.toStringAsFixed(3)}s '
        'diag=${diagDeg1.toStringAsFixed(0)}/${diagDeg2.toStringAsFixed(0)} '
        'lat=${latFrontDeg.toStringAsFixed(0)}/${latHindDeg.toStringAsFixed(0)} '
        'isTrot=$isTrot',
      );
    }

    final impactPerLeg = <_TrotLeg, double>{};
    final swingPerLeg = <_TrotLeg, double>{};
    final impactAmps = <double>[];
    final swingAmps = <double>[];
    for (final leg in _TrotLeg.values) {
      final samples = w[leg]!;
      final impact = _impactAmplitude(samples);
      final swing = _swingAmplitude(samples);
      impactPerLeg[leg] = impact;
      swingPerLeg[leg] = swing;
      impactAmps.add(impact);
      swingAmps.add(swing);
    }
    final impactCv = _cv(impactAmps);
    final swingCv = _cv(swingAmps);

    return TrotLiveMetrics(
      periodSec: periodSec,
      freqCyclesPerMin: cyclesPerMin,
      diagBeatsPerMin: diagBeatsPerMin,
      trotScore: trotScore,
      isTrot: isTrot,
      bestMode: 'accZ+pitch',
      legDevMs: {
        'VL': devMs[_TrotLeg.VL] ?? 0.0,
        'VR': devMs[_TrotLeg.VR] ?? 0.0,
        'HL': devMs[_TrotLeg.HL] ?? 0.0,
        'HR': devMs[_TrotLeg.HR] ?? 0.0,
      },
      worstLeg: _legKey(worst),
      diagPhaseDeg: diagDeg1,
      diagPhaseDeg2: diagDeg2,
      lateralFrontDeg: latFrontDeg,
      lateralHindDeg: latHindDeg,
      stabilityPct: stability,
      confidencePct: confidencePct,
      impactCv: impactCv,
      swingCv: swingCv,
      impactPerLeg: {
        'VL': impactPerLeg[_TrotLeg.VL] ?? 0.0,
        'VR': impactPerLeg[_TrotLeg.VR] ?? 0.0,
        'HL': impactPerLeg[_TrotLeg.HL] ?? 0.0,
        'HR': impactPerLeg[_TrotLeg.HR] ?? 0.0,
      },
      swingPerLeg: {
        'VL': swingPerLeg[_TrotLeg.VL] ?? 0.0,
        'VR': swingPerLeg[_TrotLeg.VR] ?? 0.0,
        'HL': swingPerLeg[_TrotLeg.HL] ?? 0.0,
        'HR': swingPerLeg[_TrotLeg.HR] ?? 0.0,
      },
    );
  }

  _RelationalResult? _computeRelational(Map<_TrotLeg, List<_TrotSample>> w) {
    final dtSec = _medianDtSecFromMs(w[_TrotLeg.VR]!);
    if (dtSec <= 0) return null;

    final primary = _relationalForSignal(w, _SignalType.accZ);
    if (primary == null) return null;
    final secondary = _relationalForSignal(w, _SignalType.pitch);

    final useSecondary = secondary != null && secondary.trotScore > 0.05;
    final trotScore = useSecondary
        ? sqrt(primary.trotScore * secondary!.trotScore)
        : primary.trotScore;
    final confidence = useSecondary
        ? (primary.confidence + secondary!.confidence) / 2.0
        : primary.confidence;
    final stability = useSecondary
        ? (primary.stability + secondary!.stability) / 2.0
        : primary.stability;

    final periodSamples = max(2, primary.periodSamples);
    final periodSec = periodSamples * dtSec;

    return _RelationalResult(
      trotScore: _clamp01(trotScore),
      confidence: _clamp01(confidence),
      periodSamples: periodSamples,
      periodSec: periodSec,
      stability: stability,
      vlHr: primary.vlHr,
      vrHl: primary.vrHl,
      vlVr: primary.vlVr,
      hlHr: primary.hlHr,
      vlHl: primary.vlHl,
    );
  }

  _RelSignal? _relationalForSignal(
    Map<_TrotLeg, List<_TrotSample>> w,
    _SignalType signal,
  ) {
    final zVL = _signalSeries(w[_TrotLeg.VL]!, signal);
    final zVR = _signalSeries(w[_TrotLeg.VR]!, signal);
    final zHL = _signalSeries(w[_TrotLeg.HL]!, signal);
    final zHR = _signalSeries(w[_TrotLeg.HR]!, signal);

    final n = [zVL.length, zVR.length, zHL.length, zHR.length].reduce(min);
    if (n < 40) return null;

    final sVL = zVL.sublist(zVL.length - n);
    final sVR = zVR.sublist(zVR.length - n);
    final sHL = zHL.sublist(zHL.length - n);
    final sHR = zHR.sublist(zHR.length - n);

    final energies = <_TrotLeg, double>{
      _TrotLeg.VL: _energy(sVL),
      _TrotLeg.VR: _energy(sVR),
      _TrotLeg.HL: _energy(sHL),
      _TrotLeg.HR: _energy(sHR),
    };
    final refLeg = energies.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
    final ref = _byLeg(refLeg, sVL, sVR, sHL, sHR);

    final maxLag = max(8, ref.length ~/ 2);
    final auto = _estimatePeriodByAutocorr(ref, maxLag);
    final T = max(2, auto.periodLag);

    final vrHl = _bestLag(sVR, sHL, T);
    final vlHr = _bestLag(sVL, sHR, T);
    final vlVr = _bestLag(sVL, sVR, T);
    final hlHr = _bestLag(sHL, sHR, T);
    final vlHl = _bestLag(sVL, sHL, T);

    final phiVRHL = _phaseFromLag(vrHl.lag, T);
    final phiVLHR = _phaseFromLag(vlHr.lag, T);
    final phiVLVR = _phaseFromLag(vlVr.lag, T);
    final phiHLHR = _phaseFromLag(hlHr.lag, T);

    final eDiag = (_distTo0(phiVRHL) + _distTo0(phiVLHR)) / 2.0;
    final eLat = (_distToPi(phiVLVR) + _distToPi(phiHLHR)) / 2.0;

    final stability = _phaseStability(
      zVL: sVL,
      zVR: sVR,
      zHL: sHL,
      zHR: sHR,
      period: T,
      segments: 4,
    );

    final sepMean =
        ((vrHl.best - vrHl.second) +
                (vlHr.best - vlHr.second) +
                (vlVr.best - vlVr.second) +
                (hlHr.best - hlHr.second)) /
            4.0;

    const wDiag = 1.0;
    const wLat = 1.0;
    final base = exp(-(wDiag * eDiag + wLat * eLat));
    final trotScore = _clamp01(base * stability);

    final conf = _clamp01(
      0.45 * stability +
          0.35 * _clamp01(sepMean) +
          0.20 * _clamp01(auto.separation),
    );

    return _RelSignal(
      trotScore: trotScore,
      confidence: conf,
      periodSamples: T,
      stability: stability,
      vlHr: vlHr,
      vrHl: vrHl,
      vlVr: vlVr,
      hlHr: hlHr,
      vlHl: vlHl,
    );
  }

  List<double> _signalSeries(List<_TrotSample> samples, _SignalType signal) {
    final out = List<double>.filled(samples.length, 0.0);
    for (int i = 0; i < samples.length; i++) {
      final s = samples[i];
      out[i] = switch (signal) {
        _SignalType.accZ => s.accZ,
        _SignalType.pitch => s.pitch,
      };
    }
    final diff = _diff(out);
    return _zscore(diff);
  }

  List<double> _byLeg(
    _TrotLeg leg,
    List<double> vl,
    List<double> vr,
    List<double> hl,
    List<double> hr,
  ) {
    switch (leg) {
      case _TrotLeg.VL:
        return vl;
      case _TrotLeg.VR:
        return vr;
      case _TrotLeg.HL:
        return hl;
      case _TrotLeg.HR:
        return hr;
    }
  }

  _AutoPeak _estimatePeriodByAutocorr(List<double> x, int maxLag) {
    if (x.length < 10) return const _AutoPeak(2, 0.0, 0.0);

    final r0 = _energy(x);
    if (r0 < 1e-9) return const _AutoPeak(2, 0.0, 0.0);

    final r = List<double>.filled(maxLag + 1, 0.0);
    r[0] = 1.0;

    for (int lag = 1; lag <= maxLag; lag++) {
      double s = 0.0;
      final n = x.length - lag;
      for (int t = 0; t < n; t++) {
        s += x[t] * x[t + lag];
      }
      r[lag] = s / r0;
    }

    int? minIdx;
    for (int k = 2; k < maxLag; k++) {
      if (r[k - 1] > r[k] && r[k] <= r[k + 1]) {
        minIdx = k;
        break;
      }
    }

    int start = (minIdx ?? 1) + 1;
    int? firstMax;
    for (int k = max(2, start); k < maxLag; k++) {
      if (r[k - 1] < r[k] && r[k] >= r[k + 1]) {
        firstMax = k;
        break;
      }
    }

    int bestLag = firstMax ?? 2;
    double best = r[bestLag];

    double second = -1e9;
    for (int k = 2; k <= maxLag; k++) {
      final v = r[k];
      if (k == bestLag) continue;
      if (v > second) second = v;
      if (firstMax == null && v > best) {
        second = best;
        best = v;
        bestLag = k;
      }
    }
    final sep = _clamp01(best - second);

    return _AutoPeak(bestLag, best, sep);
  }

  _LagPeak _bestLag(List<double> x, List<double> y, int maxLagAbs) {
    final maxLag = min(maxLagAbs, min(x.length - 2, y.length - 2));
    if (maxLag < 1) return const _LagPeak(0, 0.0, 0.0);

    final ex = _energy(x);
    final ey = _energy(y);
    final denom = sqrt(ex * ey);
    if (denom < 1e-9) return const _LagPeak(0, 0.0, 0.0);

    int bestLag = 0;
    double bestVal = -1e9;
    double secondVal = -1e9;

    for (int lag = -maxLag; lag <= maxLag; lag++) {
      double s = 0.0;

      final startX = max(0, -lag);
      final startY = max(0, lag);
      final n = min(x.length - startX, y.length - startY);

      for (int t = 0; t < n; t++) {
        s += x[startX + t] * y[startY + t];
      }

      final corr = s / denom;
      final score = corr.abs();

      if (score > bestVal) {
        secondVal = bestVal;
        bestVal = score;
        bestLag = lag;
      } else if (score > secondVal) {
        secondVal = score;
      }
    }

    return _LagPeak(bestLag, bestVal, secondVal);
  }

  double _phaseFromLag(int lag, int periodSamples) {
    return 2.0 * pi * (lag / periodSamples);
  }

  double _phaseFracFromLag(int lag, int periodSamples) {
    return _mod1(lag / periodSamples);
  }

  double _wrapRad(double a) {
    final twoPi = 2.0 * pi;
    a = (a + pi) % twoPi;
    if (a < 0) a += twoPi;
    return a - pi;
  }

  double _distTo0(double phi) => _wrapRad(phi).abs();

  double _distToPi(double phi) => _wrapRad(phi - pi).abs();

  double _phaseStability({
    required List<double> zVL,
    required List<double> zVR,
    required List<double> zHL,
    required List<double> zHR,
    required int period,
    required int segments,
  }) {
    final k = max(2, segments);
    final n = zVL.length;
    if (n < 20 || period < 2) return 0.0;

    final segLen = max(10, (n / (k + 0.5)).floor());
    final step = max(5, (segLen * 0.8).floor());

    final diagResidAngles = <double>[];
    final latResidAngles = <double>[];

    for (int start = 0; start + segLen <= n; start += step) {
      final end = start + segLen;

      final vl = zVL.sublist(start, end);
      final vr = zVR.sublist(start, end);
      final hl = zHL.sublist(start, end);
      final hr = zHR.sublist(start, end);

      final vrhl = _bestLag(vr, hl, period);
      final vlhr = _bestLag(vl, hr, period);
      final vlvr = _bestLag(vl, vr, period);
      final hlhr = _bestLag(hl, hr, period);

      final phiVRHL = _phaseFromLag(vrhl.lag, period);
      final phiVLHR = _phaseFromLag(vlhr.lag, period);
      final phiVLVR = _phaseFromLag(vlvr.lag, period);
      final phiHLHR = _phaseFromLag(hlhr.lag, period);

      diagResidAngles.add(_wrapRad(phiVRHL));
      diagResidAngles.add(_wrapRad(phiVLHR));
      latResidAngles.add(_wrapRad(phiVLVR - pi));
      latResidAngles.add(_wrapRad(phiHLHR - pi));
    }

    final rDiag = _circularResultantLength(diagResidAngles);
    final rLat = _circularResultantLength(latResidAngles);

    return _clamp01((rDiag + rLat) / 2.0);
  }

  double _circularResultantLength(List<double> angles) {
    if (angles.isEmpty) return 0.0;
    double sumSin = 0.0;
    double sumCos = 0.0;
    for (final a in angles) {
      sumSin += sin(a);
      sumCos += cos(a);
    }
    final n = angles.length.toDouble();
    final r = sqrt((sumSin / n) * (sumSin / n) + (sumCos / n) * (sumCos / n));
    return _clamp01(r);
  }

  double _energy(List<double> x) {
    double e = 0.0;
    for (final v in x) {
      e += v * v;
    }
    return e;
  }

  double _mod1(double x) {
    var y = x % 1.0;
    if (y < 0) y += 1.0;
    return y;
  }

  double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

  _Cand? _scoreWindowTrot(Map<_TrotLeg, List<_TrotSample>> w, String mode) {
    final dtSec = _medianDtSecFromMs(w[_TrotLeg.VR]!);
    if (dtSec <= 0) return null;

    final sVL = _buildSignal(w[_TrotLeg.VL]!, mode);
    final sVR = _buildSignal(w[_TrotLeg.VR]!, mode);
    final sHL = _buildSignal(w[_TrotLeg.HL]!, mode);
    final sHR = _buildSignal(w[_TrotLeg.HR]!, mode);

    final n = [sVL.length, sVR.length, sHL.length, sHR.length].reduce(min);
    if (n < 250) return null;

    final aVL = sVL.sublist(sVL.length - n);
    final aVR = sVR.sublist(sVR.length - n);
    final aHL = sHL.sublist(sHL.length - n);
    final aHR = sHR.sublist(sHR.length - n);

    final periodSec = _estimatePeriodSec(
      aVR,
      dtSec,
      minT: 0.4,
      maxT: 1.2,
    );
    if (periodSec == null || periodSec <= 0) return null;

    final maxLag = max(1, min(n - 2, ((periodSec / 2) / dtSec).round()));

    final rVLHR =
        _phaseAndQ(aVL, aHR, maxLag, dtSec, periodSec, absCorr: false);
    final rVRHL =
        _phaseAndQ(aVR, aHL, maxLag, dtSec, periodSec, absCorr: false);
    final rVLVR =
        _phaseAndQ(aVL, aVR, maxLag, dtSec, periodSec, absCorr: true);
    final rHLHR =
        _phaseAndQ(aHL, aHR, maxLag, dtSec, periodSec, absCorr: true);
    final rVLHL =
        _phaseAndQ(aVL, aHL, maxLag, dtSec, periodSec, absCorr: true);
    final rHRVR =
        _phaseAndQ(aHR, aVR, maxLag, dtSec, periodSec, absCorr: true);

    final pVLHR = rVLHR.phase;
    final qVLHR = rVLHR.quality;
    final pVRHL = rVRHL.phase;
    final qVRHL = rVRHL.quality;
    final pVLVR = rVLVR.phase;
    final qVLVR = rVLVR.quality;
    final pHLHR = rHLHR.phase;
    final qHLHR = rHLHR.quality;
    final pVLHL = rVLHL.phase;
    final qVLHL = rVLHL.quality;
    final pHRVR = rHRVR.phase;
    final qHRVR = rHRVR.quality;

    final items = <_Item>[
      _Item(pVLHR, 0.0, qVLHR),
      _Item(pVRHL, 0.0, qVRHL),
      _Item(pVLVR, 0.5, qVLVR),
      _Item(pHLHR, 0.5, qHLHR),
      _Item(pVLHL, 0.5, qVLHL),
      _Item(pHRVR, 0.5, qHRVR),
    ];

    final score = _weightedPhaseError(items);
    final qDiagMin = min(qVLHR, qVRHL);
    final qValues = <double>[qVLHR, qVRHL, qVLVR, qHLHR, qVLHL, qHRVR];
    final qFinite = qValues.where((v) => v.isFinite).toList();
    final avgQuality = qFinite.isEmpty
        ? 0.0
        : qFinite.reduce((a, b) => a + b) / qFinite.length;

    return _Cand(
      score: score,
      periodSec: periodSec,
      bestMode: mode,
      pVLHR: pVLHR,
      pVRHL: pVRHL,
      pVLVR: pVLVR,
      pHLHR: pHLHR,
      qDiagMin: qDiagMin,
      avgQuality: avgQuality,
    );
  }

  double _phaseBetween(
    Map<_TrotLeg, List<_TrotSample>> w,
    String mode,
    _TrotLeg a,
    _TrotLeg b,
    double periodSec,
  ) {
    final dtSec = _medianDtSecFromMs(w[_TrotLeg.VR]!);
    if (dtSec <= 0) return 0.0;
    final sa = _buildSignal(w[a]!, mode);
    final sb = _buildSignal(w[b]!, mode);
    final n = min(sa.length, sb.length);
    final aa = sa.sublist(sa.length - n);
    final bb = sb.sublist(sb.length - n);
    final maxLag = max(1, min(n - 2, ((periodSec / 2) / dtSec).round()));
    final result =
        _phaseAndQ(aa, bb, maxLag, dtSec, periodSec, absCorr: true);
    return result.phase;
  }
}

enum _TrotLeg { VL, VR, HL, HR }

class _TrotSample {
  final int tMs;
  final double accZ;
  final double gyroZ;
  final double roll;
  final double pitch;

  _TrotSample({
    required this.tMs,
    required this.accZ,
    required this.gyroZ,
    required this.roll,
    required this.pitch,
  });
}

class _Cand {
  final double score;
  final double periodSec;
  final String bestMode;
  final double pVLHR;
  final double pVRHL;
  final double pVLVR;
  final double pHLHR;
  final double qDiagMin;
  final double avgQuality;

  _Cand({
    required this.score,
    required this.periodSec,
    required this.bestMode,
    required this.pVLHR,
    required this.pVRHL,
    required this.pVLVR,
    required this.pHLHR,
    required this.qDiagMin,
    required this.avgQuality,
  });
}

class _Item {
  final double phase;
  final double target;
  final double weight;
  _Item(this.phase, this.target, this.weight);
}

class _PhaseQ {
  final double phase;
  final double quality;
  const _PhaseQ(this.phase, this.quality);
}

class _LagResult {
  final int lag;
  final double quality;
  const _LagResult(this.lag, this.quality);
}

enum _SignalType { accZ, pitch }

class _LagPeak {
  final int lag;
  final double best;
  final double second;
  const _LagPeak(this.lag, this.best, this.second);
}

class _AutoPeak {
  final int periodLag;
  final double peakValue;
  final double separation;
  const _AutoPeak(this.periodLag, this.peakValue, this.separation);
}

class _RelSignal {
  final double trotScore;
  final double confidence;
  final int periodSamples;
  final double stability;
  final _LagPeak vlHr;
  final _LagPeak vrHl;
  final _LagPeak vlVr;
  final _LagPeak hlHr;
  final _LagPeak vlHl;

  const _RelSignal({
    required this.trotScore,
    required this.confidence,
    required this.periodSamples,
    required this.stability,
    required this.vlHr,
    required this.vrHl,
    required this.vlVr,
    required this.hlHr,
    required this.vlHl,
  });
}

class _RelationalResult {
  final double trotScore;
  final double confidence;
  final int periodSamples;
  final double periodSec;
  final double stability;
  final _LagPeak vlHr;
  final _LagPeak vrHl;
  final _LagPeak vlVr;
  final _LagPeak hlHr;
  final _LagPeak vlHl;

  const _RelationalResult({
    required this.trotScore,
    required this.confidence,
    required this.periodSamples,
    required this.periodSec,
    required this.stability,
    required this.vlHr,
    required this.vrHl,
    required this.vlVr,
    required this.hlHr,
    required this.vlHl,
  });
}

double _weightedPhaseError(List<_Item> items) {
  double wSum = 0.0;
  double eSum = 0.0;
  for (final it in items) {
    final w = max(0.0, it.weight);
    wSum += w;
    eSum += w * _wrap01(it.phase - it.target);
  }
  return (wSum <= 1e-9) ? 1.0 : (eSum / wSum);
}

_PhaseQ _phaseAndQ(
  List<double> a,
  List<double> b,
  int maxLag,
  double dtSec,
  double periodSec, {
  required bool absCorr,
}) {
  final lag = absCorr
      ? _bestAbsCorrLag(a, b, maxLag)
      : _bestCorrLag(a, b, maxLag);
  final tau = lag.lag * dtSec;
  final p = (tau / periodSec) % 1.0;
  return _PhaseQ(p < 0 ? p + 1.0 : p, lag.quality);
}

_LagResult _bestCorrLag(List<double> a, List<double> b, int maxLag) {
  final n = min(a.length, b.length);
  final aa = a.sublist(a.length - n);
  final bb = b.sublist(b.length - n);

  int bestLag = 0;
  double best = -1e18;

  for (int lag = -maxLag; lag <= maxLag; lag++) {
    final i0 = max(0, -lag);
    final i1 = min(n, n - lag);
    final len = i1 - i0;
    if (len < 40) continue;

    double s = 0.0;
    for (int i = i0; i < i1; i++) {
      s += aa[i] * bb[i + lag];
    }
    final corr = (s / len);
    if (corr > best) {
      best = corr;
      bestLag = lag;
    }
  }
  return _LagResult(bestLag, best.abs());
}

_LagResult _bestAbsCorrLag(List<double> a, List<double> b, int maxLag) {
  final n = min(a.length, b.length);
  final aa = a.sublist(a.length - n);
  final bb = b.sublist(b.length - n);

  int bestLag = 0;
  double best = -1.0;

  for (int lag = -maxLag; lag <= maxLag; lag++) {
    final i0 = max(0, -lag);
    final i1 = min(n, n - lag);
    final len = i1 - i0;
    if (len < 40) continue;

    double s = 0.0;
    for (int i = i0; i < i1; i++) {
      s += aa[i] * bb[i + lag];
    }
    final corr = (s / len).abs();
    if (corr > best) {
      best = corr;
      bestLag = lag;
    }
  }
  return _LagResult(bestLag, best);
}

double _medianDtSecFromMs(List<_TrotSample> s) {
  if (s.length < 3) return 0.0;
  final diffs = <int>[];
  for (int i = 1; i < s.length; i++) {
    final d = s[i].tMs - s[i - 1].tMs;
    if (d > 0) diffs.add(d);
  }
  if (diffs.isEmpty) return 0.0;
  diffs.sort();
  final medMs = diffs[diffs.length ~/ 2];
  return medMs / 1000.0;
}

double? _estimatePeriodSec(
  List<double> x,
  double dtSec, {
  required double minT,
  required double maxT,
}) {
  final n = x.length;
  if (n < 200) return null;

  final minLag = max(1, (minT / dtSec).round());
  final maxLag = min(n - 2, (maxT / dtSec).round());
  if (maxLag <= minLag) return null;

  double best = -1e18;
  int bestLag = minLag;

  for (int lag = minLag; lag <= maxLag; lag++) {
    double s = 0.0;
    final m = n - lag;
    for (int i = 0; i < m; i++) {
      s += x[i] * x[i + lag];
    }
    s /= max(1, m);
    if (s > best) {
      best = s;
      bestLag = lag;
    }
  }
  return bestLag * dtSec;
}

List<double> _buildSignal(List<_TrotSample> s, String mode) {
  final acc = _zscore(s.map((e) => e.accZ).toList());
  final gyro = _zscore(s.map((e) => e.gyroZ).toList());
  final droll = _zscore(_diff(s.map((e) => e.roll).toList()));
  final dpitch = _zscore(_diff(s.map((e) => e.pitch).toList()));

  switch (mode) {
    case "accZ":
      return acc;
    case "gyroZ":
      return gyro;
    case "droll":
      return droll;
    case "dpitch":
      return dpitch;
    case "combo":
      final n = [acc.length, gyro.length, droll.length, dpitch.length].reduce(min);
      final out = List<double>.filled(n, 0.0);
      for (int i = 0; i < n; i++) {
        out[i] = 0.20 * acc[i] + 0.50 * gyro[i] + 0.15 * droll[i] + 0.15 * dpitch[i];
      }
      return out;
    default:
      return gyro;
  }
}

List<double> _diff(List<double> x) {
  if (x.length < 2) return [];
  final out = List<double>.filled(x.length - 1, 0.0);
  for (int i = 1; i < x.length; i++) {
    out[i - 1] = x[i] - x[i - 1];
  }
  return out;
}

double _impactAmplitude(List<_TrotSample> samples) {
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

double _swingAmplitude(List<_TrotSample> samples) {
  final pitch = samples.map((s) => s.pitch).toList();
  final dPitch = _diff(pitch);
  if (dPitch.isEmpty) return 0.0;
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

List<double> _smooth3(List<double> x) {
  if (x.length < 3) return x;
  final y = List<double>.from(x);
  for (int i = 1; i < x.length - 1; i++) {
    y[i] = (x[i - 1] + x[i] + x[i + 1]) / 3.0;
  }
  return y;
}

List<double> _zscore(List<double> x) {
  if (x.isEmpty) return [];
  double mean = 0.0;
  for (final v in x) mean += v;
  mean /= x.length;

  double variance = 0.0;
  for (final v in x) {
    final d = v - mean;
    variance += d * d;
  }
  variance /= max(1, x.length);

  final std = sqrt(variance);
  final denom = std < 1e-9 ? 1.0 : std;
  return x.map((v) => (v - mean) / denom).toList();
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

double _median(List<double> values) {
  if (values.isEmpty) return 0.0;
  final list = List<double>.from(values)..sort();
  final mid = list.length ~/ 2;
  if (list.length.isOdd) return list[mid];
  return (list[mid - 1] + list[mid]) / 2.0;
}

double _wrap01(double d) {
  final x = d.abs();
  return min(x, 1.0 - x);
}

double _signedWrap(double d) {
  var x = d % 1.0;
  if (x > 0.5) x -= 1.0;
  if (x < -0.5) x += 1.0;
  return x;
}

double _wrapDeg(double p01) {
  final p = min(p01, 1.0 - p01);
  return p * 360.0;
}

String _legKey(_TrotLeg leg) {
  switch (leg) {
    case _TrotLeg.VL:
      return "VL";
    case _TrotLeg.VR:
      return "VR";
    case _TrotLeg.HL:
      return "HL";
    case _TrotLeg.HR:
      return "HR";
  }
}
