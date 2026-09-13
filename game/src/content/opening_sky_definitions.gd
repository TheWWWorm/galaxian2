extends RefCounted
const Numbers = preload("res://src/content/opening_definitions.gd")
const Planets = preload("res://src/content/planet_resource_definitions.gd")
const Flares = preload("res://src/content/sun_flare_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")

static func parameters(data: Dictionary) -> bool:
	for key in ["star_mesh_base","star_texture_base","sky_mesh_id","sky_texture_id"]:
		if not Numbers.integer(data.get(key),0,65533): return false
	return Numbers.integer(data.get("world_type"),3,3) and Numbers.integer(data.get("campaign_cursor"),0,0) and Numbers.integer(data.get("star_variants"),3,3) and data.get("location_match") is bool and not data.location_match

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing opening sky declarations"
	if data.is_empty(): return ""
	if not parameters(data): return "Invalid opening sky parameters"
	if data.has("planet_resources"):
		var message: String=Planets.validate(data.planet_resources,executable_bytes,architecture)
		if not message.is_empty():return message
	if data.has("sun_flares"):
		var message: String=Flares.validate(data.sun_flares,executable_bytes,architecture)
		if not message.is_empty():return message
	var sizes := {"stars":158,"opening":71,"texture":7,"cursor":12,"system":13,"system_id":9} if architecture=="x86_64" else {"stars":134,"opening":62,"texture":6,"cursor":6,"system":6,"system_id":4} if architecture=="armv7" else {}
	var provenance: Variant = data.get("provenance")
	if sizes.is_empty() or not provenance is Dictionary or provenance.size()!=sizes.size(): return "Invalid opening sky provenance"
	var spans := []
	for key in sizes:
		var row: Variant = provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes): return "Invalid opening sky extent: "+key
		var begin := int(row.offset);var end := begin+int(row.bytes)
		for span in spans:
			if begin<span.y and end>span.x: return "Overlapping opening sky declarations"
		spans.append(Vector2i(begin,end))
	if int(provenance.stars.offset)+int(provenance.stars.bytes)!=int(provenance.opening.offset): return "Unlinked opening sky declarations"
	return ""
