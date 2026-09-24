extends SceneTree
const Session=preload("res://src/simulation/mining_session.gd")
const Definitions=preload("res://src/content/mining_session_definitions.gd")
const Approach=preload("res://src/simulation/mining_approach.gd")
const Targeting=preload("res://src/simulation/mining_targeting.gd")
const Cargo=preload("res://src/simulation/flight_cargo.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Station=preload("res://src/simulation/station_entry.gd")
const Arrival=preload("res://src/simulation/arrival_world_frame.gd")
const Handoff=preload("res://src/simulation/opening_handoff.gd")
const Fixture=preload("res://tests/opening_handoff_fixture.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const TargetFrame=preload("res://src/presentation/flight_target_frame.gd")
const ScanAnimation=preload("res://src/presentation/flight_scan_animation.gd")
const Frame=preload("res://src/simulation/first_flight_frame.gd")
const Aim=preload("res://src/simulation/opening_aim.gd")
const Scene=preload("res://src/presentation/first_flight_scene.gd")
const Visuals=preload("res://src/content/visual_library.gd")
var checks:=0
var failures:=0
var bindings: RefCounted
var cat: RefCounted
var construction: RefCounted
var approach: RefCounted
var world: RefCounted
var cargo: RefCounted
var index:=-1
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected Mac content, bindings, visuals and optional capture directory")
	if args.size() in [3,4]:await verify(args)
	print("Mining session: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)
func verify(args: Array):
	var lib:=Library.new();bindings=Bindings.new();cat=Catalogues.new();var bodies:=Bodies.new();var effects:=Effects.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not lib.select_language("gb") or not bodies.configure(lib,bindings) or not effects.configure(lib,bindings):check(false,lib.error+bindings.error+cat.error+bodies.error+effects.error);return
	if bindings.mining_session.is_empty():check(not Session.new().configure(bindings,cat,Construction.new(),false),"Legacy pack invented a mining session");return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	check(Definitions.validate(bindings.mining_session,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.mining_approach,bindings.mining_drill).is_empty(),"Session declarations were refused")
	for key in Definitions.VALUES:
		var bad: Dictionary=bindings.mining_session.duplicate(true);bad[key]=null
		check(not Definitions.parameters(bad),"Changed session parameter accepted: "+key)
	for key in bindings.mining_session.provenance:
		var bad: Dictionary=bindings.mining_session.duplicate(true);bad.provenance[key].offset+=1
		check(not Definitions.validate(bad,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.mining_approach,bindings.mining_drill).is_empty(),"Detached session provenance accepted: "+key)
	if bindings.mining_session.has("failure_instruction"):
		var mixed: Dictionary=bindings.mining_session.duplicate(true)
		mixed.failure_instruction=(Definitions.CURRENT_VALUES if mixed.failure_instruction.repeat_each_drill else Definitions.MAC_VALUES).failure_instruction.duplicate(true)
		check(not Definitions.validate(mixed,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.mining_approach,bindings.mining_drill).is_empty(),"A failure policy from another source matched unchanged provenance")
		for change in [{"text_id":607},{"repeat_each_drill":1},{"acknowledgement_advances_story":true}]:
			var bad: Dictionary=bindings.mining_session.duplicate(true);bad.failure_instruction.merge(change,true)
			check(not Definitions.parameters(bad),"Changed failure instruction parameters were accepted")
	var player:=Player.new();var handoff:=Handoff.new();check(player.configure(bindings,cat),player.error)
	var packet:=handoff.prepare(bindings,cat,Fixture.completed(bindings,player,3))
	var arrival:=Arrival.new()
	if not arrival.configure(bindings,cat,lib,packet,[1,1,1],1789100000):check(false,arrival.error);return
	for i in 500:
		arrival=arrival.evaluate(100)
		if arrival==null:check(false,"Could not prepare rescue fixture");return
		if not arrival.snapshot().boundary.is_empty():break
	var station:=Station.new();check(station.configure(bindings,cat,lib,arrival.prepare_station()),station.error)
	for i in 19:station.acknowledge()
	var departure:=station.prepare_departure(bindings,cat);construction=Construction.new()
	if not construction.prepare(bindings,cat,departure,4096,1789100000,true,bodies,effects):check(false,construction.error);return
	world=construction.scenery_owner();cargo=Cargo.new();check(cargo.configure_departure(bindings,cat,construction),cargo.error)
	for row in world.snapshot().bodies.objects:
		if row.source_size_value==7:index=row.index;break
	if index<0:check(false,"Source fixture has no core-sized asteroid");return
	var asteroid: Dictionary=world.snapshot().bodies.objects[index]
	var stand_off:=int(Approach.f32(asteroid.scale*2500.0))
	var pose:=Transform3D(Basis(Vector3.UP,PI),asteroid.position+Vector3(0,0,float(stand_off)-0.5))
	var camera:=Transform3D(Basis.IDENTITY,pose.origin)
	var frame:=TargetFrame.source_geometry(lib,bindings);var art:=ScanAnimation.source_geometry(lib,bindings,bindings.mining_targeting)
	var targeting:=Targeting.new();check(targeting.configure(bindings,cat,construction,TargetFrame.logical_radii(frame.quarter_size,false),art.frames),targeting.error)
	var aim:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"point":Vector3(400,300,-1000),"viewport_size":Vector2i(800,600)}
	for i in 39:
		if not targeting.advance(world,pose,camera,aim,100,true):check(false,targeting.error);return
	if targeting.snapshot().selected_object_index!=index:check(false,"Actual core asteroid was not acquired");return
	approach=Approach.new();check(approach.configure(bindings,cat,construction) and approach.start(world,targeting,pose),approach.error)
	var session:=fresh()
	check(not session.begin(approach,world,cargo),"Session bypassed approach/settling")
	for i in 100:
		if not approach.advance(world,100):check(false,approach.error);return
		if approach.snapshot().phase=="drill_required":break
	check(not session.begin(approach,world,cargo),"Session ignored the world's missing spin stop")
	check(world.set_spin_enabled(index,false),world.error)
	var field: Dictionary=world.snapshot();var hold: Dictionary=cargo.snapshot();var docked: Dictionary=approach.snapshot()
	check(session.begin(approach,world,cargo,Vector2(0.5,-0.5)),session.error)
	var created: Dictionary=session.snapshot()
	check(created.drill.elapsed_ms==0 and created.drill.random_state.is_empty() and created.drill.point==Vector2.ZERO and created.drill.input==Vector2(0.75,-0.75),"Creation advanced the drill or lost its latched input")
	check(not session.begin(approach,world,cargo),"Active session created a second drill")
	var random: Dictionary=field.random_state
	var paused: Dictionary=session.evaluate(world,cargo,100,random,Vector2.ZERO,true)
	check(not paused.is_empty() and paused.session.snapshot()==created and paused.random_state==random and paused.scenery.snapshot()==field and paused.cargo.snapshot()==hold,"Pause changed a mining owner or input")
	var first: Dictionary=session.evaluate(world,cargo,100,random,Vector2.ZERO)
	check(not first.is_empty() and first.session.snapshot().drill.point.distance_to(Vector2(3.75,-3.75))<0.000001 and first.session.snapshot().drill.input==Vector2.ZERO and first.random_state==random,"Mining lost input latency or consumed premature RNG")
	verify_gated_input(session,created,field,hold,random)
	check(session.snapshot()==created and world.snapshot()==field and cargo.snapshot()==hold and approach.snapshot()==docked,"Prospective drilling changed an accepted owner")
	for bad in [-1,751 if not bindings.fast_forward.is_empty() else 151,0.5,"1"]:check(session.evaluate(world,cargo,bad,random).is_empty() and session.snapshot()==created,"Invalid mining delta changed a session")
	check(session.evaluate(world,cargo,100,{}).is_empty() and session.evaluate(world,cargo,100,random,Vector2(2,0)).is_empty(),"Invalid mining RNG or command was accepted")
	check(not session.configure(bindings,cat,Construction.new(),false) and session.snapshot()==created,"Failed configuration replaced the active drill")
	var replacement:=Construction.new();check(replacement.prepare(bindings,cat,departure,4096,1789100000,true,bodies,effects),replacement.error)
	check(session.evaluate(replacement.scenery_owner(),cargo,100,random).is_empty(),"Session crossed a replacement field")
	var casualty: RefCounted=world.fork_for_frame();casualty._bodies=casualty._bodies.fork_for_frame()
	casualty._bodies.normal_hit(index,asteroid.initial_hull)
	var cancelled: Dictionary=session.evaluate(casualty,cargo,100,random,Vector2.ONE)
	check(not cancelled.is_empty() and cancelled.outcome=="target_unavailable" and cancelled.release_approach and not cancelled.resume_motion and cancelled.session.snapshot().drill.is_empty() and cancelled.cargo.snapshot()==hold and cancelled.scenery.snapshot().mined_count==0 and cancelled.random_state==random,"Destroyed target granted cargo, advanced drilling or resumed same-frame movement")
	var empty:=fresh();check(empty.begin(approach,world,cargo),empty.error)
	var stopped: Dictionary=empty.stop(world,cargo,random)
	check(not stopped.is_empty() and stopped.release_approach and not stopped.resume_motion and stopped.cargo.snapshot()==hold and stopped.scenery.snapshot().mined_count==1 and stopped.random_state==random,"Zero-ore manual stop failed its atomic retirement")
	check(stopped.session.stop(stopped.scenery,stopped.cargo,random).is_empty() and stopped.session.evaluate(stopped.scenery,stopped.cargo,100,random).is_empty(),"Finished session replayed extraction")
	var full: RefCounted=cargo.fork_for_frame();full.add_entries([{"item_id":asteroid.item_id,"quantity":hold.capacity}])
	check(not fresh().begin(approach,world,full),"A full hold began a new drill")
	var partial:=run_drilling(75,false,false)
	if partial.is_empty():return
	var before_stop: Dictionary=partial.session.snapshot()
	var result: Dictionary=partial.session.stop(partial.scenery,partial.cargo,partial.random_state)
	check(not result.is_empty() and result.cargo.snapshot().used==4 and result.session.snapshot().extraction.ore_tons==4 and result.scenery.snapshot().remaining_count==field.remaining_count-1,"Earned manual-stop ore did not enter the actual hold")
	check(partial.session.snapshot()==before_stop and partial.cargo.snapshot()==hold and partial.scenery.snapshot().mined_count==0,"Stopping mutated accepted drill, cargo or scenery")
	var hard:=run_drilling(75,false,true)
	if hard.is_empty():return
	var reduced: Dictionary=hard.session.stop(hard.scenery,hard.cargo,hard.random_state)
	check(not reduced.is_empty() and reduced.cargo.snapshot().used==2,"Hard partial drilling lost its source quantity rule")
	var failed:=run_drilling(200,true,false)
	if failed.is_empty():return
	check(failed.outcome=="failed" and failed.resume_motion and failed.release_approach and failed.cargo.snapshot()==hold and failed.scenery.snapshot().mined_count==1,"Failed drilling did not consume only its asteroid or resume motion")
	var events: Array=failed.session.snapshot().events
	check(events==[{"kind":"stop_audio_event","source_id":1},{"kind":"stop_audio_event","source_id":3},{"kind":"notification","source_id":8,"text_id":528}],"Mining failure event sequence differs from the source")
	if bindings.mining_session.has("failure_instruction"):
		var candidate: RefCounted=failed.session.fork_for_frame()
		var policy: Dictionary=bindings.mining_session.failure_instruction
		check(candidate.failure_instruction_due(2) and candidate.failure_instruction_due(3)==(int(policy.campaign_cursor)<0),"Failure instruction ignored its source campaign gate")
		check(candidate.mark_failure_instruction_shown(2) and not candidate.failure_instruction_due(2) and not failed.session.failure_instruction_shown(),"Instruction history leaked across a candidate or repeated without another attempt")
	var completed:=run_drilling(500,false,false)
	if completed.is_empty():return
	var earned: Dictionary=completed.cargo.snapshot();var core_id:=int(asteroid.item_id)+11
	check(completed.outcome=="extracted" and completed.resume_motion and earned.used==25 and earned.entries==[{"item_id":core_id,"quantity":1},{"item_id":asteroid.item_id,"quantity":24}],"Completed session lost core-first capacity or movement handoff")
	check(completed.scenery.snapshot().mined_count==1 and completed.session.snapshot().last_drill.all_layers and completed.session.drill_owner()==null,"Completed drill remained active or did not retire its asteroid")
	check(completed.session.evaluate(completed.scenery,cargo,100,completed.random_state).is_empty(),"Mismatched cargo/mining history was accepted")
	check(construction.snapshot().departure==departure and world.snapshot()==field and cargo.snapshot()==hold and station.prepare_departure(bindings,cat)==departure,"Mining sessions changed mission progress or their source construction")
	print("Mining session source asteroid ",index,"; partial ore 4t; hard 2t; complete hold 25t")
	await verify_flight(lib,args)

func verify_gated_input(session: RefCounted, created: Dictionary, field: Dictionary, hold: Dictionary, random: Dictionary):
	# The outer flight can omit its later input pass after lethal contact.
	# This fixture exercises that scheduling decision without killing an actor
	# or claiming that the application's death flow is already connected.
	var result: Dictionary=session.evaluate(world,cargo,100,random,Vector2(-1,1),false,false)
	check(not result.is_empty(),session.error)
	if result.is_empty():return
	var state: Dictionary=result.session.snapshot().drill
	check(state.point.distance_to(Vector2(3.75,-3.75))<0.000001 and state.command==created.drill.command and state.input==created.drill.input,"Gated input replaced the previous drill command")
	check(state.elapsed_ms==100 and result.random_state==random and not result.release_approach and result.cargo.snapshot()==hold,"Gated input paused drilling, consumed early RNG or cancelled mining")
	result=result.session.evaluate(result.scenery,result.cargo,100,result.random_state,Vector2.ZERO,false,false)
	check(not result.is_empty() and result.session.snapshot().drill.point.distance_to(Vector2(7.5,-7.5))<0.000001 and result.session.snapshot().drill.input==created.drill.input,"A skipped input pass was treated as a release")
	if result.is_empty():return
	var retained: Dictionary=result.session.snapshot()
	var paused: Dictionary=result.session.evaluate(result.scenery,result.cargo,150,result.random_state,Vector2.ONE,true,false)
	check(not paused.is_empty() and paused.session.snapshot()==retained and paused.random_state==result.random_state,"Pause advanced a drill with gated input")
	var resumed: Dictionary=result.session.evaluate(result.scenery,result.cargo,100,result.random_state,Vector2.ZERO)
	# Three binary32 integrations accumulate a one-ULP offset from 11.25.
	check(not resumed.is_empty() and resumed.session.snapshot().drill.point==Vector2(11.250000953674316,-11.250000953674316) and resumed.session.snapshot().drill.input==Vector2.ZERO,"Resumed input lost the retained command's last movement or failed to latch release")
	check(session.snapshot()==created and world.snapshot()==field and cargo.snapshot()==hold,"Gated input changed accepted mining owners")
	for i in 100:
		var next: Dictionary=result.session.evaluate(result.scenery,result.cargo,100,result.random_state,Vector2.ZERO,false,false)
		if next.is_empty():check(false,result.session.error);return
		result=next
		if result.outcome!="drilling":break
	check(result.outcome=="failed" and result.release_approach and result.resume_motion and result.cargo.snapshot()==hold and result.scenery.snapshot().mined_count==1,"Retained steering did not reach the source failure and extraction transaction")

func verify_flight(lib: RefCounted,args: Array):
	var flight:=Frame.new()
	if not flight.configure(bindings,cat,lib,construction,"E",0.5,Vector2i(960,720)):check(false,flight.error);return
	check(flight.stop_mining()==null,"Unreleased flight invented a stopped drill")
	for i in 130:
		flight=flight.evaluate(100)
		if flight==null:check(false,"Could not prepare first-flight briefing");return
	for i in 5:flight=flight.navigate("next")
	var asteroid: Dictionary=construction.snapshot().scenery.bodies.objects[index]
	var prepared:=begin_flight_drill(flight,asteroid)
	if prepared.is_empty():return
	flight=prepared.flight
	var departure: Dictionary=prepared.departure
	var created: Dictionary=flight.snapshot();var captures:={"drill-created":flight}
	check(not created.mining_session.drill.is_empty() and created.mining_session.drill.elapsed_ms==0 and created.mining_session.drill.random_state.is_empty() and created.random_state==departure.random_state,"Live creation consumed drilling time or random draws")
	check(flight.cancel_mining()==null and flight.stop_mining(true)==null,"Active drill accepted an approach cancel or paused stop")
	check(flight.evaluate(150,Vector2.ONE,0.0,true,Vector2i.ZERO,Vector2.ONE).snapshot()==created,"Pause changed a live drill, cargo or field")
	check(flight.evaluate(100,Vector2.ZERO,1.0,false,Vector2i.ZERO,Vector2(INF,0))==null and flight.snapshot()==created,"Bad drill input partially committed a frame")
	var running: RefCounted=flight
	for i in 75:
		var next: RefCounted=running.evaluate(100,Vector2.ZERO,0.0,false,Vector2i.ZERO,control(running.snapshot().mining_session.drill))
		if next==null:check(false,running.error);return
		running=next
		if i==24:verify_shared_random(running)
	var partial: Dictionary=running.snapshot();captures["drill-partial"]=running
	check(partial.player_pose==created.player_pose and partial.camera_view==created.camera_view and partial.cargo.used==0 and partial.mining_session.drill.ore_tons==4,"Live drilling moved the ship/camera or granted cargo before stopping")
	check(partial.random_state==partial.scenery.random_state and partial.random_state!=created.random_state,"Drilling did not continue the owned world random stream")
	var late: RefCounted=running.fork_for_frame();late._targeting._field_identity=RefCounted.new()
	var held: Dictionary=late.snapshot()
	check(late.evaluate(100)==null,"Late frame error was accepted")
	check(late.snapshot()==held and running.snapshot()==partial,"Rejected frame changed drill/RNG/cargo/field owners")
	var stopped: RefCounted=running.stop_mining()
	if stopped==null:check(false,running.error);return
	var result: Dictionary=stopped.snapshot();captures["drill-stopped"]=stopped
	check(result.cargo.used==4 and result.scenery.mined_count==1 and result.scenery.bodies.objects[index].mined and stopped.drill_owner()==null,"Live manual stop did not commit cargo and asteroid retirement together")
	check(result.player_pose==partial.player_pose and result.camera_view==partial.camera_view and result.random_state==partial.random_state and result.world_elapsed_ms==partial.world_elapsed_ms,"Manual stop advanced flight time, motion, camera or RNG")
	check(stopped.stop_mining()==null and running.snapshot()==partial,"Manual stop replayed or mutated its parent")
	var resumed: RefCounted=stopped.evaluate(100)
	check(resumed!=null and resumed.snapshot().camera_view!=result.camera_view and resumed.snapshot().player_pose.origin.distance_to(result.player_pose.origin+result.player_pose.basis.z*200)<0.1,"Manual stop did not resume ordinary flight on the following frame")
	var failed:=finish_flight(flight,true)
	if failed==null:return
	var failure: Dictionary=failed.snapshot();captures["drill-failed"]=failed
	check(failure.mining_session.extraction.phase=="failed" and failure.cargo.used==0 and failure.scenery.mined_count==1 and failure.mining_session.events.back().text_id==528,"Live failure lost its no-ore transaction or source notice")
	if bindings.mining_session.has("failure_instruction"):
		var retry:=verify_failure_retry(failed)
		if retry!=null:captures["drill-failed-again"]=retry
	var complete:=finish_flight(flight,false)
	if complete==null:return
	var success: Dictionary=complete.snapshot();captures["drill-complete"]=complete
	check(success.mining_session.extraction.all_layers and success.cargo.used==25 and success.scenery.mined_count==1 and complete.drill_owner()==null,"Live full extraction did not fill the owned cargo hold once")
	for state in [result,failure,success]:
		var progress: Dictionary=state.progress.duplicate(true);progress.erase("mining_failure_hint_seen")
		check(progress==departure.progress,"Mining changed earned counters while recording instruction history")
		for key in ["mission","campaign_cursor","mining_completed","reward_credits"]:check(state[key]==departure[key],"Mining granted unearned campaign progress: "+key)
	if complete._objective!=null:
		var objective: RefCounted=complete
		for i in 60:
			if objective.dialogue_visible():break
			objective=objective.evaluate(100)
			if objective==null:check(false,"Mined cargo objective poll failed");return
		check(objective.snapshot().cargo_objective_satisfied and objective.snapshot().dialogue.text_id==int(bindings.mining_objective.events[0].text_id) and objective.snapshot().campaign_cursor==2,"Actual full extraction did not offer the return instructions")
		for i in 3:objective=objective.navigate("next")
		check(objective.snapshot().campaign_cursor==3 and objective.snapshot().cargo.used==25 and objective.snapshot().station_return_required and not objective.snapshot().mining_completed,"Actual mined cargo lost the acknowledged return boundary")
		# Six prior tons and a clock one millisecond before its due poll are
		# explicit fixtures. Four new tons still come from the actual drill stop.
		var manual: RefCounted=running.fork_for_frame();manual._cargo.add_entries([{"item_id":0,"quantity":6}])
		manual._briefing._state.hud_elapsed_ms=5000
		manual=manual.stop_mining()
		check(manual!=null and manual.snapshot().cargo.used==10 and not manual.snapshot().cargo_objective_satisfied and not manual.dialogue_visible(),"Manual stop polled cargo before the next frame")
		manual=manual.evaluate(1)
		check(manual!=null and manual.snapshot().cargo_objective_satisfied and manual.dialogue_visible(),"Next due poll ignored the manual extraction")
	var directory: String=args[3] if args.size()==4 else OS.get_environment("GOF2_CAPTURE_DIR")
	if DisplayServer.get_name()!="headless" and not directory.is_empty():
		DirAccess.make_dir_recursive_absolute(directory)
		await render(lib,args[2],directory,captures)

func begin_flight_drill(parent: RefCounted,asteroid: Dictionary) -> Dictionary:
	var flight: RefCounted=parent.fork_for_frame()
	var distance:=float(int(Approach.f32(asteroid.scale*2500))+10000)
	# Initial pilot placement is a test fixture. Live acquisition, approach,
	# creation, drilling and world transactions run through the real frame.
	flight._pose=Transform3D(Basis(Vector3.UP,PI),asteroid.position+Vector3(0,0,distance))
	var data: Dictionary=bindings.camera_follow
	var eye: Vector3=flight._pose*Vector3(data.eye_offset[0],data.eye_offset[1],data.eye_offset[2])
	var look: Vector3=flight._pose*Vector3(data.look_offset[0],data.look_offset[1],data.look_offset[2])
	flight._camera._state.eye=eye;flight._camera._state.look=look;flight._camera._state.pose=Transform3D.IDENTITY.looking_at(look-eye,Vector3.UP);flight._camera._state.pose.origin=eye
	flight._aim=Aim.new();flight._aim.configure(bindings)
	for i in 55:
		var next: RefCounted=flight.evaluate(100,Vector2.ZERO,0.0)
		if next==null:check(false,flight.error);return {}
		flight=next
	if flight.snapshot().mining_targeting.selected_object_index!=asteroid.index:check(false,"Live scanner did not acquire the actual session asteroid");return {}
	flight=flight.evaluate(0,Vector2.ZERO,1.0)
	var departure: Dictionary=flight.snapshot()
	flight=flight.start_mining()
	if flight==null:check(false,"Live mining action was refused");return {}
	for i in 200:
		var next: RefCounted=flight.evaluate(100,Vector2.ZERO,0.0)
		if next==null:check(false,flight.error);return {}
		flight=next
		if not flight.snapshot().mining_session.drill.is_empty():break
	if flight.drill_owner()==null:check(false,"Native approach did not create its drill");return {}
	return {"flight":flight,"departure":departure}

func verify_failure_retry(failed: RefCounted) -> RefCounted:
	var original: Dictionary=failed.snapshot()
	var closed:=verify_failure_instruction(failed)
	if closed==null:return null
	var asteroid:={}
	for body in closed.snapshot().scenery.bodies.objects:
		if body.source_size_value==7 and not body.get("mined",false):asteroid=body;break
	if asteroid.is_empty():check(false,"No remaining source asteroid for a second attempt");return null
	var prepared:=begin_flight_drill(closed,asteroid)
	if prepared.is_empty():return null
	var second: RefCounted=prepared.flight
	var repeat: bool=bindings.mining_session.failure_instruction.repeat_each_drill
	check(second.snapshot().progress.mining_failure_hint_seen==not repeat and second._mining.failure_instruction_shown()==not repeat,"The next actual drill applied another source's failure reset")
	second=finish_flight(second,true)
	if second==null:return null
	var state: Dictionary=second.snapshot()
	check(state.cargo.used==0 and state.scenery.mined_count==2 and state.mining_session.extraction.phase=="failed","Retry lost the two earned failure transactions")
	check(second.dialogue_visible()==repeat and state.progress.mining_failure_hint_seen,"A second failure did not follow this source's modal repeat policy")
	check(state.campaign_cursor==original.campaign_cursor and state.mission==original.mission and state.progress==original.progress,"Failure retry changed the mission or career counters")
	check(failed.snapshot()==original,"The next attempt changed the accepted failure branch")
	if repeat:verify_failure_instruction(second)
	return second

func verify_failure_instruction(flight: RefCounted) -> RefCounted:
	var shown: Dictionary=flight.snapshot()
	check(shown.phase=="mining_instruction" and shown.dialogue.text_id==606 and shown.dialogue.speaker_name=="Info" and shown.dialogue.voice_event_id==-1 and shown.progress.mining_failure_hint_seen,"Failed drill omitted its source modal instruction or invented speech")
	check(flight.navigate("previous")==null and flight.navigate("next",true)==null and flight.start_mining()==null,"Failure instruction accepted flight input, backward navigation or a paused acknowledgement")
	var held: RefCounted=flight.evaluate(150,Vector2.ONE,1.0,false,Vector2i.ZERO,Vector2.ONE,true,true)
	check(held!=null,flight.error)
	if held==null:return null
	var paused: Dictionary=held.snapshot()
	for key in ["world_elapsed_ms","player_pose","camera_view","cargo","progress","mission","random_state","dialogue"]:
		check(paused[key]==shown[key],"Failure modal advanced "+key)
	if shown.has("flight_notices"):check(paused.flight_notices==shown.flight_notices,"The timed mining notice elapsed behind the modal")
	var closed: RefCounted=held.navigate("next")
	check(closed!=null and not closed.dialogue_visible() and closed.snapshot().progress==shown.progress and closed.snapshot().campaign_cursor==shown.campaign_cursor and closed.snapshot().world_elapsed_ms==shown.world_elapsed_ms,"Acknowledging a failure advanced the campaign or clock")
	check(closed.navigate("next")==null and flight.snapshot()==shown,"Instruction acknowledgement replayed or mutated its parent")
	var resumed: RefCounted=closed.evaluate(100)
	check(resumed!=null and resumed.snapshot().world_elapsed_ms==shown.world_elapsed_ms+100 and not resumed.dialogue_visible(),"Failure instruction did not resume ordinary flight exactly once")
	return resumed

func verify_shared_random(flight: RefCounted):
	var branch: RefCounted=flight.fork_for_frame();var other:=0 if index!=0 else 1
	branch._scenery._bodies=branch._scenery._bodies.fork_for_frame()
	var amount: int=branch.snapshot().scenery.bodies.objects[other].initial_hull
	branch._scenery._bodies.normal_hit(other,amount)
	var prior: Dictionary=branch.snapshot()
	var drill: RefCounted=branch.drill_owner()
	check(drill.advance(100,prior.random_state),drill.error)
	var expected: RefCounted=branch._scenery.fork_for_frame()
	check(expected.update(100,prior.detail_reference,1.0,null,drill.snapshot().random_state),expected.error)
	var next: RefCounted=branch.evaluate(100)
	check(next!=null and next.snapshot().random_state==expected.snapshot().random_state and next.snapshot().scenery.destruction[other]==expected.snapshot().destruction[other] and next.snapshot().mining_session.drill.point==drill.snapshot().point,"World destruction consumed RNG before drilling or used a restarted stream")
	check(branch.snapshot()==prior and flight.snapshot().scenery.bodies.objects[other].vitals.hull>0,"RNG ordering fixture changed its accepted frame")

func finish_flight(created: RefCounted, fail_input: bool) -> RefCounted:
	var flight: RefCounted=created
	for i in 500:
		var before: Dictionary=flight.snapshot()
		var command:=Vector2.ONE if fail_input else control(before.mining_session.drill)
		var next: RefCounted=flight.evaluate(100,Vector2.ZERO,0.0,false,Vector2i.ZERO,command)
		if next==null:check(false,flight.error);return null
		flight=next
		if flight.drill_owner()==null:
			var state: Dictionary=flight.snapshot()
			var hint: bool=state.phase=="mining_instruction"
			check(state.player_pose.origin.distance_to(before.player_pose.origin+before.player_pose.basis.z*200)<0.1 and (state.camera_view==before.camera_view if hint else state.camera_view!=before.camera_view) and state.player_model_basis==Basis.IDENTITY,"Automatic completion lost player motion or the later modal camera gate")
			return flight
	check(false,"Live mining did not reach its terminal transaction");return null

func control(state: Dictionary) -> Vector2:
	var desired: Vector2=-(state.point+(state.input+state.drift)*5.0)*0.2-state.drift
	var command:=Vector2.ZERO
	for axis in 2:command[axis]=signf(desired[axis])*sqrt(minf(1.0,absf(desired[axis])/3.0))
	return command

func render(lib: RefCounted,pixels: String,directory: String,captures: Dictionary):
	var visuals:=Visuals.new()
	if not visuals.open(pixels,lib.manifest):check(false,visuals.error);return
	var canvas:=SubViewport.new();canvas.size=Vector2i(960,720);canvas.own_world_3d=true;canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var scene:=Scene.new();canvas.add_child(scene)
	if not scene.build(lib,bindings,visuals,cat,captures["drill-created"]):check(false,scene.error);canvas.free();return
	for label in captures:
		var flight: RefCounted=captures[label];var state: Dictionary=flight.snapshot()
		check(scene.present(flight),scene.error)
		check(scene.mining_panel.visible==(flight.drill_owner()!=null),"Mining panel visibility differs from the live owner: "+label)
		for i in 3:await process_frame
		check(canvas.get_texture().get_image().save_png(directory.path_join(label+".png"))==OK and flight.snapshot()==state,"Capture failed or advanced live mining: "+label)
	check(scene.present(captures["drill-partial"]),scene.error)
	var previous: Transform3D=scene.geometry.player.transform;var shown: Dictionary=scene.mining_panel._state.duplicate(true)
	var bad: RefCounted=captures["drill-stopped"].fork_for_frame();bad._targeting._sample.animation_frame=9999
	check(not scene.present(bad) and scene.geometry.player.transform==previous and scene.mining_panel._state==shown,"Rejected presentation replaced the visible drill or world")
	canvas.size=Vector2i(800,450);scene.set_mobile_layout(true);check(scene.present(captures["drill-partial"]),scene.error)
	for i in 3:await process_frame
	check(canvas.get_texture().get_image().save_png(directory.path_join("drill-partial-phone.png"))==OK,"Could not save phone drilling view")
	if bindings.mining_session.has("failure_instruction"):
		check(scene.present(captures["drill-failed"]),scene.error)
		for i in 3:await process_frame
		check(canvas.get_texture().get_image().save_png(directory.path_join("drill-failed-phone.png"))==OK,"Could not save landscape phone failure instruction")
	canvas.free()

func fresh(hard:=false) -> RefCounted:
	var session:=Session.new();check(session.configure(bindings,cat,construction,hard),session.error);return session
func run_drilling(frames: int, fail_input: bool, hard: bool) -> Dictionary:
	var session:=fresh(hard)
	if not session.begin(approach,world,cargo):check(false,session.error);return {}
	var result:={"session":session,"scenery":world.fork_for_frame(),"cargo":cargo.fork_for_frame(),"random_state":world.snapshot().random_state,"outcome":"drilling"}
	for i in frames:
		var state: Dictionary=result.session.snapshot().drill
		var desired: Vector2=-(state.point+(state.input+state.drift)*5.0)*0.2-state.drift
		var command:=Vector2.ONE if fail_input else Vector2.ZERO
		if not fail_input:
			for axis in 2:command[axis]=signf(desired[axis])*sqrt(minf(1.0,absf(desired[axis])/3.0))
		var next: Dictionary=result.session.evaluate(result.scenery,result.cargo,100,result.random_state,command)
		if next.is_empty():check(false,result.session.error);return {}
		# The flight's world update follows drilling and receives its continued
		# random stream. Session evaluation alone does not impersonate that tick.
		if not next.scenery.update(100,Vector3.ZERO,1.0,null,next.random_state):check(false,next.scenery.error);return {}
		next.random_state=next.scenery.snapshot().random_state;result=next
		if next.release_approach:break
	return result
func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)
