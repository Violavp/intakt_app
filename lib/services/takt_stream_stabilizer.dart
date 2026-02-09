import 'dart:async';
import 'dart:math';

import 'takt_models.dart';

enum TaktContext {
  normal,
  still,
  lowQuality,
  transition,
  curve,
}

class TaktStabilizedState {
  final TaktUiState raw;

  /// WHOOP-artige "Wahrheit": langsam, robust, kann in Kontexten einfrieren.
  final double? stableTemporalScorePct;
  final double? stableSpatialScorePct;
  final double? stableTaktScorePct;
  final double? stableConfidencePct;

  final TaktContext context;
  final bool frozen;

  const TaktStabilizedState({
    required this.raw,
    required this.stableTemporalScorePct,
    required this.stableSpatialScorePct,
    required this.stableTaktScorePct,
    required this.stableConfidencePct,
    required this.context,
    required this.frozen,
  });

  factory TaktStabilizedState.empty() => TaktStabilizedState(
        raw: TaktUiState.empty(),
        stableTemporalScorePct: null,
        stableSpatialScorePct: null,
        stableTaktScorePct: null,
        stableConfidencePct: null,
        context: TaktContext.normal,
        frozen: true,
      );

  String get contextLabel {
    switch (context) {
      case TaktContext.normal:
        return "Normal";
      case TaktContext.still:
        return "Stillstand";
      case TaktContext.lowQuality:
        return "Signalqualität";
      case TaktContext.transition:
        return "Übergang";
      case TaktContext.curve:
        return "Kurve/Volte";
    }
  }
}

class TaktStreamStabilizer {
  final Stream<TaktUiState> _input;
  late final StreamController<TaktStabilizedState> _controller;
  StreamSubscription<TaktUiState>? _sub;

  // Tuning: bewusst konservativ, damit plötzliche Ereignisse den "Stable"-Score
  // nicht sofort runterziehen. Diese Werte können wir später datengetrieben anpassen.
  final double tauSec;
  final int transitionHoldMs;
  final int curveMinMs;
  final int curveHoldMs;
  final double lowQualityFreezeBelowPct;
  final double curveMinConfidencePct;
  final double curvePhaseErrDeg;
  final double stepFreqJumpSpm;
  final double confidenceDropPct;

  TaktStreamStabilizer({
    required Stream<TaktUiState> input,
    this.tauSec = 25.0,
    this.transitionHoldMs = 3000,
    this.curveMinMs = 2000,
    this.curveHoldMs = 2500,
    this.lowQualityFreezeBelowPct = 50.0,
    this.curveMinConfidencePct = 60.0,
    this.curvePhaseErrDeg = 35.0,
    this.stepFreqJumpSpm = 20.0,
    this.confidenceDropPct = 25.0,
  }) : _input = input {
    _controller = StreamController<TaktStabilizedState>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
  }

  Stream<TaktStabilizedState> get stream => _controller.stream;

  void dispose() {
    _stop();
    _controller.close();
  }

  // Internal state
  TaktUiState? _lastRaw;
  double? _stableTemporal;
  double? _stableSpatial;
  double? _stableTakt;
  double? _stableConf;

  double? _curveStartMs;
  double _transitionUntilMs = double.negativeInfinity;
  double _curveUntilMs = double.negativeInfinity;

  void _start() {
    _sub ??= _input.listen(_onRaw, onError: _controller.addError, onDone: () {
      _sub = null;
      if (!_controller.isClosed) _controller.close();
    });
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
  }

