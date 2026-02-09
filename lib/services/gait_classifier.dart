import 'dart:math';
import 'takt_models.dart';

class GaitClassifier {
  static const _legsLeft = {"VL", "HL"};
  static const _legsRight = {"VR", "HR"};
  static const _legsFront = {"VL", "VR"};

  Gait classify(Map<String, List<double>> events, double? periodHintMs) {
    final points = _collect(events);
    if (points.length < 4) return Gait.stehen;

    final period = periodHintMs ?? _medianPeriod(points);
    if (period == null || period <= 0) return Gait.stehen;

    final phasePoints = _toPhases(points, period);
    if (phasePoints.isEmpty) return Gait.stehen;

    final results = <int, _ClusterResult>{};
    final bics = <int, double>{};

    for (final k in [2, 3, 4]) {
      final r = _kMeansCircular(phasePoints, k);
      results[k] = r;
      bics[k] = _bicFromSse(sse: r.score, n: phasePoints.length, k: k);
    }

    // Bestes k über BIC (kleiner ist besser)
    final bestK = bics.entries.reduce((a, b) => a.value <= b.value ? a : b).key;

    if (bestK == 3 && _looksLikeGalopp(phasePoints, results[3]!)) {
      return Gait.galopp;
    }

    if (bestK == 2 && _diagonalBeatsStronger(phasePoints)) {
      return Gait.trab;
    }

    if (bestK == 4 && _looksLikeSchritt(phasePoints, results[4]!)) {
      return Gait.schritt;
    }

    return Gait.stehen;
  }

  // ------------------------------
  // Helpers: Collect / Period / Phases
  // ------------------------------

  List<_PhasePoint> _collect(Map<String, List<double>> events) {
    final list = <_PhasePoint>[];
    events.forEach((leg, ts) {
      for (final t in ts) {
        list.add(_PhasePoint(leg: leg, t: t));
      }
    });
    return list;
  }

  double? _medianPeriod(List<_PhasePoint> points) {
    final byLeg = <String, List<double>>{};
    for (final p in points) {
      byLeg.putIfAbsent(p.leg, () => []).add(p.t);
    }

    final dts = <double>[];
    for (final ts in byLeg.values) {
      if (ts.length < 2) continue;
      ts.sort();
      for (int i = 1; i < ts.length; i++) {
        final dt = ts[i] - ts[i - 1];
        if (dt > 0) dts.add(dt);
      }
    }
    if (dts.isEmpty) return null;
    dts.sort();
    return dts[dts.length ~/ 2];
  }

  List<_PhasePoint> _toPhases(List<_PhasePoint> points, double period) {
    final minT = points.map((p) => p.t).reduce(min);
    return points
        .map((p) => _PhasePoint(
              leg: p.leg,
              t: p.t,
              phase: ((p.t - minT) % period) / period,
            ))
        .toList();
  }

  // ------------------------------
  // Trab: Diagonalen stärker als lateral (robuster als "min über alle")
  // ------------------------------

  bool _diagonalBeatsStronger(List<_PhasePoint> phases) {
    final diag =
        _meanNearestPhaseDist("VL", "HR", phases) + _meanNearestPhaseDist("VR", "HL", phases);
    final lateral =
        _meanNearestPhaseDist("VL", "VR", phases) + _meanNearestPhaseDist("HL", "HR", phases);

    // Rein relative Entscheidung (keine festen Grenzwerte)
    return diag < lateral;
  }

  double _meanNearestPhaseDist(String a, String b, List<_PhasePoint> phases) {
    final pa = phases.where((p) => p.leg == a).map((p) => p.phase).toList();
    final pb = phases.where((p) => p.leg == b).map((p) => p.phase).toList();
    if (pa.isEmpty || pb.isEmpty) return double.infinity;

    double sum = 0;
    for (final xa in pa) {
      double best = double.infinity;
      for (final xb in pb) {
        best = min(best, _circularDist(xa, xb));
      }
      sum += best;
    }
    return sum / pa.length;
  }

  // ------------------------------
  // Galopp: Plausibilität über Modellvergleiche (BIC), ohne fixe Schwellen
  // ------------------------------

