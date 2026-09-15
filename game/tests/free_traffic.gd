extends "res://tests/free_population.gd"
## Detached source-generated bodies, movement and weapon pools. No career state
## is manufactured; application departure and combat-group reactions stay gated.
const FreeTraffic=preload("res://src/content/free_traffic_definitions.gd")
const AmbientCombat=preload("res://src/content/ambient_combat_definitions.gd")
const Life=preload("res://src/content/ambient_lifecycle_definitions.gd")
const Actor=preload("res://src/simulation/opening_combat_actor.gd")
const Guidance=preload("res://src/simulation/opening_npc_guidance.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const Freighter=preload("res://src/simulation/freighter_motion.gd")
const Weapons=preload("res://src/simulation/opening_npc_weapons.gd")
const Shots=preload("res://src/simulation/ordinary_projectiles.gd")
const Targeting=preload("res://src/simulation/ordinary_npc_targeting.gd")
const Geometry=preload("res://src/simulation/ordinary_hit_geometry.gd")
var geometry_seen:={}

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:verify(args)
	else:check(false,"Expected explicit content, binding and visual paths")
	print("Ordinary ship setup: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_live_setup(bindings: RefCounted,cat: RefCounted,owner: RefCounted,expected: Dictionary) -> void:
	if failures>0:return
	var rank:=int(expected.rank);var difficulty:=float(expected.difficulty)
	if not FreeTraffic.available(bindings):
		check(not Actor.new().configure_ambient(bindings,cat,owner,0,rank,difficulty),"Earlier pack inferred ordinary combat setup")
		check(not Weapons.new().configure_ambient(bindings,cat,owner,rank,difficulty),"Earlier pack inferred ordinary weapons")
		return
	var packet: Dictionary=owner.snapshot()
	var rules:=Life.guidance(bindings,packet,rank,difficulty)
	if rules.is_empty():check(false,"Generated ordinary context failed live validation");return
	check(rules.player_ship_id==packet.player_ship_id,"Guidance replaced the generated player hull")
	var bodies:=[]
	for row in packet.actors:
		var body:=Actor.new()
		if not body.configure_ambient(bindings,cat,owner,row.actor_id,rank,difficulty):check(false,body.error);return
		bodies.append(body)
		var state: Dictionary=body.snapshot()
		var hull:=int((92+14*rank)*(1.5 if difficulty==1.0 else 1.0)*(5 if row.population_group=="freighter" else 1))
		check(state.vitals.hull==hull and state.max_hull==hull and state.factory_hull==hull,"Ordinary constructor retained an authored hull override")
		check(state.vitals.shield==0 and not state.hostile and state.free_traffic,"Ordinary initial vitals or hostility changed")
		check(state.pose==row.statistics_pose and state.body_pose==row.body_pose,"Live body lost original construction pose")
		var held: Dictionary=body.snapshot()
		check(body.normal_hit(1).is_empty() and body.snapshot()==held,"Detached traffic accepted damage without faction reactions")
		check(body.refresh_hostility(),body.error)
		check(body.snapshot().hostile==(row.actor_kind==8),"Ordinary pirate did not refresh unconditional hostility")
		var members:=[-1]
		for other in packet.actors:
			if other.actor_kind!=row.actor_kind:members.append(other.actor_id)
		check(rules.target_memberships[row.actor_id]==members,"Ordinary target membership lost player-first/faction exclusion order")
		if row.population_group=="freighter":verify_freighter(bindings,owner,body,row)
	var weapons:=Weapons.new()
	if not weapons.configure_ambient(bindings,cat,owner,rank,difficulty):check(false,weapons.error);return
	var armed: Dictionary=weapons.snapshot()
	for row in packet.actors:
		var gun: Dictionary=armed.actors[row.actor_id]
		if row.population_group=="freighter":check(gun.definition.unarmed and gun.projectiles.is_empty() and gun.audio.is_empty(),"Freighter received a weapon or firing sound");continue
		var item: int={0:0,1:3,2:7,8:19}[row.actor_kind]
		var damage: int={0:3,4:3,20:24}[rank]
		check(gun.definition.item_id==item and gun.definition.damage==damage and gun.definition.interval_ms==564,"Ordinary faction, rank or cursor weapon values differ")
		check(gun.projectiles.weapon.nonplayer_source and gun.projectiles.weapon.speed_units_per_millisecond==16.0 and gun.projectiles.available_slots==4,"Ordinary weapon lost attribution, speed or capacity")
		var shots:=Shots.new()
		if not shots.configure(gun.projectiles.weapon):check(false,shots.error);return
		check(not shots.snapshot().time_ready and not shots.fire(Vector3.ZERO,Vector3.FORWARD,true).fired,"Weapon ignored strict initial interval equality")
		check(not shots.advance(1).is_empty() and shots.snapshot().time_ready,"Weapon failed to become ready after its strict boundary")
		check(shots.fire(Vector3.ZERO,Vector3(0,0,1),true).fired,"Ordinary weapon could not launch its projectile")
		check(not shots.advance(16).is_empty() and shots.snapshot().slots[0].position==Vector3(0,0,256),"Ordinary projectile lost source movement units")
		verify_guidance(bindings,cat,owner,bodies,row.actor_id,rank,difficulty)
	check(owner.snapshot()==packet,"Live setup mutated committed factory data")
	verify_rejection(bindings,packet,rank,difficulty)
	if int(expected.seed)==0 and rank==0:
		verify_opposition(bindings,rules)
		verify_other_player_hull(bindings,cat)

func verify_freighter(bindings: RefCounted,owner: RefCounted,body: RefCounted,row: Dictionary) -> void:
	var motion:=Freighter.new()
	if not motion.configure(bindings,owner,row.actor_id):check(false,motion.error);return
	var held: Dictionary=motion.snapshot()
	check(motion.update(32,false) and motion.snapshot()==held,"Disabled freighter motion advanced")
	check(motion.update(32,true),motion.error)
	var moved: Dictionary=motion.snapshot()
	check(moved.body_pose.origin==held.body_pose.origin+Vector3(0,0,32) and moved.body_pose==moved.statistics_pose and moved.elapsed_motion_ms==32,"Freighter cruise is not one source unit per millisecond")
	check(moved.source_position==held.source_position+Vector3i(0,0,32),"Freighter integer cruise position changed")
	var fork: RefCounted=motion.fork_for_frame()
	check(fork.update(16,true) and motion.snapshot()==moved,"Freighter frame copy aliases committed motion")
	check(not motion.update(-1,true) and motion.snapshot()==moved,"Invalid freighter delta partly committed")
	var shape: Dictionary=body.collision_context()
	check(shape.path=="point_geometry" and shape.boxes.size()==3,"Ordinary freighter lost its three source collision boxes")
	if geometry_seen.has(row.actor_kind):return
	geometry_seen[row.actor_kind]=true
	var root_id: int=17065 if row.actor_kind==0 else 17060
	check(body.snapshot().hull_resource==bindings.resolve(root_id,"mesh"),"Freighter body uses another faction's mesh")
	var geometry:=Geometry.new()
	var poses:=[Transform3D.IDENTITY,Transform3D(Basis(Vector3.UP,PI/2),Vector3(100,200,300))]
	for pose in poses:
		check(body.set_pose(pose,pose),body.error)
		var vector: Vector3=Vector3(2167.5,-85,24) if row.actor_kind==2 else Vector3(2610,-770,-4279)
		var edge:=geometry.box_geometry(pose.origin+vector,pose.origin,shape.boxes)
		var inside:=geometry.box_geometry(pose.origin+vector-Vector3(0.5,0,0),pose.origin,shape.boxes)
		check(not edge.hit and inside.hit,"Freighter collision face lost strict world-axis boundary")
		var union:=geometry.box_geometry(pose.origin+Vector3(0,710,292) if row.actor_kind==2 else pose.origin,pose.origin,shape.boxes)
		check(union.hit and union.box_index==(1 if row.actor_kind==2 else 0),"Freighter box overlap ordering changed")
	check(body.set_pose(row.statistics_pose,row.body_pose),body.error)

func verify_guidance(bindings: RefCounted,cat: RefCounted,owner: RefCounted,bodies: Array,id: int,rank: int,difficulty: float) -> void:
	var guide:=Guidance.new();var motion:=Flight.new();var body: RefCounted=bodies[id]
	if not guide.configure_ambient(bindings,cat,owner,id,rank,difficulty) or not motion.configure(bindings,body.snapshot().body_pose):check(false,guide.error+motion.error);return
	var origin: Vector3=body.snapshot().pose.origin
	var player:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"pose":Transform3D(Basis.IDENTITY,Vector3(25000,0,25000)),"active":true,"hull":100,
		"special_flight":false,"targeting_blocked":false,"ship_id":int(owner.snapshot().player_ship_id),"alternate_position":null}
	var state: Dictionary=owner.snapshot().random_state
	for frame in 4:
		var decision:=guide.update(16,body.snapshot(),body.snapshot().body_pose,player,state,bodies.map(func(actor):return actor.snapshot()))
		if decision.is_empty():check(false,guide.error);return
		check(body.apply_ambient_guidance(decision),body.error)
		var flight:=motion.advance(16,decision.direction,decision.speed,decision.steering_enabled,decision.travel_enabled)
		if flight.is_empty():check(false,motion.error);return
		check(body.set_pose(motion.banked_pose(),flight.root_pose),body.error)
		state=decision.random_state
	var waiting: bool=body.snapshot().population_group=="travel"
	check(body.snapshot().pose.origin==origin if waiting else body.snapshot().pose.origin!=origin,"Ordinary initialization or waiting motion changed")
	check(body.snapshot().actor_mode==(4 if waiting else 1) and body.snapshot().active!=waiting,"Ordinary actor lifecycle mode changed")
	var before: Dictionary=guide.snapshot()
	check(guide.update(1001,body.snapshot(),body.snapshot().body_pose,player,state,bodies.map(func(actor):return actor.snapshot())).is_empty() and guide.snapshot()==before,"Oversized guidance step mutated retained state")

func verify_rejection(bindings: RefCounted,packet: Dictionary,rank: int,difficulty: float) -> void:
	for key in CONTEXT:
		var changed:=packet.duplicate(true);changed.free_context.erase(key)
		check(AmbientCombat.population(bindings,changed,rank,difficulty).is_empty(),"Live setup inferred missing context "+key)
	var changed:=packet.duplicate(true);changed.actors[0].actor_kind=3
	check(AmbientCombat.population(bindings,changed,rank,difficulty).is_empty(),"Ordinary setup admitted a mismatched faction")
	changed=packet.duplicate(true);changed.binding_id="bad"
	check(AmbientCombat.population(bindings,changed,rank,difficulty).is_empty(),"Ordinary setup admitted another binding identity")
	check(AmbientCombat.population(bindings,packet,21,difficulty).is_empty() and AmbientCombat.population(bindings,packet,rank,1.5).is_empty(),"Ordinary setup inferred unsupported rank/difficulty")

func verify_opposition(bindings: RefCounted,rules: Dictionary) -> void:
	for actor in [0,1,2,3,8]:
		for target in [0,1,2,3,8]:
			var enemy: bool=actor!=target and (actor==8 or target==8 or [actor,target] in [[0,1],[1,0],[2,3],[3,2]])
			check(Targeting.opposed(actor,target,rules)==enemy,"Ordinary faction opposition changed")
	var state:={"target_index":0,"fire_desired":true,"selection_elapsed_ms":0,"straight":false}
	var actor:={"actor_kind":0,"hostile":false,"pose":Transform3D.IDENTITY,"spatial_half_extent":50000}
	var targets:=[{"active":true,"hull":100,"actor_kind":0},{"active":true,"hull":100,"actor_kind":2},{"active":true,"hull":100,"actor_kind":1},{"active":true,"hull":100,"actor_kind":8}]
	var rng:=Random.new();rng.restore({"state":2})
	var before: Dictionary=rng.snapshot()
	var chosen:=Targeting.select(state,actor,targets,rng,bindings.opening_actors.npc_initialization.guidance,rules)
	check(chosen.target_index==2 and chosen.fire_desired and rng.snapshot()==before,"Ordinary scan lost faction opposition, target order or draw-free selection")
	targets[2].active=false
	check(Targeting.select(state,actor,targets,rng,bindings.opening_actors.npc_initialization.guidance,rules).target_index==3,"Ordinary scan selected an inactive enemy")

func verify_other_player_hull(bindings: RefCounted,cat: RefCounted) -> void:
	var owner:=Factory.new()
	if not owner.configure_free_factory(bindings,cat,1,[81,86],CONTEXT,0):check(false,owner.error);return
	var packet:=owner.generate({"state":1})
	if packet.is_empty():check(false,owner.error);return
	var rules:=Life.guidance(bindings,packet,0,0.5)
	check(packet.player_ship_id==1 and rules.get("player_ship_id")==1,"Ordinary setup replaced the explicit nonstarter hull")
	var bodies:=[]
	for row in packet.actors:
		var body:=Actor.new()
		if not body.configure_ambient(bindings,cat,owner,row.actor_id,0,0.5):check(false,body.error);return
		bodies.append(body)
	verify_guidance(bindings,cat,owner,bodies,0,0,0.5)
