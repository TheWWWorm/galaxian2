extends "res://tests/free_world.gd"
## Independent factory ledgers plus actual retained equipment in an explicit
## arrival context. The application jump and career are not manufactured here.
const ArrivalRules=preload("res://src/content/free_arrival_definitions.gd")

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:verify(args)
	else:check(false,"Expected content, bindings and visuals")
	print("Ordinary arrival: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var context:=FreePopulation.CONTEXT.duplicate(true)
	context.special_arrival=true;context.player_position=Vector3(12.25,-31.5,150000)
	if not ArrivalRules.available(bindings):
		check(not Construction.new().configure_free_factory(bindings,cat,0,[81,86],context,2),"Earlier entry pack inferred a local-arrival factory")
		return
	super.verify(args)
	if failures:return
	var path:=OS.get_environment("GOF2_FREE_ARRIVAL_VECTORS")
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>2*1024*1024:check(false,"Supply independent arrival factory vectors");return
	var vectors: Variant=JSON.parse_string(file.get_as_text());file.close()
	if not vectors is Array or vectors.size()!=14:check(false,"Expected fourteen independent arrival boundaries");return
	var cases:={}
	for expected in vectors:
		context.rank=int(expected.rank);context.difficulty=float(expected.difficulty)
		context.player_position=point(expected.player_position)
		var construction:=Construction.new()
		if not construction.configure_free_factory(bindings,cat,0,[81,86],context,int(expected.seed)):check(false,construction.error);return
		var actual:=construction.generate({"state":98765})
		if actual.is_empty():check(false,construction.error);return
		check(actual.actors.size()==expected.actors.size() and actual.random_state.state==int(expected.random_state),"Arrival factory changed its actor count or draw ledger: "+expected.case)
		var sampled: Dictionary=actual.population
		check(sampled.unused_route_origin==point(expected.hostile_origin),"Arrival changed the source pirate origin")
		check(sampled.has("arrival_ambush")==expected.has("arrival_ambush"),"Arrival drew for an absent or non-pirate group")
		cases[expected.case]=true
		if expected.has("arrival_ambush"):
			var event: Dictionary=sampled.arrival_ambush;var wanted: Dictionary=expected.arrival_ambush
			check(event.chance_draw==int(wanted.chance_draw) and event.threshold==int(wanted.threshold) and event.triggered==wanted.triggered,"Arrival crossed its strict rank-adjusted chance boundary")
			check(event.previous_origin==point(wanted.previous_origin) and event.origin==point(wanted.origin),"Ambush changed the wrong source vector")
			if expected.case=="empty":check(sampled.groups.hostile==0,"Zero-sized selected group skipped the arrival draw")
		for id in actual.actors.size():
			var actor: Dictionary=actual.actors[id];var wanted: Dictionary=expected.actors[id]
			check(actor.population_group==wanted.group and actor.actor_kind==int(wanted.faction) and actor.hull_catalogue_id==int(wanted.hull),"Arrival changed group order, faction or hull")
			check(actor.body_pose.origin==point(wanted.position) and actor.statistics_pose==actor.body_pose,"Arrival lost independently calculated actor placement")
			var cargo:=[]
			for item in wanted.cargo:cargo.append({"item_id":int(item[0]),"quantity":int(item[1])})
			check(actor.cargo==cargo,"Ambush consumed an out-of-order cargo draw")
			if wanted.group!="freighter":check(actor.route.waypoints==wanted.route.map(point),"Ambush changed generated flight routes")
		var world:=World.new()
		if not world.configure_free_factory(bindings,cat,0,[81,86],context,int(expected.seed),CONDITIONS):check(false,world.error);return
		var generated:=world.generate({"state":42})
		if generated.is_empty():check(false,world.error);return
		check(generated.npc_construction==actual,"Arrival world changed its factory ledger")
		check(not FreeLife.population(bindings,actual).is_empty(),"Source arrival context did not connect to ordinary lifecycle")
		if failures:return
	for name in ["below","equal","absent","vossk","empty"]:check(cases.has(name),"Missing arrival boundary: "+name)
	for value in [null,{},Vector3.INF,Vector3(NAN,0,0),Vector3(100000016,0,0)]:
		var bad:=context.duplicate(true);bad.player_position=value
		check(not Construction.new().configure_free_factory(bindings,cat,0,[81,86],bad,2),"Malformed arrival position reached native construction")
	var scenario:=Scenario.new();var equipment: RefCounted=scenario.open(OS.get_environment("GOF2_SCENARIO_INPUT"),bindings,cat)
	if equipment==null or not Scenario.prepare_alioth_component(equipment,bindings,cat):check(false,scenario.error);return
	var retained: Dictionary=equipment.snapshot()
	context=FreePopulation.CONTEXT.duplicate(true);context.special_arrival=true;context.player_position=Vector3(0,0,150000)
	var seed: int=int(vectors.filter(func(v):return v.case=="below" and int(v.rank)==0)[0].seed)
	var scenery:=Scenery.new();var bodies:=Bodies.new();var effects:=Effects.new()
	if not bodies.configure(library,bindings) or not effects.configure(library,bindings) or not scenery.configure_free(bindings,cat,equipment,context,CONDITIONS,seed,true,bodies,effects):check(false,bodies.error+effects.error+scenery.error);return
	var scene: Dictionary=scenery.snapshot();var construction: RefCounted=scenery.world_initialization_owner().npc_construction_owner()
	check(construction.snapshot().population.arrival_ambush.triggered,"Actual equipment arrival did not retain the selected ambush")
	var player:=Player.new()
	if not player.configure_free(bindings,cat,equipment,construction):check(false,player.error);return
	verify_free_frame(library,bindings,cat,equipment,construction,player,scene.random_state)
	check(equipment.snapshot()==retained and scenery.snapshot()==scene,"Arrival control altered retained station equipment or field")
