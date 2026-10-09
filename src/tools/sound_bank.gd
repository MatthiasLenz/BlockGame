class_name SoundBank
extends RefCounted
## Bibliothek prozedural erzeugter Sounds (16 Bit, mono, 22050 Hz).

const RATE := 22050

static var _cache: Dictionary = {}

static func entries() -> Array[Dictionary]:
	return [
		_e("dig", "Graben (Erde)", "Knirschendes Graben mit dumpfem Schlag", 0.25, 42, _dig),
		_e("place", "Block setzen", "Dumpfer Aufschlag", 0.15, 7, _place),
		_e("step_grass", "Schritt Gras", "Weiches, raschelndes Schrittgeraeusch", 0.14, 1, _step_grass),
		_e("step_stone", "Schritt Stein", "Harter Tritt mit hellem Klick", 0.14, 2, _step_stone),
		_e("step_sand", "Schritt Sand", "Koerniges Knirschen", 0.18, 3, _step_sand),
		_e("step_wood", "Schritt Holz", "Hohles Poltern auf Holzboden", 0.16, 4, _step_wood),
		_e("step_snow", "Schritt Schnee", "Knirschen im Schnee", 0.22, 5, _step_snow),
		_e("hit_stone", "Auf Stein hacken", "Heller Pickelschlag auf Stein", 0.22, 6, _hit_stone),
		_e("hit_wood", "Auf Holz hacken", "Dumpfer Axthieb mit Holzklang", 0.22, 8, _hit_wood),
		_e("hit_dirt", "Auf Erde hacken", "Gedaempfter Spatenschlag", 0.16, 9, _hit_dirt),
		_e("break_stone", "Stein zerbrechen", "Splitterndes Brechen mit Bruchstuecken", 0.4, 10, _break_stone),
		_e("break_glass", "Glas zerbrechen", "Klirrende Scherben", 0.5, 11, _break_glass),
		_e("jump", "Springen", "Kurzer Absprung", 0.15, 12, _jump),
		_e("land", "Landen", "Dumpfer Aufprall nach Sprung", 0.2, 13, _land),
		_e("splash", "Wasser platschen", "Platschen beim Eintauchen", 0.45, 14, _splash),
		_e("bubbles", "Blubbern", "Aufsteigende Luftblasen", 0.5, 15, _bubbles),
		_e("pickup", "Item einsammeln", "Helles, aufsteigendes Pling", 0.3, 16, _pickup),
		_e("click", "Menue-Klick", "Kurzer UI-Klick", 0.06, 17, _click),
		_e("hurt", "Schaden", "Dumpfer Treffer mit absinkendem Ton", 0.3, 18, _hurt),
		_e("explosion", "Explosion", "Tiefes Grollen mit Rauschen", 1.0, 19, _explosion),
	]

static func get_stream(id: String) -> AudioStreamWAV:
	if _cache.has(id):
		return _cache[id]
	for e in entries():
		if e.id == id:
			var wav := _render(e.duration, e.seed, e.fn)
			_cache[id] = wav
			return wav
	return null

static func _e(id: String, label: String, desc: String, dur: float, seed_value: int, fn: Callable) -> Dictionary:
	return {"id": id, "name": label, "desc": desc, "duration": dur, "seed": seed_value, "fn": fn}

