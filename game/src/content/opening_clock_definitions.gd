extends RefCounted
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")

static func parameters(data: Dictionary) -> bool:
	return data.get("time_unit") == "milliseconds" and data.get("advance_before_controller") is bool and data.advance_before_controller and Numbers.integer(data.get("initial_elapsed_ms"), 0, 2147483647)

static func sizes(architecture: String) -> Dictionary:
	if architecture == "x86_64": return {"reset": 51, "frame": 33, "increment": 13, "getter": 13}
	if architecture == "armv7": return {"reset": 74, "frame": 34, "increment": 18, "getter": 6}
	return {}

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing opening clock declarations"
	if data.is_empty(): return ""
	if not parameters(data): return "Invalid opening clock parameters"
	var expected := sizes(architecture)
	var provenance: Variant = data.get("provenance")
	if expected.is_empty() or not provenance is Dictionary or provenance.size() != expected.size(): return "Invalid opening clock provenance"
	var spans := []
	for key in expected:
		var row: Variant = provenance.get(key)
		if not Fonts.extent(row, "offset", "bytes", [expected[key]], executable_bytes): return "Invalid opening clock extent: " + key
		var begin := int(row.offset)
		var end := begin + int(row.bytes)
		for span in spans:
			if begin < span.y and end > span.x: return "Overlapping opening clock declarations"
		spans.append(Vector2i(begin, end))
	return ""
