extends SceneTree
const Population = preload("res://src/simulation/scenery_population.gd")
const Definitions = preload("res://src/content/scenery_population_definitions.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Library = preload("res://src/content/library.gd")
var failures := 0
var vectors: Array

func _initialize() -> void:
	vectors=JSON.parse_string(FileAccess.get_file_as_string("res://tests/scenery_population_vectors.json"))
	check_synthetic()
	var args := OS.get_cmdline_user_args()
	check(args.size()%3==0,"Expected content/bindings/visual triples")
	for index in range(0,args.size()-2,3):check_profile(args[index],args[index+1])
	print("Scenery population: %d failures" % failures)
	quit(1 if failures else 0)

func check_synthetic() -> void:
	var owner := Population.new();var bindings := Bindings.new()
	check(owner.for_station(0).is_empty(),"Unconfigured population accepted")
	bindings.base_content_id="a".repeat(64);bindings.binding_id="b".repeat(64)
	bindings.scenery_population={"count_base":17,"count_bound":37,"provenance":{}}
	check(owner.configure(bindings),owner.error)
	check_vectors(owner,17,37)
	var expected: Dictionary = owner.for_station(78)
	bindings.scenery_population.count_base=1000
	check(owner.for_station(78)==expected,"Binding mutation changed configured population")
	expected.random_state.state=0
	check(owner.for_station(78).random_state.state!=0,"Returned state aliases the count owner")
	for bad in [true,null,0.5,"78",-2147483649,2147483648]:
		check(owner.for_station(bad).is_empty(),"Invalid signed station identifier accepted")
	for bad in [null,{}, {"count_base":0,"count_bound":0,"provenance":{}},{"count_base":true,"count_bound":37,"provenance":{}},{"count_base":17,"count_bound":37.5,"provenance":{}},{"count_base":17,"count_bound":37,"provenance":{},"extra":1}]:
		bindings.scenery_population=bad if bad is Dictionary else {}
		check(not owner.configure(bindings) and owner.for_station(78).is_empty(),"Unsupported configuration retained population state")
		check(not Definitions.parameters(bad),"Malformed declaration accepted")
	check(not owner.configure(null),"Missing bindings accepted")

func check_vectors(owner: RefCounted, base: int, bound: int) -> void:
	for vector in vectors:
		if int(vector.base)!=base or int(vector.bound)!=bound:continue
		var result: Dictionary = owner.for_station(int(vector.station_id))
		check(not result.is_empty(),owner.error)
		if result.is_empty():continue
		check(result.count==int(vector.count) and result.random_state.state==int(vector.state),"Station-seeded population differs from bigint reference")
		check(result.count>=base and result.count<base+bound,"Population outside its imported range")
		check(result==owner.for_station(int(vector.station_id)),"Repeat station count depends on previous requests")

func check_profile(content: String, pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var owner := Population.new()
	if not library.open(content) or not bindings.open(pack,library.manifest):
		check(false,library.error+bindings.error);return
	if bindings.scenery_population.is_empty():
		check(not owner.configure(bindings),"Legacy pack invented a scenery count")
		print(library.manifest.profile.edition,": legacy population remains unavailable")
		return
	var base := 40 if library.manifest.profile.edition=="ios-hd" else 80
	check(bindings.scenery_population.count_base==base and bindings.scenery_population.count_bound==base,"Edition-specific population changed")
	check(owner.configure(bindings),owner.error)
	check_vectors(owner,base,base)
	var result: Dictionary = owner.for_station(78)
	check(result.base_content_id==bindings.base_content_id and result.binding_id==bindings.binding_id,"Population lost provenance identity")
	var header: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	var data := bindings.scenery_population.duplicate(true)
	check(Definitions.validate(data,int(header.source_executable_bytes),header.architecture).is_empty(),"Valid provenance rejected")
	for key in data.provenance:
		var bad := data.duplicate(true)
		bad.provenance[key].bytes+=1
		check(not Definitions.validate(bad,int(header.source_executable_bytes),header.architecture).is_empty(),"Malformed proof accepted")
	var overlap := data.duplicate(true)
	overlap.provenance.station.offset=overlap.provenance.count.offset
	check(not Definitions.validate(overlap,int(header.source_executable_bytes),header.architecture).is_empty(),"Overlapping proof accepted")
	check_versions(bindings,library.manifest,pack,header)
	print(library.manifest.profile.edition,": imported range %d–%d, station 78 count %d" % [base,base+base-1,result.count])

func check_versions(bindings: RefCounted, manifest: Dictionary, source: String, header: Dictionary) -> void:
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source.path_join("registrations.json")))
	var directory := "user://tests/scenery-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	check(DirAccess.make_dir_recursive_absolute(directory)==OK,"Cannot create fixture directory")
	# Actual older packs are tested by check_profile. Relabeling today's pack
	# as v40 leaves later capabilities whose prerequisite catalogues v40 lacks.
	for scenario in ["empty","missing","malformed"]:
		var body := original.duplicate(true);var metadata := header.duplicate(true)
		if scenario=="empty":
			body.scenery_population={}
			if body.has("scenery_resources"):body.scenery_resources={}
			if body.has("scenery_effects"):body.scenery_effects={}
		elif scenario=="missing":body.erase("scenery_population")
		else:body.scenery_population.count_bound=false
		var serialized := JSON.stringify(body,"",true,true)
		metadata.records_sha256=serialized.sha256_text();metadata.records_bytes=serialized.to_utf8_buffer().size()
		metadata.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n" % [metadata.base_content_id,metadata.source_executable_sha256,metadata.architecture,metadata.records_sha256]).sha256_text()
		var file := FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE)
		file.store_string(serialized);file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(metadata));file.close()
		check(bindings.open(source,manifest),bindings.error)
		var accepted: bool = bindings.open(directory,manifest)
		if scenario=="empty":
			check(accepted and bindings.scenery_population.is_empty() and not bindings.weapon_parameters.is_empty(),"Compatible scenery scope failed: "+bindings.error)
		else:
			check(not accepted and "scenery" in bindings.error.to_lower(),"Missing/malformed scenery accepted or wrong diagnostic")
			check(bindings.scenery_population.is_empty() and bindings.weapon_parameters.is_empty() and bindings.binding_id.is_empty(),"Failed open retained staged content")
	DirAccess.remove_absolute(directory.path_join("registrations.json"))
	DirAccess.remove_absolute(directory.path_join("bindings.json"))
	DirAccess.remove_absolute(directory)

func check(condition: bool, message: String) -> void:
	if not condition:failures+=1;push_error(message)