  bool _looksLikeGalopp(List<_PhasePoint> phases, _ClusterResult k3) {
    // (A) Asymmetrie links/rechts: gemeinsames Modell vs. getrennte Modelle
    // Joint: k=3 auf allen Phasen
    final joint = k3;
    final jointBic = _bicFromSse(sse: joint.score, n: phases.length, k: 3);

    // Split: k=3 auf links und k=3 auf rechts
    final left = phases.where((p) => _legsLeft.contains(p.leg)).toList();
    final right = phases.where((p) => _legsRight.contains(p.leg)).toList();
    if (left.length < 3 || right.length < 3) return false;

    final leftR = _kMeansCircular(left, 3);
    final rightR = _kMeansCircular(right, 3);
    final splitBic = _bicFromSse(sse: leftR.score, n: left.length, k: 3) +
        _bicFromSse(sse: rightR.score, n: right.length, k: 3);

    final asymmetryOk = splitBic < jointBic;

    // (B) Rollenverteilung Vorder/Hinter abhängig vom Cluster?
    // Teste: "Front/Hind unabhängig von Cluster" vs. "Front/Hind cluster-spezifisch"
    final frontHindOk = _bicCategoricalDependence(
      assignments: k3.assignments,
      phases: phases,
      groupOfLeg: (leg) => _legsFront.contains(leg) ? 1 : 0, // 1=front, 0=hind
      k: 3,
    );

    // (C) Links/Rechts abhängig vom Cluster? (galopp-typisch, wegen Lead)
    final leftRightOk = _bicCategoricalDependence(
      assignments: k3.assignments,
      phases: phases,
      groupOfLeg: (leg) => _legsLeft.contains(leg) ? 1 : 0, // 1=left, 0=right
      k: 3,
    );

    return asymmetryOk && frontHindOk && leftRightOk;
  }

  bool _looksLikeSchritt(List<_PhasePoint> phases, _ClusterResult k4) {
    // (A) Diagonale Kopplung schwach -> sonst Trab-Tendenz
    if (_diagonalBeatsStronger(phases)) return false;

    // (B) Galopp-typische starke Links/Rechts-Asymmetrie vermeiden
    final left = phases.where((p) => _legsLeft.contains(p.leg)).toList();
    final right = phases.where((p) => _legsRight.contains(p.leg)).toList();
    if (left.length >= 4 && right.length >= 4) {
      final jointBic = _bicFromSse(sse: k4.score, n: phases.length, k: 4);
      final splitBic = _bicFromSse(sse: _kMeansCircular(left, 4).score, n: left.length, k: 4) +
          _bicFromSse(sse: _kMeansCircular(right, 4).score, n: right.length, k: 4);
      final veryAsymmetric = splitBic < jointBic;
      if (veryAsymmetric) return false;
    }

    // (C) Schritt-typisch: Cluster hängen stark von konkretem Bein ab (4-beat)
    final legDependenceOk =
        _bicLegDependence(assignments: k4.assignments, phases: phases, k: 4);

    return legDependenceOk;
  }

  /// BIC-Vergleich für binäre Gruppenvariable (z.B. front/hind oder left/right):
  /// true, wenn "cluster-spezifische Gruppenwahrscheinlichkeit" (abhängig) besser ist als unabhängig.
  bool _bicCategoricalDependence({
    required List<int> assignments,
    required List<_PhasePoint> phases,
    required int k,
    required int Function(String leg) groupOfLeg, // 0/1
  }) {
    // counts per cluster: [n0, n1]
    final counts = List.generate(k, (_) => [0, 0]);
    int total0 = 0, total1 = 0;

    for (int i = 0; i < phases.length; i++) {
      final c = assignments[i];
      if (c < 0 || c >= k) continue;
      final g = groupOfLeg(phases[i].leg); // 0/1
      counts[c][g] += 1;
      if (g == 0) {
        total0++;
      } else {
        total1++;
      }
    }

    final n = total0 + total1;
    if (n == 0) return false;

    // Log-Likelihood unabhängig: ein globales p (params=1)
    double llInd = 0;
    llInd += _safeCountLogProb(total0, total0 / n);
    llInd += _safeCountLogProb(total1, total1 / n);
    final bicInd = -2 * llInd + 1 * log(n);

    // Log-Likelihood abhängig: p je Cluster (params = k*1)
    double llDep = 0;
    int usedClusters = 0;
    for (int c = 0; c < k; c++) {
      final n0 = counts[c][0];
      final n1 = counts[c][1];
      final nc = n0 + n1;
      if (nc == 0) continue;
      usedClusters++;
      llDep += _safeCountLogProb(n0, n0 / nc);
      llDep += _safeCountLogProb(n1, n1 / nc);
    }
    final params = max(1, usedClusters); // effektiv genutzte Cluster
    final bicDep = -2 * llDep + params * log(n);

    return bicDep < bicInd;
  }

