extends RefCounted
const Numbers = preload("res://src/content/opening_definitions.gd")
const Staging = preload("res://src/content/opening_staging_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")

static func parameters(data: Dictionary) -> bool:
	if not Staging.vector(data.get("look_offset")) or not Staging.vector(data.get("eye_offset")): return false
	for key in ["look_rate", "eye_rate", "reciprocal_numerator"]:
		var value: Variant = data.get(key)
		if (not value is int and not value is float) or not is_finite(value) or value <= 0 or value > (100 if key == "reciprocal_numerator" else 1): return false
	var matrix: Variant = data.get("response_matrix")
	if not matrix is Array or matrix.size() != 5: return false
	for row in matrix:
		if not row is Array or row.size() != 9: return false
		for value in row:
			if (not value is int and not value is float) or not is_finite(value) or absf(value) > 1e15: return false
	return true

static func sizes(architecture: String) -> Dictionary:
	if architecture == "x86_64":
		return {"curve": 763, "follow": 1028, "reset": 38, "rate_scale": 119, "scale": 80, "add": 144, "subtract": 128, "point": 240, "attach": 135, "defaults": 1035, "increment": 88, "reset_ref_18": 4, "follow_ref_1e5": 4, "curve_ref_235": 8, "curve_ref_2e8": 8, "curve_ref_289": 8, "curve_ref_2a4": 8, "curve_ref_274": 8, "curve_ref_245": 8, "curve_ref_20f": 8, "curve_ref_1a5": 8, "curve_ref_153": 8, "curve_ref_15f": 8, "curve_ref_2d2": 8, "curve_ref_296": 8, "curve_ref_2b1": 8, "curve_ref_267": 8, "curve_ref_252": 8, "curve_ref_25b": 8, "curve_ref_21f": 8, "curve_ref_180": 8, "curve_ref_188": 8, "curve_ref_27d": 8, "curve_ref_1fe": 8, "curve_ref_1b6": 8, "curve_ref_142": 8, "curve_ref_e3": 8, "curve_ref_90": 8, "curve_ref_7f": 8, "curve_ref_63": 8, "curve_ref_6f": 8, "curve_ref_228": 8, "curve_ref_194": 8, "curve_ref_16f": 8, "curve_ref_d2": 8, "curve_ref_c1": 8, "curve_ref_b1": 8, "curve_ref_a0": 8, "curve_ref_3f": 8, "curve_ref_53": 8, "curve_ref_1e9": 8, "curve_ref_1d8": 8, "curve_ref_1c7": 8, "curve_ref_131": 8, "curve_ref_121": 8, "curve_ref_110": 8, "curve_ref_f4": 8, "curve_ref_100": 8}
	if architecture == "armv7":
		return {"curve": 566, "follow": 594, "reset": 28, "rate_scale": 108, "scale": 72, "add": 80, "subtract": 80, "point": 232, "attach": 90, "defaults": 570, "increment": 72, "curve_literal_1f8": 8, "curve_literal_1cc": 8, "curve_literal_19c": 8, "curve_literal_148": 8, "curve_literal_60": 8, "curve_literal_50": 8, "curve_literal_40": 8, "curve_literal_4": 8, "curve_literal_8": 8, "curve_literal_204": 8, "curve_literal_194": 8, "curve_literal_1a8": 8, "curve_literal_168": 8, "curve_literal_118": 8, "curve_literal_c4": 8, "curve_literal_b8": 8, "curve_literal_ac": 8, "curve_literal_64": 8, "curve_literal_208": 8, "curve_literal_1d0": 8, "curve_literal_158": 8, "curve_literal_164": 8, "curve_literal_128": 8, "curve_literal_e8": 8, "curve_literal_dc": 8, "curve_literal_d0": 8, "curve_literal_84": 8, "curve_literal_1f4": 8, "curve_literal_1bc": 8, "curve_literal_188": 8, "curve_literal_138": 8, "curve_literal_a0": 8, "curve_literal_90": 8, "curve_literal_80": 8, "curve_literal_70": 8, "curve_literal_44": 8, "curve_literal_1e0": 8, "curve_literal_1a4": 8, "curve_literal_174": 8, "curve_literal_120": 8, "curve_literal_114": 8, "curve_literal_108": 8, "curve_literal_f4": 8, "curve_literal_fc": 8}
	return {}

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing camera follow declarations"
	if data.is_empty(): return ""
	if not parameters(data): return "Invalid camera follow parameters"
	var expected := sizes(architecture)
	var provenance: Variant = data.get("provenance")
	if expected.is_empty() or not provenance is Dictionary or provenance.size() != expected.size(): return "Invalid camera follow provenance"
	var spans := []
	for key in expected:
		var row: Variant = provenance.get(key)
		if not Fonts.extent(row, "offset", "bytes", [expected[key]], executable_bytes): return "Invalid camera follow extent: " + key
		var start := int(row.offset)
		var end := start + int(row.bytes)
		for span in spans:
			if start < span.y and end > span.x and not (expected[key] in [4, 8] and start == span.x and end == span.y): return "Overlapping camera follow declarations"
		spans.append(Vector2i(start, end))
	return ""
