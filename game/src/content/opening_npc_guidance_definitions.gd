extends RefCounted
## Supported fresh-opening controller tuning, independently verified per edition.
const Fonts = preload("res://src/content/font_definitions.gd")
const EXPECTED = {
  "actor_kind": 8,
  "target_kind": "player",
  "selection_period_ms": 5000,
  "straight_roll_bound": 100,
  "straight_chance": 20,
  "selection_roll_bound": 100,
  "cruise_speed": 2.0,
  "boost_period_ms": 5000,
  "boost_chance": 5,
  "boost_roll_bound": 100,
  "damage_boost_elapsed_ms": 10000,
  "boost_duration_base_ms": 5000,
  "boost_duration_bound_ms": 3000,
  "boost_speed": 5.5,
  "speed_decrease": 0.949999988079071,
  "speed_increase": 1.0499999523162842,
  "damage_percent_scale": 100.0,
  "boost_damage_percent": 40.0,
  "close_half_extent": 8000,
  "special_close_half_extent": 12000,
  "fire_half_extent": 35000.0,
  "fire_alignment": 0.007629389874637127,
  "fresh_hull_base": 34,
  "difficulty_offset": -0.5
}
const SIZES = {
  "x86_64": {
    "virtual_update": 8,
    "tuning": 127,
    "speed_seed": 55,
    "hull_seed": 39,
    "selection": 119,
    "boost_damage": 123,
    "boost_start": 135,
    "boost_response": 202,
    "near": 62,
    "fire": 146,
    "hull_level": 46,
    "hull_difficulty": 37,
    "membership": 37,
    "player_first": 33,
    "literal_0": 4,
    "literal_1": 4,
    "literal_2": 8,
    "literal_3": 4,
    "literal_4": 4,
    "literal_5": 4,
    "literal_6": 4
  },
  "armv7": {
    "virtual_update": 4,
    "tuning": 132,
    "speed_seed": 38,
    "hull_seed": 30,
    "selection": 132,
    "boost_damage": 102,
    "boost_start": 130,
    "boost_return": 54,
    "boost_response": 104,
    "near": 86,
    "fire": 128,
    "hull_level": 36,
    "hull_difficulty": 44,
    "membership": 30,
    "player_first": 30,
    "literal_0": 4,
    "literal_1": 4,
    "literal_2": 8,
    "literal_3": 4,
    "literal_4": 4
  }
}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=EXPECTED.size()+1 or not data.get("provenance") is Dictionary: return false
	for key in EXPECTED:
		var value: Variant = data.get(key)
		if EXPECTED[key] is String:
			if not value is String or value!=EXPECTED[key]: return false
		elif (not value is float and not value is int) or not is_finite(float(value)) or value!=EXPECTED[key]: return false
	return true

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing opening NPC guidance declaration"
	if data.is_empty(): return ""
	if not parameters(data): return "Unsupported opening NPC guidance parameters"
	var sizes: Dictionary = SIZES.get(architecture,{})
	if sizes.is_empty() or data.provenance.size()!=sizes.size(): return "Invalid opening NPC guidance provenance"
	var spans := []
	for key in sizes:
		var row: Variant = data.provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes): return "Invalid opening NPC guidance extent: "+key
		var span := Vector2i(int(row.offset),int(row.offset)+int(row.bytes))
		for previous in spans:
			if span.x<previous.y and span.y>previous.x: return "Overlapping opening NPC guidance extents"
		spans.append(span)
	return ""
