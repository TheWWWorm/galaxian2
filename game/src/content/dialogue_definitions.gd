extends RefCounted
## Source-bound opening and rescue radio declarations. No modal instructions.
const Numbers = preload("res://src/content/opening_definitions.gd")

static func select(bindings: RefCounted, campaign_cursor: int = 0) -> Dictionary:
	match campaign_cursor:
		0: return bindings.opening_dialogue
		1: return bindings.arrival_dialogue
	return {}

static func valid_parameters(data: Dictionary, campaign_cursor: int = 0) -> bool:
	if campaign_cursor not in [0, 1] or not Numbers.integer(data.get("campaign_cursor"), campaign_cursor, campaign_cursor): return false
	var rows: Variant = data.get("events")
	var timing: Variant = data.get("timing")
	if not rows is Array or rows.size() != (23 if campaign_cursor == 0 else 3) or not timing is Dictionary: return false
	if timing.get("display_delay_ms") != 2000 or timing.get("base_duration_ms") != 1500 or timing.get("per_line_ms") != 2000: return false
	for i in rows.size():
		var row: Variant = rows[i]
		if not row is Dictionary or not Numbers.integer(row.get("text_id"), 0, 65535) or not Numbers.integer(row.get("speaker_id"), 0, 65535): return false
		if not Numbers.integer(row.get("condition"), 0, 31) or int(row.condition) not in [5, 6, 9, 27] or not row.get("values") is Array: return false
		if row.values.is_empty() or row.values.size() > 256 or (row.condition != 9 and row.values.size() != 1): return false
		for value in row.values:
			if not Numbers.integer(value, 0, 2147483647): return false
			if row.condition == 6 and (value >= rows.size() or value == i): return false
		if campaign_cursor == 1 and (row.condition != (5 if i == 0 else 6) or (i > 0 and int(row.values[0]) != i - 1)): return false
	return true

static func validate(data: Variant, executable_bytes: int, architecture: String, campaign_cursor: int = 0, opening: Dictionary = {}) -> String:
	if not data is Dictionary: return "Missing opening radio declarations"
	if data.is_empty(): return ""
	if not valid_parameters(data, campaign_cursor): return "Unsupported scene radio declarations"
	var sizes := {}
	if architecture == "x86_64":
		sizes = {"single_constructor": 91, "range_wrapper": 10, "range_constructor": 143, "dispatch": 44, "dispatch_table": 648, "duration": 32, "display_delay": 26}
	elif architecture == "armv7":
		sizes = {"single_constructor": 50, "range_wrapper": 30, "range_constructor": 104, "dispatch": 10, "dispatch_table": 324, "duration": 32, "display_delay": 44}
	if campaign_cursor == 1:
		sizes.erase("range_wrapper"); sizes.erase("range_constructor")
		if architecture == "armv7": sizes.shared_store = 14
	var provenance: Variant = data.get("provenance")
	if sizes.is_empty() or not provenance is Dictionary or provenance.size() != sizes.size() + 1: return "Missing radio provenance"
	var declaration: Variant = provenance.get("declaration")
	if not declaration is Dictionary or not Numbers.integer(declaration.get("bytes"), 1000 if campaign_cursor == 0 else 150, 2048 if campaign_cursor == 0 else 384): return "Invalid radio declaration extent"
	sizes.declaration = int(declaration.bytes)
	for key in sizes:
		var row: Variant = provenance.get(key)
		if not row is Dictionary or row.get("bytes") != sizes[key] or not Numbers.integer(row.get("offset"), 0, executable_bytes - sizes[key]): return "Invalid radio source extent"
	if campaign_cursor == 1:
		for key in ["dispatch", "dispatch_table", "single_constructor", "duration", "display_delay"]:
			if provenance[key] != opening.get("provenance", {}).get(key): return "Rescue radio belongs to another declaration owner"
		if architecture == "armv7":
			var shared: Dictionary = provenance.shared_store
			if shared.offset < declaration.offset + declaration.bytes and declaration.offset < shared.offset + shared.bytes: return "Overlapping rescue radio declarations"
	return ""
