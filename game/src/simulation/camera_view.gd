extends RefCounted
## Stateless camera geometry. The scene owner supplies a verified mode, eye and
## target; this does not select a mission target or infer cinematic phase flags.
## Fixed-eye mode has no follow lag, shake, additional roll or cockpit transform.

static func fixed_eye(eye: Vector3, target: Transform3D, inherit_target_up: bool) -> Dictionary:
	if not eye.is_finite() or not target.origin.is_finite() or not target.basis.is_finite():
		return {"error": "Camera pose contains nonfinite coordinates"}
	if not target.basis.is_equal_approx(target.basis.orthonormalized()) or target.basis.determinant() <= 0.0:
		return {"error": "Camera target must have a proper simulation orientation"}
	var direction := target.origin - eye
	if not direction.is_finite() or is_zero_approx(direction.length_squared()):
		return {"error": "Camera eye and target must be distinct"}
	var up := target.basis.y if inherit_target_up else Vector3.UP
	if is_zero_approx(direction.normalized().cross(up).length_squared()):
		return {"error": "Camera direction is parallel to its up vector"}
	# Godot cameras look along local -Z. Flight simulation uses local +Z; the
	# target orientation supplies only its up vector, never camera forward.
	var pose := Transform3D(Basis.looking_at(direction, up), eye)
	if not pose.basis.is_finite(): return {"error": "Camera orientation is outside supported coordinates"}
	return {"pose": pose}
