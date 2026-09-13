extends RefCounted
## Root transforms for a fresh scenery effect. Animated mesh children keep
## their own sampled transforms; this only owns the final camera-facing root.
const Clock = preload("res://src/simulation/scenery_effect_clock.gd")

static func for_effect(effect: RefCounted, camera: Transform3D) -> Dictionary:
	if effect==null or effect.get_script()!=Clock:
		return {"error":"Scenery effect poses require a native effect clock"}
	var state: Dictionary = effect.snapshot()
	if state.is_empty():return {"error":"Configure the scenery effect before presenting it"}
	if not state.active:return {"visible":false}
	var result := alpha_root(camera,state.pose.origin,state.scale)
	if result.has("error"):return result
	return {"visible":true,"alpha":result.pose,"breakup":state.pose}

static func alpha_root(camera: Transform3D, position: Vector3, scale: Variant) -> Dictionary:
	if not camera.is_finite() or not position.is_finite():
		return {"error":"Scenery effect pose contains nonfinite coordinates"}
	if (not scale is float and not scale is int) or not is_finite(scale) or scale<=0:
		return {"error":"Scenery effect scale must be finite and positive"}
	var stored_scale := single(float(scale))
	if not is_finite(stored_scale) or stored_scale<=0:
		return {"error":"Scenery effect scale exceeds source precision"}
	# Camera +Z points backward. Preserve its length and roll: the final source
	# wrapper normalizes the two cross products, not the camera's backward axis.
	var backward := camera.basis.z
	var right := normalized(cross(camera.basis.y,backward))
	var up := normalized(cross(backward,right))
	var basis := Basis(scaled(right,stored_scale),scaled(up,stored_scale),scaled(backward,stored_scale))
	if not right.is_finite() or not up.is_finite() or not basis.is_finite():
		return {"error":"Scenery effect orientation exceeds source precision"}
	return {"pose":Transform3D(basis,position)}

static func cross(a: Vector3, b: Vector3) -> Vector3:
	return Vector3(single(single(a.y*b.z)-single(a.z*b.y)),
		single(single(a.z*b.x)-single(a.x*b.z)),
		single(single(a.x*b.y)-single(a.y*b.x)))

static func normalized(value: Vector3) -> Vector3:
	var squared := single(single(single(value.x*value.x)+single(value.y*value.y))+single(value.z*value.z))
	var length := single(sqrt(squared))
	if not is_finite(length):return Vector3(INF,INF,INF)
	# Exact zero, including squared-length underflow, uses the source +Y fallback.
	if length==0.0:return Vector3.UP
	return Vector3(single(value.x/length),single(value.y/length),single(value.z/length))

static func scaled(value: Vector3, scale: float) -> Vector3:
	return Vector3(single(value.x*scale),single(value.y*scale),single(value.z*scale))

static func single(value: float) -> float:
	return PackedFloat32Array([value])[0]
