extends RefCounted
## Shared authored type-zero animation clocks. Encounter owners decide when to
## construct, trigger and advance them, and whether debris was actually created.
const Vitals=preload("res://src/simulation/combat_vitals.gd")
const Playback=preload("res://src/simulation/model_playback.gd")

static func create(resources: Dictionary, fragments: Array, fragment_id: int) -> Dictionary:
	if not resources.get("models") is Array or resources.models.size()!=3:return {}
	if not fragments.is_empty() and (fragments.size()<3 or fragments.size()>9):return {}
	var models:=[]
	for index in 2:models.append(model_clock(resources.models[index]))
	for fragment in fragments:
		if not fragment is Dictionary or fragment.get("resource_id")!=fragment_id or not fragment.get("rotation_radians") is Vector3 or not fragment.rotation_radians.is_finite():return {}
		var scale_value: Variant=fragment.get("scale")
		if not (scale_value is float or scale_value is int) or not is_finite(scale_value) or scale_value<0.5 or scale_value>=1.0:return {}
		models.append(model_clock(resources.models[2]))
	for model in models:
		if model.is_empty():return {}
	if not Vitals.integer(resources.get("duration_ms")) or resources.duration_ms!=models[0].end_ms:return {}
	return {"active":false,"elapsed_ms":0,"duration_ms":resources.duration_ms,"position":null,"models":models}

static func model_clock(model: Variant) -> Dictionary:
	if not model is Dictionary or not Vitals.integer(model.get("start_ms")) or not Vitals.integer(model.get("end_ms")) or model.start_ms>model.end_ms or model.end_ms<1 or model.end_ms>1000000:return {}
	var result: Dictionary=model.duplicate(true)
	result.time_ms=result.start_ms;result.playing=true
	return result

static func trigger(effect: Dictionary, position: Vector3) -> void:
	# Re-triggering retains elapsed/model clocks; retirement owns their reset.
	effect.active=true;effect.position=position
	for model in effect.models:model.playing=true

static func advance(effect: Dictionary, milliseconds: int) -> bool:
	if not effect.active:return false
	Playback.advance(effect.models,milliseconds)
	effect.elapsed_ms+=milliseconds
	if effect.elapsed_ms<=effect.duration_ms:return false
	Playback.restart(effect.models)
	effect.elapsed_ms=0;effect.active=false
	return true
