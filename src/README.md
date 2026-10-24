# MiniCraft in Godot 4.7.2

Ein kleines Minecraft-artiges Spiel mit:
- Blockwelt
- Einfaches blockiges Spielermodell
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

Ohne Argument startet das Projekt (z. B. mit `F5`) als Client und zeigt die Serverauswahl. Die Adresse
ist standardmäßig `127.0.0.1` und kann vor dem Verbinden geändert werden. `--address` und `--port` aus der Kommandozeile füllen die Verbindungseinstellungen ebenfalls
vor. Eine mit dem Feature-Tag `dedicated_server` exportierte Version startet automatisch als Server.

## Linux-Server mit systemd

Der Linux-Export besteht aus `MiniCraft.x86_64` und der danebenliegenden `MiniCraft.pck`.
Auf einem Rechner mit installierten Linux-Exportvorlagen kann er in Godot über **Projekt >
Exportieren > Linux > Projekt exportieren** erstellt werden. Der Linux-Preset exportiert nach
`export/MiniCraft.x86_64`. Die systemd-Unit startet diesen normalen Export headless mit
`--server`; ein spezieller Dedicated-Server-Export ist dafür nicht erforderlich.

Auf dem Linux-Server die beiden Exportdateien ablegen (zum Beispiel per `scp`) und den
systemd-Benutzer sowie das Installationsverzeichnis anlegen:

```sh
sudo useradd --system --user-group --no-create-home --shell /usr/sbin/nologin minicraft
sudo install -d -o root -g root -m 0755 /opt/minicraft
sudo install -o root -g root -m 0755 MiniCraft.x86_64 /opt/minicraft/MiniCraft.x86_64
sudo install -o root -g root -m 0644 MiniCraft.pck /opt/minicraft/MiniCraft.pck
```

`MiniCraft.x86_64` und `MiniCraft.pck` in den Befehlen sind die lokal exportierten Dateien.
Die Unit-Datei `deploy/minicraft-server.service` ins Repository-Installationsverzeichnis
kopieren oder separat auf den Server übertragen und anschließend aktivieren:

```sh
sudo install -o root -g root -m 0644 deploy/minicraft-server.service /etc/systemd/system/minicraft-server.service
sudo systemctl daemon-reload
sudo systemctl enable --now minicraft-server
sudo systemctl status minicraft-server
```

Der Server lauscht standardmäßig auf UDP-Port `24565`. Diesen Port in der Server-Firewall
(und gegebenenfalls zusätzlich in der Firewall des Hosting-Anbieters) freigeben. Bei UFW:

```sh
sudo ufw allow 24565/udp
```

Status und Logs lassen sich so prüfen; Änderungen an der Unit erfordern `daemon-reload` und
einen Neustart:

```sh
sudo journalctl -u minicraft-server -f
sudo systemctl restart minicraft-server
```

Für einen anderen Port `--port=24565` in der Unit anpassen und denselben UDP-Port auch in
Firewall und Client-Verbindung verwenden.

## Aufbau
- `main.gd`: Startpunkt, wählt Server oder Client.
- `server/`: Weltzustand, Terrain-Erzeugung, Validierung von Abbau/Platzieren, Paketversand.
- `client/`: Darstellung, Eingabe, Bewegung und lokale Weltansicht.
- `shared/`: Blockdefinitionen und die RPC-Schnittstelle (`WorldLink`).

Aktuell sendet der Server die gesamte Welt als Pakete begrenzter Größe; Interessensverwaltung und
Priorisierung gemäß `design.md` folgen. Der Server sendet regelmäßig die Positionen der
anderen Spieler, die Clients zeigen dort ein Spielermodell an.

## Hinweis
Das Projekt ist bewusst minimal gehalten und dient als Grundlage für eigene Erweiterungen wie Biome, Inventar, Nachtmodus oder Crafting.
