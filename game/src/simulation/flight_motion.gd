extends RefCounted
## Ordinary manual flight kinematics in source coordinates. Input response must
## supply resolved angular control units; these are not normalized stick axes.
## Local pitch (X), then yaw (Y), precede forward cruise in each simulation step.
const Cruise = preload("res://src/simulation/cruise_motion.gd")
const Definitions = preload("res://src/content/motion_definitions.gd")
var error := ""
var base_content_id := ""
var binding_id := ""
var _cruise := Cruise.new()
var _radians_per_unit_second := 0.0

func configure(bindings: RefCounted, expected_content_id: String) -> bool:
	clear()
	if not _cruise.configure(bindings, expected_content_id):
		error = _cruise.error
		return false
	var parameters: Dictionary = bindings.manual_rotation
	if not Definitions.valid_rotation_parameters(parameters):
		clear()
		error = "This content has no supported manual rotation definition"
		return false
	_radians_per_unit_second = float(parameters.angle_unit_scale) * float(parameters.radians_per_turn) \
		* float(parameters.time_scale) * 1000.0
	base_content_id = expected_content_id
	binding_id = bindings.binding_id
	return true

func clear() -> void:
	error = ""
	base_content_id = ""
	binding_id = ""
	_radians_per_unit_second = 0.0
	_cruise.clear()

func advance(pose: Transform3D, angular_units: Vector2, throttle: float, seconds: float) -> Transform3D:
	error = ""
	if binding_id.is_empty():
		error = "Configure flight motion from this session's content before advancing"
		return pose
	if not angular_units.is_finite() or not is_finite(seconds) or seconds < 0.0:
		error = "Invalid manual angular input or elapsed simulation time"
		return pose
	_cruise.advance(pose, throttle, 0.0)
	if not _cruise.error.is_empty():
		error = _cruise.error
		return pose
	# Simulation orientation is a proper rotation; visual scale belongs to meshes.
	if not pose.basis.is_equal_approx(pose.basis.orthonormalized()) or pose.basis.determinant() < 0.0:
		error = "Flight orientation must be an orthonormal rotation"
		return pose
	if seconds == 0.0: return pose
	var angles := angular_units * (_radians_per_unit_second * seconds)
	if not angles.is_finite():
		error = "Manual rotation exceeds supported coordinates"
		return pose
	var heading := (pose.basis * Basis(Vector3.RIGHT, angles.x) * Basis(Vector3.UP, angles.y)).orthonormalized()
	var next := _cruise.advance(Transform3D(heading, pose.origin), throttle, seconds)
	if not _cruise.error.is_empty():
		error = _cruise.error
		return pose
	return next

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy.base_content_id=base_content_id;copy.binding_id=binding_id
	copy._radians_per_unit_second=_radians_per_unit_second
	copy._cruise=_cruise.fork_for_frame()
	return copy
