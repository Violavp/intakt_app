import 'package:flutter/material.dart';

class MainPage extends StatelessWidget {
  const MainPage({super.key});

  static const _removedBlocks = [
    'Training & Analyse',
    'Daten & Speicherung',
    'Exports & Diagnostik',
    'Dokumentation',
    'Tests',
    'alte Widgets',
    'Entwickler-Tools',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          children: [
            const _Wordmark(),
            const SizedBox(height: 28),
            const Text(
              'InTakt App',
              style: TextStyle(
                color: Colors.black,
                fontSize: 32,
                height: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Die ausgewählten Bausteine wurden entfernt. Diese Ansicht bleibt als saubere Basis für den nächsten Aufbau bestehen.',
              style: TextStyle(
                color: Color(0xFF6D6D72),
                fontSize: 15,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E5EA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Entfernte Bausteine',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final block in _removedBlocks) _RemovedBlockRow(block),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timeline_rounded, color: Color(0xFF1C6B3A), size: 26),
        SizedBox(width: 8),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'In',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(
                text: 'Takt',
                style: TextStyle(
                  color: Color(0xFF1C6B3A),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          style: TextStyle(fontSize: 20),
        ),
      ],
    );
  }
}

class _RemovedBlockRow extends StatelessWidget {
  final String label;

  const _RemovedBlockRow(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: Color(0xFFE8F5E9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 15,
              color: Color(0xFF1C6B3A),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
