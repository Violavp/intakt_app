# InTakt – Parameterkatalog

Sammelstelle aller Parameter der Analysekette mit Definition und Einheit.
Maßgeblich ist der Code; dieses Dokument ist der Index, die Stufendokumente
enthalten Herleitung und Validierungsgrenzen.

Stand: 25.07.2026 · Import bis zeitliche Taktparameter.
Noch nicht enthalten, weil noch nicht implementiert: validiertes Scoring und
fachliche beziehungsweise medizinische Interpretation.

## 0 Konventionen

| Festlegung | Wert |
|---|---|
| interne Einheiten | Beschleunigung `m/s²`, Winkelgeschwindigkeit `rad/s`, Gerätewinkel `°`, Magnetfeld `µT`, Zeit `s`, Frequenz `Hz` |
| Umrechnung beim Import | `1 g = 9,80665 m/s²`, `1 °/s = π/180 rad/s`, `µT` unverändert |
| Sensorkürzel | `VL`, `VR`, `HL`, `HR` (Röhrbein, Pflicht), `SG` (Sattelgurt, optional) |
| Achsen | rechtshändig, `+Z` = oben in dokumentierter Ruhelage; links/rechts gespiegelt montiert |
| Konfidenz / Unsicherheit | dimensionslos in `[0, 1]`, `uncertainty = 1 − confidence`, technisch – keine klinische Wahrscheinlichkeit |
| Rückverfolgbarkeit | jeder abgeleitete Wert führt `source_name` + `source_line` der Rohzeile(n) mit |

## 1 Messgrößen (Rohkanäle)

| Parameter | Definition | Einheit |
|---|---|---|
| `acc_x/y/z_mps2` | Beschleunigung im Sensorrahmen, inkl. Schwerkraft | `m/s²` |
| `gyro_x/y/z_radps` | Winkelgeschwindigkeit im Sensorrahmen | `rad/s` |
| `mag_x/y/z_uT` | Magnetflussdichte, optional | `µT` |
| `angle_x/y/z_deg` | Geräteorientierungswinkel, optional; Kreisintervall der Quelle bleibt erhalten | `°` |
| `raw_timestamp` | unveränderter Zeitstempeltext der Quellzeile | – |
| `source_name` / `source_line` | Quelldatei und 1-basierte Zeilennummer | – |

## 2 Zeitbasen

| Parameter | Definition | Einheit |
|---|---|---|
| `reception_timestamp` | BLE-/App-Empfangszeitstempel; je BLE-Paket für alle enthaltenen Samples identisch | UTC |
| `sample_index` | nullbasierter fortlaufender Index je Sensor | – |
| `packet_index` | nullbasierter Index des BLE-Empfangspakets | – |
| `index_time_s` | `sample_index / nominal_sampling_rate_hz` | `s` |
| `analysis_time_s` | rekonstruierte gemeinsame Analysezeit, `offset_s + time_gradient · index_time_s` | `s` |
| `video_time_s` | Zeit auf der Videoachse; identisch mit `analysis_time_s` (Anker definieren den Nullpunkt) | `s` |
| `time_basis` | Kennzeichnung `RECONSTRUCTED_INDEX_TIME` bzw. UTC-Raster | – |

## 3 Import und Qualitätsprüfung

Metriken je Sensor (`quality_report.json`):

