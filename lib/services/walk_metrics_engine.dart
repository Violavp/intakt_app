import 'dart:math';

enum TaktState { green, yellow, red, unknown }

class WalkLiveMetrics {
  final double periodSec;
  final double periodStdMs;
  final double rhythmScorePct;
  final double equalnessScorePct;
  final double straightnessErrDeg;
  final double straightnessScorePct;
  final double freqCyclesPerMin;
  final double freqHoofbeatsPerMin;
  final double walkScore;
  final double taktStabilityPct;
  final double taktInstantPct;
  final double taktStablePct;
  final double taktTrendPct;
  final double confidencePct;
  final bool isFrozen;
  final TaktState taktState;
  final Map<String, double> legDevMs;
  final String worstLeg;
  final double intervalVarMs;
  final double diagPhaseDeg;
  final double latPhaseDeg;
  final double impactCv;
  final double swingCv;
  final Map<String, double> impactPerLeg;
  final Map<String, double> swingPerLeg;

  WalkLiveMetrics({
    required this.periodSec,
    required this.periodStdMs,
    required this.rhythmScorePct,
    required this.equalnessScorePct,
    required this.straightnessErrDeg,
    required this.straightnessScorePct,
    required this.freqCyclesPerMin,
    required this.freqHoofbeatsPerMin,
    required this.walkScore,
    required this.taktStabilityPct,
    required this.taktInstantPct,
    required this.taktStablePct,
    required this.taktTrendPct,
    required this.confidencePct,
    required this.isFrozen,
    required this.taktState,
    required this.legDevMs,
    required this.worstLeg,
    required this.intervalVarMs,
    required this.diagPhaseDeg,
    required this.latPhaseDeg,
    required this.impactCv,
    required this.swingCv,
    required this.impactPerLeg,
    required this.swingPerLeg,
  });
}

class WalkMetricsEngine {
  final double stableWindowSec;
  final double momentWindowSec;
  final double emitStepSec;
  static const double _minAccStdG = 0.03;
  static const double _minGyroStdDps = 1.0;
  static const int _periodHistoryN = 8;

  final Map<_WalkLeg, List<_WalkSample>> _buf = {
    _WalkLeg.VL: <_WalkSample>[],
    _WalkLeg.VR: <_WalkSample>[],
    _WalkLeg.HL: <_WalkSample>[],
    _WalkLeg.HR: <_WalkSample>[],
  };

  int? _lastEmitMs;
  final List<double> _periodHistorySec = [];
  double _periodStdMs = 0.0;
  bool _isStill = false;
  double? _emaTakt;
  double? _emaRhythm;
  double? _emaEqualness;
  WalkLiveMetrics? _lastOut;
  TaktState _state = TaktState.unknown;
  TaktState? _pendingState;
  int? _pendingSinceMs;

  WalkMetricsEngine({
    this.stableWindowSec = 15.0,
    this.momentWindowSec = 2.5,
    this.emitStepSec = 2.0,
  });

  void reset() {
    for (final b in _buf.values) {
      b.clear();
    }
    _lastEmitMs = null;
    _periodHistorySec.clear();
    _periodStdMs = 0.0;
    _isStill = false;
    _emaTakt = null;
    _emaRhythm = null;
    _emaEqualness = null;
    _lastOut = null;
    _state = TaktState.unknown;
    _pendingState = null;
    _pendingSinceMs = null;
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

    final cutoffMs = tMs - (stableWindowSec * 1000).round() - 2000;
    while (b.isNotEmpty && b.first.tMs < cutoffMs) {
      b.removeAt(0);
    }
  }