  void _onRaw(TaktUiState raw) {
    final prev = _lastRaw;
    _lastRaw = raw;

    final nowMs = raw.timestampMs;
    final prevMs = prev?.timestampMs ?? nowMs;
    final dtMsRaw = nowMs - prevMs;
    final dtMs = dtMsRaw.isFinite ? dtMsRaw.clamp(0.0, 1500.0) : 0.0;
    final dtSec = dtMs / 1000.0;

    final isStill = raw.gait == Gait.stehen;
    final confNow = raw.confidencePct;
    final confPrev = prev?.confidencePct;
    final lowQuality = (confNow == null || !confNow.isFinite)
        ? true
        : confNow < lowQualityFreezeBelowPct;

    final gaitChanged = (prev != null) &&
        (raw.gait != prev.gait) &&
        (raw.gait != Gait.stehen) &&
        (prev.gait != Gait.stehen);

    final stepNow = raw.stepFrequencySpm;
    final stepPrev = prev?.stepFrequencySpm;
    final stepJump = (stepNow != null &&
        stepPrev != null &&
        stepNow.isFinite &&
        stepPrev.isFinite &&
        (stepNow - stepPrev).abs() >= stepFreqJumpSpm &&
        dtMs <= 800.0);

    final confDrop = (confNow != null &&
        confPrev != null &&
        confNow.isFinite &&
        confPrev.isFinite &&
        (confPrev - confNow) >= confidenceDropPct &&
        dtMs <= 800.0);

    final transitionTriggered = gaitChanged || stepJump || confDrop;
    if (transitionTriggered) {
      _transitionUntilMs = max(_transitionUntilMs, nowMs + transitionHoldMs);
    }
    final transitionActive = nowMs < _transitionUntilMs;

    // "Kurve/Volte"-Heuristik: Wir nutzen nur Werte, die bereits in deinem State sind,
    // ohne harte Abhängigkeit von Sensororientierung.
    final lat = raw.lateralPhaseDeg;
    final curveCandidate = (lat != null &&
        lat.isFinite &&
        confNow != null &&
        confNow.isFinite &&
        confNow >= curveMinConfidencePct &&
        (180.0 - lat).abs() >= curvePhaseErrDeg);

    if (curveCandidate) {
      _curveStartMs ??= nowMs;
      final active = (nowMs - _curveStartMs!) >= curveMinMs;
      if (active) {
        _curveUntilMs = max(_curveUntilMs, nowMs + curveHoldMs);
      }
    } else {
      _curveStartMs = null;
    }
    final curveActive = nowMs < _curveUntilMs;

    final context = isStill
        ? TaktContext.still
        : lowQuality
            ? TaktContext.lowQuality
            : transitionActive
                ? TaktContext.transition
                : curveActive
                    ? TaktContext.curve
                    : TaktContext.normal;

    final freeze =
        context != TaktContext.normal || dtSec <= 0 || dtSec.isNaN || dtSec.isInfinite;

    _stableTemporal =
        _updateEma(prev: _stableTemporal, x: raw.temporalScorePct, dtSec: dtSec, freeze: freeze);
    _stableSpatial =
        _updateEma(prev: _stableSpatial, x: raw.spatialScorePct, dtSec: dtSec, freeze: freeze);
    _stableTakt =
        _updateEma(prev: _stableTakt, x: raw.taktScorePct, dtSec: dtSec, freeze: freeze);

    // Confidence ist hilfreich als "Qualitäts-Truth"; die glätten wir, aber frieren
    // wir nicht so aggressiv ein wie Scores (damit man Dropouts sehen kann).
    final freezeConf = isStill || dtSec <= 0;
    _stableConf = _updateEma(
      prev: _stableConf,
      x: confNow,
      dtSec: dtSec,
      freeze: freezeConf,
      tauOverrideSec: max(8.0, tauSec * 0.6),
    );

    final out = TaktStabilizedState(
      raw: raw,
      stableTemporalScorePct: _stableTemporal,
      stableSpatialScorePct: _stableSpatial,
      stableTaktScorePct: _stableTakt,
      stableConfidencePct: _stableConf,
      context: context,
      frozen: freeze,
    );

    if (!_controller.isClosed) _controller.add(out);
  }

  double? _updateEma({
    required double? prev,
    required double? x,
    required double dtSec,
    required bool freeze,
    double? tauOverrideSec,
  }) {
    if (x == null || !x.isFinite) return prev;
    if (prev == null) return x.clamp(0.0, 100.0);
    if (freeze) return prev;

    final tau = max(0.5, tauOverrideSec ?? tauSec);
    final alpha = 1.0 - exp(-dtSec / tau);
    final next = prev + alpha * (x - prev);
    return next.clamp(0.0, 100.0);
  }
}
