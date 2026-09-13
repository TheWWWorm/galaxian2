extends RefCounted
## One equipment-defined shield pulse after a strict elapsed-time threshold.
## The player owner selects when this ordinary update is eligible to run.
const Definitions = preload("res://src/content/player_recharge_definitions.gd")
const Vitals = preload("res://src/simulation/combat_vitals.gd")
var error := ""
var _state := {}
var _period_ms := 0

func configure(parameters: Dictionary, capacity: Variant, duration_ms: Variant) -> bool:
	clear()
	if not Definitions.parameters(parameters) or not Vitals.integer(capacity) or capacity>Vitals.MAX_SHIELD or not Vitals.integer(duration_ms):
		return reject("Shield recharge requires source parameters and integer equipment values")
	var pulse := 0.0
	if duration_ms>0:
		var periods := Vitals.single(Vitals.single(float(duration_ms))/float(parameters.capacity_divisor))
		pulse=Vitals.single(Vitals.single(float(capacity))/periods)
		if not is_finite(pulse) or pulse<0: return reject("Shield recharge pulse exceeds source precision")
	_state={"capacity":capacity,"duration_ms":duration_ms,"pulse":pulse,"elapsed_ms":int(parameters.initial_elapsed_ms)}
	_period_ms=int(parameters.period_ms)
	return true

func advance(hull: Variant, shield: Variant, delta_ms: Variant) -> Dictionary:
	error=""
	if _state.is_empty() or not Vitals.integer(hull) or not Vitals.integer(delta_ms) or not (shield is int or shield is float) or not is_finite(float(shield)) or shield<0 or shield>Vitals.MAX_SHIELD:
		return fail("Shield recharge requires supported living-pool values and integer milliseconds")
	var before := Vitals.single(float(shield));var after := before
	var elapsed: int=_state.elapsed_ms
	var pulsed := false
	if hull>0 and _state.duration_ms>0:
		elapsed+=delta_ms
		if elapsed>_period_ms:
			elapsed=0;pulsed=true
			after=minf(Vitals.single(before+_state.pulse),Vitals.single(float(_state.capacity)))
			if not is_finite(after) or after<0 or after>Vitals.MAX_SHIELD: return fail("Recharged shield exceeds supported source bounds")
	_state.elapsed_ms=elapsed
	return {"pulsed":pulsed,"before":before,"after":after,"elapsed_ms":elapsed}

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._state=_state.duplicate(true);copy._period_ms=_period_ms
	return copy

func clear() -> void:
	error="";_state={};_period_ms=0

func reject(message: String) -> bool:
	error=message
	return false

func fail(message: String) -> Dictionary:
	reject(message)
	return {}
