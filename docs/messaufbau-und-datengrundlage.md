# InTakt – kurze Anleitung für die Testaufnahme

Status: **bereit für die Feldaufnahme**  
Konfiguration: `INTAKT-IMU-5S-V2`  
Sensoren: vier Beine plus ein Sensor am Sattelgurt  
Bandbreite: **44 Hz**

## Sensoren anbringen

| Kürzel | Position | Hardware-ID |
|---|---|---|
| `VL` | linkes vorderes Röhrbein, außen | `1B9D88FD0E8C` |
| `VR` | rechtes vorderes Röhrbein, außen | `83FEC4707D1D` |
| `HL` | linkes hinteres Röhrbein, außen | `1792A254366C` |
| `HR` | rechtes hinteres Röhrbein, außen | `657910C7ECB7` |
| `SG` | mittig am Sattelgurt | `C5C720831275`* |

\* In Test 1 zunächst durch Ausschluss erkannt und anschließend mit dem
App-Screenshot `Ausrichtung Achsen.PNG` direkt bestätigt. Der Screenshot zeigt
für `C5C720831275` in der dokumentierten Ruhelage `AccX = 0,011 g`,
`AccY = -0,009 g` und `AccZ = 0,873 g`; Z trägt damit nahezu vollständig die
statische Schwerkraftkomponente.

Für `HL` bestätigt `Ausrichtung Achsen HL.png` die ID `1792A254366C` und
ebenfalls die Z-Ruhelage (`AccX = 0,000 g`, `AccY = 0,046 g`,
`AccZ = 0,996 g`).

### Achsen und Spiegelung

- Die Sensorachsen von `VL`, `VR`, `HL` und `HR` sind laut bestätigtem
  Messaufbau gleich wie bei `HL`.
- `+Z` zeigt in der dokumentierten Ruhelage nach oben.
- Linke und rechte Pferdeseite sind **spiegelbildlich montiert**.
- Die TXT-Rohachsen werden unverändert als lokale Sensorachsen importiert.
- Vor einem Links-rechts-Vergleich muss die horizontale Vorzeichenabbildung
  durch eine gezielte Richtungsbewegung kalibriert werden. Bis dahin wird
  keine X- oder Y-Achse automatisch gespiegelt.
- Ein Foto von jedem befestigten Sensor machen.

Beim Sattelgurtsensor zusätzlich fotografieren, auf welcher Gurtseite er sitzt
und wohin Stecker, Beschriftung oder Pfeile zeigen. Falls „mittig am
Sattelgurt“ nicht der echten Position entspricht, die tatsächliche Position im
Manifest eintragen.

## Aufnahme – nur diese Schritte

- [ ] In der App alle fünf Sensoren prüfen.
- [ ] Bandbreite bei allen Sensoren auf **44 Hz** prüfen.
- [ ] Handyvideo im Querformat starten; Pferd vollständig von der Seite filmen.
- [ ] Sensoraufnahme starten.
- [ ] Für die Synchronisation dreimal deutlich auf den Sattelgurtsensor tippen.
- [ ] 10 Sekunden ruhig stehen.
- [ ] Im Schritt gerade hin und zurück.
- [ ] Im Trab gerade hin und zurück, sofern sicher.
- [ ] 10 Sekunden ruhig stehen.
- [ ] Sensoraufnahme stoppen, danach Video stoppen.
- [ ] Alle Originaldateien und das Originalvideo unverändert sichern.

## Dateien über das Dashboard ablegen

Im Dashboard unter **Testversuche** einmal den Ordner
`/Users/violavanparidon/intakt_app/recordings` auswählen. Danach Aufnahme-ID
eintragen, die gemeinsame TXT-Datei auswählen und speichern. Das Dashboard
erzeugt automatisch:

```text
recordings/20260723_test01/
  raw/       ← unveränderte App-Dateien
  video/     ← unverändertes Handyvideo
  fotos/     ← fünf Sensorfotos
  manifest.json
```

Vorhandene Aufnahmeordner werden nicht überschrieben. Die direkte
Ordnerablage funktioniert mit Chrome oder Edge; der Browser verlangt dafür
deine ausdrückliche Freigabe.

## Was anschließend geprüft wird

Nach der Aufnahme werden aus den Originaldateien geprüft:

- tatsächliche Abtastrate und Zeitstempel,
- Spaltennamen, Einheiten und Exportformat,
- Vollständigkeit aller fünf Sensoren,
- zeitliche Zuordnung zum Video.

Die Herstellerunterlagen nennen Beschleunigung in `g`, Drehrate in `°/s` und
Winkel in `°`. Diese Angaben werden erst am echten Export bestätigt. Die
Unterlagen nennen außerdem `.txt` und `.wplay`; die konkrete App-Version und
Dateistruktur bleiben bis zum Originalexport offen.

## Abschlussstatus

Test 1 enthält die gemeinsame TXT-Datei mit fünf Sensoren, ein zeitlich
passendes Video sowie fünf Positionsfotos. Die Achsen der vier Beinsensoren
sind wie bei `HL` bestätigt; links und rechts sind spiegelbildlich montiert.
Abschlussstatus: **ABGENOMMEN MIT EINSCHRÄNKUNGEN**, weil die genaue
horizontale Vorzeichenabbildung für spätere Links-rechts-Berechnungen noch
nicht durch eine gezielte Richtungsbewegung kalibriert wurde. Der
Datenqualitätsbericht liegt unter
`outputs/test01_import_qa/quality_report.json`.
