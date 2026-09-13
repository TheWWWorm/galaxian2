extends SceneTree
const Geometry = preload("res://src/simulation/ordinary_hit_geometry.gd")
const Projectiles = preload("res://src/simulation/ordinary_projectiles.gd")
var failures := 0

func _initialize() -> void:
	var geometry := Geometry.new()
	# This contact is behind the current position by one velocity vector. It is
	# neither a forward prediction nor a sphere nor a frame-scaled sweep.
	check(geometry.bounds(Vector3(20,0,0),Vector3(20,0,0),Vector3.ZERO,1).hit,"Source velocity sign changed")
	check(not geometry.bounds(Vector3(20,0,0),Vector3(20,0,0),Vector3(40,0,0),1).hit,"Forward prediction replaced source sample")
	check(geometry.bounds(Vector3.ZERO,Vector3.ZERO,Vector3(9,9,9),10).hit,"Sphere substituted for per-axis bounds")
	for axis in 3:
		for sign_value in [-1,1]:
			var center := Vector3.ZERO
			center[axis]=10*sign_value
			check(not geometry.bounds(Vector3.ZERO,Vector3.ZERO,center,10).hit,"Exact face counted as contact")
			center[axis]=9.999*sign_value
			check(geometry.bounds(Vector3.ZERO,Vector3.ZERO,center,10).hit,"Interior point missed")
	check(not geometry.bounds(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,0).hit,"Zero extent acquired volume")
	var rounded: Dictionary = geometry.bounds(Vector3(16777216,0,0),Vector3(1,0,0),Vector3(16777216,0,0),1)
	check(not rounded.hit and rounded.relative_sample==Vector3(1,0,0),"Arithmetic was regrouped as center minus (position minus velocity)")
	# Every cube face, strict interior/exterior and asymmetric velocities.
	for extent in [0,1,3,20]:
		for x in range(-extent-1,extent+2):
			for y in [-extent-1,-extent,0,extent,extent+1]:
				for z in [-extent-1,-extent,0,extent,extent+1]:
					var velocity := Vector3(7,-3,5)
					var result: Dictionary = geometry.bounds(Vector3(10,20,30),velocity,Vector3(3+x,23+y,25+z),extent)
					check(result.hit==(absi(x)<extent and absi(y)<extent and absi(z)<extent),"Ordinary cube boundary mismatch")
	for bad in [-1,1.5,true,null,2147483648]:
		check(geometry.bounds(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,bad).is_empty(),"Invalid half extent accepted")
	for bad in [null,Vector3(INF,0,0),Vector3(0,NAN,0)]:
		check(geometry.bounds(bad,Vector3.ZERO,Vector3.ZERO,1).is_empty(),"Invalid projectile position accepted")
		check(geometry.bounds(Vector3.ZERO,bad,Vector3.ZERO,1).is_empty(),"Invalid projectile velocity accepted")
		check(geometry.bounds(Vector3.ZERO,Vector3.ZERO,bad,1).is_empty(),"Invalid target center accepted")
	check(geometry.bounds(Vector3(-3e38,0,0),Vector3.ZERO,Vector3(3e38,0,0),1).is_empty(),"Overflowed contact arithmetic accepted")
	check(geometry.point_geometry(Vector3(7,8,9),false)=={"hit":false,"path":"point_geometry","sample_position":Vector3(7,8,9)},"Point miss changed or fell back to bounds")
	check(geometry.point_geometry(Vector3(7,8,9),true).hit,"Point hit was rejected")
	check(geometry.point_geometry(Vector3.ZERO,null).is_empty(),"Missing point-geometry provider result accepted")
	check_impacts(geometry)
	print("Ordinary hit geometry checks: %d failures" % failures)
	quit(1 if failures else 0)

func check_impacts(geometry: RefCounted) -> void:
	var projectiles := Projectiles.new()
	var weapon := {"base_content_id":"a".repeat(64),"binding_id":"b".repeat(64),"item_id":2,
		"category":0,"kind":0,"damage":6,"interval_ms":5,"lifetime_ms":10,
		"speed_units_per_millisecond":20.0,"launch_mode":"ordinary","projectile_capacity":2}
	check(projectiles.configure(weapon),projectiles.error)
	projectiles.advance(1)
	var shot: Dictionary = projectiles.fire(Vector3(20,0,0),Vector3.RIGHT,true)
	var before: Dictionary = projectiles.snapshot()
	check(geometry.bounds(shot.projectile.position,shot.projectile.velocity,Vector3.ZERO,2).hit,"First overlapping target missed")
	check(projectiles.mark_impact(shot.projectile.id),projectiles.error)
	var impacted: Dictionary = projectiles.snapshot().slots[0]
	check(impacted.position==before.slots[0].position and impacted.velocity==before.slots[0].velocity and impacted.remaining_ms==-1000000,"Impact removed or changed source geometry")
	check(geometry.bounds(impacted.position,impacted.velocity,Vector3.ONE,2).hit,"Impact hid projectile from a later overlapping target")
	check(projectiles.mark_impact(shot.projectile.id),"Later impact could not mark same projectile")
	var frozen: Dictionary = projectiles.snapshot()
	var clean: Dictionary = projectiles.advance(0)
	check(projectiles.snapshot().elapsed_ms==frozen.elapsed_ms,"Zero-time cleanup advanced the gun clock")
	check(clean.cleared==[shot.projectile.id] and clean.moved.is_empty() and projectiles.snapshot().slots[0]==null,"Impacted projectile moved before cleanup")
	check(not projectiles.mark_impact(shot.projectile.id),"Cleaned impact handle remained valid")
	projectiles.advance(6)
	var expiring: Dictionary = projectiles.fire(Vector3.ZERO,Vector3.RIGHT,true)
	projectiles.advance(10)
	var expired: Dictionary = projectiles.snapshot().slots[0]
	check(expired.remaining_ms==0 and geometry.bounds(expired.position,expired.velocity,Vector3(180,0,0),1).hit,"Final lifetime position unavailable for next collision pass")
	check(projectiles.mark_impact(expiring.projectile.id),"Retained expired projectile could not be marked")
	var reused: Dictionary = projectiles.fire(Vector3.ZERO,Vector3.RIGHT,true)
	check(reused.get("fired",false) and reused.projectile.id!=expiring.projectile.id,"Impacted slot could not be reused with a fresh handle")
	frozen=projectiles.snapshot()
	check(not projectiles.mark_impact(expiring.projectile.id) and projectiles.snapshot()==frozen,"Stale impact changed reused slot")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
