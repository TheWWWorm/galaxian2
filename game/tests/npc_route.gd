extends SceneTree
const Route = preload("res://src/simulation/npc_route.gd")
const Definitions = preload("res://src/content/npc_route_definitions.gd")
const Guidance = preload("res://src/simulation/opening_npc_guidance.gd")
const NpcControl = preload("res://src/simulation/opening_npc_control.gd")
const Combat = preload("res://src/simulation/opening_combat_group.gd")
const Guns = preload("res://src/simulation/opening_npc_weapons.gd")
const Random = preload("res://src/simulation/seeded_random.gd")
const Vectors = preload("res://src/simulation/source_vectors.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Library = preload("res://src/content/library.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
var failures := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Pass content/bindings/visuals triples")
	for i in range(0,args.size()-2,3): check_profile(args[i],args[i+1])
	print("NPC route checks: %d failures" % failures)
	quit(1 if failures else 0)

func check_profile(content: String, bindings_path: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new()
	if not library.open(content) or not bindings.open(bindings_path,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error)
		return
	var route := Route.new()
	var data: Dictionary = bindings.opening_actors.npc_initialization.get("routes",{})
	if data.is_empty():
		check(not route.configure(bindings,0) and route.snapshot().is_empty(),"Legacy pack invented generated NPC routes")
		return
	var arch := "armv7" if library.manifest.profile.edition=="ios-hd" else "x86_64"
	var extent := 0
	for span in data.provenance.values(): extent=maxi(extent,int(span.offset)+int(span.bytes))
	check(Definitions.validate(data,extent,arch).is_empty(),"Route provenance rejected")
	for key in data:
		var bad := data.duplicate(true);bad.erase(key)
		check(not Definitions.parameters(bad),"Incomplete route declaration accepted: "+key)
	for key in data.provenance:
		var bad := data.duplicate(true);bad.provenance[key].bytes+=1
		check(not Definitions.validate(bad,extent,arch).is_empty(),"Changed route extent accepted: "+key)
	for value in [true,null,NAN,INF,0.5]:
		var bad := data.duplicate(true);bad.candidate_origins[0][0]=value
		check(not Definitions.parameters(bad),"Invalid route coordinate accepted")
	check(route.configure(bindings,0),route.error)
	var ungenerated: Dictionary = route.snapshot()
	check(route.advance(Vector3.ZERO).is_empty(),"Ungenerated route advanced")
	check(route.generate({}).is_empty() and route.snapshot()==ungenerated,"Bad RNG partly generated a route")
	# Independent 48-bit integer arithmetic fixtures cover 2/3/4 points and retries.
	for fixture in FIXTURES:
		check(route.configure(bindings,0),route.error)
		var random := Random.new();random.seed_from(fixture.seed)
		var initial: Dictionary = random.snapshot()
		var result := route.generate(initial)
		if result.is_empty():
			check(false,route.error)
			continue
		check(result.random_state.state==fixture.state and result.route.candidate_indices==fixture.indices,"Route RNG draw order/rejection changed")
		check(random.snapshot()==initial,"Route generator mutated caller RNG")
		for i in fixture.waypoints.size():
			var p: Array = fixture.waypoints[i]
			check(result.route.waypoints[i]==Vector3(p[0],p[1],p[2]),"Generated route coordinates changed")
		var saved: Dictionary = route.snapshot()
		check(route.generate(initial).is_empty() and route.snapshot()==saved,"Route regenerated without a fresh configuration")
		var point: Vector3 = saved.waypoints[0]
		for axis in 3:
			for sign_value in [-1,1]:
				var at := point;at[axis]+=sign_value*2000
				var boundary := route.advance(at)
				check(not boundary.is_empty() and not boundary.arrived and boundary.index==0,"Route arrival accepted box equality")
		for bad in [null,{},Vector3(NAN,0,0),Vector3(INF,0,0),Vector3(1.0e40,0,0)]:
			check(route.advance(bad).is_empty() and route.snapshot()==saved,"Invalid route position partly advanced state")
		var fork: RefCounted = route.fork_for_frame()
		var arrival: Dictionary = fork.advance(point+Vector3(1999,1999,1999))
		check(arrival.arrived and arrival.index==1 and route.snapshot()==saved,"Strict route arrival or fork ownership changed")
		for i in saved.waypoints.size():
			var current: Dictionary = route.snapshot()
			var advanced := route.advance(current.waypoints[current.index])
			check(advanced.arrived and advanced.index==(i+1)%saved.waypoints.size(),"Waypoint advance skipped a point")
			check(advanced.wrapped==(i==saved.waypoints.size()-1),"Route wrap changed")
		result.route.waypoints.clear()
		check(not route.snapshot().waypoints.is_empty(),"Returned route aliases its owner")
	for id in [-1,3,0.0,true]:check(not route.configure(bindings,id) and route.snapshot().is_empty(),"Invalid route actor accepted")
	check_guidance(bindings,catalogues)
	check_controller(bindings,catalogues)
	print(library.manifest.profile.edition,": generated route draws, arrival boxes, acquisition transitions and transaction ownership verified")

func fresh_route(bindings: RefCounted, id: int) -> RefCounted:
	var route := Route.new();check(route.configure(bindings,id),route.error)
	var random := Random.new();random.seed_from(19)
	check(not route.generate(random.snapshot()).is_empty(),route.error)
	return route

func active_group(bindings: RefCounted, catalogues: RefCounted) -> RefCounted:
	var combat := Combat.new();check(combat.configure(bindings,catalogues,0.5),combat.error)
	var scene := combat.snapshot()
	for actor in scene.actors:
		actor.pose=Transform3D.IDENTITY;actor.position=Vector3.ZERO
	var flags := [];flags.resize(bindings.opening_dialogue.events.size());flags.fill(false);flags[7]=true
	check(combat.update(scene,3,{"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"finished":flags}),combat.error)
	return combat

func player_for(bindings: RefCounted, position: Vector3) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"pose":Transform3D(Basis.IDENTITY,position),"active":true,"hull":10000,"special_flight":false,"targeting_blocked":false}

func check_guidance(bindings: RefCounted, catalogues: RefCounted) -> void:
	var guidance := Guidance.new();check(guidance.configure(bindings,catalogues,0,0.5),guidance.error)
	var route := fresh_route(bindings,0);var original: Dictionary=route.snapshot()
	check(not guidance.set_initial_route(fresh_route(bindings,1)),"Cross-actor route accepted")
	check(guidance.set_initial_route(route),guidance.error)
	check(not guidance.set_initial_route(route),"Second initial route accepted")
	var combat := active_group(bindings,catalogues)
	var actor: Dictionary = combat.snapshot().actors[0]
	actor.pose.origin=original.waypoints[0]
	var player := player_for(bindings,actor.pose.origin+Vector3(0,0,100000))
	var random := Random.new();random.seed_from(4)
	var initial := random.snapshot()
	var result := guidance.update(0,actor,actor.pose,player,initial)
	if result.is_empty():
		check(false,guidance.error)
		return
	check(result.target_kind=="route" and not result.fire_requested and not result.close_heading_preserved,"Unacquired active NPC did not patrol")
	check(result.route_event.arrived and result.route_event.index==1 and result.random_state==initial,"Patrol arrival consumed random values or ignored zero time")
	check(result.direction==Vectors.normalized(original.waypoints[1]-actor.pose.origin),"Patrol selected the old waypoint after arrival")
	check(route.snapshot()==original,"Guidance advanced the caller route")
	var retained: Dictionary = guidance.snapshot().route
	player.pose.origin=actor.pose.origin+Vector3(0,0,10000)
	result=guidance.update(0,actor,actor.pose,player,initial)
	check(result.target_kind=="player" and result.fire_requested and guidance.snapshot().route==retained,"Player acquisition advanced the dormant route")
	player.pose.origin=actor.pose.origin+Vector3(0,0,50000)
	check(guidance.update(0,actor,actor.pose,player,initial).target_kind=="player","Acquired player lost before refresh")
	result=guidance.update(5001,actor,actor.pose,player,initial)
	check(result.target_kind=="route" and not result.fire_requested and guidance.snapshot().fire_desired,"Out-of-range refresh lost the independent fire-desire latch")
	player.pose.origin=actor.pose.origin+Vector3(0,0,10000);player.targeting_blocked=true
	result=guidance.update(0,actor,actor.pose,player,result.random_state)
	check(result.target_kind=="route" and guidance.snapshot().fire_desired,"Patrol reacquired early or player suppression changed route desire")
	player.targeting_blocked=false
	result=guidance.update(5001,actor,actor.pose,player,result.random_state)
	check(result.target_kind=="player" and result.fire_requested and guidance.snapshot().route==retained,"Refresh failed to reacquire without resetting route progress")
	check(not guidance.set_initial_route(fresh_route(bindings,0)),"Running guidance accepted a new route")
	# A nearby route point does not invoke the player's close-heading override.
	guidance.configure(bindings,catalogues,0,0.5);guidance.set_initial_route(route)
	actor.pose.origin=original.waypoints[0]+Vector3(7999,0,0)
	player.pose.origin=actor.pose.origin+Vector3(0,0,100000)
	result=guidance.update(0,actor,actor.pose,player,initial)
	check(result.target_kind=="route" and result.direction==Vector3(-1,0,0) and not result.close_heading_preserved and result.route_event.index==0,"Patrol point incorrectly preserved near-player heading")
	# Inactive holding never advances its route, even with an out-of-range player.
	var held := Combat.new();held.configure(bindings,catalogues,0.5)
	guidance.configure(bindings,catalogues,0,0.5);guidance.set_initial_route(route)
	actor=held.snapshot().actors[0];actor.pose=Transform3D(Basis.IDENTITY,original.waypoints[0])
	player.pose.origin=actor.pose.origin+Vector3(0,0,100000);player.targeting_blocked=true
	result=guidance.update(5001,actor,actor.pose,player,initial)
	check(result.holding and guidance.snapshot().route==original,"Holding NPC advanced its generated route")

func check_controller(bindings: RefCounted, catalogues: RefCounted) -> void:
	var control := NpcControl.new();check(control.configure(bindings,catalogues,0.5),control.error)
	var combat := active_group(bindings,catalogues)
	var guns := Guns.new();check(guns.configure(bindings,catalogues),guns.error)
	for id in 3:
		var route := fresh_route(bindings,id)
		check(control.set_initial_route(id,route),control.error)
		check(combat.set_pose(id,Transform3D(Basis.IDENTITY,route.snapshot().waypoints[0])),combat.error)
	var player := player_for(bindings,Vector3(0,0,1000000))
	var random := Random.new();random.seed_from(4)
	var before := control.snapshot();var bodies: Dictionary = combat.snapshot();var weapons := guns.snapshot()
	# A later actor identity failure discards earlier route advances and movement.
	# Inject a stale final guidance identity to fail after the earlier staged moves.
	control._guidance[2]._identity.binding_id="other"
	var failed_state := control.snapshot()
	check(control.evaluate(combat,guns,16,player,random.snapshot()).is_empty(),"Invalid final actor did not reject the staged pass")
	check(control.snapshot()==failed_state and combat.snapshot()==bodies and guns.snapshot()==weapons,"Failed final actor retained earlier patrol progress")
	control._guidance[2]._identity.binding_id=bindings.binding_id
	var result := control.evaluate(combat,guns,16,player,random.snapshot())
	if result.is_empty():
		check(false,control.error)
		return
	check(control.snapshot()==before and combat.snapshot()==bodies and guns.snapshot()==weapons,"Successful route pass mutated its inputs")
	for actor in result.actors:
		check(actor.decision.target_kind=="route" and actor.decision.route_event.index==1 and actor.firing.is_empty(),"Ordered NPC route pass failed")
	var next: RefCounted = result.controller
	check(not next.set_initial_route(0,fresh_route(bindings,0)),"Advanced controller regenerated a route")
	check(result.random_state==random.snapshot(),"Waypoint progression consumed shared RNG")
	for i in 600:
		result=result.controller.evaluate(result.combat,result.weapons,16,player,result.random_state)
		if result.is_empty():
			check(false,"Repeated native patrol failed")
			break

func check(condition: bool, message: String) -> void:
	if not condition:
		failures+=1
		push_error(message)

const FIXTURES = [
  {
    "seed": 0,
    "indices": [
      2,
      3,
      0,
      1
    ],
    "waypoints": [
      [
        9491,
        -239,
        73719
      ],
      [
        -22146,
        -8923,
        62677
      ],
      [
        -13640,
        -4052,
        43029
      ],
      [
        21447,
        -6485,
        26053
      ]
    ],
    "state": 77392660919880
  },
  {
    "seed": 1,
    "indices": [
      0,
      3,
      2
    ],
    "waypoints": [
      [
        -6015,
        -5412,
        36847
      ],
      [
        -28252,
        -3431,
        78473
      ],
      [
        9434,
        -3394,
        69978
      ]
    ],
    "state": 155957491705596
  },
  {
    "seed": 4,
    "indices": [
      3,
      1,
      0,
      2
    ],
    "waypoints": [
      [
        -21573,
        -3308,
        59508
      ],
      [
        20558,
        -6233,
        20105
      ],
      [
        -8138,
        -8548,
        43303
      ],
      [
        17911,
        -154,
        66462
      ]
    ],
    "state": 161723249711131
  },
  {
    "seed": 19,
    "indices": [
      1,
      2
    ],
    "waypoints": [
      [
        29784,
        -4586,
        40991
      ],
      [
        25870,
        -127,
        64190
      ]
    ],
    "state": 210947475347375
  },
  {
    "seed": 97,
    "indices": [
      2,
      1,
      0
    ],
    "waypoints": [
      [
        10559,
        -5951,
        74591
      ],
      [
        10743,
        -1574,
        43112
      ],
      [
        -23962,
        -6966,
        30067
      ]
    ],
    "state": 41191029587126
  }
]
