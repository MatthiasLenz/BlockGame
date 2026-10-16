class_name TerrainGenerator
extends RefCounted

# Erzeugt alle Bloecke eines Bereichs (Vector4i: min_x, max_x, min_z, max_z) als
# flaches Array [x, y, z, typ, ...].
static func generate(region: Vector4i, world_seed: int, height_limit: int, water_height: int) -> PackedInt32Array:
	var noise := FastNoiseLite.new()
	noise.seed = world_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.05
	var data := PackedInt32Array()
	for x in range(region.x, region.y + 1):
		for z in range(region.z, region.w + 1):
			_push(data, x, BlockDefs.BEDROCK_Y, z, BlockDefs.BEDROCK)
			var h := int(round(remap(noise.get_noise_2d(x, z), -1.0, 1.0, -1.0, float(height_limit))))
			# Lueckenlos von der untersten Ebene bis zur Oberflaeche auffuellen.
			for y in range(-1, h + 1):
				var type := BlockDefs.DIRT
				if y == h and h >= water_height:
					type = _surface_type(1 + int((h + 1.0) / (height_limit + 1.0) * 2.999))
				_push(data, x, y, z, type)
			for y in range(h + 1, water_height + 1):
				_push(data, x, y, z, BlockDefs.WATER)
	return data

static func _push(data: PackedInt32Array, x: int, y: int, z: int, type: int) -> void:
	data.append(x)
	data.append(y)
	data.append(z)
	data.append(type)

static func _surface_type(height_level: int) -> int:
	if height_level <= 1:
		return BlockDefs.GRASS
	if height_level <= 2:
		return BlockDefs.HILL
	return BlockDefs.ROCK
