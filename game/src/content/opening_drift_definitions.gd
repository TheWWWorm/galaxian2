extends RefCounted
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")

static func parameters(data: Dictionary) -> bool:
	if data.get("waveform") != "absolute_sine" or data.get("application") != "per_update_world_y" or data.get("time_unit") != "milliseconds": return false
	for key in ["frequency_per_millisecond", "bias"]:
		var value: Variant = data.get(key)
		if (not value is int and not value is float) or not is_finite(value): return false
	if data.frequency_per_millisecond <= 0 or data.frequency_per_millisecond > 1000 or absf(data.bias) > 1000000: return false
	if not data.get("skip_formation_update") is bool or not data.skip_formation_update or not Numbers.integer(data.get("through_phase"), 0, 255): return false
	var ids: Variant = data.get("actor_ids")
	if not ids is Array or ids.is_empty() or ids.size() > 64: return false
	var found := {}
	for id in ids:
		if not Numbers.integer(id, 0, 63) or found.has(int(id)): return false
		found[int(id)] = true
	return true

static func sizes(architecture: String) -> Dictionary:
	if architecture == "x86_64": return {"cut": 272, "wave": 102, "sine": 33, "elapsed_getter": 13, "translate": 200, "frequency": 4, "bias": 4, "sign": 4}
	if architecture == "armv7": return {"cut": 286, "wave": 110, "sine": 46, "elapsed_getter": 6, "translate": 160}
	return {}

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing opening drift declarations"
	if data.is_empty(): return ""
	if not parameters(data): return "Invalid opening drift parameters"
	var expected := sizes(architecture)
	var provenance: Variant = data.get("provenance")
	if expected.is_empty() or not provenance is Dictionary or provenance.size() != expected.size(): return "Invalid opening drift provenance"
	var spans := []
	for key in expected:
		var row: Variant = provenance.get(key)
		if not Fonts.extent(row, "offset", "bytes", [expected[key]], executable_bytes): return "Invalid opening drift extent: " + key
		var begin := int(row.offset)
		var end := begin + int(row.bytes)
		for span in spans:
			if begin < span.y and end > span.x: return "Overlapping opening drift declarations"
		spans.append(Vector2i(begin, end))
	return ""
