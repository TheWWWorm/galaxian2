extends SceneTree
## Ordinary Var Hastra construction, using an explicitly released station
## fixture. This does not verify live traffic or an earned application trip.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Construction=preload("res://src/simulation/opening_npc_construction.gd")
const World=preload("res://src/simulation/opening_world_initialization.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Scenario=preload("res://tests/fixtures/equipment_scenario.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Scenery=preload("res://src/simulation/opening_scenery.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const CONDITIONS={"companions_empty":true,"location_match":false,"special_placement":false}
const VECTORS=[
	[0,1,Vector3(-8947,4491,39761),32934430199125,30,Vector3(-24423,6438,44413)],
	[1,4,Vector3(4904,-5566,36606),185454638771764,3,Vector3(-3833,-4,37840)],
	[2,4,Vector3(3350,4606,39719),9368989764503,3,Vector3(13444,5692,25153)],
	[1789100000,1,Vector3(-9174,1702,42590),45061582439541,19,Vector3(-19865,-1277,43674)],
]
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	print("Mido traffic construction: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library):
		check(false,library.error+bindings.error+cat.error);return
	if bindings.mido_travel.is_empty():
		check(not Construction.new().configure_local_traffic(bindings,cat,null,0),"Earlier bindings invented ordinary traffic");return
	var scenario:=Scenario.new()
	var equipment: RefCounted=scenario.open(OS.get_environment("GOF2_SCENARIO_INPUT"),bindings,cat)
	if equipment==null:check(false,scenario.error);return
	check(not Construction.new().configure_local_traffic(bindings,cat,equipment,0),"Traffic bypassed the station exchange")
	if not equipment.prepare_training_completion(bindings,cat) or not equipment.complete_training(equipment.snapshot().cargo) or not equipment.apply_station_exchange(bindings,cat,9):check(false,equipment.error);return
	var unchanged: Dictionary=equipment.snapshot()
	for vector in VECTORS:
		var owner:=Construction.new()
		if not owner.configure_local_traffic(bindings,cat,equipment,vector[0]):check(false,owner.error);return
		check(owner.generate({"state":-1}).is_empty(),"Traffic accepted an invalid incoming stream")
		var state:=owner.generate({"state":12345})
		if state.is_empty():check(false,owner.error);return
		check(state.campaign_cursor==10 and state.actors.size()==vector[1],"Early Mido population count changed")
		check(state.population.spawn_center==vector[2] and state.population.before_actors_random_state.state==vector[3],"Traffic prelude changed its source draw order")
		check(state.actors[0].hull_catalogue_id==vector[4] and state.actors[0].factory_position==vector[5],"First traffic hull or spawn differs from the independent random vector")
		check(owner.generate({"state":0}).is_empty() and owner.snapshot()==state,"Traffic regenerated after construction")
		for actor in state.actors:
			check(actor.actor_kind==3 and actor.subtype==0 and actor.hull_catalogue_id in [3,6,19,20,30],"Traffic selected an unsupported faction or hull")
			check(actor.body_pose.origin==actor.factory_position and actor.statistics_pose==actor.body_pose,"Traffic replaced its ordinary spawn pose")
			var delta: Vector3=actor.factory_position-vector[2]
			check(delta.x>=-20000 and delta.x<20000 and delta.y>=-20000 and delta.y<20000 and delta.z>=-20000 and delta.z<20000,"Traffic escaped the common spawn region")
			var route: RefCounted=owner.route(actor.actor_id)
			check(route!=null and route.snapshot()==actor.route and actor.route.loop,"Traffic lost its generated patrol owner")
			check(actor.discarded_cargo.is_empty() and not actor.has("discarded_route"),"Traffic discarded its generated cargo or route")
		var world:=World.new()
		if not world.configure_local_traffic(bindings,cat,equipment,vector[0],CONDITIONS):check(false,world.error);return
		var populated:=world.generate({"state":99999})
		if populated.is_empty():check(false,world.error);return
		check(populated.npc_construction==state,"Population did not reseed after scenery")
		check(populated.weapon_effects.size()==state.actors.size(),"Traffic weapons lost an actor")
		var random:=Random.new();random.restore(state.random_state)
		for id in state.actors.size():
			var effects: Dictionary=populated.weapon_effects[id]
			check(effects.actor_id==id and effects.discarded_default.item_id==0 and effects.primary.item_id==25 and effects.primary.resource_id==14606,"Mido traffic received pirate weapon assignments")
			for part in [effects.discarded_default,effects.primary]:
				var flips:=[]
				for index in 4:flips.append(random.next_int(2)==0)
				check(part.flipped==flips,"Traffic effect allocation changed its post-constructor stream")
		check(populated.random_state==random.snapshot(),"Traffic world lost its final shared stream")
	check(equipment.snapshot()==unchanged,"Traffic mutated the player's inventory")
	check(not Construction.new().configure_local_traffic(bindings,cat,equipment,-1),"Traffic accepted invalid Unix seconds")
	for difficulty in [-1.0,0.0,1.5,NAN]:
		check(not World.new().configure_local_traffic(bindings,cat,equipment,0,CONDITIONS,difficulty),"Traffic invented an unsupported difficulty population")
	check(World.new().configure_local_traffic(bindings,cat,equipment,0,CONDITIONS,1.0),"Traffic rejected its second supported difficulty")
	var changed:=CONDITIONS.duplicate();changed.companions_empty=false
	check(not World.new().configure_local_traffic(bindings,cat,equipment,0,changed),"Traffic ignored an extra companion")
	verify_field(library,bindings,cat,equipment)

func verify_field(library: RefCounted, bindings: RefCounted, cat: RefCounted, equipment: RefCounted) -> void:
	var player:=Player.new()
	if not player.configure_local_travel(bindings,cat,equipment):check(false,player.error);return
	var cache:=player.cache_snapshot()
	check(not World.new().configure_local_arrival(bindings,cat,equipment,cache,CONDITIONS),"Var Hastra borrowed Kernstal's empty story population")
	check(not Scenery.new().configure_local_arrival(bindings,cat,equipment,cache,CONDITIONS,1789100000),"Var Hastra scenery borrowed the arrival construction path")
	var bodies:=Bodies.new();var effects:=Effects.new();var field:=Scenery.new()
	if not bodies.configure(library,bindings) or not effects.configure(library,bindings):check(false,bodies.error+effects.error);return
	if not field.configure_local_departure(bindings,cat,equipment,cache,CONDITIONS,1789100000,true,bodies,effects):check(false,field.error);return
	var state:=field.snapshot()
	check(state.station_id==78 and state.world_initialization.campaign_cursor==10 and not state.bodies.is_empty(),"Local departure replaced its source location or omitted its physical field")
	var world: Dictionary=state.world_initialization
	check(world.npc_construction.actors.size()==1 and world.npc_construction.actors[0].hull_catalogue_id==19,"Local scenery lost its independently seeded traffic")
	check(state.random_state==world.random_state and world.input_random_state!=world.npc_construction.population.seed_random_state,"Local scenery did not preserve the separate population reseed")
	check(field.fork_for_frame().snapshot()==state,"A detached departure lost its traffic state")

func check(value: bool, message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr(message)
