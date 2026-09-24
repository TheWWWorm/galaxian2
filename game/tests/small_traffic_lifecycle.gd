extends "res://tests/mido_ambient_combat.gd"
## Original generated destinations and earned equipment fixture. World clocks,
## player target, selected-actor passes and cargo RNG inputs are explicit here;
## the check does not imply an integrated Kernstal departure or death recycling.
const Guide=preload("res://src/simulation/opening_npc_guidance.gd")
const Motion=preload("res://src/simulation/npc_flight.gd")
const LaunchClock=preload("res://src/simulation/traffic_launch_clock.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
var travel_cases:=0
var flight_cases:=0
var supported_lifecycle:=false

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	if supported_lifecycle and not failures:check(travel_cases==3 and flight_cases==3,"The generated travel vectors did not exercise the complete flight cycle")
	print("Small traffic lifecycle: %d checks; %d failures; %d launch cases; %d flight cases"%[checks,failures,travel_cases,flight_cases])
	quit(1 if failures else 0)

func verify_population(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,construction: RefCounted) -> void:
	super.verify_population(bindings,catalogues,equipment,construction)
	if failures:return
	if bindings.ambient_lifecycle.is_empty():
		check(not LaunchClock.new().configure(bindings,construction,0),"Old pack acquired traffic launch control");return
	supported_lifecycle=true
	var group:=fresh(bindings,catalogues,equipment,construction)
	if group==null:return
	var initial: Dictionary=construction.snapshot()
	var clock:=LaunchClock.new()
	check(clock.configure(bindings,construction,0),clock.error)
	var before:=clock.snapshot()
	for invalid in [-1,751 if not bindings.fast_forward.is_empty() else 151,1.5,true]:
		check(clock.advance(invalid,group.snapshot()).is_empty() and clock.snapshot()==before,"Invalid clock duration advanced station traffic")
	var malformed: Dictionary=group.snapshot();malformed.actors[-1].binding_id="0".repeat(64)
	check(clock.advance(100,malformed).is_empty() and clock.snapshot()==before,"A foreign later actor partly advanced the launch clock")
	var chosen:=-1
	for actor in initial.actors:
		if actor.population_group=="travel":chosen=int(actor.actor_id);break
	if chosen<0:
		check(clock.configure(bindings,construction,10000) and clock.advance(1,group.snapshot()).actor_id==-1,"A launch check invented a travel actor")
		return
	travel_cases+=1
	var guide:=Guide.new();var flight:=Motion.new()
	check(guide.configure_ambient(bindings,catalogues,construction,chosen,0,0.5),guide.error)
	check(flight.configure(bindings,group.snapshot().actors[chosen].body_pose),flight.error)
	var target:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"ship_id":0,
		"pose":Transform3D(Basis.IDENTITY,Vector3(2000000,0,0)),"active":true,"hull":95,
		"special_flight":false,"targeting_blocked":false,"alternate_position":null}
	var random:={"state":98765}
	var state: Dictionary=group.snapshot().actors[chosen]
	check(state.actor_mode==4 and not state.active and state.vitals.hull==64,"The travel pool started as an active fighter")
	check(not group.collision_context(chosen).eligible and not damage(group,chosen,100).accepted,"Parked traffic received a hit")
	for delta in [150,150,150,150,150,150,150,150,150,150]:
		var waiting:=step(guide,flight,group,chosen,delta,target,random)
		if waiting.is_empty():return
		check(waiting.traffic_waiting and waiting.random_state==random and flight.snapshot().root_pose==initial.actors[chosen].body_pose,"Parked actor moved, fired or consumed selection RNG")
		clock.advance(delta,group.snapshot())
	# The same source clock can resume from its retained value. Boundary inputs
	# here avoid replaying 10 seconds for every generated population vector.
	check(clock.configure(bindings,construction,10000),clock.error)
	check(clock.advance(0,group.snapshot()).actor_id==-1,"Exactly ten seconds launched a ship")
	var launched:=clock.advance(1,group.snapshot())
	check(launched.actor_id==chosen and launched.checked and launched.elapsed_ms==0,"Source launch failed to choose the first inactive travel slot")
	var cargo: Dictionary=construction.sample_relaunch_cargo(random)
	check(cargo.cargo==[{"item_id":100,"quantity":5}] and cargo.random_state.state==235406769951317,"Launch cargo changed the independent original-catalogue vector")
	var old_guide:=guide.snapshot();var old_flight:=flight.snapshot()
	check(group.relaunch_ambient(chosen,bindings),group.error)
	state=group.snapshot().actors[chosen]
	check(guide.relaunch_ambient(state) and flight.apply_scripted_pose(state.body_pose),guide.error+flight.error)
	check(state.body_pose.origin==Vector3.ZERO and state.body_pose.basis==old_flight.root_pose.basis and state.active and state.actor_mode==1 and state.travel_cycle==1,"Traffic launch moved its source origin, changed axes or lost activity")
	check(guide.snapshot().selection_elapsed_ms==old_guide.selection_elapsed_ms and guide.snapshot().boost_elapsed_ms==old_guide.boost_elapsed_ms and guide.snapshot().route.index==0,"Launch reset retained clocks or lost the original destination")
	check(not group.relaunch_ambient(chosen,bindings),"An already active ship launched twice")
	check(clock.configure(bindings,construction,10000) and clock.advance(1,group.snapshot()).actor_id==-1,"An active ship occupied another launch request")
	check(construction.snapshot()==initial,"Traffic relaunch regenerated or mutated constructor data")
	flight_cases+=1
	# Keep original generated destination; target remains outside this isolated
	# actor's engagement cube. The retained cargo input is a separate source draw.
	random=cargo.random_state
	var result:=step(guide,flight,group,chosen,0,target,random)
	if result.is_empty():return
	random=result.random_state
	check(result.target_kind=="route" and not result.fire_requested,"Neutral traffic targeted the player")
	var duration:=0
	while duration<19999:
		var dt:=mini(150,19999-duration)
		if duration==19800:
			check(group.begin_contact_pass(random,true),group.error)
			damage(group,chosen,27)
			random=group.contact_random_state()
		result=step(guide,flight,group,chosen,dt,target,random)
		if result.is_empty():return
		random=result.random_state;duration+=dt
		if result.get("traffic_departure",false):check(false,"Traffic departed before twenty seconds on its route");return
	var preceding: Dictionary=flight.snapshot();var speed: float=guide.snapshot().speed
	var statistics: Transform3D=group.snapshot().actors[chosen].pose
	# Source route arrival is processed before the departure timer. Place only
	# a fork at the original destination to exercise that competing boundary.
	var arrived_group: RefCounted=group.fork_for_frame();var arrived_guide: RefCounted=guide.fork_for_frame();var arrived_motion: RefCounted=flight.fork_for_frame()
	var destination_pose: Transform3D=preceding.root_pose;destination_pose.origin=initial.actors[chosen].route.waypoints[0]
	check(arrived_motion.apply_scripted_pose(destination_pose) and arrived_group.set_pose(chosen,arrived_motion.snapshot().pose,destination_pose),arrived_motion.error+arrived_group.error)
	var arrived: Dictionary=step(arrived_guide,arrived_motion,arrived_group,chosen,1,target,random)
	check(not arrived.is_empty() and not arrived.get("traffic_departure",false) and arrived.route_event.completed and arrived_guide.snapshot().route_elapsed_ms==0,"Finishing the route failed to reset the departure timer before its boundary")
	check(group.snapshot().actors[chosen].pose==statistics and flight.snapshot()==preceding,"An arrival fork moved committed traffic")
	result=step(guide,flight,group,chosen,1,target,random)
	if result.is_empty():return
	random=result.random_state
	check(result.get("traffic_departure",false) and not result.traffic_parked and result.speed==Vitals.single(speed*1.100000023841858),"Twenty-second route boundary lost its departure burst")
	check(flight.snapshot().history==preceding.history and flight.snapshot().bank==preceding.bank and group.snapshot().actors[chosen].pose==statistics,"Departure changed bank history or refreshed the source statistics pose")
	var acceleration_steps:=0
	while not result.traffic_parked and acceleration_steps<60:
		var previous: Dictionary=flight.snapshot()
		result=step(guide,flight,group,chosen,0,target,random)
		if result.is_empty():return
		random=result.random_state;acceleration_steps+=1
		check(previous==flight.snapshot(),"Zero-time departure acceleration moved the ship or changed banking")
	check(result.traffic_parked and result.speed>100 and not group.snapshot().actors[chosen].active and group.snapshot().actors[chosen].actor_mode==4,"Departure failed to park after its strict speed limit")
	check(not group.collision_context(chosen).eligible,"Departed traffic stayed collidable")
	var held:=guide.snapshot()
	check(guide.update(-1,group.snapshot().actors[chosen],flight.snapshot().root_pose,target,random,group.snapshot().actors).is_empty() and guide.snapshot()==held,"Invalid traffic guidance partly committed")
	var second_cargo: Dictionary=construction.sample_relaunch_cargo(random)
	var preceding_boost:=guide.snapshot()
	check(not second_cargo.is_empty() and group.relaunch_ambient(chosen,bindings),construction.error+group.error)
	state=group.snapshot().actors[chosen]
	check(guide.relaunch_ambient(state) and flight.apply_scripted_pose(state.body_pose),guide.error+flight.error)
	check(state.travel_cycle==2 and state.body_pose.origin==Vector3.ZERO and state.vitals.hull==state.max_hull and guide.snapshot().route_elapsed_ms==0,"A second launch lost cycle identity, health or route reset")
	check(preceding_boost.boost_active and guide.snapshot().boost_active and guide.snapshot().speed_target==preceding_boost.speed_target and guide.snapshot().boost_duration_ms==preceding_boost.boost_duration_ms and not guide.snapshot().damage_boost,"Relaunch incorrectly cleared the retained boost state")
	check(group.snapshot().provocation.requested_damage[chosen]==0 and group.snapshot().provocation.warning_issued and not group.snapshot().provocation.forced_hostile[chosen] and group.current_reputation()==REPUTATION,"Relaunch failed to clear actor damage or changed world warnings/reputation")
	var saved: Dictionary=group.snapshot()
	var copy: RefCounted=group.fork_for_frame();damage(copy,chosen,1000,true)
	check(not copy.relaunch_ambient(chosen,bindings),"Destroyed traffic bypassed its unfinished recycle lifecycle")
	check(group.snapshot()==saved and construction.snapshot()==initial,"Tentative death changed live traffic or its construction")

func step(guide: RefCounted,flight: RefCounted,group: RefCounted,id: int,delta: int,player: Dictionary,random: Dictionary) -> Dictionary:
	if not group.refresh_hostility(id):check(false,group.error);return {}
	var body: Dictionary=group.snapshot();var actor: Dictionary=body.actors[id]
	var decision: Dictionary=guide.update(delta,actor,flight.snapshot().root_pose,player,random,body.actors)
	if decision.is_empty():check(false,guide.error);return {}
	if not group.apply_ambient_guidance(decision):check(false,group.error);return {}
	if decision.get("traffic_departure",false):
		var moved: Dictionary=flight.advance_forward_only(delta,decision.speed)
		if moved.is_empty() or not group.apply_ambient_departure_pose(id,moved.root_pose):check(false,flight.error+group.error);return {}
	elif decision.travel_enabled or decision.steering_enabled:
		var moved: Dictionary=flight.advance(delta,decision.direction,decision.speed,decision.steering_enabled,decision.travel_enabled)
		if moved.is_empty() or not group.set_pose(id,moved.pose,moved.root_pose):check(false,flight.error+group.error);return {}
	return decision
