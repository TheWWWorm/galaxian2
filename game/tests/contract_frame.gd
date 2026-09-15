extends "res://tests/contract_world.gd"
## Uses the inherited earned opening and explicit offer/acquisition fixtures.
## The live frame owns motion, contacts, clock, career, targeting and camera.
const LiveFrame=preload("res://src/simulation/first_flight_frame.gd")
var live_frames:=0
var result_cases:={}
var travel_verified:=false
var result_count:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	check(worlds_verified==30 and live_frames==2550 and result_count==4 and travel_verified,"The live flight check did not finish all worlds, results and the retained Courier journey")
	print("Contract frames: %d checks; %d worlds; %d frames; %d results; %d failures"%[checks,worlds_verified,live_frames,result_count,failures])
	quit(1 if failures else 0)

func verify_world(bindings: RefCounted,cat: RefCounted,library: RefCounted,construction: RefCounted) -> void:
	var frame:=LiveFrame.new()
	if not frame.configure(bindings,cat,library,construction,"D",1.0):check(false,frame.error);return
	var original: Dictionary=construction.snapshot()
	var initial: Dictionary=frame.snapshot()
	check(initial.campaign_cursor==13 and initial.contracts.progress==initial.progress,"The live flight lost its retained contract career")
	check(initial.location.station_id==original.location.station_id and initial.mission==original.departure.mission,"The frame substituted a story mission or location")
	for tick in 85:
		var next: RefCounted=frame.evaluate(150,Vector2(.05,-.025),.5,false,Vector2i(1280,720),Vector2.ZERO,true)
		if next==null:check(false,"Contract frame "+str(tick)+": "+frame.error);return
		frame=next;live_frames+=1
		if frame.contract_result_pending():break
	var state: Dictionary=frame.snapshot()
	check(state.player_pose!=initial.player_pose and state.world_elapsed_ms>0,"The live contract frame did not move the ship")
	check(state.contracts.progress==state.progress and state.contracts.credits==initial.contracts.credits,"The frame split career state or paid an unacknowledged result")
	var paused: RefCounted=frame.evaluate(150,Vector2.ONE,1.0,true)
	check(paused!=null and paused.snapshot()==state,"Pause advanced the contract flight")
	check(construction.snapshot()==original,"A live frame mutated its retained preparation")
	var mission: Dictionary=original.scenery.world_initialization.contract_context.mission
	if mission.get("kind") in [4,7,12] and not result_cases.has(mission.kind):
		verify_result(bindings,cat,library,construction,true)
		if mission.kind==12:verify_result(bindings,cat,library,construction,false)
		if failures:return
		result_cases[mission.kind]=true
	if not travel_verified and initial.location.station_id==79 and initial.contracts.mission.get("kind")==0:
		verify_pending_travel(bindings,cat,library,construction)
		if failures:return
	if not frame.contract_result_pending() and not frame.death_active():
		for station_id in [75,76,77,78,79]:
			if station_id==state.location.station_id:continue
			var course: RefCounted=frame.select_planet(station_id)
			check(course!=null,"An ordinary contract flight cannot select a Mido destination: "+frame.error)
			if course==null:return
	worlds_verified+=1
	print("Contract frame world %d: station %d, active kind %d; %d accepted frames"%[worlds_verified,state.location.station_id,mission.get("kind",-1),live_frames])

