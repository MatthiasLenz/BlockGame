extends Node3D

const WORLD_RADIUS := 40
const WORLD_EXPANSION_TRIGGER := 16
const WORLD_EXPANSION_SIZE := 16
@export_range(0, 64) var max_height := 4
# Globale maximale Wasserhoehe (Y-Ebene des obersten Wasserblocks); wirkt nur auf neu generierte Bereiche.
@export_range(-1, 64) var water_level := 4
@export_range(0.0, 20.0, 0.1) var swim_speed := 3.5
@export_range(0.0, 20.0, 0.1) var water_sink_speed := 2.5
const BLOCK_SIZE := 1.0
const PLAYER_SCALE := 1.0
const BEDROCK_Y := -2
const BEDROCK_COLOR := Color(0.28, 0.29, 0.3)
const GRASS_COLOR := Color(0.35, 0.7, 0.32)
const HILL_COLOR := Color(0.45, 0.62, 0.38)
const ROCK_COLOR := Color(0.6, 0.5, 0.38)
const DIRT_COLOR := Color(0.47, 0.33, 0.2)
const WATER_COLOR := Color(0.2, 0.45, 0.85, 0.55)
const WATER_GRAVITY_FACTOR := 0.3
const BLOCK_TEXTURE_VARIANTS := 256

var blocks: Dictionary = {}
var water_blocks: Dictionary = {}
var water_material: StandardMaterial3D
var block_mesh: BoxMesh
var block_textures: Dictionary = {}
var block_materials: Dictionary = {}
var world_min_x := -WORLD_RADIUS
var world_max_x := WORLD_RADIUS
var world_min_z := -WORLD_RADIUS
var world_max_z := WORLD_RADIUS
var terrain_seed := 0
var generation_thread := Thread.new()
var generation_thread_running := false
var generation_queue: Array[Vector4i] = []
var generated_positions: Array[Vector3i] = []
var generated_colors: Array[Color] = []
var generation_cursor := 0
var world_initialized := false
var highlight: MeshInstance3D
const SOUND_VOICES := 6
const STEP_INTERVAL := 0.25
var sound_players: Array[AudioStreamPlayer] = []
var step_timer := 0.0
var was_on_floor := true
var fall_speed := 0.0
var player: CharacterBody3D
var camera: Camera3D
var raycast: RayCast3D

var move_speed := 5.5 * PLAYER_SCALE
const JUMP_HEIGHT := 1.5 * BLOCK_SIZE
const STEP_HEIGHT := 1.05 * BLOCK_SIZE
var gravity := 18.0 * PLAYER_SCALE
var jump_force := sqrt(2.0 * gravity * JUMP_HEIGHT)
var yaw := -90.0
var pitch := 0.0
const CAMERA_HEIGHT := 0.7 * PLAYER_SCALE
const STEP_SMOOTH_SPEED := 6.0
var step_offset := 0.0

const MAX_HEARTS := 10
var health := MAX_HEARTS
var hearts: Array[Control] = []

# Linke Hand: Bloecke zum Platzieren, rechte Hand: Werkzeuge (nur Anzeige)
var left_items: Array[Color] = [GRASS_COLOR, HILL_COLOR, ROCK_COLOR, DIRT_COLOR]
var right_items: Array[String] = ["Hand", "Pick", "Axt", "Schwert"]
var left_selected := 0
var right_selected := 0
var left_slots: Array[Panel] = []
var left_counts: Array[Label] = []
var right_slots: Array[Panel] = []
var hand: MeshInstance3D
var hand_rest := Vector3(0.45, -0.35, -0.6)
var hand_tween: Tween
var holding_block := false
var hand_state := ""

const INVENTORY_SLOTS := 27
var inventory: Dictionary = {}
var inventory_open := false
var inventory_panel: PanelContainer
var inventory_grid: GridContainer

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_build_player()
	_build_world()
	_create_lighting()
	_create_crosshair()
	_create_hud()
	_create_hand()
	_create_inventory()
	_create_highlight()
	_create_sound_players()

func _process(_delta: float) -> void:
	_update_world_generation()

