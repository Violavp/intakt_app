# InTakt-Zeitsynchronisation

## Scope und fachliche Definition

Der Analysebaustein erzeugt aus vier bereits importierten IMU-Sensorströmen
einen neuen, synchronisierten Datensatz. Er verändert weder Rohdateien noch
importierte `ImuSample`-Objekte.

Benötigt werden:

- streng steigende Zeitstempel je Sensor,
- dreiachsige Beschleunigung in `m/s²`,
- dreiachsige Winkelgeschwindigkeit in `rad/s`,
- optional Magnetfeld in `µT`,
- alle vier konfigurierten Pflichtsensoren.

Ausgegeben werden:

- ein gemeinsamer Zeitstempel pro Rasterzeile,
- linear interpolierte Sensorwerte in den internen Einheiten,
- die beiden Quellzeilen jedes interpolierten Werts,
- Startversatz, Signalversatz, Drift, Lag-Residualfehler, Korrelation,
  Rasterabdeckung und Unsicherheit je Sensor,
- Beobachtung, Unsicherheit und Empfehlung für jede Auffälligkeit.

Der erwartete Wertebereich für Korrelation ist `[-1, 1]`, für Abdeckung
`[0, 1]` und für die kombinierte Unsicherheit `[0, ∞)` ms. Offset, Drift und
Residualfehler besitzen bewusst keinen erfundenen physiologischen oder
gerätespezifischen Referenzbereich. Ihre Akzeptanzschwellen sind ausschließlich
technische Konfigurationswerte.

## Mathematische Definition

Der erste Pflichtsensor (Standard `VL`) ist die Referenz. Für jedes gleitende
Fenster wird der Lag gesucht, der die Pearson-Korrelation der
Beschleunigungsbeträge maximiert:

```text
a(t) = sqrt(ax(t)² + ay(t)² + az(t)²)
lag_k = argmax_lag corr(a_ref(t), a_sensor(t + lag))
```

Nur Fenster mit mindestens der konfigurierten Zahl von Wertepaaren und
ausreichender Korrelation werden verwendet. Mindestens zwei gültige Fenster
sind nötig. Die Lags werden mit einem affinen Modell beschrieben:

```text
lag(t) = offset + drift × t
korrigierte_zeit(t) = quellzeit(t) − lag(t)
drift_ppm = drift × 1 000 000
```

Der Synchronisationsfehler ist der RMSE der Fensterlags gegenüber diesem
Modell:

```text
RMSE_ms = sqrt(mean((lag_k − lag(t_k))²))
```

Die ausgewiesene technische Unsicherheit kombiniert quadratisch:

```text
unsicherheit_ms =
  sqrt(RMSE_ms² + (lag_suchschritt_ms / 2)² + (rasterperiode_ms / 2)²)
```

Nach der Clock-Korrektur wird die Schnittmenge aller Sensorzeiträume bestimmt.
Das Raster ist an UTC-Mikrosekunden seit Unix-Epoch ausgerichtet. Bei
Quellzeiten ohne dokumentierten UTC-Offset bleibt die absolute Weltzeit trotz
dieser einheitlichen technischen Repräsentation unsicher. Die Standardperiode
beträgt `10 000 µs` beziehungsweise `100 Hz`.

Alle Messkanäle werden linear interpoliert. Ein Quellintervall größer als das
Dreifache des medianen Sensorintervalls wird nicht überbrückt; der Rasterwert
bleibt ausdrücklich leer.

## Zentrale Konfiguration

`ImuSynchronizationConfig` enthält alle technischen Entscheidungen:

| Parameter | Standard | Einheit/Bedeutung |
|---|---:|---|
| `targetSamplingRateHz` | 100 | gemeinsames Raster in Hz |
| `referenceSensorLabel` | erster Pflichtsensor | Referenz |
| `maximumLag` | 250 | symmetrischer Suchbereich in ms |
| `lagStep` | 2 | Suchschritt in ms |
| `correlationWindow` | 2000 | Fensterlänge in ms |
| `correlationWindowStep` | 1000 | Fensterschritt in ms |
| `minimumSamplesPerSensor` | 20 | minimale Eingangslänge |
| `minimumCorrelationSamples` | 20 | minimale Paare je Fenster |
| `minimumWindowCorrelation` | 0,5 | technische Mindestkorrelation |
| `maximumLagResidual` | 12 | maximaler Lag-RMSE in ms |
| `minimumCoverage` | 0,95 | minimale Rasterabdeckung |
| `maximumInterpolationGapFactor` | 3 | maximale Lücke in Medianintervallen |

Diese Standards sind keine medizinischen Aussagen und keine behaupteten
Sensorgrenzen.

## Status und Ausschlusskriterien

