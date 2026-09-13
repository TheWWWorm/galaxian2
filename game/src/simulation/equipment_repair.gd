extends RefCounted
## Ordered equipment repair pulses. The owner supplies current hull and armor.
const Definitions = preload("res://src/content/player_repair_definitions.gd")
const Vitals = preload("res://src/simulation/combat_vitals.gd")
var error := ""
var _state := {}
var _parameters := {}

func configure(parameters: Dictionary, max_hull: Variant, max_armor: Variant, device_mode: Variant) -> bool:
	clear()
	if not Definitions.parameters(parameters) or not Vitals.integer(max_hull) or not Vitals.integer(max_armor) or not device_mode is int or device_mode not in [-1,0,1]:
		return reject("Repair requires source parameters, integer capacities and an explicit device mode")
	_parameters=parameters.duplicate(true)
	_state={"max_hull":max_hull,"max_armor":max_armor,"device_mode":device_mode,"hull_elapsed_ms":0,"armor_elapsed_ms":0}
	return true

func advance(hull: Variant, armor: Variant, delta_ms: Variant) -> Dictionary:
	error=""
	if _state.is_empty() or not Vitals.integer(hull) or not Vitals.integer(armor) or not Vitals.integer(delta_ms):
		return fail("Repair requires integer current pools and elapsed milliseconds")
	var next := _state.duplicate()
	var result := {"before":{"hull":hull,"armor":armor},"after":{"hull":hull,"armor":armor},
		"hull_pulsed":false,"armor_pulsed":false,"hull_repaired":0,"armor_repaired":0}
	if hull>0 and next.device_mode>=0:
		next.hull_elapsed_ms+=delta_ms;next.armor_elapsed_ms+=delta_ms
		if Vitals.single(float(next.hull_elapsed_ms))>float(_parameters.hull_periods_ms[next.device_mode]):
			next.hull_elapsed_ms=0;result.hull_pulsed=true
			if hull<next.max_hull:
				result.after.hull=mini(hull+int(_parameters.hull_amount),next.max_hull)
				result.hull_repaired=result.after.hull-hull
		if Vitals.single(float(next.armor_elapsed_ms))>float(_parameters.armor_periods_ms[next.device_mode]):
			next.armor_elapsed_ms=0;result.armor_pulsed=true
			if result.after.hull>=next.max_hull and armor<next.max_armor:
				# Avoid evaluating the source's signed overflow outside its valid range.
				if armor>Vitals.MAX_INTEGER-int(_parameters.armor_amount): return fail("Armor repair addition exceeds source integer bounds")
				result.after.armor=mini(armor+int(_parameters.armor_amount),next.max_armor)
				result.armor_repaired=result.after.armor-armor
	_state=next
	result.hull_elapsed_ms=next.hull_elapsed_ms;result.armor_elapsed_ms=next.armor_elapsed_ms
	return result

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._state=_state.duplicate(true);copy._parameters=_parameters.duplicate(true)
	return copy

func clear() -> void:
	error="";_state={};_parameters={}

func reject(message: String) -> bool:
	error=message
	return false

func fail(message: String) -> Dictionary:
	reject(message)
	return {}
