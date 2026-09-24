extends "res://tests/sahi_flight.gd"
## The same native combat/recovery pilot through the accepted session, not a
## manually advanced world with presentation sampled only for screenshots.
const Session=preload("res://src/presentation/first_flight_session.gd")
const DialoguePanel=preload("res://src/presentation/station_dialogue_panel.gd")
var session: Node3D
var now:=1000000
var observed_phases:={}
var portal_starts:=0
var sound_revision:=-1
var briefing_ids:=[]
var arrival_library: RefCounted
var arrival_visuals: RefCounted
var arrival_bindings: RefCounted
var arrival_catalogues: RefCounted
var arrival_bodies: RefCounted
var arrival_effects: RefCounted

func test_label() -> String:return "Sahi session integration"

func build_flight(library: RefCounted,bindings: RefCounted,cat: RefCounted,visuals: RefCounted,construction: RefCounted) -> Dictionary:
	arrival_library=library;arrival_visuals=visuals
	arrival_bindings=bindings;arrival_catalogues=cat;arrival_bodies=Bodies.new();arrival_effects=Effects.new()
	if not arrival_bodies.configure(library,bindings) or not arrival_effects.configure(library,bindings):check(false,arrival_bodies.error+arrival_effects.error);return {}
	now=1000000;observed_phases={};portal_starts=0;sound_revision=-1
	briefing_ids=bindings.mido_travel.sahi_visit.briefing.events.map(func(event):return int(event.voice_event_id))
	session=Session.new();root.add_child(session)
	if not session.configure_sahi_selected(library,bindings,visuals,construction,now,123) or not session.activate():
		check(false,session.error);session.free();return {}
	check(session.status=="running" and not session.can_control(),"Sahi session skipped its entry camera")
	var entry: RefCounted=session.flight_owner();var initial: Dictionary=entry.snapshot()
	check(entry.construct_sahi_arrival(bindings,cat,4096,123)==null and entry.snapshot()==initial,"Sahi constructed a Void world before actual portal contact")
	return {"frame":session.flight_owner(),"scene":session.scene}

func advance_flight(frame: RefCounted,milliseconds: int,commands: Vector2,throttle: float,fire:=false) -> RefCounted:
	if session.can_control():
		var current: float=session.snapshot().input_throttle
		for step in 10:
			if absf(current-throttle)<.01:break
			var action:="throttle_up" if throttle>current else "throttle_down"
			if not session.action(action):frame.reject(session.error);return null
			current=session.snapshot().input_throttle
	now+=milliseconds*1000
	if not session.step(now,commands,fire):frame.reject(session.error);return null
	var state: Dictionary=session.snapshot()
	var sound: Dictionary=session.flight_audio.snapshot()
	for operation in sound.history:
		if operation.revision>sound_revision and operation.get("source_id")==34 and operation.action in ["start","start_spatial"]:portal_starts+=1
	sound_revision=sound.revision
	var phase: int=state.get("sahi_stage",{}).get("phase",-1)
	if not observed_phases.has(phase):
		observed_phases[phase]=true
		if phase>0:
			check(not session.can_control() and not session.flight_hud_visible(state),"Sahi cinematic retained session controls or HUD")
			var accepted: Dictionary=session.snapshot()
			check(not session.action("autopilot") and not session.select_planet(10),"Sahi cinematic accepted a flight action")
			check(session.snapshot()==accepted and session.flight_audio.snapshot()==sound,"Rejected cinematic input changed the accepted frame or sound")
			check(session.set_pause("user",true,now),session.error)
			now+=500000
			check(session.step(now,Vector2.ONE,true) and session.snapshot()==accepted,"Paused Sahi cinematic advanced its world")
			check(session.flight_audio.snapshot().paused,"Sahi pause did not suspend flight audio")
			check(session.set_pause("user",false,now),session.error)
			if phase==2:
				check(portal_starts==1 and sound.active.has(34),"Sahi portal did not start its original sound exactly once")
	return session.flight_owner()

func navigate_flight(frame: RefCounted,action: String) -> RefCounted:
	if not session.navigate(action):frame.reject(session.error);return null
	return session.flight_owner()