  WalkLiveMetrics? poll() {
    final lastTs = <int>[];
    for (final leg in _WalkLeg.values) {
      final b = _buf[leg]!;
      if (b.isEmpty) return null;
      lastTs.add(b.last.tMs);
    }
    final nowMs = lastTs.reduce(min);

    if (_lastEmitMs != null) {
      final dt = (nowMs - _lastEmitMs!) / 1000.0;
      if (dt < emitStepSec) return null;
    }

    final stableWin = _collectWindow(
      nowMs: nowMs,
      windowSec: stableWindowSec,
      minSamplesPerLeg: 60,
    );
    if (stableWin == null) return null;

    final momentWin = _collectWindow(
          nowMs: nowMs,
          windowSec: momentWindowSec,
          minSamplesPerLeg: 60,
        ) ??
        stableWin;

    if (_isStillWindow(stableWin)) {
      _isStill = true;
      _periodHistorySec.clear();
      _periodStdMs = 0.0;
      _emaTakt = null;
      _emaRhythm = null;
      _emaEqualness = null;
      _lastOut = null;
      _state = TaktState.unknown;
      _pendingState = null;
      _pendingSinceMs = null;
      _lastEmitMs = nowMs;
      return null;
    }
    _isStill = false;

    final stableRaw = _computeRawMetrics(stableWin, updatePeriodHistory: true);
    final instantRaw =
        _computeRawMetrics(momentWin, updatePeriodHistory: false);

    final dtSec = _lastEmitMs == null
        ? emitStepSec
        : (nowMs - _lastEmitMs!) / 1000.0;
    final alpha = _alphaFromTau(dtSec, 10.0);
    _emaTakt = _emaUpdate(_emaTakt, stableRaw.taktStabilityPct, alpha);
    _emaRhythm = _emaUpdate(_emaRhythm, stableRaw.rhythmScorePct, alpha);
    _emaEqualness = _emaUpdate(_emaEqualness, stableRaw.equalnessScorePct, alpha);

    final taktStablePct =
        (_emaTakt ?? stableRaw.taktStabilityPct).clamp(0.0, 100.0);
    final taktInstantPct = instantRaw.taktStabilityPct.clamp(0.0, 100.0);
    final taktTrendPct = taktInstantPct - taktStablePct;

    final samplesPerLeg = _minSamplesPerLeg(stableWin);
    final confidencePct = _confidence(
      samplesPerLeg: samplesPerLeg,
      periodHistoryLen: _periodHistorySec.length,
      periodStdMs: _periodStdMs,
    );

    final shouldFreeze = confidencePct < 50.0;
    if (shouldFreeze && _lastOut != null) {
      final frozen = _lastOut!;
      final out = WalkLiveMetrics(
        periodSec: frozen.periodSec,
        periodStdMs: frozen.periodStdMs,
        rhythmScorePct: frozen.rhythmScorePct,
        equalnessScorePct: frozen.equalnessScorePct,
        straightnessErrDeg: frozen.straightnessErrDeg,
        straightnessScorePct: frozen.straightnessScorePct,
        freqCyclesPerMin: frozen.freqCyclesPerMin,
        freqHoofbeatsPerMin: frozen.freqHoofbeatsPerMin,
        walkScore: frozen.walkScore,
        taktStabilityPct: frozen.taktStablePct,
        taktInstantPct: taktInstantPct,
        taktStablePct: frozen.taktStablePct,
        taktTrendPct: taktInstantPct - frozen.taktStablePct,
        confidencePct: confidencePct,
        isFrozen: true,
        taktState: frozen.taktState,
        legDevMs: frozen.legDevMs,
        worstLeg: frozen.worstLeg,
      intervalVarMs: frozen.intervalVarMs,
      diagPhaseDeg: frozen.diagPhaseDeg,
      latPhaseDeg: frozen.latPhaseDeg,
      impactCv: frozen.impactCv,
      swingCv: frozen.swingCv,
      impactPerLeg: frozen.impactPerLeg,
      swingPerLeg: frozen.swingPerLeg,
    );
      _lastOut = out;
      _lastEmitMs = nowMs;
      return out;
    }

    final targetState = _targetState(taktStablePct);
    _state = _applyHysteresis(_state, targetState, nowMs);

    final out = WalkLiveMetrics(
      periodSec: stableRaw.periodSec,
      periodStdMs: stableRaw.periodStdMs,
      rhythmScorePct: _emaRhythm?.clamp(0.0, 100.0) ?? stableRaw.rhythmScorePct,
      equalnessScorePct:
          _emaEqualness?.clamp(0.0, 100.0) ?? stableRaw.equalnessScorePct,
      straightnessErrDeg: stableRaw.straightnessErrDeg,
      straightnessScorePct: stableRaw.straightnessScorePct,
      freqCyclesPerMin: stableRaw.freqCyclesPerMin,
      freqHoofbeatsPerMin: stableRaw.freqHoofbeatsPerMin,
      walkScore: stableRaw.walkScore,
      taktStabilityPct: taktStablePct,
      taktInstantPct: taktInstantPct,
      taktStablePct: taktStablePct,
      taktTrendPct: taktTrendPct,
      confidencePct: confidencePct,
      isFrozen: false,
      taktState: _state,
      legDevMs: stableRaw.legDevMs,
      worstLeg: stableRaw.worstLeg,
      intervalVarMs: stableRaw.intervalVarMs,
      diagPhaseDeg: stableRaw.diagPhaseDeg,
      latPhaseDeg: stableRaw.latPhaseDeg,
      impactCv: stableRaw.impactCv,
      swingCv: stableRaw.swingCv,
      impactPerLeg: stableRaw.impactPerLeg,
      swingPerLeg: stableRaw.swingPerLeg,
    );

    _lastOut = out;
    _lastEmitMs = nowMs;
    return out;
  }

