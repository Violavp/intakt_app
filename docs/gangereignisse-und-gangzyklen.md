# Gangereignisse und Gangzyklen

## Abgrenzung

Die Stufe liest ausschließlich vorverarbeitete IMU-Werte und vorhandene
Gangartsegmente. Sie verändert weder Rohdaten noch Import, Qualitätsprüfung,
Zeitrekonstruktion, Vorverarbeitung oder Segmentierung. Parameterberechnung,
Scoring und medizinische Interpretation bleiben nachgelagerte, getrennte
Stufen.

## Beobachtung und Signalwahl

- `filtered_gyro_y_radps` (AsY) beschreibt den vorzeichenbehafteten
  Bewegungsverlauf rund um ein Ereignis.
- `filtered_acc_x_mps2` (AccX) ergänzt das Ereignismuster um den
  Beschleunigungsverlauf.
- Rechts montierte Sensoren sind gegenüber links gespiegelt. Für `VR` und `HR`
  werden AsY und AccX deshalb vor der Ereignisregel mit `−1` multipliziert.
- Angle Z liefert ausschließlich die vorgelagerte Reitrichtung. Die
  Ereigniserkennung verwendet weiterhin nur AsY und AccX.
- Auftreten und Abheben werden als getrennte, normalisierte AsY-/AccX-Muster je
  Gangart, Bein und Reitrichtung gelernt. Ein Muster wird nicht auf ein anderes
  Bein oder die Gegenrichtung übertragen.

## Ereignisregel

1. Um jeden bestätigten Zeitpunkt wird ein Fenster von
   `pattern_half_window_seconds` vor und nach dem Ereignis ausgeschnitten.
2. Signiertes AsY und AccX werden innerhalb des Fensters jeweils zentriert und
   skaliert. Dadurch beschreibt das Muster den Kurvenverlauf statt die absolute
   Amplitude.
3. Auftret- und Abhebebeispiele werden getrennt gemittelt. Mindestens
   `minimum_pattern_examples_per_kind` Beispiele sind erforderlich.
4. Die vollständigen Gangsegmente werden mit beiden Mustern verglichen.
   Lokale Maxima ab `minimum_pattern_correlation` werden Kandidaten.
5. Auftretkandidaten werden anhand der bestätigten Medianzyklusdauer getrennt.
   Zwischen zwei Auftreten wird der passendste Abhebekandidat nahe der
   bestätigten Medianstanddauer gewählt.
6. Fehlt ein passendes Richtungsmuster, bleibt nur die bisherige
   AsY-Hystereseregel als `UNCALIBRATED_DEFAULT`; ihre Qualität wird reduziert
   und sie bleibt prüfpflichtig.
7. Nutzerkorrekturen ersetzen den nächstgelegenen automatischen Kandidaten
   unabhängig von dessen vorheriger Ereignisbezeichnung oder werden
   rückverfolgbar ergänzt.

Die Bezeichnungen Auftreten und Abheben sind durch die Nutzerin in mehreren
Signalblöcken bestätigt. Sie bleiben eine Signalinterpretation und sind nicht
gegen eine Kraftplatte validiert.

## Zyklus und Qualität

Ein Zyklus beginnt mit Auftreten eines Beins und endet mit dessen nächstem
Auftreten:

`Zyklusdauer = Ende − Start`

`Standzeit = Abheben − Start`

`Schwungzeit = Ende − Abheben`

Der technische Qualitätswert `[0, 1]` kombiniert Musterähnlichkeit,
Übereinstimmung der bestätigten Mustervorlagen und Rasterabdeckung. Für
unkalibrierte Bereiche wird der konfigurierte Reduktionsfaktor angewandt. Er
ist bewusst unabhängig von der
Dauerregelmäßigkeit, weil diese erst in der nachgelagerten Taktstufe gemessen
wird. Andernfalls würden unregelmäßige Zyklen vor der Variabilitätsberechnung
ausgesiebt. Der Qualitätswert ist kein medizinischer Score. Unplausible Zyklen
werden nicht gelöscht, sondern mit Ausschlussgründen ausgegeben:

- Zyklusdauer außerhalb der Aufnahmekalibrierung,
- unvollständige Rasterabdeckung,
- ungültige Ereignisfolge,
- Überschreitung einer Gangart- oder Richtungsgrenze,
- Qualitätswert unter Mindestwert.

## Ausgaben

- `gait_cycle_report.json`: Annahmen, Konfiguration, Ereignisse, Zyklen,
  Unsicherheiten und Issues.
- `gait_events.csv`: alle automatischen und nutzerkorrigierten Ereignisse.
- `gait_cycles.csv`: Start, Abheben, Ende, Stand-/Schwungzeit, Qualität und
  Ausschlussgründe sowie Ereignis-IDs und fortgepflanzte Zeitunsicherheiten.
- `gait_cycle_review.svg`: AsY-/AccX-Verlauf, Ereignisse und farblich
  gekennzeichnete Zyklen.

Die nachgelagerte, getrennte Parameterstufe erzeugt zusätzlich
`takt_parameter_report.json`, `takt_windows.csv` und `takt_trend.svg`.
Definitionen stehen in `docs/taktparameter.md`.

## Unsicherheit und Validierung

Die aktuelle Aufnahme besitzt eine technisch synchronisierte Videozeit, deren
Synchronisationsbericht `REVIEW_REQUIRED` ist. Die Nutzerkorrekturen stammen
aus der grafischen Signalkontrolle. `IMG_4011.MOV` ist ausdrücklich
ausgeschlossen; `IMG_4012.MOV` ist die einzige gültige Videoreferenz. Das
Erfolgskriterium „mit mehreren Videos verglichen“ ist deshalb mit dem
vorhandenen Bestand noch nicht erfüllt. Eine zweite unabhängige Aufnahme muss
mit demselben Protokoll annotiert werden.
