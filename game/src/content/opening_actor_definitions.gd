extends RefCounted
## World-loader declarations precede cinematic repositioning and visibility.
const NPC = preload("res://src/content/npc_initialization_definitions.gd")
const Player = preload("res://src/content/player_initialization_definitions.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")

static func parameters(data: Dictionary) -> bool:
	if not Numbers.integer(data.get("player_current_hull_override"), 1, 2147483647): return false
	var actors: Variant = data.get("actors")
	if not actors is Array or actors.is_empty() or actors.size() > 32: return false
	for i in actors.size():
		var actor: Variant = actors[i]
		if not actor is Dictionary or not Numbers.integer(actor.get("actor_id"), i, i) or not Numbers.integer(actor.get("hull_catalogue_id"), 0, 4095) or not Numbers.integer(actor.get("actor_kind"), 0, 255) or not Numbers.integer(actor.get("current_hull_override"), 1, 2147483647): return false
		var position: Variant = actor.get("position")
		if not position is Array or position.size() != 3: return false
		for component in position:
			if (not component is float and not component is int) or not is_finite(component) or absf(component) > 10000000: return false
	return true

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing opening actor declarations"
	if data.is_empty(): return ""
	if data.has("player_initialization"):
		var player_error := Player.validate(data.player_initialization,executable_bytes,architecture)
		if not player_error.is_empty(): return player_error
	if data.has("npc_initialization"):
		var npc_error := NPC.validate(data.npc_initialization, executable_bytes, architecture)
		if not npc_error.is_empty(): return npc_error
	if not parameters(data): return "Invalid opening actor parameters"
	var sizes := {}
	if architecture == "x86_64": sizes = {"declaration": 413, "dispatch": 43, "cursor_getter": 12, "hull_setter": 30, "position": 4}
	elif architecture == "armv7": sizes = {"declaration": 356, "dispatch": 96, "cursor_getter": 6, "hull_setter": 18}
	var provenance: Variant = data.get("provenance")
	if sizes.is_empty() or not provenance is Dictionary or provenance.size() != sizes.size(): return "Invalid opening actor provenance"
	var spans := []
	for key in sizes:
		var row: Variant = provenance.get(key)
		if not Fonts.extent(row, "offset", "bytes", [sizes[key]], executable_bytes): return "Invalid opening actor declaration extent"
		var start := int(row.offset)
		var end := start + int(row.bytes)
		for span in spans:
			if start < span.y and end > span.x: return "Overlapping opening actor declarations"
		spans.append(Vector2i(start, end))
	return ""
