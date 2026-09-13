extends RefCounted
const Definitions = preload("res://src/content/opening_drift_definitions.gd")

static func definition(mac := true) -> Dictionary:
	var provenance := {}
	var offset := 100
	var sizes := Definitions.sizes("x86_64" if mac else "armv7")
	for key in sizes:
		provenance[key] = {"offset": offset, "bytes": sizes[key]}
		offset += sizes[key] + 16
	return {"frequency_per_millisecond": 0.03125, "bias": -0.25,
		"actor_ids": [0, 1, 2], "through_phase": 2, "skip_formation_update": true,
		"time_unit": "milliseconds", "waveform": "absolute_sine",
		"application": "per_update_world_y", "provenance": provenance}
