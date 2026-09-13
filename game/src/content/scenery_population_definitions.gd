extends RefCounted
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")

static func parameters(data: Variant) -> bool:
	return data is Dictionary and data.size()==3 and Numbers.integer(data.get("count_base"),0,4096) and Numbers.integer(data.get("count_bound"),1,4096) and data.count_base+data.count_bound<=8192 and data.get("provenance") is Dictionary

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing scenery population declarations"
	if data.is_empty(): return ""
	if not parameters(data): return "Invalid scenery population parameters"
	var sizes := {"count":66,"station":13,"station_id":9,"seed":69,"draw":171,"bits":93} if architecture=="x86_64" else {"count":70,"station":6,"station_id":4,"seed":72,"draw":114,"bits":126} if architecture=="armv7" else {}
	if sizes.is_empty() or data.provenance.size()!=sizes.size(): return "Invalid scenery population provenance"
	var spans := []
	for key in sizes:
		var row: Variant = data.provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes): return "Invalid scenery population extent: "+key
		var span := Vector2i(int(row.offset),int(row.offset)+int(row.bytes))
		for previous in spans:
			if span.x<previous.y and span.y>previous.x: return "Overlapping scenery population extents"
		spans.append(span)
	return ""