func portal_arrived(frame: RefCounted) -> void:
	check(session.status=="sahi_arrival_transition_required" and not session.can_control(),"Session did not own its completed Sahi portal boundary")
	check(session.snapshot().cargo==frame.snapshot().cargo and session.snapshot().campaign_cursor==24,"Sahi session changed cargo or advanced an unconstructed world")
	var spoken: Array=session.briefing_audio.snapshot().history.map(func(row):return row.source_id)
	check(spoken==briefing_ids,"Sahi session did not play all four original briefing voices in order")
	var sound: Dictionary=session.flight_audio.snapshot()
	check(sound.unsupported.is_empty() and sound.voice_displayed==[true,true,true,true,true],"Sahi did not play its five original radio voices")
	check(portal_starts==1,"Sahi replayed its portal-start sound")
	var held: Dictionary=session.snapshot()
	now+=1000000
	check(session.step(now,Vector2.ONE,true) and session.snapshot()==held,"Completed portal boundary advanced or recommitted the world")
	check(session.flight_audio.snapshot()==sound,"Completed portal boundary repeated audio")
	await verify_void_arrival(frame)

func verify_void_arrival(frame: RefCounted) -> void:
	var before: Dictionary=frame.snapshot()
	if not load("res://src/content/post_sahi_definitions.gd").available(arrival_bindings):
		check(frame.construct_sahi_arrival(arrival_bindings,arrival_catalogues,4096,123)==null and frame.snapshot()==before,"A retained pre-Void pack synthesized missing campaign content")
		print("Retained pack: Sahi boundary verified; Void arrival capability absent")
		return
	for times in [[-1,123],[4096,-1]]:
		var rejected: RefCounted=frame.construct_sahi_arrival(arrival_bindings,arrival_catalogues,times[0],times[1],true,arrival_bodies,arrival_effects)
		check(rejected==null and frame.snapshot()==before,"Rejected Void construction changed the accepted portal frame")
	var next: RefCounted=frame.construct_sahi_arrival(arrival_bindings,arrival_catalogues,4096,123,true,arrival_bodies,arrival_effects)
	if next==null:check(false,frame.error);return
	var state: Dictionary=next.snapshot();var inventory: Dictionary=next.equipment_owner().snapshot()
	check(state.campaign_cursor==25 and state.station_id==-1 and state.system_id==-1 and state.location.void_location,"Actual Sahi portal selected an ordinary or incorrect world")
	check(state.pending_station_id==48 and state.pending_system_id==9 and not state.has("gate_environment") and state.environment_object.resource_id==16994,"Void arrival lost its return destination or original wormhole")
	check(state.player_pose.origin==state.void_environment.player_position and state.entry_conditions.location_match,"Void arrival lost its original gate spawn or special-location selection")
	check(state.departure.mission.kind==156 and state.departure.mission.station_id==-1 and state.departure.mission.reward==0 and state.departure.mission.bonus==0,"Void entry changed its original mission or granted a reward")
	check(state.scenery.departure_population.center==Vector3(-30000,0,30000) and state.scenery.world_initialization.npc_construction.actors.size()==3,"Void entry substituted ordinary traffic or scenery")
	var context: Dictionary=state.scenery.world_initialization.npc_construction.sahi_context
	check(context==state.sahi_context and context.campaign_cursor==25 and context.mission_kind==156,"Void player and cast disagree about the selected mission")
	var expected: Array=before.cargo.entries.duplicate(true);var marked:=false
	for row in expected:
		if row.item_id==131 and not marked:row.mission=true;marked=true
	check(inventory.cargo.entries==expected,"Void arrival changed more than the first existing crystal flag: expected %s, got %s"%[expected,inventory.cargo.entries])
	print("Sahi retained cargo rows: ",before.cargo.entries,"; first item131 protected: ",marked)
	var hold=load("res://src/simulation/flight_cargo.gd").new()
	check(hold.configure_departure(arrival_bindings,arrival_catalogues,next) and hold.snapshot()==inventory.cargo,"Void's live hold rejected or altered its retained protected crystal: "+hold.error)
	var held: Dictionary=hold.snapshot()
	check(not hold.add_entries([{"item_id":132,"quantity":1,"mission":true}]) and hold.snapshot()==held,"Void admitted an unrelated mission cargo marker")
	var protect_again: RefCounted=next.equipment_owner();var protected: Dictionary=protect_again.snapshot()
	check(not protect_again.protect_sahi_cargo(arrival_bindings) and protect_again.snapshot()==protected,"Void replayed Sahi protection from the wrong world")
	for key in ["used","capacity","free_space"]:
		check(inventory.cargo[key]==before.cargo[key],"Void arrival changed retained cargo "+key)
	for key in ["ship_id","equipment_ids","slots"]:
		check(inventory.loadout[key]==before.equipment.loadout[key],"Void arrival changed retained equipment "+key)
	check(state.player.vitals.hull==before.player.vitals.hull and state.player.vitals.armor==before.player.vitals.armor and state.player.vitals.shield==int(before.player.vitals.shield),"Void entry refilled or lost actual ship health")
	check(state.player.gamma==int(before.player.gamma),"Void entry reset the retained ship cache level")
	var expected_progress: Dictionary=before.progress.duplicate(true)
	expected_progress.merge(Career.calculate_progress(arrival_bindings.opening_handoff,25,before.progress.player_kills,before.progress.pirate_kills,before.progress.other_score),true)
	check(state.departure.progress==expected_progress,"Void entry lost combat progress or granted unearned statistics")
	check(frame.snapshot()==before and session.snapshot().campaign_cursor==24,"Preparing the next world prematurely committed the accepted session")
	var repeated: RefCounted=frame.construct_sahi_arrival(arrival_bindings,arrival_catalogues,4096,123,true,arrival_bodies,arrival_effects)
	if repeated==null:check(false,frame.error);return
	check(repeated.equipment_owner().snapshot()==inventory and repeated.snapshot().departure.progress==state.departure.progress,"Retrying Void preparation duplicated cargo or career progress")
	var detached: RefCounted=next.void_environment_owner();detached._state.objects.clear()
	check(next.void_environment_owner().snapshot()==state.void_environment,"A prospective-world consumer mutated retained Void scenery")
	var accepted: Dictionary=session.snapshot();var audio: Dictionary=session.flight_audio.snapshot()
	var old_camera: Camera3D=root.get_camera_3d()
	var rejected:=Session.new();root.add_child(rejected)
	check(not rejected.configure_sahi_arrival(arrival_library,arrival_bindings,arrival_visuals,frame,now,-1,123),"Invalid arrival seed entered a live session")
	rejected.free()
	check(session.snapshot()==accepted and session.flight_audio.snapshot()==audio and root.get_camera_3d()==old_camera,"Rejected arrival changed the accepted session, sound or camera")
	var live:=Session.new();root.add_child(live)
	if not live.configure_sahi_arrival(arrival_library,arrival_bindings,arrival_visuals,frame,now,4096,123):check(false,live.error);live.free();return
	var entry: Dictionary=live.snapshot()
	check(entry.player.vitals==state.player.vitals and entry.cargo==inventory.cargo and entry.progress==expected_progress,"Live Void session reset retained ship pools, cargo or progress")
	check(frame.snapshot()==before and session.snapshot()==accepted and session.flight_audio.snapshot()==audio and root.get_camera_3d()==old_camera,"Prospective live arrival took over the accepted Sahi session")
	check(not session.configure_sahi_arrival(arrival_library,arrival_bindings,arrival_visuals,frame,now,4096,123) and session.snapshot()==accepted,"In-place arrival destroyed its current session")
	session.scene.set_display_active(false)
	check(session.set_pause("transition",true,now),session.error)
	await verify_live_void(live,arrival_bindings,now)
	live.free()
	print("Actual Sahi portal adopted Void25: ",inventory.cargo.used," retained cargo; hull ",state.player.vitals.hull,"; native movement, world and original result; no return mission granted")