| Parameter | Definition | Einheit |
|---|---|---|
| `rows` | importierte Zeilen | – |
| `unique_timestamps` | verschiedene Zeitstempelwerte | – |
| `duplicate_timestamp_rows` | Zeilen mit bereits vorher gesehenem Zeitstempel | – |
| `backward_timestamp_rows` | Zeilen mit rückwärts laufendem Zeitstempel | – |
| `duration_s` | letzter minus erster Zeitstempel | `s` |
| `row_rate_hz` | `rows / duration_s` | `Hz` |
| `unique_timestamp_rate_hz` | `unique_timestamps / duration_s` | `Hz` |
| `median_positive_interval_ms` | Median aller positiven Zeitstempeldifferenzen | `ms` |
| `max_positive_interval_ms` | größte positive Zeitstempeldifferenz | `ms` |
| `adaptive_gap_threshold_ms` | `max(100; 5 × median_positive_interval_ms)` | `ms` |
| `gaps_over_adaptive_threshold` | Anzahl Intervalle über dieser Schwelle | – |
| `estimated_missing_rows` | aus Lückenlänge und Medianintervall geschätzt | – |
| `irregular_interval_locations` | Intervalle, die Median um **beide** Toleranzen überschreiten | – |
| `magnetometer_rows` | Zeilen mit gültigem Magnetfeld | – |
| `constant_channels` / `frozen_segments` | Kanäle bzw. Läufe exakt gleicher Folgewerte | – |
| `extreme_outliers` | Werte außerhalb `Q1 − 3·IQR` … `Q3 + 3·IQR` | Kanaleinheit |
| `quality_status` | technischer Sensorstatus | – |
| `ready_for_further_analysis` | alle Pflichtsensoren technisch geeignet | bool |

Schwellen (`ImuQualityAnalyzer`, technisch, nicht physiologisch):

| Parameter | Wert | Einheit |
|---|---|---|
| `unexpectedlyShortDuration` | 2 | `s` |
| `irregularIntervalRelativeTolerance` | 0,2 | – |
| `irregularIntervalAbsoluteTolerance` | 1 | `ms` |
| `frozenRunMinSamples` | 10 | Samples |
| `extremeOutlierIqrMultiplier` | 3 | IQR |
| `extremeOutlierMinSamples` | 8 | Samples |

## 4 Zeitsynchronisation (signalbasiert, UTC-Raster)

| Parameter | Definition | Einheit |
|---|---|---|
| `reference_sensor` | Sensor, auf dessen Zeitachse ausgerichtet wird | – |
| `grid_sampling_rate_hz` / `grid_period_us` | Rasterrate bzw. Rasterperiode | `Hz` / `µs` |
| `raw_start_offset_ms` | Startzeitdifferenz zum Referenzsensor vor Korrektur | `ms` |
| `estimated_signal_offset_ms` | konstanter Versatz aus Kreuzkorrelation | `ms` |
| `estimated_drift_ppm` | linearer Gang der Sensoruhr | `ppm` |
| `lag_ms` | Versatz eines Korrelationsfensters | `ms` |
| `window_center_s` | Mittenzeit des Korrelationsfensters | `s` |
| `correlation` / `mean_window_correlation` | Pearson-Korrelation im Fenster bzw. deren Mittel, `[−1, 1]` | – |
| `paired_samples` | Wertepaare im Fenster | – |
| `lag_residual_rmse_ms` | RMS-Abweichung der Fensterversätze vom Fit | `ms` |
| `maximum_absolute_lag_residual_ms` | größter Betrag dieser Abweichung | `ms` |
| `source_sampling_rate_hz` | tatsächliche Quellrate des Sensors | `Hz` |
| `output_coverage` | Anteil belegter Rasterpunkte, `[0, 1]` | – |
| `uncertainty_ms` | kombinierte Zeitunsicherheit je Sensor | `ms` |

## 5 Indexzeit-Rekonstruktion