func _exit_tree() -> void:
	if generation_thread_running:
		generation_thread.wait_to_finish()

func _create_sound_players() -> void:
	for i in SOUND_VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		sound_players.append(p)

# Spielt einen Sound der SoundBank auf der naechsten freien Stimme ab.
func _play_sound(id: String, pitch_min := 1.0, pitch_max := 1.0, volume_db := 0.0) -> void:
	var stream := SoundBank.get_stream(id)
	if stream == null:
		return
	var p: AudioStreamPlayer = null
	for candidate in sound_players:
		if not candidate.playing:
			p = candidate
			break
	if p == null:
		p = sound_players[0]
	p.stream = stream
	p.pitch_scale = randf_range(pitch_min, pitch_max)
	p.volume_db = volume_db
	p.play()

func _update_movement_sounds(delta: float, moving: bool) -> void:
	var on_floor := player.is_on_floor()
	if on_floor and not was_on_floor and 	fall_speed > 4.0 * PLAYER_SCALE:
			_play_sound("land", 0.9, 1.1, clampf(-12.0 + fall_speed / PLAYER_SCALE, -12.0, 0.0))
	was_on_floor = on_floor
	fall_speed = 0.0 if on_floor else maxf(fall_speed, -player.velocity.y)
	if on_floor and moving:
		step_timer -= delta
		if step_timer <= 0.0:
			step_timer = STEP_INTERVAL
			_play_sound("step_grass", 0.85, 1.15, -4.0)
	else:
		step_timer = 0.0

func _create_highlight() -> void:
	var s := BLOCK_SIZE * 0.502
	var corners: Array[Vector3] = []
	for i in 8:
		corners.append(Vector3(s if i & 1 else -s, s if i & 2 else -s, s if i & 4 else -s))
	var verts := PackedVector3Array()
	for i in 8:
		for bit in [1, 2, 4]:
			if not i & bit:
				verts.append(corners[i])
				verts.append(corners[i | bit])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 1.0)
	mesh.surface_set_material(0, mat)
	highlight = MeshInstance3D.new()
	highlight.mesh = mesh
	highlight.visible = false
	add_child(highlight)

func _update_highlight() -> void:
	var target: Node = null
	if not inventory_open and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and raycast.is_colliding():
		target = raycast.get_collider()
	if target != null and target.has_meta("cell"):
		highlight.global_position = (target as Node3D).global_position
		highlight.visible = true
	else:
		highlight.visible = false

func _create_inventory() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	inventory_panel = PanelContainer.new()
	inventory_panel.set_anchors_preset(Control.PRESET_CENTER)
	inventory_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	inventory_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	inventory_panel.visible = false
	layer.add_child(inventory_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	inventory_panel.add_child(box)
	var title := Label.new()
	title.text = "Inventar (I zum Schliessen)"
	box.add_child(title)

	inventory_grid = GridContainer.new()
	inventory_grid.columns = 9
	inventory_grid.add_theme_constant_override("h_separation", 4)
	inventory_grid.add_theme_constant_override("v_separation", 4)
	box.add_child(inventory_grid)
	_refresh_inventory()

func _refresh_inventory() -> void:
	for child in inventory_grid.get_children():
		child.queue_free()
	var colors := inventory.keys()
	for i in INVENTORY_SLOTS:
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(56, 56)
		var filled := i < colors.size()
		slot.add_theme_stylebox_override("panel", _slot_style(false, colors[i] if filled else Color(0.2, 0.2, 0.22)))
		if filled:
			var count := Label.new()
			count.text = str(inventory[colors[i]])
			count.position = Vector2(30, 32)
			slot.add_child(count)
		inventory_grid.add_child(slot)

func _toggle_inventory() -> void:
	inventory_open = not inventory_open
	inventory_panel.visible = inventory_open
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if inventory_open else Input.MOUSE_MODE_CAPTURED)

func _create_hand() -> void:
	hand = MeshInstance3D.new()
	hand.position = hand_rest
	camera.add_child(hand)
	_update_hand()