## Shared acceptance observations for the focused selected-world case and the
## actual living Sahi portal. Only the latter proves the transition prerequisite.
func verify_live_void(live: Node3D,bindings: RefCounted,clock: int) -> void:
	var initial: Dictionary=live.snapshot()
	check(initial.campaign_cursor==25 and initial.location.station_id==-1 and initial.location.system_id==-1 and initial.mission.kind==156,"Void session selected an ordinary location or mission")
	check(initial.actors.size()==3 and initial.actors.all(func(actor):return actor.actor_kind==9),"Void session substituted ordinary traffic")
	check(not initial.has("sahi_stage") and not initial.has("station_exterior") and initial.has("void_portal") and initial.pending_station_id==48 and initial.pending_system_id==9,"Void session retained Sahi controls/scenery or lost the returning portal/destination")
	check(initial.void_portal.position==initial.environment_object.position and initial.void_portal.visible and live.scene.portal!=null,"Void did not present its generated source wormhole")
	check(initial.player_pose.origin==Vector3(0,-6541,194479) and initial.void_portal.position==Vector3(2339,8951,75581),"Seed4096 lost the independent gate-then-wormhole placement draws")
	var entry: Dictionary=live.flight_owner()._entry
	check(entry.player_yaw_units==32768 and entry.before_yaw_random_state==entry.yaw_random_state and initial.player_pose.basis.z.dot(Vector3.FORWARD)>.99999 and initial.player_pose.basis.y==Vector3.UP,"Void arrival consumed ordinary launch yaw or inherited gate pitch")
	check(live.scene.void_environment!=null and live.scene.sun==null and live.scene.planets==null and live.scene.station==null,"Void rendered an ordinary star system")
	check(live.scene.void_environment.station.get_child_count()==3 and live.scene.gates!=null,"Void scene lost its original station assembly or gate")
	check(not live.scene.visible and live.scene.get_children().filter(func(node):return node is CanvasLayer).all(func(layer):return not layer.visible),"Prepared arrival appeared before activation")
	check(live.flight_audio.snapshot().history.is_empty(),"Prepared arrival played sound before activation")
	if not live.activate():check(false,live.error);return
	check(live.scene.visible and root.get_camera_3d()==live.camera and not live.activate(),"Void activation did not adopt exactly once")
	var accepted: Dictionary=live.snapshot();var audio: Dictionary=live.flight_audio.snapshot()
	check(not live.step(clock+100000,Vector2(INF,0)) and live.snapshot()==accepted and live.flight_audio.snapshot()==audio,"Invalid Void controls changed the accepted frame or audio")
	await capture_frame(live.scene,live.flight_owner(),"void-live-arrival")
	var controlled:=false;var modal:=false
	for tick in 250:
		clock+=100000
		if not live.step(clock,Vector2(.15,.25),true):check(false,live.error);return
		var state: Dictionary=live.snapshot()
		if live.can_control() and not controlled:
			controlled=true
			var before: Dictionary=live.snapshot()
			check(not live.action("autopilot") and live.snapshot()==before,"Void selected a nonexistent docking station")
			check(live.set_pause("user",true,clock),live.error)
			clock+=500000
			check(live.step(clock,Vector2.ONE,true) and live.snapshot()==before and live.flight_audio.snapshot().paused,"Paused Void flight advanced gameplay or failed to pause sound")
			check(live.set_pause("user",false,clock),live.error)
		if state.world_elapsed_ms<=10000:check(not state.dialogue.visible,"Void mission completed at or before the strict source threshold")
		if state.dialogue.visible:
			modal=true
			check(state.world_elapsed_ms>10000 and state.dialogue.count==3,"Void result lost its source time predicate or three original lines")
			break
	check(controlled and modal,"Void entry did not release control and reach its original result")
	if not modal:return
	var result: Dictionary=live.snapshot()
	check(result.mining_objective.mission_completed and result.campaign_cursor==25,"Void result failed to complete its mission while retaining the campaign cursor")
	check(result.player_pose!=initial.player_pose and result.actors[0].body_pose!=initial.actors[0].body_pose,"Live Void player or original cast did not move")
	check(result.gate_animation!=initial.gate_animation,"The live Void gate clock did not advance")
	check(result.cargo==initial.cargo and result.equipment.loadout==initial.equipment.loadout and result.progress.player_kills==initial.progress.player_kills,"Void result invented cargo, equipment or kill rewards")
	check(result.player.vitals.hull>0 and not live.can_control(),"Void result did not retain the living player and modal input gate")
	await capture_frame(live.scene,live.flight_owner(),"void-live-result")
	clock+=100000
	if not live.step(clock,Vector2.ONE,true):check(false,live.error);return
	var frozen: Dictionary=live.snapshot()
	for key in ["player_pose","player","world_elapsed_ms","world_phase_elapsed_ms","cargo","random_state","gate_animation","void_portal","radio"]:
		check(frozen[key]==result[key],"Void modal advanced "+key)
	var source: Array=bindings.mido_travel.post_sahi.void.result_events if bindings.mido_travel.post_sahi.void.has("result_events") else Frame.OrdinaryFlight.Authored.Post.mission(bindings,25).result_events
	var before_ack: Dictionary=live.snapshot()
	# The selected world has no contract owner. Add only the retained-career UI
	# discriminator to detached presentation state; never modify the live frame.
	var ui_contracts:={"base_content_id":result.base_content_id,"binding_id":result.binding_id,
		"campaign_cursor":result.campaign_cursor,"progress":result.progress.duplicate(true)}
	var panel:=DialoguePanel.new();root.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ui_state: Dictionary=before_ack.duplicate(true);ui_state.contracts=ui_contracts
	if not panel.configure_flight(arrival_library,bindings,arrival_visuals,ui_state):check(false,panel.error);panel.free();return
	check(source.any(func(row):return int(row.speaker_id)==6) and panel._portraits.has(6),"Retained-career Void UI did not load the original result speaker")
	for row in source:
		var live_state: Dictionary=live.snapshot();var shown: Dictionary=live_state.dialogue
		check(shown.text_id==int(row.text_id) and shown.speaker_id==int(row.speaker_id) and shown.voice_event_id==int(row.voice_event_id),"Void result displayed the wrong original line")
		ui_state=live_state.duplicate(true);ui_state.contracts=ui_contracts.duplicate(true)
		check(panel.present(ui_state) and panel.visible and panel._portrait.texture==panel._portraits.get(int(row.speaker_id)) and panel._body.text==shown.desktop_text and panel._name.text==shown.speaker_name,"Retained-career Void UI lost the original result portrait or text")
		if not live.navigate("next"):check(false,live.error);panel.free();return
	panel.free()
	check(live.snapshot().campaign_cursor==26 and before_ack.campaign_cursor==25,"Void UI fixture changed live campaign progress")
	check(live.objective_audio.snapshot().history.map(func(row):return int(row.source_id))==source.map(func(row):return int(row.voice_event_id)),"Void result did not speak each original voice in order")
	var acknowledged: Dictionary=live.snapshot()
	check(live.status=="running" and live.can_control() and acknowledged.campaign_cursor==26 and acknowledged.mission==Frame.OrdinaryFlight.Authored.Post.active_mission(bindings,26) and not acknowledged.station_return_supported,"Void final Next failed to select the pending pursuit in its existing flight")
	var earned: Dictionary=result.progress.duplicate(true)
	earned.merge(Career.calculate_progress(bindings.opening_handoff,26,earned.player_kills,earned.pirate_kills,earned.other_score),true)
	check(acknowledged.mining_objective.mission_completed and acknowledged.progress==earned and acknowledged.encounter.campaign_cursor==25,"Void acknowledgement lost completion or its physical encounter identity")
	for key in ["player_pose","player","actors","cargo","random_state","world_elapsed_ms","void_portal"]:
		check(acknowledged[key]==before_ack[key],"Void result acknowledgement reset "+key)
	check(live.flight_audio.snapshot().unsupported.is_empty(),"Void flight reported unsupported original audio")
	if failures:return
	print("Void live session: ",result.world_elapsed_ms,"ms; three moving source actors; result voices ",source.map(func(row):return row.voice_event_id),"; retained cargo ",result.cargo.used)
	await enter_void_return(live,clock)

