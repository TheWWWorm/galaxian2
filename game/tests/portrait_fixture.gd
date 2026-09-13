extends RefCounted
## Synthetic declarations only; no original resource names or executable data.
static func definition(mac := true) -> Dictionary:
	var suffixes := {}
	var keys := ["baseline", "expanded", "medium", "large"]
	var values := ["", "_expanded", "_middle", "_big"]
	for i in keys.size():
		suffixes[keys[i]] = {"value": values[i], "offset": 1000 + i * 50, "bytes": values[i].length() + 1}
	var rows := []
	for i in 152:
		var stem := "data/textures/synthetic_%d" % i
		var variants := {}
		for key in keys: variants[key] = "resources/" + stem + suffixes[key].value + ".aei"
		rows.append({"id": 600 + i, "stem": stem, "variants": variants,
			"source_offset": 5000 + i * 380, "source_bytes": 187 if mac else 336,
			"stem_offset": 1500 + i * 20, "stem_bytes": stem.length() + 1,
			"extension_offset": 4800, "extension_bytes": 5})
	return {"rows": rows, "suffixes": suffixes, "provenance": {"selection": {"offset": 100, "bytes": 128 if mac else 282}}}