| Parameter | Definition | Einheit |
|---|---|---|
| `nominal_sampling_rate_hz` | konfigurierte Sollrate | `Hz` |
| `effective_sampling_rate_hz` | aus Samplezahl und rekonstruierter Dauer | `Hz` |
| `offset_s` | Achsenabschnitt der Anpassung Indexzeit → Analysezeit | `s` |
| `time_gradient` | Steigung derselben Anpassung; 1 = keine Skalierung | – (`s/s`) |
| `estimated_drift_ppm` | `(time_gradient − 1) × 10⁶` | `ppm` |
| `fitted_analysis_time_s` | angepasste Analysezeit des Samples | `s` |
| `fit_residual_ms` | Abweichung Anker ↔ Fit | `ms` |
| `anchor_residual_rmse_ms` | RMS dieser Abweichungen | `ms` |
| `maximum_absolute_anchor_residual_ms` | größter Betrag davon | `ms` |
| `base_uncertainty_ms` | Grundunsicherheit der rekonstruierten Zeitachse | `ms` |
| `sample_uncertainty_ms` | Unsicherheit je Sample (`minimum`/`maximum`) | `ms` |
| `packet_count` | Anzahl BLE-Empfangspakete | – |
| `duplicate_reception_timestamp_samples` | Samples, die sich einen Empfangszeitstempel teilen | – |
| `reception_gap_ms` | Empfangslücke zwischen zwei Paketen | `ms` |
| `expected_covered_ms` | bei Sollrate erwartete Abdeckung dieser Lücke | `ms` |
| `possible_missing_samples` | rechnerisch fehlende Samples; `SUSPECTED_NOT_PROVEN` | – |
| `loss_determination` / `loss_reason` | Aussagekraft der Verlusteinschätzung und Begründung | – |
| Anker: `video_time_s`, `uncertainty_ms`, `assignment` | Videozeit, Ankerunsicherheit, Zuordnungsbegründung | `s` / `ms` / – |

## 6 Signalvorverarbeitung

Signalstufen je Rasterpunkt (jeweils `x/y/z`):

| Parameter | Definition | Einheit |
|---|---|---|
| `raw_acc_*` / `raw_gyro_*` | unveränderter rekonstruierter Wert | `m/s²` / `rad/s` |
| `cleaned_*` | nach Hampel-Ausreißerersetzung | wie oben |
| `filtered_*` | nullphasig tiefpassgefiltert, Sensorrahmen | wie oben |
| `aligned_*` | in den Schwerkraftrahmen gedreht (nur Vertikale gelöst) | wie oben |
| `gravity_*` | geschätzter Gravitationsanteil | `m/s²` |
| `movement_*` | `aligned_acc − gravity` | `m/s²` |
| `outlier_replaced` | Rasterpunkt wurde ersetzt | bool |
| `processing_temporal_resolution_ms` | halbe Periode der Grenzfrequenz; **kein** Zeitstempelfehler | `ms` |

Konfiguration `config/vorverarbeitung.v1.json`:

| Parameter | Definition | Wert | Einheit |
|---|---|---|---|
| `low_pass_cutoff_hz` | Grenzfrequenz Nutzsignal | 20,0 | `Hz` |
| `gravity_cutoff_hz` | Grenzfrequenz Gravitationsschätzung | 0,5 | `Hz` |
| `butterworth_order` | Ordnung je Durchlaufrichtung (nur 4 implementiert) | 4 | – |
| `hampel_half_window_samples` | halbe Fensterbreite des Hampel-Filters | 3 | Samples |
| `hampel_threshold_mad` | Ausreißerschwelle in MAD | 4,0 | MAD |
| `maximum_outlier_run_samples` | längere Läufe gelten als echtes Ereignis | 1 | Samples |
| `minimum_acceleration_mad_mps2` | MAD-Untergrenze Beschleunigung | 0,02 | `m/s²` |
| `minimum_angular_velocity_mad_radps` | MAD-Untergrenze Drehrate | 0,002 | `rad/s` |
| `minimum_segment_samples` | kürzere Segmente werden nicht verarbeitet | 20 | Samples |
| `orientation_window_seconds` | Ruhefenster zur Lagebestimmung | 2,0 | `s` |
| `orientation_maximum_gyro_rms_radps` | Ruhekriterium Drehrate | 0,15 | `rad/s` |
| `orientation_maximum_gravity_deviation_mps2` | zulässige Abweichung vom Normwert | 1,5 | `m/s²` |
| `standard_gravity_mps2` | Normfallbeschleunigung | 9,80665 | `m/s²` |
| `comparison_moving_average_window_samples` | Fenster des Vergleichsfilters | 5 | Samples |
| `minimum_event_peak_retention` | geforderter Peak-Erhalt | 0,75 | – |