func enter_void_return(live: Node3D,clock: int) -> void:
	var initial: Dictionary=live.snapshot();var relocated:=false
	# Mission25 requires escaping through the portal, not defeating its cast.
	# Fly the actual corrected incoming heading and retain any pursuit damage.
	var previous_portal: Vector3=live.snapshot().void_portal.position
	relocated=previous_portal!=initial.void_portal.position
	while live.snapshot().input_throttle<.99:
		if not live.action("throttle_up"):check(false,live.error);return
	for tick in 3500:
		var state: Dictionary=live.snapshot()
		if live.status=="void_return_transition_required":
			check(state.void_portal_contact.portal_entered and state.player.vitals.hull>0,"Void return accepted a dead or noncontacting player")
			check(state.campaign_cursor==26 and state.mission==initial.mission and state.cargo==initial.cargo,"Void portal changed the acknowledged campaign or cargo before adoption")
			check(not state.dialogue.visible and not live.can_control(),"Void return did not hold its accepted flight boundary")
			var audio: Dictionary=live.flight_audio.snapshot()
			clock+=1000000
			var frozen: bool=live.step(clock,Vector2.ONE,true)
			var held: Dictionary=live.snapshot();var held_audio: Dictionary=live.flight_audio.snapshot()
			if not frozen or held!=state or held_audio!=audio:
				print("Void boundary differences: ",state.keys().filter(func(key):return held.get(key)!=state[key]),"; audio ",audio.keys().filter(func(key):return held_audio.get(key)!=audio[key]),"; ",live.error)
			check(frozen and held==state and held_audio==audio,"Void boundary advanced the world or repeated audio")
			if failures:return
			await capture_frame(live.scene,live.flight_owner(),"void-return-contact")
			print("Void return contact at ",state.world_phase_elapsed_ms,"ms; hull ",state.player.vitals.hull,"; recurring relocation observed ",relocated)
			await verify_void_return(live,clock)
			return
		var offset: Vector3=state.void_portal.position-state.player_pose.origin
		var local: Vector3=state.player_pose.basis.inverse()*offset
		var angles:=Vector2(-atan2(local.y,sqrt(local.x*local.x+local.z*local.z)),atan2(local.x,local.z))
		var commands:=Vector2(signf(angles.x)*sqrt(minf(absf(angles.x)*2.0,1.0)),signf(angles.y)*sqrt(minf(absf(angles.y)*2.0,1.0)))
		clock+=100000
		if not live.step(clock,commands,false):check(false,live.error);return
		if live.flight_owner().death_active():check(false,"Void return pilot died before entering the original portal");return
		if live.snapshot().void_portal.position!=previous_portal:
			relocated=true;previous_portal=live.snapshot().void_portal.position
			check(live.snapshot().void_portal.elapsed_ms==-3000 and live.snapshot().void_portal.visible,"The recurring Void portal lost its opening state")
			await capture_frame(live.scene,live.flight_owner(),"void-return-relocated")
		if tick%500==0:print("Void pilot tick ",tick," distance ",int(offset.length())," hull ",state.player.vitals.hull)
		if tick%20==0:await process_frame
	check(false,"Native Void flight did not enter its returning wormhole")

