extends "res://tests/free_departure.gd"
## The earned ordinary departure uses actual flight input and station guidance.
## Actual docking retains the ordinary station and permits another departure.
const Frame=preload("res://src/simulation/first_flight_frame.gd")
const Station=preload("res://src/simulation/station_entry.gd")

func verify_encounter(library: RefCounted,bindings: RefCounted,cat: RefCounted,construction: RefCounted) -> void:
	super.verify_encounter(library,bindings,cat,construction)
	if failures:return
	var flight:=Frame.new()
	if not flight.configure(bindings,cat,library,construction,"E",.5):check(false,flight.error);return
	var initial: Dictionary=flight.snapshot();var entry: Dictionary=construction.snapshot()
	check(initial.campaign_cursor==18 and initial.station_return_supported and initial.station_exterior.station_id==98,"Ordinary flight lacks its actual Alioth exterior and docking")
	check(initial.player_destruction.phase=="ready" and initial.has("npc_scanner") and initial.has("radio"),"Ordinary flight omitted death, acquisition or radio owners")
	check(initial.contracts.flight.ordinary_context.station_id==98 and initial.contract_result.is_empty(),"The ordinary world lost its retained career or activated a contract result")
	check(not Station.new().configure_return(bindings,cat,library,flight),"Ordinary station entry accepted a flight without docking")
	for actor in initial.actors:
		var outbound: bool=actor.get("population_group")=="travel" and actor.has("travel_cycle")
		check(flight._scanner.valid_mode(actor.actor_id,6)==outbound and flight._scanner.fork_for_frame().valid_mode(actor.actor_id,6)==outbound,"Scanner lost the travelling ship's declared departure mode")
		for mode in [-1,6.0,7]:check(not flight._scanner.valid_mode(actor.actor_id,mode),"Scanner accepted an undeclared or noninteger actor mode")
	check(flight.evaluate(100,Vector2.ONE,0.0,true).snapshot()==initial,"Pause changed the ordinary departure")
	check(flight.start_station_autopilot()==null and flight.snapshot()==initial,"Protected entry enabled docking input")
	for tick in 70:
		var next: RefCounted=flight.evaluate(100,Vector2.ONE,0.0)
		if next==null:check(false,flight.error);return
		flight=next
	var launch: Dictionary=flight.snapshot()
	check(not launch.entry_released and not launch.player.damage_allowed and launch.entry_elapsed_ms==7000,"Ordinary entry released at the exact7000ms boundary")
	check(launch.player_pose.origin.distance_to(initial.player_pose.origin+initial.player_pose.basis.z*14000)<.1 and launch.angular_units==Vector2.ZERO,"Ordinary entry changed its source cruise or accepted early steering")
	var released: RefCounted=flight.evaluate(1,Vector2(0,1),0.0)
	if released==null:check(false,flight.error);return
	flight=released
	var state: Dictionary=flight.snapshot()
	check(state.entry_released and state.phase=="flight" and not state.dialogue.visible and state.player.damage_allowed,"Ordinary release invented a mission briefing or retained launch protection")
	check(state.camera_view.mode=="follow" and state.angular_units.y>0 and state.scenery_collision_enabled,"Ordinary release lost camera, steering or scenery contacts")
	var shots:=0
	for tick in 12:
		var next: RefCounted=flight.evaluate(100,Vector2(.1,-.2),.5,false,Vector2i.ZERO,Vector2.ZERO,true)
		if next==null:check(false,flight.error);return
		flight=next
		for gun in flight.snapshot().encounter.primary_fire.get("weapons",[]):
			if gun.result.get("fired",false):shots+=1
	check(shots>0 and flight.snapshot().player_pose.basis!=state.player_pose.basis,"Released ordinary input did not steer and fire the installed primary")
	var dock: RefCounted=flight.start_station_autopilot()
	if dock==null:check(false,flight.error);return
	flight=dock
	for tick in 1200:
		if flight.snapshot().get("boundary","")=="station_transition_required":break
		var next: RefCounted=flight.evaluate(100)
		if next==null:check(false,flight.error);return
		flight=next
		if flight.death_active():check(false,"The earned departure fixture died during ordinary station guidance");return
	state=flight.snapshot()
	var packet: Dictionary=flight.prepare_station()
	if packet.is_empty():check(false,flight.error);return
	check(state.boundary=="station_transition_required" and packet.docking.station_id==98 and packet.campaign_cursor==18,"Ordinary guidance failed to produce actual station contact")
	check(packet.mission==entry.departure.mission and packet.cargo==entry.departure.cargo,"Ordinary docking changed cargo or the pending Suttnar story")
	check(packet.contracts.credits==7850 and packet.contracts.completed_side_missions==4 and not packet.contracts.has("flight") and packet.contracts.pending_result.is_empty(),"Ordinary docking paid an unearned reward or retained a live flight ledger")
	check(packet.progress==packet.contracts.progress and packet.equipment.ship_affiliation==0 and packet.equipment.loadout==entry.departure.loadout,"Docking lost career, affiliation or equipped loadout")
	check(flight.evaluate(100,Vector2.ONE).snapshot()==state and construction.snapshot()==entry,"Completed docking changed its retained flight or original construction")
	var station:=Station.new()
	if not station.configure_return(bindings,cat,library,flight):check(false,station.error);return
	var docked: Dictionary=station.snapshot()
	check(docked.phase=="free_play_required" and docked.alioth_return_acknowledged and not docked.dialogue.visible and docked.dialogue.count==0,"Ordinary station entry replayed the completed conversation")
	check(docked.contracts==packet.contracts and docked.progress==packet.progress and docked.cargo==packet.cargo and docked.player_cache==packet.player_cache,"Ordinary return changed its accepted career, cargo or current vitals")
	check(not station.acknowledge() and station.snapshot()==docked,"An ordinary return granted another dialogue acknowledgement")
	var departure: Dictionary=station.prepare_departure(bindings,cat)
	check(not departure.is_empty() and departure.contracts==docked.contracts and departure.mission==docked.mission and station.snapshot()==docked,"Returned station cannot prepare another ordinary flight without mutating its career")
	var repeated:=Station.new()
	check(repeated.configure_return(bindings,cat,library,flight) and repeated.snapshot()==docked,"Re-preparing station entry changed the accepted docking result")
	print("Earned18 frame: ",shots," primary shots; actual docking at ",state.world_elapsed_ms,"ms; ",packet.docking.position)
