extends "res://tests/mido_traffic.gd"
## Generated traffic advances through shared native guidance and motion. This
## component check does not supply an earned trip or a traffic combat path.
const TrafficControl=preload("res://src/simulation/combat_training_control.gd")
const TrafficBody=preload("res://src/simulation/opening_combat_actor.gd")
const TrafficRules=preload("res://src/content/mido_travel_definitions.gd")
const Motion=preload("res://src/simulation/npc_flight.gd")

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	print("Mido traffic patrol: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_field(library: RefCounted, bindings: RefCounted, cat: RefCounted, equipment: RefCounted) -> void:
	super.verify_field(library,bindings,cat,equipment)
	var seen_hulls:=[]
	var observed_boost:=false
	for seed in [0,1,2,3,4,5,6,7,1789100000]:
		var world:=World.new()
		if not world.configure_local_traffic(bindings,cat,equipment,seed,CONDITIONS) or world.generate({"state":9999}).is_empty():check(false,world.error);return
		var initial:=world.snapshot()
		for actor in initial.npc_construction.actors:
			if not seen_hulls.has(actor.hull_catalogue_id):seen_hulls.append(actor.hull_catalogue_id)
		var owner:=TrafficControl.new()
		var rank: int=seed%2
		var difficulty: float=0.5 if rank==0 else 1.0
		if not owner.configure_local_patrol(bindings,cat,world,rank,difficulty):check(false,owner.error);return
		var before:=owner.snapshot()
		check(before.support_state=="patrol_only" and before.campaign_cursor==10,"Patrol invented full combat or changed campaign context")
		check(owner.fork_for_frame().snapshot()==before and before.random_state==initial.random_state,"Configuring patrol consumed the world stream or lost its fork")
		var expected_hull: int=(60 if rank==0 else 74) if difficulty==0.5 else (90 if rank==0 else 111)
		for actor in before.combat.actors:
			check(actor.vitals.hull==expected_hull and actor.max_hull==expected_hull and actor.factory_hull==expected_hull,"Ordinary traffic inherited Gunant's authored health")
			check(actor.actor_mode==0 and actor.active and not actor.hostile and not actor.friendly,"Ordinary traffic inherited friendly or pirate initialization")
			check(not actor.targeting_blocked and not actor.statistics_targeting_blocked and actor.node_draw_requested and actor.engine_draw_enabled,"Ordinary traffic lost its source draw or targeting gates")
		var target:=player_target(bindings)
		var first:=owner.advance(150,target)
		if first.is_empty():check(false,owner.error);return
		check(first.random_state==before.random_state and first.firing_requests.is_empty(),"Initial mode consumed boost/firing draws")
		for id in first.decisions.size():
			var decision: Dictionary=first.decisions[id]
			var actor: Dictionary=first.combat.actors[id]
			check(decision.initializing and not decision.travel_enabled and not decision.steering_enabled and not decision.fire_requested and actor.actor_mode==1,"Initial ordinary mode failed to defer flight")
			check(actor.pose==before.combat.actors[id].pose and actor.body_pose==before.combat.actors[id].body_pose,"Initial ordinary mode moved its factory body")
			check(owner.snapshot().guidance[id].target_index==-1 and decision.target_kind=="route","Neutral traffic selected the player or another same-kind ship")
		var second:=owner.advance(150,target)
		if second.is_empty():check(false,owner.error);return
		for id in second.decisions.size():
			var actor: Dictionary=second.combat.actors[id]
			check(not second.decisions[id].initializing and second.decisions[id].travel_enabled and second.decisions[id].target_kind=="route","Ordinary patrol did not enter native flight")
			check(Motion.rigid_pose(actor.body_pose) and actor.body_pose.origin.distance_to(first.combat.actors[id].body_pose.origin)>299.0 and actor.body_pose.origin.distance_to(first.combat.actors[id].body_pose.origin)<301.0,"Patrol movement lost its source units or finite root")
		# Cross a target refresh and random boost interval using the actual shared
		# stream. Membership must remain neutral throughout, including near player.
		for frame in 70:
			var result:=owner.advance(150,target)
			if result.is_empty():check(false,owner.error);return
			if not result.firing_requests.is_empty():check(false,"Unprovoked same-faction traffic opened fire");return
			for guidance in owner.snapshot().guidance:observed_boost=observed_boost or guidance.boost_active
		check(owner.snapshot().random_state!=before.random_state,"Patrol failed to consume its retained decision/boost stream")
		check(world.snapshot()==initial,"Live patrol mutated detached construction or its generated routes")
		verify_rejections(owner,world,bindings,cat,rank,difficulty,target)
	seen_hulls.sort()
	check(seen_hulls==[3,6,19,20,30],"Patrol checks omitted a permitted original hull")
	check(observed_boost,"Ordinary traffic inherited Gunant's disabled random boost")

func verify_rejections(owner: RefCounted, world: RefCounted, bindings: RefCounted, cat: RefCounted, rank: int, difficulty: float, target: Dictionary) -> void:
	var before: Dictionary=owner.snapshot()
	for delta in [-1,151,0.5]:
		check(owner.advance(delta,target).is_empty() and owner.snapshot()==before,"Invalid patrol duration partially advanced the group")
	var wrong:=target.duplicate(true);wrong.binding_id="0".repeat(64)
	check(owner.advance(150,wrong).is_empty() and owner.snapshot()==before,"Foreign player partially advanced patrol")
	check(owner.advance(150,target,null,{"state":-1}).is_empty() and owner.snapshot()==before,"Invalid shared stream partially advanced patrol")
	var combat: RefCounted=owner.combat_owner()
	var bodies: Dictionary=combat.snapshot()
	check(combat.normal_hit(0,1).is_empty() and combat.snapshot()==bodies,"Patrol silently accepted damage without retaliation")
	check(owner.advance(150,target,combat).is_empty() and owner.snapshot()==before,"Patrol borrowed the unfinished combat path")
	check(not owner.set_destruction(bindings,null) and owner.snapshot()==before,"Patrol borrowed training destruction")
	check(owner.evaluate(combat,null,150,target,before.random_state).is_empty() and owner.snapshot()==before,"Patrol borrowed training weapons")
	for invalid_rank in [-1,3,0.5]:
		check(not TrafficControl.new().configure_local_patrol(bindings,cat,world,invalid_rank,difficulty),"Patrol invented an unsupported career rank")
	check(not TrafficControl.new().configure_local_patrol(bindings,cat,world,rank,1.5),"Patrol ignored unsupported hardest traffic")
	check(not TrafficBody.new().configure_local_patrol(bindings,cat,world,-1,rank,difficulty),"Patrol accepted a missing actor")
	var malformed: Dictionary=world.snapshot()
	malformed.npc_construction.actors[0].actor_kind=8
	check(TrafficRules.patrol(bindings,malformed,rank,difficulty).is_empty(),"Patrol accepted a pirate in the ordinary faction list")
	malformed=world.snapshot();malformed.station_id=79
	check(TrafficRules.patrol(bindings,malformed,rank,difficulty).is_empty(),"Kernstal borrowed Var Hastra traffic")
	var copy: RefCounted=owner.fork_for_frame()
	var expected: Dictionary=owner.advance(0,target)
	var actual: Dictionary=copy.advance(0,target)
	check(not expected.is_empty() and actual==expected and owner.snapshot()==copy.snapshot(),"Patrol forks diverged across an ordinary zero-duration pass")

func player_target(bindings: RefCounted) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"ship_id":0,
		"pose":Transform3D(Basis.IDENTITY,Vector3(10,10,10000)),"active":true,"hull":10,
		"special_flight":false,"targeting_blocked":false,"alternate_position":null}