func verify_void_return(departing: Node3D,clock: int) -> void:
	var accepted: Dictionary=departing.snapshot();var active_camera:=root.get_camera_3d()
	var source: RefCounted=departing.flight_owner()
	var source_before: Dictionary=source.snapshot()
	for times in [[-1,123],[4096,-1]]:
		check(source.construct_void_return(arrival_bindings,arrival_catalogues,times[0],times[1],true,arrival_bodies,arrival_effects)==null and source.snapshot()==source_before,"Rejected return preparation changed the accepted Void frame")
	var candidate: RefCounted=source.construct_void_return(arrival_bindings,arrival_catalogues,4096,123,true,arrival_bodies,arrival_effects)
	if candidate==null:check(false,source.error);return
	var entry: Dictionary=candidate.snapshot()
	var incoming: Dictionary=entry.departure.arrival_environment
	check(entry.campaign_cursor==26 and entry.location.station_id==48 and entry.location.system_id==9 and entry.pending_station_id==48 and entry.pending_system_id==9,"Void return lost the current/pending Sahi destination")
	check(incoming.source=="cached_planet" and incoming.cache_station_id==45 and incoming.planet_index==1,"Void return ignored the second retained location's planet")
	check(entry.player_pose.origin==incoming.planets.entries[1].origin*4.0 and entry.player_pose.basis.z.dot(-entry.player_pose.origin.normalized())>.99999,"Void return lost its fresh source planet position/heading")
	check(entry.player_pose!=accepted.player_pose and entry.before_yaw_random_state==entry.yaw_random_state,"Return retained the contact pose or consumed ordinary launch yaw")
	check(entry.departure.cargo==accepted.cargo and entry.player.vitals==accepted.player.vitals,"Return changed retained cargo or actual ship pools")
	check(entry.departure.progress==accepted.progress,"Void portal advanced the acknowledged career a second time")
	check(entry.departure.mission=={"kind":4,"station_id":48,"reward":0,"bonus":0,"source_parameter":0},"Return selected another pursuit mission or granted a reward")
	for actor in entry.scenery.world_initialization.npc_construction.actors:
		var delta: Vector3=actor.body_pose.origin-entry.player_pose.origin-entry.player_pose.basis.z.normalized()*8000.0
		check(delta.x>=-700 and delta.x<700 and delta.y>=-700 and delta.y<700 and delta.z>=-700 and delta.z<700,"Pursuer was not placed around the fresh player's forward point")
	var next:=Session.new();root.add_child(next)
	if not next.configure_void_return(arrival_library,arrival_bindings,arrival_visuals,source,clock,4096,123):check(false,next.error);next.free();return
	check(root.get_camera_3d()==active_camera and not next.scene.visible and next.flight_audio.snapshot().history.is_empty(),"Prepared return stole the camera or played before adoption")
	if not next.activate():check(false,next.error);next.free();return
	check(next.snapshot().actors.size()==2 and not next.snapshot().has("void_environment") and not next.snapshot().has("radio"),"Sahi pursuit retained the Void environment/radio or lost its two ships")
	await capture_frame(next.scene,next.flight_owner(),"void-return-arrival")
	var briefing:=false
	for tick in 150:
		clock+=100000
		if not next.step(clock):check(false,next.error);next.free();return
		if next.snapshot().dialogue.visible:briefing=true;break
	check(briefing,"Pursuit did not open its original entry briefing")
	if briefing:
		var events: Array=arrival_bindings.mido_travel.post_sahi.missions["26"].briefing_events
		for event in events:
			check(next.snapshot().dialogue.text_id==int(event.text_id) and next.snapshot().dialogue.voice_event_id==int(event.voice_event_id),"Pursuit briefing selected another original line")
			if not next.navigate("next"):check(false,next.error);next.free();return
		check(next.briefing_audio.snapshot().history.map(func(row):return int(row.source_id))==events.map(func(row):return int(row.voice_event_id)),"Pursuit briefing voices were missing or repeated")
		check(next.can_control() and next.snapshot().campaign_cursor==26 and not next.snapshot().mining_objective.mission_completed,"Briefing granted pursuit completion or withheld flight")
	print("Void return adopted original pursuit26; hull ",next.snapshot().player.vitals.hull,"; planet slot ",incoming.planet_index)
	if briefing:await verify_pursuit_completion(next,clock)
	next.free()