Kennzahlen je Sensor:

| Parameter | Definition | Einheit |
|---|---|---|
| `input_samples` / `output_samples` / `gap_samples` | Rasterpunkte ein, aus, fehlend | – |
| `replaced_outlier_samples` | ersetzte Ausreißer | – |
| `retained_candidate_outlier_samples` | erkannt, aber als Ereignis behalten | – |
| `quality_score` | `Abdeckung × Orientierungskonfidenz`, `[0, 1]`, rein technisch | – |
| `window_start_s` / `window_end_s` | genutztes Ruhefenster | `s` |
| `gravity_magnitude_mps2` | Betrag der gemessenen Schwerkraft im Ruhefenster | `m/s²` |
| `gravity_residual_mps2` | Abweichung zu `standard_gravity_mps2` | `m/s²` |
| `gyro_rms_radps` | RMS der Drehrate im Ruhefenster | `rad/s` |
| `rotation_sensor_to_gravity_frame` | zeilenweise 3×3-Rotation; Gierwinkel bleibt ungelöst | – |
| `roughness_rms_mps2` | RMS der zweiten Differenz des gefilterten Signals | `m/s²` |
| `peak_to_peak_retention` | Spitze-Tal gefiltert / roh | – |
| `strongest_event_time_shift_ms` | Zeitversatz des stärksten Ereignisses durch Filterung | `ms` |

## 7 Gangart und Analyseabschnitte

Konfiguration `config/gangsegmentierung.v1.json`:

| Parameter | Definition | Wert | Einheit |
|---|---|---|---|
| `window_seconds` | Analysefensterlänge | 4,0 | `s` |
| `step_seconds` | Fensterversatz | 0,5 | `s` |
| `minimum_window_coverage` | geforderte Belegung je Fenster | 0,9 | – |
| `movement_on_rms_mps2` | Einschaltschwelle Bewegung (Hysterese) | 0,45 | `m/s²` |
| `movement_off_rms_mps2` | Ausschaltschwelle Bewegung | 0,30 | `m/s²` |
| `minimum_frequency_hz` / `maximum_frequency_hz` | Suchband der Schrittfrequenz | 0,5 / 4,5 | `Hz` |
| `frequency_resolution_hz` | Rasterweite der Spektralsuche | 0,05 | `Hz` |
| `minimum_spectral_confidence` | Mindestkontrast des Spektralpeaks | 0,35 | – |
| `minimum_cluster_windows` | Fenster je Gangart-Cluster | 6 | – |
| `minimum_cluster_separation` | geforderter Clusterabstand | 0,4 | Merkmalseinheit |
| `gait_clustering_feature` | Clustermerkmal (`frequency` \| `diagonal_synchrony`) | `frequency` | – |
| `enabled_movement_gaits` | zugelassene Bewegungsgangarten | `WALK`, `TROT` | – |
| `minimum_movement_bout_seconds` | Mindestdauer einer Bewegungsphase | 3,0 | `s` |
| `gait_order_reset_standing_seconds` | Stillstand, der die Gangartfolge zurücksetzt | 5,0 | `s` |
| `minimum_gait_advance_windows` | Fenster vor einem Gangartwechsel | 6 | – |
| `enforce_configured_gait_order` | erwartete Reihenfolge erzwingen | true | bool |
| `minimum_direction_slope_degps` | kleinster Betrag eines langfristigen Angle-Z-Trends je zustimmendem Bein | 2,0 | `°/s` |
| `direction_trend_window_seconds` | vom Frequenzfenster getrenntes Angle-Z-Trendfenster | 12,0 | `s` |
| `minimum_direction_agreement_sensors` | gleichgerichtete Beinsensoren für eine gültige Richtung | 4 | Sensoren |
| `direction_change_confirmation_windows` | Mindestfolge stabiler Richtungsfenster | 2 | Fenster |
| `positive_angle_z_direction` | nutzerbestätigte Vorzeichenzuordnung für die Montage von `test01` | `LEFT` | – |
| `maximum_interruption_seconds` | überbrückbare Unterbrechung | 2,0 | `s` |
| `minimum_analyzable_seconds` | Mindestdauer für `analyzable` | 3,0 | `s` |
| `minimum_analyzable_confidence` | Mindestkonfidenz für `analyzable` | 0,55 | – |
| `minimum_stable_windows` | stabile Fenster je Segment | 2 | – |
| `required_leg_labels` | Pflichtsensoren | `VL VR HL HR` | – |

