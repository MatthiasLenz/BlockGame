class_name BlockDefs
extends RefCounted

# Blocktypen werden als Ganzzahlen uebertragen; Farben gehoeren nur zur Darstellung.
const AIR := 0
const BEDROCK := 1
const GRASS := 2
const HILL := 3
const ROCK := 4
const DIRT := 5
const WATER := 6

const BEDROCK_Y := -2

const COLORS := {
	BEDROCK: Color(0.28, 0.29, 0.3),
	GRASS: Color(0.35, 0.7, 0.32),
	HILL: Color(0.45, 0.62, 0.38),
	ROCK: Color(0.6, 0.5, 0.38),
	DIRT: Color(0.47, 0.33, 0.2),
	WATER: Color(0.2, 0.45, 0.85, 0.55),
}

static func color_of(type: int) -> Color:
	return COLORS.get(type, Color.MAGENTA)

static func is_placeable(type: int) -> bool:
	return type == GRASS or type == HILL or type == ROCK or type == DIRT
