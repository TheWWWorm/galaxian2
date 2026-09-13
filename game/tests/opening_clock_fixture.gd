extends RefCounted
const Definitions = preload("res://src/content/opening_clock_definitions.gd")

static func definition(mac: bool = true) -> Dictionary:
	var data := {"initial_elapsed_ms": 12, "advance_before_controller": true, "time_unit": "milliseconds", "provenance": {}}
	var offset := 256
	for key in Definitions.sizes("x86_64" if mac else "armv7"):
		var size: int = Definitions.sizes("x86_64" if mac else "armv7")[key]
		data.provenance[key] = {"offset": offset,"bytes": size}
		offset += size+16
	return data
