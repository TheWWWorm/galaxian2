extends "res://tests/first_flight_session.gd"
## Controlled positions isolate contact order in the real mining session.
## No resulting station save or campaign progress is claimed.

func mine_trip(_args: PackedStringArray) -> bool:
	var flight: RefCounted=host.session.flight_owner()
	check(flight.snapshot().scenery_collision_supported,"Imported content lacks physical-contact integration")
	if failures:return false
	var original: Dictionary=flight.snapshot()
	var asteroid: Dictionary=original.scenery.bodies.objects[0]
	var travel: Vector3=flight._pilot.coast(Transform3D.IDENTITY,1.0,0.1).origin
	var forward:=travel.normalized()
	flight._pose=Transform3D(Basis.IDENTITY,asteroid.position-forward*(float(asteroid.half_extent)+travel.length()*0.5))
	flight._statistics_pose=flight._pose;flight._pilot.angular_units=Vector2.ZERO
	flight._collision_enabled=true
	check(flight._autopilot.observe_scripted_pose(flight._pose),flight._autopilot.error)
	var prior: Dictionary=flight.snapshot()
	var expected_player: RefCounted=flight._player.fork_for_frame()
	var impact: Dictionary=expected_player.normal_hit(20)
	check(not impact.is_empty(),expected_player.error)
	var next: RefCounted=flight.evaluate(100,Vector2.ZERO,1.0)
	if next==null:check(false,flight.error);return false
	var state: Dictionary=next.snapshot()
	check(flight.snapshot()==prior,"Prospective physical contact mutated the accepted frame")
	check(state.scenery.bodies.objects[asteroid.index].vitals.hull==0 and state.scenery.bodies.objects[asteroid.index].contact,"Post-motion entry into an asteroid did not damage/mark its body")
	check(state.player.vitals.hull==expected_player.snapshot().vitals.hull and state.player.vitals.armor==expected_player.snapshot().vitals.armor,"Asteroid contact did not apply the source player damage")
	check(state.scenery.destruction[asteroid.index].lifecycle.actor_state!=0,"Physical destruction bypassed its native explosion lifecycle")
	check(host.session._commit(next,false),host.session.error)
	if failures:return false
	var held: Dictionary=host.session.snapshot()
	check(held.scenery.bodies.objects[asteroid.index].vitals.hull==0,"Accepted renderer lost the destroyed asteroid")
	check(host.session.scene.scenery.destruction!=null,"Live flight omitted the source scenery destruction layer")
	check(not host.session.scene.scenery.objects[asteroid.index].visible,"Destroyed Var Hastra asteroid remained visible as an intact mesh")
	if failures:return false
	var station: Dictionary=flight._station.snapshot()
	var shape: Dictionary=station.collision.get("shapes",station.collision.boxes)[0]
	var touching: RefCounted=flight.fork_for_frame()
	touching._pose.origin=station.pose.origin+shape.center
	touching._statistics_pose=touching._pose
	check(touching._autopilot.observe_scripted_pose(touching._pose),touching._autopilot.error)
	var station_before: Dictionary=touching._player.snapshot()
	var pushed: RefCounted=touching.evaluate(0,Vector2.ZERO,0.0)
	if pushed==null:check(false,touching.error);return false
	check(pushed.snapshot().player_pose.origin!=touching.snapshot().player_pose.origin,"Station authored volume did not project the ship outside")
	check(pushed.snapshot().player.vitals==station_before.vitals,"Station contact invented impact damage")
	check(pushed._autopilot.snapshot().player_pose==pushed.snapshot().player_pose,"Guidance retained the rejected pre-contact pose")
	return false
