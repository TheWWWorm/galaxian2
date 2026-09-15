extends "res://tests/free_traffic.gd"
## Detached contract-world inputs exercise native counts, factories and combat.
## Acceptance and earned payment belong to the station/application integration.
const Delivery=preload("res://src/content/ordinary_contracts_definitions.gd")

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:verify_delivery(args)
	else:check(false,"Expected explicit content, binding and visual paths")
	print("Ordinary contract population: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_delivery(args: PackedStringArray) -> void:
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	var file:=FileAccess.open(OS.get_environment("GOF2_ORDINARY_CONTRACT_VECTORS"),FileAccess.READ)
	if file==null or file.get_length()>2*1024*1024:check(false,"Supply independent delivery construction vectors");return
	var vectors: Variant=JSON.parse_string(file.get_as_text());file.close()
	if not vectors is Array or vectors.size()!=42:check(false,"Expected delivery difficulty and RNG boundary vectors");return
	for expected in vectors:
		var context:=CONTEXT.duplicate(true)
		context.rank=int(expected.rank);context.difficulty=float(expected.difficulty)
		context.side_missions_empty=false;context.special_arrival=bool(expected.arrival)
		context.player_position=point(expected.delivery.player)
		context.side_mission={"kind":int(expected.delivery.kind),"difficulty":int(expected.delivery.difficulty),"story":false,
			"station_id":98 if expected.delivery.selected else 96}
		context.mission_kind=0 if expected.delivery.selected else -1
		context.mission_completed=not expected.delivery.selected
		var owner:=Factory.new()
		if not Delivery.available(bindings):
			check(not owner.configure_free_factory(bindings,cat,0,[81,86],context,int(expected.seed)),"Earlier binding inferred accepted-job traffic")
			continue
		if not owner.configure_free_factory(bindings,cat,0,[81,86],context,int(expected.seed)):check(false,owner.error);return
		var incoming:={"state":int(expected.get("incoming",12345))}
		var actual:=owner.generate(incoming)
		if actual.is_empty():check(false,owner.error);return
		check(actual.actors.size()==expected.actors.size(),"Delivery actor count differs from the source ledger")
		check(actual.random_state.state==int(expected.random_state),"Delivery factory draw order differs from the independent ledger")
		check(actual.population.before_actors_random_state.state==int(expected.before_actors),"Contract population reseed or draw order changed")
		check(actual.population.hostile_faction==int(expected.hostile_faction) and actual.population.hostile_selected==bool(expected.hostile_selected),"Delivery population changed shared faction selection")
		for group in expected.groups:check(actual.population.groups[group]==int(expected.groups[group]),"Contract population group changed: "+group)
		for id in actual.actors.size():
			var actor: Dictionary=actual.actors[id];var wanted: Dictionary=expected.actors[id]
			check(actor.population_group==wanted.group and actor.actor_kind==int(wanted.faction) and actor.hull_catalogue_id==int(wanted.hull),"Delivery group order, faction or per-actor hull differs")
			check(actor.body_pose.origin==point(wanted.position) and actor.statistics_pose==actor.body_pose,"Delivery relative position or float32 order differs")
			var cargo:=[]
			for item in wanted.cargo:cargo.append({"item_id":int(item[0]),"quantity":int(item[1])})
			check(actor.cargo==cargo,"Delivery factory lost original generated cargo")
			if actor.population_group!="freighter":check(actor.route.waypoints==wanted.route.map(point),"Delivery factory changed its original generated route")
		check(not FreeTraffic.population(bindings,actual,context.rank,context.difficulty).is_empty(),"Generated delivery population failed native combat validation")
		var standing:=preload("res://src/simulation/faction_reputation.gd").new()
		check(standing.configure(bindings,18,actual.actors.map(func(actor):return actor.actor_kind),context.difficulty),standing.error)
		check(standing.restore(bindings,standing.snapshot()),"Delivery faction ledger failed exact restore")
		var accounting:=preload("res://src/simulation/npc_death_accounting.gd").new()
		check(accounting.configure_ambient(bindings,owner),accounting.error)
		check(accounting.snapshot().get("spawn_generations",[-1]).size()==actual.actors.size(),"Delivery world lost its complete traffic-generation ledger")
		check(accounting.fork_for_frame().snapshot()==accounting.snapshot(),"Delivery accounting changed across frame copies")
		var world:=World.new()
		if not world.configure_free_factory(bindings,cat,0,[81,86],context,int(expected.seed),{"companions_empty":true,"location_match":false,"special_placement":false}):check(false,world.error);return
		var initialized:=world.generate(incoming)
		if initialized.is_empty():check(false,world.error);return
		check(initialized.npc_construction==actual,"Delivery world changed its factory inputs")
		var stream:=Random.new();stream.restore(actual.random_state)
		for actor in actual.actors:
			var effect: Dictionary=initialized.weapon_effects[actor.actor_id]
			if actor.population_group=="freighter":continue
			for item in [effect.discarded_default,effect.primary]:
				var flips:=[]
				for slot in 4:flips.append(stream.next_int(2)==0)
				check(item.flipped==flips,"Delivery weapon setup lost post-construction draw order")
			if actor.population_group=="delivery_pirate":check(effect.primary.item_id==19,"Delivery pirate received another faction's weapon")
		check(initialized.random_state==stream.snapshot(),"Delivery world changed its final random stream")
		if expected.delivery.selected:
			check(actual.actors==[] and not actual.population.has("unix_seconds") and actual.population.incoming_random_state==incoming,"Active courier inferred ordinary traffic or reseeded")
			var weapons:=Weapons.new()
			check(weapons.configure_ambient(bindings,cat,owner,context.rank,context.difficulty),weapons.error)
			check(not Life.guidance(bindings,actual,context.rank,context.difficulty).is_empty(),"Active courier lost its zero-ship guidance context")
		elif int(expected.delivery.difficulty)==9:verify_live_setup(bindings,cat,owner,expected)
		for patch in [{"side_missions_empty":true},{"mission_story":true},{"player_position":Vector3(NAN,0,0)},{"side_mission":{}},{"mission_completed":not context.mission_completed}]:
			var invalid:=context.duplicate(true);invalid.merge(patch,true)
			check(not Population.new().configure_free(bindings,cat,invalid,1),"Malformed delivery context generated traffic")
		var missing:=context.duplicate(true);missing.erase("player_position")
		check(not Population.new().configure_free(bindings,cat,missing,1),"Delivery pirates inferred the player's position")
		for patch in [{"kind":4},{"kind":15},{"kind":false},{"difficulty":0},{"difficulty":10},{"station_id":56}]:
			var invalid:=context.duplicate(true);invalid.side_mission.merge(patch,true)
			check(not Population.new().configure_free(bindings,cat,invalid,1),"An unsupported job, difficulty or destination entered delivery construction")
		check(owner.generate(incoming).is_empty() and owner.snapshot()==actual,"Delivery factory generated twice")
		if failures>0:return
