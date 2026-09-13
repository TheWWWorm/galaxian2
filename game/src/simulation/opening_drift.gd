extends RefCounted
## Source-bound displacement per controller update. Elapsed simulation time is
## supplied explicitly; this component does not invent save/new-game clock state.
const Definitions = preload("res://src/content/opening_drift_definitions.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")

static func displacement(data: Dictionary, elapsed_ms: Variant, phase: Variant, formation_revealed_now: bool) -> Dictionary:
	if not Definitions.parameters(data): return {"error": "Opening drift is unavailable"}
	if not Numbers.integer(elapsed_ms, 0, 9007199254740991) or not Numbers.integer(phase, 0, 255): return {"error": "Invalid opening drift time or phase"}
	if formation_revealed_now or phase > data.through_phase: return {"value": Vector3.ZERO, "apply": false}
	# Match source float input/product/result boundaries while using native sin.
	var time := PackedFloat32Array([elapsed_ms])[0]
	var angle := PackedFloat32Array([time * data.frequency_per_millisecond])[0]
	var wave := PackedFloat32Array([sin(angle)])[0]
	var amount := PackedFloat32Array([absf(wave) + data.bias])[0]
	if not is_finite(amount): return {"error": "Opening drift exceeds supported coordinates"}
	return {"value": Vector3(0, amount, 0), "apply": true}
