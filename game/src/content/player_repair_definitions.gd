extends RefCounted
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")
const VALUES = {"equipment_type":15,"item_type_value_index":5,"item_id_value_index":1,"slow_item_id":75,"missing_device_mode":-1,
	"hull_periods_ms":[600,420],"armor_periods_ms":[1000,700],"hull_amount":1,"armor_amount":2,
	"initial_elapsed_ms":0,"base_hull_field":1,"upgrade_tag":0,"upgrade_bonus":40,
	"initial_upgrades":[],"after_shield_recharge":true,"requires_full_hull_for_armor":true,"discard_excess_time":true}
const SIZES = {"x86_64":{"update":244,"device_getter":9,"hull_max":12,"hull_add":35,"armor_current":12,"armor_max":12,"armor_add":41,"timers_zero":22,"device_assignment":35,"device_zero":8,"item_id":8,"hull_source":59,"stats_capacity":12,"ship_clone":148,"ship_ctor":240,"periods":16},"armv7":{"update":286,"device_getter":4,"hull_max":6,"hull_add":20,"armor_current":6,"armor_max":6,"armor_add":20,"timers_zero":8,"device_assignment":26,"device_zero":28,"item_id":4,"hull_source":50,"stats_capacity":18,"ship_clone":216,"ship_ctor":212,"periods":16}}

static func parameters(data: Dictionary) -> bool:
	if data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary: return false
	for key in VALUES:
		var value: Variant=data.get(key)
		if VALUES[key] is int:
			if not Numbers.integer(value,VALUES[key],VALUES[key]): return false
		elif VALUES[key] is bool:
			if not value is bool or value!=VALUES[key]: return false
		else:
			if not value is Array or value.size()!=VALUES[key].size(): return false
			for index in value.size():
				if not Numbers.integer(value[index],VALUES[key][index],VALUES[key][index]): return false
	return true

static func validate(data: Variant, executable_bytes: int, architecture: String, player: Dictionary) -> String:
	if not data is Dictionary: return "Missing player repair declaration"
	if data.is_empty(): return ""
	if not parameters(data): return "Invalid player repair parameters"
	var sizes: Dictionary=SIZES.get(architecture,{})
	if sizes.is_empty() or data.provenance.size()!=sizes.size(): return "Invalid repair provenance"
	var spans := []
	for key in sizes:
		var row: Variant=data.provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes): return "Invalid repair source extent"
		var span := Vector2i(int(row.offset),int(row.offset)+int(row.bytes))
		for prior in spans:
			if span.x<prior.y and span.y>prior.x: return "Overlapping repair source extents"
		spans.append(span)
	var recharge: Variant=player.get("recharge")
	if not recharge is Dictionary or not recharge.get("provenance") is Dictionary: return "Repair requires shield recharge ordering"
	for key in ["recharge","clock_zero"]:
		if not Fonts.extent(recharge.provenance.get(key),"offset","bytes",[94,110] if key=="recharge" else [11,8],executable_bytes): return "Invalid repair ordering anchor"
	if int(data.provenance.update.offset)!=int(recharge.provenance.recharge.offset)+int(recharge.provenance.recharge.bytes): return "Repair is disconnected from shield recharge"
	if int(data.provenance.timers_zero.offset)+int(data.provenance.timers_zero.bytes)!=int(recharge.provenance.clock_zero.offset): return "Repair clocks are disconnected"
	return ""