  bool get isStill => _isStill;

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

  Map<_WalkLeg, List<_WalkSample>>? _collectWindow({
    required int nowMs,
    required double windowSec,
    required int minSamplesPerLeg,
  }) {
    final startMs = nowMs - (windowSec * 1000).round();
    final win = <_WalkLeg, List<_WalkSample>>{};
    for (final leg in _WalkLeg.values) {
      final w = _buf[leg]!
          .where((s) => s.tMs >= startMs && s.tMs <= nowMs)
          .toList()
        ..sort((a, b) => a.tMs.compareTo(b.tMs));
      if (w.length < minSamplesPerLeg) return null;
      win[leg] = w;
    }
    return win;
  }

  int _minSamplesPerLeg(Map<_WalkLeg, List<_WalkSample>> win) {
    return win.values.map((v) => v.length).reduce(min);
  }

  double _emaUpdate(double? prev, double x, double alpha) {
    if (prev == null) return x;
    return prev + alpha * (x - prev);
  }

  double _alphaFromTau(double dtSec, double tauSec) {
    return 1.0 - exp(-dtSec / max(0.001, tauSec));
  }

  double _confidence({
    required int samplesPerLeg,
    required int periodHistoryLen,
    required double periodStdMs,
  }) {
    double c = 1.0;
    if (samplesPerLeg < 120) c *= 0.5;
    if (periodHistoryLen < 5) c *= 0.4;
    if (periodStdMs == 0.0 && periodHistoryLen < 5) c *= 0.3;
    return (c * 100.0).clamp(0.0, 100.0);
  }

  TaktState _targetState(double score) {
    if (score.isNaN) return TaktState.unknown;
    if (score >= 80) return TaktState.green;
    if (score >= 65) return TaktState.yellow;
    return TaktState.red;
  }

  TaktState _applyHysteresis(TaktState current, TaktState target, int nowMs) {
    if (current == TaktState.unknown) {
      _pendingState = null;
      _pendingSinceMs = null;
      return target;
    }
    if (target == current) {
      _pendingState = null;
      _pendingSinceMs = null;
      return current;
    }

    if (_pendingState != target) {
      _pendingState = target;
      _pendingSinceMs = nowMs;
      return current;
    }

    final since = _pendingSinceMs ?? nowMs;
    final dt = nowMs - since;
    final worsening = _stateLevel(target) > _stateLevel(current);
    final needMs = worsening ? 3000 : 6000;
    if (dt >= needMs) {
      _pendingState = null;
      _pendingSinceMs = null;
      return target;
    }
    return current;
  }

  int _stateLevel(TaktState state) {
    switch (state) {
      case TaktState.green:
        return 0;
      case TaktState.yellow:
        return 1;
      case TaktState.red:
        return 2;
      case TaktState.unknown:
        return 3;
    }
  }

