extends "res://tests/mido_station_departure.gd"
## Connected application journey after the earned training prerequisite. The
## inherited training combat/contact fixtures disclose their direct placements.
## Local travel, arrival and docking then run through the actual player controls.
var application_journey_verified:=false

func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected explicit Mac content, bindings, visuals and optional captures")
	if args.size() in [3,4]:verify(args.slice(0,3))
	if is_instance_valid(training_scene):training_scene.free()
	if is_instance_valid(training_sound):training_sound.free()
	print("Mido application prerequisite: %d checks; %d failures"%[checks,failures])
	if failures==0:await verify_training_application(args)
	check(application_journey_verified,"The application never completed its supported station visits")
	if is_instance_valid(host):host.free()
	print("Mido application: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func after_training_application_reload(args: PackedStringArray):
	if failures>0:return
	var station: Node=host.session;station.rebase_time(now_us)
	var before: Dictionary=station.snapshot()
	check(before.campaign_cursor==9 and before.get("local_conversation",false) and not before.conversation_started,"Training reload did not prepare the local conversation")
	check(not before.dialogue.visible and station.audio.snapshot().history.is_empty(),"Reload exposed or spoke the next mission before its delay")
	key(KEY_ENTER)
	check(station.snapshot()==before and host._launch_packet.is_empty(),"Early station input skipped the conversation delay")
	check(station.set_pause("user",true,now_us),station.error)
	if not training_app_step():return
	check(station.snapshot()==before and station.audio.snapshot().history.is_empty(),"Paused station advanced the local dialogue")
	check(station.set_pause("user",false,now_us),station.error)
	for i in 10:
		if not training_app_step():return
	check(station.snapshot().dialogue.text_id==1747 and station.audio.snapshot().history.back().source_id==453,"Post-training narrator did not start with the original text and voice")
	if args.size()==4:await capture(args[3],"mido-app-narrator")
	var index:=0
	for event in bindings.mido_travel.conversations[0].events:
		var state: Dictionary=station.snapshot()
		check(state.campaign_cursor==9 and state.dialogue.index==index and state.dialogue.text_id==int(event.text_id),"Local conversation skipped a required line or completed early")
		check(state.equipment==before.equipment and state.cargo==before.cargo and state.progress==before.progress,"Local conversation exchanged equipment or granted progress before final acknowledgement")
		check(station.audio.snapshot().line==index,"Local speech lost its acknowledged dialogue position")
		if event.voice_event_id>=0:check(station.audio.snapshot().history.back().source_id==int(event.voice_event_id),"Local conversation used another original recording")
		else:check(station.audio._player==null,"Silent local instruction replayed the preceding voice")
		if index==3:
			key(KEY_LEFT);check(station.snapshot().dialogue.text_id==1749,"Previous-line input failed in the new conversation")
			key(KEY_ENTER);check(station.snapshot().dialogue.text_id==1750,"Returning to the current line changed its index")
		if index==10 and args.size()==4:await capture(args[3],"mido-app-travel-instruction")
		key(KEY_ENTER);index+=1
	var ready: Dictionary=station.snapshot()
	check(ready.campaign_cursor==10 and ready.phase=="local_departure_required" and ready.local_conversation_acknowledged,"Final station acknowledgement failed to release local departure")
	check(ready.loadout.equipment_ids==[22,86,81,55] and ready.cargo==before.cargo and ready.reward_credits==0 and ready.progress.rank_score==before.progress.rank_score+1,"Local departure changed the earned inventory, reward or campaign credit")
	check(host._launch_button.visible and not host._pause_button.visible,"Ready local station omitted its launch control or exposed desktop touch controls")
	key(KEY_ENTER)
	check(not host._launch_packet.is_empty() and host._launch_dialog.visible and station.snapshot()==ready,"Station keyboard launch skipped its confirmation")
	host.cancel_departure()
	check(not host.enter_first_flight(now_us) and station.snapshot()==ready,"Cancelled local departure changed the accepted station")
	var textures: Dictionary=visuals.textures;visuals.textures={}
	check(host.request_departure() and not host.enter_first_flight(now_us,1789100000,1789100000) and host.session==station and station.snapshot()==ready,"Failed local launch discarded the station or applied its exchange twice")
	visuals.textures=textures
	check(host.retry_transition() and host.enter_first_flight(now_us,1789100000,1789100000),host.status.text)
	if not host.session is TrainingSession:return
	var flight: Node=host.session;flight.rebase_time(now_us)
	check(not is_instance_valid(station) and flight.snapshot().equipment==ready.equipment and flight.snapshot().progress==ready.progress,"Accepted local departure lost the actual station state")
	await verify_local_session_journey(args,flight)
	if failures>0 or not host.session is Station:return
	var finished: Dictionary=host.session.snapshot()
	application_journey_verified=finished.campaign_cursor==11 and finished.get("local_visit_acknowledged",false)
	check(application_journey_verified,"Kernstal did not retain the earned next mission")
	if bindings.mido_travel.get("continuation",{}).is_empty():
		check(not host.request_departure(),"An earlier pack enabled Yrdal")
	else:
		application_journey_verified=false
		await verify_yrdal_application(args)
	print("Mido application station visits: %d checks; %d failures"%[checks,failures])

func verify_yrdal_application(args: PackedStringArray,cursor: int=11):
	var trip: Dictionary=bindings.mido_travel.continuation if cursor==11 else bindings.mido_travel.return_visit
	var prefix:="yrdal" if cursor==11 else "kernstal-return"
	var station: Node=host.session
	var before: Dictionary=station.snapshot()
	check(before.campaign_cursor==cursor and before.mission.station_id==int(trip.station_id),"The continuation lost the earned Local visit objective")
	if not host.request_departure() or not host.enter_first_flight(now_us,1789100000,1789100000):check(false,host.status.text);return
	var departure: Node=host.session;departure.rebase_time(now_us);host.present_session()
	check(departure.snapshot().campaign_cursor==cursor and departure.snapshot().location.station_id==int(trip.from_station_id),"The next launch selected another mission or location")
	check(departure.snapshot().progress==before.progress and departure.snapshot().equipment==before.equipment,"The next launch changed earned career or inventory")
	for i in 71:
		if not training_app_step():return
	check(departure.can_control() and not departure.scene.radio.visible and departure.flight_audio!=null,"The continuation failed to release its flight and sound")
	var initial: Dictionary=departure.snapshot()
	check(departure.scene.encounter.actors.size()==initial.encounter.combat.actors.size(),"Rendered mixed traffic lost actors")
	for actor in initial.encounter.combat.actors:
		var node: Dictionary=departure.scene.encounter.actors[actor.actor_id]
		if actor.get("population_group")=="freighter":
			check(node.freighter and node.hull.get_meta("source_ship_id")==15 and node.hull.levels.size()==2,"Freighter lost its original hull or alternate")
		else:check(node.engine!=null,"Ordinary traffic lost its original engine")
	if args.size()==4:await capture(args[3],prefix+"-departure-traffic")
	# This detached branch uses explicit lethal damage to exercise the new
	# player's ordinary death/fade/continue owner without altering the journey.
	var armed: Array=initial.encounter.weapons.actors.filter(func(row):return not row.get("projectiles",{}).is_empty())
	if not armed.is_empty():verify_local_game_over(departure.flight_owner(),armed[0].projectiles.weapon)
	key(KEY_M)
	check(departure.map_active() and host.map_panel.visible,"The continuation lost its local map")
	var map: Dictionary=host.map_panel.snapshot()
	check(map.station_id==int(trip.from_station_id) and map.rows.filter(func(row):return row.supported).map(func(row):return row.station_id)==[int(trip.station_id)],"The map enabled an unsupported destination or omitted Local visit")
	host.map_panel.select_station(int(trip.station_id));host.map_panel.request_confirmation()
	check(host.map_panel.snapshot().confirmation_visible,"Local visit selection skipped its course confirmation")
	if args.size()==4:await capture(args[3],prefix+"-map-course")
	if not host.confirm_map_planet(int(trip.station_id),now_us):check(false,host.status.text);return
	departure.rebase_time(now_us)
	for i in 2000:
		if departure.status=="local_arrival_transition_required":break
		if not training_app_step():return
	if departure.status!="local_arrival_transition_required":check(false,"Rendered planet guidance never reached Local visit: "+departure.status);return
	var travelling: Dictionary=departure.snapshot()
	check(travelling.progress==before.progress and travelling.cargo==before.cargo,"Travel completed the mission early")
	var sounds:=travel_audio_history(departure)
	check(sounds.size()==2 and sounds.all(func(event):return event.destination_station_id==int(trip.station_id)),"Local visit travel sounds lost the destination")
	host._process(0)
	if host._transition_failed or not host.session is TrainingSession:check(false,host.status.text);return
	var arrival: Node=host.session;arrival.rebase_time(now_us)
	check(arrival.snapshot().location.station_id==int(trip.station_id) and arrival.scene.encounter.actors.is_empty(),"Local visit arrived in another scene or retained departure traffic")
	check(arrival.snapshot().station_exterior.station_id==int(trip.station_id) and arrival.snapshot().progress==before.progress,"Local visit used another exterior or changed progress")
	host.present_session()
	if args.size()==4:await capture(args[3],prefix+"-entry")
	for i in 71:
		if not training_app_step():return
	check(arrival.can_control() and arrival.snapshot().player.damage_allowed,"Local visit arrival failed to release input and damage")
	if args.size()==4:await capture(args[3],prefix+"-flight")
	if not arrival.action("autopilot"):check(false,arrival.error);return
	for i in 2000:
		if arrival.status=="station_transition_required":break
		if not training_app_step():return
	if arrival.status!="station_transition_required":check(false,"Rendered Local visit guidance never docked");return
	var docked: Dictionary=arrival.snapshot()
	if not host.enter_station(now_us,42):check(false,host.status.text);return
	var visit: Node=host.session;visit.rebase_time(now_us)
	check(visit.snapshot().campaign_cursor==cursor and visit.snapshot().loadout.station_id==int(trip.station_id),"Local visit docking selected another station conversation")
	for i in 10:
		if not training_app_step():return
	if not visit.snapshot().dialogue.visible:check(false,"Local visit conversation did not start");return
	if args.size()==4:await capture(args[3],prefix+"-conversation-start")
	var index:=0
	for event in trip.events:
		var current: Dictionary=visit.snapshot()
		check(current.dialogue.text_id==int(event.text_id) and current.dialogue.speaker_id==int(event.speaker_id),"Local visit used another original dialogue or portrait")
		check(current.campaign_cursor==cursor and current.progress==before.progress and current.cargo==docked.cargo,"An unfinished Local visit line advanced progress or removed cargo")
		if event.voice_event_id>=0:check(visit.audio.snapshot().history.back().source_id==int(event.voice_event_id),"The visit used another voice recording")
		else:check(visit.audio._player==null,"The silent instruction retained a voice player")
		if index==2 and args.size()==4:await capture(args[3],prefix+"-conversation-contact")
		key(KEY_ENTER);index+=1
	var finished: Dictionary=visit.snapshot()
	application_journey_verified=finished.campaign_cursor==int(trip.next_cursor) and finished.get("local_visit_acknowledged",false)
	check(application_journey_verified and finished.mission.station_id==int(trip.next_station_id) and finished.mission.kind==int(trip.next_kind) and finished.reward_credits==0,"Local visit lost the authored return mission or awarded credits")
	check(finished.progress.rank_score==before.progress.rank_score+1 and finished.progress.reputation==before.progress.reputation and finished.equipment==docked.equipment,"Local visit acknowledgement changed inventory or reputation")
	if cursor==11 and not bindings.mido_travel.get("return_visit",{}).is_empty():
		application_journey_verified=false
		await verify_yrdal_application(args,12)
	else:
		var contracts_supported: bool=cursor==12 and TrainingSession.supported(bindings,13)
		check(host.request_departure()==contracts_supported and host._launch_button.visible==contracts_supported,"The next departure disagrees with its supported contract session")
		host.cancel_departure()
		if cursor==12:
			check(finished.mission.completed_contract_target==4 and finished.completed_side_missions==0 and finished.phase=="contracts_required","The application bypassed the side-mission requirement")
			if bindings.early_contracts.has("station_generation"):
				var locations: Dictionary=host.locations_snapshot()
				check(locations.locations.map(func(row):return row.station_id)==[78,79,76],"The actual local journey changed the source FIFO order")
				check(locations.locations.map(func(row):return row.population.context.campaign_cursor)==[1,10,11],"Contacts were generated at docking/acknowledgement instead of their actual location selections")
				check(finished.contracts.population==locations.locations[1].population and finished.contracts.population.context.campaign_cursor==10,"The acknowledged lounge lost its original Kernstal population")
				check(finished.contracts.credits==0 and finished.contracts.completed_side_missions==0 and finished.contracts.mission.is_empty(),"Opening retained lounge contacts invented a job, payment or completion")
			if args.size()==4:await capture(args[3],prefix+"-contracts-required")
			await after_lounge_application(args)
	print("Mido application visit%d: %d checks; %d failures"%[cursor,checks,failures])

func after_lounge_application(_args: PackedStringArray):pass
