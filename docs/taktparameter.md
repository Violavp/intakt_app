# Zeitliche Taktparameter

## Fachlicher Umfang

Die FN beschreibt Takt als Gleichmaß aller Schritte, Tritte und Sprünge und
verbindet ihn mit dem individuell passenden Tempo. Für InTakt wird daraus
keine einzelne Wertnote abgeleitet. Die Parameterstufe beschreibt getrennt:

1. Zyklusdauer und Zyklusfrequenz,
2. Streuung der Zyklusdauer,
3. Änderung der Zyklusdauer innerhalb eines Fensters,
4. Stabilität der Phasenbeziehungen,
5. zeitliche Links-rechts-Symmetrie.

Grundlage:

- https://www.pferdesport-deutschland.de/ausbildung/ausbildung-des-pferdes/ausbildung-des-pferdes
- https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0254813
- https://pubmed.ncbi.nlm.nih.gov/27862238/
- https://www.frontiersin.org/journals/veterinary-science/articles/10.3389/fvets.2024.1459553/full

Das Ergebnis ist eine zeitliche Signalbeobachtung. Es ist weder eine
reitsportliche Taktbewertung noch eine Aussage über Lahmheit oder Gesundheit.

## Stellung in der Pipeline

```text
Import
→ Qualitätsprüfung
→ Zeitrekonstruktion
→ Vorverarbeitung
→ frequenzbasierte Gangsegmentierung
→ Ereignis- und Zykluserkennung
→ zeitliche Taktparameter
→ später: validiertes Scoring und Interpretation
```

Der Baustein erkennt keine Ereignisse neu und ändert keine Gangart. AngleZ
trennt lediglich linke und rechte Linien, damit diese nicht in einem
Mittelwert vermischt werden.

Verwendet werden nur vollständige, technisch plausible Zyklen, die vollständig
innerhalb desselben Gangart- und Richtungsfensters liegen. Übergänge,
Richtungswechsel, Unterbrechungen und nicht analysierbare Segmente werden
ausdrücklich als ungültige Fenster ausgegeben.

## Warum zehn bis zwanzig Sekunden?

Die erste technische Konfiguration verwendet:

| Einstellung | Wert | Begründung |
|---|---:|---|
| Auswertefenster | adaptiv 10–20 s | kürzestes Fenster mit mindestens sechs gültigen Zyklen jedes Beins |
| Aktualisierung | 1 s | später live-taugliche, gleitende Anzeige |
| Mindestzahl | 6 gültige Zyklen je Bein | verhindert Mittelwerte aus einzelnen Zyklen |
| Vergleich | vorheriges angrenzendes gültiges Fenster | aktuelles und vorheriges Fenster überlappen nicht |

Zehn und zwanzig Sekunden sind keine physiologischen Referenzwerte. In
`test01` ergab ein festes 10-s-Fenster wegen unvollständiger automatischer
Ereignisse nur 4 gültige Fenster. Bei 15 s waren es 44 von 92, bei 20 s 71 von
77 möglichen stabilen Fenstern. Deshalb beginnt der Algorithmus bei 10 s und
verlängert rückwärts bis höchstens 20 s. Die Einstellung muss mit weiteren
Pferden, Geschwindigkeiten und unabhängig annotierten Aufnahmen geprüft
werden.

Ein Fenster wird jede Sekunde neu berechnet. Die Verlaufsaussage verwendet das
zeitlich unmittelbar davor liegende gültige Fenster nur dann, wenn es das
aktuelle Fenster nicht überlappt. Damit werden dieselben Zyklen nicht
gleichzeitig als aktueller und vorheriger Zustand verwendet.

## Definitionen

Für Bein `l` und Zyklus `i`:

```text
T_l,i = t_l,i+1 - t_l,i
```

Mittelwert und Stichprobenstreuung:

```text
mean_T = sum(T_i) / n
SD_T = sqrt(sum((T_i - mean_T)^2) / (n - 1))
```

Zyklusfrequenz:

```text
f = 1 / mean_T
```

Variabilität:

```text
CV_T = 100 * SD_T / mean_T
```

Die Frequenz ist damit eine echte, ereignisbasierte Zyklusfrequenz. Sie ist
nicht mit der dominanten Frequenz des Beschleunigungsspektrums aus der
Gangsegmentierung gleichzusetzen.

