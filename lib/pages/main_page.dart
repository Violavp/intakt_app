import 'dart:async';
import 'package:flutter/material.dart';

import '../services/BLE.dart';
import '../services/sensor_storage.dart';
import '../widgets/circle_indicator.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  late BLEManager ble;
  late SensorStorage storage;

  @override
  void initState() {
    super.initState();

    storage = SensorStorage();
    ble = BLEManager(storage: storage);

    // Sensoren sofort verbinden
    ble.startScanAndConnect();

    // UI regelmäßig updaten (für Statuspunkte)
    Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F0E),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(height: 10),

            // Titel
            const Text(
              "Live-\nTraining",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 10),

            // Tabs
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _tab("Schritt", false),
                const SizedBox(width: 12),
                _tab("Trab", true),
                const SizedBox(width: 12),
                _tab("Galopp", false),
              ],
            ),

            const SizedBox(height: 20),

            // KPIs (Takt, Symmetrie, Lastaufnahme)
            SizedBox(
              width: 280,
              height: 300,
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pushNamed(context, "/takt"),
                    child: const CircularIndicator(
                      label: "Takt",
                      value: 0.75,
                      color: Color(0xFF3AE6A1),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pushNamed(context, "/symmetrie"),
                        child: const CircularIndicator(
                          label: "Geraderichtung",
                          value: 0.62,
                          color: Color(0xFFE6B63A),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pushNamed(context, "/last"),
                        child: const CircularIndicator(
                          label: "Lastaufnahme",
                          value: 0.44,
                          color: Color(0xFFE63A4A),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),

            Column(
              children: [
                // Verbindungspunkte
                connectionDots(),
                const SizedBox(height: 18),

                // Start Training Button
                Container(
                  width: 300,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF7FDB70),
                        Color(0xFF6DBF63),
                      ],
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      "Start Training",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // Export Daten Button
                Container(
                  width: 300,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2F2C),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text(
                      "Export Daten",
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------
  //   UI-Teile
  // ---------------------------------------------

  Widget _tab(String label, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: active ? Colors.white : const Color(0xFF1C2622),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.black : Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // Verbindungspunkte VL / VR / HL / HR
  Widget connectionDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        dot("VL"),
        const SizedBox(width: 12),
        dot("VR"),
        const SizedBox(width: 12),
        dot("HL"),
        const SizedBox(width: 12),
        dot("HR"),
      ],
    );
  }

  Widget dot(String role) {
    final isConnected = ble.connected[role] ?? false;

    Color color =
        isConnected ? const Color(0xFF00FF85) : const Color(0xFFFF5757);

    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.9),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.7),
            blurRadius: 6,
            spreadRadius: 1.5,
          ),
        ],
      ),
    );
  }
}
