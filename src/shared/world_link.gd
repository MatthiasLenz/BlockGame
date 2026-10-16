class_name WorldLink
extends Node

# Gemeinsame RPC-Schnittstelle von Server und Client. Beide Seiten legen den Knoten
# unter identischem Pfad an (.../Game/WorldLink); die Logik haengt an den Signalen.
# Blockdaten werden als flaches Array [x, y, z, typ, x, y, z, typ, ...] uebertragen,
# Typ AIR entfernt einen Block. Einzelne Aenderungen sind Pakete mit einem Block.

const DEFAULT_PORT := 24565

# Server -> Client
signal welcomed(spawn_position: Vector3)
signal blocks_received(data: PackedInt32Array)
signal snapshot_finished
signal inventory_received(inventory: Dictionary)
signal players_received(ids: PackedInt32Array, positions: PackedVector3Array, looks: PackedVector2Array, held: PackedInt32Array)
signal player_swung(id: int)

# Client -> Server (nur auf dem Server ausgeloest)
signal position_reported(pos: Vector3, look: Vector2)
signal swing_requested
signal held_reported(type: int)
signal break_requested(pos: Vector3i)
signal place_requested(pos: Vector3i, type: int)

@rpc("authority", "call_remote", "reliable")
func s_welcome(spawn_position: Vector3) -> void:
	welcomed.emit(spawn_position)

@rpc("authority", "call_remote", "reliable")
func s_blocks(data: PackedInt32Array) -> void:
	blocks_received.emit(data)

@rpc("authority", "call_remote", "reliable")
func s_snapshot_done() -> void:
	snapshot_finished.emit()

@rpc("authority", "call_remote", "reliable")
func s_inventory(inventory: Dictionary) -> void:
	inventory_received.emit(inventory)

# Position, Blickrichtung (x = Yaw, y = Pitch in Grad) und gehaltener Blocktyp
# (AIR = keiner) aller anderen Spieler, gleich indiziert.
@rpc("authority", "call_remote", "unreliable_ordered")
func s_players(ids: PackedInt32Array, positions: PackedVector3Array, looks: PackedVector2Array, held: PackedInt32Array) -> void:
	if ids.size() == positions.size() and ids.size() == looks.size() and ids.size() == held.size():
		players_received.emit(ids, positions, looks, held)

@rpc("any_peer", "call_remote", "reliable")
func c_held(type: int) -> void:
	if multiplayer.is_server():
		held_reported.emit(type)

# Ein anderer Spieler hat die Hand bewegt (Abbauen/Platzieren).
@rpc("authority", "call_remote", "reliable")
func s_swing(id: int) -> void:
	player_swung.emit(id)

@rpc("any_peer", "call_remote", "reliable")
func c_swing() -> void:
	if multiplayer.is_server():
		swing_requested.emit()

@rpc("any_peer", "call_remote", "unreliable_ordered")
func c_position(pos: Vector3, look: Vector2) -> void:
	if multiplayer.is_server():
		position_reported.emit(pos, look)

@rpc("any_peer", "call_remote", "reliable")
func c_break(pos: Vector3i) -> void:
	if multiplayer.is_server():
		break_requested.emit(pos)

@rpc("any_peer", "call_remote", "reliable")
func c_place(pos: Vector3i, type: int) -> void:
	if multiplayer.is_server():
		place_requested.emit(pos, type)
