extends RefCounted
const EscapeCamera = preload("res://src/content/opening_escape_camera_definitions.gd")
const Escape = preload("res://src/content/opening_escape_definitions.gd")
const NpcScanner = preload("res://src/content/npc_scanner_definitions.gd")
const PlayerAim = preload("res://src/content/player_aim_definitions.gd")
const ProjectileImpacts = preload("res://src/content/projectile_impact_definitions.gd")
const ProjectileVisuals = preload("res://src/content/projectile_visual_definitions.gd")
const PlayerFlight = preload("res://src/content/opening_player_flight_definitions.gd")
const PlayerMotion = preload("res://src/content/opening_player_motion_definitions.gd")
## Source coordinates and a reveal condition, not a resolved camera or mission.
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")

static func vector(value: Variant) -> bool:
	if not value is Array or value.size() != 3: return false
	for v in value:
		if (not v is float and not v is int) or not is_finite(v) or absf(v) > 10000000: return false
	return true

static func axes(forward: Variant, up: Variant) -> bool:
	if not vector(forward) or not vector(up): return false
	var f := Vector3(forward[0], forward[1], forward[2])
	var u := Vector3(up[0], up[1], up[2])
	return is_equal_approx(f.length_squared(), 1.0) and is_equal_approx(u.length_squared(), 1.0) and is_zero_approx(f.dot(u))

static func parameters(data: Dictionary) -> bool:
	var initial: Variant = data.get("initial")
	var formation: Variant = data.get("formation")
	if not initial is Dictionary or not formation is Dictionary: return false
	if not vector(initial.get("player_position")) or not vector(initial.get("camera_position_parameter")) or not axes(initial.get("player_forward"), initial.get("player_up")): return false
	var hidden: Variant = initial.get("hidden_actor_ids")
	if not hidden is Array or hidden.size() != 3: return false
	for i in 3:
		if not Numbers.integer(hidden[i], i, i): return false
	if not vector(formation.get("player_position")) or not vector(formation.get("camera_position_parameter")) or not Numbers.integer(formation.get("after_event_finished"), 0, 255): return false
	var actors: Variant = formation.get("actors")
	if not actors is Array or actors.size() != hidden.size(): return false
	for i in actors.size():
		var row: Variant = actors[i]
		if not row is Dictionary or not Numbers.integer(row.get("actor_id"), i, i) or not vector(row.get("position")) or not axes(row.get("forward"), row.get("up")) or not row.get("visible") is bool: return false
	return true

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing opening staging declarations"
	if data.is_empty(): return ""
	if not parameters(data): return "Invalid opening staging parameters"
	if data.has("player_motion"):
		var motion_error := PlayerMotion.validate(data.player_motion,executable_bytes,architecture,data)
		if not motion_error.is_empty(): return motion_error
	if data.has("escape_camera"):
		var camera_error := EscapeCamera.validate(data.escape_camera,executable_bytes,architecture,data)
		if not camera_error.is_empty():return camera_error
	if data.has("escape"):
		var escape_error := Escape.validate(data.escape,executable_bytes,architecture,data)
		if not escape_error.is_empty():return escape_error
	if data.has("npc_scanner"):
		var scanner_error := NpcScanner.validate(data.npc_scanner,executable_bytes,architecture,data)
		if not scanner_error.is_empty(): return scanner_error
	if data.has("player_aim"):
		var aim_error := PlayerAim.validate(data.player_aim,executable_bytes,architecture,data)
		if not aim_error.is_empty(): return aim_error
	if data.has("projectile_impacts"):
		var impact_error := ProjectileImpacts.validate(data.projectile_impacts,executable_bytes,architecture,data)
		if not impact_error.is_empty(): return impact_error
	if data.has("projectile_visuals"):
		var visual_error := ProjectileVisuals.validate(data.projectile_visuals,executable_bytes,architecture,data)
		if not visual_error.is_empty(): return visual_error
	if data.has("player_flight"):
		var flight_error := PlayerFlight.validate(data.player_flight,executable_bytes,architecture,data)
		if not flight_error.is_empty(): return flight_error
	var sizes := {}
	if architecture == "x86_64":
		sizes = {"initial": 366, "formation": 489, "player_getter": 13, "actor_getter": 13, "event_getter": 13, "cursor_getter": 12, "visibility": 14, "event_finished": 11, "camera_vector": 35, "camera_components": 21, "initial_ref_a3": 4}
		for key in ["72", "7a", "82", "ad", "9d", "a5", "dd", "e5", "ed", "fa", "102", "13a", "11e", "126", "15c", "148", "164"]:
			sizes["formation_ref_" + key] = 4
	elif architecture == "armv7":
		sizes = {"initial": 320, "formation": 424, "initial_dispatch": 58, "update_dispatch": 186, "player_getter": 6, "actor_getter": 6, "event_getter": 6, "cursor_getter": 6, "visibility": 10, "event_finished": 6, "camera_vector": 18, "camera_components": 10}
	var provenance: Variant = data.get("provenance")
	if sizes.is_empty() or not provenance is Dictionary or provenance.size() != sizes.size(): return "Invalid opening staging provenance"
	var spans := []
	for key in sizes:
		var row: Variant = provenance.get(key)
		if not Fonts.extent(row, "offset", "bytes", [sizes[key]], executable_bytes): return "Invalid opening staging extent: " + key
		var start := int(row.offset)
		var end := start + int(row.bytes)
		for span in spans:
			# Multiple scalar operands may refer to the same read-only float.
			if start < span.y and end > span.x and not (sizes[key] == 4 and start == span.x and end == span.y): return "Overlapping opening staging declarations"
		spans.append(Vector2i(start, end))
	return ""
