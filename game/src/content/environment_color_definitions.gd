extends RefCounted
const Fonts = preload("res://src/content/font_definitions.gd")
const COUNTS := {"sun_rgb":19,"planet_rgb":27,"rim_rgb":19}

## v30 mislabeled the rim table. Normalize only that historical schema, without
## changing the source payload or accepting competing declarations.
static func normalize_v30(data: Variant) -> Variant:
	if not data is Dictionary or data.is_empty(): return data
	if not data.has("material_ambient_rgb") or data.has("rim_rgb"): return null
	var old_provenance: Variant = data.get("provenance")
	if not old_provenance is Dictionary: return null
	if not old_provenance.has("material_ambient_rgb") or not old_provenance.has("material") or old_provenance.has("rim_rgb") or old_provenance.has("rim"): return null
	var result: Dictionary = data.duplicate(true)
	if result.has("material_ambient_rgb") and not result.has("rim_rgb"):
		result.rim_rgb = result.material_ambient_rgb
		result.erase("material_ambient_rgb")
	var provenance: Variant = result.get("provenance")
	if provenance is Dictionary:
		for names in [["material_ambient_rgb", "rim_rgb"], ["material", "rim"]]:
			if provenance.has(names[0]) and not provenance.has(names[1]):
				provenance[names[1]] = provenance[names[0]]
				provenance.erase(names[0])
	return result

static func parameters(data: Dictionary) -> bool:
	if data.has("material_ambient_rgb"): return false
	for key in COUNTS:
		var rows: Variant = data.get(key)
		if not rows is Array or rows.size()!=COUNTS[key]: return false
		for row in rows:
			if not row is Array or row.size()!=3: return false
			for value in row:
				if not (value is float or value is int) or not is_finite(float(value)) or value<0 or value>16: return false
	return true

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing environment color declarations"
	if data.is_empty(): return ""
	if data.size()!=COUNTS.size()+1: return "Unexpected environment color declarations"
	if not parameters(data): return "Invalid environment color tables"
	var sizes := {"sun":88,"planet":81,"rim":48,"system":13,"sky_index":9,"station":13,"planet_type":9} if architecture=="x86_64" else {"sun":92,"planet":20,"planet_table":28,"rim":80,"system":6,"sky_index":4,"station":6,"planet_type":4} if architecture=="armv7" else {}
	if sizes.is_empty(): return "Unsupported environment color architecture"
	for key in COUNTS: sizes[key]=COUNTS[key]*12
	var provenance: Variant = data.get("provenance")
	if not provenance is Dictionary or provenance.size()!=sizes.size(): return "Invalid environment color provenance"
	var spans := []
	for key in sizes:
		var row: Variant = provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes): return "Invalid environment color extent: "+key
		var begin := int(row.offset);var end := begin+int(row.bytes)
		for span in spans:
			if begin<span.y and end>span.x: return "Overlapping environment color declarations"
		spans.append(Vector2i(begin,end))
	var sun_end := int(provenance.sun.offset)+int(provenance.sun.bytes)
	if int(provenance.rim.offset)<=sun_end or int(provenance.rim.offset)>=sun_end+2048 or abs(int(provenance.planet.offset)-int(provenance.sun.offset))>=2048: return "Unlinked environment color declarations"
	if architecture=="armv7" and (int(provenance.planet_table.offset)<sun_end or int(provenance.planet_table.offset)>=int(provenance.rim.offset)): return "Unlinked planet color table"
	return ""
