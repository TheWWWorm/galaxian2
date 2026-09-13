extends RefCounted
## Declarative handling conversion and equipment selection; no loadout ownership.

static func valid_parameters(data: Dictionary) -> bool:
	if data.get("equipment_rule") != "last_matching" or data.get("item_type_value_index") != 5: return false
	for key in ["base_add", "base_divisor", "base_scale", "base_offset", "upgrade_bonus", "percent_divisor", "response_scale"]:
		var value: Variant = data.get(key)
		var maximum := 10000.0 if key in ["percent_divisor", "response_scale"] else (10.0 if key == "upgrade_bonus" else 100.0)
		if not (value is int or value is float) or not is_finite(value) or absf(value) > maximum: return false
		if key not in ["base_add", "base_offset"] and value <= 0: return false
	for key in ["upgrade_tag", "equipment_type", "equipment_percent_property"]:
		var value: Variant = data.get(key)
		var maximum := 255 if key == "upgrade_tag" else (29 if key == "equipment_type" else 65535)
		if not (value is int or value is float) or not is_finite(value) or value != floor(value) or value < 0 or value > maximum: return false
	return true

static func provenance_sizes(architecture: String) -> Dictionary:
	if architecture == "armv7":
		return {"handling_getter": 66, "upgrade_bonus": 4, "response_setup": 44, "equipment_getter": 4,
			"percent_divisor": 4, "response_scale": 4, "handling_setup": 8, "percent_load": 4,
			"equipment_assignment": 14, "property_getter": 48, "equipment_selector": 14,
			"type_getter": 4, "equipment_table": 30, "item_type_layout": 26}
	if architecture == "x86_64":
		return {"handling_getter": 105, "upgrade_bonus": 4, "base_add": 4, "base_divisor": 4, "base_scale": 4,
			"base_offset": 4, "response_setup": 60, "equipment_getter": 9, "percent_divisor": 4, "response_scale": 4,
			"handling_setup": 13, "equipment_assignment": 26, "property_getter": 42, "equipment_selector": 25,
			"type_getter": 9, "equipment_table_load": 7, "equipment_table": 120, "item_type_layout": 42}
	return {}

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Invalid vehicle response definitions"
	if data.is_empty(): return ""
	if not valid_parameters(data): return "Unsupported vehicle response parameters"
	if architecture == "armv7" and [data.base_add, data.base_divisor, data.base_scale, data.base_offset] != [0.0, 1.0, 1.0, 0.0]:
		return "ARM direct-base handling has an unsupported conversion"
	var sizes := provenance_sizes(architecture)
	if sizes.is_empty() or not data.get("provenance") is Dictionary or data.provenance.size() != sizes.size():
		return "Missing vehicle response provenance"
	for key in sizes:
		var row: Variant = data.provenance.get(key)
		if not row is Dictionary or row.get("bytes") != sizes[key]: return "Unsupported vehicle reader layout"
		var offset: Variant = row.get("offset")
		if not (offset is int or offset is float) or not is_finite(offset) or offset != floor(offset) \
				or offset < 0 or offset > executable_bytes - sizes[key]: return "Invalid vehicle source extent"
	return ""
