extends "res://tests/gate_arrival.gd"
## Earn the actual gate/local trip, acknowledge the original visit, then save,
## reload and depart with the same accepted delivery and inventory.
const SaveFile=preload("res://src/simulation/station_save_file.gd")
const Archive=preload("res://src/simulation/station_archive.gd")
var retained_job:={}

func verify_free_application() -> void:
	var directory:=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	if directory.is_empty() or not FreePlayCheckpoint.private_path(directory+"/save.bin"):check(false,"Set a private campaign visit save directory");return
	app.enable_saves(directory)
	app.show();app.present_session();await process_frame;resume_application_focus()
	var initial: Dictionary=app.session.station_owner().snapshot()
	if initial.campaign_cursor==19 and initial.loadout.station_id==56:
		retained_job=initial.contracts.mission.duplicate(true)
		await verify_visit_continuation(initial)
		if failures:await capture_free_application("campaign-visit-failure")
		return
	if app.session.snapshot().contracts.mission.is_empty():
		# This unescorted journey uses the source's difficulty-one passenger
		# offer. The courier's extra pirate encounter needs combat input.
		if not await acquire_passenger_cabin():return
		var station: RefCounted=app.session.station_owner()
		var state: Dictionary=station.snapshot();var selected:=-1
		for id in state.contracts.offers:
			var offer: Dictionary=state.contracts.offers[id].offer
			if offer.mission.kind==11 and offer.mission.station_id==99 and offer.mission.difficulty==1 and station.contract_preview(id,definitions).get("can_accept",false):selected=id;break
		if selected<0:check(false,"The earned lounge lacks its retained passenger fixture");return
		if not app.contract_action("open",-1) or not app.contract_action("accept",selected) or not app.contract_action("close",-1):check(false,app.session.error);return
	retained_job=app.session.snapshot().contracts.mission.duplicate(true)
	check(retained_job.kind==11 and retained_job.station_id==99 and retained_job.difficulty==1 and app.session.snapshot().contracts.passengers==3,"The visit fixture lost its actual accepted passengers")
	var capture:=OS.get_environment("GOF2_CAPTURE_VISIT_STATION")
	if not capture.is_empty():
		var checkpoint:=FreePlayCheckpoint.new()
		if not checkpoint.capture(capture,app.session.station_owner(),definitions):check(false,checkpoint.error);return
	var ready: Dictionary=app.session.station_owner().snapshot()
	if ready.loadout.station_id==98:await super.verify_free_application()
	elif ready.campaign_cursor==18 and ready.loadout.station_id in [95,70]:await after_local_journeys(ready,{})
	else:check(false,"Use an earned station on the actual Suttnar journey")
	if failures:await capture_free_application("campaign-visit-failure")

func application_step() -> bool:
	if not super.application_step():return false
	if app.session is FlightSession and app.session.flight_owner()._player.snapshot().vitals.hull<=0:
		var state: Dictionary=app.session.snapshot()
		check(false,"The travel fixture was destroyed: "+str({"station":state.location.station_id,"clock":state.world_elapsed_ms,"death":state.player_destruction.phase,"vitals":state.player.vitals}))
		return false
	return true

