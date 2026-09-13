extends RefCounted
## Explicit source placement variants. Physical display selection is separate.
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")
const Textures = preload("res://src/content/portrait_texture_definitions.gd")

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing portrait layer declarations"
	if data.is_empty(): return ""
	if architecture not in ["x86_64", "armv7"]: return "Unsupported portrait layer architecture"
	if not data.get("part_bases") is Array or data.part_bases.size() != 13: return "Invalid portrait families"
	for family in data.part_bases:
		if not family is Array or family.size() != 4: return "Invalid portrait family parts"
		for id in family:
			if not Numbers.integer(id, -1, 65534): return "Invalid portrait part image ID"
	if not data.get("draw_order") is Array or data.draw_order.size() != 4: return "Unsupported portrait layer order"
	for i in 4:
		if not Numbers.integer(data.draw_order[i], 0, 3) or int(data.draw_order[i]) != [2, 1, 0, 3][i]: return "Unsupported portrait layer order"
	if not data.get("variants") is Dictionary or data.variants.size() != 4: return "Missing portrait placement variants"
	for variant in Textures.VARIANTS:
		var families: Variant = data.variants.get(variant)
		if not families is Array or families.size() != 13: return "Invalid portrait placement families"
		for family in families:
			if not family is Array or family.size() != 4: return "Invalid portrait layer placements"
			for layer in family:
				if not layer is Dictionary or not Numbers.integer(layer.get("anchor"), 0, 32) or int(layer.anchor) not in [0, 16, 32] or not Numbers.integer(layer.get("y"), -8192, 8192): return "Unsupported portrait layer placement"
	var provenance: Variant = data.get("provenance")
	if not provenance is Dictionary or provenance.size() != 7: return "Invalid portrait layer provenance"
	var sizes := {"selection": 316 if architecture == "x86_64" else 382, "order": 61 if architecture == "x86_64" else 56, "part_bases": 208}
	for variant in Textures.VARIANTS: sizes[variant] = 416
	var spans := []
	for key in sizes:
		var row: Variant = provenance.get(key)
		if not Fonts.extent(row, "offset", "bytes", [sizes[key]], executable_bytes): return "Invalid portrait table extent"
		var start := int(row.offset)
		var end := start + int(row.bytes)
		for span in spans:
			if start < span.y and end > span.x: return "Overlapping portrait declarations"
		spans.append(Vector2i(start, end))
	return ""

static func plan(data: Dictionary, portrait: Dictionary, variant: String) -> Dictionary:
	if data.is_empty() or not data.get("variants", {}).has(variant): return {"error": "Portrait placement variant is unavailable"}
	if portrait.get("status") != "fixed" or not Numbers.integer(portrait.get("family"), 0, data.part_bases.size() - 1): return {"error": "Portrait family has no supported layer definitions"}
	var parts: Variant = portrait.get("parts")
	if not parts is Array or parts.size() != 4: return {"error": "Invalid fixed portrait parts"}
	var family := int(portrait.family)
	var result := []
	for part_value in data.draw_order:
		var part := int(part_value)
		if not Numbers.integer(parts[part], -1, 255): return {"error": "Invalid portrait part index"}
		var base := int(data.part_bases[family][part])
		if base == -1 or int(parts[part]) == -1: continue
		var id := base + int(parts[part])
		if id > 65534: return {"error": "Portrait part image ID overflows"}
		var position: Dictionary = data.variants[variant][family][part]
		result.append({"part": int(part), "image_id": id, "anchor": int(position.anchor), "y": int(position.y)})
	if result.is_empty(): return {"error": "Portrait contains no supported layers"}
	return {"layers": result}
