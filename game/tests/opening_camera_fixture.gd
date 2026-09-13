extends RefCounted
const Definitions = preload("res://src/content/opening_camera_definitions.gd")

static func definition(mac := true) -> Dictionary:
	var provenance := {}
	var offset := 100
	var sizes := Definitions.sizes("x86_64" if mac else "armv7")
	for key in sizes:
		provenance[key] = {"offset": offset, "bytes": sizes[key]}
		offset += sizes[key] + 16
	return {"initial_target": "player", "initial_fixed_eye": true, "inherit_target_up": true,
		"actor_cut": {"after_event_finished": 5, "actor_id": 1, "eye": [-123, 192, -123]},
		"pan": {"velocity_per_ms": [0.75, 0, -1.25], "engagement_after_event_finished": 8, "follow_player_after_event_finished": 10}, "provenance": provenance}