func after_local_journeys(original: Dictionary,_initial_stock: Dictionary) -> void:
	if app.session.snapshot().loadout.station_id==95:
		if not await visit_gate(14,70):return
		if not await release_application_flight() or not await dock_application():return
	if not await visit_gate(11,55):return
	if not await release_application_flight():return
	check(app.session.snapshot().contracts.travel_statistics.jumpgates_used==2,"Union skipped an intermediate system or counted another jump")
	if not await acquire_application_planet(56):return
	if not app.enter_local_arrival(now_us,4096,1789100000):check(false,app.status.text);return
	var arrival: Dictionary=app.session.snapshot()
	check(arrival.location.station_id==56 and arrival.location.system_id==11 and arrival.campaign_cursor==18,"The trip did not reach the pending Suttnar visit")
	check(arrival.encounter.combat.actors.is_empty() and not arrival.dialogue.visible,"Suttnar created ambient ships or bypassed its flight clock")
	var frame: RefCounted=app.session.flight_owner()
	var field: RefCounted=frame._scenery.presentation_identity()
	var flight: RefCounted=frame._encounter._control.flight_identity()
	app.session.rebase_time(now_us)
	# The launch controller holds the HUD poll clock for its first seven
	# seconds. The first eligible five-second poll follows that release.
	var poll_ticks:=ceili(float(definitions.mido_travel.free_flight.launch_clear_after_ms+definitions.mido_travel.suttnar_visit.hud_poll_minimum_ms)/100.0)+2
	for tick in poll_ticks:
		if app.session.snapshot().dialogue.visible:break
		if not application_step():return
	var opened: Dictionary=app.session.snapshot()
	check(opened.dialogue.visible and opened.dialogue.text_id==int(definitions.mido_travel.suttnar_visit.events[0].text_id) and opened.world_elapsed_ms>10000 and opened.campaign_cursor==18,"The original visit did not open at its eligible poll: "+str({"world_ms":opened.world_elapsed_ms,"hud_ms":opened.hud_elapsed_ms,"visit":opened.mining_objective.campaign_visit.phase}))
	check(not app.session.can_control() and app.session.scene.dialogue.visible,"The visit did not take ownership of flight input")
	if failures:return
	var frozen: Dictionary=app.session.snapshot()
	now_us+=1000000
	if not app.session.step(now_us,Vector2.ONE,true):check(false,app.session.error);return
	check(app.session.snapshot().player_pose==frozen.player_pose and app.session.snapshot().world_elapsed_ms==frozen.world_elapsed_ms,"Modal acknowledgement advanced flight")
	for event in definitions.mido_travel.suttnar_visit.events:
		var line: Dictionary=app.session.snapshot().dialogue
		check(line.text_id==int(event.text_id) and line.voice_event_id==int(event.voice_event_id) and app.session.scene.dialogue._portrait.texture!=null,"The visit lost original text, speech or portraits")
		var speech: Array=app.session.objective_audio.snapshot().history
		check(not speech.is_empty() and speech.back().source_id==int(event.voice_event_id),"The visit did not dispatch the original voice clip")
		check(app.session.snapshot().campaign_cursor==18,"The campaign advanced before the final acknowledgement")
		await capture_free_application("suttnar-line-%d"%int(event.text_id))
		if not app.session.navigate("next"):check(false,app.session.error);return
	var acknowledged: Dictionary=app.session.snapshot()
	check(acknowledged.campaign_cursor==19 and acknowledged.mission=={"kind":156,"station_id":55,"reward":0,"bonus":0,"source_parameter":0} and not acknowledged.dialogue.visible,"The final line did not select the original Kappa objective")
	check(acknowledged.contracts.credits==original.contracts.credits and acknowledged.contracts.completed_side_missions==4 and acknowledged.contracts.mission==retained_job and acknowledged.contracts.passengers==3 and acknowledged.cargo==arrival.cargo,"The visit changed a wallet, accepted job, passengers or cargo")
	check(app.session.flight_owner()._scenery.presentation_identity()==field and app.session.flight_owner()._encounter._control.flight_identity()==flight,"Acknowledgement rebuilt the running world")
	check(acknowledged.encounter.combat.actors.is_empty() and acknowledged.progress.player_kills==arrival.progress.player_kills and acknowledged.progress.capital_ship_kills==arrival.progress.capital_ship_kills,"The visit invented combat or lost a retained statistic")
	verify_retained_geometry(acknowledged)
	if failures:return
	print("Suttnar acknowledged all eight original lines/voices; the existing flight, wallet, passengers and cargo remain owned at cursor19")
	if not await dock_application():return
	var landed: Dictionary=app.session.station_owner().snapshot()
	check(landed.campaign_cursor==19 and landed.loadout.station_id==56 and landed.contracts.mission==retained_job,"Docking lost the acknowledged visit or accepted delivery")
	await verify_visit_continuation(landed)

func verify_retained_geometry(state: Dictionary) -> void:
	var geometry: Node3D=app.session.scene.geometry
	var original: Transform3D=geometry.player.transform
	for invalid in ["missing_receipt","wrong_origin","wrong_destination","wrong_station","unacknowledged"]:
		var altered: Dictionary=app.session.scene._player_geometry_state(state).duplicate(true)
		match invalid:
			"missing_receipt":altered.contracts.flight.erase("story_transition")
			"wrong_origin":altered.contracts.flight.story_transition.from_cursor=17
			"wrong_destination":altered.mission.station_id=57
			"wrong_station":altered.location.station_id=55
			"unacknowledged":altered.mining_objective.campaign_visit.acknowledged=false
		altered.player_pose.origin+=Vector3.ONE
		check(not geometry.apply_state(altered) and geometry.player.transform==original,"Invalid visit transition moved the retained ship: "+invalid)
	check(geometry.apply_state(app.session.scene._player_geometry_state(state)),geometry.error)

