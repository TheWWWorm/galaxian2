extends "res://tests/convoy_flight.gd"
## Four earned application jobs, ordinary transit14 and actual capture arrival.
## Inherited contact RNG and lethal contacts are explicit diagnostic fixtures.
const Transit=preload("res://src/content/convoy_transit_definitions.gd")
const TravelRules=preload("res://src/content/mido_travel_definitions.gd")
const OrdinaryRules=preload("res://src/content/ordinary_flight_definitions.gd")
const TransitCheckpoint=preload("res://tests/fixtures/transit_station_scenario.gd")
const TouchInput=preload("res://tests/fixtures/touch_input.gd")

func _initialize() -> void:
	call_deferred("run_transit_checkpoint" if not OS.get_environment("GOF2_CONVOY_STATION_SCENARIO").is_empty() else "run_progression")

func run_transit_checkpoint() -> void:
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,720)
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3:check(false,"Expected content, bindings and visuals");quit(1);return
	source=load("res://src/content/library.gd").new();definitions=load("res://src/content/resource_bindings.gd").new();catalogue=load("res://src/content/catalogues.gd").new();visual=Visuals.new()
	if not source.open(args[0]) or not definitions.open(args[1],source.manifest) or not catalogue.open(source) or not source.select_language("gb") or not visual.open(args[2],source.manifest):check(false,source.error+definitions.error+catalogue.error+visual.error);quit(1);return
	var checkpoint:=TransitCheckpoint.new()
	var station: RefCounted=checkpoint.open(OS.get_environment("GOF2_CONVOY_STATION_SCENARIO"),definitions)
	if station==null:check(false,checkpoint.error);quit(1);return
	app=Host.new();root.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.set_context(source,definitions,visual);app.set_process(false);app._focused=true
	var session:=StationSession.new();app.viewport.add_child(session);session._world=station
	if not session._build_scene(source,definitions,visual,catalogue,now_us,42) or not app.station_panel.configure_station_return(source,definitions,visual,13) or not session.activate():check(false,session.error+app.station_panel.error)
	else:
		app.session=session;app.present_session()
		await after_four_successes()
	app.free();print("Application transit checkpoint: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func after_four_successes() -> void:
	if failures:return
	var capture_path:=OS.get_environment("GOF2_CAPTURE_CONVOY_STATION")
	if not capture_path.is_empty():
		var checkpoint:=TransitCheckpoint.new()
		if not checkpoint.capture(capture_path,app.session.station_owner(),definitions):check(false,checkpoint.error);return
	check(Transit.available(definitions.mido_travel),"The transit declaration is missing")
	var text_shift: int=14 if catalogue.tables.ships.size()==64 else 0
	var before: Dictionary=app.session.snapshot()
	check(before.campaign_cursor==13 and before.loadout.station_id!=79 and before.dialogue.text_id==1792+text_shift,"Four distant jobs did not open the original story in the application")
	check(before.contracts.credits==7850 and before.completed_side_missions==4,"The continuous career changed its earned balance")
	check(not app.request_departure(),"The unacknowledged story allowed departure")
	for station in [75,76,77,78,79]:
		check(TravelRules.navigation_stations(definitions.mido_travel,14,station).size()==5,"Transit lost a Mido destination")
		check(Transit.selected(definitions.mido_travel,14,station,Transit.mission(definitions.mido_travel))==(station==79),"Convoy ignored its original target")
	check(OrdinaryRules.briefing(definitions,14,true).events.is_empty() and OrdinaryRules.briefing(definitions,14).events.size()==1,"Transit borrowed the convoy's acknowledged instruction")
	app.session.rebase_time(now_us)
	for tick in 11:
		if not application_step():return
	for id in [1792+text_shift,1793+text_shift]:
		check(app.session.snapshot().dialogue.text_id==id,"Story acknowledgement skipped a line")
		app.station_navigation("next")
		if app._transition_failed:check(false,app.status.text);return
	var acknowledged: Dictionary=app.session.snapshot()
	check(acknowledged.campaign_cursor==14 and acknowledged.contracts.campaign_cursor==14 and acknowledged.phase=="convoy_departure_required","Application failed to retain the actual story cursor")
	check(acknowledged.contracts.credits==before.contracts.credits and acknowledged.cargo==before.cargo,"Acknowledging the story paid or discarded inventory")
	check(app.session.audio.snapshot().history.map(func(row):return row.source_id)==[222,223],"The story omitted its original voices")
	if failures:return
	if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
	if not await release_application_flight():return
	check(app.session.snapshot().campaign_cursor==14 and not app.session.snapshot().has("convoy_capture"),"Departure spawned the convoy at the fourth-job station")
	check(app.session.snapshot().contracts.credits==before.contracts.credits and app.session.snapshot().mission==acknowledged.mission,"Ordinary transit lost the story or wallet")
	# Dock at another station while retaining14. No story replay or reset to13.
	if not await travel_application(76) or not await dock_application():return
	check(app.session.snapshot().campaign_cursor==14 and not app.session.snapshot().dialogue.visible and app.session.snapshot().phase=="convoy_departure_required","An intermediate dock restarted the story")
	if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
	if not await release_application_flight():return
	if not await travel_to_convoy():return
	var arrived: Dictionary=app.session.snapshot()
	check(arrived.campaign_cursor==14 and arrived.location.station_id==79 and arrived.has("convoy_capture") and arrived.actors.size()==7,"Kernstal arrival did not select the authored convoy")
	check(app.current_locations().snapshot().current_station_id==79,"The application lost its location cache entering the convoy")
	if failures:return
	var lethal:=false;var death_checked:=false;var seen_modal:=false;var disabled:=false
	var previous_phase:=-1;var phase_ticks:=0
	for tick in 1000:
		var frame: RefCounted=app.session.flight_owner()
		if frame.dialogue_visible():
			seen_modal=true
			check(frame.snapshot().dialogue.text_id==1794+text_shift,"The convoy opened an unrelated instruction")
			await capture_view("application-convoy-instruction")
			if not app.session.navigate("next"):check(false,app.session.error);return
			frame=app.session.flight_owner()
		if frame.snapshot().world_elapsed_ms>=10000 and not death_checked:
			death_checked=true
			if not verify_lethal_branch(frame,app.session.scene):return
		if frame.snapshot().world_elapsed_ms>=20000 and not lethal:
			# Same disclosed lethal actor contact as the component replay.
			var combat: RefCounted=frame._encounter._combat
			if not combat.begin_contact_pass(frame.snapshot().random_state,true) or combat.normal_hit(1,combat.snapshot().actors[1].vitals.hull,true).is_empty():check(false,combat.error);return
			if not app.session._commit(frame,false):check(false,app.session.error);return
			lethal=true
		if not application_step():return
		disabled=disabled or app.session.flight_owner().convoy_input_blocked()
		var phase:=int(app.session.snapshot().convoy_capture.phase)
		phase_ticks=phase_ticks+1 if phase==previous_phase else 0
		previous_phase=phase
		if phase_ticks==2:await capture_view("application-convoy-phase-%d"%phase)
		if app.session.status=="convoy_arrival_transition_required":break
		if tick%100==0:await process_frame
	check(seen_modal and disabled and death_checked and app.session.status=="convoy_arrival_transition_required","Application capture did not reach its station boundary")
	if failures:return
	var captured: Dictionary=app.session.snapshot()
	if not app.enter_station(now_us,42,1789423200):check(false,app.status.text);return
	check(app.session.snapshot().campaign_cursor==15 and app.session.snapshot().loadout.station_id==98 and app.session.snapshot().loadout.system_id==19,"Application failed to enter Alioth")
	check(app.current_locations().snapshot().current_station_id==98 and app.session.snapshot().contracts.credits==before.contracts.credits,"Alioth lost the actual wallet or generated cache")
	check(app.session.snapshot().cargo==captured.cargo,"Alioth replaced captured cargo")
	app.session.rebase_time(now_us)
	for tick in 11:
		if not application_step():return
	await capture_view("application-alioth-desktop")
	root.size=Vector2i(960,540);app.set_mobile_layout(true);TouchInput.set_preference(app,true)
	app.present_session()
	await capture_view("application-alioth-phone-landscape")
	root.size=Vector2i(1280,720);app.set_mobile_layout(false);app.set_touch_controls(false)
	app.present_session()
	for event in definitions.mido_travel.alioth_arrival.events:
		check(app.session.snapshot().campaign_cursor==15 and app.session.snapshot().dialogue.text_id==int(event.text_id),"Alioth skipped an original station line")
		app.station_navigation("next")
		if app._transition_failed:check(false,app.status.text);return
	check(app.session.snapshot().campaign_cursor==16 and app.session.snapshot().contracts.campaign_cursor==16 and app.session.snapshot().contracts.completed_side_missions==4,"Application did not finish the earned Alioth conversation")
	if not load("res://src/content/alioth_return_definitions.gd").available(definitions):
		check(not app.request_departure(),"Application invented the unfinished next encounter")
	else:check(FlightSession.supported(definitions,16),"The completed Alioth flight is unavailable")
	print("Application earned13 -> transit14 -> Kernstal convoy -> Alioth15 -> acknowledged16; retained ",app.session.snapshot().contracts.credits," credits")

func travel_to_convoy() -> bool:
	if not await acquire_application_planet(79):return false
	var previous: Dictionary=app.session.snapshot()
	if not app.enter_local_arrival(now_us,4096,1789100000):check(false,app.status.text);return false
	app.session.rebase_time(now_us)
	print("Application local arrival selected the Kernstal convoy")
	check(app.session.flight_owner().convoy_career_owner().snapshot().credits==previous.contracts.credits,"Convoy construction replaced the retained career")
	return failures==0
