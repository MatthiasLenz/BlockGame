extends Node

# Autoritativer Weltserver: haelt den Blockzustand, validiert Spieleraktionen und
# schickt Blockdaten in Paketen begrenzter Groesse an die Clients.

const MAX_CLIENTS := 16
const WORLD_RADIUS := 40
const WORLD_EXPANSION_TRIGGER := 16
const WORLD_EXPANSION_SIZE := 16
const PACKET_BLOCKS := 2048
const PACKETS_PER_FRAME := 4
const PLAYER_SYNC_INTERVAL := 0.05
const REACH := 8.0
const MAX_POSITION_STEP := 32.0
const PLAYER_HALF_HEIGHT := 0.9
const PLAYER_HALF_WIDTH := 0.9
const NEIGHBORS: Array[Vector3i] = [
	Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK,
]

@export_range(0, 64) var max_height := 4
@export_range(-1, 64) var water_level := 4
var port := WorldLink.DEFAULT_PORT

var terrain_seed := 0
var blocks: Dictionary = {}  # Vector3i -> Blocktyp (fest)
var water: Dictionary = {}  # Vector3i -> true
var world_min_x := -WORLD_RADIUS
var world_max_x := WORLD_RADIUS
var world_min_z := -WORLD_RADIUS
var world_max_z := WORLD_RADIUS
var players: Dictionary = {}  # Peer-ID -> {"position": Vector3, "inventory": Dictionary}
var send_queues: Dictionary = {}  # Peer-ID -> Array aus PackedInt32Array bzw. null (Snapshot-Ende)
var link: WorldLink
var player_sync_timer := 0.0
var console_thread: Thread

func _ready() -> void:
	terrain_seed = randi()
	link = WorldLink.new()
	link.name = "WorldLink"
	add_child(link)
	link.position_reported.connect(_on_position_reported)
	link.break_requested.connect(_on_break_requested)
	link.place_requested.connect(_on_place_requested)

	_generate_region(Vector4i(world_min_x, world_max_x, world_min_z, world_max_z))

	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_CLIENTS)
	if error != OK:
		push_error("Server konnte nicht auf Port %d starten: %s" % [port, error_string(error)])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("Server laeuft auf Port %d (Seed %d, %d Bloecke)" % [port, terrain_seed, blocks.size() + water.size()])
	if DisplayServer.get_name() == "headless":
		console_thread = Thread.new()
		console_thread.start(_console_loop)
		print("Konsole bereit, 'help' zeigt die Befehle")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()

# Der blockierende stdin-Thread verhindert ein reguläres Engine-Herunterfahren;
# deshalb wird der Prozess nach dem Freigeben des Ports beendet.
func _quit() -> void:
	_shutdown()
	if console_thread != null:
		OS.kill(OS.get_process_id())
	get_tree().quit()

# Liest stdin in einem eigenen Thread, damit die Eingabe das Spiel nicht blockiert
# und Logausgaben weiterhin erscheinen. Der Thread wird nicht beigetreten, da das
# Lesen blockiert; er endet mit dem Prozess.
func _console_loop() -> void:
	while true:
		var input := OS.read_string_from_stdin(1024)
		if input.is_empty():
			return # stdin geschlossen
		for line in input.split("\n", false):
			line = line.strip_edges()
			if not line.is_empty():
				_run_command.call_deferred(line)

func _run_command(line: String) -> void:
	var parts := line.split(" ", false)
	var args := parts.slice(1)
	match parts[0].to_lower():
		"help":
			print("Befehle: help, status, players, kick <id>, stop (auch: quit, exit)")
		"status":
			print("Port %d, Seed %d, %d Spieler, %d Bloecke, Welt X %d..%d Z %d..%d" % [
				port, terrain_seed, players.size(), blocks.size() + water.size(),
				world_min_x, world_max_x, world_min_z, world_max_z])
		"players":
			if players.is_empty():
				print("Keine Spieler verbunden")
			for id in players:
				print("Spieler %d bei %s" % [id, players[id]["position"]])
		"kick":
			if args.size() != 1 or not args[0].is_valid_int() or not players.has(args[0].to_int()):
				print("Verwendung: kick <id> (gueltige Spieler-ID)")
			else:
				multiplayer.multiplayer_peer.disconnect_peer(args[0].to_int())
		"stop", "quit", "exit":
			print("Server wird beendet")
			_quit()
		_:
			print("Unbekannter Befehl '%s', 'help' zeigt die Befehle" % parts[0])

