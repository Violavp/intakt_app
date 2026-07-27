# InTakt – Gangart und Analyseabschnitte

## Scope und fachliche Definition

Der Baustein `GaitSegmenter` bestimmt zeitliche Bewegungsabschnitte aus dem
bereits vorverarbeiteten gemeinsamen IMU-Raster. Er trennt Stillstand von
Bewegung, ordnet periodische Bewegung technisch Schritt, Trab oder optional
Galopp zu und markiert Übergänge, kurze Unterbrechungen und
Wendungskandidaten. Nur Abschnitte, die alle technischen Qualitätsbedingungen
erfüllen, erhalten `analyzable = true`.

Dies ist genau ein Analysebaustein. Import, Qualitätsprüfung,
Zeitrekonstruktion, Vorverarbeitung, spätere Ereigniserkennung,
Parameterberechnung, Scoring und Interpretation bleiben getrennt. Rohdaten
werden ausschließlich gelesen und niemals verändert.

Benötigte Signale:

- vier vorverarbeitete Beinsensoren `VL`, `VR`, `HL`, `HR`,
- dreiachsige Bewegungsbeschleunigung in `m/s²`,
- dreiachsige ausgerichtete Winkelgeschwindigkeit in `rad/s`,
- AngleX/Y/Z der vier Beinsensoren in Grad; für Richtung und Biegung wird
  ausschließlich AngleZ verwendet,
- `analysis_time_s` in Sekunden sowie Quellzeilen aus der Zeitrekonstruktion.

Ausgaben je Segment:

- Start, Ende und Dauer in Sekunden,
- identische Videozeitgrenzen (`video_start_s`, `video_end_s`),
- `STANDING`, `WALK`, `TROT`, `GALLOP` oder `UNKNOWN`,
- technische Konfidenz und Unsicherheit in `[0, 1]`,
- dominante Beinfrequenz in `Hz`,
- Bewegungs-RMS in `m/s²` und Datenabdeckung,
- Richtung `LEFT`, `RIGHT` oder `UNKNOWN`, getrennte Angle-Z-Trends für vorne
  und hinten sowie eine signierte Biegungsrate in `°/s`,
- Übergangs-, Wendungs-, Unterbrechungs- und Analyseflag,
- angewandte manuelle Korrekturen samt Begründung,
- erste und letzte Rohdaten-Quellzeile je Sensor.

Welche Gangarten vorkommen dürfen, wird aus dem dokumentierten
Aufnahmeprotokoll konfiguriert. Für `test01` sind ausschließlich `WALK` und
`TROT` aktiviert; `GALLOP` kann daher nicht ausgegeben werden. Die
Signalgruppen sind aufnahmeinterne technische Merkmale und keine
physiologischen Referenzbereiche.

## Mathematische und technische Definition

### Bewegungszustand

Die Entscheidung wird alle `step_seconds` aus dem lokalen RMS der vier
Beinsensoren getroffen:

```text
r_leg = sqrt(mean(ax² + ay² + az²))
r_move = mean(r_VL, r_VR, r_HL, r_HR)
```

Eine Hysterese verhindert schnelles Umschalten: Bewegung beginnt bei
`movement_on_rms_mps2` und endet erst unter `movement_off_rms_mps2`. Ist die
kleinste Abdeckung eines Beins geringer als `minimum_window_coverage`, kann das
Fenster nicht analysierbar werden. Stillstand und Bewegung sind damit eine
technische Signalentscheidung, nicht die Beobachtung einer Körperhaltung.

### Periodizität und Gangart

In einem größeren, zentrierten Fenster wird für die vertikale
Bewegungsbeschleunigung jedes Beins eine diskrete Frequenzsuche durchgeführt:

```text
P(f) = sum_leg |sum_n (z_leg[n] - mean(z_leg)) exp(-i 2π f n / fs)|² / N²
```

Das stärkste `P(f)` liefert die dominante Beinfrequenz. Die spektrale
Konfidenz ist der normierte Kontrast zwischen stärkstem Bin und mittlerer
Hintergrundleistung:

```text
C_spectral = (P_max - mean(P_other)) / (P_max + mean(P_other))
```

