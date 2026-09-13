extends RefCounted
const Numbers = preload("res://src/content/opening_definitions.gd")
const Staging = preload("res://src/content/opening_staging_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")

static func parameters(data: Dictionary) -> bool:
	if data.get("initial_target") != "player" or not data.get("initial_fixed_eye") is bool or data.get("initial_fixed_eye") != true or not data.get("inherit_target_up") is bool: return false
	var cut: Variant = data.get("actor_cut")
	var pan: Variant = data.get("pan")
	if not cut is Dictionary or not pan is Dictionary: return false
	if not Numbers.integer(cut.get("after_event_finished"), 0, 255) or not Numbers.integer(cut.get("actor_id"), 0, 2) or not Staging.vector(cut.get("eye")): return false
	if not Staging.vector(pan.get("velocity_per_ms")) or not Numbers.integer(pan.get("engagement_after_event_finished"), 0, 255) or not Numbers.integer(pan.get("follow_player_after_event_finished"), 0, 255): return false
	return cut.after_event_finished < pan.engagement_after_event_finished and pan.engagement_after_event_finished < pan.follow_player_after_event_finished

static func sizes(architecture: String) -> Dictionary:
	if architecture == "x86_64":
		return {"attach": 135, "cut": 272, "pan2": 189, "pan3": 200, "defaults": 1035, "increment": 88, "mode_setter": 10, "target_setter": 10, "cut_ref_a9": 4, "cut_ref_a1": 4, "pan2_ref_c": 4, "pan2_ref_18": 4, "pan3_ref_1b": 4, "pan3_ref_27": 4}
	if architecture == "armv7":
		return {"attach": 90, "cut": 286, "pan2": 190, "pan3": 220, "defaults": 570, "increment": 72, "route3": 8, "mode_setter": 6, "target_setter": 4, "pan2_literal_6": 4, "pan2_literal_c": 4, "pan3_literal_c": 4, "pan3_literal_14": 4}
	return {}

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing opening camera declarations"
	if data.is_empty(): return ""
	if not parameters(data): return "Invalid opening camera parameters"
	var expected := sizes(architecture)
	var provenance: Variant = data.get("provenance")
	if expected.is_empty() or not provenance is Dictionary or provenance.size() != expected.size(): return "Invalid opening camera provenance"
	var spans := []
	for key in expected:
		var row: Variant = provenance.get(key)
		if not Fonts.extent(row, "offset", "bytes", [expected[key]], executable_bytes): return "Invalid opening camera extent: " + key
		var start := int(row.offset)
		var end := start + int(row.bytes)
		for span in spans:
			if start < span.y and end > span.x and not (expected[key] == 4 and start == span.x and end == span.y): return "Overlapping opening camera declarations"
		spans.append(Vector2i(start, end))
	return ""