func _exit_tree() -> void:
	_shutdown()

# Trennt alle Clients und gibt den Port frei.
func _shutdown() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return
	peer.close()
	multiplayer.multiplayer_peer = null
	print("Server beendet, Port %d freigegeben" % port)

func _broadcast_player_positions() -> void:
	for id in players:
		var ids := PackedInt32Array()
		var positions := PackedVector3Array()
		for other in players:
			if other != id:
				ids.append(other)
				positions.append(players[other]["position"])
		link.s_players.rpc_id(id, ids, positions)

func _process(delta: float) -> void:
	player_sync_timer += delta
	if player_sync_timer >= PLAYER_SYNC_INTERVAL:
		player_sync_timer = 0.0
		_broadcast_player_positions()
	for id in send_queues:
		var queue: Array = send_queues[id]
		var sent := 0
		while sent < PACKETS_PER_FRAME and not queue.is_empty():
			var entry = queue.pop_front()
			if entry == null:
				link.s_snapshot_done.rpc_id(id)
				print("-> Spieler %d: Welt-Snapshot vollstaendig gesendet" % id)
			else:
				link.s_blocks.rpc_id(id, entry)
				print("-> Spieler %d: Blockpaket mit %d Bloecken (%d Bytes), %d Pakete in Warteschlange" % [id, entry.size() / 4, entry.size() * 4, queue.size()])
			sent += 1

func _spawn_position() -> Vector3:
	return Vector3(0.0, max_height + 4.0, 8.0)

func _on_peer_connected(id: int) -> void:
	var spawn := _spawn_position()
	players[id] = {"position": spawn, "inventory": {}}
	send_queues[id] = []
	link.s_welcome.rpc_id(id, spawn)
	print("-> Spieler %d: Willkommen, Spawn %s" % [id, spawn])
	var snapshot := PackedInt32Array()
	for pos: Vector3i in blocks:
		_push(snapshot, pos, blocks[pos])
	for pos: Vector3i in water:
		_push(snapshot, pos, BlockDefs.WATER)
	_enqueue(id, snapshot)
	send_queues[id].append(null)
	print("Spieler %d verbunden" % id)

func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	send_queues.erase(id)
	print("Spieler %d getrennt" % id)

func _push(data: PackedInt32Array, pos: Vector3i, type: int) -> void:
	data.append(pos.x)
	data.append(pos.y)
	data.append(pos.z)
	data.append(type)

# Zerlegt Blockdaten in Pakete mit hoechstens PACKET_BLOCKS Bloecken.
func _enqueue(id: int, data: PackedInt32Array) -> void:
	var step := PACKET_BLOCKS * 4
	for start in range(0, data.size(), step):
		send_queues[id].append(data.slice(start, start + step))

func _broadcast(data: PackedInt32Array) -> void:
	for id in players:
		_enqueue(id, data)

func _store(data: PackedInt32Array) -> void:
	for i in range(0, data.size(), 4):
		var pos := Vector3i(data[i], data[i + 1], data[i + 2])
		if data[i + 3] == BlockDefs.WATER:
			if not blocks.has(pos):
				water[pos] = true
		else:
			water.erase(pos)
			blocks[pos] = data[i + 3]

func _generate_region(region: Vector4i) -> PackedInt32Array:
	var data := TerrainGenerator.generate(region, terrain_seed, max_height, water_level)
	_store(data)
	return data

func _expand_region(region: Vector4i) -> void:
	_broadcast(_generate_region(region))

