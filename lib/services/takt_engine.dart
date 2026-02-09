import 'dart:async';
import 'dart:math';

import 'gallop_metrics_engine.dart';
import 'takt_models.dart';
import 'takt_score_utils.dart';
import 'trot_metrics_engine.dart';
import 'walk_metrics_engine.dart';
import 'walk_score_engine.dart';

class TaktEngine {
  final Duration emitInterval = const Duration(milliseconds: 200);
  static const _knownLegs = {"VL", "VR", "HL", "HR"};
  final WalkScoreEngine _walkScoreEngine = WalkScoreEngine();
  WalkScoreResult? _lastWalkScore;
  final WalkMetricsEngine _walkMetricsEngine = WalkMetricsEngine();
  WalkLiveMetrics? _lastWalkMetrics;
  final TrotMetricsEngine _trotMetricsEngine = TrotMetricsEngine();
  TrotLiveMetrics? _lastTrotMetrics;
  final GallopMetricsEngine _gallopMetricsEngine = GallopMetricsEngine();
  GallopLiveMetrics? _lastGallopMetrics;
  final _ScoreSmoother _walkSmoother = _ScoreSmoother();
  final _ScoreSmoother _trotSmoother = _ScoreSmoother();
  final _ScoreSmoother _gallopSmoother = _ScoreSmoother();

  final _controller = StreamController<TaktUiState>.broadcast();
  double _lastEmitMs = 0;

  Stream<TaktUiState> get stream => _controller.stream;

  void reset() {
    _lastEmitMs = 0;
    _walkScoreEngine.reset();
    _lastWalkScore = null;
    _walkMetricsEngine.reset();
    _lastWalkMetrics = null;
    _trotMetricsEngine.reset();
    _lastTrotMetrics = null;
    _gallopMetricsEngine.reset();
    _lastGallopMetrics = null;
    _walkSmoother.reset();
    _trotSmoother.reset();
    _gallopSmoother.reset();
  }

  void addSample({
    required String leg,
    required double timestampMs,
    required double accZ,
    required double gyroZ,
    required double roll,
    required double pitch,
    double? accX,
    double? accY,
    double? gyroX,
    double? gyroY,
  }) {
    if (!_knownLegs.contains(leg)) return;
    final ax = accX ?? 0.0;
    final ay = accY ?? 0.0;
    final gx = gyroX ?? 0.0;
    final gy = gyroY ?? 0.0;
    final accNorm = sqrt(ax * ax + ay * ay + accZ * accZ);
    final gyroNorm = sqrt(gx * gx + gy * gy + gyroZ * gyroZ);
    _walkScoreEngine.addSample(
      leg: leg,
      timestampMs: timestampMs,
      accZ: accNorm,
      gyroZ: gyroNorm,
      roll: roll,
      pitch: pitch,
    );
    _walkMetricsEngine.addSample(
      leg: leg,
      timestampMs: timestampMs,
      accZ: accNorm,
      gyroZ: gyroNorm,
      roll: roll,
      pitch: pitch,
    );
    _trotMetricsEngine.addSample(
      leg: leg,
      timestampMs: timestampMs,
      accZ: accNorm,
      gyroZ: gyroNorm,
      roll: roll,
      pitch: pitch,
    );
    _gallopMetricsEngine.addSample(
      leg: leg,
      timestampMs: timestampMs,
      accZ: accNorm,
      pitch: pitch,
    );
    if (_shouldEmit(timestampMs)) {
      final state = _compute(timestampMs);
      if (!_controller.isClosed) {
        _controller.add(state);
      }
      _lastEmitMs = timestampMs;
    }
  }

  bool _shouldEmit(double tsMs) {
    if (_lastEmitMs == 0) return true;
    return tsMs - _lastEmitMs >= emitInterval.inMilliseconds;
  }

