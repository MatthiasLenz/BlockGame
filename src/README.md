# MiniCraft in Godot 4.6.3

Ein kleines Minecraft-artiges Spiel mit:
- Blockwelt
- WASD-Bewegung
- Springen
- Maussteuerung
- Blöcke abbauen und platzieren

## Steuerung
- `WASD`: Bewegen
- `Leertaste`: Springen
- `Maus`: Blick drehen
- `Linke Maustaste`: Block abbauen
- `Rechte Maustaste`: Block platzieren

## Ausführen
1. Godot 4.7.2 öffnen oder die Konsolenversion verwenden.
2. Server starten (headless): `godot --headless --path src -- --server [--port=24565]`
3. Client starten (mehrfach möglich): `godot --path src -- [--address=127.0.0.1] [--port=24565]`

Ohne Argument startet das Projekt (z. B. mit `F5`) als Client und verbindet sich mit `127.0.0.1:24565`.
Eine mit dem Feature-Tag `dedicated_server` exportierte Version startet automatisch als Server.

## Aufbau
- `main.gd`: Startpunkt, wählt Server oder Client.
- `server/`: Weltzustand, Terrain-Erzeugung, Validierung von Abbau/Platzieren, Paketversand.
- `client/`: Darstellung, Eingabe, Bewegung und lokale Weltansicht.
- `shared/`: Blockdefinitionen und die RPC-Schnittstelle (`WorldLink`).

Aktuell sendet der Server die gesamte Welt als Pakete begrenzter Größe; Interessensverwaltung und
Priorisierung gemäß `design.md` folgen. Andere Spieler werden noch nicht dargestellt.

## Hinweis
Das Projekt ist bewusst minimal gehalten und dient als Grundlage für eigene Erweiterungen wie Biome, Inventar, Nachtmodus oder Crafting.
