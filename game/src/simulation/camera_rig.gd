extends RefCounted
## Native fixed-eye and ordinary player-follow views. The director supplies the
## shot, the scene supplies current target poses, and this rig owns view history.
## Orbit/cockpit transforms, shake, extra roll and later modes are not selected.
const Definitions = preload("res://src/content/camera_follow_definitions.gd")
const FrameClock = preload("res://src/simulation/frame_clock.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const Library = preload("res://src/content/library.gd")
const Director = preload("res://src/simulation/opening_camera.gd")
const CameraView = preload("res://src/simulation/camera_view.gd")
const Poses = preload("res://src/simulation/opening_staging.gd")
var error := ""
var _base := ""
var _binding := ""
var _max_ms := 0
var _data := {}
var _look_coefficients := PackedFloat64Array()
var _eye_coefficients := PackedFloat64Array()
var _state := {}

func clear() -> void:
	error = ""
	_base = ""
	_binding = ""
	_max_ms = 0
	_data = {}
	_look_coefficients = PackedFloat64Array()
	_eye_coefficients = PackedFloat64Array()
	_state = {}

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
	return true

func update(delta_ms: Variant, shot: Dictionary, scene: Dictionary, fixed_refresh: Dictionary = {}, view_translation: Variant = null) -> bool:
	error = ""
	if _binding.is_empty(): return reject("Configure camera rig before updating")
	if not Numbers.integer(delta_ms, 0, _max_ms): return reject("Camera frame exceeds the imported clock interval")
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
	return copy

func reject(message: String) -> bool:
	error = message
	return false

func fail(message: String) -> bool:
	clear()
	error = message
	return false