Unterhalb der Mindestkonfidenz wird Bewegung ausdrücklich `UNKNOWN`. Die
übrigen Fenster werden innerhalb derselben Aufnahme deterministisch in so
viele Frequenzgruppen geclustert, wie das Aufnahmeprotokoll Gangarten
freigibt. Die Clusterzentren werden aufsteigend den konfigurierten Gangarten
zugeordnet. Bei `test01` bedeutet das: niedrigere stabile Frequenzgruppe =
Schritt, höhere stabile Frequenzgruppe = Trab. Es gibt keine feste
physiologische Hz-Grenze.

Die Fensterentscheidungen werden anschließend zu zeitlichen Blöcken
zusammengefasst. Eine neue höhere Gangart muss über mehrere Fenster stabil
sein. Weil das Protokoll für `test01` Schritt vor Trab vorgibt, wird ein
späterer kurzer Frequenzrückgang nicht als Rückkehr zum Schritt ausgegeben,
sondern `UNKNOWN` und damit als prüfpflichtiger Übergangsbereich markiert.
Längerer Stillstand setzt diese Reihenfolgenlogik zurück. Kurze
Handhabungsereignisse vor und nach dem eigentlichen Bewegungsversuch bleiben
`UNKNOWN`.

Die Segmentkonfidenz ist:

```text
C = coverage × C_spectral                 für Bewegung
C = coverage × C_activity                 für Stillstand
uncertainty = 1 - C
```

Sie ist ein reproduzierbarer technischer Qualitätswert und keine kalibrierte
Wahrscheinlichkeit.

### Übergänge, Wendungen und Unterbrechungen

- Ein Entscheidungsintervall an einem Zustandswechsel wird als Übergang
  markiert.
- Ein kurzes Stillstandsintervall zwischen zwei Bewegungsintervallen wird bis
  `maximum_interruption_seconds` als Unterbrechung markiert.
- AngleZ wird je Bein über die `±180°`-Grenze entfaltet. In einem vom
  Frequenzfenster getrennten Langzeitfenster wird die lineare Steigung
  `s_leg` in `°/s` bestimmt.
- Stimmen alle vier Beinsensoren oberhalb der technischen Mindeststeigung im
  Vorzeichen überein, gilt für die nutzerbestätigte Montage von `test01`:
  `s_leg > 0 → LEFT`, `s_leg < 0 → RIGHT`. Andernfalls ist die Richtung
  ausdrücklich `UNKNOWN`.
- Ein Wendungskandidat entsteht erst beim nachhaltigen Wechsel
  `LEFT → RIGHT` oder `RIGHT → LEFT`. Eine Änderung der Frequenz ohne
  Vorzeichenwechsel bleibt ausschließlich ein Gangartwechsel.

```text
delta_i = wrapTo180(angle_z_i - angle_z_(i-1))
unwrapped_i = unwrapped_(i-1) + delta_i
s_leg = covariance(time, unwrapped) / variance(time)
s_front = mean(s_VL, s_VR)
s_hind  = mean(s_HL, s_HR)
```

`mean_angle_z_trend_degps` beziehungsweise `line_bending_rate_degps`
beschreibt die signierte Winkelentwicklung der gerittenen Linie. Ohne
Streckeninformation ist sie keine geometrische Krümmung in `1/m`.

Übergänge, Wendungskandidaten und Unterbrechungen werden unabhängig von der
Gangart von der weiteren Analyse ausgeschlossen.

### Auswahl analysierbarer Abschnitte

`analyzable = true` gilt nur, wenn gleichzeitig:

1. die Gangart `WALK`, `TROT` oder `GALLOP` ist,
2. die Mindestdauer erreicht ist,
3. Konfidenz und Abdeckung ihre Mindestwerte erreichen,
4. kein Übergang, Wendungskandidat oder Unterbrechung vorliegt,
5. kein manueller Ausschluss aktiv ist.

Ungültige oder unsichere Abschnitte bleiben sichtbar und werden nicht durch
Ersatzwerte kaschiert.

## Zentrale Konfiguration

Alle Entscheidungen stehen in `config/gangsegmentierung.v1.json`.