Größen je Segment (`gait_segments.csv`):

| Parameter | Definition | Einheit |
|---|---|---|
| `start_s` / `end_s` / `duration_s` | Segmentgrenzen und Dauer auf der Analysezeitachse | `s` |
| `video_start_s` / `video_end_s` | identische Grenzen auf der Videoachse | `s` |
| `gait` | `STANDING`, `WALK`, `TROT`, `GALLOP`, `UNKNOWN` | – |
| `confidence` | Mittel der Fensterkonfidenzen; Fenster: `coverage × Spektral- bzw. Aktivitätskonfidenz` | – |
| `uncertainty` | `1 − confidence` | – |
| `dominant_leg_frequency_hz` | Frequenz maximaler Leistung der vertikalen Bewegungsbeschleunigung aller Beine im Suchband | `Hz` |
| `diagonal_synchrony` | Mittel der Pearson-Korrelationen `VL↔HR` und `VR↔HL` der vertikalen Bewegungsbeschleunigung, `[−1, 1]` | – |
| `movement_rms_mps2` | Mittel über die Beinsensoren des RMS des Betrags der Bewegungsbeschleunigung | `m/s²` |
| `coverage` | kleinster Belegungsanteil der Beinsensoren, `[0, 1]` | – |
| `riding_direction` | `LEFT` bei gemeinsam positivem, `RIGHT` bei gemeinsam negativem langfristigem Angle-Z-Trend, sonst `UNKNOWN` | – |
| `direction_valid` / `direction_invalid_reason` | gültig nur bei Vierbein-Konsens; sonst expliziter Ausschlussgrund und keine aggregierte Biegungsrate | bool / Text |
| `front_angle_z_trend_degps` | Mittel der entfalteten Angle-Z-Steigungen von `VL`, `VR` | `°/s` |
| `hind_angle_z_trend_degps` | Mittel der entfalteten Angle-Z-Steigungen von `HL`, `HR` | `°/s` |
| `mean_angle_z_trend_degps` / `line_bending_rate_degps` | Mittel der zustimmenden vier Beinsteigungen; signierte Richtungs-/Biegungsrate, keine geometrische Krümmung | `°/s` |
| `direction_confidence` | Anteil der vier Pflichtsensoren, die das ausgegebene Trendvorzeichen stützen | `[0,1]` |
| `transition` | Übergang zwischen Gangarten | bool |
| `turn_candidate` | nachhaltiger Wechsel `LEFT↔RIGHT`; Randfenster bleiben ausgeschlossen | bool |
| `interruption` | kurze Unterbrechung | bool |
| `analyzable` | erfüllt alle technischen Bedingungen für die Weiterverarbeitung | bool |
| `manually_corrected` / `correction_reasons` | begründete manuelle Korrektur | bool / Text |
| `source_lines` | erste und letzte Rohzeile je Sensor | – |
| `centroid` (Cluster) | Clusterschwerpunkt im gewählten Merkmal | `Hz` bzw. Korrelation |

Spektralkonfidenz eines Fensters: `(P_peak − P_hintergrund) / (P_peak + P_hintergrund)`,
begrenzt auf `[0, 1]`. Aktivitätskonfidenz bei Stillstand ist der auf `[0, 1]`
begrenzte Abstand zur Ausschaltschwelle.

## 8 Gangereignisse und Gangzyklen

Konfiguration `config/gangzyklen.v1.json`:

