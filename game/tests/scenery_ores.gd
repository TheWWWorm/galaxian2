extends SceneTree
const Fixture = preload("res://tests/scenery_fixture.gd")
const Ores = preload("res://src/simulation/scenery_ores.gd")
const Definitions = preload("res://src/content/scenery_resource_definitions.gd")
const Generator = preload("res://src/simulation/seeded_random.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Library = preload("res://src/content/library.gd")
var failures := 0

func _initialize() -> void:
	check_synthetic()
	var args := OS.get_cmdline_user_args()
	check(args.size()%3==0,"Expected content/bindings/visual triples")
	for index in range(0,args.size()-2,3):check_profile(args[index],args[index+1])
	print("Scenery ores: %d failures" % failures)
	quit(1 if failures else 0)


func check_synthetic() -> void:
	var data := Fixture.make();var bindings: RefCounted = data[0];var catalogues: RefCounted = data[1];var owner := Ores.new()
	check(owner.choose({"state":1},0).is_empty(),"Unconfigured ore sampling accepted")
	check(Definitions.parameters(JSON.parse_string(JSON.stringify(bindings.scenery_resources))),"JSON numeric fields changed policy validity")
	check(owner.configure(bindings,catalogues,0,false,false,0),owner.error)
	var snap := owner.snapshot()
	var ids := [0,7,9,1,5,2,4,8,3,6,10];var weights := [100,98,95,89,43,40,38,36,0,0,0]
	for index in ids.size():check(snap.rows[index]=={"item_id":ids[index],"weight":weights[index]},"Distance threshold, stable tie order or rank discount changed")
	var expected: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/scenery_ores_vectors.json"))
	var random := Generator.new();random.seed_from(42);var state := random.snapshot();var cursor := 0
	for vector in expected:
		var result := owner.choose(state,cursor)
		check(not result.is_empty(),owner.error)
		if result.is_empty():break
		check(result.item_id==int(vector.item_id) and result.cursor==int(vector.cursor) and result.draws==int(vector.draws) and result.random_state.state==int(vector.state),"Independent ore/random stream reference differs")
		check(owner.choose(state,cursor)==result,"Sample depends on hidden random or cursor state")
		cursor=result.cursor;state=result.random_state
		# Other scene work may consume this stream between ore selections.
		random.restore(state);random.next_int(60000);state=random.snapshot()
	snap.rows[0].weight=-100;bindings.scenery_resources.weight_base=1;catalogues.tables.systems[0].fields[3]=1000
	check(owner.snapshot().rows[0].weight==100,"Configured ore distribution aliases caller data")
	for bad in [null,true,{}, {"state":-1},{"state":281474976710656}]:check(owner.choose(bad,0).is_empty(),"Invalid random state accepted")
	for bad in [null,true,0.5,-1,6]:check(owner.choose({"state":1},bad).is_empty(),"Invalid cursor accepted")
	data=Fixture.make();bindings=data[0];catalogues=data[1]
	check(owner.configure(bindings,catalogues,0,true,true,90),owner.error)
	check(owner.snapshot().rows[0]=={"item_id":11,"weight":100},"Special flag did not replace distribution IDs")
	var unchanged := {"state":123456}
	var special := owner.choose(unchanged,4)
	check(special.item_id==10 and special.draws==0 and special.cursor==4 and special.random_state==unchanged,"Location branch must bypass sampling and choose its fallback even with the special override")
	check(owner.configure(bindings,catalogues,0,false,true,89),owner.error)
	check(owner.snapshot().rows[0].item_id==0,"Special override ran before its source cursor")
	check(owner.configure(bindings,catalogues,0,false,true,90),owner.error)
	for row in owner.snapshot().rows:check(row.item_id==11,"Special override omitted a ranked row")
	check(owner.choose({"state":123},0).item_id==11,"Special ore was not accepted")
	for bad in [null,{}, {"weight_base":1}]:check(not Definitions.parameters(bad),"Malformed resource policy accepted")
	for scenario in ["identity","context","station","origin","distance","missing"]:
		data=Fixture.make();bindings=data[0];catalogues=data[1]
		var flag: Variant = false;var station: Variant = 0
		if scenario=="identity":catalogues.content_id="c".repeat(64)
		elif scenario=="context":flag=0
		elif scenario=="station":station=true
		elif scenario=="origin":catalogues.tables.items[0].arrays[2][9]=999
		elif scenario=="distance":catalogues.tables.systems[1].fields[3]=2147483647
		else:bindings.scenery_resources={}
		check(not owner.configure(bindings,catalogues,station,flag,false,0) and owner.snapshot().is_empty(),"Failed ore configuration retained state: "+scenario)
	data=Fixture.make();bindings=data[0];catalogues=data[1]
	for index in range(1,10):catalogues.tables.systems[index].fields[3]=10000
	catalogues.tables.items[0].arrays[2][9]=1
	check(owner.configure(bindings,catalogues,0,false,false,0),owner.error)
	check(owner.choose({"state":1},0).is_empty() and "No source" in owner.error,"Impossible ore table hung or fabricated a choice")

func check_profile(content: String, pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new();var owner := Ores.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error);return
	if bindings.scenery_resources.is_empty():
		check(not owner.configure(bindings,catalogues,78,false,false,0),"Legacy pack invented scenery ore declarations")
		print(library.manifest.profile.edition,": legacy ore selection unavailable");return
	var snapshots := []
	for station in catalogues.tables.stations:
		check(owner.configure(bindings,catalogues,station.id,false,false,0),owner.error)
		var snapshot := owner.snapshot();check(snapshot.rows.size()==11,"Incomplete ore distribution")
		if snapshot.is_empty():continue
		snapshots.append(snapshot.rows)
		var random := Generator.new();random.seed_from(station.id)
		var choice := owner.choose(random.snapshot(),0)
		check(not choice.is_empty(),owner.error)
		if not choice.is_empty():check(choice.base_content_id==bindings.base_content_id and choice.binding_id==bindings.binding_id,"Ore selection lost content identity")
	# Private report contains original catalogue-derived data and stays outside source.
	var report := "user://tests/scenery-ores-%s.json" % library.manifest.profile.edition
	DirAccess.make_dir_recursive_absolute("user://tests")
	var file := FileAccess.open(report,FileAccess.WRITE);file.store_string(JSON.stringify(snapshots));file.close()
	print("Ore report: ",ProjectSettings.globalize_path(report))
	check_versions(bindings,library.manifest,pack)
	print(library.manifest.profile.edition,": all %d station ore distributions and source draws checked" % snapshots.size())

func check_versions(bindings: RefCounted, manifest: Dictionary, pack: String) -> void:
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("registrations.json")))
	var header: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	var directory := "user://tests/ore-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(directory)
	for scenario in ["legacy","empty","missing","malformed","disconnected"]:
		var body := original.duplicate(true);var metadata := header.duplicate(true)
		if scenario=="legacy":body.reader="resource-registration-v41";metadata.reader=body.reader;body.erase("scenery_resources")
		elif scenario=="empty":body.scenery_resources={}
		elif scenario=="missing":body.erase("scenery_resources")
		elif scenario=="malformed":body.scenery_resources.model_ids[0]=-1
		else:body.scenery_resources.provenance.entry.offset-=1
		var serialized := JSON.stringify(body)
		metadata.records_sha256=serialized.sha256_text();metadata.records_bytes=serialized.to_utf8_buffer().size()
		metadata.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n" % [metadata.base_content_id,metadata.source_executable_sha256,metadata.architecture,metadata.records_sha256]).sha256_text()
		var file := FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE);file.store_string(serialized);file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE);file.store_string(JSON.stringify(metadata));file.close()
		check(bindings.open(pack,manifest),bindings.error)
		var accepted: bool = bindings.open(directory,manifest)
		if scenario in ["legacy","empty"]:check(accepted and bindings.scenery_resources.is_empty() and not bindings.scenery_population.is_empty(),"Compatible ore scope failed: "+bindings.error)
		else:check(not accepted and bindings.scenery_resources.is_empty() and bindings.binding_id.is_empty() and "scenery" in bindings.error.to_lower(),"Malformed ore scope accepted or retained state")
	for name in ["registrations.json","bindings.json"]:DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)

func check(condition: bool,message: String) -> void:
	if not condition:failures+=1;push_error(message)
