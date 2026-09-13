extends RefCounted

static func definition(mac := true) -> Dictionary:
	var provenance := {"declaration": {"offset": 100, "bytes": 413 if mac else 356},
		"dispatch": {"offset": 600, "bytes": 43 if mac else 96},
		"cursor_getter": {"offset": 720, "bytes": 12 if mac else 6},
		"hull_setter": {"offset": 750, "bytes": 30 if mac else 18}}
	if mac: provenance.position = {"offset": 800, "bytes": 4}
	return {"actors": [{"actor_id": 0, "hull_catalogue_id": 0, "actor_kind": 8, "position": [10, -20, 30], "current_hull_override": 123},
		{"actor_id": 1, "hull_catalogue_id": 1, "actor_kind": 8, "position": [-30, 20, 10], "current_hull_override": 321}],
		"player_current_hull_override": 9999, "provenance": provenance}