| Parameter | Definition | Wert | Einheit |
|---|---|---|---|
| `smoothing_seconds` | Glättungsfenster der absoluten AsY-Aktivität | 0,05 | `s` |
| `minimum_phase_seconds` | Mindestdauer eines Ruhe-/Bewegungszustands | 0,12 | `s` |
| `refinement_seconds` | Suchradius um einen Zustandsübergang | 0,10 | `s` |
| `walk_minimum_cycle_seconds` / `walk_maximum_cycle_seconds` | Aufnahmekalibrierung Schritt | 0,90 / 1,60 | `s` |
| `trot_minimum_cycle_seconds` / `trot_maximum_cycle_seconds` | Aufnahmekalibrierung Trab | 0,55 / 1,10 | `s` |
| `minimum_coverage` | minimale Rasterabdeckung eines Zyklus | 0,90 | – |
| `minimum_cycle_quality` | technischer Mindestqualitätswert | 0,55 | – |
| `manual_match_tolerance_seconds` | Zuordnungsradius einer Nutzerkorrektur | 0,20 | `s` |
| `pattern_half_window_seconds` | Zeit vor und nach einem bestätigten Ereignis im AsY-/AccX-Muster | 0,12 | `s` |
| `minimum_pattern_examples_per_kind` | kleinste Beispielanzahl jeweils für Auftreten und Abheben | 2 | Ereignisse |
| `minimum_pattern_correlation` | kleinste normierte Ähnlichkeit eines automatischen Kandidaten mit dem Ereignismuster | 0,45 | Korrelation |
| `same_event_spacing_fraction` | Mindestabstand gleichartiger Kandidaten relativ zur bestätigten Medianzyklusdauer | 0,65 | Anteil |
| `phase_search_tolerance_fraction` | Suchabweichung für Abheben relativ zur bestätigten Medianstanddauer | 0,45 | Anteil |
| `uncalibrated_quality_factor` | Qualitätsfaktor für die Schwellenregel ohne passendes Ereignismuster | 0,65 | Faktor |
| `required_leg_labels` | Pflichtsensoren | `VL VR HL HR` | – |

Größen je Zyklus:

| Parameter | Definition | Einheit |
|---|---|---|
| `start_s` / `end_s` | aufeinanderfolgende Auftret-Ereignisse desselben Beins | `s` |
| `liftoff_s` | Abheben zwischen Start und Ende | `s` |
| `duration_s` | `end_s − start_s` | `s` |
| `stance_s` | `liftoff_s − start_s` | `s` |
| `swing_s` | `end_s − liftoff_s` | `s` |
| `start_event_id` / `liftoff_event_id` / `end_event_id` | Verweise auf die drei auslösenden Signalereignisse | – |
| `duration_uncertainty_ms` | `sqrt(u_start² + u_end²)` | `ms` |
| `stance_uncertainty_ms` | `sqrt(u_start² + u_liftoff²)` | `ms` |
| `swing_uncertainty_ms` | `sqrt(u_liftoff² + u_end²)` | `ms` |
| `duration_deviation_fraction` | Betrag der Abweichung von der aufnahmeinternen Median-Zyklusdauer, nur Beobachtung und kein Ausschluss | Anteil |
| `quality` | mittlerer Ereigniskontrast × Abdeckung; unabhängig von der Dauerregelmäßigkeit | – |
| `uncertainty` | `1 − quality` | – |
| `plausible` | keine technische Ausschlussregel verletzt | bool |
| `user_confirmed` | alle drei Zyklusereignisse nutzerbestätigt | bool |
| `riding_direction` | von der vorgelagerten Angle-Z-Regel übernommene Reitrichtung; nicht aus AsY/AccX bestimmt | – |
| `pattern_calibration` | `USER_CONFIRMED`, `DIRECTION_PATTERN_CALIBRATED` oder `UNCALIBRATED_DEFAULT` | – |
| `pattern_support_count` / `pattern_agreement` | Zahl bestätigter Referenzereignisse und mittlere Ähnlichkeit der Beispiele mit ihrer AsY-/AccX-Vorlage | Ereignisse / Anteil |