# Zeigt den ausgewaehlten Block in der Hand, bei Werkzeugwahl wieder die Hand.
func _update_hand() -> void:
	var show_block: bool = holding_block and int(inventory.get(left_items[left_selected], 0)) > 0
	var key := str(left_selected) if show_block else "hand"
	if key == hand_state:
		return
	hand_state = key
	var mat := StandardMaterial3D.new()
	var box := BoxMesh.new()
	if show_block:
		box.size = Vector3(0.28, 0.28, 0.28)
		mat.albedo_texture = _get_block_texture(0, left_items[left_selected] == DIRT_COLOR)
		mat.albedo_color = left_items[left_selected]
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		hand.rotation_degrees = Vector3(0.0, 30.0, 0.0)
	else:
		box.size = Vector3(0.18, 0.18, 0.6)
		mat.albedo_color = Color(0.9, 0.72, 0.55)
		hand.rotation_degrees = Vector3(0.0, 15.0, 0.0)
	hand.mesh = box
	hand.material_override = mat

func _swing_hand() -> void:
	if hand_tween and hand_tween.is_running():
		hand_tween.kill()
	hand.position = hand_rest
	hand_tween = create_tween()
	hand_tween.tween_property(hand, "position", hand_rest + Vector3(-0.1, 0.05, -0.4), 0.08)
	hand_tween.tween_property(hand, "position", hand_rest, 0.12)

func _place_hand() -> void:
	if hand_tween and hand_tween.is_running():
		hand_tween.kill()
	hand.position = hand_rest
	hand_tween = create_tween()
	hand_tween.set_trans(Tween.TRANS_QUAD)
	hand_tween.tween_property(hand, "position", hand_rest + Vector3(-0.05, -0.1, -0.15), 0.06).set_ease(Tween.EASE_OUT)
	hand_tween.tween_property(hand, "position", hand_rest + Vector3(0.0, 0.03, 0.0), 0.08)
	hand_tween.tween_property(hand, "position", hand_rest, 0.06)

func _slot_style(selected: bool, color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_border_width_all(4 if selected else 2)
	style.border_color = Color.WHITE if selected else Color(0.1, 0.1, 0.1)
	return style

func _create_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	root.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.alignment = BoxContainer.ALIGNMENT_END
	root.add_theme_constant_override("separation", 8)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var heart_row := HBoxContainer.new()
	heart_row.alignment = BoxContainer.ALIGNMENT_CENTER
	heart_row.add_theme_constant_override("separation", 2)
	heart_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(heart_row)
	for i in MAX_HEARTS:
		var heart := Control.new()
		heart.custom_minimum_size = Vector2(24, 22)
		heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
		heart.draw.connect(_draw_heart.bind(heart, i))
		heart_row.add_child(heart)
		hearts.append(heart)

	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 48)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size.y = 80
	root.add_child(bar)

	var left_group := HBoxContainer.new()
	var right_group := HBoxContainer.new()
	for group in [left_group, right_group]:
		group.add_theme_constant_override("separation", 6)
		group.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(group)

	for i in left_items.size():
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(64, 64)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label := Label.new()
		label.text = str(i + 1)
		label.position = Vector2(4, 0)
		slot.add_child(label)
		var count := Label.new()
		count.position = Vector2(34, 36)
		slot.add_child(count)
		left_counts.append(count)
		left_group.add_child(slot)
		left_slots.append(slot)
	for i in right_items.size():
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(64, 64)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var num := Label.new()
		num.text = str(i + 1 + left_items.size())
		num.position = Vector2(4, 0)
		slot.add_child(num)
		var name_label := Label.new()
		name_label.text = right_items[i]
		name_label.set_anchors_preset(Control.PRESET_CENTER)
		name_label.position = Vector2(8, 28)
		slot.add_child(name_label)
		right_group.add_child(slot)
		right_slots.append(slot)
	_refresh_hud()

