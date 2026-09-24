extends SceneTree
## Mac docking integration. Initial asteroid placement and boundary/vital cases
## are explicit fixtures; acquisition, drilling, earned cargo and the trip back
## use the native flight owners. No original executable runs in this test.
const Frame=preload("res://src/simulation/first_flight_frame.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Station=preload("res://src/simulation/station_entry.gd")
const Arrival=preload("res://src/simulation/arrival_world_frame.gd")
const Handoff=preload("res://src/simulation/opening_handoff.gd")
const Fixture=preload("res://tests/opening_handoff_fixture.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Aim=preload("res://src/simulation/opening_aim.gd")
const Cache=preload("res://src/simulation/flight_player_cache.gd")
const Definitions=preload("res://src/content/station_return_definitions.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Session=preload("res://src/presentation/station_session.gd")
const DialoguePanel=preload("res://src/presentation/station_dialogue_panel.gd")
const Speech=preload("res://src/presentation/station_audio.gd")
var checks:=0
var failures:=0
var lib:=Library.new()
var bindings:=Bindings.new()
var cat:=Catalogues.new()
var construction:=Construction.new()
var ready: RefCounted
var returning: RefCounted
var docked: RefCounted

func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	if args.size()==3 and DisplayServer.get_name()!="headless" and not OS.get_environment("GOF2_CAPTURE_DIR").is_empty():args.append(OS.get_environment("GOF2_CAPTURE_DIR"))
	check(args.size() in [3,4],"Expected Mac content, bindings, visuals and optional capture directory")
	if args.size() in [3,4]:await verify(args)
	print("Station return: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var bodies:=Bodies.new();var effects:=Effects.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not lib.select_language("gb") or not bodies.configure(lib,bindings) or not effects.configure(lib,bindings):check(false,lib.error+bindings.error+cat.error+bodies.error+effects.error);return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	check(header.architecture=="x86_64","This verification is Mac only")
	if not bindings.station_return.is_empty():
		check(Definitions.validate(bindings.station_return,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.first_flight).is_empty(),"Station return declarations were refused")
		var other: Dictionary=(Definitions.VALUES if int(bindings.station_return.events[0].text_id)==int(Definitions.MAC_VALUES.events[0].text_id) else Definitions.MAC_VALUES).duplicate(true)
		other.provenance=bindings.station_return.provenance.duplicate(true)
		check(not Definitions.validate(other,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.first_flight).is_empty(),"Station return accepted another source's conversation with these proofs")
		for key in Definitions.VALUES:
			var bad: Dictionary=bindings.station_return.duplicate(true);bad[key]=null
			check(not Definitions.parameters(bad),"Changed station return parameter accepted: "+key)
		for key in Definitions.SPANS:
			var bad: Dictionary=bindings.station_return.duplicate(true);bad.provenance[key].offset+=1
			check(not Definitions.validate(bad,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.first_flight).is_empty(),"Detached station return provenance accepted: "+key)
	var player:=Player.new();var handoff:=Handoff.new();check(player.configure(bindings,cat),player.error)
	var arrival:=Arrival.new()
	if not arrival.configure(bindings,cat,lib,handoff.prepare(bindings,cat,Fixture.completed(bindings,player,3)),[1,1,1],1789100000):check(false,arrival.error);return
	for i in 500:
		arrival=arrival.evaluate(100)
		if arrival==null:check(false,"Could not prepare rescue fixture");return
		if not arrival.snapshot().boundary.is_empty():break
	var station:=Station.new();check(station.configure(bindings,cat,lib,arrival.prepare_station()),station.error)
	for i in 19:station.acknowledge()
	if not construction.prepare(bindings,cat,station.prepare_departure(bindings,cat),4096,1789100000,true,bodies,effects):check(false,construction.error);return
	ready=Frame.new()
	if not ready.configure(bindings,cat,lib,construction,"E",.5,Vector2i(960,720)):check(false,ready.error);return
	check(ready.prepare_station().is_empty() and not Station.new().configure_return(bindings,cat,lib,ready),"Unreleased flight entered the station")
	if bindings.station_return.is_empty():check(not ready.snapshot().has("station_arrival"),"Legacy flight invented docking");return
	for i in 130:ready=ready.evaluate(100)
	if ready==null:check(false,"Could not prepare first-flight briefing");return
	for i in 5:ready=ready.navigate("next")
	returning=mine_and_acknowledge()
	if returning==null:return
	verify_gates()
	verify_cache()
	if failures:return
	var flight: RefCounted=returning.start_station_autopilot()
	if flight==null:check(false,returning.error);return
	# Current damage/energy are deliberate fixtures. Arrival must copy them,
	# rather than restoring the fresh ship's construction cache.
	flight._player._state.vitals.hull=71;flight._player._state.gamma=37.875
	for i in 4000:
		var next: RefCounted=flight.evaluate(100)
		if next==null:check(false,flight.error);return
		flight=next
		if not flight.prepare_station().is_empty():break
	if flight.prepare_station().is_empty():check(false,"Native guidance did not reach Var Hastra");return
	docked=flight
	verify_arrival()
	if failures==0:await verify_presentation(args)

func mine_and_acknowledge() -> RefCounted:
	var flight: RefCounted=ready.fork_for_frame();var asteroid:={}
	for row in construction.snapshot().scenery.bodies.objects:
		if row.source_size_value==7:asteroid=row;break
	if asteroid.is_empty():check(false,"Source fixture has no core-sized asteroid");return null
	var distance:=float(int(asteroid.scale*2500)+10000)
	flight._pose=Transform3D(Basis(Vector3.UP,PI),asteroid.position+Vector3(0,0,distance))
	var data: Dictionary=bindings.camera_follow
	var eye: Vector3=flight._pose*Vector3(data.eye_offset[0],data.eye_offset[1],data.eye_offset[2])
	var look: Vector3=flight._pose*Vector3(data.look_offset[0],data.look_offset[1],data.look_offset[2])
	flight._camera._state.eye=eye;flight._camera._state.look=look;flight._camera._state.pose=Transform3D.IDENTITY.looking_at(look-eye,Vector3.UP);flight._camera._state.pose.origin=eye
	flight._aim=Aim.new();flight._aim.configure(bindings)
	for i in 55:flight=flight.evaluate(100,Vector2.ZERO,0.0)
	if flight==null:check(false,"Scanner preparation failed");return null
	check(flight.snapshot().mining_targeting.selected_object_index==asteroid.index,"Live scanner missed the authored asteroid")
	flight=flight.evaluate(0,Vector2.ZERO,1.0)
	flight=flight.start_mining()
	if flight==null:check(false,"Live mining was refused");return null
	for i in 200:
		var next: RefCounted=flight.evaluate(100,Vector2.ZERO,0.0)
		if next==null:check(false,flight.error);return null
		flight=next
		if flight.drill_owner()!=null:break
	if flight.drill_owner()==null:check(false,"Approach did not start drilling");return null
	for i in 500:
		var state: Dictionary=flight.snapshot().mining_session.drill
		var desired: Vector2=-(state.point+(state.input+state.drift)*5.0)*.2-state.drift
		var command:=Vector2.ZERO
		for axis in 2:command[axis]=signf(desired[axis])*sqrt(minf(1.0,absf(desired[axis])/3.0))
		var next: RefCounted=flight.evaluate(100,Vector2.ZERO,0.0,false,Vector2i.ZERO,command)
		if next==null:check(false,flight.error);return null
		flight=next
		if flight.drill_owner()==null:break
	check(flight.snapshot().cargo.used==25 and flight.snapshot().scenery.mined_count==1 and flight.snapshot().mining_session.extraction.all_layers,"Native extraction failed to earn its full hold")
	for i in 60:
		if flight.dialogue_visible():break
		flight=flight.evaluate(100)
		if flight==null:check(false,"Mined-cargo mission poll failed");return null
	check(flight.snapshot().dialogue.text_id==int(bindings.mining_objective.events[0].text_id) and flight.prepare_station().is_empty(),"Unacknowledged cargo entered station")
	for i in 3:flight=flight.navigate("next")
	if flight==null:check(false,"Return instructions failed");return null
	check(flight.snapshot().campaign_cursor==3 and flight.snapshot().cargo.used==25 and flight.snapshot().station_return_required,"Acknowledgement lost earned cargo or its return mission")
	print("Actual mined return: asteroid ",asteroid.index,"; 25t; starting distance ",flight.snapshot().player_pose.origin.length())
	return flight

func positioned(source: RefCounted, position: Vector3) -> RefCounted:
	var flight: RefCounted=source.fork_for_frame()
	flight._pose=Transform3D(Basis.looking_at(-position,Vector3.UP,true),position)
	flight._pilot.angular_units=Vector2.ZERO
	flight._autopilot.observe_manual(flight._pose,Vector2.ZERO)
	flight._station_contact=false
	return flight

func verify_gates():
	var radial:=Vector3.ZERO
	for direction in [Vector3(0,.6,.8),Vector3(.8,.6,0),Vector3(1,0,0),Vector3(0,0,1)]:
		if ready._station.point_volume(direction*15999)<0 and ready._station.point_volume(direction*16001)<0:radial=direction;break
	if radial==Vector3.ZERO:check(false,"No external radius fixture was found");return
	var outside: RefCounted=positioned(returning,radial*16001).start_station_autopilot()
	var crossing: RefCounted=outside.evaluate(1)
	if crossing==null:check(false,outside.error);return
	check(crossing.snapshot().player_pose.origin.length()<16000 and crossing.prepare_station().is_empty() and not crossing.snapshot().station_arrival.pre_motion_contact,"Contact used post-motion radius on the crossing frame")
	var arrived: RefCounted=crossing.evaluate(0)
	check(arrived!=null and not arrived.prepare_station().is_empty() and arrived.snapshot().station_volume_index<0,"Next pre-motion contact failed outside authored boxes")
	var edge: RefCounted=positioned(returning,radial*16000).start_station_autopilot()
	check(edge.evaluate(0).prepare_station().is_empty(),"The strict 16000-unit boundary docked")
	var manual:=positioned(returning,radial*15999)
	check(manual.evaluate(0).prepare_station().is_empty(),"Proximity without station selection docked")
	var denied: RefCounted=positioned(ready,radial*15999).start_station_autopilot().evaluate(0)
	check(denied!=null and denied.prepare_station().is_empty() and denied.snapshot().flight_notices.pending.all(func(n):return n.source_id!=21),"Restricted mission used radius alone for its refusal notice")
	denied=positioned(ready,Vector3(100,100,100)).start_station_autopilot().evaluate(0)
	check(denied!=null and denied.prepare_station().is_empty() and denied.snapshot().flight_notices.pending.any(func(n):return n.source_id==21),"Restricted mission omitted its post-volume notice or docked")
	# Hold the preceding collision flag false to isolate the later point query.
	var volume: RefCounted=positioned(returning,Vector3(100,100,100)).start_station_autopilot();volume._collision_enabled=false
	var accepted: RefCounted=volume.evaluate(0)
	check(accepted!=null and not accepted.prepare_station().is_empty() and not accepted.snapshot().station_arrival.pre_motion_contact and accepted.snapshot().station_volume_index==3,"Current station volume required a preceding contact flag")
	var before: Dictionary=outside.snapshot()
	check(outside.evaluate(100,Vector2.ONE,0.0,true).snapshot()==before and outside.evaluate(151)==null and outside.evaluate(1,Vector2(NAN,0))==null and outside.snapshot()==before,"Paused/invalid docking changed accepted flight")
	var bad: RefCounted=positioned(returning,radial*15999).start_station_autopilot();bad._cargo._mined_indices=[]
	var held: Dictionary=bad.snapshot();check(bad.evaluate(1)==null and bad.snapshot()==held,"Invalid mining history partially committed arrival")
	bad=positioned(returning,radial*15999).start_station_autopilot();bad._cargo._field_identity=RefCounted.new();held=bad.snapshot()
	check(bad.evaluate(1)==null and bad.snapshot()==held,"Cargo from another field committed arrival")
	bad=positioned(returning,radial*15999).start_station_autopilot();bad._objective._state.mission.reward=1;held=bad.snapshot()
	check(bad.evaluate(1)==null and bad.snapshot()==held,"Changed delivery reward was accepted")

func verify_cache():
	var seed: Dictionary=construction.snapshot().departure.loadout
	var player: Dictionary=returning.snapshot().player
	# Synthetic fractional pools exercise getter conversion even though the
	# starter has no shield equipment. These are not claimed loadout capacities.
	player.vitals.hull=73;player.vitals.armor=8;player.vitals.shield=17.875;player.gamma=6.75
	var cache:=Cache.station_arrival_cache(bindings.station_return,seed,player)
	check(Cache.matches(cache,seed,3) and cache.values=={"hull":73,"armor":8,"shield":17,"gamma":6},"Arrival did not truncate current shield/gamma or copied stale pools")
	for key in ["base_content_id","binding_id","ship_id","equipment_ids"]:
		var bad:=player.duplicate(true);bad[key]=null
		check(Cache.station_arrival_cache(bindings.station_return,seed,bad).is_empty(),"Arrival accepted mismatched player "+key)
	for value in [NAN,INF,2147483648.0]:
		var bad:=player.duplicate(true);bad.gamma=value
		check(Cache.station_arrival_cache(bindings.station_return,seed,bad).is_empty(),"Arrival accepted unrepresentable current energy")

func verify_arrival():
	var accepted: Dictionary=docked.snapshot();var packet: Dictionary=docked.prepare_station()
	check(packet.cargo==returning.snapshot().cargo and packet.player_cache.values.hull==71 and packet.player_cache.values.gamma==37,"Docking lost cargo or restored the fresh construction pools")
	check(packet.player_cache!=accepted.player_cache and packet.player_cache.campaign_cursor==3 and packet.player==accepted.player,"Docking cache did not use the current player")
	check(packet.progress==accepted.progress and packet.mission=={"kind":11,"station_id":78,"reward":0,"bonus":0},"Arrival granted an unacknowledged reward or mission")
	packet.cargo.entries.clear();packet.player_cache.values.hull=0
	check(docked.prepare_station().cargo.used==25 and docked.prepare_station().player_cache.values.hull==71,"Prepared station packet exposed mutable accepted state")
	check(docked.evaluate(150,Vector2.ONE).snapshot()==accepted and docked.start_mining()==null and docked.start_station_autopilot()==null and docked.cancel_station_autopilot()==null and docked.navigate("next")==null,"Pending station transition advanced world or accepted gameplay input")
	var station:=Station.new();check(station.configure_return(bindings,cat,lib,docked),station.error)
	var before: Dictionary=station.snapshot()
	check(not station.configure_return(bindings,cat,lib,returning) and station.snapshot()==before,"Unarrived flight replaced a prepared station")
	check(not station.configure_return(bindings,cat,lib,RefCounted.new()) and station.snapshot()==before,"Foreign owner replaced a prepared station")
	check(before.cargo==accepted.cargo and before.player_cache.values.hull==71 and before.progress==accepted.progress and before.campaign_cursor==3,"Station arrival changed cargo, vitals or progress")
	check(not station.previous() and station.snapshot()==before,"First return line navigated backward")
	for i in 5:
		var current: Dictionary=station.snapshot()
		check(current.dialogue.text_id==int(bindings.station_return.events[i].text_id) and current.dialogue.speaker_id==[2,0,2,0,2][i] and current.cargo==accepted.cargo and current.campaign_cursor==3,"Return line removed cargo or changed source dialogue")
		check(station.prepare_departure(bindings,cat).is_empty() and station.snapshot()==current,"Return conversation allowed early departure or changed state")
		check(station.acknowledge(),station.error)
	var finished: Dictionary=station.snapshot()
	check(finished.campaign_cursor==4 and finished.delivery_acknowledged and finished.cargo.used==0 and finished.cargo.entries.is_empty() and finished.cargo.free_space==25,"Final acknowledgement failed to clear the complete hold")
	check(finished.player_cache.values==before.player_cache.values and finished.player_cache.campaign_cursor==4 and finished.arrival_player==before.arrival_player,"Final acknowledgement reset ship vitals")
	check(finished.mission=={"kind":154,"station_id":78,"reward":0,"bonus":0,"source_parameter":25} and finished.reward_credits==0 and not finished.mining_completed,"Return invented rewards or completion of the full mining tutorial")
	check(finished.progress.player_kills==3 and finished.progress.rank_score==before.progress.rank_score+int(bindings.opening_handoff.cursor_weight),"Return lost earned progress or cursor rank contribution")
	check(not station.acknowledge() and station.snapshot()==finished,"Return acknowledgement replayed")
	if bindings.full_hold_departure.is_empty():check(station.prepare_departure(bindings,cat).is_empty(),"Legacy return invented second departure")
	else:verify_second_departure(station)

func verify_second_departure(station: RefCounted):
	var before: Dictionary=station.snapshot();var packet: Dictionary=station.prepare_departure(bindings,cat)
	if packet.is_empty():check(false,station.error);return
	check(packet.size()==16 and packet.campaign_cursor==4 and packet.progress==before.progress and packet.mission==before.mission and packet.loadout==before.loadout,"Second departure lost its completed delivery state")
	check(packet.cargo_used==0 and packet.confirmation_required and packet.confirmation_text_id==386 and packet.source_state==2 and packet.world_type==3 and packet.audio_selector==1,"Second departure changed the source confirmation, cleared hold or scene request")
	check(packet.reset_cache.values=={"hull":-1,"armor":-1,"shield":-1,"gamma":-1} and packet.player_cache.values=={"hull":95,"armor":0,"shield":0,"gamma":100} and packet.player.vitals.hull==95 and packet.player.gamma==100.0,"Second departure reused damaged arrival pools")
	check(packet.player_cache.campaign_cursor==4 and packet.player.campaign_cursor==4 and packet.reset_cache.campaign_cursor==4 and station.snapshot()==before and before.player_cache.values.hull==71,"Second departure mutated station state while preparing a fresh player")
	packet.loadout.equipment_ids.clear();packet.player.vitals.hull=0;packet.progress.player_kills=0
	check(station.snapshot()==before and station.prepare_departure(bindings,cat).progress.player_kills==3 and station.prepare_departure(bindings,cat).loadout==before.loadout,"Second departure exposed mutable state")
	var second_world:=Construction.new()
	if bindings.full_hold_flight.is_empty():
		check(not second_world.prepare(bindings,cat,station.prepare_departure(bindings,cat),4096,1789100000) and second_world.snapshot().is_empty(),"Legacy second departure silently reused the NPC-free first world")
	else:
		check(second_world.prepare(bindings,cat,station.prepare_departure(bindings,cat),4096,1789100000),second_world.error)
		var world: Dictionary=second_world.snapshot()
		if world.is_empty():return
		check(world.campaign_cursor==4 and world.departure.progress==before.progress and world.scenery.world_initialization.npc_construction.actors.size()==1 and station.snapshot()==before,"Second departure lost its actor, earned progress or station transaction")
	for scenario in ["cargo","acknowledgement","mission","cache"]:
		var bad: RefCounted=station.fork()
		match scenario:
			"cargo":bad._state.cargo.used=1
			"acknowledgement":bad._state.delivery_acknowledged=false
			"mission":bad._state.mission.source_parameter=10
			"cache":bad._state.player_cache.campaign_cursor=3
		var unchanged: Dictionary=bad.snapshot()
		check(bad.prepare_departure(bindings,cat).is_empty() and bad.snapshot()==unchanged,"Invalid second departure partially committed: "+scenario)

func verify_presentation(args: PackedStringArray):
	var visuals:=Visuals.new();check(visuals.open(args[2],lib.manifest),visuals.error)
	var canvas:=SubViewport.new();canvas.size=Vector2i(960,720);canvas.own_world_3d=true;canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var panel:=DialoguePanel.new();canvas.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var speech:=Speech.new();root.add_child(speech)
	for language in lib.manifest.languages:
		check(lib.select_language(language),lib.error)
		var station:=Station.new();check(station.configure_return(bindings,cat,lib,docked) and panel.configure_station_return(lib,bindings,visuals),station.error+panel.error)
		if language in ["gb","de"]:check(speech.configure_station_return(lib,bindings),speech.error)
		for i in 5:
			var state: Dictionary=station.snapshot()
			check(panel.present(state) and panel._body.text==lib.strings[int(bindings.station_return.events[i].text_id)],"Wrong return localization: "+language)
			if language in ["gb","de"]:
				check(speech.present(i) and speech._player!=null and speech.snapshot().history.back().source_id==411+i,"Wrong return voice")
				var history: Array=speech.snapshot().history;speech.present(i);check(speech.snapshot().history==history,"Repainting restarted speech")
				speech.set_paused(true);check(speech._player.stream_paused,"Return speech ignored pause");speech.set_paused(false)
			if args.size()==4:
				for mobile in [false,true]:
					canvas.size=Vector2i(800,450) if mobile else Vector2i(960,720);panel.set_mobile_layout(mobile)
					for f in 3:await process_frame
					check(Rect2(Vector2.ZERO,canvas.size).encloses(panel._panel.get_rect()) and (panel._body.get_content_height()<=panel._body.size.y or panel._body.scroll_active),"Return text escapes viewport: "+language)
			station.acknowledge()
		check(panel.present(station.snapshot()) and not panel.visible,"Acknowledged return panel remained visible")
	speech.free();check(lib.select_language("gb"),lib.error)
	check(panel.configure_station_return(lib,bindings,visuals),panel.error);panel.set_mobile_layout(false);canvas.size=Vector2i(960,720)
	var session:=Session.new();canvas.add_child(session)
	if not session.configure_return(lib,bindings,visuals,docked,0,42):check(false,session.error);canvas.free();return
	check(session.activate() and not session.snapshot().conversation_started and session.audio.snapshot().history.is_empty(),"Scene loading auto-started return conversation")
	check(not session.navigate("next",panel),"Return conversation bypassed its entry delay")
	for i in 9:session.step((i+1)*100000)
	check(not session.snapshot().conversation_started,"Return began before the one-second entry delay")
	check(session.step(1000000) and session.snapshot().conversation_started and session.audio.snapshot().history[0].source_id==411,"Return did not start with its source voice")
	check(panel.present(session.snapshot()),panel.error)
	session.set_pause("user",true,1000000);var held: Dictionary=session.snapshot()
	check(session.step(5000000) and session.snapshot()==held and not session.navigate("next",panel),"Paused return advanced camera/dialogue")
	session.set_pause("user",false,5000000);session.step(5100000)
	check(session.snapshot().camera.elapsed_ms==1100,"Return pause accumulated catch-up time")
	var foreign:=DialoguePanel.new();canvas.add_child(foreign);held=session.snapshot()
	check(not session.navigate("next",foreign) and session.snapshot()==held,"Rejected panel committed return dialogue");foreign.free()
	check(session.navigate("next",panel) and session.navigate("previous",panel) and session.audio.snapshot().history.size()==3,"Return back-navigation lost speech replay")
	for i in 5:
		if args.size()==4 and i in [0,1]:
			for mobile in [false,true]:
				canvas.size=Vector2i(800,450) if mobile else Vector2i(960,720);panel.set_mobile_layout(mobile)
				for f in 8:await process_frame
				await RenderingServer.frame_post_draw
				check(canvas.get_texture().get_image().save_png(args[3].path_join("station-return-%d-%s.png"%[i,"phone" if mobile else "desktop"]))==OK,"Could not capture returned station")
		check(session.navigate("next",panel),session.error)
	check(session.snapshot().campaign_cursor==4 and session.snapshot().cargo.used==0 and session.audio._player==null and not panel.visible,"Live return did not finish its cargo/dialogue transaction")
	canvas.free()

func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;printerr("FAIL ",checks,": ",message)
