extends RefCounted
const Fonts = preload("res://src/content/font_definitions.gd")

static func parameters(data: Variant) -> bool:
	return data is Dictionary and (data.is_empty() or (data.size()==2 and data.get("mode")=="target" and data.get("provenance") is Dictionary))

static func resolved(data: Variant) -> bool:
	return data is Dictionary and data.size()==1 and data.get("mode")=="target"

static func validate(data: Variant, executable_bytes: int, architecture: String, weapon: Dictionary) -> String:
	if not parameters(data): return "Invalid weapon collision bounds"
	if data.is_empty(): return ""
	var sizes := {"constructor_call":70,"wrapper":10,"constructor_entry":4,"default":7,"selector":44} if architecture=="x86_64" else {"constructor_call":72,"wrapper":92,"constructor_entry":4,"default":184,"selector":22} if architecture=="armv7" else {}
	var p: Dictionary = data.provenance
	if sizes.is_empty() or p.size()!=sizes.size(): return "Invalid weapon collision bounds provenance"
	var spans := []
	for key in sizes:
		var row: Variant = p.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes): return "Invalid weapon collision bounds extent"
		var span := Vector2i(int(row.offset),int(row.offset)+int(row.bytes))
		for previous in spans:
			if span.x<previous.y and span.y>previous.x: return "Overlapping weapon collision bounds extents"
		spans.append(span)
	if p.constructor_call!=weapon.get("projectile_capacity",{}).get("provenance",{}).get("constructor_call"):
		return "Weapon bounds belong to another ordinary constructor"
	var gate: Variant = weapon.get("ordinary_hit_policy",{}).get("provenance",{}).get("additional_gate")
	if not gate is Dictionary or int(p.selector.offset)!=int(gate.offset)+(0x4d9 if architecture=="x86_64" else -0x26a):
		return "Weapon bounds belong to another collision path"
	if int(p.default.offset)!=int(p.constructor_entry.offset)+(0x349 if architecture=="x86_64" else 0x1e8):
		return "Disconnected weapon bounds constructor default"
	return ""