func verify_result(bindings: RefCounted,cat: RefCounted,library: RefCounted,construction: RefCounted,success: bool) -> void:
	var frame:=LiveFrame.new()
	if not frame.configure(bindings,cat,library,construction,"D",1.0):check(false,frame.error);return
	frame=release(frame)
	if frame==null:return
	var kind: int=frame.snapshot().contracts.mission.kind
	# Explicit placements activate the actual dormant ships. Explicit lethal
	# hits isolate scene result order; this is not a manual-combat playthrough.
	if kind!=7:
		for actor in frame.snapshot().encounter.combat.actors:
			if kind==12 and actor.actor_id==0:continue
			frame._pose.origin=actor.pose.origin+Vector3(0,0,20000)
			for tick in 2:
				var active: RefCounted=frame.evaluate(0)
				if active==null:check(false,frame.error);return
				frame=active
	var before: Dictionary=frame.snapshot()
	var combat: RefCounted=frame._encounter._combat
	if not combat.begin_contact_pass(before.random_state,true):check(false,combat.error);return
	for actor in combat.snapshot().actors:
		if kind==12 and actor.actor_id==0:continue
		var hit: Dictionary=combat.normal_hit(actor.actor_id,actor.vitals.hull,not success)
		if hit.is_empty():check(false,combat.error);return
		check(hit.destroyed_now,"The explicit live result fixture did not destroy an active target")
	if failures:return
	var destroyed: RefCounted=frame.evaluate(0)
	if destroyed==null:check(false,frame.error);return
	frame=destroyed
	if kind==7:
		var particles: Dictionary=frame.snapshot().damage_particles.owners.junk.junk_burst
		check(particles.slots.filter(func(slot):return slot.appearance.age_ms==0).size()==mini(frame.snapshot().encounter.combat.actors.size(),int(particles.preset.capacity)),"The live debris pass lost its original manual burst")
		var scanner_class=preload("res://src/simulation/opening_npc_scanner.gd")
		for actor in frame.snapshot().encounter.combat.actors:
			check(scanner_class.selectable(actor)==actor.active,"A dropped Junk container lost its target eligibility")
	for tick in 100:
		if frame.contract_result_pending():break
		var next: RefCounted=frame.evaluate(100)
		if next==null:check(false,frame.error);return
		frame=next
	if not frame.contract_result_pending():check(false,"The live contract outcome never opened its result");return
	var pending: Dictionary=frame.snapshot()
	check(pending.contract_result.completed==success and pending.contract_result.failed==not success,"The live result changed its actual outcome")
	check(pending.contracts.credits==before.contracts.credits and pending.contracts.completed_side_missions==before.contracts.completed_side_missions+(1 if success else 0),"The live result paid before Close or lost completion credit")
	check(pending.progress==pending.contracts.progress and pending.mission==before.mission,"The live result split career state or completed the story")
	var frozen: RefCounted=frame.evaluate(150,Vector2.ONE,1.0,false,Vector2i(1280,720),Vector2.ONE,true)
	check(frozen!=null and frozen.snapshot()==pending,"An open result advanced gameplay, particles, camera or audio serial")
	check(frame.acknowledge_contract_result(pending.contract_result.serial,true)==null and frame.acknowledge_contract_result(pending.contract_result.serial+1)==null and frame.snapshot()==pending,"A paused or stale Close changed the accepted flight")
	var closed: RefCounted=frame.acknowledge_contract_result(pending.contract_result.serial)
	if closed==null:check(false,frame.error);return
	var after: Dictionary=closed.snapshot()
	check(after.contract_result.is_empty() and after.contracts.mission.is_empty() and after.contracts.accepted_contact.is_empty() and after.world_path.is_empty(),"Close retained the completed side slot, accepted contact or shared world path")
	check(after.encounter.combat.actors==pending.encounter.combat.actors and after.encounter.controller.destruction==pending.encounter.controller.destruction and after.random_state==pending.random_state and after.damage_particles==pending.damage_particles,"Close rebuilt actors, destroyed cargo, advanced particles or consumed RNG")
	check(after.player_pose==pending.player_pose and after.station_autopilot==pending.station_autopilot,"Ordinary planet/station guidance was mistaken for a special mission target")
	check(closed.acknowledge_contract_result(pending.contract_result.serial)==null,"The live result paid twice")
	var continued: RefCounted=closed.evaluate(100)
	if continued==null:check(false,closed.error);return
	check(continued.snapshot().world_elapsed_ms>after.world_elapsed_ms and continued.snapshot().contracts.credits==after.contracts.credits,"Flight did not resume with its settled wallet")
	result_count+=1
	print("Contract frame result: kind %d, success %s"%[kind,success])

func verify_pending_travel(bindings: RefCounted,cat: RefCounted,library: RefCounted,construction: RefCounted) -> void:
	var frame:=LiveFrame.new()
	if not frame.configure(bindings,cat,library,construction,"D",1.0):check(false,frame.error);return
	frame=release(frame)
	if frame==null:return
	var before: Dictionary=frame.snapshot()
	var course: RefCounted=frame.select_planet(75)
	if course==null:check(false,frame.error);return
	frame=course
	for tick in 2000:
		if not frame.prepare_local_arrival().is_empty():break
		var next: RefCounted=frame.evaluate(100)
		if next==null:check(false,frame.error);return
		frame=next
	if frame.prepare_local_arrival().is_empty():check(false,"The pending Courier never reached its destination through live planet guidance");return
	var arrived: RefCounted=frame.construct_local_arrival(bindings,cat,4096,1789100000,true,_world_bodies,_world_effects)
	if arrived==null:check(false,frame.error);return
	var career: Dictionary=arrived.contract_owner().snapshot()
	check(not career.has("flight") and career.mission==before.contracts.mission and career.accepted_contact==before.contracts.accepted_contact and career.credits==before.contracts.credits,"Local arrival lost or paid the unfinished Courier")
	var destination:=LiveFrame.new()
	if not destination.configure(bindings,cat,library,arrived,"D",1.0):check(false,destination.error);return
	destination=release(destination)
	if destination==null:return
	var guided: RefCounted=destination.start_station_autopilot()
	if guided==null:check(false,destination.error);return
	for tick in 2000:
		if guided.snapshot().get("boundary")=="station_transition_required":break
		var next: RefCounted=guided.evaluate(100)
		if next==null:check(false,guided.error);return
		guided=next
	var packet: Dictionary=guided.prepare_station()
	if packet.is_empty():check(false,guided.error);return
	check(packet.docking.station_id==75 and packet.contracts==guided.contract_owner().snapshot() and not packet.contracts.has("flight"),"Live docking lost its actual destination or retained a flight ledger")
	check(packet.contracts.mission==before.contracts.mission and packet.contracts.credits==before.contracts.credits and packet.mission==before.mission and packet.cargo==before.cargo,"Docking silently delivered cargo, paid the contract or changed the story")
	travel_verified=true
	print("Contract frame travel: retained Courier, live 79 to 75 guidance and docking")
	after_contract_docking(bindings,cat,library,guided)

func after_contract_docking(_bindings: RefCounted,_cat: RefCounted,_library: RefCounted,_flight: RefCounted) -> void:
	pass