| Parameter | Standard | Einheit / Bedeutung |
|---|---:|---|
| `window_seconds` | 4,0 | Frequenz-Kontextfenster, s |
| `step_seconds` | 0,5 | zeitliche Entscheidungsauflösung, s |
| `minimum_window_coverage` | 0,9 | kleinste Beinabdeckung, Anteil |
| `movement_on_rms_mps2` | 0,45 | Bewegung beginnt, `m/s²` RMS |
| `movement_off_rms_mps2` | 0,30 | Bewegung endet, `m/s²` RMS |
| `minimum_frequency_hz` | 0,5 | untere Frequenzsuche, Hz |
| `maximum_frequency_hz` | 4,5 | obere Frequenzsuche, Hz |
| `frequency_resolution_hz` | 0,05 | Frequenzraster, Hz |
| `minimum_spectral_confidence` | 0,35 | kleinster Spektralkontrast |
| `minimum_cluster_windows` | 6 | kleinste Frequenzgruppe, Fenster |
| `minimum_cluster_separation` | 0,4 | kleinster Abstand der Clusterzentren, Hz |
| `gait_clustering_feature` | `frequency` | Merkmal der Gangartgruppen |
| `enabled_movement_gaits` | `WALK,TROT` | laut Protokoll erlaubte Gangarten |
| `minimum_movement_bout_seconds` | 3,0 | kürzester Bewegungsblock, s |
| `gait_order_reset_standing_seconds` | 5,0 | Stillstand bis Reihenfolge-Reset, s |
| `minimum_gait_advance_windows` | 6 | Stabilität einer höheren Gangart |
| `enforce_configured_gait_order` | `true` | protokollierte Reihenfolge beachten |
| `minimum_direction_slope_degps` | 2,0 | technische Angle-Z-Mindeststeigung, `°/s` |
| `direction_trend_window_seconds` | 12,0 | langfristiges Trendfenster, `s` |
| `minimum_direction_agreement_sensors` | 4 | erforderlicher Vierbein-Konsens |
| `direction_change_confirmation_windows` | 2 | stabiler Richtungswechsel, Fenster |
| `positive_angle_z_direction` | `LEFT` | nutzerbestätigte Montagezuordnung für `test01` |
| `maximum_interruption_seconds` | 2,0 | maximale kurze Pause, s |
| `minimum_analyzable_seconds` | 3,0 | Mindestdauer, s |
| `minimum_analyzable_confidence` | 0,55 | Mindestkonfidenz |
| `minimum_stable_windows` | 2 | kürzester Bewegungszustand, Fenster |

Diese Werte sind dokumentierte Prototypentscheidungen. Das Vier-Sekunden-Fenster
und die blockweise Auswertung wurden nach der Fehlanalyse von `test01`
festgelegt; eine unabhängige Aufnahme muss deshalb zeigen, ob sie
übertragbar sind.

## Manuelle Korrektur und Videoprüfung

Eine Korrekturdatei enthält überlappungsfreie Videozeitintervalle, eine
Begründung und optional Gangart, Übergangs-, Wendungs-/Unterbrechungsflag oder manuellen
Ausschluss. Überlappende, nicht endliche oder rückwärts laufende Intervalle
werden abgelehnt; negative Zeiten vor dem Videonullpunkt bleiben für
extrapolierte Randdaten zulässig. Die automatische Unsicherheit bleibt nach einer
Korrektur erhalten.

```sh
dart run tool/segment_gaits.dart \
  --segmentation-config config/gangsegmentierung.v1.json \
  --corrections meine_korrekturen.json \
  --out outputs/test01_gait_segmentation \
  recordings/test01/raw/20260723203422.txt
```

Ohne `--corrections` wird ausschließlich automatisch segmentiert. Erzeugt
werden:

```text
gait_segmentation_report.json
gait_segments.csv
gait_segments_video_timeline.svg
```

CSV und SVG verwenden dieselbe Videozeit wie die affine
Video-IMU-Zeitrekonstruktion. Dadurch lassen sich Grenzen direkt am Video
prüfen. Das Beispiel
`config/gangsegmentierung-korrekturen.beispiel.json` demonstriert das Schema,
wird aber nicht automatisch auf Messdaten angewandt.

## Validierung, Grenzen und nächste Referenz

Automatisierte kontrollierte Tests prüfen:

