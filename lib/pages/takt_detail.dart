import 'package:flutter/material.dart';
import '../widgets/metric_box.dart';



class TaktDetailPage extends StatelessWidget {
  const TaktDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1612),
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

      body: Center(
        child: Container(
          width: 390,
          height: 844,
          decoration: BoxDecoration(
            color: const Color(0xFF13211B), // iPhone-Rounded-Frame
            borderRadius: BorderRadius.circular(46),
          ),
          child: Column(
            children: [
              const SizedBox(height: 20),

              // Tabs
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _tab("Schritt", false),
                  const SizedBox(width: 10),
                  _tab("Trab", true),
                  const SizedBox(width: 10),
                  _tab("Galopp", false),
                ],
              ),

              const SizedBox(height: 20),

              const Text(
                "Varianz der Abstände",
                style: TextStyle(
                  fontFamily: "Inter",
                  fontSize: 16,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 18),

              // MAIN GRID VISUALIZATION
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // --- Radial soft background glow ---
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

                   

                    // --- Axes (super thin lines) ---
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

                    // --- 4 High-Fidelity Glowing Circles ---
                    _glowCircle(
                      label: "VL",
                      value: "-15ms",
                      color: const Color(0xFF3AE68F),
                      subtitle: "Vorne Links",
                      alignment: const Alignment(-0.75, -0.55),
                    ),
                    _glowCircle(
                      label: "VR",
                      value: "+8ms",
                      color: const Color(0xFF6EE6F5),
                      subtitle: "Vorne Rechts",
                      alignment: const Alignment(0.75, -0.55),
                    ),
                    _glowCircle(
                      label: "HL",
                      value: "+40ms",
                      color: const Color(0xFFE6D35F),
                      subtitle: "Hinten Links",
                      alignment: const Alignment(-0.75, 0.55),
                    ),
                    _glowCircle(
                      label: "HR",
                      value: "-25ms",
                      color: const Color(0xFFE65F5F),
                      subtitle: "Hinten Rechts",
                      alignment: const Alignment(0.75, 0.55),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // METRIC BOXES AT THE BOTTOM
             Column(
              children: [
                const MetricBox(
                  title: "Schrittfrequenz",
                  value: "78 Schritte/min",
                ),

                const SizedBox(height: 12),

                const MetricBox(
                  title: "Phasenverschiebung diagonal vs. lateral",
                  value: "2.3°",
                ),

                const SizedBox(height: 12),

                const MetricBox(
                  title: "Taktstabilität",
                  value: "±12%",
                ),
              ],
            )
            ],
          ),
        ),
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
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.45),
                      blurRadius: 40,
                      spreadRadius: 4,
                    ),
                  ],
                ),
              ),

              // circle stroke
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 3),
                ),
              ),

              // value
              Text(
                value,
                style: TextStyle(
                  fontFamily: "Inter",
                  fontSize: 21,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 15,
              fontFamily: "Inter",
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            subtitle,
            style: const TextStyle(
              fontFamily: "Inter",
              fontSize: 13,
              color: Colors.white38,
            ),
          ),
        ],
      ),
    );
  }

}