  TaktUiState _compute(double nowMs) {
    final walkResult = _walkScoreEngine.poll();
    if (walkResult != null) {
      _lastWalkScore = walkResult;
    }
    final metrics = _walkMetricsEngine.poll();
    if (metrics != null) {
      _lastWalkMetrics = metrics;
    } else if (_walkMetricsEngine.isStill) {
      _lastWalkMetrics = null;
      _lastWalkScore = null;
      _lastTrotMetrics = null;
      _lastGallopMetrics = null;
      _walkSmoother.reset();
      _trotSmoother.reset();
      _gallopSmoother.reset();
    }

    if (!_walkMetricsEngine.isStill) {
      final trotMetrics = _trotMetricsEngine.poll();
      if (trotMetrics != null) {
        _lastTrotMetrics = trotMetrics;
      }
    }

    if (!_walkMetricsEngine.isStill) {
      final gallopMetrics = _gallopMetricsEngine.poll();
      if (gallopMetrics != null) {
        _lastGallopMetrics = gallopMetrics;
      }
    }

    final walkOk = _lastWalkScore?.isWalk == true && !_walkMetricsEngine.isStill;
    final trotOk =
        _lastTrotMetrics?.isTrot == true && !_walkMetricsEngine.isStill;
    final gallopOk =
        _lastGallopMetrics?.isGallop == true && !_walkMetricsEngine.isStill;
    final gConf = _lastGallopMetrics?.confidencePct ?? 0.0;
    final tConf = _lastTrotMetrics?.confidencePct ?? 0.0;
    final gait = (gallopOk && gConf >= 45 && gConf >= tConf)
        ? Gait.galopp
        : trotOk
            ? Gait.trab
            : walkOk
                ? Gait.schritt
                : Gait.stehen;

    final dev = gallopOk
        ? _lastGallopMetrics?.legDevMs
        : trotOk
            ? _lastTrotMetrics?.legDevMs
            : _lastWalkMetrics?.legDevMs;
    final diagPhaseDeg = gallopOk
        ? null
        : trotOk
            ? _avg(_lastTrotMetrics?.diagPhaseDeg,
                _lastTrotMetrics?.diagPhaseDeg2)
            : _lastWalkMetrics?.diagPhaseDeg;
    final lateralPhaseDeg = gallopOk
        ? null
        : trotOk
            ? _avg(_lastTrotMetrics?.lateralFrontDeg,
                _lastTrotMetrics?.lateralHindDeg)
            : _lastWalkMetrics?.latPhaseDeg;
    final straightnessScorePct =
        _lastWalkMetrics?.straightnessScorePct ?? 100.0;
    TaktScoreTriple? scoreTriple;
    Map<String, double>? legScores;
    _SmoothedScores? smoothedScores;
    double? confidencePct;
    if (gallopOk && _lastGallopMetrics != null) {
      scoreTriple = computeGallopScores(
        isGallop: _lastGallopMetrics!.isGallop,
        lead: _lastGallopMetrics!.lead,
        periodSec: _lastGallopMetrics!.periodSec,
        diagonalPairTightMs: _lastGallopMetrics!.diagonalPairTightMs,
        otherDiagonalMs: _lastGallopMetrics!.otherDiagonalMs,
        gallopScorePct: _lastGallopMetrics!.gallopScorePct,
        legDevMs: _lastGallopMetrics!.legDevMs,
        straightnessScorePct: straightnessScorePct,
        impactCv: _lastGallopMetrics!.impactCv,
        swingCv: _lastGallopMetrics!.swingCv,
      );
      legScores = computeLegScores(
        periodSec: _lastGallopMetrics!.periodSec,
        legDevMs: _lastGallopMetrics!.legDevMs,
        impactPerLeg: _lastGallopMetrics!.impactPerLeg,
        swingPerLeg: _lastGallopMetrics!.swingPerLeg,
      );
      smoothedScores = _gallopSmoother.update(
        temporalIn: scoreTriple.temporal,
        spatialIn: scoreTriple.spatial,
        taktIn: scoreTriple.takt,
        confidencePct: scoreTriple.confidence,
        nowMs: nowMs.round(),
      );
      confidencePct =
          _lastGallopMetrics!.confidencePct.isFinite
              ? _lastGallopMetrics!.confidencePct
              : scoreTriple.confidence;
    } else if (trotOk && _lastTrotMetrics != null) {
      scoreTriple = computeTrotScores(
        periodSec: _lastTrotMetrics!.periodSec,
        trotScore: _lastTrotMetrics!.trotScore,
        isTrot: _lastTrotMetrics!.isTrot,
        legDevMs: _lastTrotMetrics!.legDevMs,
        diagPhaseDeg: _lastTrotMetrics!.diagPhaseDeg,
        diagPhaseDeg2: _lastTrotMetrics!.diagPhaseDeg2,
        lateralFrontDeg: _lastTrotMetrics!.lateralFrontDeg,
        lateralHindDeg: _lastTrotMetrics!.lateralHindDeg,
        straightnessScorePct: straightnessScorePct,
        stabilityPct: _lastTrotMetrics!.stabilityPct,
        impactCv: _lastTrotMetrics!.impactCv,
        swingCv: _lastTrotMetrics!.swingCv,
      );
      legScores = computeLegScores(
        periodSec: _lastTrotMetrics!.periodSec,
        legDevMs: _lastTrotMetrics!.legDevMs,
        impactPerLeg: _lastTrotMetrics!.impactPerLeg,
        swingPerLeg: _lastTrotMetrics!.swingPerLeg,
      );
      smoothedScores = _trotSmoother.update(
        temporalIn: scoreTriple.temporal,
        spatialIn: scoreTriple.spatial,
        taktIn: scoreTriple.takt,
        confidencePct: scoreTriple.confidence,
        nowMs: nowMs.round(),
      );
      confidencePct =
          _lastTrotMetrics!.confidencePct.isFinite
              ? _lastTrotMetrics!.confidencePct
              : scoreTriple.confidence;
    } else if (walkOk && _lastWalkMetrics != null) {
      scoreTriple = computeWalkScores(
        periodSec: _lastWalkMetrics!.periodSec,
        periodStdMs: _lastWalkMetrics!.periodStdMs,
        intervalVarMs: _lastWalkMetrics!.intervalVarMs,
        walkScore: _lastWalkMetrics!.walkScore,
        legDevMs: _lastWalkMetrics!.legDevMs,
        straightnessScorePct: straightnessScorePct,
        impactCv: _lastWalkMetrics!.impactCv,
        swingCv: _lastWalkMetrics!.swingCv,
      );
      legScores = computeLegScores(
        periodSec: _lastWalkMetrics!.periodSec,
        legDevMs: _lastWalkMetrics!.legDevMs,
        impactPerLeg: _lastWalkMetrics!.impactPerLeg,
        swingPerLeg: _lastWalkMetrics!.swingPerLeg,
      );
      smoothedScores = _walkSmoother.update(
        temporalIn: scoreTriple.temporal,
        spatialIn: scoreTriple.spatial,
        taktIn: scoreTriple.takt,
        confidencePct: scoreTriple.confidence,
        nowMs: nowMs.round(),
      );
      confidencePct =
          _lastWalkScore?.confidencePct ?? scoreTriple.confidence;
    }

    final state = TaktUiState(
      legs: {
        "VL": LegMetrics(offsetMs: dev?["VL"], scorePct: legScores?["VL"]),
        "VR": LegMetrics(offsetMs: dev?["VR"], scorePct: legScores?["VR"]),
        "HL": LegMetrics(offsetMs: dev?["HL"], scorePct: legScores?["HL"]),
        "HR": LegMetrics(offsetMs: dev?["HR"], scorePct: legScores?["HR"]),
      },
      stepFrequencySpm: gallopOk
          ? _lastGallopMetrics?.hoofbeatsPerMin
          : trotOk
              ? _lastTrotMetrics?.diagBeatsPerMin
              : walkOk
                  ? _lastWalkMetrics?.freqHoofbeatsPerMin
                  : 0.0,
      diagPhaseDeg: diagPhaseDeg,
      lateralPhaseDeg: lateralPhaseDeg,
      intervalVarMs: gallopOk || trotOk ? null : _lastWalkMetrics?.intervalVarMs,
      stabilityPct: gallopOk
          ? _lastGallopMetrics?.gallopScorePct
          : trotOk
              ? _lastTrotMetrics?.stabilityPct
              : _lastWalkMetrics?.taktStabilityPct,
      temporalScorePct: smoothedScores?.temporal ?? scoreTriple?.temporal,
      spatialScorePct: smoothedScores?.spatial ?? scoreTriple?.spatial,
      taktScorePct: smoothedScores?.takt ?? scoreTriple?.takt,
      confidencePct: confidencePct,
      confidence: confidencePct != null,
      timestampMs: nowMs,
      gait: gait,
    );
    return state;
  }

