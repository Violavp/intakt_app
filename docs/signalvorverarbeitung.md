# InTakt-Signalvorverarbeitung

## Scope und fachliche Definition

Der Baustein verarbeitet ausschließlich das gemeinsame Raster der separaten
indexbasierten Zeitrekonstruktion. Import, Qualitätsprüfung,
Zeitrekonstruktion, Ereigniserkennung, Parameterberechnung, Scoring und
Interpretation bleiben eigenständige Stufen. Rohdateien und importierte
`ImuSample`-Objekte werden weder verändert noch überschrieben.

Benötigte Signale:

- dreiachsige Beschleunigung in `m/s²`,
- dreiachsige Winkelgeschwindigkeit in `rad/s`,
- optional dreiachsiges Magnetfeld in `µT`,
- optional AngleX/Y/Z in Grad,
- rekonstruierte Analysezeit in Sekunden,
- Lücken und Quellzeilen aus der Zeitrekonstruktion.

Ausgegeben werden für jeden Rasterpunkt:

- unveränderte Rohwerte samt Quellzeilen,
- statistisch bereinigte Werte,
- tiefpassgefilterte Werte im Sensorrahmen,
- in einen Schwerkraftrahmen gedrehte Werte,
- geschätzter Gravitations- und Bewegungsanteil,
- Ausreißermarkierung und technische zeitliche Auflösung.

Die Gerätewinkel werden in dieser Stufe nicht gefiltert oder anatomisch
umgedeutet. Sie bleiben im rekonstruierten Rohwert erhalten; die spätere
Richtungsstufe entfaltet ausschließlich AngleZ über die `±180°`-Grenze.

Es wird keine physiologische Kennzahl berechnet. Wertebereiche der Messgrößen
werden nicht künstlich begrenzt. Nicht endliche Werte, ungültige Zeitachsen,
fehlende Eingangsdaten und zu kurze Segmente führen zu expliziten ungültigen
Ergebnissen oder Lücken.

## Verarbeitungsschritte und Mathematik

### 1. Isolierte Ausreißerkandidaten

Jeder Beschleunigungs- und Gyroskopkanal wird getrennt mit einem Hampel-Fenster
geprüft:

```text
m_i   = Median(x_(i-k) … x_(i+k))
MAD_i = Median(|x_j - m_i|)
s_i   = max(1,4826 × MAD_i, konfigurierte Mindestskala)
Kandidat, wenn |x_i - m_i| > h × s_i
```

Nur Kandidatenläufe bis zur konfigurierten Maximallänge werden durch den
lokalen Median ersetzt. Längere Läufe bleiben erhalten, weil sie ein reales
kurzes Bewegungsereignis darstellen können. Die Zahl ersetzter und bewusst
beibehaltener Kandidaten wird gemeldet. Das ist eine technische robuste Regel,
kein Sensor- oder Pferdereferenzbereich.

### 2. Bewegungs-Tiefpass

Ausgewählt ist ein Butterworth-Tiefpass vierter Ordnung als Kaskade zweier
Biquads mit den normierten Polpaar-Güten
`Q = 0,541196100146197` und `Q = 1,306562964876377`. Für jedes Polpaar werden
die digitalen RBJ-Koeffizienten verwendet:

```text
ω = 2π fc / fs
α = sin(ω) / (2Q)
b0 = (1 - cos(ω)) / (2(1 + α))
b1 = (1 - cos(ω)) / (1 + α)
b2 = b0
a1 = -2cos(ω) / (1 + α)
a2 = (1 - α) / (1 + α)
```

Der Filter läuft vorwärts und rückwärts. Dadurch entsteht keine systematische
Phasenverschiebung; die effektive Amplitudenantwort wird quadriert und die
Offline-Verarbeitung ist nicht kausal. Das Signal wird an beiden Enden konstant
gepolstert. Filterzustände werden niemals über Datenlücken getragen.

Zum technischen Vergleich berechnet der Bericht für den ausgewählten Filter
und einen zentrierten gleitenden Mittelwert:

- RMS der ersten Differenz als Rauheitsmaß in `m/s²`,
- Verhältnis der Peak-to-Peak-Amplituden,
- Verschiebung des stärksten betragsmäßigen Ereignisses in `ms`.

Diese Größen zeigen Glättung und Ereigniserhaltung, validieren aber noch keine
Gangereignisse.

### 3. Sensororientierung

In gleitenden Fenstern wird die mittlere Beschleunigung und der Gyroskop-RMS
berechnet. Das Fenster mit der geringsten normierten Abweichung von
Standardgravitation und der geringsten Rotation wird als Lagefenster gewählt.
Es wird nur akzeptiert, wenn beide konfigurierten technischen Kriterien erfüllt
sind.

Eine Rodrigues-Rotation richtet den mittleren Gravitationsvektor auf `+Z` aus.
Damit sind Roll und Pitch technisch vereinheitlicht. Eine Drehung um die
Vertikale (Yaw), anatomisch vorwärts/seitwärts und die exakten Vorzeichen der
gespiegelten Rechts-/Linksmontage bleiben ohne gerichtete Kalibrierung
unbestimmt. Es werden keine nicht belegten Achstransformationen erfunden.

### 4. Gravitation und Bewegung

Auf die ausgerichtete Beschleunigung wird ein separater nullphasiger Tiefpass
mit niedriger Grenzfrequenz angewendet:

```text
g_est(t) = LP_gravity(a_aligned(t))
a_movement(t) = a_aligned(t) - g_est(t)
```

Beide Anteile sind filterbasierte Schätzungen. Langsame reale
Körperbewegungen können dem Gravitationsanteil zugerechnet werden; schnelle
Lageänderungen können im Bewegungsanteil verbleiben. Diese Unsicherheit ist
nicht durch das aktuelle Sensorsignal allein auflösbar.

