extends "res://tests/lounge_progression.gd"
## Four earned jobs and an actual return to Kernstal precede the new native scene.
## A disclosed lethal test contact expedites choreography, never career setup.
const ConvoyConstruction=preload("res://src/simulation/first_flight_construction.gd")
const ConvoyFrame=preload("res://src/simulation/first_flight_frame.gd")
const ConvoyBodies=preload("res://src/content/scenery_body_resources.gd")
const ConvoyEffects=preload("res://src/content/scenery_effect_resources.gd")
const Checkpoint=preload("res://tests/fixtures/convoy_station_scenario.gd")
const Capture=preload("res://src/simulation/convoy_capture.gd")
const EmpRules=preload("res://src/content/convoy_effect_definitions.gd")

func _initialize() -> void:
	if OS.get_environment("GOF2_CONVOY_STATION_SCENARIO").is_empty():call_deferred("run_progression")
	else:call_deferred("run_checkpoint")

func run_checkpoint() -> void:
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,720)
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3:check(false,"Expected explicit content, bindings and visuals");quit(1);return
	source=load("res://src/content/library.gd").new();definitions=load("res://src/content/resource_bindings.gd").new();catalogue=load("res://src/content/catalogues.gd").new();visual=Visuals.new()
	if not source.open(args[0]) or not definitions.open(args[1],source.manifest) or not catalogue.open(source) or not source.select_language("gb") or not visual.open(args[2],source.manifest):check(false,source.error+definitions.error+catalogue.error+visual.error);quit(1);return
	var checkpoint:=Checkpoint.new()
	var station: RefCounted=checkpoint.open(OS.get_environment("GOF2_CONVOY_STATION_SCENARIO"),definitions)
	if station==null:check(false,checkpoint.error)
	else:await verify_convoy_station(station)
	print("Convoy checkpoint: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func after_four_successes() -> void:
	super.after_four_successes()
	if failures:return
	var actual: RefCounted=app.session.station_owner()
	var distant: RefCounted=actual.fork()
	if not distant.begin_contract_conversation(definitions,catalogue,source) or not distant.acknowledge() or not distant.acknowledge():check(false,distant.error);return
	var refusal:=ConvoyConstruction.new()
	if actual.snapshot().loadout.station_id!=79:
		check(not refusal.prepare_convoy(definitions,catalogue,distant,4096,1789100000),"The story teleported a distant station into the convoy")
		if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
		if not await release_application_flight() or not await travel_application(79) or not await dock_application():return
	actual=app.session.station_owner()
	var capture_path:=OS.get_environment("GOF2_CAPTURE_CONVOY_STATION")
	if not capture_path.is_empty():
		var checkpoint:=Checkpoint.new()
		if not checkpoint.capture(capture_path,actual,definitions):check(false,checkpoint.error);return
	await verify_convoy_station(actual)

func verify_convoy_station(actual: RefCounted) -> void:
	var before: Dictionary=actual.snapshot()
	var station: RefCounted=actual.fork()
	if not station.begin_contract_conversation(definitions,catalogue,source) or not station.acknowledge() or not station.acknowledge():check(false,station.error);return
	var bodies:=ConvoyBodies.new();var effects:=ConvoyEffects.new()
	if not bodies.configure(source,definitions) or not effects.configure(source,definitions):check(false,bodies.error+effects.error);return
	var construction:=ConvoyConstruction.new()
	if not construction.prepare_convoy(definitions,catalogue,station,4096,1789100000,true,bodies,effects):check(false,construction.error);return
	check(actual.snapshot()==before,"Preparing the convoy changed the docked application")
	check(construction.snapshot().player_pose.origin==Vector3(40000,0,120000),"Convoy started at a generic mining position")
	check(construction.snapshot().departure.cargo==before.cargo and construction.snapshot().departure.contracts.credits==before.contracts.credits,"Departure lost earned cargo or paid an extra reward")
	if is_instance_valid(app):app.hide()
	var live:=FlightSession.new();root.add_child(live)
	if not live.configure_convoy(source,definitions,visual,station,now_us,4096,1789100000) or not live.activate():check(false,live.error);live.free();return
	var frame: RefCounted=live.flight_owner()
	print("Convoy native scene prepared from four earned jobs at Kernstal")
	var first: Dictionary=frame.snapshot();var lethal:=false;var disabled:=false;var hidden:=false;var moved_camera:=false
	var previous_disabled:=Transform3D.IDENTITY
	var captured:=[];var death_checked:=false;var emp_sounds:=0
	var emp_checked:=false
	for tick in 1000:
		if frame.dialogue_visible():
			var acknowledged: RefCounted=frame.navigate("next")
			if acknowledged==null:check(false,frame.error);return
			frame=acknowledged
			if not live._commit(frame,false):check(false,live.error);live.free();return
		if not death_checked and frame.snapshot().world_elapsed_ms>=10000 and not frame.dialogue_visible():
			death_checked=true
			if not verify_lethal_branch(frame,live.scene):live.free();return
		if not lethal and frame.snapshot().world_elapsed_ms>=20000:
			var combat: RefCounted=frame._encounter._combat
			if not combat.begin_contact_pass(frame.snapshot().random_state,true) or combat.normal_hit(1,combat.snapshot().actors[1].vitals.hull,true).is_empty():check(false,combat.error);return
			lethal=true
		var next: RefCounted=frame.evaluate(100,Vector2(.2,-.1),0.0,false,Vector2i(1280,720),Vector2.ZERO,false)
		if next==null:check(false,frame.error);return
		frame=next
		var sound_revision: int=live.flight_audio.snapshot().revision
		if not live._commit(frame,true):check(false,live.error);live.free();return
		for operation in live.flight_audio.snapshot().history:
			if operation.revision>sound_revision and operation.get("source_id")==15 and operation.action in ["start","start_spatial"]:emp_sounds+=1
		var current: Dictionary=frame.snapshot()
		if EmpRules.available(definitions) and current.convoy_capture.phase==Capture.Stage.DISABLED and not emp_checked:
			emp_checked=true
			var particles: Dictionary=current.damage_particles
			check(particles.emp.bound_to_player,"Live convoy never bound its EMP sprites to Betty")
			var retained_particles: RefCounted=frame.damage_particle_owner()
			check(not retained_particles.apply_convoy_capture(frame._convoy) and retained_particles.snapshot()==particles,"Repeated capture replayed the particle activation")
			for kind in ["emp17","emp18"]:
				var sprite: Dictionary=particles.owners.npc0[kind]
				check(sprite.enabled and sprite.visible and sprite.baseline==current.player_pose.origin and sprite.slots.any(func(slot):return slot.appearance.age_ms>=0),"Live EMP sprite has no attached visible particles: "+kind)
				for id in range(1,5):check(not particles.owners["npc%d"%id][kind].enabled,"Capture enabled another fighter's EMP")
			await capture_view("convoy-emp-active")
		if current.convoy_capture.phase not in captured and not frame.dialogue_visible():
			if current.convoy_capture.phase==Capture.Stage.PULSE:
				if not verify_capture_mining(frame,live.scene) or not verify_capture_guidance(frame):live.free();return
			captured.append(current.convoy_capture.phase)
			check(frame.evaluate(100,Vector2.ONE,1.0,true).snapshot()==current,"Paused convoy changed actors, cues or capture time")
			var history: Array=live.flight_audio.snapshot().history
			if not live._commit(frame,false):check(false,live.error);live.free();return
			check(live.flight_audio.snapshot().history==history,"Presenting the same capture frame replayed audio")
			await capture_view("convoy-phase-%d"%current.convoy_capture.phase)
		if frame.death_active():check(false,"Player died before the diagnostic capture completed");return
		if frame.convoy_input_blocked():
			if disabled:check(current.player_pose==previous_disabled,"Disabled player moved under held steering")
			previous_disabled=current.player_pose;disabled=true
			check(not current.player_aim.visible,"Disabled capture left flight targeting active")
			check(frame.start_station_autopilot()==null and frame.start_mining()==null,"Capture accepted a flight action")
		if not current.convoy_capture.ship_visible:hidden=true
		if current.convoy_capture.phase>=Capture.Stage.CAPTURE_VIEW:
			if EmpRules.available(definitions):check(current.damage_particles.owners.npc0.emp17.enabled and current.damage_particles.owners.npc0.emp18.enabled,"Capture view redirected the nozzle stop to the EMP manager")
			moved_camera=current.camera_shot.target=="actor" and current.camera_shot.actor_id==6
		if frame.convoy_arrival_required():break
	var final: Dictionary=frame.snapshot()
	check(frame.convoy_arrival_required() and final.boundary=="convoy_arrival_transition_required","Production frame did not reach its Alioth request: "+str(final.convoy_capture))
	check(disabled and hidden and moved_camera,"Production frame omitted disabled flight, ship hiding or capital-ship camera")
	check(final.campaign_cursor==14 and final.progress.campaign_cursor==14 and not final.combat_objective_satisfied,"Capture granted premature campaign completion")
	check(final.convoy_capture.arrival=={"campaign_cursor":15,"station_id":98,"source_state":5,"mission_kind":11,"source_parameter":0,"reward":0,"bonus":0},"Convoy requested another destination or a reward")
	check(final.actors.slice(0,3).all(func(actor):return actor.convoy_script_retired),"Capture left a pirate active")
	check(final.progress.player_kills==first.progress.player_kills,"Direct retirement awarded player kills")
	check(death_checked and emp_sounds==2,"Capture omitted the death branch check or its two original EMP sounds")
	check(not EmpRules.available(definitions) or emp_checked,"The scene skipped its attached EMP verification")
	check(live.flight_audio.snapshot().voice_displayed==[true,true,true,true,true],"Capture omitted an original timed transmission")
	check(frame.evaluate(100).snapshot()==final,"Pending station arrival advanced the convoy again")
	print("Convoy production frame request at ",final.world_elapsed_ms,"ms; native camera ",final.camera_view.eye)
	await after_convoy(frame,live)
	live.free()

func after_convoy(_frame: RefCounted,_live: Node3D) -> void:
	pass

func verify_capture_mining(original: RefCounted,scene: Node3D) -> bool:
	# Explicit close placement selects an actual core asteroid in this field.
	# The approach, radio, capture, drill and extraction all run natively.
	var before: Dictionary=original.snapshot();var branch: RefCounted=original.fork_for_frame();var asteroid:={}
	for body in before.scenery.bodies.objects:
		if body.source_size_value==7:asteroid=body;break
	if asteroid.is_empty():check(false,"The convoy field has no core asteroid for the mining branch");return false
	var distance:=float(int(asteroid.scale*2500))-.5
	branch._pose=Transform3D(Basis(Vector3.UP,PI),asteroid.position+Vector3(0,0,distance))
	branch._pilot.angular_units=Vector2.ZERO;branch._targeting._selected=int(asteroid.index)
	if not branch._autopilot.observe_manual(branch._pose,Vector2.ZERO):check(false,branch._autopilot.error);return false
	var selected: RefCounted=branch.start_mining()
	if selected==null:check(false,branch.error);return false
	branch=selected;var blocked_drill:=false
	for tick in 240:
		var current: Dictionary=branch.snapshot()
		if branch.convoy_input_blocked() and branch.drill_owner()!=null:
			blocked_drill=true
			var a: RefCounted=branch.evaluate(100,Vector2.ONE,1,false,Vector2i(1280,720),Vector2.ONE)
			var b: RefCounted=branch.evaluate(100,-Vector2.ONE,0,false,Vector2i(1280,720),-Vector2.ONE)
			if a==null or b==null:check(false,branch.error);return false
			check(a.snapshot().mining_session==b.snapshot().mining_session,"Capture accepted new drill controls")
			var mining: Dictionary=a.snapshot().mining_session
			check(a.drill_owner()==null or mining.drill.elapsed_ms==current.mining_session.drill.elapsed_ms+100,"Capture froze an already running drill")
			check(branch.evaluate(100,Vector2.ONE,1,true).snapshot()==current,"Pause advanced capture mining")
			check(branch.stop_mining()==null and branch.cancel_mining()==null,"Capture accepted a disabled mining action")
			var invalid: RefCounted=branch.fork_for_frame()
			invalid._scenery._bodies=invalid._scenery._bodies.fork_for_frame()
			check(invalid._scenery._bodies.normal_hit(int(asteroid.index),100000).destroyed_now,"Could not supply the unavailable-target diagnostic")
			var cancelled: RefCounted=invalid.evaluate(100)
			if cancelled==null:check(false,invalid.error);return false
			check(cancelled.drill_owner()==null and cancelled.snapshot().mining_session.phase=="cancelled" and cancelled.snapshot().cargo==current.cargo and cancelled.snapshot().scenery.mined_count==current.scenery.mined_count,"Unavailable capture-mining target granted extraction")
			check(branch.snapshot()==current,"Rejected-target branch changed accepted capture mining")
			check(a.snapshot().mining_approach.model_basis==a.snapshot().player_model_basis,"Capture drift was lost by the active mining owner")
			branch=a
			break
		var next: RefCounted=branch.evaluate(100,Vector2.ZERO,0,false,Vector2i(1280,720),Vector2.ZERO)
		if next==null:check(false,branch.error);return false
		branch=next
	check(blocked_drill,"The diagnostic did not overlap a native drill with capture")
	if not blocked_drill:return false
	for tick in 160:
		if branch.drill_owner()==null:break
		var next: RefCounted=branch.evaluate(100,Vector2.ONE,1,false,Vector2i(1280,720),Vector2.ONE)
		if next==null:check(false,branch.error);return false
		branch=next
	var after: Dictionary=branch.snapshot()
	check(branch.drill_owner()==null and after.mining_session.phase=="finished" and after.scenery.mined_count==before.scenery.mined_count+1,"Capture mining failed to finish its ordinary extraction")
	check(after.cargo==branch.equipment_owner().snapshot().cargo and after.progress.campaign_cursor==14,"Capture mining lost retained cargo or advanced the campaign")
	if not scene.present(branch):check(false,scene.error);return false
	check(scene.mining_panel==null or not scene.mining_panel.visible,"Finished capture mining left its drill panel visible")
	check(original.snapshot()==before,"Diagnostic capture mining changed the accepted flight")
	if not scene.present(original):check(false,scene.error);return false
	print("Capture mining continued to ",after.mining_session.extraction.phase," with ",after.cargo.used," cargo units retained")
	return failures==0

func verify_capture_guidance(original: RefCounted) -> bool:
	var before: Dictionary=original.snapshot()
	var branch: RefCounted=original.start_station_autopilot()
	if branch==null:check(false,original.error);return false
	for tick in 150:
		if branch.convoy_input_blocked():break
		var next: RefCounted=branch.evaluate(100)
		if next==null:check(false,branch.error);return false
		branch=next
	var frozen: Dictionary=branch.snapshot()
	check(branch.convoy_input_blocked() and frozen.station_autopilot.active,"Capture discarded retained station guidance")
	var next: RefCounted=branch.evaluate(100,Vector2.ONE,1)
	if next==null:check(false,branch.error);return false
	check(next.snapshot().player_pose==frozen.player_pose and next.snapshot().station_autopilot==frozen.station_autopilot,"Capture advanced gated guidance under held controls")
	check(original.snapshot()==before,"Guidance diagnostic changed the accepted convoy")
	return failures==0

func verify_lethal_branch(original: RefCounted,scene: Node3D) -> bool:
	# Explicit diagnostic contacts use the actual initialized pirate weapon.
	# The earned career and the successful capture branch remain untouched.
	var before: Dictionary=original.snapshot()
	var branch: RefCounted=original.fork_for_frame()
	var weapon: Dictionary=branch._player._npc_weapons[0]
	for hit in 4096:
		if branch._player.snapshot().vitals.hull==0:break
		if branch._player.weapon_hit(weapon,true,true,false).is_empty():check(false,branch._player.error);return false
	check(branch._player.snapshot().vitals.hull==0,"Diagnostic contacts did not exhaust the actual player pools")
	var sequence_key:="alioth_attack" if before.has("alioth_attack") else "convoy_capture"
	var initial_capture: Dictionary=before[sequence_key]
	var death_rules: Dictionary=definitions.player_destruction
	var death_frames:=ceili(float(death_rules.failure_after_ms+death_rules.failure_delay_ms+death_rules.fade_ms)/150.0)+5
	for tick in death_frames:
		if branch.dialogue_visible():
			# A fixture acknowledgement is still required if the initial briefing
			# opens during destruction; production must not auto-dismiss it.
			var frozen: RefCounted=branch.evaluate(150)
			if frozen==null:check(false,branch.error);return false
			check(frozen.snapshot().player_destruction.elapsed_ms==branch.snapshot().player_destruction.elapsed_ms,"Modal instructions advanced player destruction")
			var acknowledged: RefCounted=branch.navigate("next")
			if acknowledged==null:check(false,branch.error);return false
			branch=acknowledged
		var next: RefCounted=branch.evaluate(150)
		if next==null:check(false,branch.error);return false
		branch=next
		check(not branch.convoy_arrival_required() and branch.snapshot()[sequence_key].phase==initial_capture.phase,"A lethal player contact advanced the story sequence")
		if branch.game_over_waiting():break
	var death: Dictionary=branch.snapshot().player_destruction
	check(branch.death_active() and branch.game_over_waiting(),"Convoy death did not reach game over: %s / %dms / %dms"%[death.phase,death.elapsed_ms,death.fade_elapsed_ms])
	if not scene.present(branch):check(false,scene.error);return false
	check(branch.snapshot().progress.campaign_cursor==before.progress.campaign_cursor,"Player death advanced the campaign")
	if sequence_key=="convoy_capture":check(branch.snapshot().convoy_capture.arrival.is_empty(),"Player death published an Alioth arrival")
	else:
		var acknowledged: RefCounted=branch.request_game_over_exit()
		check(acknowledged!=null and acknowledged.prepare_game_over()=={"base_content_id":before.base_content_id,"binding_id":before.binding_id,"source_state":1,"campaign_cursor":before.campaign_cursor},"Alioth game over lost its acknowledged exit")
	check(original.snapshot()==before,"Death diagnostic mutated the live capture branch")
	if not scene.present(original):check(false,scene.error);return false
	return failures==0

func capture_view(label: String) -> void:
	if DisplayServer.get_name()=="headless":return
	var directory:=OS.get_environment("GOF2_CONVOY_CAPTURE_DIR")
	if directory.is_empty():directory=OS.get_environment("GOF2_CAPTURE_DIR")
	if directory.is_empty():return
	if not Checkpoint.private_path(directory+"/capture.png"):check(false,"Keep captures outside engine source");return
	DirAccess.make_dir_recursive_absolute(directory)
	await process_frame
	RenderingServer.force_draw(false)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(label+".png"))==OK,"Cannot capture original convoy scene")
