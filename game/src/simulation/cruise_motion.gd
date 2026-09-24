extends RefCounted
## Native continuous translation in original content coordinates, local +Z and signed X.
## The caller supplies elapsed simulation seconds (zero while paused) and heading.
## Steering, acceleration, boost, collisions and wall-clock policy are not defined
## by this component. Do not use hangar presentation transforms as flight poses.
const Definitions = preload("res://src/content/motion_definitions.gd")
const Library = preload("res://src/content/library.gd")
var error := ""
var base_content_id := ""
var binding_id := ""
var _speed_per_second := 0.0

func configure(bindings: RefCounted, expected_content_id: String) -> bool:
	clear()
	if not Library.valid_hash(expected_content_id) or bindings.base_content_id != expected_content_id \
			or not Library.valid_hash(bindings.binding_id):
		error = "Cruise bindings belong to a different or unavailable content identity"
		return false
	var definition: Dictionary = bindings.cruise
	if not Definitions.valid_rate(definition.get("speed_units_per_millisecond")) \
			or not Definitions.valid_forward_axis(definition.get("forward_axis")):
		error = "This content has no supported ordinary cruise definition"
		return false
	base_content_id = expected_content_id
	binding_id = bindings.binding_id
	_speed_per_second = float(definition.speed_units_per_millisecond) * 1000.0
	return true

func clear() -> void:
	error = ""
	base_content_id = ""
	binding_id = ""
	_speed_per_second = 0.0

func advance(pose: Transform3D, throttle: float, seconds: float, lateral_units_per_millisecond:=0.0) -> Transform3D:
	error = ""
	if binding_id.is_empty():
		error = "Configure ordinary cruise from this session's content before advancing"
		return pose
	if not is_finite(throttle) or throttle < 0.0 or throttle > 1.0 \
			or not is_finite(seconds) or seconds < 0.0 or not is_finite(lateral_units_per_millisecond) \
			or absf(lateral_units_per_millisecond) > 2.0:
		error = "Invalid ordinary cruise throttle, lateral rate or elapsed simulation time"
		return pose
	if not pose.is_finite() or not is_finite(pose.basis.determinant()) or pose.basis.determinant() == 0.0:
		error = "Invalid flight pose"
		return pose
	var forward := pose.basis.z.normalized()
	var lateral := pose.basis.x.normalized()
	var next := pose.origin + (forward * (_speed_per_second * throttle) + lateral * (lateral_units_per_millisecond * 1000.0)) * seconds
	if not forward.is_finite() or forward.is_zero_approx() or not lateral.is_finite() or lateral.is_zero_approx() or not next.is_finite():
		error = "Cruise displacement exceeds supported coordinates"
		return pose
	return Transform3D(pose.basis, next)

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy.base_content_id=base_content_id;copy.binding_id=binding_id
	copy._speed_per_second=_speed_per_second
	return copy