## Zentrale Konfiguration

Alle veränderbaren Entscheidungen stehen in
`config/vorverarbeitung.v1.json` und werden durch
`ImuPreprocessingConfig` validiert.

| JSON-Parameter | Standard | Einheit/Bedeutung |
|---|---:|---|
| `low_pass_cutoff_hz` | 20 | Bewegungs-Tiefpass, Hz |
| `gravity_cutoff_hz` | 0,5 | Gravitationsschätzung, Hz |
| `butterworth_order` | 4 | Ordnung je Filterrichtung |
| `hampel_half_window_samples` | 3 | halbe Fensterbreite, Samples |
| `hampel_threshold_mad` | 4 | robuste Standardabweichungen |
| `maximum_outlier_run_samples` | 1 | maximal ersetzte Laufweite |
| `minimum_acceleration_mad_mps2` | 0,02 | Mindestskala, `m/s²` |
| `minimum_angular_velocity_mad_radps` | 0,002 | Mindestskala, `rad/s` |
| `minimum_segment_samples` | 20 | minimale Filtersegmentlänge |
| `orientation_window_seconds` | 2 | Lagefenster, s |
| `orientation_maximum_gyro_rms_radps` | 0,15 | technisches Ruhekriterium |
| `orientation_maximum_gravity_deviation_mps2` | 1,5 | Grav.-Residuum |
| `standard_gravity_mps2` | 9,80665 | Umrechnungs-/Lagekonstante |
| `comparison_moving_average_window_samples` | 5 | Vergleichsfenster |
| `minimum_event_peak_retention` | 0,75 | technische Prüfschwelle |

Die Grenzfrequenzen sind zunächst technische Prototypentscheidungen. Die
Sensoreinstellung der Referenzaufnahme nennt eine Bandbreite von `44 Hz`; eine
unabhängige Hersteller- oder Laborvalidierung der tatsächlichen
Übertragungsfunktion liegt im Projekt noch nicht vor.

## Reproduzierbarer Aufruf und Ausgaben

```sh
dart run tool/preprocess_imu.dart \
  --preprocessing-config config/vorverarbeitung.v1.json \
  --out outputs/test01_preprocessing \
  recordings/test01/raw/20260723203422.txt
```

Erzeugt werden:

```text
preprocessing_report.json
raw_filtered_comparison.csv
raw_filtered_preview.svg
```

JSON dokumentiert Konfiguration, Qualitätswerte, Filtervergleich,
Orientierungsfenster, Beobachtungen, Unsicherheiten und Empfehlungen. CSV stellt
Roh-, Filter-, Gravitations- und Bewegungswerte zeilengleich gegenüber und
enthält die ursprünglichen Quellzeilen. SVG überlagert Rohsignal, gefiltertes
Signal und Bewegungsanteil für alle Sensoren.

## Validierung, Grenzen und nächste Referenz

Automatisierte kontrollierte Tests prüfen:

- konstante Lage mit bekannter Schwerkraftrichtung,
- Nutzsignal plus hochfrequentes Rauschen,
- isolierte statistische Spitze,
- mehrsampleiges Ereignis, das nicht als Ausreißer entfernt werden darf,
- kurze Lücke ohne Filterung über die Lücke,
- unregelmäßige Ereignisabstände,
- unterschiedliche konfigurierte Abtastraten,
- leere, zu kurze, nicht endliche und zeitlich ungültige Eingaben,
- Wiederholbarkeit sowie CSV-/SVG-Rückverfolgbarkeit.

Die reale Referenz `test01` enthält Videoanker und eine dokumentierte
Sensoranbringung. Sie ermöglicht einen visuellen Roh-/Filtervergleich, aber
noch keine belastbare Fehlerstatistik gegen annotierte Hufereignisse. Der
nächste Versuch sollte deshalb zusätzlich ein unverdecktes, framegenau
annotiertes Ereignisprotokoll, eine definierte ruhige Lagephase und eine
gerichtete Achskalibrierung enthalten. Erst dann können Grenzfrequenz,
Ereigniserhaltung und anatomische Achsen fachlich validiert werden.

### Technisches Ergebnis für `test01`

Der dokumentierte CLI-Lauf verarbeitete am 24. Juli 2026 alle `24.910`
gemeinsamen Rasterpunkte für die vier Beinsensoren und den optionalen
Gurtsensor. In der erzeugten Vorverarbeitung entstanden keine zusätzlichen
Lücken. Die folgenden Werte sind Beobachtungen dieser einzelnen Aufnahme und
keine Referenzbereiche:

| Sensor | ersetzte Samples | beibehaltene Kandidaten | Peak-Erhaltung | Peak-Zeitverschiebung |
|---|---:|---:|---:|---:|
| VL | 312 | 52 | 0,831 | 0 ms |
| VR | 293 | 80 | 0,951 | 10 ms |
| HL | 263 | 24 | 0,876 | 0 ms |
| HR | 306 | 41 | 0,889 | 0 ms |
| SG | 151 | 41 | 0,661 | 10 ms |

`test01` erhält den Status `PREPROCESSING_REVIEW_REQUIRED`. Erstens verlangt
bereits die vorgelagerte indexbasierte Zeitrekonstruktion eine manuelle
Prüfung. Zweitens unterschreitet der Gurtsensor mit `0,661` die konfigurierte
technische Peak-Erhaltung von `0,75`. Die Schwelle wurde nicht nachträglich
verändert. Für die vier Beinsensoren blieb das stärkste Ereignis innerhalb
eines Rasterintervalls von `10 ms`; dies belegt technische Sichtbarkeit in
dieser Aufnahme, aber noch keine fachliche Erkennungsgenauigkeit.
