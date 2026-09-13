extends SceneTree
const Field = preload("res://src/simulation/scenery_field.gd")
const Fixture = preload("res://tests/scenery_fixture.gd")
const Generator = preload("res://src/simulation/seeded_random.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Visuals = preload("res://src/content/visual_library.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Geometry = preload("res://src/presentation/scenery_geometry.gd")
var failures := 0

func _initialize() -> void:
	check_synthetic()
	var args := OS.get_cmdline_user_args()
	check(args.size()%3==0,"Expected content/bindings/visual triples")
	for index in range(0,args.size()-2,3):check_profile(args[index],args[index+1],args[index+2])
	print("Scenery field: %d failures" % failures)
	quit(1 if failures else 0)

func check_synthetic() -> void:
	var owner := Field.new()
	check(owner.generate(Vector3.ZERO,{"state":1}).is_empty(),"Unconfigured field accepted")
	var vectors: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/scenery_field_vectors.json"))
	var saw_retry := false;var saw_close := false
	for vector in vectors:
		var data := Fixture.make();var bindings: RefCounted = data[0];var catalogues: RefCounted = data[1]
		if vector.system==22:
			while catalogues.tables.systems.size()<=22:catalogues.tables.systems.append(catalogues.tables.systems[0].duplicate(true))
			catalogues.tables.stations[0].system_id=22
		check(owner.configure(bindings,catalogues,0,vector.location,vector.special,90),owner.error)
		var random := Generator.new();random.seed_from(int(vector.seed));var state := random.snapshot()
		var center := vec(vector.center);var result := owner.generate(center,state)
		check(not result.is_empty(),owner.error)
		if result.is_empty():continue
		check(result==owner.generate(center,state),"Field depends on hidden RNG state")
		check(result.objects.size()==vector.objects.size() and result.large_count==int(vector.large_count) and result.random_state.state==int(vector.state) and result.ore_cursor==int(vector.ore_cursor),"Field count or shared construction stream differs from reference")
		for index in mini(result.objects.size(),vector.objects.size()):
			var actual: Dictionary = result.objects[index];var expected: Dictionary = vector.objects[index]
			for key in ["index","item_id","model_variant","model_id","large","source_size_value","position_attempts","ore_draws"]:
				check(actual[key]==expected[key],"Seed %d row %d %s differs" % [vector.seed,index,key])
			for key in ["position","angles","construction_axis","spin"]:
				check(actual[key]==vec(expected[key]),"Seed %d row %d %s float32 values differ" % [vector.seed,index,key])
			check(actual.scale==Field.f32(float(expected.scale)),"Source scale rounding differs")
			check(actual.basis.is_equal_approx(Basis.from_euler(actual.angles,EULER_ORDER_XYZ)),"Initial scenery rotation order differs")
			saw_retry=saw_retry or actual.position_attempts>1
			if actual.large and index>1:
				for previous in result.objects.slice(0,index):
					if Field.source_distance(actual.position,previous.position)<=8000:saw_close=true
		var saved := result.duplicate(true)
		bindings.scenery_resources.model_ids[0]=999;catalogues.tables.stations[0].system_id=999
		result.objects[0].position=Vector3.INF;result.random_state.state=0
		check(owner.generate(center,state)==saved,"Field aliases input declarations or returned state")
	check(saw_retry and saw_close,"Reference cases did not exercise retry and ANY-predecessor spacing")
	for center in [null,{},Vector3.INF,Vector3(NAN,0,0),Vector3(100000016.0,0,0)]:
		check(owner.generate(center,{"state":1}).is_empty(),"Invalid center accepted")
	for state in [null,{},true,{"state":-1},{"state":281474976710656}]:check(owner.generate(Vector3.ZERO,state).is_empty(),"Invalid construction RNG accepted")
	var data := Fixture.make();data[0].scenery_population={}
	check(not owner.configure(data[0],data[1],0,false,false,0) and owner.generate(Vector3.ZERO,{"state":1}).is_empty(),"Failed configuration retained a usable field")
	check(Field.source_distance(Vector3.ZERO,Vector3(8000,1,0))==8000 and Field.source_distance(Vector3.ZERO,Vector3(8001,0,0))==8001,"Spacing must compare truncated source distance")

func check_profile(content: String, pack: String, textures: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var visuals := Visuals.new();var catalogues := Catalogues.new();var owner := Field.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not catalogues.open(library) or not visuals.open(textures,library.manifest):
		check(false,library.error+bindings.error+catalogues.error+visuals.error);return
	if bindings.scenery_resources.is_empty():
		check(not owner.configure(bindings,catalogues,78,false,false,0),"Legacy field invented resource declarations")
		print(library.manifest.profile.edition,": legacy field unavailable");return
	var special_station := -1
	for station in catalogues.tables.stations:
		if int(station.system_id)==22:special_station=int(station.id);break
	check(special_station>=0,"System 22 fixture station unavailable")
	for variant in 4:
		var station := special_station if variant==2 else 78
		check(owner.configure(bindings,catalogues,station,variant==1,variant==3,90),owner.error)
		var random := Generator.new();random.seed_from(1789100000)
		var field := owner.generate(Vector3.ZERO,random.snapshot())
		check(not field.is_empty(),owner.error)
		if field.is_empty():continue
		var geometry := Geometry.new()
		check(geometry.build(field,library,visuals,bindings),geometry.error)
		check(geometry.objects.size()==field.objects.size(),"Source field model count differs")
		for index in geometry.objects.size():
			var node: Node3D = geometry.objects[index];var row: Dictionary = field.objects[index]
			check(row.model_variant==variant and node.position==row.position and node.transform.basis.is_equal_approx(row.basis.scaled(Vector3.ONE*row.scale)),"Source model alternative or pose differs")
		if geometry.objects.size()>1:
			var first: Node3D = geometry.objects[0];var second: Node3D = geometry.objects[1]
			check(first.instances[0].mesh==second.instances[0].mesh and first.materials[0]!=second.materials[0],"Scenery must share meshes and keep independent materials")
		for scenario in ["position","basis","scale","alternative"]:
			var bad_pose := field.duplicate(true)
			if scenario=="position":bad_pose.objects[0].position=Vector3(NAN,0,0)
			elif scenario=="basis":bad_pose.objects[0].basis=Basis.IDENTITY.scaled(Vector3(2,1,1))
			elif scenario=="scale":bad_pose.objects[0].scale=0.0
			else:bad_pose.objects[0].model_variant=4
			check(not geometry.build(bad_pose,library,visuals,bindings) and geometry.objects.is_empty(),"Malformed pose accepted: "+scenario)
		var malformed := field.duplicate(true);malformed.objects[0].model_id=-1
		check(not geometry.build(malformed,library,visuals,bindings) and geometry.objects.is_empty() and geometry.get_child_count()==0,"Invalid rebuild retained scenery")
		malformed=field.duplicate(true);malformed.binding_id="f".repeat(64)
		check(not geometry.build(malformed,library,visuals,bindings),"Cross-binding field accepted")
		geometry.free()
	print(library.manifest.profile.edition,": four field alternatives generated and assembled, including identity-keyed magma")

func vec(values: Array) -> Vector3:
	return Vector3(values[0],values[1],values[2])

func check(condition: bool, message: String) -> void:
	if not condition:failures+=1;push_error(message)
