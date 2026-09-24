extends "res://tests/player_station_departure.gd"
## An untouched earned Gunant save supplies the ordinary Var Hastra field and
## Microgun. Only the test ship pose and throttle are placed for a short contact.

func verify_departure(app: Control) -> void:
	await super.verify_departure(app)
	if failures:return
	var session: Node=app.game.session
	var flight: RefCounted=session.flight_owner()
	var before: Dictionary=flight.snapshot()
	check(before.scenery.destruction.size()==before.scenery.objects.size() and session.scene.scenery.destruction!=null,"Earned Var Hastra flight omitted prepared scenery lifecycles")
	if failures:return
	var asteroid: Dictionary=before.scenery.bodies.objects[0]
	for body in before.scenery.bodies.objects:
		if int(body.vitals.hull)<int(asteroid.vitals.hull):asteroid=body
	var origin: Vector3=asteroid.position-Vector3.BACK*(float(asteroid.half_extent)+100.0)
	flight._pose=Transform3D(Basis.IDENTITY,origin)
	flight._statistics_pose=flight._pose
	flight._collision_enabled=false
	flight._pilot.angular_units=Vector2.ZERO
	check(session._commit(flight,false),session.error)
	if failures:return
	session._throttle=0.0
	session.rebase_time(0)
	app.game.present_session()
	await capture("asteroid-before-gunfire")
	var fired:=false
	var contacted:=false
	var destroyed:=false
	var destruction_tick:=-1
	for tick in 180:
		check(session.step((tick+1)*100000,Vector2.ZERO,true),session.error)
		if failures:return
		var state: Dictionary=session.snapshot()
		var shot: Dictionary=state.encounter.primary_fire
		fired=fired or (not shot.is_empty() and shot.weapons.any(func(row):return row.result.fired))
		contacted=contacted or int(state.scenery.bodies.objects[asteroid.index].vitals.hull)<int(asteroid.vitals.hull)
		if int(state.scenery.bodies.objects[asteroid.index].vitals.hull)==0:
			destroyed=true;destruction_tick=tick
			check(state.scenery.destruction[asteroid.index].lifecycle.actor_state==3,"Gunfire did not enter the source breakup lifecycle")
			check(not session.scene.scenery.objects[asteroid.index].visible and session.scene.scenery.destruction._effects.has(asteroid.index),"Destroyed ordinary asteroid retained its intact mesh or lacked breakup geometry")
			app.game.present_session()
			await capture("asteroid-gunfire-breakup")
			break
	check(fired and contacted and destroyed,"Earned Microgun did not destroy the generated Var Hastra asteroid: "+str({"fired":fired,"contacted":contacted,"destroyed":destroyed,"hull":session.snapshot().scenery.bodies.objects[asteroid.index].vitals.hull}))

	if failures:return
	var retired:=false
	for tick in 80:
		check(session.step((destruction_tick+tick+2)*100000),session.error)
		if failures:return
		var state: Dictionary=session.snapshot()
		check(not session.scene.scenery.objects[asteroid.index].visible,"Breakup revealed the destroyed intact asteroid again")
		if tick==3:
			app.game.present_session()
			await capture("asteroid-breakup-advancing")
		if int(state.scenery.destruction[asteroid.index].lifecycle.actor_state)==4:
			retired=true
			check(not session.scene.scenery.destruction._effects.has(asteroid.index),"Completed breakup left a permanent effect model")
			app.game.present_session()
			await capture("asteroid-breakup-finished")
			break
	check(retired,"Destroyed asteroid breakup never completed")
