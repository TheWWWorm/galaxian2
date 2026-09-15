extends "res://tests/alioth_flight.gd"
## Actual application departure, live Alioth battle, docking and station dialogue.
const ReturnRules=preload("res://src/content/alioth_return_definitions.gd")
const FreePlayCheckpoint=preload("res://tests/fixtures/free_play_station_scenario.gd")

func prepare_alioth_flight(station: RefCounted) -> Node3D:
	if not ReturnRules.available(definitions):check(false,"Alioth return declarations are unavailable");return null
	if not is_instance_valid(app):
		app=Host.new();root.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		app.set_context(source,definitions,visual);app.set_process(false);app._focused=true
		var restored:=StationSession.new();app.viewport.add_child(restored);restored._world=station.fork()
		if not restored._build_scene(source,definitions,visual,catalogue,now_us,42) or not app.station_panel.configure_empty(source,definitions) or not restored.activate():check(false,restored.error+app.station_panel.error);return null
		app.session=restored
	app.show();app.present_session();await process_frame
	resume_application_focus()
	var before: Dictionary=app.session.station_owner().snapshot()
	if not app.request_departure():check(false,app.status.text);return null
	app.cancel_departure()
	check(app.session.station_owner().snapshot()==before,"Cancelling Alioth departure changed the earned station")
	if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return null
	check(app.session is FlightSession and app.session.snapshot().campaign_cursor==16,"The application did not enter Alioth's actual flight")
	return app.session

func after_alioth_flight(live: Node3D,frame: RefCounted,station: RefCounted) -> void:
	var initial: Dictionary=station.snapshot();var finished: Dictionary=frame.snapshot()
	var original_stock: Dictionary=station.contract_owner().location_owner().location(98).stock
	check(frame.convoy_career_owner().snapshot().progress==finished.progress,"The accepted Alioth objective lost its retained career")
	check(frame.convoy_career_owner().snapshot().credits==initial.contracts.credits,"Alioth battle paid an unearned reward")
	if not verify_lethal_branch(frame,live.scene):return
	live.rebase_time(now_us);app.present_session()
	if not await dock_application():return
	var docked: Dictionary=app.session.snapshot()
	check(docked.campaign_cursor==17 and docked.loadout.station_id==98 and (docked.docking.pre_motion_contact or docked.docking.post_motion_volume_index>=0),"Alioth returned without actual docking")
	check(docked.progress==docked.contracts.progress and docked.contracts.credits==initial.contracts.credits and docked.cargo==finished.cargo,"Docking changed the earned wallet, cargo or career")
	check(not docked.equipment.has("ship_affiliation"),"Docking applied the affiliation assignment before acknowledgement")
	for tick in 11:
		if not application_step():return
	for event in definitions.mido_travel.alioth_return.events:
		var state: Dictionary=app.session.snapshot()
		check(state.campaign_cursor==17 and state.dialogue.visible and state.dialogue.text_id==int(event.text_id),"Alioth return skipped an original acknowledged line")
		if int(event.text_id) in [1821,1837]:await capture_return_view("alioth-return-%d"%int(event.text_id))
		app.station_navigation("next")
		if app._transition_failed:check(false,app.status.text);return
	var final: Dictionary=app.session.snapshot()
	check(final.campaign_cursor==18 and final.contracts.campaign_cursor==18 and final.phase=="free_play_required" and final.alioth_return_acknowledged and not final.dialogue.visible,"Alioth return did not close at its real next mission")
	check(final.mission=={"kind":156,"station_id":56,"reward":0,"bonus":0,"source_parameter":0},"Alioth return invented or completed the pending Suttnar mission")
	check(final.equipment.ship_affiliation==0 and final.loadout==docked.loadout and final.cargo==docked.cargo,"The original affiliation assignment changed the ship or cargo")
	check(final.contracts.credits==initial.contracts.credits and final.contracts.completed_side_missions==4 and final.reward_credits==0,"Alioth station acknowledgement granted a reward or side-job success")
	var voices:=[]
	for event in definitions.mido_travel.alioth_return.events:
		if int(event.voice_event_id)>=0:voices.append(int(event.voice_event_id))
	check(app.session.audio.snapshot().history.map(func(row):return row.source_id)==voices,"Alioth return omitted or replayed original speech")
	check(final.locations.current_station_id==98 and app.current_locations().location(98).stock==original_stock,"Alioth return regenerated its cached stock")
	var path:=OS.get_environment("GOF2_CAPTURE_FREE_PLAY_STATION")
	if failures==0 and not path.is_empty():
		var checkpoint:=FreePlayCheckpoint.new()
		check(checkpoint.capture(path,app.session.station_owner(),definitions),checkpoint.error)
	print("Application Alioth16 -> live battle -> docking17 -> acknowledged18; retained ",final.contracts.credits," credits")

func capture_return_view(label: String) -> void:
	var directory:=OS.get_environment("GOF2_ALIOTH_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name()=="headless":return
	if not AliothCheckpoint.private_path(directory+"/capture.png"):check(false,"Keep Alioth captures outside engine source");return
	DirAccess.make_dir_recursive_absolute(directory)
	var before: Dictionary=app.session.snapshot()
	resume_application_focus();app.present_session()
	await process_frame
	resume_application_focus();RenderingServer.force_draw(false);await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(label+".png"))==OK,"Cannot capture the Alioth station return")
	root.size=Vector2i(960,540);app.set_mobile_layout(true);app.set_touch_controls(true)
	app.present_session()
	await process_frame
	resume_application_focus();RenderingServer.force_draw(false);await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(label+"-mobile.png"))==OK,"Cannot capture the landscape Alioth station return")
	root.size=Vector2i(1280,720);app.set_mobile_layout(false);app.set_touch_controls(false)
	resume_application_focus();app.present_session()
	check(app.session.snapshot()==before,"Landscape station presentation changed the earned state")

func release_alioth_flight(_live: Node3D) -> void:
	if not OS.get_environment("GOF2_ALIOTH_STATION_SCENARIO").is_empty() and is_instance_valid(app):app.free()

func verify_alioth_stage(live: Node3D,frame: RefCounted) -> bool:
	# Separate lethal diagnostics cover death during the suspended escape view.
	# The successful battle still receives no injected actor damage or progress.
	return verify_lethal_branch(frame,live.scene) if frame.snapshot().alioth_attack.phase==Attack.Stage.ESCAPE_VIEW else true
