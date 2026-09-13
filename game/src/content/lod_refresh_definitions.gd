extends RefCounted
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")

static func parameters(data: Dictionary) -> bool:
	return Numbers.integer(data.get("initial_milliseconds"),0,1000000) and Numbers.integer(data.get("refresh_at_milliseconds"),1,1000000) and Numbers.integer(data.get("reset_milliseconds"),0,0) and data.get("time_unit")=="milliseconds" and data.get("forced_refresh_resets_clock") is bool and not data.forced_refresh_resets_clock

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing LOD refresh declarations"
	if data.is_empty(): return ""
	if not parameters(data): return "Invalid LOD refresh parameters"
	var sizes := {"initial":11,"tick":35,"batch":222} if architecture=="x86_64" else {"initial":14,"tick":24,"batch":168} if architecture=="armv7" else {}
	var provenance: Variant = data.get("provenance")
	if sizes.is_empty() or not provenance is Dictionary or provenance.size()!=sizes.size(): return "Invalid LOD refresh provenance"
	var spans := []
	for key in sizes:
		var row: Variant = provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes): return "Invalid LOD refresh extent: "+key
		var begin := int(row.offset);var end := begin+int(row.bytes)
		for span in spans:
			if begin<span.y and end>span.x: return "Overlapping LOD refresh declarations"
		spans.append(Vector2i(begin,end))
	return ""
