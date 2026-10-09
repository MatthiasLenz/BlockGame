extends Node3D

const WORLD_RADIUS := 40
@export_range(0, 64) var max_height := 4
const BLOCK_SIZE := 1.0
const PLAYER_SCALE := 2.0

var blocks: Dictionary = {}
var block_mesh: BoxMesh
var block_texture: ImageTexture
var block_materials: Dictionary = {}
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
const JUMP_HEIGHT := 2.5 * BLOCK_SIZE
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
var left_items: Array[Color] = [Color(0.35, 0.7, 0.32), Color(0.45, 0.62, 0.38), Color(0.6, 0.5, 0.38), Color(0.35, 0.55, 0.28)]
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
		mat.albedo_texture = _get_block_texture()
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
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.05
	var base_color := Color(0.35, 0.55, 0.28)
	for x in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
		for z in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
			var h := int(round(remap(noise.get_noise_2d(x, z), -1.0, 1.0, -1.0, float(max_height))))
			# Nur die obersten 3 Schichten, damit nicht tausende unsichtbare Bloecke entstehen.
			for y in range(maxi(-1, h - 2), h + 1):
				_spawn_block(Vector3i(x, y, z), _color_for_height(1 + int((h + 1.0) / (max_height + 1.0) * 2.999)) if y == h else base_color)

func _color_for_height(height_level: int) -> Color:
	if height_level <= 1:
		return Color(0.35, 0.7, 0.32)
	if height_level <= 2:
		return Color(0.45, 0.62, 0.38)
	return Color(0.6, 0.5, 0.38)

func _get_block_mesh() -> BoxMesh:
	if block_mesh == null:
		block_mesh = BoxMesh.new()
		block_mesh.size = Vector3(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	return block_mesh

func _get_block_texture() -> ImageTexture:
	if block_texture == null:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1234
		var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
		for px in 16:
			for py in 16:
				var v := rng.randf_range(0.78, 1.0)
				img.set_pixel(px, py, Color(v, v, v))
		block_texture = ImageTexture.create_from_image(img)
	return block_texture

func _get_block_material(color: Color) -> StandardMaterial3D:
	if not block_materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.albedo_texture = _get_block_texture()
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.roughness = 0.9
		block_materials[color] = material
	return block_materials[color]

func _spawn_block(pos: Vector3i, color: Color) -> void:
	if blocks.has(pos):
		return

	var body := StaticBody3D.new()
	body.position = Vector3(pos.x, pos.y, pos.z)
	body.set_meta("cell", pos)
	body.set_meta("color", color)

	var mesh := MeshInstance3D.new()
	mesh.mesh = _get_block_mesh()
	mesh.position = Vector3.ZERO
	mesh.material_override = _get_block_material(color)

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
	if player == null:
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

	if input_dir.length() > 0.0:
		input_dir = input_dir.normalized()
		player.velocity.x = input_dir.x * move_speed
		player.velocity.z = input_dir.z * move_speed
	else:
		player.velocity.x = move_toward(player.velocity.x, 0.0, move_speed)
		player.velocity.z = move_toward(player.velocity.z, 0.0, move_speed)

	if Input.is_physical_key_pressed(KEY_SPACE) and player.is_on_floor() and not inventory_open:
		player.velocity.y = jump_force
		_play_sound("jump", 0.95, 1.05, -6.0)
	else:
		player.velocity.y -= gravity * delta

	_try_step_up(delta)
	player.move_and_slide()
	step_offset = move_toward(step_offset, 0.0, STEP_SMOOTH_SPEED * delta * maxf(absf(step_offset), 0.3))
	camera.position.y = CAMERA_HEIGHT + step_offset
	_update_movement_sounds(delta, Vector2(player.velocity.x, player.velocity.z).length() > 0.5 * move_speed)

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