# fn(t, rng, st) -> Sample in [-1, 1]; st haelt den Filterzustand.
static func _render(duration: float, seed_value: int, fn: Callable) -> AudioStreamWAV:
	var n := int(RATE * duration)
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st := {}
	for i in n:
		var s: float = clampf(fn.call(float(i) / RATE, rng, st), -1.0, 1.0)
		pcm.encode_s16(i * 2, int(s * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = pcm
	return wav

# Tiefpass-gefiltertes Rauschen; a nahe 0 = dumpf, 1 = hell.
static func _noise(rng: RandomNumberGenerator, st: Dictionary, key: String, a: float) -> float:
	var v: float = st.get(key, 0.0)
	v += (rng.randf_range(-1.0, 1.0) - v) * a
	st[key] = v
	return v

# Hochpass-Rauschen fuer helle Anteile.
static func _hiss(rng: RandomNumberGenerator, st: Dictionary, key: String, a: float) -> float:
	var raw := rng.randf_range(-1.0, 1.0)
	var v: float = st.get(key, 0.0)
	v += (raw - v) * a
	st[key] = v
	return raw - v

static func _attack(t: float, secs: float) -> float:
	return minf(t / secs, 1.0)

static func _dig(t: float, rng: RandomNumberGenerator, st: Dictionary) -> float:
	var lp := _noise(rng, st, "a", 0.3)
	var scrape := lp * (0.55 + 0.45 * sin(TAU * 35.0 * t)) * _attack(t, 0.005) * exp(-t * 20.0)
	var thud := sin(TAU * 85.0 * t) * exp(-t * 65.0) * 0.6
	return (scrape * 1.6 + thud) * 0.7

static func _place(t: float, rng: RandomNumberGenerator, st: Dictionary) -> float:
	var lp := _noise(rng, st, "a", 0.25)
	var thunk := sin(TAU * 110.0 * t) * exp(-t * 35.0)
	var dirt := lp * exp(-t * 50.0) * 0.8
	return (thunk + dirt) * 0.8

static func _step_grass(t: float, rng: RandomNumberGenerator, st: Dictionary) -> float:
	var n := _noise(rng, st, "a", 0.35)
	var rustle := _hiss(rng, st, "b", 0.4) * 0.25
	var env := _attack(t, 0.008) * exp(-t * 28.0)
	return (n * 1.4 + rustle) * env * 0.8 + sin(TAU * 70.0 * t) * exp(-t * 50.0) * 0.3

static func _step_stone(t: float, rng: RandomNumberGenerator, st: Dictionary) -> float:
	var tick := _hiss(rng, st, "a", 0.5) * exp(-t * 90.0) * 0.6
	var body := sin(TAU * 140.0 * t) * exp(-t * 45.0) * 0.6
	var tap := sin(TAU * 900.0 * t) * exp(-t * 120.0) * 0.25
	return tick + body + tap

static func _step_sand(t: float, rng: RandomNumberGenerator, st: Dictionary) -> float:
	var n := _noise(rng, st, "a", 0.55)
	var env := _attack(t, 0.02) * exp(-t * 16.0)
	return n * env * 1.1 + sin(TAU * 60.0 * t) * exp(-t * 40.0) * 0.25

static func _step_wood(t: float, rng: RandomNumberGenerator, st: Dictionary) -> float:
	var knock := sin(TAU * 190.0 * t) * exp(-t * 40.0) + sin(TAU * 310.0 * t) * exp(-t * 55.0) * 0.5
	var n := _noise(rng, st, "a", 0.3) * exp(-t * 70.0) * 0.5
	return knock * 0.7 + n

static func _step_snow(t: float, rng: RandomNumberGenerator, st: Dictionary) -> float:
	var n := _noise(rng, st, "a", 0.5)
	var crunch := 0.5 + 0.5 * sin(TAU * 55.0 * t + n * 4.0)
	var env := _attack(t, 0.01) * exp(-t * 13.0)
	return n * crunch * env * 1.3 + _hiss(rng, st, "b", 0.6) * exp(-t * 40.0) * 0.15

static func _hit_stone(t: float, rng: RandomNumberGenerator, st: Dictionary) -> float:
	var clink := (sin(TAU * 1250.0 * t) + 0.6 * sin(TAU * 2310.0 * t) + 0.3 * sin(TAU * 3470.0 * t)) * exp(-t * 35.0)
	var crack := _hiss(rng, st, "a", 0.4) * exp(-t * 120.0)
	var thump := sin(TAU * 120.0 * t) * exp(-t * 50.0)
	return clink * 0.35 + crack * 0.5 + thump * 0.5

static func _hit_wood(t: float, rng: RandomNumberGenerator, st: Dictionary) -> float:
	var tone := sin(TAU * 240.0 * t) * exp(-t * 28.0) + 0.5 * sin(TAU * 480.0 * t) * exp(-t * 40.0)
	var chop := _noise(rng, st, "a", 0.3) * exp(-t * 80.0)
	return tone * 0.6 + chop * 0.6

static func _hit_dirt(t: float, rng: RandomNumberGenerator, st: Dictionary) -> float:
	var n := _noise(rng, st, "a", 0.18) * exp(-t * 45.0)
	var thud := sin(TAU * 75.0 * t) * exp(-t * 40.0)
	return n * 1.4 + thud * 0.6

static func _break_stone(t: float, rng: RandomNumberGenerator, st: Dictionary) -> float:
	var crack := _hiss(rng, st, "a", 0.3) * exp(-t * 60.0)
	var rumble := _noise(rng, st, "b", 0.15) * exp(-t * 9.0) * (0.6 + 0.4 * sin(TAU * 28.0 * t))
	var thud := sin(TAU * 70.0 * t) * exp(-t * 18.0)
	# Herabfallende Bruchstuecke als zufaellige Klicks.
	if t > 0.08 and rng.randf() < 0.004:
		st["chip"] = 1.0
	var c: float = st.get("chip", 0.0)
	var chips := c * rng.randf_range(-1.0, 1.0) * 0.5
	st["chip"] = c * 0.9
	return crack * 0.5 + rumble * 0.9 + thud * 0.5 + chips

static func _break_glass(t: float, rng: RandomNumberGenerator, st: Dictionary) -> float:
	var shatter := _hiss(rng, st, "a", 0.15) * exp(-t * 14.0) * 0.35
	var ring := 0.0
	for f in [2400.0, 3100.0, 4200.0, 5300.0]:
		ring += sin(TAU * f * t) * exp(-t * (18.0 + f * 0.002))
	if rng.randf() < 0.003:
		st["tk"] = 1.0
		st["tkf"] = rng.randf_range(3000.0, 6500.0)
		st["tkt"] = t
	var tk: float = st.get("tk", 0.0)
	var tinkle := sin(TAU * st.get("tkf", 4000.0) * (t - st.get("tkt", 0.0))) * tk * 0.4
	st["tk"] = tk * 0.995
	return shatter + ring * 0.12 + tinkle

static func _jump(t: float, rng: RandomNumberGenerator, st: Dictionary) -> float:
	var n := _noise(rng, st, "a", 0.3) * _attack(t, 0.01) * exp(-t * 22.0)
	var f := 120.0 + 180.0 * t
	return n * 0.8 + sin(TAU * f * t) * exp(-t * 25.0) * 0.4

static func _land(t: float, rng: RandomNumberGenerator, st: Dictionary) -> float:
	var thud := sin(TAU * (90.0 - 100.0 * t) * t) * exp(-t * 22.0)
	var n := _noise(rng, st, "a", 0.2) * exp(-t * 35.0)
	return thud * 0.8 + n * 0.8

static func _splash(t: float, rng: RandomNumberGenerator, st: Dictionary) -> float:
	var wash := _noise(rng, st, "a", 0.4) * _attack(t, 0.01) * exp(-t * 7.0)
	var sizzle := _hiss(rng, st, "b", 0.3) * exp(-t * 10.0) * 0.4
	var drop := sin(TAU * (500.0 + 1500.0 * t) * t) * exp(-t * 30.0) * 0.2
	return (wash * 1.2 + sizzle) * (0.7 + 0.3 * sin(TAU * 14.0 * t)) + drop

static func _bubbles(t: float, rng: RandomNumberGenerator, st: Dictionary) -> float:
	if rng.randf() < 0.0008:
		st["b"] = 1.0
		st["bf"] = rng.randf_range(300.0, 900.0)
		st["bt"] = t
	var b: float = st.get("b", 0.0)
	var age: float = t - st.get("bt", 0.0)
	var f: float = st.get("bf", 500.0) * (1.0 + 4.0 * age)
	st["b"] = b * 0.9992
	return sin(TAU * f * age) * b * exp(-age * 30.0) * 0.8

static func _pickup(t: float, _rng: RandomNumberGenerator, _st: Dictionary) -> float:
	var f := 880.0 if t < 0.08 else 1320.0
	var local := t if t < 0.08 else t - 0.08
	return (sin(TAU * f * local) + 0.3 * sin(TAU * f * 2.0 * local)) * exp(-local * 14.0) * 0.45

static func _click(t: float, rng: RandomNumberGenerator, st: Dictionary) -> float:
	return (sin(TAU * 1800.0 * t) * 0.5 + _hiss(rng, st, "a", 0.5) * 0.3) * exp(-t * 110.0)

static func _hurt(t: float, rng: RandomNumberGenerator, st: Dictionary) -> float:
	var f := 200.0 - 300.0 * t
	var body := sin(TAU * f * t) * exp(-t * 12.0)
	var n := _noise(rng, st, "a", 0.25) * exp(-t * 30.0)
	return body * 0.7 + n * 0.5

static func _explosion(t: float, rng: RandomNumberGenerator, st: Dictionary) -> float:
	var rumble := _noise(rng, st, "a", 0.08) * exp(-t * 3.5)
	var blast := _noise(rng, st, "b", 0.5) * exp(-t * 9.0)
	var boom := sin(TAU * (60.0 - 30.0 * t) * t) * exp(-t * 4.0)
	return (rumble * 2.2 + blast * 0.9 + boom * 0.9) * _attack(t, 0.003) * 0.6