func verify_pursuit_completion(live: Node3D,clock: int) -> int:
	var initial: Dictionary=live.snapshot()
	var preceding_session:=session;var preceding_clock:=now
	session=live;now=clock
	var survived: RefCounted=await recover_void_cargo(live.flight_owner(),live.scene,false)
	clock=now;session=preceding_session;now=preceding_clock
	if survived==null:return -1
	for tick in 80:
		if live.snapshot().dialogue.visible:break
		clock+=100000
		if not live.step(clock):check(false,live.error);return -1
	var result: Dictionary=live.snapshot()
	check(result.dialogue.visible and result.mining_objective.mission_completed and result.actors.filter(func(actor):return actor.actor_mode==4).size()==2,"Native pursuit defeats did not open the completed two-line result")
	if not result.dialogue.visible:return -1
	check(result.campaign_cursor==26 and result.cargo==initial.cargo and result.progress.player_kills==initial.progress.player_kills+2 and result.reward_credits==0,"Pursuit result changed cargo/cursor or lost actual combat accounting")
	await capture_frame(live.scene,live.flight_owner(),"pursuit-result")
	for event in [1920,1921]:
		check(live.snapshot().dialogue.text_id==event,"Pursuit result selected another original line")
		if not live.navigate("next"):check(false,live.error);return -1
	check(live.objective_audio.snapshot().history.map(func(row):return int(row.source_id))==[313,314],"Pursuit result lost its original voices")
	var acknowledged: Dictionary=live.snapshot()
	check(live.can_control() and acknowledged.campaign_cursor==27 and acknowledged.mission=={"kind":11,"station_id":10,"reward":0,"bonus":0,"source_parameter":0} and not acknowledged.mining_objective.station_return_required,"Pursuit final Next failed to advance27 and restore ordinary navigation")
	check(acknowledged.encounter.campaign_cursor==26 and acknowledged.local_travel.campaign_cursor==27,"Pursuit completion replaced the physical encounter or lost navigation")
	for key in ["player_pose","player","actors","cargo","random_state","world_elapsed_ms","station_autopilot"]:
		check(acknowledged[key]==result[key],"Pursuit acknowledgement reset "+key)
	var source_frame: RefCounted=live.flight_owner()
	var departing: RefCounted=source_frame.select_planet(45)
	check(departing!=null,"Pursuit completion requires docking before ordinary planet guidance: "+source_frame.error)
	if departing!=null:
		var guidance: Dictionary=departing.snapshot().station_autopilot
		check(guidance.active and guidance.target_kind=="planet" and guidance.station_id==45 and guidance.history==acknowledged.station_autopilot.history,"Ordinary planet selection lost its target or retained steering history")
	check(live.snapshot()==acknowledged,"Detached planet guidance changed the accepted pursuit flight")
	print("Native pursuit26 completed: two mode4 actors; hull ",acknowledged.player.vitals.hull,"; pending27 in the retained flight")
	clock=await verify_pursuit_docking(live,clock)
	return clock

