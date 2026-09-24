extends "res://tests/first_flight_session.gd"
## A controlled damaged-ship branch verifies a lethal physical contact through
## the real mining session. It earns no cargo, reward or saved campaign progress.

func mine_trip(args: PackedStringArray) -> bool:
	var flight: RefCounted=host.session.flight_owner()
	var parent: Dictionary=flight.snapshot()
	check(parent.scenery_collision_supported,"This content lacks physical scenery contacts")
	var before: RefCounted=flight.fork_for_frame()
	check(not before._player.normal_hit(76).is_empty(),before._player.error)
	check(before._player.snapshot().vitals.hull==19,"The controlled branch did not retain its real starter pools")
	var asteroid: Dictionary=before.snapshot().scenery.bodies.objects[0]
	before._pose.origin=asteroid.position+Vector3(float(asteroid.half_extent)*0.5,0,0)
	before._statistics_pose=before._pose
	check(before._autopilot.observe_scripted_pose(before._pose),before._autopilot.error)
	var lethal: RefCounted=before.evaluate(0,Vector2.ZERO,0.0)
	if lethal==null:check(false,before.error);return false
	var state: Dictionary=lethal.snapshot()
	check(state.player.vitals.hull==0,"Asteroid contact did not exhaust the damaged starter hull")
	check(lethal.death_active() and state.get("player_destruction",{}).get("phase")=="tumble","First-mining collision death did not enter the shared native lifecycle")
	check(flight.snapshot()==parent,"Controlled lethal branch mutated the retained mining world")
	if failures:return false
	var sound_start: int=host.session.flight_audio.snapshot().history.size()
	check(host.session._commit(lethal,false),host.session.error)
	host.present_session()
	check(not host.session.can_control() and not host.flight_vitals.visible,"Lethal contact left flight input or HUD active")
	var stopped_audio: Dictionary=host.session.flight_audio.snapshot()
	check(not stopped_audio.active.has(stopped_audio.music_id),"Lethal contact retained ordinary music playback")
	for tick in 250:
		if host.session.snapshot().player_destruction.phase=="game_over":break
		if not step():return false
	state=host.session.snapshot()
	check(state.player_destruction.game_over_visible and state.player_destruction.phase=="game_over","Collision death did not reach its source game-over display")
	check(state.cargo==parent.cargo and state.mining_objective.campaign_cursor==parent.mining_objective.campaign_cursor,"Collision death changed cargo or completed the mining objective")
	check(host.session.scene.game_over!=null and host.session.scene.game_over.visible,"The native death lifecycle had no visible continuation panel")
	check(state.damage_particles.burst_count==1 and state.damage_particles.owners.keys()==["player","world"],"First-mining death lost its single source burst or invented particle owners")
	var sounds: Array=host.session.flight_audio.snapshot().history.slice(sound_start)
	check(sounds.filter(func(op):return op.get("action")=="stop_music").size()==1 and not sounds.any(func(op):return op.get("action")=="replace_music"),"Death lost its music stop or restarted ordinary music")
	var breakup_base:=int(bindings.player_destruction.breakup_sound_base)
	var breakup_bound:=int(bindings.player_destruction.breakup_sound_bound)
	check(sounds.filter(func(op):return op.get("action")=="start_spatial" and int(op.get("source_id",-1))>=breakup_base and int(op.get("source_id",-1))<breakup_base+breakup_bound).size()==1,"First-mining breakup sound was lost or repeated")
	check(sounds.filter(func(op):return op.get("action")=="start" and op.get("source_id")==int(bindings.player_destruction.failure_sound)).size()==1,"First-mining failure sound was lost or repeated")
	if args.size()==4:await capture(args[3],"first-mining-collision-game-over")
	key(KEY_SPACE)
	check(host.session.status=="game_over_transition_required",host.session.error)
	check(host.enter_game_over(),host.status.text)
	check(host.session==null and host.game_over_result().transition.campaign_cursor==2,"Game-over continuation did not return from the first mining flight")
	return false