  double _safeCountLogProb(int count, double p) {
    if (count == 0) return 0;
    final pp = max(p, 1e-12);
    return count * log(pp);
  }

  bool _bicLegDependence({
    required List<int> assignments,
    required List<_PhasePoint> phases,
    required int k,
  }) {
    int legCat(String leg) {
      switch (leg) {
        case 'VL':
          return 0;
        case 'VR':
          return 1;
        case 'HL':
          return 2;
        case 'HR':
          return 3;
        default:
          return 0;
      }
    }

    final counts = List.generate(k, (_) => List.filled(4, 0));
    final global = List.filled(4, 0);
    int n = 0;

    for (int i = 0; i < phases.length; i++) {
      final c = assignments[i];
      if (c < 0 || c >= k) continue;
      final cat = legCat(phases[i].leg);
      counts[c][cat] += 1;
      global[cat] += 1;
      n++;
    }
    if (n == 0) return false;

    double llInd = 0;
    for (int cat = 0; cat < 4; cat++) {
      llInd += _safeCountLogProb(global[cat], global[cat] / n);
    }
    final bicInd = -2 * llInd + 3 * log(n); // 4 Kategorien -> 3 Parameter

    double llDep = 0;
    int usedClusters = 0;
    for (int c = 0; c < k; c++) {
      final nc = counts[c].reduce((a, b) => a + b);
      if (nc == 0) continue;
      usedClusters++;
      for (int cat = 0; cat < 4; cat++) {
        llDep += _safeCountLogProb(counts[c][cat], counts[c][cat] / nc);
      }
    }
    final params = max(3, usedClusters * 3); // je Cluster 3 freie Parameter (4 Kategorien)
    final bicDep = -2 * llDep + params * log(n);

    return bicDep < bicInd;
  }

  // ------------------------------
  // Circular KMeans + BIC
  // ------------------------------

  _ClusterResult _kMeansCircular(List<_PhasePoint> points, int k) {
    if (points.isEmpty) {
      return _ClusterResult(k: k, centers: const [], assignments: const [], score: double.infinity);
    }

    List<double> centers = List.generate(k, (i) => (i + 0.5) / k);
    List<int> assign = List.filled(points.length, 0);

    for (int iter = 0; iter < 10; iter++) {
      // assign
      for (int i = 0; i < points.length; i++) {
        final p = points[i].phase;
        double bestDist = _circularDist(p, centers[0]);
        int best = 0;
        for (int c = 1; c < k; c++) {
          final d = _circularDist(p, centers[c]);
          if (d < bestDist) {
            bestDist = d;
            best = c;
          }
        }
        assign[i] = best;
      }

      // recompute centers
      for (int c = 0; c < k; c++) {
        final vals = <double>[];
        for (int i = 0; i < points.length; i++) {
          if (assign[i] == c) vals.add(points[i].phase);
        }
        if (vals.isEmpty) continue;
        centers[c] = _circularMean(vals);
      }
    }

    double sse = 0;
    for (int i = 0; i < points.length; i++) {
      final d = _circularDist(points[i].phase, centers[assign[i]]);
      sse += d * d;
    }

    return _ClusterResult(k: k, centers: centers, assignments: assign, score: sse);
  }

  double _bicFromSse({required double sse, required int n, required int k}) {
    // BIC für SSE-basiertes Modell (k als Komplexitätsmaß; n als Stichprobengröße)
    // Verhindert, dass "größeres k gewinnt, weil SSE immer kleiner wird".
    const eps = 1e-12;
    final s = max(sse, eps);
    final nn = max(n, 1);
    return nn * log(s / nn) + k * log(nn);
  }

  double _circularDist(double a, double b) {
    final diff = (a - b).abs();
    return min(diff, 1.0 - diff);
  }

  double _circularMean(List<double> values) {
    if (values.isEmpty) return 0;
    double sumSin = 0;
    double sumCos = 0;
    for (final v in values) {
      sumSin += sin(2 * pi * v);
      sumCos += cos(2 * pi * v);
    }
    final angle = atan2(sumSin, sumCos);
    final mean = angle / (2 * pi);
    return (mean + 1) % 1;
  }
}

class _PhasePoint {
  final String leg;
  final double t; // ms
  final double phase;
  _PhasePoint({required this.leg, required this.t, this.phase = 0});
}

class _ClusterResult {
  final int k;
  final List<double> centers;
  final List<int> assignments;
  final double score; // SSE
  _ClusterResult({
    required this.k,
    required this.centers,
    required this.assignments,
    required this.score,
  });
}
