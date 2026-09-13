extends RefCounted
## Synthetic font declarations; no original glyphs, strings or texture files.
static func definition(baseline: String, medium: String, large: String) -> Dictionary:
	var records := []
	for i in 8: records.append({"id": 500 + i, "texture_id": 17, "font_group": 1 if i == 1 else 0, "source_offset": i * 60, "source_bytes": 57})
	var languages := {"rows": [], "provenance": {"dispatch": {"offset": 0, "bytes": 46}, "table": {"offset": 50, "bytes": 64}}}
	for i in 16: languages.rows.append({"language_id": i, "file": "a" + String.chr(97 + i) + ".lang", "source_offset": 0, "source_bytes": 18, "string_offset": i * 10, "string_bytes": 8})
	var selection := {"default_font_id": 500, "secondary_font_id": 501, "language_font_id": 502, "overrides": [], "spacing": {"default": [-2, -3, -3, -4], "cjk": [-4, -5, -4, -6], "japanese": [-5, -6, -5, -7]}, "source_offset": 0, "source_bytes": 578}
	for i in 5: selection.overrides.append({"language_id": [9, 10, 11, 14, 15][i], "font_id": 503 + i})
	return {"records": records, "languages": languages, "selection": selection,
		"textures": {"rows": [{"texture_id": 17, "variants": {"baseline": baseline, "medium": medium, "large": large}, "source_offsets": {"baseline": 350, "medium": 100, "large": 200}}], "provenance": {"medium": {"offset": 20, "bytes": 16}, "large": {"offset": 160, "bytes": 31}}}}
