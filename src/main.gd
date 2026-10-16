extends Node

# Startpunkt: waehlt per Kommandozeile Server oder Client.
#   Server: godot --headless --path src -- --server [--port=24565]
#   Client: godot --path src -- [--address=127.0.0.1] [--port=24565]
# Eine mit dem Feature-Tag "dedicated_server" exportierte Version startet den Server automatisch.

const SERVER_SCENE := "res://server/server.tscn"
const CLIENT_SCENE := "res://client/client.tscn"

func _ready() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var as_server := args.has("server") or OS.has_feature("dedicated_server")
	var game: Node = load(SERVER_SCENE if as_server else CLIENT_SCENE).instantiate()
	# Beide Seiten brauchen identische Knotenpfade fuer RPCs.
	game.name = "Game"
	var port := int(args.get("port", WorldLink.DEFAULT_PORT))
	if as_server:
		game.port = port
	else:
		game.server_port = port
		game.server_address = str(args.get("address", game.server_address))
	add_child(game)

func _parse_args(raw: PackedStringArray) -> Dictionary:
	var result := {}
	for arg in raw:
		if not arg.begins_with("--"):
			continue
		var parts := arg.substr(2).split("=", true, 1)
		result[parts[0]] = parts[1] if parts.size() > 1 else true
	return result
