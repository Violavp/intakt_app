# InTakt-Datenimport

## Scope

Die Pipeline importiert BitMotion-TXT/CSV-Exporte der vier Beinsensoren
`VL`, `VR`, `HL` und `HR`. Der konfigurierte Sattelgurtsensor `SG` wird
zusätzlich akzeptiert, ist für dieses Goal aber optional. Eine gemeinsame
multiplexierte Datei und mehrere Einzelsensordateien werden unterstützt.
Rohdateien werden ausschließlich gelesen.

## Internes Datenmodell und Einheiten

Jede Quellzeile wird genau einem Sensor über seine 12-stellige Hardware-ID
zugeordnet. Quellreihenfolge, Original-Zeitstempel, Quelldatei und Zeilennummer
bleiben erhalten.

| Größe | erkannte Quelleinheiten | interne Einheit | Umrechnung |
|---|---|---|---|
| Beschleunigung X/Y/Z | `g`, `m/s²` | `m/s²` | `1 g = 9,80665 m/s²` |
| Winkelgeschwindigkeit X/Y/Z | `°/s`, `rad/s` | `rad/s` | `°/s × π/180` |
| Magnetfeld X/Y/Z (optional) | `µT`/`uT` | `µT` | keine |
| Orientierungswinkel AngleX/Y/Z (optional) | `°` | `°` | keine; Kreisintervall `[-180, 180]` bleibt erhalten |

Eine Einheit wird nur aus dem Spaltenkopf oder einer expliziten
`unitOverrides`-Angabe übernommen. Unbekannte, gemischte oder nur teilweise
vorhandene Achseinheiten führen zu einem verständlichen Importfehler.
Optionale Winkel müssen entweder als vollständiges
`AngleX/AngleY/AngleZ`-Triplett vorliegen oder bleiben ausdrücklich `null`.

## Zeitstempel und Unsicherheit

Unterstützt werden ISO-8601 sowie numerische Zeitstempel mit im Header
dokumentierten `s`, `ms` oder `us`. Der beobachtete BitMotion-Export enthält
lokale ISO-Zeiten ohne UTC-Offset. Außerdem tragen mehrere aufeinanderfolgende
Messzeilen desselben Sensors denselben Millisekunden-Zeitstempel. Deshalb:

- bleiben Zeilen in Originalreihenfolge,
- werden Zeitstempel weder sortiert noch interpoliert,
- werden Duplikate, Rücksprünge und Empfangslücken gemeldet,
- werden Zeilenrate und Rate eindeutiger Empfangszeitstempel getrennt
  ausgewiesen.

Die genaue Abtastzeit einer einzelnen gebündelten Zeile ist nicht belegt.

## Qualitätsprüfung

Die Qualitätsprüfung ist von Import und späterer Signalverarbeitung getrennt.
Jeder konfigurierte Pflichtsensor und jeder zusätzlich aufgezeichnete Sensor
erhält genau einen Status:

- `USABLE`: keine erkannte technische Auffälligkeit,
- `REVIEW_REQUIRED`: Auffälligkeiten sind lokalisiert; automatische
  Weiterverarbeitung bleibt gesperrt,
- `UNUSABLE`: Pflichtdaten fehlen, die Aufnahme ist zu kurz oder Zeitstempel
  laufen rückwärts.

Der Gesamtbericht ist nur mit ausschließlich `USABLE` bewerteten Sensoren für
die automatische Weiterverarbeitung freigegeben. Er meldet fehlende
Pflichtsensoren, unterschiedliche Zeilenzahlen und Ratenschätzungen,
Zeitstempelprobleme, adaptive Datenlücken, unregelmäßige positive Intervalle,
unerwartet kurze Aufnahmen, unvollständige optionale Magnetometerwerte,
eingefrorene Kanalabschnitte und extreme statistische Ausreißer. Er verändert
oder verwirft keine Werte.

Die Kurzaufnahme-Schwelle (Standard: 2 s) ist eine konfigurierbare technische
QA-Annahme und kein physiologischer Referenzbereich. Eine Datenlücke ist ein
positiver Empfangsabstand größer als das Maximum aus 100 ms und dem Fünffachen
des medianen positiven Empfangsabstands. Berichtete Lücken enthalten beide
Zeitstempel, Quelldateien, Quellzeilen und eine ausdrücklich unsichere Schätzung
fehlender Empfangszeilen.

Ein positives Intervall gilt als unregelmäßig, wenn seine Abweichung vom Median
sowohl 1 ms als auch 20 % überschreitet. Ein Freeze-Kandidat erfordert
standardmäßig mindestens zehn exakt gleiche aufeinanderfolgende Werte eines
Kanals. Extreme Werte werden erst ab acht Werten eines Kanals rein statistisch
außerhalb von `Q1/Q3 ± 3 × IQR` markiert. Diese Schwellen sind konfigurierbare
technische Prüfregeln, keine Sensor-Messgrenzen oder physiologischen
Referenzbereiche. Markierungen enthalten Kanal, Einheit, Wert beziehungsweise
Abschnitt, Zeitstempel und Quellzeilen. Es wird nichts automatisch entfernt
oder ersetzt. `NaN`, `Infinity` und fehlende Pflichtmesswerte werden bereits
beim Import als ungültige Dateiwerte abgelehnt.

## Grafische Plausibilitätsprüfung

Der CLI-Aufruf erzeugt neben dem JSON-Qualitätsbericht eine SVG-Vorschau des
Beschleunigungsbetrags aller erkannten Sensoren. Die X-Achse zeigt bewusst die
Quellreihenfolge und keine erfundene Einzelzeitachse. Die Vorschau ist eine
technische Sichtprüfung, keine Bewegungsanalyse und keine Diagnose.

```sh
dart run tool/import_imu.dart \
  --out outputs/test01_import \
  recordings/test01/raw/20260723203422.txt
```

Ausgaben:

```text
outputs/test01_import/quality_report.json
outputs/test01_import/preview.svg
```

Bei `REVIEW_REQUIRED` oder `UNUSABLE` bleibt der Bericht erhalten und der
Prozess endet mit Statuscode 2. Mit einer Einzelsensordatei ohne
Sensor-ID-Spalte kann die Bibliothek eine explizite Hardware-ID über
`ImuSource.hardwareId` erhalten; der CLI verlangt derzeit eine
Sensor-ID-Spalte.
