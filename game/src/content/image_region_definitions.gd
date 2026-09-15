extends RefCounted
## Image aliases retain alternative declarations. Texture/atlas selection belongs
## to the source display profile; conflicting alternatives never choose by order.
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing image region declarations"
	if data.is_empty(): return ""
	if architecture not in ["x86_64", "armv7"]: return "Unsupported image region architecture"
	if not data.get("records") is Array or data.records.size() > 10000 or not data.get("ranges") is Array or data.ranges.size() > 1: return "Invalid image region declarations"
	var mac := architecture == "x86_64"
	var extents := {}
	for row in data.records:
		if not row is Dictionary: return "Invalid image region record"
		for key in ["id", "texture_id", "region"]:
			if not Numbers.integer(row.get(key), 0, 65534): return "Invalid image region value"
		if not Fonts.extent(row, "source_offset", "source_bytes", [64, 68] if mac else [82, 90, 94], executable_bytes) or extents.has(int(row.source_offset)): return "Invalid image region provenance"
		extents[int(row.source_offset)] = true
	for row in data.ranges:
		if not row is Dictionary or not Numbers.integer(row.get("count"), 1, 1024) or row.get("region") != 0: return "Invalid image region range"
		for key in ["first_id", "first_texture_id"]:
			if not Numbers.integer(row.get(key), 0, 65535 - int(row.count)): return "Image region range overflows"
		if not Fonts.extent(row, "source_offset", "source_bytes", [106] if mac else [128], executable_bytes): return "Invalid image range provenance"
	return ""

static func candidates(data: Dictionary, identifier: int, texture_id := -1) -> Array:
	if identifier < 0 or identifier > 65534 or texture_id < -1 or texture_id > 65534: return []
	var found := []
	for record in data.get("records", []):
		if int(record.id) == identifier and (texture_id == -1 or int(record.texture_id) == texture_id):
			append_unique(found, int(record.texture_id), int(record.region))
	for sequence in data.get("ranges", []):
		var index := identifier - int(sequence.first_id)
		if index >= 0 and index < int(sequence.count):
			var selected := int(sequence.first_texture_id) + index
			if texture_id == -1 or selected == texture_id: append_unique(found, selected, int(sequence.region))
	return found

static func append_unique(rows: Array, texture_id: int, region: int) -> void:
	var row := {"texture_id": texture_id, "region": region}
	if not rows.has(row): rows.append(row)