  double? _avg(double? a, double? b) {
    if (a == null && b == null) return null;
    if (a == null) return b;
    if (b == null) return a;
    return (a + b) / 2.0;
  }
}

class _SmoothedScores {
  final double temporal;
  final double spatial;
  final double takt;
  final bool frozen;

  const _SmoothedScores({
    required this.temporal,
    required this.spatial,
    required this.takt,
    required this.frozen,
  });
}

class _ScoreSmoother {
  final double tauSec;
  final double freezeThreshold;
  double? _temporal;
  double? _spatial;
  double? _takt;
  int? _lastMs;

  _ScoreSmoother({
    this.tauSec = 10.0,
    this.freezeThreshold = 50.0,
  });

  void reset() {
    _temporal = null;
    _spatial = null;
    _takt = null;
    _lastMs = null;
  }

  _SmoothedScores update({
    required double temporalIn,
    required double spatialIn,
    required double taktIn,
    required double confidencePct,
    required int nowMs,
  }) {
    final frozen = confidencePct < freezeThreshold;
    if (frozen && _temporal != null && _spatial != null && _takt != null) {
      return _SmoothedScores(
        temporal: _temporal!,
        spatial: _spatial!,
        takt: _takt!,
        frozen: true,
      );
    }

    final dtSec = _lastMs == null ? 0.0 : (nowMs - _lastMs!) / 1000.0;
    final alpha = _alphaFromTau(dtSec <= 0 ? 0.0 : dtSec, tauSec);

    _temporal = _emaUpdate(_temporal, temporalIn, alpha);
    _spatial = _emaUpdate(_spatial, spatialIn, alpha);
    _takt = _emaUpdate(_takt, taktIn, alpha);
    _lastMs = nowMs;

    return _SmoothedScores(
      temporal: _temporal!,
      spatial: _spatial!,
      takt: _takt!,
      frozen: false,
    );
  }

  double _emaUpdate(double? prev, double x, double alpha) {
    if (prev == null) return x;
    return prev + alpha * (x - prev);
  }

  double _alphaFromTau(double dtSec, double tauSec) {
    if (dtSec <= 0) return 1.0;
    return 1.0 - exp(-dtSec / max(0.001, tauSec));
  }
}
