extends RefCounted
## Native fixed-eye and ordinary player-follow views. The director supplies the
## shot, the scene supplies current target poses, and this rig owns view history.
## The flight may supply an accepted look-at perturbation; eye and ship poses
## remain unchanged. Orbit/cockpit transforms, extra roll and later modes are not selected.
const Definitions = preload("res://src/content/camera_follow_definitions.gd")
const FrameClock = preload("res://src/simulation/frame_clock.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const Library = preload("res://src/content/library.gd")
const Director = preload("res://src/simulation/opening_camera.gd")
const CameraView = preload("res://src/simulation/camera_view.gd")
const Poses = preload("res://src/simulation/opening_staging.gd")
const FastForward = preload("res://src/content/fast_forward_definitions.gd")
var error := ""
var _base := ""
var _binding := ""
var _max_ms := 0
var _data := {}
var _look_coefficients := PackedFloat64Array()
var _eye_coefficients := PackedFloat64Array()
var _state := {}
var _response_rules := {}
var _cached_handling := 0.0
var _look_rate := 0.0
var _eye_rate := 0.0
var _fast := false
var _response_dirty := false
var _relative_capture := false
var _player_handling := 0.0

func clear() -> void:
	error = ""
	_base = ""
	_binding = ""
	_max_ms = 0
	_data = {}
	_look_coefficients = PackedFloat64Array()
	_eye_coefficients = PackedFloat64Array()
	_state = {}
	_response_rules={};_cached_handling=0.0;_look_rate=0.0;_eye_rate=0.0
	_fast=false;_response_dirty=false;_relative_capture=false;_player_handling=0.0

func configure(bindings: RefCounted) -> bool:
	clear()
	if not Definitions.parameters(bindings.camera_follow) or not FrameClock.valid_parameters(bindings.frame_clock): return fail("Camera rig requires source follow and frame-clock declarations")
	if not Library.valid_hash(bindings.base_content_id) or not Library.valid_hash(bindings.binding_id): return fail("Camera rig content identity is unavailable")
	_data = bindings.camera_follow.duplicate(true)
	_look_coefficients = coefficients(_data.response_matrix, _data.look_rate)
	_eye_coefficients = coefficients(_data.response_matrix, _data.eye_rate)
	for value in _look_coefficients + _eye_coefficients:
		if not is_finite(value): return fail("Camera response coefficients overflowed")
	_base = bindings.base_content_id
	_binding = bindings.binding_id
	_max_ms = int(bindings.frame_clock.max_frame_milliseconds)
	_look_rate=float(_data.look_rate);_eye_rate=float(_data.eye_rate)
	if FastForward.parameters(bindings.get("fast_forward")):
		_response_rules=bindings.fast_forward.camera.duplicate(true)
		_cached_handling=float(_response_rules.initial_cached_handling)
		_response_dirty=true
	return true

## Mode changes rebuild response coefficients without replacing view history.
## The retained handling cache survives a return to keyboard/controller steering.
func set_fast_forward(enabled: bool) -> bool:
	error=""
	if _response_rules.is_empty():return reject("Camera lacks Fast Forward response declarations")
	var rates:=_handling_rates(_cached_handling)
	if not _set_response_rates(rates.x,rates.y):return false
	_fast=enabled
	if not enabled:_response_dirty=true
	return true

func refresh_player_response(relative_capture: bool,handling: float) -> bool:
	error=""
	if _response_rules.is_empty():return true
	if not is_finite(handling) or handling<=0:return reject("Camera handling must be finite and positive")
	var rounded:=single(handling)
	if not is_finite(rounded):return reject("Camera handling exceeds source precision")
	if not _response_dirty or _fast:return true
	var rates:=_handling_rates(rounded) if relative_capture else Vector2(float(_response_rules.fixed_normal_look_rate),float(_response_rules.fixed_normal_eye_rate))
	if not _set_response_rates(rates.x,rates.y):return false
	if relative_capture:_cached_handling=rounded
	_response_dirty=false;_relative_capture=relative_capture;_player_handling=rounded
	return true

func mark_response_dirty() -> void:
	if not _response_rules.is_empty():_response_dirty=true

func _handling_rates(handling: float) -> Vector2:
	var scaled:=single(handling*float(_response_rules.handling_scale))
	var look:=single(single(single(float(_response_rules.look_complement)-scaled)*float(_response_rules.look_scale))+float(_response_rules.look_add))
	var eye:=single(single(scaled*float(_response_rules.eye_scale))+float(_response_rules.eye_add))
	return Vector2(look,eye)

func _set_response_rates(look: float,eye: float) -> bool:
	if not is_finite(look) or not is_finite(eye):return reject("Camera response rates overflowed")
	var look_coefficients:=coefficients(_data.response_matrix,look)
	var eye_coefficients:=coefficients(_data.response_matrix,eye)
	for value in look_coefficients+eye_coefficients:
		if not is_finite(value):return reject("Camera response coefficients overflowed")
	_look_rate=look;_eye_rate=eye
	_look_coefficients=look_coefficients;_eye_coefficients=eye_coefficients
	return true

func response_snapshot() -> Dictionary:
	return {"fast":_fast,"dirty":_response_dirty,"cached_handling":_cached_handling,
		"relative_capture":_relative_capture,"player_handling":_player_handling,"look_rate":_look_rate,"eye_rate":_eye_rate}

static func single(value: float) -> float:return PackedFloat32Array([value])[0]

func update(delta_ms: Variant, shot: Dictionary, scene: Dictionary, fixed_refresh: Dictionary = {}, view_translation: Variant = null, look_jitter: Variant = Vector3.ZERO) -> bool:
	error = ""
	if _binding.is_empty(): return reject("Configure camera rig before updating")
	if not Numbers.integer(delta_ms, 0, _max_ms): return reject("Camera frame exceeds the imported clock interval")
	if not look_jitter is Vector3 or not look_jitter.is_finite() or (delta_ms == 0 and look_jitter != Vector3.ZERO):
		return reject("Camera perturbation requires a finite look offset and a positive update")
	if shot.get("base_content_id") != _base or shot.get("binding_id") != _binding: return reject("Camera shot belongs to another content identity")
	if shot.get("mode") not in ["fixed_eye", "follow"]: return reject("Unsupported camera mode")
	var resolved := Director.target_pose(shot, scene)
	if resolved.has("error"): return reject(resolved.error)
	var target: Transform3D = resolved.target
	if not target.origin.is_finite() or not target.basis.is_finite() or not target.basis.is_equal_approx(target.basis.orthonormalized()) or target.basis.determinant() <= 0:
		return reject("Camera target must have a finite proper simulation pose")
	if shot.mode == "fixed_eye" and (not shot.get("eye") is Vector3 or not shot.eye.is_finite() or not shot.get("inherit_target_up") is bool):
		return reject("Invalid fixed-eye camera parameters")
	var prior := _state
	if view_translation != null:
		if not view_translation is Vector3 or not view_translation.is_finite() or not fixed_refresh.is_empty():
			return reject("Invalid or conflicting camera view translation")
		if prior.is_empty() and delta_ms == 0: return reject("Camera translation requires a preceding orientation")
		if not prior.is_empty():
			# Formation moves the renderer's existing camera matrix without
			# recomputing its orientation. A positive ordinary update follows.
			prior = prior.duplicate(true)
			prior.eye = view_translation
			prior.pose.origin = view_translation
	if not fixed_refresh.is_empty():
		var refreshed := fixed_view(fixed_refresh, scene)
		if refreshed.has("error"): return reject(refreshed.error)
		prior = refreshed
	# Ordinary view updates require positive time. A pan setter's immediate
	# fixed-eye refresh is independent of that ordinary frame-time check.
	if delta_ms == 0:
		_state = prior
		return true
	var eye: Vector3
	var look: Vector3
	var inherit_up := true
	if shot.mode == "fixed_eye":
		eye = shot.eye
		look = target.origin
		inherit_up = shot.inherit_target_up
	else:
		if prior.is_empty(): return reject("Follow camera requires the preceding view")
		var desired_eye := target * Poses.vec(_data.eye_offset)
		var desired_look := target * Poses.vec(_data.look_offset)
		var eye_weight := weight(_eye_coefficients, int(delta_ms), _data.reciprocal_numerator)
		var look_weight := weight(_look_coefficients, int(delta_ms), _data.reciprocal_numerator)
		if not is_finite(eye_weight) or not is_finite(look_weight): return reject("Camera response is outside supported numbers")
		eye = prior.eye.lerp(desired_eye, eye_weight)
		look = prior.look.lerp(desired_look, look_weight)
	# Ordinary follow always uses the current target's up, independent of the
	# fixed-eye mode's up-inheritance option.
	# Store the perturbed look point in view history, never the simulation pose.
	look += look_jitter
	var view := CameraView.fixed_eye(eye, Transform3D(target.basis, look), inherit_up)
	if view.has("error"): return reject(view.error)
	_state = {"base_content_id": _base, "binding_id": _binding, "eye": eye,
		"look": look, "pose": view.pose, "mode": shot.mode}
	return true

func fixed_view(shot: Dictionary, scene: Dictionary) -> Dictionary:
	if shot.get("base_content_id") != _base or shot.get("binding_id") != _binding:
		return {"error": "Camera refresh belongs to another content identity"}
	if shot.get("mode") != "fixed_eye" or not shot.get("eye") is Vector3 or not shot.get("inherit_target_up") is bool:
		return {"error": "Camera refresh requires a fixed-eye shot"}
	var resolved := Director.target_pose(shot, scene)
	if resolved.has("error"): return resolved
	var target: Transform3D = resolved.target
	var view := CameraView.fixed_eye(shot.eye, target, shot.inherit_target_up)
	if view.has("error"): return view
	return {"base_content_id": _base, "binding_id": _binding, "eye": shot.eye,
		"look": target.origin, "pose": view.pose, "mode": "fixed_eye"}

static func polynomial(values: Variant, argument: float) -> float:
	var result := 0.0
	for i in range(values.size() - 1, -1, -1): result = result * argument + float(values[i])
	return result

static func coefficients(matrix: Array, rate: float) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	for row in matrix: result.append(polynomial(row, rate))
	return result

static func weight(values: PackedFloat64Array, milliseconds: int, numerator: float) -> float:
	# Source stores the reciprocal and final weight as floats; the table and
	# polynomial coefficients are doubles. Native vector arithmetic is float32.
	var reciprocal := PackedFloat32Array([numerator / float(milliseconds)])[0]
	return PackedFloat32Array([polynomial(values, float(milliseconds)) * reciprocal])[0]

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func fork_for_frame() -> RefCounted:
	var copy: RefCounted = get_script().new()
	copy._base = _base
	copy._binding = _binding
	copy._max_ms = _max_ms
	copy._data = _data.duplicate(true)
	copy._look_coefficients = _look_coefficients.duplicate()
	copy._eye_coefficients = _eye_coefficients.duplicate()
	copy._state = _state.duplicate(true)
	copy._response_rules=_response_rules;copy._cached_handling=_cached_handling
	copy._look_rate=_look_rate;copy._eye_rate=_eye_rate;copy._fast=_fast
	copy._response_dirty=_response_dirty;copy._relative_capture=_relative_capture;copy._player_handling=_player_handling
	return copy

func reject(message: String) -> bool:
	error = message
	return false

func fail(message: String) -> bool:
	clear()
	error = message
	return false
