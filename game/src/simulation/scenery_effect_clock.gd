extends RefCounted
## A fresh scenery breakup owns two model clocks and a separate lifetime.
## This component advances source time only; drawing, body retirement, cargo
## and mining outcomes belong to their own verified owners.
const Resources = preload("res://src/content/scenery_effect_resources.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Frames = preload("res://src/simulation/frame_clock.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const Playback = preload("res://src/simulation/model_playback.gd")
var error := ""
var _state := {}
var _max_ms := 0
var _presentation_identity: RefCounted

func configure(bindings: RefCounted, effect: Dictionary, scale: Variant) -> bool:
	clear()
	if bindings==null or bindings.get_script()!=Bindings or not Resources.effect_parameters(effect,bindings):
		return reject("Scenery effect clocks require matching source resources")
	if not Frames.valid_parameters(bindings.frame_clock):
		return reject("Scenery effects require an ordinary source frame clock")
	if (not scale is float and not scale is int) or not is_finite(scale) or scale<=0:
		return reject("Scenery effect scale must be finite and positive")
	var stored_scale := single(float(scale))
	if not is_finite(stored_scale) or stored_scale<=0:
		return reject("Scenery effect scale exceeds source precision")
	var parameters: Dictionary = bindings.scenery_effects
	var speed := single(float(parameters.speed_base))
	if stored_scale<float(parameters.speed_threshold):
		speed=single(speed+single(single(float(parameters.speed_threshold)-stored_scale)*single(float(parameters.speed_scale))))
	var duration := single(single(float(effect.duration_ms))/speed)
	if not is_finite(duration) or duration<0 or duration>2147483520.0:
		return reject("Scenery effect duration exceeds the supported source interval")
	var models := []
	for source in effect.models:
		models.append({"model_id":int(source.model_id),"resource":source.resource,
			"start_ms":int(source.start_ms),"end_ms":int(source.end_ms),
			"time_ms":int(source.start_ms),"playing":true})
	_state={"base_content_id":effect.base_content_id,"binding_id":effect.binding_id,
		"base_model_id":int(effect.base_model_id),"effect_type":int(effect.effect_type),
		"source_duration_ms":int(effect.duration_ms),"duration_ms":int(duration),
		"scale":stored_scale,"speed":speed,"elapsed_ms":0,"models":models,
		"triggered":false,"active":false,"finished":false,"pose":null}
	_max_ms=int(bindings.frame_clock.max_frame_milliseconds)
	_presentation_identity=RefCounted.new()
	return true

func trigger(pose: Transform3D) -> bool:
	error=""
	if _state.is_empty():return reject("Configure a scenery effect before triggering it")
	if _state.triggered:return reject("A scenery effect can only be triggered once")
	if not pose.is_finite():return reject("Scenery effect requires a finite initial pose")
	# The actor's transition tick captures the pose and arms playback. Its
	# following presentation update owns the first elapsed-time increment.
	_state.pose=pose
	_state.triggered=true
	_state.active=true
	return true

func update(delta_ms: Variant) -> bool:
	error=""
	if _state.is_empty():return reject("Configure a scenery effect before updating it")
	if not Numbers.integer(delta_ms,0,_max_ms):return reject("Invalid scenery effect presentation duration")
	if not _state.active or delta_ms==0:return true
	# Truncate each model increment independently; do not carry a fraction or
	# reconstruct model time from the lifetime clock's accumulated elapsed time.
	var increment := int(single(single(float(delta_ms))*_state.speed))
	Playback.advance(_state.models,increment)
	_state.elapsed_ms+=int(delta_ms)
	# Model playback may still be active at expiry. Lifetime uses unscaled
	# frame time, and equality deliberately remains active for this frame.
	if _state.elapsed_ms>_state.duration_ms:
		Playback.restart(_state.models)
		_state.elapsed_ms=0
		_state.active=false
		_state.finished=true
	return true

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func fork_for_frame() -> RefCounted:
	var copy: RefCounted = get_script().new()
	copy._state=_state.duplicate(true)
	copy._max_ms=_max_ms
	copy._presentation_identity=_presentation_identity
	return copy

func presentation_identity() -> RefCounted:
	# A frame candidate is the same logical effect. Reconfiguration starts a new
	# one, even when all source identifiers happen to match the previous effect.
	return _presentation_identity

func clear() -> void:
	error="";_state={};_max_ms=0;_presentation_identity=null

static func single(value: float) -> float:
	return PackedFloat32Array([value])[0]

func reject(message: String) -> bool:
	error=message
	return false
