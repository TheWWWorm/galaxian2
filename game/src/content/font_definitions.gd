extends RefCounted
## Imported font records, source language IDs, spacing and atlas branch choices.
const Numbers = preload("res://src/content/opening_definitions.gd")
const MODES := ["baseline", "medium", "baseline", "large"]

static func parameters(data: Dictionary) -> bool:
	if not data.get("records") is Array or data.records.size() != 8: return false
	var fonts := {}
	var texture_ids := {}
	for row in data.records:
		if not row is Dictionary or not Numbers.integer(row.get("id"), 0, 65534) or not Numbers.integer(row.get("texture_id"), 0, 65534) or not Numbers.integer(row.get("font_group"), 0, 31): return false
		if fonts.has(int(row.id)): return false
		fonts[int(row.id)] = true
		texture_ids[int(row.texture_id)] = true
	var languages: Variant = data.get("languages")
	if not languages is Dictionary or not languages.get("rows") is Array or languages.rows.size() != 16: return false
	var names := {}
	for i in 16:
		var row: Variant = languages.rows[i]
		if not row is Dictionary or row.get("language_id") != i or not row.get("file") is String: return false
		var name: String = row.file
		if not name.ends_with(".lang") or name.length() not in [7, 8] or names.has(name): return false
		for code in name.trim_suffix(".lang").to_utf8_buffer():
			if code < 97 or code > 122: return false
		names[name] = true
	var selection: Variant = data.get("selection")
	if not selection is Dictionary: return false
	var used := {}
	for key in ["default_font_id", "secondary_font_id", "language_font_id"]:
		if not Numbers.integer(selection.get(key), 0, 65534) or not fonts.has(int(selection[key])): return false
		used[int(selection[key])] = true
	if not selection.get("overrides") is Array or selection.overrides.size() != 5: return false
	var language_ids := [9, 10, 11, 14, 15]
	for i in 5:
		var row: Variant = selection.overrides[i]
		if not row is Dictionary or row.get("language_id") != language_ids[i] or not Numbers.integer(row.get("font_id"), 0, 65534) or not fonts.has(int(row.font_id)): return false
		used[int(row.font_id)] = true
	if used.size() != fonts.size() or not selection.get("spacing") is Dictionary: return false
	for key in ["default", "cjk", "japanese"]:
		var row: Variant = selection.spacing.get(key)
		if not row is Array or row.size() != 4: return false
		for value in row:
			if not Numbers.integer(value, -32, 32): return false
	var textures: Variant = data.get("textures")
	if not textures is Dictionary or not textures.get("rows") is Array or textures.rows.size() != texture_ids.size(): return false
	var seen := {}
	for row in textures.rows:
		if not row is Dictionary or not Numbers.integer(row.get("texture_id"), 0, 65534) or not texture_ids.has(int(row.texture_id)) or seen.has(int(row.texture_id)): return false
		seen[int(row.texture_id)] = true
		if not row.get("variants") is Dictionary or row.variants.size() != 3 or not row.get("source_offsets") is Dictionary or row.source_offsets.size() != 3: return false
		var paths := {}
		for mode in ["baseline", "medium", "large"]:
			var path: Variant = row.variants.get(mode)
			if not path is String or path.is_empty() or paths.has(path): return false
			paths[path] = true
	return true

static func extent(row: Variant, offset_key: String, size_key: String, sizes: Array, executable_bytes: int) -> bool:
	return row is Dictionary and Numbers.integer(row.get(size_key), 1, executable_bytes) and int(row[size_key]) in sizes and Numbers.integer(row.get(offset_key), 0, executable_bytes - int(row[size_key]))

static func validate(data: Variant, executable_bytes: int, architecture: String, registrations: Dictionary) -> String:
	if not data is Dictionary: return "Missing font declarations"
	if data.is_empty(): return ""
	if architecture not in ["armv7", "x86_64"] or not parameters(data): return "Invalid font declarations"
	var mac := architecture == "x86_64"
	for row in data.records:
		if not extent(row, "source_offset", "source_bytes", [57] if mac else [84, 86], executable_bytes): return "Invalid font record extent"
	for row in data.languages.rows:
		if not extent(row, "source_offset", "source_bytes", [18, 21] if mac else [22], executable_bytes) or not extent(row, "string_offset", "string_bytes", [row.file.length() + 1], executable_bytes): return "Invalid font language extent"
	var provenance: Variant = data.languages.get("provenance")
	if not provenance is Dictionary or provenance.size() != 2 or not extent(provenance.get("dispatch"), "offset", "bytes", [46] if mac else [20], executable_bytes) or not extent(provenance.get("table"), "offset", "bytes", [64] if mac else [32], executable_bytes): return "Invalid font language dispatch"
	if not extent(data.selection, "source_offset", "source_bytes", [578] if mac else [544], executable_bytes): return "Invalid font selection extent"
	provenance = data.textures.get("provenance")
	if not provenance is Dictionary or provenance.size() != 2 or not extent(provenance.get("medium"), "offset", "bytes", [16] if mac else [20], executable_bytes) or not extent(provenance.get("large"), "offset", "bytes", [31] if mac else [38], executable_bytes): return "Invalid font atlas branch extent"
	for row in data.textures.rows:
		for mode in ["baseline", "medium", "large"]:
			if not Numbers.integer(row.source_offsets.get(mode), 0, executable_bytes - 1): return "Invalid font atlas registration extent"
		if not row.source_offsets.medium < row.source_offsets.large or not row.source_offsets.large < row.source_offsets.baseline: return "Font atlas branches are out of order"
		var original: Array = registrations.get(int(row.texture_id), [])
		if original.size() != 3: return "Missing or ambiguous font atlas registrations"
		for mode in ["baseline", "medium", "large"]:
			var matches := 0
			for source in original:
				if source.kind == "texture" and source.registration_type == 2 and source.resource == row.variants[mode] and source.source_offset == row.source_offsets.get(mode): matches += 1
			if matches != 1: return "Font atlas does not match its source registration"
	return ""

static func choice(data: Dictionary, language: String, source_mode: int, role := "main") -> Dictionary:
	if source_mode < 0 or source_mode >= MODES.size() or role not in ["main", "secondary", "language_list"] or not parameters(data): return {}
	var language_id := -1
	for row in data.languages.rows:
		if row.file == language + ".lang": language_id = int(row.language_id)
	if language_id < 0: return {}
	var selection: Dictionary = data.selection
	var font_id := int(selection.default_font_id)
	var spacing := 0
	if role == "main":
		for row in selection.overrides:
			if row.language_id == language_id: font_id = int(row.font_id)
		var family := "japanese" if language_id == 15 else "cjk" if language_id in [9, 10, 11, 14] else "default"
		spacing = int(selection.spacing[family][source_mode])
	else: font_id = int(selection.secondary_font_id if role == "secondary" else selection.language_font_id)
	for row in data.records:
		if row.id != font_id: continue
		for texture in data.textures.rows:
			if texture.texture_id == row.texture_id:
				return {"font_id": font_id, "texture_id": int(row.texture_id), "font_group": int(row.font_group), "resource": texture.variants[MODES[source_mode]], "spacing": spacing, "source_mode": source_mode, "language_id": language_id}
	return {}
