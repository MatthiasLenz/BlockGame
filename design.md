# Weltzustand und Block-Streaming

## Ziel

Die Aufteilung und Speicherung der Spielwelt ist von ihrer Übertragung zu
trennen. Die Welt wird durch globale Koordinaten und ihren Blockzustand
beschrieben. Welche Blöcke ein Client wann erhält und wie sie in
Übertragungspakete aufgeteilt werden, ist eine separate Entscheidung.

Streaming-Pakete sind daher keine Welt- oder Speicher-Chunks. Sie dürfen
räumlich zusammenhängende Blöcke bündeln, müssen aber weder feste Abmessungen
noch feste Grenzen haben.

## Verantwortlichkeiten

### Weltzustand auf dem Server

- Der Server ist die maßgebliche Quelle für den Blockzustand.
- Der Zustand eines Blocks wird anhand seiner Weltkoordinaten bestimmt, zum
  Beispiel aus einem Terrain-Seed und den gespeicherten Änderungen an der
  generierten Welt.
- Speicherung, Abfrage und Änderungen des Weltzustands funktionieren
  unabhängig davon, ob ein Block bereits an einen Client übertragen wurde.

### Interesse und Anfrage des Clients

- Der Client meldet, welche Bereiche er sehen oder betreten können soll.
- Eine Anfrage kann Position, Blickrichtung und gewünschte Reichweite
  enthalten. Der Server validiert und begrenzt die Anfrage, bevor er daraus
  relevante Weltbereiche ableitet.
- Anfragen sind Empfehlungen für den Bedarf des Clients, keine Autorisierung
  für beliebige Weltabfragen.

### Auswahl und Priorisierung

- Der Server ermittelt die für den Client relevanten Blöcke aus Weltzustand
  und gemeldetem Interesse.
- Die Auswahl kann Sichtfeld, Entfernung und Priorität berücksichtigen.
- Nahe Daten, sichtbare Daten und voraussichtlich bald benötigte Daten können
  bevorzugt werden. Nicht sichtbare Blöcke dürfen später übertragen werden.
- Sichtbarkeit ist nicht der einzige Bedarf: Nahe Blöcke außerhalb des
  Sichtfelds können für Kollisionen, Bewegung und Interaktionen erforderlich
  sein.
- Noch nicht geladene Daten müssen von bestätigter Luft unterschieden werden.
  Eine Streaming-Lücke darf nicht als leerer Weltbereich interpretiert werden.

### Paketierung und Übertragung

- Die Paketierung erhält eine Obergrenze in Bytes, damit große oder
  unvorhersehbare Datenmengen den Übertragungsweg nicht überlasten.
- Der Server kann Blöcke räumlich benachbart bündeln, etwa um die Kompression
  zu verbessern. Das ist eine Optimierung und keine Voraussetzung des
  Protokolls.
- Pakete können über beliebige Weltkoordinaten adressierte Blockdaten
  enthalten; ihre Grenzen müssen nicht mit internen Weltpartitionen
  übereinstimmen.
- Übertragen werden kompakte Blockdaten und Weltkoordinaten, keine Godot-Nodes
  oder Szenenobjekte. Darstellung und lokale Kollisionsrepräsentation erstellt
  der Client aus den empfangenen Daten.

### Lokale Weltansicht des Clients

- Der Client fügt empfangene Blockzustände anhand ihrer globalen Koordinaten in
  seine lokale Weltansicht ein.
- Die lokale Ansicht ist ein Cache des Serverzustands und nicht selbst die
  maßgebliche Speicherung der Welt.
- Der Client kann fehlende oder veraltete Bereiche gezielt nachfordern, wenn
  sich sein Interesse ändert oder er zusätzliche Daten benötigt.
- Verspätete Antworten auf überholte Anfragen dürfen keine neueren Daten
  überschreiben. Anfragen und Datenänderungen benötigen dafür geeignete
  Kennungen oder Versionsstände.

## Änderungen und Autorität

- Änderungen der Welt werden auf dem Server angewendet und an Clients
  verteilt, deren Interesse die betroffenen Koordinaten umfasst.
- Der Server prüft Änderungen und Spieleraktionen autoritativ. Die lokale
  Darstellung des Clients allein entscheidet nicht, ob ein Block abgebaut,
  platziert oder verändert werden darf.
- Für reproduzierbares Terrain können Seed und Änderungen gegenüber dem
  generierten Grundzustand gespeichert werden, statt alle unveränderten
  Blöcke einzeln abzulegen.

## Ablauf

1. Der Client meldet oder aktualisiert sein Interesse.
2. Der Server validiert die Anfrage und bestimmt relevante Blockdaten.
3. Der Server priorisiert die Daten und bündelt sie in Pakete innerhalb des
   Übertragungslimits.
4. Der Client übernimmt die Daten anhand ihrer Koordinaten in die lokale
   Ansicht.
5. Bei verändertem Bedarf fordert der Client gezielt weitere oder aktualisierte
   Daten an.
6. Serveränderungen werden für betroffene interessierte Clients veröffentlicht;
   nicht benötigte Bereiche können aus der lokalen Ansicht entfernt und später
   erneut angefordert werden.

## Abgrenzung

Interne räumliche Strukturen dürfen die Abfrage beschleunigen, müssen aber
weder das externe Anfrageformat noch die Paketgrenzen bestimmen. Damit bleiben
Weltmodell, Interessensverwaltung, Priorisierung, Paketierung und
Clientdarstellung unabhängig weiterentwickelbar.