func _draw_heart(heart: Control, index: int) -> void:
	var full := index < health
	var color := Color(0.85, 0.1, 0.15) if full else Color(0.25, 0.25, 0.25)
	heart.draw_circle(Vector2(7, 7), 6.0, color)
	heart.draw_circle(Vector2(17, 7), 6.0, color)
	heart.draw_colored_polygon(PackedVector2Array([Vector2(1.5, 10), Vector2(22.5, 10), Vector2(12, 21)]), color)

func _refresh_hud() -> void:
	if hand != null:
		_update_hand()
	for i in left_slots.size():
		left_slots[i].add_theme_stylebox_override("panel", _slot_style(i == left_selected, left_items[i]))
		left_counts[i].text = str(inventory.get(left_items[i], 0))
	for i in right_slots.size():
		right_slots[i].add_theme_stylebox_override("panel", _slot_style(i == right_selected, Color(0.3, 0.3, 0.35)))
	for heart in hearts:
		heart.queue_redraw()

func _create_crosshair() -> void:
	var layer := CanvasLayer.new()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cross := Control.new()
	cross.custom_minimum_size = Vector2(24, 24)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.draw.connect(func():
		cross.draw_line(Vector2(12, 2), Vector2(12, 22), Color.WHITE, 2.0)
		cross.draw_line(Vector2(2, 12), Vector2(22, 12), Color.WHITE, 2.0))
	center.add_child(cross)
	layer.add_child(center)
	add_child(layer)

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = Vector3(0.0, max_height + 4.0, 8.0)

	var collision := CollisionShape3D.new()
	collision.shape = CapsuleShape3D.new()
	collision.shape.height = 1.8 * PLAYER_SCALE
	collision.shape.radius = 0.4 * PLAYER_SCALE
	player.add_child(collision)

	camera = Camera3D.new()
	camera.position = Vector3(0.0, CAMERA_HEIGHT, 0.0)
	camera.current = true
	camera.near = 0.1
	camera.far = 200.0
	player.add_child(camera)

	raycast = RayCast3D.new()
	raycast.target_position = Vector3(0.0, 0.0, -5.0 * PLAYER_SCALE)
	raycast.enabled = true
	raycast.collide_with_bodies = true
	raycast.collide_with_areas = false
	raycast.hit_from_inside = false
	camera.add_child(raycast)
	add_child(player)

func _create_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 40.0, 0.0)
	sun.light_energy = 1.2
	add_child(sun)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.72, 0.86, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.9)
	env.ambient_light_energy = 0.7
	environment.environment = env
	add_child(environment)

func _build_world() -> void:
	terrain_seed = randi()
	_queue_world_region(world_min_x, world_max_x, world_min_z, world_max_z)
	_start_next_world_generation()

func _queue_world_region(min_x: int, max_x: int, min_z: int, max_z: int) -> void:
	generation_queue.append(Vector4i(min_x, max_x, min_z, max_z))

func _start_next_world_generation() -> void:
	if generation_thread_running or generation_queue.is_empty():
		return
	var region: Vector4i = generation_queue.pop_front()
	generation_thread_running = true
	var error: Error = generation_thread.start(_generate_world_region_data.bind(region, terrain_seed, max_height, water_level))
	if error != OK:
		generation_thread_running = false
		push_error("World generation thread could not be started: %s" % error_string(error))

func _update_world_generation() -> void:
	if generation_thread_running and not generation_thread.is_alive():
		var result: Dictionary = generation_thread.wait_to_finish()
		generation_thread = Thread.new()
		generation_thread_running = false
		generated_positions = result["positions"]
		generated_colors = result["colors"]
		generation_cursor = 0

	var end_index := mini(generation_cursor + 512, generated_positions.size())
	while generation_cursor < end_index:
		_spawn_block(generated_positions[generation_cursor], generated_colors[generation_cursor])
		generation_cursor += 1

	if generation_cursor == generated_positions.size() and not generated_positions.is_empty():
		generated_positions.clear()
		generated_colors.clear()
		generation_cursor = 0
		_start_next_world_generation()
		if not world_initialized and generation_queue.is_empty() and not generation_thread_running:
			world_initialized = true

