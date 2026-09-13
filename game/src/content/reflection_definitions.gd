extends RefCounted
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")

static func parameters(data: Dictionary) -> bool:
	return Numbers.integer(data.get("texture_base"),0,65533) and Numbers.integer(data.get("special_id"),0,65533)

static func texture_id(data: Dictionary,sky_index: Variant,location_match: Variant) -> int:
	if not parameters(data) or not location_match is bool:return -1
	if location_match:return int(data.special_id)
	if not Numbers.integer(sky_index,0,18):return -1
	# Source lookup narrows the sum to an unsigned 16-bit resource identifier.
	return (int(data.texture_base)+int(sky_index))&65535

static func validate(data: Variant,executable_bytes: int,architecture: String,projection: Dictionary,sky: Dictionary) -> String:
	if not data is Dictionary:return "Missing reflection selection declarations"
	if data.is_empty():return ""
	if data.size()!=3 or not parameters(data):return "Invalid reflection selection parameters"
	var sizes := {"select":94,"bind":330,"predicate":26,"system":13,"sky_index":9,"load_context":7} if architecture=="x86_64" else {"select":94,"bind":240,"predicate":10,"system":6,"sky_index":4,"load_context":6} if architecture=="armv7" else {}
	var provenance: Variant = data.get("provenance")
	if sizes.is_empty() or not provenance is Dictionary or provenance.size()!=sizes.size():return "Invalid reflection selection provenance"
	var spans := []
	for key in sizes:
		var row: Variant = provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes):return "Invalid reflection selection extent: "+key
		var begin := int(row.offset);var end := begin+int(row.bytes)
		for span in spans:
			if begin<span.y and end>span.x:return "Overlapping reflection declarations"
		spans.append(Vector2i(begin,end))
	if provenance.predicate!=projection.get("provenance",{}).get("predicate") or provenance.system!=sky.get("provenance",{}).get("system") or provenance.load_context!=sky.get("provenance",{}).get("texture"):
		return "Reflection selection is not linked to the active location and texture definitions"
	return ""
