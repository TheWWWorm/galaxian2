extends RefCounted
## Imported localization offsets and fixed portrait definitions. No procedural
## appearances or zero-filled source objects are synthesized by this scope.
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing speaker declarations"
	if data.is_empty(): return ""
	if architecture not in ["armv7", "x86_64"]: return "Unsupported speaker declaration architecture"
	if not Numbers.integer(data.get("fixed_speaker_count"), 1, 128): return "Invalid fixed speaker count"
	var count := int(data.fixed_speaker_count)
	if not Numbers.integer(data.get("first_name_id"), 0, 65535 - count) or not Numbers.integer(data.get("agent_speaker_start"), count + 1, 65535) or not Numbers.integer(data.get("procedural_speaker"), 0, count - 1): return "Invalid speaker declaration bounds"
	if not data.get("portraits") is Array or data.portraits.size() != count: return "Incomplete speaker declarations"
	for i in count:
		var row: Variant = data.portraits[i]
		if not row is Dictionary or row.get("speaker_id") != i or row.get("status") not in ["fixed", "procedural", "unavailable"]: return "Invalid speaker portrait record"
		if (row.status == "procedural") != (i == int(data.procedural_speaker)): return "Conflicting procedural speaker"
		if row.status == "fixed":
			if not Numbers.integer(row.get("family"), 0, 255) or not row.get("parts") is Array or row.parts.size() != 4: return "Invalid fixed portrait parts"
			for part in row.parts:
				if not Numbers.integer(part, -1, 255): return "Invalid portrait part index"
			if not Fonts.extent(row, "source_offset", "source_bytes", [20], executable_bytes): return "Invalid portrait definition provenance"
		elif row.size() != 2:
			return "Unavailable portrait contains invented parts"
	var provenance: Variant = data.get("provenance")
	if not provenance is Dictionary or provenance.size() != 4: return "Missing speaker declaration provenance"
	var mac := architecture == "x86_64"
	for spec in [["speaker_selection", 285 if mac else 182], ["name_selection", 248 if mac else 264], ["speaker_getter", 9 if mac else 4], ["portrait_table", count * (8 if mac else 4)]]:
		if not Fonts.extent(provenance.get(spec[0]), "offset", "bytes", [spec[1]], executable_bytes): return "Invalid speaker declaration provenance"
	return ""
