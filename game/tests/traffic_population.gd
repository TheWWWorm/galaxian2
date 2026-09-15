extends SceneTree
## Population rules only. No mission, earned save, or actor-motion claim.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Population=preload("res://src/simulation/traffic_population.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const CONTEXT={"system_id":15,"station_id":79,"campaign_cursor":11,"difficulty":0.5,
	"mission_kind":-1,"mission_completed":true,"mission_story":false,"companions_empty":true,"station_response":false}
# Independently calculated integer vectors include fallback, maximum population,
# no patrol, freighters alone, and the supported maximum Unix seed.
const VECTORS=[
	[0,1,1,3,Vector3(8719,2854,41077),93792642996822],
	[1,2,0,4,Vector3(9978,-8252,46569),1721836393473],
	[2,1,0,0,Vector3(9847,5068,30094),277934256203520],
	[1789100000,1,1,1,Vector3(-9287,-691,27021),156528413463542],
	[2147483647,0,1,0,Vector3(-5483,5515,30112),201390832006047],
	[55,4,0,0,Vector3(7119,-4526,47306),33297177797127],
	[22,3,1,4,Vector3(9321,-5299,49602),256884028601084],
	[23,0,0,3,Vector3(-9419,3595,25094),164813221997735],
]
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit content, bindings and visuals")
	if args.size()==3:verify(args)
	print("Traffic population: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest):
		check(false,library.error+bindings.error);return
	if bindings.ambient_population.is_empty():
		check(not Population.new().configure(bindings,CONTEXT,0),"Earlier content invented the mixed population")
		verify_legacy(bindings);return
	for vector in VECTORS:
		var population:=Population.new()
		if not population.configure(bindings,CONTEXT,vector[0]):check(false,population.error);return
		check(population.generate({"state":-1}).is_empty() and population.snapshot().is_empty(),"Invalid scenery stream committed population")
		var state:=population.generate({"state":12345})
		if state.is_empty():check(false,population.error);return
		check(state.groups=={"patrol":vector[1],"travel":vector[2],"freighter":vector[3]},"Population groups differ from the source count vector")
		check(state.actor_count==vector[1]+vector[2]+vector[3],"Population omitted a non-patrol group")
		check(state.spawn_center==vector[4] and state.before_actors_random_state=={"state":vector[5]},"Population lost a draw or changed its spawn region")
		check(state.station_id==79 and state.campaign_cursor==11 and state.binding_id==bindings.binding_id,"Population lost its exact source context")
		var second:=Population.new();second.configure(bindings,CONTEXT,vector[0])
		check(second.generate({"state":9999})==state,"Population failed to reseed after the scenery stream")
		check(population.generate({"state":0}).is_empty() and population.snapshot()==state,"Population regenerated after committing")
		state.groups.patrol=99
		check(population.snapshot().groups.patrol!=99,"Caller mutated the retained population")
	for key in CONTEXT:
		var changed:=CONTEXT.duplicate();changed.erase(key)
		check(not Population.new().configure(bindings,changed,0),"Population accepted omitted context: "+key)
	for changed in [{"system_id":14},{"station_id":76},{"station_id":78},{"campaign_cursor":10},{"campaign_cursor":12},
		{"mission_kind":11},{"mission_completed":false},{"mission_story":true},{"companions_empty":false},{"station_response":true},
		{"difficulty":1.5},{"difficulty":NAN},{"difficulty":true}]:
		var context:=CONTEXT.duplicate();context.merge(changed,true)
		check(not Population.new().configure(bindings,context,0),"Population accepted an unsupported world override")
	for seconds in [-1,2147483648,1.5,true]:
		check(not Population.new().configure(bindings,CONTEXT,seconds),"Population accepted an invalid Unix seed")
	var standard:=CONTEXT.duplicate();standard.difficulty=1.0
	check(Population.new().configure(bindings,standard,0),"Population rejected supported standard difficulty")
	verify_legacy(bindings)

func verify_legacy(bindings: RefCounted) -> void:
	for vector in [[0,1,Vector3(-8947,4491,39761),32934430199125],[1,4,Vector3(4904,-5566,36606),185454638771764],
		[2,4,Vector3(3350,4606,39719),9368989764503],[1789100000,1,Vector3(-9174,1702,42590),45061582439541]]:
		var random:=Random.new();random.seed_from(555)
		var data: Dictionary=bindings.mido_travel.departure_traffic.duplicate(true);data.unix_seconds=vector[0]
		var legacy:=Population.first_departure(data,random)
		check(legacy.actor_count==vector[1] and legacy.spawn_center==vector[2] and legacy.before_actors_random_state.state==vector[3],"Shared sampler changed the supported Var Hastra population")
		check(random.snapshot()==legacy.before_actors_random_state and not legacy.has("groups"),"Shared sampler changed the old constructor's state contract")
		if not bindings.ambient_population.is_empty():
			var context:=CONTEXT.duplicate();context.station_id=78;context.campaign_cursor=10
			var population:=Population.new();population.configure(bindings,context,vector[0])
			var common:=population.generate({"state":1})
			for key in legacy:check(common.get(key)==legacy[key],"Old and new population owners disagree on "+key)
			check(common.groups.travel==0 and common.groups.freighter==0,"Var Hastra invented extra traffic")

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
