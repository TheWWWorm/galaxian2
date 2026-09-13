extends RefCounted

static func definition(mac := true) -> Dictionary:
	var bases := []
	var variants := {}
	for i in 13: bases.append([500, 510, 520, -1])
	for name in ["baseline", "expanded", "medium", "large"]:
		var families := []
		for i in 13: families.append([{"anchor": 16, "y": 3}, {"anchor": 32, "y": 8}, {"anchor": 16, "y": -2}, {"anchor": 0, "y": 0}])
		variants[name] = families
	var provenance := {"selection": {"offset": 64, "bytes": 316 if mac else 382}, "order": {"offset": 512, "bytes": 61 if mac else 56}, "part_bases": {"offset": 640, "bytes": 208}}
	for i in variants.size(): provenance[variants.keys()[i]] = {"offset": 1024 + i * 512, "bytes": 416}
	return {"part_bases": bases, "variants": variants, "draw_order": [2, 1, 0, 3], "provenance": provenance}