func verify_pursuit_docking(live: Node3D,clock: int) -> int:
	var initial: Dictionary=live.snapshot()
	check(initial.station_return_supported,"Pursuit return has no native station docking")
	if not live.action("autopilot"):check(false,live.error);return clock
	for tick in 3000:
		if live.status=="station_transition_required":break
		clock+=100000
		if not live.step(clock):check(false,live.error);return clock
		if live.flight_owner().death_active():check(false,"Pursuit pilot died before docking at Sahi");return clock
		if tick%500==0:print("Pursuit docking tick ",tick," position ",live.snapshot().player_pose.origin)
		if tick%30==0:await process_frame
	if live.status!="station_transition_required":check(false,"Pursuit guidance did not reach Sahi docking");return clock
	var accepted: Dictionary=live.snapshot();var packet: Dictionary=live.flight_owner().prepare_station()
	check(packet.campaign_cursor==27 and packet.docking.station_id==48 and packet.cargo==initial.cargo,"Pursuit docking lost the acknowledged career, Sahi or retained cargo")
	check(packet.player==accepted.player and packet.player_cache.values.hull==accepted.player.vitals.hull and packet.player_cache.values.shield==int(accepted.player.vitals.shield),"Sahi docking refilled or changed the current pools")
	check(packet.progress==accepted.progress and packet.mission==initial.mission,"Docking advanced the story again or replaced the pending Thynome visit")
	await capture_frame(live.scene,live.flight_owner(),"pursuit-sahi-docking")
	print("Pursuit26 reached actual Sahi dock; hull ",accepted.player.vitals.hull,"; retained cargo ",packet.cargo.used)
	return clock

func finish_flight(_scene: Node3D) -> void:session.free()
