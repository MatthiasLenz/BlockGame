extends Control
## Sound-Bibliothek: Fenster mit Liste der prozeduralen Sounds zum Abspielen.

var _list: ItemList
var _info: Label
var _player: AudioStreamPlayer
var _entries: Array[Dictionary]

func _ready() -> void:
	_entries = SoundBank.entries()
	get_window().title = "Sound-Bibliothek"
	get_window().size = Vector2i(560, 640)

	var bg := ColorRect.new()
	bg.color = Color(0.14, 0.15, 0.17)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Sound-Bibliothek (%d Sounds) - Doppelklick oder Enter zum Abspielen" % _entries.size()
	box.add_child(title)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for e in _entries:
		_list.add_item("%s  (%.2f s)" % [e.name, e.duration])
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(_play)
	box.add_child(_list)

	_info = Label.new()
	_info.custom_minimum_size.y = 40
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	var play := Button.new()
	play.text = "Abspielen"
	play.pressed.connect(func():
		var sel := _list.get_selected_items()
		if sel.size() > 0:
			_play(sel[0]))
	row.add_child(play)

	var stop := Button.new()
	stop.text = "Stopp"
	stop.pressed.connect(func(): _player.stop())
	row.add_child(stop)

	var pitch_label := Label.new()
	pitch_label.text = "Tonhoehe:"
	row.add_child(pitch_label)

	var pitch := HSlider.new()
	pitch.min_value = 0.5
	pitch.max_value = 2.0
	pitch.step = 0.01
	pitch.value = 1.0
	pitch.custom_minimum_size.x = 160
	pitch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pitch.value_changed.connect(func(v: float): _player.pitch_scale = v)
	row.add_child(pitch)

	_player = AudioStreamPlayer.new()
	add_child(_player)

	_list.select(0)
	_info.text = _entries[0].desc

func _on_selected(index: int) -> void:
	_info.text = _entries[index].desc
	_play(index)

func _play(index: int) -> void:
	_player.stream = SoundBank.get_stream(_entries[index].id)
	_player.play()
