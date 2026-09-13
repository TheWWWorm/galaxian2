extends RefCounted
const Definitions = preload("res://src/content/camera_follow_definitions.gd")

static func definition(mac := true) -> Dictionary:
	var provenance := {}
	var offset := 100
	var sizes := Definitions.sizes("x86_64" if mac else "armv7")
	for key in sizes:
		provenance[key] = {"offset": offset, "bytes": sizes[key]}
		offset += sizes[key] + 16
	# Synthetic rates give constant weights of 1/4 for look and 1/2 for eye.
	var matrix := []
	for i in 5:
		var row := []; row.resize(9); row.fill(0.0)
		if i == 1: row[1] = 1.0
		matrix.append(row)
	return {"look_offset": [12, 30, 100], "eye_offset": [-18, 45, -220],
		"look_rate": 0.25, "eye_rate": 0.5, "response_matrix": matrix,
		"reciprocal_numerator": 1.0, "provenance": provenance}
