import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/BLE.dart';
import '../services/takt_engine.dart';
import '../services/takt_models.dart';
import '../services/takt_stream_stabilizer.dart';
import '../services/recording_foreground_service.dart';
import '../services/sensor_storage.dart';
import 'takt_detail.dart';
import '../widgets/circle_indicator.dart';
import '../widgets/green_gradient_background.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  late BLEManager ble;
  late SensorStorage storage;
  late TaktEngine _gaitEngine;
  late TaktStreamStabilizer _stabilizer;
  bool _recording = false;
  bool _calibrating = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();

    storage = SensorStorage();
    _gaitEngine = TaktEngine();
    ble = BLEManager(storage: storage, gaitEngine: _gaitEngine);
    _stabilizer = TaktStreamStabilizer(input: _gaitEngine.stream);

    // Sensoren sofort verbinden
    ble.startScanAndConnect();

    // UI regelmäßig updaten (für Statuspunkte)
    Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _stabilizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GreenGradientBackground(
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(height: 10),
              const Text(
                "Live-Training",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              StreamBuilder<TaktStabilizedState>(
                stream: _stabilizer.stream,
                initialData: TaktStabilizedState.empty(),
                builder: (context, snapshot) {
                  final s = snapshot.data ?? TaktStabilizedState.empty();
                  final gait = s.raw.gait;
                  return Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _tab("Stehen", gait == Gait.stehen),
                          const SizedBox(width: 12),
                          _tab("Schritt", gait == Gait.schritt),
                          const SizedBox(width: 12),
                          _tab("Trab", gait == Gait.trab),
                          const SizedBox(width: 12),
                          _tab("Galopp", gait == Gait.galopp),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Kontext: ${s.contextLabel}${s.frozen ? " (freeze)" : ""}",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.55),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 280,
                height: 300,
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TaktDetailPage(
                            stateStream: _stabilizer.stream,
                          ),
                        ),
                      ),
                      child: StreamBuilder<TaktStabilizedState>(
                        stream: _stabilizer.stream,
                        initialData: TaktStabilizedState.empty(),
                        builder: (context, snapshot) {
                          final s = snapshot.data ?? TaktStabilizedState.empty();
                          final taktPct = (s.stableTaktScorePct ??
                                  s.raw.taktScorePct ??
                                  0.0)
                              .clamp(0.0, 100.0);
                          return CircularIndicator(
                            label: "Takt",
                            value: (taktPct / 100.0).clamp(0.0, 1.0),
                            color: const Color(0xFF3AE6A1),
                          );
                        },
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
                  connectionDots(),
                  const SizedBox(height: 18),
                  _actionButton(
                    label: _recording ? "Training beenden" : "Start Training",
                    active: _recording,
                    onTap: _toggleRecording,
                  ),
                  const SizedBox(height: 18),
                  _actionButton(
                    label: _calibrating ? "Kalibrierung läuft..." : "Kalibrierung",
                    active: _calibrating,
                    onTap: _runCalibration,
                  ),
                const SizedBox(height: 12),
                _actionButton(
                  label: "Export Daten",
                  active: _exporting,
                  onTap: _exportData,
                ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
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
    final fps = ble.framesPerSecondByRole();
    final drops = ble.droppedFramesByRole();
    String fmt(String role) {
      final hz = fps[role] ?? 0;
      final d = drops[role] ?? 0;
      return d > 0 ? "$role ${hz}Hz · drop $d" : "$role ${hz}Hz";
    }

    return Column(
      children: [
        Row(
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
        ),
        const SizedBox(height: 6),
        Text(
          "${fmt("VL")}  |  ${fmt("VR")}  |  ${fmt("HL")}  |  ${fmt("HR")}",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withOpacity(0.45),
            fontWeight: FontWeight.w600,
          ),
        ),
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

  Future<void> _toggleRecording() async {
    if (_recording) {
      await storage.stopRecording();
      setState(() => _recording = false);
      WakelockPlus.disable();
      RecordingForegroundService.stop();
    } else {
      await storage.startRecording();
      _gaitEngine.reset();
      setState(() => _recording = true);
      WakelockPlus.enable();
      RecordingForegroundService.start();
    }
  }

  Future<void> _exportData() async {
    setState(() => _exporting = true);
    try {
      final file = await storage.exportCsv();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Exportiert: ${file.path}"),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Export fehlgeschlagen: $e"),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<void> _runCalibration() async {
    if (_calibrating) return;
    setState(() => _calibrating = true);
    try {
      final ok = await ble.calibrateAll();
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1F302B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                ok ? Icons.check_circle : Icons.error,
                size: 48,
                color: ok ? const Color(0xFF3AE6A1) : Colors.redAccent,
              ),
              const SizedBox(height: 12),
              Text(
                ok ? "Kalibrierung abgeschlossen" : "Kalibrierung fehlgeschlagen",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Kalibrierung fehlgeschlagen: $e")),
      );
    } finally {
      if (mounted) setState(() => _calibrating = false);
    }
  }

  Widget _actionButton({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 300,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: active
              ? const LinearGradient(
                  colors: [Color(0xFF7FDB70), Color(0xFF6DBF63)],
                )
              : null,
          color: active ? null : const Color(0xFF2A2F2C),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : Colors.white.withOpacity(0.85),
            ),
          ),
        ),
      ),
    );
  }
}
