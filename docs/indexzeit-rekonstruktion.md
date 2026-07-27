# Rekonstruktion der Samplezeiten durch Indexierung

## Scope und fachliche Definition

Der Analysebaustein `IndexTimeReconstructor` erzeugt aus den unveränderten
importierten Sensorzeilen eine ausdrücklich **rekonstruierte** Zeitbasis. Er
adressiert Exporte, in denen mehrere Samples eines BLE-Empfangspakets denselben
Empfangszeitstempel tragen.

Benötigte Eingaben:

- Originalreihenfolge, Quellname und Quellzeile jedes IMU-Samples,
- BLE-/App-Empfangszeitstempel,
- dreiachsige Beschleunigung in `m/s²`,
- dreiachsige Winkelgeschwindigkeit in `rad/s`,
- optional Magnetfeld in `µT`,
- optional AngleX/Y/Z in Grad,
- konfigurierte nominale Abtastrate je Sensor in `Hz`,
- mindestens ein bis zur Rohzeile rückverfolgbarer Video-IMU-Anker je
  Pflichtsensor.

Vorhandene optionale Sensoren werden ebenfalls rekonstruiert, wenn ihnen
Videoanker zugeordnet sind. Dadurch fließen bei `test01` die Anfangsereignisse
am Gurtsensor SG zusammen mit den Endereignissen der Beinsensoren ein. Ein
fehlender optionaler Sensor blockiert das Vier-Bein-Raster nicht.

Ausgaben:

- eindeutiger nullbasierter Sampleindex je Sensor,
- BLE-Paketindex,
- Indexzeit und rekonstruierte Analysezeit in Sekunden,
- nominale und effektive Abtastrate in `Hz`,
- Offset in Sekunden, linearer Zeitgradient und Driftindikator in `ppm`,
- Anker-Residualfehler und Rekonstruktionsunsicherheit in Millisekunden,
- Verluststatus und auffällige Empfangslücken,
- gemeinsames Raster mit Quellindizes und Quellzeilen,
- gemeinsame Darstellung von Index-/Analysezeit, Empfangszeit und Videoankern.

Winkel werden auf dem kürzesten Weg über ihr Kreisintervall interpoliert.
Zwischen `179°` und `-179°` entsteht daher ein Wert an der
`±180°`-Grenze und niemals ein erfundener Wert um `0°`.

Der erwartete mathematische Wertebereich für den positiven Zeitgradienten ist
`(0, ∞)`, für Unsicherheit und Residualfehler `[0, ∞)` ms. Es werden keine
physiologischen Referenzbereiche oder medizinischen Aussagen abgeleitet.

## Trennung und Unveränderlichkeit

Der Import bleibt in `lib/imu_import`, die technische Zeitrekonstruktion in
`lib/imu_sync`. Die Rekonstruktion sortiert, ergänzt oder verändert keine
`ImuSample`-Objekte und schreibt niemals in Rohdateien. Das Ergebnis hält eine
Referenz auf das ursprüngliche Objekt und weist Quellname sowie Quellzeile aus.
Vermutete fehlende Samples werden nicht in die Indexfolge eingefügt.

## Mathematische Definition

Für Sensor `s`, Sampleindex `i` und konfigurierte nominale Rate `f_nom,s`:

```text
index_time_s(i) = i / f_nom,s
analysis_time_s(i) = offset_s + gradient_s × index_time_s(i)
drift_indicator_ppm = (gradient_s − 1) × 1 000 000
```

Bei mindestens zwei Videoankern wird `offset` und `gradient` durch lineare
Kleinste-Quadrate-Anpassung zwischen Indexzeit und Videozeit geschätzt. Bei
genau einem Anker ist der Offset bestimmbar; der Gradient wird hilfsweise aus
der effektiven Empfangsrate abgeleitet:

```text
f_eff,s = (N_s − 1) / (t_reception,last − t_reception,first)
gradient_s = f_nom,s / f_eff,s
```

Dieser Ein-Anker-Fall erhält immer den Status `REVIEW_REQUIRED`, weil Sensor-
Clock-Drift und BLE-/App-Paketierung nicht getrennt werden können.

Der Ankerfehler wird in Millisekunden angegeben:

```text
residual_k_ms = 1000 ×
  (video_time_k − analysis_time(sample_index_k))
RMSE_ms = sqrt(mean(residual_k_ms²))
```

Die technische Basisunsicherheit kombiniert quadratisch:

```text
U_base_ms = sqrt(
  RMSE_ms²
  + U_video_anchor_ms²
  + (max_packet_span_ms / 2 + timestamp_resolution_ms / 2)²
)
```

Außerhalb der Anker wächst die Sampleunsicherheit zusätzlich mit einer
Gradientenabweichung. Bei mindestens zwei Ankern ist dies die Differenz
zwischen angepasstem und aus der Empfangsrate abgeleitetem Gradienten. Bei nur
einem Anker wird konservativ die Abweichung des Empfangsraten-Gradienten von
`1` verwendet. Dies ist eine technische Fehlerfortpflanzung, kein
statistisches Konfidenzintervall.

## BLE-Pakete und Verluste

Aufeinanderfolgende Zeilen desselben Sensors mit identischem Empfangszeitstempel
werden zu einem Paket gruppiert. Der Bericht enthält Paketanzahl,
Paketgrößenverteilung und die Anzahl zusätzlicher Samples mit doppeltem
Empfangszeitstempel. Die Sample-CSV enthält den Paketindex jeder Rohzeile.