func _extend_world_if_needed() -> void:
	var player_x := player.global_position.x
	var player_z := player.global_position.z
	if player_x >= world_max_x - WORLD_EXPANSION_TRIGGER:
		var new_max_x := world_max_x + WORLD_EXPANSION_SIZE
		_queue_world_region(world_max_x + 1, new_max_x, world_min_z, world_max_z)
		world_max_x = new_max_x
	elif player_x <= world_min_x + WORLD_EXPANSION_TRIGGER:
		var new_min_x := world_min_x - WORLD_EXPANSION_SIZE
		_queue_world_region(new_min_x, world_min_x - 1, world_min_z, world_max_z)
		world_min_x = new_min_x

	if player_z >= world_max_z - WORLD_EXPANSION_TRIGGER:
		var new_max_z := world_max_z + WORLD_EXPANSION_SIZE
		_queue_world_region(world_min_x, world_max_x, world_max_z + 1, new_max_z)
		world_max_z = new_max_z
	elif player_z <= world_min_z + WORLD_EXPANSION_TRIGGER:
		var new_min_z := world_min_z - WORLD_EXPANSION_SIZE
		_queue_world_region(world_min_x, world_max_x, new_min_z, world_min_z - 1)
		world_min_z = new_min_z

	_start_next_world_generation()

static func _generate_world_region_data(region: Vector4i, seed: int, height_limit: int, water_height: int) -> Dictionary:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.05
	var positions: Array[Vector3i] = []
	var colors: Array[Color] = []
	for x in range(region.x, region.y + 1):
		for z in range(region.z, region.w + 1):
			positions.append(Vector3i(x, BEDROCK_Y, z))
			colors.append(BEDROCK_COLOR)
			var h := int(round(remap(noise.get_noise_2d(x, z), -1.0, 1.0, -1.0, float(height_limit))))
			# Lueckenlos von der untersten Ebene bis zur Oberflaeche auffuellen.
			for y in range(-1, h + 1):
				positions.append(Vector3i(x, y, z))
				if y == h and h >= water_height:
					var level := 1 + int((h + 1.0) / (height_limit + 1.0) * 2.999)
					colors.append(_color_for_height(level))
				else:
					colors.append(DIRT_COLOR)
			for y in range(h + 1, water_height + 1):
				positions.append(Vector3i(x, y, z))
				colors.append(WATER_COLOR)
	return {"positions": positions, "colors": colors}

static func _color_for_height(height_level: int) -> Color:
	if height_level <= 1:
		return GRASS_COLOR
	if height_level <= 2:
		return HILL_COLOR
	return ROCK_COLOR

