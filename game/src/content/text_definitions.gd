extends RefCounted
## Source language-loader aliases affect glyph selection, never saved Unicode text.
const Numbers = preload("res://src/content/opening_definitions.gd")

static func valid_parameters(data: Dictionary) -> bool:
	var rows: Variant = data.get("aliases")
	if not rows is Array or rows.size() != 20: return false
	var seen := {}
	for row in rows:
		if not row is Array or row.size() != 2: return false
		for code in row:
			if not Numbers.integer(code, 33, 65535) or (code >= 0xd800 and code <= 0xdfff): return false
		if seen.has(int(row[0])): return false
		seen[int(row[0])] = true
	return true

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing text alias declarations"
	if data.is_empty(): return ""
	if not valid_parameters(data): return "Invalid text aliases"
	var sizes := {}
	if architecture == "x86_64": sizes = {"declaration": 602, "switch_table": 88}
	elif architecture == "armv7": sizes = {"declaration": 438, "switch_table": 22}
	var provenance: Variant = data.get("provenance")
	if sizes.is_empty() or not provenance is Dictionary or provenance.size() != sizes.size(): return "Missing text alias provenance"
	for key in sizes:
		var row: Variant = provenance.get(key)
		if not row is Dictionary or row.get("bytes") != sizes[key] or not Numbers.integer(row.get("offset"), 0, executable_bytes - sizes[key]): return "Invalid text alias source extent"
	return ""