  _RawMetrics _computeRawMetrics(
    Map<_WalkLeg, List<_WalkSample>> w, {
    required bool updatePeriodHistory,
  }) {
    final signals = <_WalkLeg, List<double>>{};
    final times = <_WalkLeg, List<int>>{};

    for (final leg in _WalkLeg.values) {
      final s = w[leg]!;
      times[leg] = s.map((e) => e.tMs).toList();

      final acc = _zscore(s.map((e) => e.accZ).toList());
      final gyro = _zscore(s.map((e) => e.gyroZ).toList());
      final dRoll = _zscore(_diff(s.map((e) => e.roll).toList()));
      final dPitch = _zscore(_diff(s.map((e) => e.pitch).toList()));

      final n = [acc.length, gyro.length, dRoll.length, dPitch.length].reduce(min);
      final out = List<double>.filled(n, 0.0);
      for (int i = 0; i < n; i++) {
        out[i] = 0.20 * acc[i] + 0.50 * gyro[i] + 0.15 * dRoll[i] + 0.15 * dPitch[i];
      }
      signals[leg] = out;
    }

    final dtSec = max(0.01, _medianDiffSec(times[_WalkLeg.VR]!));
    final periodSec = _estimatePeriodSec(
          signals[_WalkLeg.VR]!,
          dtSec,
          minPeriodSec: 0.7,
          maxPeriodSec: 2.0,
        ) ??
        1.2;

    if (updatePeriodHistory) {
      _pushPeriod(periodSec);
    }

    final phi = <_WalkLeg, double>{_WalkLeg.HL: 0.0};
    for (final leg in [_WalkLeg.VL, _WalkLeg.VR, _WalkLeg.HR]) {
      final tau = _bestLagSecAbsCorr(
        signals[_WalkLeg.HL]!,
        signals[leg]!,
        dtSec,
        maxLagSec: periodSec / 2,
      );
      phi[leg] = _mod1(tau / periodSec);
    }

    const exp = <_WalkLeg, double>{
      _WalkLeg.HL: 0.00,
      _WalkLeg.VL: 0.25,
      _WalkLeg.HR: 0.50,
      _WalkLeg.VR: 0.75,
    };

    final phaseErrors = <double>[];
    for (final leg in _WalkLeg.values) {
      phaseErrors.add(_mod1(phi[leg]! - exp[leg]!));
    }
    final globalOffset = _circularMeanPhase(phaseErrors);

    final devMs = <_WalkLeg, double>{};
    for (final leg in _WalkLeg.values) {
      final d = _signedWrap(phi[leg]! - exp[leg]! - globalOffset) * periodSec * 1000.0;
      devMs[leg] = d;
    }

    _WalkLeg worstLeg = _WalkLeg.VR;
    double worstAbs = -1;
    for (final leg in _WalkLeg.values) {
      final a = devMs[leg]!.abs();
      if (a > worstAbs) {
        worstAbs = a;
        worstLeg = leg;
      }
    }

    final phaseErr = _WalkLeg.values
            .map((leg) => _wrap01(phi[leg]! - exp[leg]! - globalOffset))
            .reduce((a, b) => a + b) /
        4.0;

    final ph = [
      phi[_WalkLeg.HL]!,
      phi[_WalkLeg.VL]!,
      phi[_WalkLeg.HR]!,
      phi[_WalkLeg.VR]!,
    ]..sort();
    final deltas = <double>[
      ph[1] - ph[0],
      ph[2] - ph[1],
      ph[3] - ph[2],
      (ph[0] + 1.0) - ph[3],
    ];
    final meanDelta = deltas.reduce((a, b) => a + b) / deltas.length;
    double variance = 0.0;
    for (final d in deltas) {
      final dd = d - meanDelta;
      variance += dd * dd;
    }
    variance /= deltas.length;
    final intervalStdMs = sqrt(variance) * periodSec * 1000.0;

    final impactPerLeg = <_WalkLeg, double>{};
    final swingPerLeg = <_WalkLeg, double>{};
    final impactAmps = <double>[];
    final swingAmps = <double>[];
    for (final leg in _WalkLeg.values) {
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

    final pVLHR = _phaseBetween(
      signals[_WalkLeg.VL]!,
      signals[_WalkLeg.HR]!,
      dtSec,
      periodSec,
    );
    final pVLVR = _phaseBetween(
      signals[_WalkLeg.VL]!,
      signals[_WalkLeg.VR]!,
      dtSec,
      periodSec,
    );
    final pHLHR = _phaseBetween(
      signals[_WalkLeg.HL]!,
      signals[_WalkLeg.HR]!,
      dtSec,
      periodSec,
    );

    final diagPhaseDeg = _wrap01(pVLHR) * 360.0;
    final latPhaseDeg = _wrap01(pVLVR) * 360.0;

    const rhythmStdMaxMs = 120.0;
    const intervalStdMaxMs = 60.0;
    final rhythmScorePct = _scorePctFromStd(_periodStdMs, rhythmStdMaxMs);
    final equalnessScorePct = _scorePctFromStd(intervalStdMs, intervalStdMaxMs);

    final frontErrDeg = _wrap01(pVLVR - 0.50) * 360.0;
    final hindErrDeg = _wrap01(pHLHR - 0.50) * 360.0;
    final straightnessErrDeg = (frontErrDeg + hindErrDeg) / 2.0;
    final straightnessScorePct =
        (1.0 - (straightnessErrDeg / 60.0)).clamp(0.0, 1.0) * 100.0;

    final taktStabilityPct =
        (0.70 * rhythmScorePct + 0.30 * equalnessScorePct).clamp(0.0, 100.0);

    final cyclesPerMin = 60.0 / periodSec;
    final hoofbeatsPerMin = 240.0 / periodSec;

    return _RawMetrics(
      periodSec: periodSec,
      periodStdMs: _periodStdMs,
      rhythmScorePct: rhythmScorePct,
      equalnessScorePct: equalnessScorePct,
      straightnessErrDeg: straightnessErrDeg,
      straightnessScorePct: straightnessScorePct,
      freqCyclesPerMin: cyclesPerMin,
      freqHoofbeatsPerMin: hoofbeatsPerMin,
      walkScore: phaseErr,
      taktStabilityPct: taktStabilityPct,
      legDevMs: {
        "VL": devMs[_WalkLeg.VL] ?? 0.0,
        "VR": devMs[_WalkLeg.VR] ?? 0.0,
        "HL": devMs[_WalkLeg.HL] ?? 0.0,
        "HR": devMs[_WalkLeg.HR] ?? 0.0,
      },
      worstLeg: _legKey(worstLeg),
      intervalVarMs: intervalStdMs,
      diagPhaseDeg: diagPhaseDeg,
      latPhaseDeg: latPhaseDeg,
      impactCv: impactCv,
      swingCv: swingCv,
      impactPerLeg: {
        "VL": impactPerLeg[_WalkLeg.VL] ?? 0.0,
        "VR": impactPerLeg[_WalkLeg.VR] ?? 0.0,
        "HL": impactPerLeg[_WalkLeg.HL] ?? 0.0,
        "HR": impactPerLeg[_WalkLeg.HR] ?? 0.0,
      },
      swingPerLeg: {
        "VL": swingPerLeg[_WalkLeg.VL] ?? 0.0,
        "VR": swingPerLeg[_WalkLeg.VR] ?? 0.0,
        "HL": swingPerLeg[_WalkLeg.HL] ?? 0.0,
        "HR": swingPerLeg[_WalkLeg.HR] ?? 0.0,
      },
    );
  }

  void _pushPeriod(double periodSec) {
    _periodHistorySec.add(periodSec);
    if (_periodHistorySec.length > _periodHistoryN) {
      _periodHistorySec.removeAt(0);
    }
    if (_periodHistorySec.length < 3) {
      _periodStdMs = 0.0;
      return;
    }
    final mean =
        _periodHistorySec.reduce((a, b) => a + b) / _periodHistorySec.length;
    double variance = 0.0;
    for (final p in _periodHistorySec) {
      final d = p - mean;
      variance += d * d;
    }
    variance /= _periodHistorySec.length;
    _periodStdMs = sqrt(variance) * 1000.0;
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

class _RawMetrics {
  final double periodSec;
  final double periodStdMs;
  final double rhythmScorePct;
  final double equalnessScorePct;
  final double straightnessErrDeg;
  final double straightnessScorePct;
  final double freqCyclesPerMin;
  final double freqHoofbeatsPerMin;
  final double walkScore;
  final double taktStabilityPct;
  final Map<String, double> legDevMs;
  final String worstLeg;
  final double intervalVarMs;
  final double diagPhaseDeg;
  final double latPhaseDeg;
  final double impactCv;
  final double swingCv;
  final Map<String, double> impactPerLeg;
  final Map<String, double> swingPerLeg;

  _RawMetrics({
    required this.periodSec,
    required this.periodStdMs,
    required this.rhythmScorePct,
    required this.equalnessScorePct,
    required this.straightnessErrDeg,
    required this.straightnessScorePct,
    required this.freqCyclesPerMin,
    required this.freqHoofbeatsPerMin,
    required this.walkScore,
    required this.taktStabilityPct,
    required this.legDevMs,
    required this.worstLeg,
    required this.intervalVarMs,
    required this.diagPhaseDeg,
    required this.latPhaseDeg,
    required this.impactCv,
    required this.swingCv,
    required this.impactPerLeg,
    required this.swingPerLeg,
  });
}

String _legKey(_WalkLeg leg) {
  switch (leg) {
    case _WalkLeg.VL:
      return "VL";
    case _WalkLeg.VR:
      return "VR";
    case _WalkLeg.HL:
      return "HL";
    case _WalkLeg.HR:
      return "HR";
  }
}

double _phaseBetween(List<double> a, List<double> b, double dtSec, double periodSec) {
  final tau = _bestLagSecAbsCorr(a, b, dtSec, maxLagSec: periodSec / 2);
  return _mod1(tau / periodSec);
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

double _mod1(double x) {
  var y = x % 1.0;
  if (y < 0) y += 1.0;
  return y;
}

double _circularMeanPhase(List<double> phases) {
  if (phases.isEmpty) return 0.0;
  double sumSin = 0.0;
  double sumCos = 0.0;
  for (final p in phases) {
    final ang = 2 * pi * p;
    sumSin += sin(ang);
    sumCos += cos(ang);
  }
  final angle = atan2(sumSin, sumCos);
  return _mod1(angle / (2 * pi));
}

List<double> _diff(List<double> x) {
  if (x.isEmpty) return [];
  final out = List<double>.filled(x.length, 0.0);
  for (int i = 1; i < x.length; i++) {
    out[i] = x[i] - x[i - 1];
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
  if (tMs.length < 3) return 0.01;
  final diffs = <double>[];
  for (int i = 1; i < tMs.length; i++) {
    final dMs = (tMs[i] - tMs[i - 1]).toDouble();
    if (dMs > 0) diffs.add(dMs / 1000.0);
  }
  if (diffs.isEmpty) return 0.01;
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
  if (n < 80) return null;

  final minLag = max(1, (minPeriodSec / dtSec).round());
  final maxLag = min(n - 2, (maxPeriodSec / dtSec).round());
  if (maxLag <= minLag) return null;

  double best = -1e9;
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

double _bestLagSecAbsCorr(
  List<double> a,
  List<double> b,
  double dtSec, {
  required double maxLagSec,
}) {
  final n = min(a.length, b.length);
  if (n < 60) return 0.0;

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
    if (cnt < 20) continue;

    final corr = (s / cnt).abs();
    if (corr > best) {
      best = corr;
      bestLag = lag;
    }
  }
  return bestLag * dtSec;
}

double _scorePctFromStd(double stdMs, double maxMs) {
  if (maxMs <= 0) return 0.0;
  final s = (1.0 - (stdMs / maxMs)).clamp(0.0, 1.0);
  return s * 100.0;
}

double _impactAmplitude(List<_WalkSample> samples) {
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

double _swingAmplitude(List<_WalkSample> samples) {
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

bool _isStillWindow(Map<_WalkLeg, List<_WalkSample>> w) {
  final accStds = <double>[];
  final gyroStds = <double>[];
  for (final leg in _WalkLeg.values) {
    final samples = w[leg]!;
    accStds.add(_std(samples.map((s) => s.accZ).toList()));
    gyroStds.add(_std(samples.map((s) => s.gyroZ).toList()));
  }
  final accMed = _median(accStds);
  final gyroMed = _median(gyroStds);
  return accMed < WalkMetricsEngine._minAccStdG &&
      gyroMed < WalkMetricsEngine._minGyroStdDps;
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