## 9 Zeitliche Taktparameter

Konfiguration `config/taktparameter.v1.json`:

| Parameter | Definition | Wert | Einheit |
|---|---|---:|---|
| `minimum_window_seconds` | kürzestes gleitendes Auswertefenster | 10,0 | `s` |
| `maximum_window_seconds` | längstes Fenster, falls sechs Zyklen je Bein früher nicht erreicht werden | 20,0 | `s` |
| `step_seconds` | Aktualisierungsschritt | 1,0 | `s` |
| `minimum_valid_cycles_per_leg` | Mindestzahl vollständiger plausibler Zyklen je Bein | 6 | Zyklen |
| `confidence_interval_multiplier` | Faktor für technisches 95-%-Intervall | 1,96 | – |
| `required_leg_labels` | Pflichtsensoren | `VL VR HL HR` | – |

Größen je Fenster und je Bein:

| Parameter | Definition | Einheit |
|---|---|---|
| `mean_cycle_duration` | Mittel der vollständigen Zyklusdauern | `s` |
| `cycle_frequency` | `1 / mean_cycle_duration` | `Hz` |
| `cycle_duration_standard_deviation` | Stichproben-SD der Zyklusdauern | `s` |
| `cycle_duration_coefficient_of_variation` | `100 × SD / mean` | `%` |
| `cycle_duration_drift` | lineare Steigung der Zyklusdauer über der Zeit | `s/s` |
| `mean_phase` | zirkulärer Mittelwert der Zielbeinphase relativ zum Referenzbein | Zyklusanteil |
| `circular_standard_deviation` | zirkuläre Streuung derselben Phase | Zyklusanteil |
| `absolute_expected_phase_deviation` | kleinster Kreisabstand zur technisch erwarteten Phase, falls definiert | Zyklusanteil |
| `phase_dispersion` | Mittel der gültigen zirkulären Phasenstreuungen | Zyklusanteil |
| `temporal_symmetry_deviation` | Mittel der Abweichungen der kontralateralen Beinpaare von Phase `0,5` | `%` des Zyklus |
| `standard_uncertainty` | kombinierte technische Standardunsicherheit | Parametereinheit |
| `confidence_interval_95` | `value ± 1,96 × standard_uncertainty` | Parametereinheit |
| `valid` / `invalid_reason` | Gültigkeit; ungültige Werte sind `null` | bool / Text |
| `assessment` | `IMPROVED`, `WORSENED`, `STABLE_WITHIN_UNCERTAINTY`, `CHANGED_WITHOUT_VALENCE` oder `COMPARISON_UNAVAILABLE` | – |

## 10 Statuswerte

| Feld | Werte |
|---|---|
| Import | `ready_for_further_analysis` (bool), `quality_status` je Sensor |
| Synchronisation / Vorverarbeitung / Segmentierung / Zyklen / Taktparameter | `*_ACCEPTED`, `*_REVIEW_REQUIRED`, `*_NOT_POSSIBLE` |
| Meldungen | `code`, `severity`, `observation`, `uncertainty`, `recommendation` – Beobachtung, Unsicherheit und Empfehlung bleiben getrennt |
| Verlusteinschätzung | `loss_determination`, Lücken stets `SUSPECTED_NOT_PROVEN` |

## 11 Offen

| Punkt | Stand |
|---|---|
| horizontale Vorzeichen der Beinsensoren | für diese Montage nutzerbestätigt: links `+1`, rechts gespiegelt `−1`; bei neuer Montage erneut kalibrieren |
| Gierwinkel der Orientierung | ungelöst; nur die Vertikale ist bestimmt |
| echte Hufkontaktzeiten | Signalereignisse nutzerbestätigt, aber nicht gegen Kraftplatte validiert |
| Mehrvideovergleich | nur `IMG_4012.MOV` ist gültige Referenz; zweite unabhängige Aufnahme fehlt |
| physiologische Referenzbereiche | bewusst keine; alle Schwellen sind technische Konfigurationswerte |
