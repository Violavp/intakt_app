import 'package:flutter/material.dart';
import '../widgets/metric_box.dart';
import '../services/takt_models.dart';
import '../services/takt_stream_stabilizer.dart';
import '../widgets/green_gradient_background.dart';

class TaktDetailPage extends StatelessWidget {
  final Stream<TaktStabilizedState>? stateStream;
  const TaktDetailPage({super.key, this.stateStream});

  @override
  Widget build(BuildContext context) {
    final stream = stateStream;
    Widget content = _buildContent(context, TaktStabilizedState.empty());
    if (stream != null) {
      content = StreamBuilder<TaktStabilizedState>(
        stream: stream,
        initialData: TaktStabilizedState.empty(),
        builder: (context, snapshot) {
          return _buildContent(
              context, snapshot.data ?? TaktStabilizedState.empty());
        },
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          "Takt-Analyse",
          style: TextStyle(
            fontFamily: "Inter",
            fontSize: 22,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: GreenGradientBackground(
        child: SafeArea(
          top: false,
          child: content,
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, TaktStabilizedState s) {
    final state = s.raw;
    final topInset =
        MediaQuery.of(context).padding.top + kToolbarHeight + 12;
    final temporal = s.stableTemporalScorePct ?? state.temporalScorePct;
    final spatial = s.stableSpatialScorePct ?? state.spatialScorePct;
    final takt = s.stableTaktScorePct ?? state.taktScorePct;
    final conf = s.stableConfidencePct ?? state.confidencePct;

    return Padding(
      padding: EdgeInsets.only(top: topInset, left: 16, right: 16, bottom: 16),
      child: Column(
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _tab("Stehen", state.gait == Gait.stehen),
            const SizedBox(width: 10),
            _tab("Schritt", state.gait == Gait.schritt),
            const SizedBox(width: 10),
            _tab("Trab", state.gait == Gait.trab),
            const SizedBox(width: 10),
            _tab("Galopp", state.gait == Gait.galopp),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          "Kontext: ${s.contextLabel}${s.frozen ? " (freeze)" : ""}",
          style: TextStyle(
            fontFamily: "Inter",
            fontSize: 12,
            color: Colors.white.withOpacity(0.55),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          "Varianz der Abstände",
          style: TextStyle(
            fontFamily: "Inter",
            fontSize: 16,
            color: Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _formatVarMs(state.intervalVarMs),
          style: const TextStyle(
            fontFamily: "Inter",
            fontSize: 14,
            color: Colors.white38,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0.2, 0.1),
                      radius: 1.1,
                      colors: [
                        Color(0x2216A085),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                child: Container(
                  width: 220,
                  height: 1,
                  color: Colors.white.withOpacity(0.12),
                ),
              ),
              Positioned(
                child: Container(
                  height: 220,
                  width: 1,
                  color: Colors.white.withOpacity(0.12),
                ),
              ),
              _glowCircle(
                label: "VL",
                value: _formatLegScore(state.legs["VL"]?.scorePct),
                color: _severityColorFromScore(
                  const Color(0xFF3AE68F),
                  state.legs["VL"]?.scorePct,
                ),
                subtitle: "Vorne Links",
                alignment: const Alignment(-0.78, -0.65),
              ),
              _glowCircle(
                label: "VR",
                value: _formatLegScore(state.legs["VR"]?.scorePct),
                color: _severityColorFromScore(
                  const Color(0xFF6EE6F5),
                  state.legs["VR"]?.scorePct,
                ),
                subtitle: "Vorne Rechts",
                alignment: const Alignment(0.78, -0.65),
              ),
              _glowCircle(
                label: "HL",
                value: _formatLegScore(state.legs["HL"]?.scorePct),
                color: _severityColorFromScore(
                  const Color(0xFFE6D35F),
                  state.legs["HL"]?.scorePct,
                ),
                subtitle: "Hinten Links",
                alignment: const Alignment(-0.78, 0.65),
              ),
              _glowCircle(
                label: "HR",
                value: _formatLegScore(state.legs["HR"]?.scorePct),
                color: _severityColorFromScore(
                  const Color(0xFFE65F5F),
                  state.legs["HR"]?.scorePct,
                ),
                subtitle: "Hinten Rechts",
                alignment: const Alignment(0.78, 0.65),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Column(
          children: [
            MetricBox(
              title: "Zeitliches Gleichmaß",
              value: _formatPct(temporal),
            ),
            const SizedBox(height: 12),
            MetricBox(
              title: "Räumliches Gleichmaß",
              value: _formatPct(spatial),
            ),
            const SizedBox(height: 12),
            MetricBox(
              title: "Taktscore",
              value: _formatPct(takt),
            ),
            const SizedBox(height: 12),
            MetricBox(
              title: "Datenqualität",
              value: _formatPct(conf),
            ),
          ],
        )
      ],
      ),
    );
  }

  // -----------------------------------------------------------
  // TABS (Schritt / Trab / Galopp)
  // -----------------------------------------------------------
  Widget _tab(String text, bool active) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: active ? Colors.white : const Color(0xFF2A3A35),
        borderRadius: BorderRadius.circular(14),
        boxShadow: active
            ? [
                BoxShadow(
                  color: Colors.white.withOpacity(0.25),
                  blurRadius: 20,
                  spreadRadius: -8,
                )
              ]
            : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: "Inter",
          fontSize: 14,
          color: active ? Colors.black : Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // -----------------------------------------------------------
  // HIGH-FIDELITY GLOWING CIRCLE
  // -----------------------------------------------------------
  Widget _glowCircle({
    required String label,
    required String value,
    required String subtitle,
    required Color color,
    required Alignment alignment,
  }) {
    const outerSize = 96.0;
    const innerSize = 78.0;

    return Align(
      alignment: alignment,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Circle + Glow
          Stack(
            alignment: Alignment.center,
            children: [
              // outer glow
              Container(
                width: outerSize,
                height: outerSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.45),
                      blurRadius: 32,
                      spreadRadius: 4,
                    ),
                  ],
                ),
              ),

              // circle stroke
              Container(
                width: innerSize,
                height: innerSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2.5),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontFamily: "Inter",
              fontSize: 18,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontFamily: "Inter",
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            subtitle,
            style: const TextStyle(
              fontFamily: "Inter",
              fontSize: 12,
              color: Colors.white38,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatMs(double? v) {
    if (v == null || v.isNaN || v.isInfinite) return "--";
    final sign = v >= 0 ? "+" : "-";
    return "$sign${v.abs().toStringAsFixed(0)}ms";
  }

  String _formatLegScore(double? v) {
    if (v == null || v.isNaN || v.isInfinite) return "--";
    return "${v.toStringAsFixed(0)}%";
  }

  String _formatVarMs(double? v) {
    if (v == null || v.isNaN || v.isInfinite) return "--";
    return "±${v.abs().toStringAsFixed(0)} ms";
  }

  String _formatPhasePair(double? diag, double? lat) {
    if (diag == null || lat == null) return "--";
    return "diag ${diag.toStringAsFixed(0)}° · lat ${lat.toStringAsFixed(0)}°";
  }

  String _formatPct(double? v) {
    if (v == null || v.isNaN || v.isInfinite) return "--";
    return "${v.toStringAsFixed(0)}%";
  }

  Color _severityColor(Color base, double? devMs) {
    if (devMs == null || devMs.isNaN || devMs.isInfinite) {
      return base.withOpacity(0.35);
    }
    final a = devMs.abs();
    if (a < 30) return base;
    if (a < 60) return Color.lerp(base, const Color(0xFFE6B63A), 0.55)!;
    return Color.lerp(base, const Color(0xFFE63A4A), 0.7)!;
  }

  Color _severityColorFromScore(Color base, double? scorePct) {
    if (scorePct == null || scorePct.isNaN || scorePct.isInfinite) {
      return base.withOpacity(0.35);
    }
    if (scorePct >= 80) return base;
    if (scorePct >= 60) {
      return Color.lerp(base, const Color(0xFFE6B63A), 0.55)!;
    }
    return Color.lerp(base, const Color(0xFFE63A4A), 0.7)!;
  }

}
