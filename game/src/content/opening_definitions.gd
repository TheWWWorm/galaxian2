extends RefCounted
## Import-time opening loadout seed. Mission triggers and scene state are separate.

static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value == floor(value) and value >= low and value <= high

static func valid_parameters(data: Dictionary) -> bool:
	if not integer(data.get("ship_id"), 0, 4095) or not integer(data.get("station_id"), 0, 4095) or data.get("item_category_value_index") != 3:
		return false
	var rows: Variant = data.get("equipment")
	if not rows is Array or rows.size() != 7: return false
	for row in rows:
		if not row is Dictionary or not integer(row.get("item_id"), 0, 4095) or not integer(row.get("slot"), 0, 255) or not integer(row.get("quantity"), 1, 2147483647):
			return false
	return true

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing opening loadout declarations"
	if data.is_empty(): return ""
	if not valid_parameters(data): return "Unsupported opening loadout declarations"
	var sizes := {}
	if architecture == "x86_64":
		sizes = {"declaration": 376, "item_clone": 31, "stack_clone": 30, "install_category": 57, "category_getter": 9, "ship_clone": 27}
	elif architecture == "armv7":
		sizes = {"declaration": 284, "item_clone": 18, "stack_clone": 18, "install_category": 14, "category_getter": 4, "slot_offsets": 26, "ship_clone": 18}
	if sizes.is_empty() or not data.get("provenance") is Dictionary or data.provenance.size() != sizes.size():
		return "Missing opening loadout provenance"
	for key in sizes:
		var row: Variant = data.provenance.get(key)
		if not row is Dictionary or row.get("bytes") != sizes[key] or not integer(row.get("offset"), 0, executable_bytes - sizes[key]):
			return "Invalid opening loadout source extent"
	return ""
