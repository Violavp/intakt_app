import 'package:flutter/material.dart';
import '../core_metrics/takt_metric.dart';
import '../widgets/analysis_metric_tile.dart';

class MainPage extends StatelessWidget {
  const MainPage({super.key, this.taktPresentation});

  final TaktTilePresentation? taktPresentation;

  @override
  Widget build(BuildContext context) {
    final takt = taktPresentation ?? TaktTilePresentation.empty();
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            const _Wordmark(),
            const SizedBox(height: 26),
            const Text(
              'Dein Ritt im Überblick',
              style: TextStyle(
                color: Colors.black,
                fontSize: 30,
                height: 1.05,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 9),
            const Text(
              'Vier Kernbereiche für den ersten InTakt-Prototypen. Tippe auf eine Kachel, um zu sehen, welche Merkmale später in die Bewertung eingehen.',
              style: TextStyle(
                color: Color(0xFF6D6D72),
                fontSize: 15,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.87,
              children: [
                AnalysisMetricTile(
                  title: 'Takt',
                  subtitle: 'Rhythmus, Fußfolge und Stabilität',
                  icon: Icons.graphic_eq_rounded,
                  accentColor: Color(0xFF1C6B3A),
                  statusLabel: 'direkt messbar',
                  description:
                      'Die Takt-Kachel beschreibt, wie regelmäßig und stabil sich das Pferd innerhalb einer Gangart bewegt. Sie soll mehrere zeitliche Merkmale gemeinsam bewerten, statt einen einzelnen CV-Wert als Takt zu behandeln.',
                  features: [
                    'Regelmäßigkeit der TD-zu-TD-Zyklusdauer',
                    'Konstanz von Stütz- und Schwungphase',
                    'Fußfolge und diagonale Phasenlage',
                    'Stabilisierung des Rhythmus nach Übergängen',
                    'Wiederholbarkeit aufeinanderfolgender Zyklen',
                  ],
                  evidenceText: takt.evidenceText,
                  resultLabel: takt.resultLabel,
                  resultDetails: takt.details,
                  limitationText:
                      'Ein einzelner Timing-Parameter ist kein vollständiger Takt-Score. Tempoänderung, Übergänge und fehlerhafte Ereigniserkennung müssen getrennt berücksichtigt werden.',
                ),
                const AnalysisMetricTile(
                  title: 'Losgelassenheit',
                  subtitle: 'Fluss, Glätte und Lockerwerden',
                  icon: Icons.air_rounded,
                  accentColor: Color(0xFF4F7DCC),
                  statusLabel: 'Proxy',
                  description:
                      'Die Losgelassenheits-Kachel bündelt messbare Begleitmerkmale einer flüssigen, wiederholbaren Bewegung. Sie beschreibt zunächst Bewegungsglätte und Entwicklung im Ritt, nicht den psychischen oder muskulären Zustand direkt.',
                  features: [
                    'Ähnlichkeit benachbarter Bewegungszyklen',
                    'Glätte und abrupte Bewegungsänderungen',
                    'Anteil ungewöhnlicher Zyklen',
                    'Entwicklung von Anfang zu Ende des Ritts',
                    'Stabilität bei vergleichbarer Gangart und Aufgabe',
                  ],
                  evidenceText:
                      'Die Sensoren können Bewegungsfluss und Wiederholbarkeit objektiv beschreiben. Daraus lässt sich ein Losgelassenheits-Proxy entwickeln und später gegen Trainerbeurteilungen validieren.',
                  limitationText:
                      'SPARC, Jerk oder Regelmäßigkeit allein beweisen keine Losgelassenheit. Rückenaktivität, Schmerz und mentale Entspannung werden mit den vier Beinsensoren nicht direkt gemessen.',
                ),
                const AnalysisMetricTile(
                  title: 'Symmetrie',
                  subtitle: 'Links/rechts und handabhängige Muster',
                  icon: Icons.compare_arrows_rounded,
                  accentColor: Color(0xFF9A6BC2),
                  statusLabel: 'gut messbar',
                  description:
                      'Die Symmetrie-Kachel prüft, ob sich linke und rechte Gliedmaßen unter vergleichbaren Bedingungen ähnlich verhalten und ob Unterschiede auf beiden Händen bestehen oder mit der Kurve die Seite wechseln.',
                  features: [
                    'Links/rechts-Stütz- und Schwungphasendifferenzen',
                    'Links/rechts-Bewegungsumfang und Rotationsdynamik',
                    'Ähnlichkeit kompletter Gyro-Zyklusformen',
                    'Vergleich linke Hand, rechte Hand und gerade Abschnitte',
                    'Einfluss der Kurvenintensität auf Seitendifferenzen',
                  ],
                  evidenceText:
                      'Zeitliche und kinematische Links/rechts-Unterschiede sind mit vier Beinsensoren sehr gut zugänglich und eignen sich deshalb stark für den Prototypen.',
                  limitationText:
                      'Symmetrie ist nicht automatisch Geraderichtung und keine Lahmheitsdiagnose. Kurvenradius, Tempo, Boden, natürliche Seitigkeit und Sensorlage müssen mitgedacht werden.',
                ),
                const AnalysisMetricTile(
                  title: 'Gewichtsverschiebung',
                  subtitle: 'Hinweis auf mehr Hinterhandbeteiligung',
                  icon: Icons.balance_rounded,
                  accentColor: Color(0xFFC47A3A),
                  statusLabel: 'Proxy',
                  description:
                      'Diese Kachel soll zeigen, ob sich die Bewegungsorganisation relativ zur Hinterhand verschiebt. Für den Prototypen ist das ausdrücklich ein Mehrmerkmals-Proxy für Hinterhandbeteiligung und noch keine direkte Kraft- oder Schwerpunktmessung.',
                  features: [
                    'Zeitorganisation von Vorder- und Hinterhandkontakt',
                    'Diagonale TD- und LO-Reihenfolge',
                    'Hinterbeinwinkel bei Hufaufsatz und Hufabheben',
                    'Rotationsumfang und Dynamik der Hinterbeine',
                    'Kontakt- und Schwebeorganisation bei erhaltenem Takt',
                  ],
                  evidenceText:
                      'Die vorhandenen Versammlungs- und Piaffe/Passage-Studien liefern plausible Zielmuster. Diese müssen in Entwicklungsmessungen gegen Kraftplatte, Becken/Rumpf oder 3D-Referenz validiert werden.',
                  limitationText:
                      'Längere Stützzeit bedeutet nicht automatisch mehr Gewicht. Bis zur externen Validierung darf die App nur von einem Hinweis auf stärkere Hinterhandbeteiligung sprechen.',
                ),
              ],
            ),
            const SizedBox(height: 18),
            const _PrototypeNotice(),
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

class _PrototypeNotice extends StatelessWidget {
  const _PrototypeNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.science_outlined,
            color: Color(0xFF1C6B3A),
            size: 21,
          ),
          SizedBox(width: 11),
          Expanded(
            child: Text(
              'Prototyp: Die Kacheln bilden jetzt die Zielstruktur der App. Die nächsten Schritte sind die datengetriebene Berechnung der Merkmale und die Validierung der Aussagen.',
              style: TextStyle(
                color: Color(0xFF5C5C60),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
