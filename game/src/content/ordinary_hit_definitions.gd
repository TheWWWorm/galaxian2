extends RefCounted
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")

static func parameters(data: Variant) -> bool:
	if not data is Dictionary: return false
	if data.is_empty(): return true
	return data.size()==4 and Numbers.integer(data.get("additional_damage_property"),0,65535) \
		and Numbers.integer(data.get("missing_additional_damage"),-2147483648,-1) \
		and (data.get("nonplayer_damage_scale") is float or data.get("nonplayer_damage_scale") is int) \
		and data.nonplayer_damage_scale==1.0 and data.get("provenance") is Dictionary

static func validate(data: Variant, executable_bytes: int, architecture: String, weapon: Dictionary) -> String:
	if not parameters(data): return "Invalid ordinary hit policy"
	if data.is_empty(): return ""
	var sizes := {"classification":65,"additional_store":21,"property_getter":42,"additional_gate":34,"damage_route":185,"normal_hit":23} if architecture=="x86_64" else {"classification":56,"additional_store":10,"property_getter":48,"additional_gate":28,"damage_route":120,"normal_hit":40} if architecture=="armv7" else {}
	var p: Dictionary = data.provenance
	if sizes.is_empty() or p.size()!=sizes.size(): return "Invalid ordinary hit provenance"
	var spans := []
	for key in sizes:
		var row: Variant = p.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes): return "Invalid ordinary hit extent"
		var span := Vector2i(int(row.offset),int(row.offset)+int(row.bytes))
		for previous in spans:
			if span.x<previous.y and span.y>previous.x: return "Overlapping ordinary hit extents"
		spans.append(span)
	if p.classification!=weapon.get("launch_modes",{}).get("provenance",{}).get("classification") or p.property_getter!=weapon.get("provenance",{}).get("property_getter"):
		return "Ordinary hit policy belongs to another weapon catalogue"
	if int(p.additional_store.offset)!=int(p.classification.offset)+int(p.classification.bytes) or int(p.damage_route.offset)!=int(p.additional_gate.offset)+int(p.additional_gate.bytes):
		return "Disconnected ordinary hit declarations"
	return ""

static func resolved(data: Variant, damage: int) -> bool:
	return data is Dictionary and data.size()==3 \
		and data.get("additional_damage_required") is bool \
		and data.get("additional_damage") is int \
		and data.additional_damage>=-2147483648 and data.additional_damage<=2147483647 \
		and data.get("nonplayer_damage") is int and data.nonplayer_damage==damage
