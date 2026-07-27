# InTakt

InTakt ist ein Prototyp zur sensorbasierten Bewegungs- und Ganganalyse beim
Pferd.

## IMU-Datenimport

Die Importpipeline liest die vier konfigurierten Beinsensoren aus gemeinsamen
BitMotion-Exporten oder getrennten Dateien, ordnet Hardware-IDs eindeutig zu,
vereinheitlicht dokumentierte Einheiten und bewertet die technische
Datenqualität. Ein optionaler Sattelgurtsensor und Magnetometerkanäle werden
berücksichtigt. Rohdateien werden nicht verändert.

Beispiel:

```sh
dart run tool/import_imu.dart \
  --out outputs/test01_import \
  recordings/test01/raw/20260723203422.txt
```

Der Aufruf erzeugt einen JSON-Qualitätsbericht und eine SVG-Vorschau. Details,
Annahmen, Einheiten und Unsicherheiten stehen in
[`docs/datenimport.md`](docs/datenimport.md).

## IMU-Zeitsynchronisation

Vier technisch geeignete Sensorströme können signalbasiert auf ein gemeinsames
UTC-Raster synchronisiert werden. Offset, lineare Clock-Drift,
Synchronisationsfehler, Unsicherheit und Rasterabdeckung werden pro Sensor
dokumentiert; CSV und SVG bleiben bis zu den ursprünglichen Quellzeilen
rückverfolgbar.

```sh
dart run tool/synchronize_imu.dart \
  --rate 100 \
  --out outputs/test01_synchronization \
  recordings/test01/raw/20260723203422.txt
```

Definition, Formeln, Ausschlusskriterien und bekannte Validierungsgrenzen stehen
in [`docs/zeitsynchronisation.md`](docs/zeitsynchronisation.md).

## IMU-Signalvorverarbeitung

Das rekonstruierte gemeinsame Raster kann reproduzierbar ausreißerbereinigt,
nullphasig tiefpassgefiltert, an der Schwerkraftrichtung ausgerichtet und in
Gravitations- und Bewegungsanteile getrennt werden. Rohwerte und Quellzeilen
bleiben in allen Vergleichsausgaben erhalten.

```sh
dart run tool/preprocess_imu.dart \
  --preprocessing-config config/vorverarbeitung.v1.json \
  --out outputs/test01_preprocessing \
  recordings/test01/raw/20260723203422.txt
```

Filtervergleich, Formeln, Konfiguration, Einheiten und bekannte
Orientierungsgrenzen stehen in
[`docs/signalvorverarbeitung.md`](docs/signalvorverarbeitung.md).

## Gangart und Analyseabschnitte

Das vorverarbeitete gemeinsame Raster kann in Stillstand, Schritt, Trab,
optional Galopp und unsichere Bewegung segmentiert werden. Übergänge,
Wendungskandidaten und Unterbrechungen bleiben sichtbar, werden aber von der
weiteren Analyse ausgeschlossen. Jede Grenze ist auf Videozeit und
Rohdaten-Quellzeilen rückverfolgbar; begründete manuelle Korrekturen sind
optional.

```sh
dart run tool/segment_gaits.dart \
  --segmentation-config config/gangsegmentierung.v1.json \
  --out outputs/test01_gait_segmentation \
  recordings/test01/raw/20260723203422.txt
```

Definition, Formeln, Unsicherheit, Korrekturschema und Validierungsgrenzen
stehen in
[`docs/gangart-und-analyseabschnitte.md`](docs/gangart-und-analyseabschnitte.md).

## Gangereignisse und Gangzyklen

Auf Schritt- und Trabsegmenten werden pro Bein getrennte Auftret- und
Abhebemuster aus signiertem AsY und AccX erkannt. Die Muster werden aus
nutzerbestätigten Ereignissen getrennt nach Gangart, Bein und Reitrichtung
gelernt; unkalibrierte Bereiche bleiben ausdrücklich prüfpflichtig. Die
gespiegelte Montage der rechten Sensoren wird vor der Ereigniserkennung
kanonisiert. Jeder Zyklus
besitzt Auftreten, Abheben, Ende, Stand- und Schwungzeit, technischen
Qualitätswert und nachvollziehbare Ausschlussgründe.

```sh
dart run tool/detect_gait_cycles.dart \
  --cycle-config config/gangzyklen.v1.json \
  --takt-config config/taktparameter.v1.json \
  --event-corrections config/gangereignisse-test01-nutzerbestaetigt.json \
  --out outputs/test01_gait_cycles \
  recordings/test01/raw/20260723203422.txt
```

Der Aufruf erzeugt Ereignis- und Zyklusberichte sowie getrennte
adaptive 10–20-Sekunden-Taktfenster mit Unsicherheiten, Verlaufsvergleich und
Erklärungscodes. Definitionen und Validierungsgrenzen stehen in
[`docs/gangereignisse-und-gangzyklen.md`](docs/gangereignisse-und-gangzyklen.md)
und [`docs/taktparameter.md`](docs/taktparameter.md).

## Parameterkatalog

Alle Parameter der Analysekette mit Definition, Einheit und konfiguriertem Wert
stehen gesammelt in [`docs/parameterkatalog.md`](docs/parameterkatalog.md).

## Prüfungen

```sh
dart format --output=none --set-exit-if-changed lib/imu_import lib/imu_sync lib/imu_preprocessing lib/gait_segmentation lib/gait_cycles lib/takt_parameters tool test
flutter analyze
flutter test
node --test test/messkonfiguration_test.mjs
flutter build macos --debug
```