func _get_block_mesh() -> BoxMesh:
	if block_mesh == null:
		block_mesh = BoxMesh.new()
		block_mesh.size = Vector3(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	return block_mesh

func _get_block_texture(variant: int = 0, dirt := false) -> ImageTexture:
	var key := Vector2i(variant, int(dirt))
	if not block_textures.has(key):
		var noise := FastNoiseLite.new()
		noise.seed = 1234 + variant
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.5 if dirt else 0.2
		var min_v := 0.45 if dirt else 0.6
		var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
		for px in 16:
			for py in 16:
				var v := clampf(remap(noise.get_noise_2d(px, py), -1.0, 1.0, min_v, 1.0), min_v, 1.0)
				img.set_pixel(px, py, Color(v, v, v))
		block_textures[key] = ImageTexture.create_from_image(img)
	return block_textures[key]

func _get_block_material(color: Color, variant: int) -> StandardMaterial3D:
	if not block_materials.has(color):
		block_materials[color] = {}
	var materials_for_color: Dictionary = block_materials[color]
	if not materials_for_color.has(variant):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.albedo_texture = _get_block_texture(variant, color == DIRT_COLOR)
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.roughness = 0.9
		materials_for_color[variant] = material
	return materials_for_color[variant]

func _get_water_material() -> StandardMaterial3D:
	if water_material == null:
		water_material = StandardMaterial3D.new()
		water_material.albedo_color = WATER_COLOR
		water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		water_material.roughness = 0.2
	return water_material

# Wasser ist transparent und ohne Kollision, damit man hindurchlaufen und Bloecke darin platzieren kann.
func _spawn_water(pos: Vector3i) -> void:
	if blocks.has(pos) or water_blocks.has(pos):
		return
	var mesh := MeshInstance3D.new()
	mesh.mesh = _get_block_mesh()
	mesh.position = Vector3(pos.x, pos.y, pos.z)
	mesh.material_override = _get_water_material()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	water_blocks[pos] = mesh

func _spawn_block(pos: Vector3i, color: Color) -> void:
	if color == WATER_COLOR:
		_spawn_water(pos)
		return
	if blocks.has(pos):
		return
	if water_blocks.has(pos):
		water_blocks[pos].queue_free()
		water_blocks.erase(pos)

	var body := StaticBody3D.new()
	body.position = Vector3(pos.x, pos.y, pos.z)
	body.set_meta("cell", pos)
	body.set_meta("color", color)

	var mesh := MeshInstance3D.new()
	mesh.mesh = _get_block_mesh()
	mesh.position = Vector3.ZERO
	var texture_variant := hash(pos) & 0x7fffffff
	mesh.material_override = _get_block_material(color, texture_variant % BLOCK_TEXTURE_VARIANTS)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	shape.shape = box_shape

	body.add_child(mesh)
	body.add_child(shape)
	add_child(body)
	blocks[pos] = body

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_I:
		_toggle_inventory()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if inventory_open:
			_toggle_inventory()
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return
	if inventory_open:
		return
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton and event.pressed:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.2
		pitch -= event.relative.y * 0.2
		pitch = clamp(pitch, -89.0, 89.0)
		player.rotation.y = deg_to_rad(yaw)
		camera.rotation.x = deg_to_rad(pitch)
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var idx: int = event.physical_keycode - KEY_1
		if idx >= 0 and idx < left_items.size():
			left_selected = idx
			holding_block = true
			_update_hand()
			_refresh_hud()
		elif idx >= left_items.size() and idx < left_items.size() + right_items.size():
			right_selected = idx - left_items.size()
			holding_block = false
			_update_hand()
			_refresh_hud()
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_swing_hand()
			_break_block()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_place_block()

func _physics_process(delta: float) -> void:
	if player == null or not world_initialized:
		return
	_update_highlight()

	var input_dir := Vector3.ZERO
	if not inventory_open:
		if Input.is_physical_key_pressed(KEY_W):
			input_dir -= camera.global_transform.basis.z
		if Input.is_physical_key_pressed(KEY_S):
			input_dir += camera.global_transform.basis.z
		if Input.is_physical_key_pressed(KEY_A):
			input_dir -= camera.global_transform.basis.x
		if Input.is_physical_key_pressed(KEY_D):
			input_dir += camera.global_transform.basis.x
	input_dir.y = 0.0

	var in_water := _is_player_in_water()
	var horizontal_speed := swim_speed if in_water else move_speed
	if input_dir.length() > 0.0:
		input_dir = input_dir.normalized()
		player.velocity.x = input_dir.x * horizontal_speed
		player.velocity.z = input_dir.z * horizontal_speed
	else:
		player.velocity.x = move_toward(player.velocity.x, 0.0, horizontal_speed)
		player.velocity.z = move_toward(player.velocity.z, 0.0, horizontal_speed)

	if in_water:
		if Input.is_physical_key_pressed(KEY_SPACE) and not inventory_open:
			player.velocity.y = _swim_up_velocity(delta)
		else:
			player.velocity.y = maxf(player.velocity.y - gravity * WATER_GRAVITY_FACTOR * delta, -water_sink_speed)
	elif Input.is_physical_key_pressed(KEY_SPACE) and player.is_on_floor() and not inventory_open:
		player.velocity.y = jump_force
		_play_sound("jump", 0.95, 1.05, -6.0)
	else:
		player.velocity.y -= gravity * delta

	_try_step_up(delta)
	player.move_and_slide()
	_extend_world_if_needed()
	step_offset = move_toward(step_offset, 0.0, STEP_SMOOTH_SPEED * delta * maxf(absf(step_offset), 0.3))
	camera.position.y = CAMERA_HEIGHT + step_offset
	_update_movement_sounds(delta, Vector2(player.velocity.x, player.velocity.z).length() > 0.5 * move_speed)

# Wasser ist ohne Kollision; Spieler gilt als im Wasser, wenn seine Koerpermitte (Kapselmitte) in einem Wasserblock liegt.
func _is_player_in_water() -> bool:
	return water_blocks.has(_player_center_cell())

func _player_center_cell() -> Vector3i:
	var p := player.global_position
	return Vector3i(roundi(p.x), roundi(p.y), roundi(p.z))

# Aufstieg stoppt an der Wasseroberflaeche, sodass etwa der halbe Koerper im Wasser bleibt.
func _swim_up_velocity(delta: float) -> float:
	var cell := _player_center_cell()
	if water_blocks.has(cell + Vector3i.UP):
		return swim_speed
	var surface_y := cell.y + 0.5 * BLOCK_SIZE - 0.02
	return clampf((surface_y - player.global_position.y) / delta, 0.0, swim_speed)

# Hebt den Spieler auf eine Stufe (bis STEP_HEIGHT), wenn die Bewegung sonst blockiert waere.
func _try_step_up(delta: float) -> void:
	var motion := Vector3(player.velocity.x, 0.0, player.velocity.z) * delta
	if not player.is_on_floor() or motion.length_squared() < 0.000001:
		return
	var xf := player.global_transform
	if not player.test_move(xf, motion):
		return
	var up := Vector3.UP * STEP_HEIGHT
	if player.test_move(xf, up):
		return
	var raised := xf.translated(up)
	if player.test_move(raised, motion):
		return
	player.global_position += up
	player.velocity.y = 0.0
	step_offset -= STEP_HEIGHT

func _break_block() -> void:
	if raycast == null or not raycast.is_colliding():
		return
	var collider = raycast.get_collider()
	if collider == null or not collider.has_meta("cell"):
		return
	var pos: Vector3i = collider.get_meta("cell")
	if pos.y == BEDROCK_Y:
		return
	if blocks.has(pos):
		var color: Color = collider.get_meta("color")
		inventory[color] = inventory.get(color, 0) + 1
		_refresh_inventory()
		_refresh_hud()
		_play_sound("dig", 0.85, 1.15)
		blocks[pos].queue_free()
		blocks.erase(pos)

func _place_block() -> void:
	var color := left_items[left_selected]
	if inventory.get(color, 0) <= 0:
		return
	if raycast == null or not raycast.is_colliding():
		return
	var collider = raycast.get_collider()
	if collider == null or not collider.has_meta("cell"):
		return
	var target_pos: Vector3i = collider.get_meta("cell")
	var normal := raycast.get_collision_normal()
	var place_pos := Vector3i(
		int(target_pos.x + round(normal.x)),
		int(target_pos.y + round(normal.y)),
		int(target_pos.z + round(normal.z))
	)

	if blocks.has(place_pos):
		return

	# Nur blockieren, wenn der Block die Kapsel des Spielers (Radius 0.4, Hoehe 1.8, jeweils mal PLAYER_SCALE, Ursprung in der Mitte) ueberlappt.
	# Unterhalb der Fuesse gibt es eine kleine Toleranz, damit Bloecke direkt unter dem Spieler moeglich sind.
	var diff := Vector3(place_pos) - player.global_position
	var half_height := 0.9 * PLAYER_SCALE
	var half_width := 0.4 * PLAYER_SCALE + 0.5
	var y_limit := half_height + 0.5 - 0.1 if diff.y < 0.0 else half_height + 0.5
	if absf(diff.x) < half_width and absf(diff.y) < y_limit and absf(diff.z) < half_width:
		return
	_spawn_block(place_pos, color)
	_play_sound("place", 0.9, 1.1)
	_place_hand()
	inventory[color] -= 1
	if inventory[color] <= 0:
		inventory.erase(color)
	_refresh_inventory()
	_refresh_hud()
