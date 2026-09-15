extends SceneTree
## Detached factory input vectors. No mission, station save or earned progress is
## created; actual departure permission belongs to the session integration tests.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Definitions=preload("res://src/content/free_population_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Population=preload("res://src/simulation/traffic_population.gd")
const World=preload("res://src/simulation/opening_world_initialization.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Routes=preload("res://src/simulation/npc_route.gd")
const Factory=preload("res://src/simulation/opening_npc_construction.gd")
const CONTEXT={"system_id":19,"station_id":98,"campaign_cursor":18,"difficulty":0.5,"rank":0,
	"mission_kind":-1,"mission_completed":true,"mission_story":false,"companions_empty":true,
	"side_missions_empty":true,"station_response":false,"special_arrival":false,"void_encounter":false}
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:verify(args)
	else:check(false,"Expected explicit content, binding and visual paths")
	print("Ordinary population: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	if not Definitions.available(bindings):
		check(not Population.new().configure_free(bindings,cat,CONTEXT,0),"Earlier content inferred ordinary population rules")
		check(not Factory.new().configure_free_factory(bindings,cat,0,[81,86],CONTEXT,0),"Earlier content inferred ordinary factories")
		return
	var file:=FileAccess.open(OS.get_environment("GOF2_FREE_POPULATION_VECTORS"),FileAccess.READ)
	if file==null or file.get_length()>2*1024*1024:check(false,"Supply independent private factory vectors");return
	var vectors: Variant=JSON.parse_string(file.get_as_text());file.close()
	if not vectors is Array or vectors.size()!=27:check(false,"Expected the independent boundary vectors");return
	var observed:={}
	for expected in vectors:
		var context:=CONTEXT.duplicate();context.rank=int(expected.rank);context.difficulty=float(expected.difficulty)
		var population:=Population.new()
		if not population.configure_free(bindings,cat,context,int(expected.seed)):check(false,population.error);return
		check(population.generate({"state":-1}).is_empty() and population.snapshot().is_empty(),"Invalid scenery stream generated ordinary traffic")
		var selected:=population.generate({"state":98765})
		if selected.is_empty():check(false,population.error);return
		for key in expected.groups:check(int(selected.groups[key])==int(expected.groups[key]),"Population count differs: %s/%d/%s"%[key,expected.seed,expected.difficulty])
		check(selected.hostile_selected==expected.hostile_selected and selected.hostile_faction==int(expected.hostile_faction),"Hostile choice or source faction changed")
		check(selected.spawn_center==point(expected.center) and selected.unused_route_origin==point(expected.hostile_origin),"Population changed its source spawn region")
		check(selected.before_actors_random_state.state==int(expected.before_actors),"Ordinary count draws differ from the independent stream")
		check(not selected.has("count_draw") and selected.security==3 and selected.system_faction==0,"Augmenta retained an early Mido count draw or wrong catalogue field")
		var owner:=Factory.new()
		if not owner.configure_free_factory(bindings,cat,0,[81,86],context,int(expected.seed)):check(false,owner.error);return
		var actual:=owner.generate({"state":12345})
		if actual.is_empty():check(false,owner.error);return
		check(actual.actors.size()==expected.actors.size(),"Factory lost an ordinary population group")
		check(actual.random_state.state==int(expected.random_state),"Factory draw ledger differs for seed%d/difficulty%s/rank%d"%[expected.seed,expected.difficulty,expected.rank])
		check(actual.population==selected,"Factory changed the independently verified count sampler")
		var world:=World.new()
		if not world.configure_free_factory(bindings,cat,0,[81,86],context,int(expected.seed),{"companions_empty":true,"location_match":false,"special_placement":false}):check(false,world.error);return
		var populated:=world.generate({"state":12345})
		if populated.is_empty():check(false,world.error);return
		check(populated.npc_construction==actual,"World initialization changed ordinary constructor inputs")
		var stream:=Random.new();stream.restore({"state":int(expected.random_state)})
		for id in actual.actors.size():
			var actor: Dictionary=actual.actors[id];var effects: Dictionary=populated.weapon_effects[id]
			if actor.population_group=="freighter":check(effects=={"actor_id":id,"unarmed":true},"Ordinary freighter received an armed pool");continue
			var source: Dictionary=bindings.early_contracts.ship_combat.weapons.factions.filter(func(row):return int(row.actor_kind)==actor.actor_kind)[0]
			check(effects.discarded_default.item_id==0 and effects.primary.item_id==int(source.item_id),"Ordinary ship received another faction's weapon")
			for effect in [effects.discarded_default,effects.primary]:
				var flips:=[]
				for slot in 4:flips.append(stream.next_int(2)==0)
				check(effect.flipped==flips,"Weapon effects consumed an out-of-order draw")
		check(populated.random_state==stream.snapshot(),"World initialization changed its final RNG")
		var hostile_hull:=-1
		for id in actual.actors.size():
			var actor: Dictionary=actual.actors[id];var wanted: Dictionary=expected.actors[id]
			check(actor.actor_id==id and actor.population_group==wanted.group and actor.actor_kind==int(wanted.faction) and actor.hull_catalogue_id==int(wanted.hull),"Factory changed group order, faction or hull")
			check(actor.body_pose.origin==point(wanted.position) and actor.statistics_pose==actor.body_pose,"Factory changed source placement")
			var cargo:=[]
			for item in wanted.cargo:cargo.append({"item_id":int(item[0]),"quantity":int(item[1])})
			check(actor.cargo==cargo and actor.discarded_cargo.is_empty(),"Factory changed retained cargo")
			if wanted.group=="freighter":
				observed["freighter"+str(int(wanted.faction))]=true
				check(actor.subtype==1 and actor.fragments.is_empty() and actor.route.is_empty() and owner.route(id)==null,"Freighter acquired a small-ship route or debris")
				check(actor.world_flag and actor.model_assembly_required and actor.assembly==bindings.mido_travel.free_population.freighter_assemblies[str(int(wanted.faction))],"Freighter lost its source model assembly")
			else:
				check(actor.subtype==0 and actor.route.waypoints==wanted.route.map(point) and owner.route(id).snapshot()==actor.route,"Small ship route differs from its draw ledger")
				if wanted.group=="travel":check(actor.flight_mode==4 and actor.travel_flag and not actor.route.loop,"Travel ship lost its destination and initial mode")
				if wanted.group=="hostile":
					observed["hostile"+str(int(wanted.faction))]=true
					if hostile_hull<0:hostile_hull=actor.hull_catalogue_id
					check(hostile_hull==actor.hull_catalogue_id and actor.route.loop,"Hostile group drew individual hulls or discarded its patrol route")
		verify_live_setup(bindings,cat,owner,expected)
		check(owner.generate({"state":1}).is_empty() and owner.snapshot()==actual,"A committed factory generated twice")
		check(population.generate({"state":1}).is_empty() and population.snapshot()==selected,"A committed population generated twice")
		actual.actors.clear();selected.groups.patrol=-1
		check(not owner.snapshot().actors.is_empty() and population.snapshot().groups.patrol>=3,"Snapshots alias committed construction")
	for key in ["freighter0","freighter2","hostile1","hostile8"]:check(observed.has(key),"The vectors omitted source faction branch "+key)
	for key in CONTEXT:
		var changed:=CONTEXT.duplicate();changed.erase(key)
		check(not Population.new().configure_free(bindings,cat,changed,0),"An omitted source input was inferred: "+key)
	for patch in [{"rank":-1},{"rank":21},{"difficulty":1.5},{"difficulty":NAN},{"difficulty":true},{"system_id":15},{"station_id":56},{"campaign_cursor":17},{"mission_kind":156},{"mission_completed":false},{"mission_story":true},{"companions_empty":false},{"side_missions_empty":false},{"station_response":true},{"special_arrival":true},{"void_encounter":true}]:
		var changed:=CONTEXT.duplicate();changed.merge(patch,true)
		check(not Population.new().configure_free(bindings,cat,changed,0),"Unsupported encounter context produced ordinary traffic")
	for invalid in [{},{"campaign_cursor":18,"rank":-1,"difficulty":0.5},{"campaign_cursor":17,"rank":0,"difficulty":0.5},{"campaign_cursor":18,"rank":0,"difficulty":NAN}]:check(not Routes.new().configure_free_generated(bindings,0,invalid),"Invalid route context was accepted")
	for seconds in [-1,2147483648,0.5,true]:check(not Population.new().configure_free(bindings,cat,CONTEXT,seconds),"Invalid Unix seed was accepted")
	for station in [95,96,97,98,99]:
		var changed:=CONTEXT.duplicate();changed.station_id=station
		check(Population.new().configure_free(bindings,cat,changed,0),"A source Augmenta location lost ordinary population")
	check(not Factory.new().configure_free_traffic(bindings,cat,null,CONTEXT,0),"The session adapter accepted absent retained equipment")
	check(not Factory.new().configure_free_factory(bindings,cat,-1,[],CONTEXT,0),"Unknown player hull was accepted")
	check(not Factory.new().configure_free_factory(bindings,cat,0,[-1],CONTEXT,0),"Unknown installed equipment was accepted")
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	for key in Definitions.SPANS:
		var broken: Dictionary=bindings.mido_travel.duplicate(true);broken.provenance.erase(key)
		check(not Travel.validate(broken,int(header.source_executable_bytes),"x86_64",bindings.arrival_staging,bindings.station_entry,bindings.combat_training).is_empty(),"Missing population source proof was accepted")

func point(values: Array) -> Vector3:return Vector3(float(values[0]),float(values[1]),float(values[2]))
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)

func verify_live_setup(_bindings: RefCounted,_cat: RefCounted,_owner: RefCounted,_expected: Dictionary) -> void:
	pass
