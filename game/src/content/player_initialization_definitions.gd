extends RefCounted
## Fresh player statistics only. Empty declarations preserve older pack support.
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")
const Recharge = preload("res://src/content/player_recharge_definitions.gd")
const Repair = preload("res://src/content/player_repair_definitions.gd")
const VALUES := {"half_extent":1200,"initial_active":true,"initial_damage_allowed":true,
	"is_player":true,"equipment_rule":"last_matching","missing_capacity":0,
	"item_type_value_index":5,"shield_equipment_type":9,"armor_equipment_type":10,
	"shield_property":18,"armor_property":20}

static func parameters(data: Dictionary) -> bool:
	for key in VALUES:
		var value: Variant=data.get(key)
		if VALUES[key] is int:
			if not Numbers.integer(value,VALUES[key],VALUES[key]): return false
		elif typeof(value)!=typeof(VALUES[key]) or value!=VALUES[key]: return false
	return true

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing player initialization declaration"
	if data.is_empty(): return ""
	if not parameters(data): return "Invalid player initialization parameters"
	var sizes := {}
	if architecture=="x86_64":
		sizes={"factory":96,"shield_getter":9,"armor_getter":9,"shield_setter":28,"armor_setter":22,
			"shield_assignment":26,"armor_assignment":26,"reset":8,"loop_initial":37,"loop_next":20,
			"damage_permission":18,"damage_setter":13,"active":7,"equipment_table":120}
	elif architecture=="armv7":
		sizes={"factory":94,"shield_getter":4,"armor_getter":4,"shield_setter":24,"armor_setter":12,
			"shield_assignment":14,"armor_assignment":14,"zero_vector":4,"reset":12,"loop_offset":8,
			"loop_initial":4,"loop_next":14,"damage_permission":16,"damage_setter":6,"active":36,"equipment_table":30}
	var provenance: Variant=data.get("provenance")
	if sizes.is_empty() or not provenance is Dictionary or provenance.size()!=sizes.size(): return "Invalid player initialization provenance"
	var spans := []
	for key in sizes:
		var row: Variant=provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes): return "Invalid player initialization extent"
		var span := Vector2i(int(row.offset),int(row.offset)+int(row.bytes))
		for previous in spans:
			if span.x<previous.y and span.y>previous.x: return "Overlapping player initialization extents"
		spans.append(span)
	if data.has("recharge"):
		var recharge_error := Recharge.validate(data.recharge,executable_bytes,architecture,data)
		if not recharge_error.is_empty(): return recharge_error
	if data.has("repair"):
		var repair_error := Repair.validate(data.repair,executable_bytes,architecture,data)
		if not repair_error.is_empty(): return repair_error
	return ""