func _extend_world_if_needed(pos: Vector3) -> void:
	if pos.x >= world_max_x - WORLD_EXPANSION_TRIGGER:
		var new_max_x := world_max_x + WORLD_EXPANSION_SIZE
		_expand_region(Vector4i(world_max_x + 1, new_max_x, world_min_z, world_max_z))
		world_max_x = new_max_x
	elif pos.x <= world_min_x + WORLD_EXPANSION_TRIGGER:
		var new_min_x := world_min_x - WORLD_EXPANSION_SIZE
		_expand_region(Vector4i(new_min_x, world_min_x - 1, world_min_z, world_max_z))
		world_min_x = new_min_x

	if pos.z >= world_max_z - WORLD_EXPANSION_TRIGGER:
		var new_max_z := world_max_z + WORLD_EXPANSION_SIZE
		_expand_region(Vector4i(world_min_x, world_max_x, world_max_z + 1, new_max_z))
		world_max_z = new_max_z
	elif pos.z <= world_min_z + WORLD_EXPANSION_TRIGGER:
		var new_min_z := world_min_z - WORLD_EXPANSION_SIZE
		_expand_region(Vector4i(world_min_x, world_max_x, new_min_z, world_min_z - 1))
		world_min_z = new_min_z

func _on_position_reported(pos: Vector3) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id) or not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
		return
	var player: Dictionary = players[id]
	if pos.distance_to(player["position"]) > MAX_POSITION_STEP:
		return
	player["position"] = pos
	_extend_world_if_needed(pos)

func _within_reach(player_pos: Vector3, cell: Vector3i) -> bool:
	return player_pos.distance_to(Vector3(cell)) <= REACH

func _in_world(cell: Vector3i) -> bool:
	return cell.x >= world_min_x and cell.x <= world_max_x \
		and cell.z >= world_min_z and cell.z <= world_max_z \
		and cell.y > BlockDefs.BEDROCK_Y and cell.y <= max_height + 64

func _on_break_requested(pos: Vector3i) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id) or not blocks.has(pos) or pos.y == BlockDefs.BEDROCK_Y:
		return
	var player: Dictionary = players[id]
	if not _within_reach(player["position"], pos):
		return
	var type: int = blocks[pos]
	blocks.erase(pos)
	var inventory: Dictionary = player["inventory"]
	inventory[type] = inventory.get(type, 0) + 1
	var change := PackedInt32Array()
	_push(change, pos, BlockDefs.AIR)
	_broadcast(change)
	link.s_inventory.rpc_id(id, inventory)
	print("-> Spieler %d: Inventar gesendet %s" % [id, inventory])

func _on_place_requested(pos: Vector3i, type: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id) or not BlockDefs.is_placeable(type):
		return
	var player: Dictionary = players[id]
	var inventory: Dictionary = player["inventory"]
	if inventory.get(type, 0) <= 0 or blocks.has(pos) or not _in_world(pos):
		return
	if not _within_reach(player["position"], pos) or not _has_solid_neighbor(pos) or _overlaps_any_player(pos):
		return
	water.erase(pos)
	blocks[pos] = type
	inventory[type] -= 1
	if inventory[type] <= 0:
		inventory.erase(type)
	var change := PackedInt32Array()
	_push(change, pos, type)
	_broadcast(change)
	link.s_inventory.rpc_id(id, inventory)
	print("-> Spieler %d: Inventar gesendet %s" % [id, inventory])

func _has_solid_neighbor(cell: Vector3i) -> bool:
	for offset in NEIGHBORS:
		if blocks.has(cell + offset):
			return true
	return false

# Wie auf dem Client: Block darf nicht die Spielerkapsel ueberlappen; unterhalb der Fuesse gilt eine kleine Toleranz.
func _overlaps_any_player(cell: Vector3i) -> bool:
	for id in players:
		var diff := Vector3(cell) - (players[id]["position"] as Vector3)
		var y_limit := PLAYER_HALF_HEIGHT + 0.4 if diff.y < 0.0 else PLAYER_HALF_HEIGHT + 0.5
		if absf(diff.x) < PLAYER_HALF_WIDTH and absf(diff.y) < y_limit and absf(diff.z) < PLAYER_HALF_WIDTH:
			return true
	return false
