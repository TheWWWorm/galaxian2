extends "res://tests/sahi_session.gd"
## Selected193 component. The living return is covered by sahi_session; this
## fixture verifies native combat but does not establish an earned saved route.
const Post=preload("res://src/content/post_sahi_definitions.gd")
const Ordinary=preload("res://src/content/ordinary_flight_definitions.gd")
const Objective=preload("res://src/simulation/mining_objective.gd")
const Cargo=preload("res://src/simulation/flight_cargo.gd")
const Cache=preload("res://src/simulation/flight_player_cache.gd")
const LiveSession=preload("res://src/presentation/first_flight_session.gd")
const StationEntry=preload("res://src/simulation/station_entry.gd")

func test_label() -> String:return "Post-Sahi pursuit objective"
func component_equipment() -> Array:return [2,86,81,68]

func after_prepared(library: RefCounted,bindings: RefCounted,cat: RefCounted,prepared: RefCounted) -> void:
	if not Post.available(bindings):check(false,"Selected193 lacks post-Sahi source declarations");return
	if not library.select_language("gb"):check(false,library.error);return
	var component: Dictionary=selected_sahi_with_locations(library,bindings,cat,prepared,null,null)
	if component.is_empty():return
	var sahi: RefCounted=component.construction;var locations: RefCounted=component.locations
	var source: Dictionary=sahi.snapshot()
	var equipment: RefCounted=sahi.equipment_owner()
	var sahi_loadout: Dictionary=equipment.snapshot().loadout
	if not equipment.relocate_post_sahi(bindings,25):check(false,equipment.error);return
	var cache25: Dictionary=Cache.capture_post_sahi(bindings.mido_travel,sahi_loadout,equipment.snapshot().loadout,sahi.player_owner().snapshot(),25)
	if cache25.is_empty():check(false,"Selected Sahi fixture could not retain the Void player cache");return
	var progress25: Dictionary=source.departure.progress.duplicate(true)
	progress25.merge(Career.calculate_progress(bindings.opening_handoff,25,progress25.player_kills,progress25.pirate_kills,progress25.other_score),true)
	var context25: Dictionary=source.sahi_context.duplicate(true)
	context25.merge({"campaign_cursor":25,"station_id":-1,"system_id":-1,"mission_kind":156,"rank":progress25.rank},true)
	var void_world:=FlightConstruction.new()
	if not void_world.prepare_post_sahi_selected(bindings,cat,equipment,context25,progress25,{},4096,123,true,null,null,cache25,null,locations):check(false,void_world.error);return
	check(void_world.selected_locations_owner().snapshot()==locations.snapshot(),"Selected Void world lost the generated Sahi history")
	var void_loadout: Dictionary=void_world.equipment_owner().snapshot().loadout
	var returning: RefCounted=void_world.equipment_owner()
	if not returning.relocate_post_sahi(bindings,26):check(false,returning.error);return
	var cache26: Dictionary=Cache.capture_post_sahi(bindings.mido_travel,void_loadout,returning.snapshot().loadout,void_world.player_owner().snapshot(),26)
	if cache26.is_empty():check(false,"Selected Void fixture could not retain the return player cache");return
	var progress26: Dictionary=void_world.snapshot().departure.progress.duplicate(true)
	progress26.merge(Career.calculate_progress(bindings.opening_handoff,26,progress26.player_kills,progress26.pirate_kills,progress26.other_score),true)
	var context26: Dictionary=void_world.snapshot().sahi_context.duplicate(true)
	context26.merge({"campaign_cursor":26,"station_id":48,"system_id":9,"mission_kind":4,"rank":progress26.rank},true)
	check(Post.selected(bindings.mido_travel,context26),"Selected Void context did not retain the source pursuit identity: "+str(context26))
	var placement:=load("res://src/content/local_arrival_environment_definitions.gd")
	var world: Dictionary=load("res://src/content/ordinary_world_definitions.gd").catalogue_location(bindings,cat,48)
	check(placement.location_supported(bindings,cat,48,26),"Selected193 cannot place the return planet: available="+str(placement.available(bindings))+" content="+str(cat.content_id==bindings.base_content_id)+" world="+str(world))
	var bodies:=Bodies.new();var effects:=Effects.new()
	if not bodies.configure(library,bindings) or not effects.configure(library,bindings):check(false,bodies.error+effects.error);return
	var before_return: Dictionary=returning.snapshot();var before_history: Dictionary=locations.snapshot()
	var missing_history:=FlightConstruction.new()
	check(not missing_history.prepare_post_sahi_selected(bindings,cat,returning,context26,progress26,{},4096,123,true,bodies,effects,cache26) and missing_history.snapshot().is_empty() and returning.snapshot()==before_return and locations.snapshot()==before_history,"Selected pursuit26 accepted missing location history or changed its inputs")
	var selected:=FlightConstruction.new()
	if not selected.prepare_post_sahi_selected(bindings,cat,returning,context26,progress26,{},4096,123,true,bodies,effects,cache26,null,locations):check(false,selected.error);return
	check(selected.selected_locations_owner().snapshot()==locations.snapshot(),"Selected return world lost the generated Sahi history")
	var arrival_player: Dictionary=selected.player_owner().snapshot()
	var retained: Dictionary=StationEntry.retained_player_state(arrival_player)
	check(load("res://src/simulation/station_archive.gd").data_tree(retained) and retained.vitals==arrival_player.vitals,"The returned player cannot retain its actual pools as station save data")
	check(selected.player_owner().snapshot()==arrival_player and selected.snapshot().sahi_context.player_pose==arrival_player.sahi_context.player_pose,"Station metadata changed the live player or pursuit placement")
	if failures:return
	var incoming: Dictionary=selected.snapshot().departure.arrival_environment
	check(incoming.source=="cached_planet" and incoming.cache_station_id==45 and incoming.planet_index==1,"Selected pursuit return ignored the actual cached planet")
	var mission: Dictionary=Post.mission(bindings,26)
	var briefing: Dictionary=Ordinary.briefing_presentation(bindings,26)
	var rules: Dictionary=Ordinary.objective(bindings,26)
	check(briefing.campaign_cursor==26 and briefing.mission_kind==4 and briefing.events==mission.briefing_events,"Pursuit briefing lost original1917–1919/173–175")
	check(rules.campaign_cursor==26 and rules.mission_kind==4 and rules.station_id==48 and rules.required_cargo==0 and rules.events==mission.result_events and rules.pursuit_condition=={"kind":7,"value":2},"Pursuit objective lost source mission, result or condition")
	var objective:=Objective.new()
	if not objective.configure(bindings,library,selected,"A","E"):check(false,objective.error);return
	var cargo:=Cargo.new()
	if not cargo.configure_departure(bindings,cat,selected):check(false,cargo.error);return
	var encounter:=Encounter.new()
	if not encounter.configure_story(bindings,cat,library,selected.player_owner(),selected.scenery_owner(),selected.equipment_owner(),progress26.reputation):check(false,encounter.error);return
	var initial: Dictionary=objective.snapshot()
	check(initial.campaign_cursor==26 and initial.mission==selected.snapshot().departure.mission and initial.mission.kind==4 and not initial.mission_completed and not initial.combat_objective_satisfied and initial.progress==progress26,"Pursuit began completed or altered the retained mission")
	check(encounter.snapshot().combat.actors.size()==2 and encounter.snapshot().combat.actors.all(func(actor):return actor.actor_mode!=4),"Pursuit component lost its two live actors")
	var observed: Dictionary=encounter.snapshot()
	var invalid: RefCounted=encounter.fork_for_frame();invalid._identity=invalid._identity.duplicate();invalid._identity.binding_id="foreign"
	check(not objective.poll(cargo,selected.scenery_owner(),true,invalid) and objective.snapshot()==initial,"Foreign encounter changed pursuit progress")
	check(objective.poll(cargo,selected.scenery_owner(),true,encounter) and objective.snapshot()==initial,"Zero mode4 actors completed pursuit")
	for matched in 4:
		var modes:=[]
		for id in 3:modes.append({"actor_mode":4 if id<matched else 1})
		check(Objective._pursuit_mode_four_count(modes)==matched and (Objective._pursuit_mode_four_count(modes)==2)==(matched==2),"Condition7 did not count exactly "+str(matched)+" mode4 actors")
	encounter._combat._actors[0]._state.actor_mode=4
	check(objective.poll(cargo,selected.scenery_owner(),true,encounter) and not objective.snapshot().combat_objective_satisfied,"One mode4 actor completed pursuit")
	encounter._combat._actors[1]._state.actor_mode=4
	check(objective.poll(cargo,selected.scenery_owner(),false,encounter) and not objective.snapshot().combat_objective_satisfied,"Dead player received pursuit result")
	if not objective.poll(cargo,selected.scenery_owner(),true,encounter):check(false,objective.error);return
	var result: Dictionary=objective.snapshot()
	check(result.phase=="return_instructions" and result.mission_completed and result.combat_objective_satisfied and result.dialogue.visible and result.dialogue.count==2,"Exactly two mode4 actors did not open the completed result")
	check(result.campaign_cursor==26 and result.mission==initial.mission and result.reward_credits==0 and result.progress==initial.progress and cargo.snapshot().used==0,"Pursuit result granted cursor, credits, kill progress or cargo")
	for row in mission.result_events:
		var line: Dictionary=objective.snapshot().dialogue
		check(line.text_id==int(row.text_id) and line.speaker_id==int(row.speaker_id) and line.voice_event_id==int(row.voice_event_id),"Pursuit result lost original1920–1921/313–314")
		check(objective.navigate("next"),objective.error)
	var acknowledged: Dictionary=objective.snapshot()
	var earned: Dictionary=initial.progress.duplicate(true)
	earned.merge(Career.calculate_progress(bindings.opening_handoff,27,earned.player_kills,earned.pirate_kills,earned.other_score),true)
	check(acknowledged.campaign_cursor==27 and acknowledged.progress==earned and acknowledged.mission==Post.active_mission(bindings,27) and acknowledged.mission_completed and acknowledged.combat_objective_acknowledged and not acknowledged.station_return_required and not acknowledged.dialogue.visible,"Pursuit final Next failed to advance27 and retire the selected mission")
	check(not objective.navigate("next") and objective.poll(cargo,selected.scenery_owner(),true,encounter) and objective.snapshot()==acknowledged,"Pursuit acknowledgement or result replayed")
	check(encounter.snapshot().get("binding_id")==observed.binding_id,"Detached identity rejection mutated the accepted encounter")
	await verify_live_pursuit(library,bindings,cat,selected)

