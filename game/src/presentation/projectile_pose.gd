extends RefCounted
## Source ordinary projectile roots. Final lifetime overshoot remains signed;
## cleanup removes the slot on its following weapon update.
const Vitals=preload("res://src/simulation/combat_vitals.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")

static func sample(slot: Variant, kind: int, camera: Transform3D, reduced_scale: bool, rules: Dictionary, captured_up:=false) -> Dictionary:
	if slot==null:return {"visible":false}
	if not slot is Dictionary or not slot.get("position") is Vector3 or not slot.get("velocity") is Vector3 or not Numbers.integer(slot.get("remaining_ms"),-1000000,2147483647):return {"error":"Invalid projectile presentation slot"}
	if not slot.position.is_finite() or not slot.velocity.is_finite() or not camera.is_finite():return {"error":"Nonfinite projectile presentation pose"}
	if slot.position.x==rules.hidden_position_x:return {"visible":false}
	var basis: Basis
	if kind==int(rules.camera_facing_kind):
		basis=Basis(camera.basis.x,camera.basis.y,-camera.basis.z)
	else:
		var reference_up:=Vector3.UP
		if captured_up:
			if not slot.get("up") is Vector3 or not slot.up.is_finite():return {"error":"Projectile lost its captured firing up axis"}
			reference_up=slot.up
		var forward:=Vectors.normalized(slot.velocity)
		var right:=Vectors.normalized(Vectors.cross(reference_up,forward))
		var up:=Vectors.normalized(Vectors.cross(forward,right))
		basis=Basis(right,up,forward)
	var scale:=1.0
	if slot.remaining_ms<int(rules.shrink_below_ms):scale=Vitals.single(Vitals.single(float(slot.remaining_ms))/float(rules.shrink_divisor))
	for axis in 3:basis[axis]=Vectors.scaled(basis[axis],scale)
	if reduced_scale and kind==int(rules.camera_facing_kind):
		for axis in 3:basis[axis]=Vectors.scaled(basis[axis],float(rules.reduced_billboard_scale))
		scale=Vitals.single(scale*float(rules.reduced_billboard_scale))
	var pose:=Transform3D(basis,slot.position)
	if not pose.is_finite():return {"error":"Projectile pose exceeded source precision"}
	return {"visible":true,"pose":pose,"scale":scale}
