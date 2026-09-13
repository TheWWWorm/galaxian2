extends RefCounted
const Fonts = preload("res://src/content/font_definitions.gd")

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=5: return false
	var scale: Variant=data.get("nonhostile_scale")
	if not (scale is int or scale is float) or scale!=0.20000000298023224: return false
	return data.get("special_flight_multipliers")==[3.0,0.25] and data.get("rounding")=="binary32_then_truncate" and data.get("nonhostile_precedes_special") is bool and data.nonhostile_precedes_special and data.get("provenance") is Dictionary

static func validate(data: Variant, executable_bytes: int, architecture: String, weapon: Dictionary) -> String:
	if not data is Dictionary: return "Missing player hit policy"
	if data.is_empty(): return ""
	if not parameters(data): return "Invalid player hit policy"
	var sizes := {"damage_route":185,"nonhostile":4,"special_first":4,"special_second":4} if architecture=="x86_64" else {"damage_route":120,"scaling_setup":12} if architecture=="armv7" else {}
	if sizes.is_empty() or data.provenance.size()!=sizes.size(): return "Invalid player hit provenance"
	var spans := []
	for key in sizes:
		var row: Variant=data.provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes): return "Invalid player hit extent"
		var span := Vector2i(int(row.offset),int(row.offset)+int(row.bytes))
		for prior in spans:
			if span.x<prior.y and span.y>prior.x: return "Overlapping player hit extents"
		spans.append(span)
	if data.provenance.damage_route!=weapon.get("ordinary_hit_policy",{}).get("provenance",{}).get("damage_route"): return "Player hit policy belongs to another collision route"
	if architecture=="armv7" and int(data.provenance.scaling_setup.offset)!=int(data.provenance.damage_route.offset)-0x344: return "Disconnected player hit scaling registers"
	return ""
