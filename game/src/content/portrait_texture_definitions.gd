extends RefCounted
## Original portrait texture stems, explicit suffix variants and provenance.
## Variants are source composition choices, not automatic device detection.
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")
const VARIANTS := ["baseline", "expanded", "medium", "large"]

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing portrait texture declarations"
	if data.is_empty(): return ""
	if architecture not in ["armv7", "x86_64"] or not data.get("rows") is Array or data.rows.size() != 152:
		return "Invalid portrait texture declarations"
	if not data.get("suffixes") is Dictionary or data.suffixes.size() != VARIANTS.size(): return "Invalid portrait suffix declarations"
	var suffix_values := {}
	for key in VARIANTS:
		var suffix: Variant = data.suffixes.get(key)
		if not suffix is Dictionary or not suffix.get("value") is String or suffix.value.length() > 32: return "Invalid portrait suffix"
		for code in suffix.value.to_utf8_buffer():
			if code != 95 and (code < 48 or code > 57) and (code < 97 or code > 122): return "Unsafe portrait suffix"
		if not Fonts.extent(suffix, "offset", "bytes", [suffix.value.length() + 1], executable_bytes) or suffix_values.has(suffix.value): return "Invalid portrait suffix provenance"
		suffix_values[suffix.value] = true
	if data.suffixes.baseline.value != "": return "Invalid baseline portrait suffix"
	var ids := {}
	var stems := {}
	var previous_end := 0
	var sizes := [163, 181, 187] if architecture == "x86_64" else [322, 330, 336, 338, 354, 364, 370]
	for row in data.rows:
		if not row is Dictionary or not Numbers.integer(row.get("id"), 0, 65534) or ids.has(int(row.id)): return "Conflicting portrait texture ID"
		ids[int(row.id)] = true
		if not row.get("stem") is String or not row.stem.begins_with("data/") or row.stem.length() > 1024 or stems.has(row.stem): return "Invalid portrait filename stem"
		stems[row.stem] = true
		for character in row.stem:
			if character.unicode_at(0) < 32 or character in [".", "\\", ":"]: return "Unsafe portrait filename stem"
		for part in row.stem.split("/"):
			if part.is_empty(): return "Unsafe portrait filename stem"
		if not Fonts.extent(row, "source_offset", "source_bytes", sizes, executable_bytes) or int(row.source_offset) < previous_end: return "Invalid portrait record provenance"
		previous_end = int(row.source_offset) + int(row.source_bytes)
		if not Fonts.extent(row, "stem_offset", "stem_bytes", [row.stem.to_utf8_buffer().size() + 1], executable_bytes) or not Fonts.extent(row, "extension_offset", "extension_bytes", [5], executable_bytes): return "Invalid portrait filename provenance"
		if not row.get("variants") is Dictionary or row.variants.size() != VARIANTS.size(): return "Missing portrait variants"
		for key in VARIANTS:
			if row.variants.get(key) != "resources/" + row.stem + data.suffixes[key].value + ".aei": return "Portrait variant differs from its source declaration"
	var provenance: Variant = data.get("provenance")
	if not provenance is Dictionary or provenance.size() != 1 or not Fonts.extent(provenance.get("selection"), "offset", "bytes", [128] if architecture == "x86_64" else [282], executable_bytes): return "Invalid portrait selection provenance"
	if int(provenance.selection.offset) + int(provenance.selection.bytes) > int(data.rows[0].source_offset): return "Portrait selection overlaps its records"
	return ""
