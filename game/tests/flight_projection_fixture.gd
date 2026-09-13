extends RefCounted
const Definitions = preload("res://src/content/flight_projection_definitions.gd")

static func definition(mac: bool = true) -> Dictionary:
	var data := {"vertical_fov_radians": PI / 2.0, "near": 4.0, "far": 1000.0,
		"matching_location_early_far": 2000.0, "early_cursor_limit": 7,
		"fov_axis": "vertical", "provenance": {}}
	var offset := 256
	for key in Definitions.sizes("x86_64" if mac else "armv7"):
		var size: int = Definitions.sizes("x86_64" if mac else "armv7")[key]
		data.provenance[key] = {"offset": offset, "bytes": size}
		offset += size + 16
	return data
