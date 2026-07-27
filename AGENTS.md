# InTakt-Projektkontext

InTakt ist ein System zur sensorbasierten Bewegungs- und Ganganalyse beim Pferd.

Der erste Meilenstein ist ein Analyse-Prototyp, der exportierte Daten von vier
IMU-Sensoren verarbeitet. Die Datenerfassung erfolgt zunächst über die
BitMotion-App. Eine eigene BLE-Anbindung und eine vollständige Smartphone-App
sind noch nicht Bestandteil dieses Meilensteins.

## Arbeitsregeln

- Arbeite immer nur am aktuell beauftragten Goal.
- verschaff dir einen Überblick über das gesammt Projekt. 
- Lies vorhandenen Code, bevor du neue Strukturen erstellst.
- Überschreibe keinen bestehenden Ansatz ohne dokumentierte Begründung.
- Rohdaten dürfen nicht verändert werden.
- Trenne Import, Qualitätsprüfung, Vorverarbeitung, Ereigniserkennung,
  Parameterberechnung, Scoring und Interpretation.
- erstelle keiene unnötigen Dateien.
- Jeder Parameter benötigt Definition und Einheit, sammmel alle Parameter in einem Dokument welches wenig Kontigent verbraucht. 
- Beobachtung, Hypothese und Empfehlung müssen getrennt werden.
- Ein Goal ist erst abgeschlossen, wenn seine Erfolgskriterien geprüft wurden.