Ein ungewöhnlich großer Abstand zweier Paket-Empfangszeiten wird als
`SUSPECTED_NOT_PROVEN` gemeldet. Ohne Sensor-Sequenznummer oder monotone
Sensorzeit sind genaue Paket- und Sampleverluste nicht bestimmbar. Deshalb:

- werden keine Lückenindizes oder Ersatzsamples erfunden,
- bedeutet `possible_missing_samples` nur eine Empfangszeit-Indikation,
- bleibt der Verluststatus bei unauffälligen Abständen `notDeterminable`,
- führt ein auffälliger Abstand zu `suspected`.

## Gemeinsames Raster

Die Schnittmenge der rekonstruierten Zeiträume aller Pflichtsensoren wird auf
ein Raster mit konfigurierter Rate abgebildet. Standard sind `100 Hz` bzw.
`10 ms`. Alle Kanäle werden linear interpoliert. Jeder Rasterwert nennt unteren
und oberen Sampleindex, Quellname, Quellzeile und Unsicherheit. Ein
Quellintervall oberhalb des konfigurierten Lückenfaktors wird nicht überbrückt.

## Zentrale Konfiguration

| Parameter | Standard | Einheit/Bedeutung |
|---|---:|---|
| `defaultNominalSamplingRateHz` | 100 | nominale Sensorrate in Hz |
| `nominalSamplingRatesHz` | leer | optionale Rate je Sensor |
| `targetSamplingRateHz` | 100 | gemeinsames Raster in Hz |
| `maximumInterpolationGapFactor` | 3 | maximale Interpolationslücke in Nominalintervallen |
| `suspectedPacketGapFactor` | 2,5 | Schwelle für auffällige Empfangslücken |
| `receptionTimestampResolution` | 1 | angenommene Auflösung in ms |
| `defaultAnchorUncertainty` | 20 | Standard-Ankerunsicherheit in ms |
| `maximumAnchorResidual` | 100 | technischer Ausschlusswert in ms |
| `minimumSamplesPerSensor` | 2 | minimale Sensorlänge |

Diese Werte sind technische Entscheidungen und keine Gerätegarantien.

## Status und Ausschlusskriterien

- `TIME_RECONSTRUCTION_ACCEPTED`: alle Pflichtsensoren sind gültig, besitzen
  mindestens zwei Videoanker und es bestehen keine unaufgelösten
  Verlustmeldungen.
- `TIME_RECONSTRUCTION_REVIEW_REQUIRED`: ein gemeinsames Raster existiert,
  aber mindestens ein Sensor besitzt nur einen Anker oder der Verluststatus ist
  nicht sicher bestimmbar.
- `TIME_RECONSTRUCTION_NOT_POSSIBLE`: kein gemeinsames Raster wird ausgegeben.

Ausgeschlossen werden fehlende Pflichtsensoren, zu kurze Reihen, NaN/Infinity,
rückwärts laufende Empfangszeit, fehlende oder nicht rückverfolgbare Anker,
mehrere Anker am selben Sampleindex, nicht positiver Gradient, zu großer
Anker-Residualfehler und eine leere gemeinsame Zeitüberlappung.

## CLI und grafische Prüfung

```sh
dart run tool/reconstruct_imu_time.dart \
  --nominal-rate 100 \
  --target-rate 100 \
  --anchors recordings/test01/evidence/video_imu_synchronisation.json \
  --out outputs/test01_index_time \
  recordings/test01/raw/20260723203422.txt
```

Ausgaben:

```text
time_reconstruction_report.json
reconstructed_samples.csv
reconstructed_common_grid.csv
time_reconstruction_preview.svg
```

Die Sample-CSV enthält Indexzeit, Empfangszeit und rekonstruierte Analysezeit
gemeinsam. Die SVG stellt pro Sensor den Verlauf der rekonstruierten Zeit und
der paketierten Empfangszeit über dem Sampleindex dar; Videoanker erscheinen
als orange Markierungen.

## Validierung und bekannte Grenzen

Automatisierte kontrollierte Tests prüfen normale und unterschiedliche
Abtastraten, bekannte Offsets und Gradienten, gebündelte Zeitstempel,
Messrauschen, unregelmäßige Signale, kurze Empfangslücken, Wiederholbarkeit,
leere Eingaben, fehlende Sensoren und Anker, NaN, rückwärts laufende Zeit,
kurze Aufnahmen, fehlerhafte Konfiguration sowie CSV-/SVG-Rückverfolgbarkeit.

Die vorhandene Testaufnahme stellt neun Video-IMU-Anker bereit. Nicht jeder
Pflichtsensor besitzt dabei je einen Anker am Anfang und am Ende. Für solche
Sensoren muss der Gradient aus der effektiven Empfangsrate geschätzt werden;
die reale Ausgabe ist daher nur `REVIEW_REQUIRED`. Der Algorithmus ist
technisch gegen kontrollierte Daten geprüft, aber noch nicht mit
hardwareseitigen Samplezeitstempeln oder Sequenznummern fachlich validiert.

Empfehlung für den nächsten Versuch: für jeden Sensor ein klar isoliertes,
sicht- und hörbares Ereignis am Anfang und Ende annotieren und zusätzlich
Sensor-Sequenznummer sowie monotone Sensorzeit exportieren.
