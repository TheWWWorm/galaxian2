extends RefCounted
## Shared source-coordinate binary32 vector operations. Positive Z is forward.
const Vitals = preload("res://src/simulation/combat_vitals.gd")

static func local_xyz(angles: Vector3) -> Basis:
	return Basis(Vector3.RIGHT,angles.x)*Basis(Vector3.UP,angles.y)*Basis(Vector3.BACK,angles.z)

static func scaled(value: Vector3, factor: float) -> Vector3:
	return Vector3(Vitals.single(Vitals.single(value.x)*factor),Vitals.single(Vitals.single(value.y)*factor),Vitals.single(Vitals.single(value.z)*factor))

static func normalized(value: Vector3) -> Vector3:
	var vector := scaled(value,1.0)
	var total := dot(vector,vector)
	if not is_finite(total): return Vector3(INF,INF,INF)
	var length := Vitals.single(sqrt(total))
	if length==0: return Vector3.UP
	return Vector3(Vitals.single(vector.x/length),Vitals.single(vector.y/length),Vitals.single(vector.z/length))

static func squares(value: Vector3) -> Vector3:
	return Vector3(Vitals.single(value.x*value.x),Vitals.single(value.y*value.y),Vitals.single(value.z*value.z))

static func added(left: Vector3, right: Vector3) -> Vector3:
	return Vector3(Vitals.single(left.x+right.x),Vitals.single(left.y+right.y),Vitals.single(left.z+right.z))

static func dot(left: Vector3, right: Vector3) -> float:
	return Vitals.single(Vitals.single(Vitals.single(left.x*right.x)+Vitals.single(left.y*right.y))+Vitals.single(left.z*right.z))

static func cross(left: Vector3, right: Vector3) -> Vector3:
	return Vector3(Vitals.single(Vitals.single(left.y*right.z)-Vitals.single(left.z*right.y)),
		Vitals.single(Vitals.single(left.z*right.x)-Vitals.single(left.x*right.z)),
		Vitals.single(Vitals.single(left.x*right.y)-Vitals.single(left.y*right.x)))
