extends RefCounted
## Ordinary projectile contact geometry, after encounter-owned target eligibility.
## The source's optional point-geometry result is authoritative. Bounds never
## replace a negative point-geometry result, and no swept ray is inferred.
const Vitals = preload("res://src/simulation/combat_vitals.gd")
const Projectiles = preload("res://src/simulation/ordinary_projectiles.gd")
const Volumes = preload("res://src/content/station_collision_volumes.gd")
var error := ""

func bounds(projectile_position: Variant, velocity_per_ms: Variant, target_center: Variant, half_extent: Variant) -> Dictionary:
	error = ""
	if not Projectiles.finite_vector(projectile_position) or not Projectiles.finite_vector(velocity_per_ms) or not Projectiles.finite_vector(target_center):
		return fail("Ordinary bounds contact requires finite source-space vectors")
	if not Vitals.integer(half_extent): return fail("Ordinary bounds require an explicit nonnegative integer half extent")
	var position := Projectiles.scaled(projectile_position,1.0)
	var velocity := Projectiles.scaled(velocity_per_ms,1.0)
	var center := Projectiles.scaled(target_center,1.0)
	# Preserve (center - position) + velocity, with binary32 at each operation.
	# This uses velocity itself, not a frame displacement or a swept segment.
	var delta := Vector3(Vitals.single(center.x-position.x),Vitals.single(center.y-position.y),Vitals.single(center.z-position.z))
	delta = Projectiles.added(delta,velocity)
	if not delta.is_finite(): return fail("Ordinary bounds arithmetic exceeds finite coordinates")
	var upper := Vitals.single(float(half_extent))
	var lower := Vitals.single(float(-half_extent))
	var hit := delta.x > lower and delta.x < upper and delta.y > lower and delta.y < upper and delta.z > lower and delta.z < upper
	return {"hit":hit,"path":"bounds","relative_sample":delta}

func point_geometry(projectile_position: Variant, point_test_result: Variant) -> Dictionary:
	error = ""
	if not Projectiles.finite_vector(projectile_position) or not point_test_result is bool:
		return fail("Enabled point geometry requires an explicit native result at the projectile position")
	# The encounter's geometry provider tests the unshifted projectile position.
	# This method preserves selection semantics; it does not implement that provider.
	return {"hit":point_test_result,"path":"point_geometry","sample_position":Projectiles.scaled(projectile_position,1.0)}

func box_geometry(projectile_position: Variant, body_position: Variant, boxes: Variant) -> Dictionary:
	error=""
	if not Projectiles.finite_vector(projectile_position) or not Projectiles.finite_vector(body_position) or not boxes is Array or boxes.is_empty() or boxes.size()>64:return fail("Point geometry requires finite source positions and explicit boxes")
	var centers:=[]
	for box in boxes:
		if not box is Dictionary or box.size()!=2 or not Projectiles.finite_vector(box.get("offset")) or not Projectiles.finite_vector(box.get("half_extents")):return fail("Invalid point collision box")
		var half: Vector3=box.half_extents
		if half.x<=0 or half.y<=0 or half.z<=0:return fail("Empty point collision box")
		var center:=Projectiles.added(body_position,box.offset)
		if not center.is_finite():return fail("Point box exceeds finite coordinates")
		centers.append(center)
	var point:=Projectiles.scaled(projectile_position,1.0)
	# Source boxes translate in world axes; neither model rotation nor projectile
	# velocity rotates or shifts this sample. The first containing box wins.
	for index in boxes.size():
		if Volumes.contains_point(point,centers[index],boxes[index].half_extents):
			var result:=point_geometry(point,true);result.box_index=index
			return result
	return point_geometry(point,false)

func fail(message: String) -> Dictionary:
	error = message
	return {}
