extends SceneTree
const Construction = preload("res://src/simulation/opening_npc_construction.gd")
const Definitions = preload("res://src/content/npc_construction_definitions.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Library = preload("res://src/content/library.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Vitals = preload("res://src/simulation/combat_vitals.gd")
const NpcControl = preload("res://src/simulation/opening_npc_control.gd")
const Random = preload("res://src/simulation/seeded_random.gd")
var failures := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Pass content/bindings/visuals triples")
	for i in range(0,args.size()-2,3): check_profile(args[i],args[i+1])
	print("Opening NPC construction checks: %d failures" % failures)
	quit(1 if failures else 0)

func check_profile(content: String, bindings_path: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new()
	if not library.open(content) or not bindings.open(bindings_path,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error)
		return
	var owner := Construction.new()
	var data: Dictionary = bindings.opening_actors.npc_initialization.get("construction",{})
	if data.is_empty():
		check(not owner.configure(bindings,catalogues) and owner.snapshot().is_empty(),"Legacy pack invented NPC construction")
		return
	var arch := "armv7" if library.manifest.profile.edition=="ios-hd" else "x86_64"
	var extent := 0
	for span in data.provenance.values(): extent=maxi(extent,int(span.offset)+int(span.bytes))
	check(Definitions.validate(data,extent,arch).is_empty(),"Construction provenance rejected")
	for key in data:
		var bad := data.duplicate(true);bad.erase(key)
		check(not Definitions.parameters(bad),"Incomplete construction accepted: "+key)
	for key in data.provenance:
		var bad := data.duplicate(true);bad.provenance[key].bytes+=1
		check(not Definitions.validate(bad,extent,arch).is_empty(),"Changed provenance accepted: "+key)
	for bad_value in [true,null,NAN,INF,0.5]:
		var bad := data.duplicate(true);bad.spawn_origin[0]=bad_value
		check(not Definitions.parameters(bad),"Invalid construction coordinate accepted")
	var original_items: Array=catalogues.tables.items.duplicate(true)
	for fixture in FIXTURES:
		catalogues.tables.items=original_items.duplicate(true)
		if fixture.restricted:
			for item in catalogues.tables.items: item.arrays[0]=[1]
		if not owner.configure(bindings,catalogues):
			check(false,owner.error)
			continue
		var empty: Dictionary=owner.snapshot()
		check(owner.route(0)==null,"Ungenerated route escaped")
		for state in [{},{"state":-1},{"state":281474976710656},{"state":true}]:
			check(owner.generate(state).is_empty() and owner.snapshot()==empty,"Invalid RNG partly constructed NPCs")
		var input := {"state":fixture.input_state}
		var result := owner.generate(input)
		if result.is_empty():
			check(false,owner.error)
			continue
		check(input.state==fixture.input_state and result.random_state.state==fixture.state,"Shared constructor RNG order changed")
		for id in 3:
			var actual: Dictionary=result.actors[id];var expected: Dictionary=fixture.actors[id]
			check(actual.actor_id==id and actual.cargo.is_empty(),"Opening cargo discard or population changed")
			check(actual.factory_position==vector(expected.position),"Factory XYZ draw order changed")
			check(actual.discarded_cargo==expected.discarded,"Cargo filtering/quantity/fallback changed")
			check(actual.route.candidate_indices==expected.indices,"Route selection received wrong constructor RNG")
			for point in expected.waypoints.size():check(actual.route.waypoints[point]==vector(expected.waypoints[point]),"Route coordinates received wrong constructor RNG")
			check(actual.fragments.size()==expected.count,"Fragment count changed")
			check_fragment(actual.fragments[0],expected.first_fragment)
			check_fragment(actual.fragments[-1],expected.last_fragment)
			var detached: RefCounted=owner.route(id)
			check(detached!=null and detached.snapshot()==actual.route,"Constructor route handoff differs")
			if detached!=null:detached.advance(actual.route.waypoints[0])
			check(owner.route(id).snapshot()==actual.route,"Handed off route aliases constructor")
		var saved: Dictionary=owner.snapshot()
		check(owner.generate(input).is_empty() and owner.snapshot()==saved,"Constructor regenerated NPCs")
		result.actors[0].fragments.clear();result.actors[1].route.waypoints.clear();result.random_state.state=0
		check(owner.snapshot()==saved,"Constructor snapshot aliases its owner")
	check_excluded_cargo(bindings,catalogues,original_items)
	catalogues.tables.items=original_items.duplicate(true)
	check(owner.configure(bindings,catalogues),owner.error)
	check(not owner.generate({"state":280936762154123}).is_empty(),owner.error)
	var controller := NpcControl.new()
	check(controller.configure(bindings,catalogues,0.5),controller.error)
	for id in 3:check(controller.set_initial_route(id,owner.route(id)),controller.error)
	var previous := catalogues.content_id;catalogues.content_id="0".repeat(64)
	check(not owner.configure(bindings,catalogues) and owner.snapshot().is_empty(),"Cross-content construction accepted")
	catalogues.content_id=previous
	catalogues.tables.items[232].arrays[2][3]=99
	check(not owner.configure(bindings,catalogues) and owner.snapshot().is_empty(),"Late invalid cargo record partly configured")
	catalogues.tables.items=original_items.duplicate(true)
	catalogues.tables.items[54].arrays[2][5]=18
	check(not owner.configure(bindings,catalogues),"Special cargo predicate entered unsupported fresh scope")
	print(library.manifest.profile.edition,": shared construction stream, route handoff, cargo discard and fragment records verified")

func check_excluded_cargo(bindings: RefCounted, catalogues: RefCounted, original: Array) -> void:
	# Only forbidden IDs have a positive price. The independent seed-zero
	# fixture encounters 217, 175 and 218, then exhausts all 100 attempts.
	catalogues.tables.items=original.duplicate(true)
	for item in catalogues.tables.items:
		item.arrays[0]=[];item.arrays[2][13]=100;item.arrays[2][15]=0;item.arrays[2][17]=0
	for id in [164,175,217,218]:
		var item: Dictionary=catalogues.tables.items[id]
		item.arrays[2][3]=4;item.arrays[2][15]=100;item.arrays[2][17]=100
	var owner := Construction.new();var random := Random.new()
	check(owner.configure(bindings,catalogues),owner.error)
	random.seed_from(0)
	check(owner._sample_cargo(random)==[{"item_id":159,"quantity":6}],"Excluded cargo ID escaped through JSON numeric membership")
	check(random.snapshot().state==238479845105265,"Excluded candidate rejection did not preserve RNG draws")

func vector(values: Array) -> Vector3:
	return Vector3(values[0],values[1],values[2])

func check_fragment(actual: Dictionary, expected: Array) -> void:
	var rotation := Vector3.ZERO
	for axis in 3:rotation[axis]=Vitals.single(Vitals.single(float(expected[axis])/180.0)*3.1415927410125732)
	check(actual.resource_id==14292 and actual.rotation_radians==rotation and actual.scale==Vitals.single(float(expected[3])/100.0),"Fragment axis order or source float conversion changed")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures+=1
		push_error(message)

const FIXTURES = [
	{"input_state":25214903917,"state":5646331179885,"restricted":false,"actors":[
		{"position":[1360,5948,8029],"indices":[3,0,1,2],"waypoints":[[-17527,-5738,61095],[-13553,-6485,26053],[9491,-239,38719],[12854,-8923,62677]],"discarded":[{"item_id":124,"quantity":3}],"count":6,"first_fragment":[195,200,295,55],"last_fragment":[187,107,268,55]},
		{"position":[-14742,17408,6517],"indices":[3,2,0],"waypoints":[[-17420,-7703,63662],[21457,-1449,56726],[-16549,-8282,39358]],"discarded":[{"item_id":102,"quantity":1}],"count":4,"first_fragment":[45,239,293,67],"last_fragment":[61,37,277,86]},
		{"position":[-19359,-1710,-9849],"indices":[1,2],"waypoints":[[16865,-3014,24004],[5984,-7238,61792]],"discarded":[{"item_id":140,"quantity":6}],"count":6,"first_fragment":[312,345,105,63],"last_fragment":[314,248,89,88]},
	]},
	{"input_state":25214903916,"state":209487643708223,"restricted":false,"actors":[
		{"position":[8985,-15412,-18153],"indices":[3,1,0],"waypoints":[[-14683,-8737,75562],[9434,-3394,34978],[-9687,-5746,34904]],"discarded":[{"item_id":109,"quantity":8},{"item_id":118,"quantity":3}],"count":7,"first_fragment":[0,151,286,83],"last_fragment":[165,29,299,95]},
		{"position":[-15241,-19190,-5383],"indices":[1,0,2],"waypoints":[[13053,-1175,37101],[-6474,-7626,20620],[20601,-4564,71650]],"discarded":[{"item_id":125,"quantity":9}],"count":5,"first_fragment":[46,137,185,50],"last_fragment":[231,110,25,95]},
		{"position":[-18144,-15136,-13709],"indices":[3,2,0,1],"waypoints":[[-20905,-8108,66463],[18863,-3410,67679],[-5984,-4564,25288],[17028,-8489,34362]],"discarded":[{"item_id":69,"quantity":2},{"item_id":133,"quantity":5}],"count":4,"first_fragment":[7,243,138,52],"last_fragment":[219,28,338,83]},
	]},
	{"input_state":25214903934,"state":247468946317445,"restricted":false,"actors":[
		{"position":[-8275,1644,-15944],"indices":[2,3],"waypoints":[[8022,-520,60504],[-29389,-3928,56514]],"discarded":[{"item_id":150,"quantity":5}],"count":9,"first_fragment":[289,68,284,93],"last_fragment":[203,191,301,66]},
		{"position":[3512,1339,-8515],"indices":[1,2],"waypoints":[[16294,-9872,24449],[26895,-3159,67741]],"discarded":[{"item_id":123,"quantity":4},{"item_id":108,"quantity":4}],"count":7,"first_fragment":[210,303,33,71],"last_fragment":[80,169,90,73]},
		{"position":[1224,-9720,2126],"indices":[1,3,2],"waypoints":[[21000,-8405,29978],[-23305,-1892,72899],[29833,-6282,61573]],"discarded":[{"item_id":153,"quantity":2}],"count":3,"first_fragment":[20,78,194,76],"last_fragment":[199,272,174,75]},
	]},
	{"input_state":24499952013,"state":194052657704714,"restricted":false,"actors":[
		{"position":[16714,-8199,-3085],"indices":[3,2],"waypoints":[[-24259,-5950,64978],[19309,-2979,76084]],"discarded":[],"count":4,"first_fragment":[178,102,294,94],"last_fragment":[314,214,233,60]},
		{"position":[-8815,-14547,12271],"indices":[0,2],"waypoints":[[-18930,-4063,26774],[16064,-5719,74195]],"discarded":[{"item_id":162,"quantity":8},{"item_id":149,"quantity":6}],"count":4,"first_fragment":[145,192,56,94],"last_fragment":[228,308,146,58]},
		{"position":[2821,672,-13156],"indices":[3,2],"waypoints":[[-5604,-506,72402],[14548,-7376,64969]],"discarded":[{"item_id":134,"quantity":1},{"item_id":158,"quantity":9}],"count":7,"first_fragment":[263,287,299,75],"last_fragment":[151,247,65,85]},
	]},
	{"input_state":280936762154123,"state":140974702666229,"restricted":false,"actors":[
		{"position":[704,5566,3393],"indices":[0,1,2,3],"waypoints":[[-8751,-4631,44913],[15734,-6284,34796],[19883,-4737,77313],[-6418,-131,78579]],"discarded":[{"item_id":125,"quantity":8}],"count":5,"first_fragment":[166,125,241,61],"last_fragment":[313,235,124,70]},
		{"position":[9429,12580,17450],"indices":[1,2,0],"waypoints":[[13972,-1172,22537],[10044,-760,56829],[-25744,-9091,36735]],"discarded":[],"count":6,"first_fragment":[166,10,82,50],"last_fragment":[122,326,324,75]},
		{"position":[4046,-4160,18814],"indices":[3,2],"waypoints":[[-10933,-7161,62899],[14470,-9102,58656]],"discarded":[{"item_id":119,"quantity":3}],"count":4,"first_fragment":[22,147,26,62],"last_fragment":[314,256,255,75]},
	]},
	{"input_state":153548941033574,"state":56108864767610,"restricted":false,"actors":[
		{"position":[14720,13852,-11917],"indices":[3,2],"waypoints":[[-22286,-6119,67295],[28952,-5937,64869]],"discarded":[{"item_id":112,"quantity":1},{"item_id":118,"quantity":8}],"count":8,"first_fragment":[113,108,66,93],"last_fragment":[271,285,40,62]},
		{"position":[-11613,-13158,14031],"indices":[3,1,2,0],"waypoints":[[-15055,-8286,62935],[19966,-888,28225],[28918,-5494,64409],[-10526,-7289,29624]],"discarded":[{"item_id":127,"quantity":8}],"count":4,"first_fragment":[2,192,113,73],"last_fragment":[211,336,232,59]},
		{"position":[7509,-19191,-2576],"indices":[0,3],"waypoints":[[-24504,-8257,34128],[-13743,-8002,70270]],"discarded":[{"item_id":126,"quantity":4},{"item_id":44,"quantity":2}],"count":4,"first_fragment":[84,255,23,99],"last_fragment":[178,155,130,66]},
	]},
	{"input_state":25214903934,"state":258056409070031,"restricted":true,"actors":[
		{"position":[-8275,1644,-15944],"indices":[2,3],"waypoints":[[8022,-520,60504],[-29389,-3928,56514]],"discarded":[{"item_id":161,"quantity":2}],"count":5,"first_fragment":[123,183,214,75],"last_fragment":[24,243,187,62]},
		{"position":[3327,-19025,-10691],"indices":[3,2],"waypoints":[[-8840,-6191,63530],[25546,-5145,55315]],"discarded":[{"item_id":156,"quantity":5}],"count":7,"first_fragment":[193,125,334,59],"last_fragment":[40,19,263,83]},
		{"position":[19429,-16728,-2448],"indices":[0,1],"waypoints":[[-14659,-2763,25909],[25271,-4740,44080]],"discarded":[{"item_id":154,"quantity":9}],"count":4,"first_fragment":[198,36,75,66],"last_fragment":[32,264,170,56]},
	]},
]