- Stillstand, Schritt, Trab und optional Galopp mit bekannten Frequenzen,
- Übergänge, kurze Unterbrechungen, Angle-Z-Richtung und Richtungswechsel,
- normales, verrauschtes und unregelmäßig moduliertes Signal,
- kurze Datenlücken und unterschiedliche konfigurierbare Rasterraten,
- Wiederholbarkeit,
- leere/fehlende Eingaben, fehlende Sensoren, NaN/Infinity,
- falsche Zeitreihen, kurze Aufnahmen und ungültige Konfiguration,
- manuelle Korrekturen, Konflikte, Videozeiten und Quellzeilen.

Die kontrollierten Fehlermaße sind Klassenübereinstimmung der stabilen
synthetischen Abschnitte sowie exakte Wiederholbarkeit der JSON-Ausgabe.
Echte Sensitivität, Spezifität, Grenzfehler in Sekunden und
Konfidenzkalibrierung sind mangels unabhängiger Aufnahme noch nicht
bestimmbar.

### Technische Beobachtung für `test01`

Der reproduzierbare reale Lauf mit der nutzerbestätigten Angle-Z-Regel erzeugt
`60` zeitmarkierte Segmente und fünf lange technisch analysierbare
Bewegungsabschnitte. Der Gesamtstatus bleibt `SEGMENTATION_REVIEW_REQUIRED`,
weil die Vorverarbeitung geprüft werden muss und Gangfenster weiterhin
`UNKNOWN` enthalten. Zirkelbewegung wird nicht mehr pauschal als Wendung
ausgeschlossen.

Die aufnahmeinterne Frequenztrennung ergab ein Schritt-Cluster mit Zentrum
`2,33 Hz` und ein Trab-Cluster mit Zentrum `3,66 Hz`. Das sind dominante
Sensorsignal-Frequenzen, keine Schritt- oder Trabreferenzwerte. Die
zusammengefasste automatische Zeitlinie lautet:

- Schritt `20,45–71,95 s`,
- kurzer Stillstand/Übergang,
- Schritt `75,95–129,95 s`,
- Trab `129,95–143,45 s`,
- unsicherer Richtungs-/Übergangsbereich `143,45–161,95 s`,
- Trab `161,95–203,45 s`.

Die Richtungsausgabe stimmt mit der Nutzer-/Videobestätigung überein:

- erster Schrittblock `LEFT`,
- Wechselbereich ungefähr `81,95–84,95 s`,
- zweiter Schrittblock und erster Trabblock `RIGHT`,
- Wechselbereich ungefähr `158,45–160,45 s`,
- zweiter Trabblock `LEFT`.

Vor und nach dem eigentlichen Versuch wurden kurze Klopf-/Handhabungsereignisse
als `UNKNOWN` markiert. Es wurde kein Galopp ausgegeben. Es wurden keine
manuellen Korrekturen angewandt.

Die frühere Datei `lib/services/gait_classifier.dart` im Ausgangs-Commit
klassifizierte bereits erkannte Hufereignisse über Kreisphasen, war aber nicht
an die neue Import-, Zeit- und Vorverarbeitungspipeline angebunden und lieferte
weder Segmentgrenzen, Unsicherheit noch manuelle Korrekturen. Sie wurde daher
nicht wiederhergestellt oder stillschweigend überschrieben.

Bekannte Grenzen:

- Frequenz allein kann Gangarten in Übergängen und bei unregelmäßigem Gang
  verwechseln.
- Die Vorzeichenzuordnung `positiv = LEFT` ist für Montage und Aufnahme
  `test01` nutzerbestätigt, aber noch nicht an einer unabhängigen Aufnahme
  validiert.
- Die Biegungsrate in `°/s` ist keine geometrische Krümmung; dafür fehlen
  belastbare Weg- oder Geschwindigkeitsdaten.
- Die Segmentgrenze ist durch `step_seconds`, Filterauflösung und
  Video-IMU-Synchronisationsfehler begrenzt.
- Galopp ist technisch vorgesehen, aber in der vorhandenen Testaufnahme laut
  Manifest nicht als Referenzgangart dokumentiert.
- Ein laufender Algorithmus ist noch keine fachliche Validierung.

Für den nächsten Versuch wird eine unabhängige, framegenaue Videoannotation
von Stillstand, Gangarten, Übergängen, Wendungen und Unterbrechungen durch eine
fachkundige Person empfohlen. Diese Annotation darf nicht zur gleichzeitigen
Schwellenauswahl und Ergebnisbewertung verwendet werden; Training und Prüfung
müssen getrennt bleiben.
