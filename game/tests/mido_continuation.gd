extends "res://tests/mido_arrival.gd"
## Continues the preceding arrival component through native planet guidance,
## destination construction, docking and explicit original dialogue. The inherited
## starting fixture is disclosed by mido_arrival; this is not a saved campaign.
var continuation_verified:=false

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	check(continuation_verified,"The station visit did not reach the continuation")
	print("Mido continuation: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func after_local_visit(bindings: RefCounted,cat: RefCounted,library: RefCounted,station: RefCounted) -> void:
	if bindings.mido_travel.get("continuation",{}).is_empty():
		check(station.prepare_departure(bindings,cat).is_empty(),"Earlier bindings enabled Yrdal")
		continuation_verified=true;return
	var visit:=verify_visit(bindings,cat,library,station)
	if visit==null:return
	continuation_verified=true
	after_yrdal_visit(bindings,cat,library,visit)

func verify_visit(bindings: RefCounted,cat: RefCounted,library: RefCounted,station: RefCounted) -> RefCounted:
	var before: Dictionary=station.snapshot()
	var cursor:=int(before.campaign_cursor)
	var trip:=Definitions.journey(bindings.mido_travel,cursor)
	if trip.is_empty():check(false,"This test requires a supported next local visit");return null
	var packet: Dictionary=station.prepare_departure(bindings,cat)
	if packet.is_empty():check(false,station.error);return null
	check(packet.campaign_cursor==cursor and packet.loadout.station_id==int(trip.from_station_id) and packet.mission.station_id==int(trip.station_id),"Continuation changed its origin or objective")
	check(packet.progress==before.progress and packet.station_response_flags==before.station_response_flags and packet.equipment==before.equipment,"Departure lost the earned visit state")
	var bodies:=Bodies.new();var effects:=Effects.new()
	if not bodies.configure(library,bindings) or not effects.configure(library,bindings):check(false,bodies.error+effects.error);return null
	var construction:=Construction.new()
	if not construction.prepare(bindings,cat,packet,4096,1789100000,true,bodies,effects,station.equipment_owner()):check(false,construction.error);return null
	check(station.snapshot()==before,"Detached continuation changed the station")
	var world: Dictionary=construction.snapshot()
	check(world.scenery.world_initialization.npc_construction.actors.size()>0,"Local departure lost ordinary traffic")
	var frame:=Frame.new()
	if not frame.configure(bindings,cat,library,construction,"D",1.0):check(false,frame.error);return null
	check(frame.prepare_station().is_empty() and frame.prepare_local_arrival().is_empty(),"New departure completed the visit early")
	frame=release(frame)
	if frame==null:return null
	var start: Dictionary=frame.snapshot()
	check(start.player.damage_allowed and start.entry_released and not start.dialogue.visible,"Continuation failed to release its empty entry briefing")
	check(start.progress==before.progress and start.cargo==before.cargo and start.station_response_flags==before.station_response_flags,"Entry changed progress, cargo or responses")
	var selected: RefCounted=frame.select_planet(int(trip.station_id))
	if selected==null:check(false,frame.error);return null
	frame=selected
	for tick in 2000:
		if not frame.prepare_local_arrival().is_empty():break
		var next: RefCounted=frame.evaluate(100)
		if next==null:check(false,frame.error);return null
		frame=next
	if frame.prepare_local_arrival().is_empty():check(false,"Planet guidance never reached the destination arrival");return null
	var departed: Dictionary=frame.snapshot()
	check(departed.progress==before.progress and departed.mission==packet.mission,"Travel completed or changed the pending mission")
	var arrived: RefCounted=frame.construct_local_arrival(bindings,cat,4096,1789100000,true,bodies,effects)
	if arrived==null:check(false,frame.error);return null
	var destination: Dictionary=arrived.snapshot()
	check(destination.campaign_cursor==cursor and destination.location.station_id==int(trip.station_id) and destination.location.system_id==int(trip.system_id),"Arrival selected another world")
	check(destination.departure.cargo==before.cargo and destination.departure.progress==before.progress,"Arrival changed cargo or career")
	check(Definitions.valid_response_flags(bindings.mido_travel,destination.departure.station_response_flags,cursor,true) and before.station_response_flags.keys().all(func(id):return destination.departure.station_response_flags[id]==before.station_response_flags[id]),"Arrival lost station response history")
	check(destination.scenery.world_initialization.npc_construction.actors.is_empty(),"the destination arrival invented ordinary traffic or a scripted cast")
	var approach:=Frame.new()
	if not approach.configure(bindings,cat,library,arrived,"D",1.0):check(false,approach.error);return null
	approach=release(approach)
	if approach==null:return null
	var guided: RefCounted=approach.start_station_autopilot()
	if guided==null:check(false,approach.error);return null
	for tick in 2000:
		if guided.snapshot().get("boundary")=="station_transition_required":break
		var next: RefCounted=guided.evaluate(100)
		if next==null:check(false,guided.error);return null
		guided=next
	var docked: Dictionary=guided.prepare_station()
	if docked.is_empty():check(false,guided.error);return null
	check(docked.docking.station_id==int(trip.station_id) and docked.campaign_cursor==cursor,"Docking selected another mission")
	var visit:=StationEntry.new()
	if not visit.configure_return(bindings,cat,library,guided):check(false,visit.error);return null
	var entered: Dictionary=visit.snapshot()
	check(entered.dialogue.count==trip.events.size() and entered.dialogue.text_id==int(trip.events[0].text_id),"the destination started another conversation")
	for index in trip.events.size():
		var current: Dictionary=visit.snapshot()
		check(current.dialogue.text_id==int(trip.events[index].text_id) and current.dialogue.speaker_id==int(trip.events[index].speaker_id) and current.campaign_cursor==cursor and current.progress==before.progress,"An unfinished the destination line changed progress")
		check(visit.prepare_departure(bindings,cat).is_empty(),"the destination launched during its conversation")
		if not visit.acknowledge():check(false,visit.error);return null
	var finished: Dictionary=visit.snapshot()
	var expected_mission:={"kind":int(trip.next_kind),"station_id":int(trip.next_station_id),"reward":0,"bonus":0,"source_parameter":0}
	if trip.has("contract_gate"):expected_mission.completed_contract_target=int(trip.contract_gate.initial_completed_count)+int(trip.contract_gate.additional_completions)
	check(finished.campaign_cursor==int(trip.next_cursor) and finished.mission==expected_mission,"the destination lost the authored next visit")
	check(finished.progress.rank_score==before.progress.rank_score+1 and finished.progress.player_kills==before.progress.player_kills and finished.progress.pirate_kills==before.progress.pirate_kills and finished.progress.reputation==before.progress.reputation,"the destination granted unearned kills or reputation")
	check(finished.cargo==entered.cargo and finished.equipment==entered.equipment and finished.reward_credits==0 and finished.station_response_flags==entered.station_response_flags,"the destination acknowledgement changed inventory or station history")
	check(not visit.acknowledge() and visit.snapshot()==finished,"The conversation completed twice")
	return visit

func after_yrdal_visit(bindings: RefCounted,cat: RefCounted,_library: RefCounted,visit: RefCounted) -> void:
	var packet: Dictionary=visit.prepare_departure(bindings,cat)
	check(packet.is_empty()==bindings.mido_travel.get("return_visit",{}).is_empty(),"The following mission ignored its content capability")

func release(frame: RefCounted) -> RefCounted:
	for tick in 70:
		var next: RefCounted=frame.evaluate(100)
		if next==null:check(false,frame.error);return null
		frame=next
	check(not frame.snapshot().entry_released,"Entry released before 7001 milliseconds")
	var released: RefCounted=frame.evaluate(1)
	if released==null:check(false,frame.error)
	return released
