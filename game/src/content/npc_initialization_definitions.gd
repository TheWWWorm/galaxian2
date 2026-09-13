extends RefCounted
const Hull = preload("res://src/content/npc_hull_definitions.gd")
const WorldInitialization = preload("res://src/content/opening_world_initialization_definitions.gd")
const Construction = preload("res://src/content/npc_construction_definitions.gd")
const Routes = preload("res://src/content/npc_route_definitions.gd")
const Holding = preload("res://src/content/npc_holding_definitions.gd")
const Hostility = preload("res://src/content/npc_hostility_definitions.gd")
const Destruction = preload("res://src/content/npc_destruction_definitions.gd")
const DeathAccounting = preload("res://src/content/npc_death_accounting_definitions.gd")
const Guidance = preload("res://src/content/opening_npc_guidance_definitions.gd")
const Flight = preload("res://src/content/npc_flight_definitions.gd")
const Primary = preload("res://src/content/opening_npc_weapon_definitions.gd")
## Constructor declarations for ordinary NPC ships, not arbitrary actor classes.
const Activation = preload("res://src/content/npc_activation_definitions.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")

static func parameters(data: Dictionary) -> bool:
	for key in ["ordinary_half_extent", "special_half_extent"]:
		if not Numbers.integer(data.get(key), 1, 10000000): return false
	var difficulty: Variant = data.get("special_difficulty")
	if (not difficulty is float and not difficulty is int) or not is_finite(difficulty) or difficulty < 0 or difficulty > 10: return false
	if not Numbers.integer(data.get("initial_armor"),0,0): return false
	var shield: Variant = data.get("initial_shield")
	if (not shield is float and not shield is int) or shield != 0: return false
	for key in ["initial_firing_allowed", "initial_active", "initial_damage_allowed", "is_player", "initial_special_impact_state", "initial_collision_enabled", "initial_point_geometry"]:
		if not data.get(key) is bool: return false
	return true

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing NPC initialization declaration"
	if data.is_empty(): return ""
	if data.has("hull"):
		var hull_error := Hull.validate(data.hull,executable_bytes,architecture,data)
		if not hull_error.is_empty(): return hull_error
	if data.has("death_accounting"):
		var accounting_error := DeathAccounting.validate(data.death_accounting,executable_bytes,architecture,data)
		if not accounting_error.is_empty(): return accounting_error
	if data.has("destruction"):
		var destruction_error := Destruction.validate(data.destruction,executable_bytes,architecture,data)
		if not destruction_error.is_empty(): return destruction_error
	if data.has("destruction_audio"):
		var audio_error := Destruction.validate_audio(data.destruction_audio,executable_bytes,architecture,data)
		if not audio_error.is_empty():return audio_error
	if data.has("hostility"):
		var hostility_error := Hostility.validate(data.hostility,executable_bytes,architecture,data)
		if not hostility_error.is_empty(): return hostility_error
	if data.has("world_initialization"):
		var world_error := WorldInitialization.validate(data.world_initialization,executable_bytes,architecture)
		if not world_error.is_empty(): return world_error
	if data.has("construction"):
		var construction_error := Construction.validate(data.construction,executable_bytes,architecture)
		if not construction_error.is_empty(): return construction_error
	if data.has("routes"):
		var route_error := Routes.validate(data.routes,executable_bytes,architecture)
		if not route_error.is_empty(): return route_error
	if data.has("holding"):
		var holding_error := Holding.validate(data.holding,executable_bytes,architecture)
		if not holding_error.is_empty(): return holding_error
	if data.has("guidance"):
		var guidance_error := Guidance.validate(data.guidance,executable_bytes,architecture)
		if not guidance_error.is_empty(): return guidance_error
	if data.has("flight"):
		var flight_error := Flight.validate(data.flight,executable_bytes,architecture)
		if not flight_error.is_empty(): return flight_error
	if data.has("primary_weapon"):
		var primary_error := Primary.validate(data.primary_weapon, executable_bytes, architecture)
		if not primary_error.is_empty(): return primary_error
	if data.has("activation"):
		var activation_error := Activation.validate(data.activation,executable_bytes,architecture)
		if not activation_error.is_empty(): return activation_error
	if not parameters(data): return "Invalid NPC initialization parameters"
	var sizes := {}
	if architecture == "x86_64":
		sizes = {"opening_deactivation":30,"activity_setter":13,"factory_entry":4,"selection":70,"selector":34,"difficulty_value":4,"stats_wrapper":10,"stats_entry":20,"extent_argument":9,"pools":33,"firing":7,"active":7,"damage":7,"player":4,"ship_call":32,"actor_wrapper":14,"base_call":14,"special_state":4,"collision_enabled":7,"point_geometry":4}
	elif architecture == "armv7":
		sizes = {"opening_deactivation":28,"activity_setter":6,"factory_entry":4,"selection":60,"selector":36,"stats_wrapper":30,"stats_entry":28,"extent_argument":4,"zero_integer":2,"zero_register":4,"pools":28,"flags":88,"ship_call":32,"actor_wrapper":60,"base_call":30,"actor_flags":62,"point_geometry":26}
	var provenance: Variant = data.get("provenance")
	if sizes.is_empty() or not provenance is Dictionary or provenance.size() != sizes.size(): return "Invalid NPC initialization provenance"
	var spans := []
	for key in sizes:
		var row: Variant = provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes): return "Invalid NPC initialization extent"
		var start := int(row.offset)
		var end := start + int(row.bytes)
		for span in spans:
			if start < span.y and end > span.x: return "Overlapping NPC initialization extents"
		spans.append(Vector2i(start,end))
	return ""