Alle vier Beinwerte bleiben einzeln erhalten. Der Fensterwert ist der Mittelwert
der vier Beinmittelwerte beziehungsweise der vier beinbezogenen
Variationskoeffizienten. Dadurch werden unterschiedlich viele erkannte Zyklen
eines Beins nicht stillschweigend stärker gewichtet. Die Unsicherheit des
Fensterwerts enthält zusätzlich die Streuung zwischen den Beinen.

Die Tempostabilität ist die Steigung einer linearen Anpassung:

```text
T_i = intercept + drift * cycle_mid_time_i
```

`drift > 0` bedeutet längere Zyklen im Fenster, `drift < 0` kürzere Zyklen.
Keine Richtung wird ohne individuellen Bezug als besser bewertet.

## Beinphasen

Die Phase eines Zielbeins relativ zum Referenzbein ist:

```text
phase = fraction((target_event_time - reference_event_time) /
                 reference_cycle_duration)
```

Ausgegeben werden zirkulärer Mittelwert und zirkuläre Standardabweichung.
Für Schritt wird die Phasenstabilität beschrieben, aber kein exakt
gleichmäßiger Viertelzyklus erzwungen.

Für Trab werden zusätzlich die dokumentierten Beziehungen geprüft:

- `VL ↔ HR` und `VR ↔ HL`: erwartete Diagonalphase `0`,
- `VL ↔ VR` und `HL ↔ HR`: erwartete Gegenphase `0,5`.

Diese Zielphasen beschreiben den technischen Zweitakt. Abweichungen sind keine
Diagnose.

## Unsicherheit

Die Ereigniszeitunsicherheit wird für eine Zyklusdauer fortgepflanzt:

```text
u_T = sqrt(u_start² + u_end²)
```

Die Unsicherheit eines Mittelwerts kombiniert:

- Streuung der beobachteten Zyklen,
- fortgepflanzte Ereigniszeitunsicherheit.

Streuung, Variationskoeffizient und zirkuläre Streuung erhalten eine
deterministische Jackknife-Unsicherheit. Alle gültigen Größen enthalten
Standardunsicherheit und ein technisches 95-%-Intervall mit Faktor `1,96`.
Diese Intervalle sind nicht klinisch kalibriert.

Ungültige Werte werden so ausgegeben:

```json
{
  "valid": false,
  "value": null,
  "invalid_reason": "insufficient_valid_cycles_VL"
}
```

## Live-Verlauf und erklärbare Änderung

Vier Komponenten werden zwischen zwei nicht überlappenden Fenstern verglichen:

| Beobachtung | Bedeutung einer kleineren Größe |
|---|---|
| Zyklusdauer-CV | gleichmäßigere Zykluszeiten |
| Betrag der Zyklusdauer-Steigung | stabileres Tempo |
| Phasenstreuung | stabilere Beinabfolge |
| zeitliche Symmetrieabweichung | gleichmäßigere Links-rechts-Zeitbeziehung |

Eine Komponente wird nur als `IMPROVED` oder `WORSENED` bezeichnet, wenn die
Differenz größer als `1,96 × kombinierte Standardunsicherheit` ist.
Andernfalls lautet die Ausgabe `STABLE_WITHIN_UNCERTAINTY`.

Eine Frequenzänderung wird lediglich als
`CHANGED_WITHOUT_VALENCE` gekennzeichnet: schneller oder langsamer ist ohne
weiteren Kontext nicht automatisch besser oder schlechter.

Damit kann eine spätere Oberfläche zum Beispiel anzeigen:

- „zeitliches Gleichmaß verbessert“,
- „größte Verschlechterung: wechselnde Zyklusdauer“,
- „Tempo hat sich verändert; keine Qualitätswertung“,
- „nicht bestimmbar: zu wenige gültige Zyklen an HR“.

Eine zusammengefasste Taktampel oder Wertnote wird erst entwickelt, wenn die
Einzelparameter unabhängig validiert und fachlich gewichtet wurden.

## Ausgaben

Der bestehende Gangzyklus-Aufruf erzeugt zusätzlich:

```text
takt_parameter_report.json
takt_windows.csv
takt_trend.svg
```

Der JSON-Bericht enthält je Fenster alle Beinwerte, verwendeten Zyklus-IDs,
Phasenpaare, Unsicherheiten, Vergleichsfenster und erklärenden
Beobachtungscodes. Über die Zyklus- und Ereignisberichte führen die IDs bis zu
Rohdatei und Rohzeile zurück.
