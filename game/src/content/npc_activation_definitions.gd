extends RefCounted
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")

static func parameters(data: Dictionary) -> bool:
	if not Numbers.integer(data.get("after_event_finished"),0,255) or not Numbers.integer(data.get("phase"),3,3): return false
	if data.get("active") != true or not data.get("active") is bool or not Numbers.integer(data.get("actor_mode"),1,1): return false
	if not Numbers.integer(data.get("spatial_half_extent"),1,10000000): return false
	var ids: Variant = data.get("actor_ids")
	if not ids is Array or ids.is_empty() or ids.size()>32: return false
	var unique := {}
	for id in ids:
		if not Numbers.integer(id,0,31) or unique.has(int(id)): return false
		unique[int(id)]=true
	return true

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing NPC activation declaration"
	if data.is_empty(): return ""
	if not parameters(data): return "Invalid NPC activation parameters"
	var sizes := {}
	if architecture=="x86_64": sizes={"cue":189,"actor_wrapper":14,"table_initializer":11,"virtual_activation":8,"activation":33,"activity_setter":13}
	elif architecture=="armv7": sizes={"cue":190,"actor_wrapper":60,"table_initializer":18,"virtual_activation":4,"activation":20,"activity_setter":6}
	var provenance: Variant = data.get("provenance")
	if sizes.is_empty() or not provenance is Dictionary or provenance.size()!=sizes.size(): return "Invalid NPC activation provenance"
	var spans := []
	for key in sizes:
		var row: Variant = provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes): return "Invalid NPC activation extent"
		var start := int(row.offset)
		var end := start+int(row.bytes)
		for span in spans:
			if start<span.y and end>span.x: return "Overlapping NPC activation extents"
		spans.append(Vector2i(start,end))
	return ""