- `SYNCHRONIZATION_ACCEPTED`: Offset und Drift sind bestimmbar, der
  Residualfehler liegt innerhalb der Konfiguration und alle Sensoren erreichen
  die Mindestabdeckung.
- `SYNCHRONIZATION_REVIEW_REQUIRED`: Ein gemeinsamer Datensatz ist vorhanden,
  aber mindestens eine Abdeckung unterschreitet die Schwelle. Nicht
  interpolierte Lücken bleiben sichtbar.
- `SYNCHRONIZATION_NOT_POSSIBLE`: Es wird kein Ersatzdatensatz ausgegeben.

Eine Synchronisation wird ausgeschlossen bei fehlenden Pflichtsensoren,
zu wenigen Messwerten, nicht endlichen Werten, doppelten oder rückwärts
laufenden Zeitstempeln, zu kurzer gemeinsamer Überlappung, konstantem oder
nicht eindeutig korrelierbarem Signal, weniger als zwei gültigen Fenstern oder
zu großem Lag-Residual.

## Grafische Prüfung und CLI

```sh
dart run tool/synchronize_imu.dart \
  --rate 100 \
  --reference VL \
  --out outputs/test01_synchronization \
  recordings/test01/raw/20260723203422.txt
```

Bei bestimmbarer Synchronisation entstehen:

```text
synchronization_report.json
synchronized.csv
synchronization_preview.svg
```

Der JSON-Bericht dokumentiert Modell und Fehler. Die CSV enthält das gemeinsame
Raster, alle Signale und die beteiligten Quellzeilen. Die SVG zeigt den
Beschleunigungsbetrag aller Sensoren über derselben Zeitachse und nennt Offset,
Drift, RMSE und Abdeckung. Bei ungültiger Synchronisation bleibt nur der Bericht
erhalten; es wird kein scheinbar gültiger Datensatz erfunden.

## Validierung und bekannte Grenzen

Automatisierte kontrollierte Tests decken unterschiedliche Abtastraten,
bekannte positive und negative Startversätze, bekannte lineare Clock-Drift,
Rauschen, leicht unregelmäßige Abtastung, kurze Datenlücken, konstante Signale,
fehlende Sensoren, nicht endliche Werte, doppelte Zeitstempel, kurze Aufnahmen,
Wiederholbarkeit sowie CSV- und SVG-Ausgabe ab.

Die kontrollierten Tests prüfen die technische Schätzung gegen bekannte
synthetische Offsets und Drifts. Für `test01` liegt zusätzlich eine externe
Video-/Audioreferenz vor. Neun sicht- und hörbare Klopfereignisse am Gurt und
an den Beinsensoren wurden den isolierten IMU-Ereignissen zugeordnet. Das
affine Modell über die 241,085 s lange Aufnahme ergibt:

| Qualitätsmaß | Ergebnis | Einheit |
|---|---:|---|
| modellierter Versatz bei Videozeit 0 | 4,982 | s |
| Lag-Residual-RMSE | 42,302 | ms |
| maximaler absoluter Residualfehler | 86,546 | ms |
| geschätzter Modellgradient | −366,489 | ppm |
| Zahl der Referenzanker | 9 | Ereignisse |

Die vollständigen Anker, Formeln, Quellen und Zuordnungsunsicherheiten stehen
in
`recordings/test01/evidence/video_imu_synchronisation.json`; die zugehörige
grafische Prüfung liegt als `video_imu_synchronisation.svg` vor. Das zuvor
betrachtete `IMG_4011.MOV` wurde vom Benutzer als falsches Video bestätigt und
ist nicht in die Kennzahlen eingeflossen.

Der vorhandene BitMotion-Beispielexport bündelt mehrere Zeilen desselben
Sensors unter identischen Empfangszeitstempeln. Der hier beschriebene
signalbasierte Synchronisierer weist diese Aufnahme weiterhin zurück. Für
diesen Export steht separat die
[`indexbasierte Zeitrekonstruktion`](indexzeit-rekonstruktion.md) zur
Verfügung. Sie übernimmt die Originalreihenfolge, kennzeichnet jede
Analysezeit ausdrücklich als rekonstruiert und weist die zusätzliche
Unsicherheit aus. Die Videoanker beseitigen die Unsicherheit auf Sampleebene
nicht. Ein geschätzter Gradient kann auch BLE-/App-Paketierung und die
manuelle Wahl des Ereignismaximums enthalten und ist daher keine isoliert
nachgewiesene Sensor-Clock-Drift.

Empfehlung für den nächsten Versuch: die bereits bewährten sicht- und hörbaren
Klopfereignisse beibehalten und zusätzlich monotone Sensorabtastzeitstempel
oder einen gemeinsamen Hardware-Trigger speichern. Erst dann kann die reale
Aufnahme ohne erfundene Zwischenzeiten als synchronisierter Sampledatensatz
freigegeben werden.
