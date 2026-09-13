extends RefCounted
## Shared generated coordinate routes; context owners validate each population.
const Fonts = preload("res://src/content/font_definitions.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const ORIGINS = [[-30000,-10000,20000],[5000,-10000,20000],[5000,-10000,55000],[-30000,-10000,55000]]
const BOUNDS = [25000,10000,25000]
const EXPECTED = {"count_minimum":2,"count_bound":3,"candidate_bound":4,"initial_index":0,"arrival_half_extent":2000}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=EXPECTED.size()+4 or not data.get("provenance") is Dictionary: return false
	if not data.get("loop") is bool or not data.loop: return false
	for key in EXPECTED:
		if not Numbers.integer(data.get(key),EXPECTED[key],EXPECTED[key]): return false
	var origins: Variant = data.get("candidate_origins")
	var bounds: Variant = data.get("coordinate_bounds")
	if not origins is Array or origins.size()!=4 or not bounds is Array or bounds.size()!=3: return false
	for axis in 3:
		if not Numbers.integer(bounds[axis],BOUNDS[axis],BOUNDS[axis]): return false
	for i in 4:
		if not origins[i] is Array or origins[i].size()!=3: return false
		for axis in 3:
			if not Numbers.integer(origins[i][axis],ORIGINS[i][axis],ORIGINS[i][axis]): return false
	return true

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing opening NPC route declaration"
	if data.is_empty(): return ""
	if not parameters(data): return "Unsupported opening NPC route parameters"
	var sizes: Dictionary = SIZES.get(architecture,{})
	if sizes.is_empty() or data.provenance.size()!=sizes.size(): return "Invalid opening NPC route provenance"
	var spans := []
	for key in sizes:
		var row: Variant = data.provenance.get(key)
		# v48 packs retain the older seven-byte-wider Mac signature extent.
		if not Fonts.extent(row,"offset","bytes",([733,726] if architecture=="x86_64" and key=="generation" else [sizes[key]]),executable_bytes): return "Invalid opening NPC route extent: "+key
		var span := Vector2i(int(row.offset),int(row.offset)+int(row.bytes))
		for previous in spans:
			if span.x<previous.y and span.y>previous.x: return "Overlapping opening NPC route extents"
		spans.append(span)
	return ""

const SIZES = {
  "armv7": {
    "advance": 246,
    "advance_wrapper": 14,
    "copy_plain": 46,
    "copy_points": 88,
    "dispatch": 158,
    "fire_gate": 34,
    "generation": 652,
    "loop": 4,
    "near_gate": 20,
    "policy": 118,
    "route": 354,
    "waypoint": 72,
    "waypoint_tail": 30,
    "wrapper": 14,
    "virtual_update": 4,
    "selection": 132,
    "positive_extent": 4,
    "negative_extent": 4
  },
  "x86_64": {
    "advance": 301,
    "advance_wrapper": 24,
    "copy_plain": 38,
    "copy_points": 162,
    "dispatch": 184,
    "fire_gate": 42,
    "generation": 726,
    "loop": 10,
    "near_gate": 30,
    "policy": 111,
    "route": 331,
    "waypoint": 100,
    "wrapper": 10,
    "virtual_update": 8,
    "selection": 119,
    "positive_extent": 4,
    "negative_extent": 4
  }
}