func verify_live_pursuit(library: RefCounted,bindings: RefCounted,cat: RefCounted,selected: RefCounted) -> void:
	var visuals:=Visuals.new()
	if not visuals.open(visual_path,library.manifest):check(false,visuals.error);return
	root.size=Vector2i(1280,720)
	var live:=LiveSession.new();root.add_child(live)
	var clock:=1000000
	if not live._configure_construction(library,bindings,visuals,cat,selected,clock,123,false):check(false,live.error);live.free();return
	check(not live.scene.visible and live.flight_audio.snapshot().history.is_empty(),"Prepared pursuit became visible or audible before adoption")
	if not live.activate():check(false,live.error);live.free();return
	check(live.snapshot().actors.size()==2 and not live.snapshot().has("radio") and live.scene.station!=null and live.scene.planets!=null,"Pursuit scene lost its original cast/environment or invented a radio")
	for tick in 150:
		clock+=100000
		if not live.step(clock):check(false,live.error);live.free();return
		if live.snapshot().dialogue.visible:break
	check(live.snapshot().dialogue.visible,"Pursuit session did not open its briefing")
	if live.snapshot().dialogue.visible:
		for event in bindings.mido_travel.post_sahi.missions["26"].briefing_events:
			check(live.snapshot().dialogue.text_id==int(event.text_id),"Pursuit session selected the wrong briefing line")
			if not live.navigate("next"):check(false,live.error);live.free();return
		check(live.briefing_audio.snapshot().history.map(func(row):return int(row.source_id))==[173,174,175],"Pursuit session lost its three original briefing voices")
		check(live.can_control() and not live.snapshot().mining_objective.mission_completed,"Pursuit briefing completed combat or withheld native flight")
		verify_unfinished_contact(live)
		await verify_pursuit_completion(live,clock)
	live.free()

func verify_unfinished_contact(live: Node3D) -> void:
	# Detached station-contact fixture, not flown progress. The independent live
	# pilot below covers real completed combat and autopilot docking.
	var accepted: Dictionary=live.snapshot()
	var contact: RefCounted=live.flight_owner().start_station_autopilot()
	if contact==null:check(false,live.flight_owner().error);return
	contact._pose.origin=Vector3.ZERO;contact._station_contact=true
	if not contact._evaluate_station_return():check(false,contact.error);return
	var packet: Dictionary=contact.prepare_station()
	check(packet.is_empty() and contact.snapshot().campaign_cursor==26 and not contact.snapshot().mining_objective.mission_completed and contact.snapshot().progress==accepted.progress and contact.snapshot().cargo==accepted.cargo,"Unfinished pursuit contact bypassed its mission restriction or changed progress/cargo")
	check(live.snapshot()==accepted,"Detached unfinished docking mutated the active flight")