func verify_visit_continuation(landed: Dictionary) -> void:
	check(landed.campaign_cursor==19 and landed.loadout.station_id==56 and landed.contracts.passengers==3 and retained_job.kind==11 and retained_job.station_id==99,"The saved continuation lost its earned story or passenger job")
	if not app.save_station():check(false,app._save_notice.text);return
	var file:=SaveFile.new();var document:=file.load_document(app.station_save_path(),definitions,catalogue,source)
	check(document.get("version")==3 and document.get("station",{}).get("campaign_cursor")==19,"The visit did not write a versioned station record")
	if not app.load_station(now_us):check(false,app._save_notice.text);return
	check(app.session.station_owner().snapshot()==landed,"Loading the visit station changed earned progress")
	if OS.get_environment("GOF2_VISIT_STATION_UI_ONLY")=="1":
		await verify_saved_services(landed)
		return
	if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
	if not await release_application_flight():return
	check(app.session.snapshot().campaign_cursor==19 and not app.session.snapshot().encounter.combat.actors.is_empty(),"The next launch repeated the completed story population")
	if not app.open_map():check(false,app.status.text);return
	var kappa: Dictionary=app.map_panel.snapshot().rows.filter(func(row):return row.station_id==55)[0]
	check(kappa.mission_target and not kappa.supported,"The unimplemented Kappa visit was exposed")
	if not app.close_map(now_us):check(false,app.status.text);return
	if not await travel_application(57) or not await dock_application():return
	check(app.session.snapshot().campaign_cursor==19 and app.session.snapshot().loadout.station_id==57 and app.session.snapshot().contracts.mission==retained_job,"Post-visit travel lost its retained career")
	print("Earned Suttnar cursor19 retained through station save/load, departure and Tornard travel")

func verify_saved_services(landed: Dictionary) -> void:
	await capture_free_application("suttnar-station")
	check(app._launch_button.visible and app._hangar_button.visible and app._lounge_button.visible,"The restored station omitted an available service")
	var key:=InputEventKey.new();key.physical_keycode=KEY_H;key.pressed=true;app._unhandled_input(key)
	check(app.equipment_panel.visible and app.session.snapshot().hangar_open,"The restored station's Hangar shortcut failed")
	if failures:return
	await capture_free_application("suttnar-hangar")
	if not app.equipment_action("close"):check(false,app.session.error);return
	key=InputEventKey.new();key.physical_keycode=KEY_L;key.pressed=true;app._unhandled_input(key)
	check(app.lounge_panel.visible and app.session.snapshot().lounge_open,"The restored station's Space Lounge shortcut failed")
	if failures:return
	await capture_free_application("suttnar-lounge")
	if not app.contract_action("close",-1):check(false,app.session.error);return
	var after: Dictionary=app.session.station_owner().snapshot()
	for field in ["credits","mission","passengers","progress"]:
		check(after.contracts[field]==landed.contracts[field],"Browsing restored services changed retained "+field)
	check(after.loadout==landed.loadout and after.cargo==landed.cargo and after.mission==landed.mission,"Browsing restored services changed the ship, cargo or story")
	if not app.load_station(now_us):check(false,app._save_notice.text);return
	check(app.session.station_owner().snapshot()==after,"Service-exit autosave changed the restored station")
	print("Restored Suttnar Hangar/H, Space Lounge/L and service-exit autosave retained the actual career")

func visit_gate(system_id: int,station_id: int) -> bool:
	if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return false
	if not await release_application_flight():return false
	return await follow_gate_course(system_id,station_id)

func follow_gate_course(system_id: int,station_id: int) -> bool:
	if not app.open_map() or not app.switch_map_system(system_id):check(false,app.status.text);return false
	app.map_panel.select_station(station_id);app.map_panel.request_confirmation()
	if not app.confirm_map_planet(station_id,now_us):check(false,app.map_panel.error);return false
	if not await reach_gate_confirmation():return false
	if not app.choose_gate_confirmation(0,now_us):check(false,app.session.error);return false
	app.session.rebase_time(now_us)
	for tick in 90:
		if app.session.status!="running":break
		now_us+=100000
		if not app.session.step(now_us):check(false,app.session.error);return false
	if app.session.status!="gate_arrival_transition_required":check(false,"The actual gate did not complete its animation");return false
	if not app.enter_gate_arrival(now_us,4096,flight_world_seconds()):check(false,app.status.text);return false
	check(app.session.snapshot().location.system_id==system_id and app.session.snapshot().location.station_id==station_id,"The gate arrived outside the selected adjacent system")
	return failures==0
