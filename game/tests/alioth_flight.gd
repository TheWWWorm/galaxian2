extends "res://tests/convoy_application.gd"
## The inherited path earns its station; only earlier diagnostic combat is
## expedited. This encounter starts at the original position and uses NPC fire.
const AliothCheckpoint=preload("res://tests/fixtures/alioth_station_scenario.gd")
const Attack=preload("res://src/simulation/alioth_attack.gd")

func _initialize() -> void:
	call_deferred("run_alioth_checkpoint" if not OS.get_environment("GOF2_ALIOTH_STATION_SCENARIO").is_empty() else "run_progression")

func after_four_successes() -> void:
	await super.after_four_successes()
	if failures:return
	var station: RefCounted=app.session.station_owner()
	var path:=OS.get_environment("GOF2_CAPTURE_ALIOTH_STATION")
	if not path.is_empty():
		var checkpoint:=AliothCheckpoint.new()
		if not checkpoint.capture(path,station,definitions):check(false,checkpoint.error);return
	await verify_alioth_station(station)

func run_alioth_checkpoint() -> void:
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,720)
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3:check(false,"Expected explicit content, bindings and visuals");quit(1);return
	source=load("res://src/content/library.gd").new();definitions=load("res://src/content/resource_bindings.gd").new();catalogue=load("res://src/content/catalogues.gd").new();visual=Visuals.new()
	if not source.open(args[0]) or not definitions.open(args[1],source.manifest) or not catalogue.open(source) or not source.select_language("gb") or not visual.open(args[2],source.manifest):check(false,source.error+definitions.error+catalogue.error+visual.error);quit(1);return
	var checkpoint:=AliothCheckpoint.new()
	var station: RefCounted=checkpoint.open(OS.get_environment("GOF2_ALIOTH_STATION_SCENARIO"),definitions)
	if station==null:check(false,checkpoint.error)
	else:await verify_alioth_station(station)
	print("Alioth flight: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify_alioth_station(station: RefCounted) -> void:
	var before: Dictionary=station.snapshot()
	if is_instance_valid(app):app.hide()
	var live: Node3D=await prepare_alioth_flight(station)
	if live==null:return
	var frame: RefCounted=live.flight_owner()
	var initial: Dictionary=frame.snapshot()
	check(initial.player_pose.origin==Vector3(10,10,10000),"Alioth departure replaced the actual ordinary player position")
	check(initial.actors.size()==10 and initial.alioth_portal.position==Vector3(0,0,210000),"Alioth lost the authored cast or relocated portal")
	check(station.snapshot()==before and frame.convoy_career_owner().snapshot()==before.contracts,"Preparing flight changed the retained career")
	var seen:=[];var lines:=[];var first_motion:=false;var escape_suspended:=false
	var seen_deaths:=[]
	print("Alioth production scene prepared at ",initial.player_pose.origin)
	for tick in 4000:
		var previous: Dictionary=frame.snapshot()
		if frame.dialogue_visible():
			var id:=int(previous.dialogue.text_id)
			lines.append(id)
			if id in [1811,1820]:await capture_alioth_view(live,frame,"alioth-line-%d"%id,true)
			var frozen: RefCounted=frame.evaluate(150,Vector2.ONE,1.0)
			if frozen==null:check(false,frame.error);break
			var frozen_state: Dictionary=frozen.snapshot()
			check(frozen_state.world_elapsed_ms==previous.world_elapsed_ms and frozen_state.player_pose==previous.player_pose and frozen_state.alioth_portal.animation_elapsed_ms==previous.alioth_portal.animation_elapsed_ms and frozen_state.alioth_attack.elapsed_ms==previous.alioth_attack.elapsed_ms,"Alioth modal instruction advanced flight time")
			var acknowledged: RefCounted=frame.navigate("next")
			if acknowledged==null:check(false,frame.error);break
			frame=acknowledged
			if not live._commit(frame,false):check(false,live.error);break
			if frame.snapshot().campaign_cursor==17:break
			continue
		# Fly using the ordinary throttle; the ship is never teleported and no
		# actor damage, radio flags or completion state is supplied by the test.
		var throttle:=1.0 if previous.player_pose.origin.z<140000 else 0.0
		var next: RefCounted=frame.evaluate(150,Vector2.ZERO,throttle)
		if next==null:check(false,frame.error);break
		frame=next
		if not live._commit(frame,true):check(false,live.error);break
		var current: Dictionary=frame.snapshot()
		var phase:=int(current.alioth_attack.phase)
		if phase not in seen:
			seen.append(phase)
			print("Alioth phase ",phase," at ",current.world_elapsed_ms,"ms; player ",current.player_pose.origin)
			check(frame.evaluate(150,Vector2.ONE,1.0,true).snapshot()==current,"Paused Alioth changed flight or its sequence")
			if not verify_alioth_stage(live,frame):break
			await capture_alioth_view(live,frame,"alioth-phase-%d"%phase)
		for id in 3:
			if current.actors[id].vitals.hull==0 and id not in seen_deaths:
				seen_deaths.append(id);print("Alioth NPC fire destroyed freighter ",id," at ",current.world_elapsed_ms,"ms")
		if phase==Attack.Stage.FREIGHTER_VIEW and previous.alioth_attack.phase==phase and current.player_pose!=previous.player_pose:first_motion=true
		if current.alioth_attack.player_update_suspended and previous.alioth_attack.player_update_suspended:
			escape_suspended=true
			if current.player_pose!=previous.player_pose or current.player!=previous.player:check(false,"Escape view updated the suspended player");break
		if frame.cinematic_input_blocked() and phase not in [Attack.Stage.ATTACK,Attack.Stage.BATTLE,Attack.Stage.ESCAPE_READY,Attack.Stage.RETURN_FLIGHT]:
			if frame.start_station_autopilot()!=null or frame.start_mining()!=null:check(false,"Cinematic accepted player actions");break
		if frame.death_active():check(false,"Player died on the actual Alioth flight path");break
		if tick%100==0:await process_frame
	var final: Dictionary=frame.snapshot()
	check(final.campaign_cursor==17 and final.combat_objective_satisfied and final.combat_objective_acknowledged,"Alioth did not reach its acknowledged return mission")
	check(seen==[0,1,2,3,4,5,6] and seen_deaths.size()==3,"Alioth omitted source choreography or actual freighter deaths")
	check(first_motion and escape_suspended,"Alioth did not preserve the two different player update policies")
	check(lines==[1811,1812,1818,1819,1820],"Alioth skipped an acknowledged source line: "+str(lines))
	check(final.radio.finished==[true,true,true,true,true] and live.flight_audio.snapshot().voice_displayed==[true,true,true,true,true],"Alioth omitted original timed dialogue or voice")
	check(final.progress.player_kills==initial.progress.player_kills and final.mission=={"kind":11,"station_id":98,"reward":0,"bonus":0,"source_parameter":0},"Scripted departure invented player kills or a mission reward")
	check(station.snapshot()==before,"Detached flight changed its original station")
	print("Alioth final at ",final.world_elapsed_ms,"ms; lines ",lines,"; phases ",seen)
	if failures==0:await after_alioth_flight(live,frame,station)
	release_alioth_flight(live if is_instance_valid(live) else null)

func prepare_alioth_flight(station: RefCounted) -> Node3D:
	var live:=FlightSession.new();root.add_child(live)
	if not live.configure_alioth(source,definitions,visual,station,now_us,4096,1789100000) or not live.activate():check(false,live.error);live.free();return null
	return live

func after_alioth_flight(_live: Node3D,_frame: RefCounted,_station: RefCounted) -> void:pass
func verify_alioth_stage(_live: Node3D,_frame: RefCounted) -> bool:return true
func release_alioth_flight(live: Node3D) -> void:
	if is_instance_valid(live):live.free()

func capture_alioth_view(live: Node3D,frame: RefCounted,label: String,with_mobile:=false) -> void:
	var directory:=OS.get_environment("GOF2_ALIOTH_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name()=="headless":return
	if not AliothCheckpoint.private_path(directory+"/capture.png"):check(false,"Keep Alioth captures outside engine source");return
	DirAccess.make_dir_recursive_absolute(directory)
	_refresh_capture_host(live)
	await process_frame
	_refresh_capture_host(live)
	RenderingServer.force_draw(false);await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(label+".png"))==OK,"Cannot capture Alioth flight")
	if not with_mobile:return
	var before: Dictionary=frame.snapshot()
	root.size=Vector2i(960,540);live.scene.set_mobile_layout(true)
	if is_instance_valid(app) and app.session==live:app.set_mobile_layout(true);app.set_touch_controls(true)
	await process_frame
	_refresh_capture_host(live)
	var mobile: RefCounted=frame.evaluate(0,Vector2.ZERO,0.0,false,Vector2i(live.get_viewport().get_visible_rect().size))
	if mobile==null or not live.scene.present(mobile):check(false,frame.error+live.scene.error)
	else:
		await process_frame;RenderingServer.force_draw(false);await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(directory.path_join(label+"-mobile.png"))==OK,"Cannot capture landscape Alioth UI")
	root.size=Vector2i(1280,720);live.scene.set_mobile_layout(false)
	if is_instance_valid(app) and app.session==live:app.set_mobile_layout(false);app.set_touch_controls(false)
	check(live.scene.present(frame) and frame.snapshot()==before,"Landscape presentation changed the accepted flight")
	_refresh_capture_host(live)

func _refresh_capture_host(live: Node3D) -> void:
	if is_instance_valid(app) and app.session==live:
		resume_application_focus();app.present_session()
