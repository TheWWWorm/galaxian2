extends RefCounted
## Shared ordinary player guidance. Content owners select the target and gains.
## This moves once; it does not acquire targets or decide arrival/completion.
const Vectors=preload("res://src/simulation/source_vectors.gd")

static func advance(pose: Transform3D, target: Vector3, milliseconds: int, gain: float, speed: float, turn_fraction: float, throttle: float) -> Transform3D:
	var forward:=Vectors.normalized(pose.basis.z)
	var direction:=Vectors.normalized(Vectors.added(target,-pose.origin))
	var weight:=single(float(int(single(float(milliseconds)*gain)))*turn_fraction)
	var heading:=Vectors.normalized(Vectors.added(forward,Vectors.scaled(Vectors.added(direction,-forward),weight)))
	var right:=Vectors.normalized(Vectors.cross(Vector3.UP,heading))
	var up:=Vectors.normalized(Vectors.cross(heading,right))
	var distance:=single(speed*single(float(milliseconds)*throttle))
	return Transform3D(Basis(right,up,heading),Vectors.added(pose.origin,Vectors.scaled(heading,distance)))

static func signed_turn(previous: Basis, heading: Vector3, sign_angle: float) -> float:
	var cosine:=Vectors.dot(Vectors.normalized(previous.z),heading)
	var angle:=single(acos(cosine)) if cosine>-1.0 and cosine<1.0 else -0.0
	if angle!=0.0:
		var side:=Vectors.dot(previous.x,heading)
		if side>=-1.0 and side<=1.0 and single(acos(side))<sign_angle:angle=-angle
	return angle

static func single(value: float) -> float:return PackedFloat32Array([value])[0]
