extends RefCounted
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")

static func parameters(data: Dictionary) -> bool:
	if data.get("fov_axis") != "vertical": return false
	for key in ["vertical_fov_radians", "near", "far", "matching_location_early_far"]:
		var value: Variant = data.get(key)
		if (not value is int and not value is float) or not is_finite(value): return false
	if data.vertical_fov_radians <= 0 or data.vertical_fov_radians >= PI: return false
	if data.near <= 0 or data.far <= data.near or data.matching_location_early_far <= data.near: return false
	if maxf(data.far, data.matching_location_early_far) > 1e9: return false
	return Numbers.integer(data.get("early_cursor_limit"), 0, 2147483647)

static func sizes(architecture: String) -> Dictionary:
	if architecture == "x86_64": return {"start": 102, "setter": 213, "predicate": 26, "compare": 22, "metrics": 250, "cursor": 12, "fov": 4, "near": 4, "fallback": 4, "far": 8}
	if architecture == "armv7": return {"start": 100, "setter": 216, "predicate": 10, "compare": 22, "metrics": 252, "cursor": 6, "fallback": 4, "far": 8}
	return {}

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing flight projection declarations"
	if data.is_empty(): return ""
	if not parameters(data): return "Invalid flight projection parameters"
	var expected := sizes(architecture)
	var provenance: Variant = data.get("provenance")
	if expected.is_empty() or not provenance is Dictionary or provenance.size() != expected.size(): return "Invalid flight projection provenance"
	var spans := []
	for key in expected:
		var row: Variant = provenance.get(key)
		if not Fonts.extent(row, "offset", "bytes", [expected[key]], executable_bytes): return "Invalid flight projection extent: " + key
		var begin := int(row.offset)
		var end := begin + int(row.bytes)
		for span in spans:
			if begin < span.y and end > span.x: return "Overlapping flight projection declarations"
		spans.append(Vector2i(begin, end))
	return ""
