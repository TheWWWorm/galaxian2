extends SceneTree
## Focused restoration from the earned capture station; no campaign progress is
## manufactured. Ordinary version1 compatibility has its own retained-file suite.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Archive=preload("res://src/simulation/station_archive.gd")
const SaveFile=preload("res://src/simulation/station_save_file.gd")
const Checkpoint=preload("res://tests/fixtures/alioth_station_scenario.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:verify(args)
	else:check(false,"Expected content, bindings and visuals")
	print("Campaign station saves: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not library.select_language("gb") or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var checkpoint:=Checkpoint.new();var station: RefCounted=checkpoint.open(OS.get_environment("GOF2_ALIOTH_STATION_SCENARIO"),bindings)
	if station==null:check(false,checkpoint.error);return
	var original: Dictionary=station.snapshot();var archive:=Archive.new()
	var document:=archive.capture(station,bindings)
	var restored:=archive.restore(bindings,cat,library,document)
	if restored==null:check(false,archive.error);return
	check(document.version==2 and restored.snapshot()==original,"Restoring the captured career changed the earned station")
	check(archive.capture(restored,bindings)==document,"The captured career changed on recapture")
	check(restored.prepare_departure(bindings,cat)==station.prepare_departure(bindings,cat),"The captured career prepares a different Alioth departure")
	check(not restored.open_equipment(bindings,cat,library) and not restored.acknowledge(),"The captured checkpoint replayed its acknowledgement or unlocked shopping")
	for mutation in [
		[["station","alioth_conversation_acknowledged"],false],[["station","mission","kind"],156],
		[["station","player_cache","values","hull"],0],[["career","completed_side_missions"],3],
		[["career","credits"],-1],[["career","travel_statistics","jumpgates_used"],-1],
		[["career","pending_result"],{"serial":1}],[["career","progress","rank"],99],
		[["inventory","ship_affiliation"],0],[["inventory","prototype_drill_replaced"],false],
		[["locations","current_station_id"],79]]:
		var invalid:=document.duplicate(true);var parent: Dictionary=invalid
		for index in mutation[0].size()-1:parent=parent[mutation[0][index]]
		parent[mutation[0].back()]=mutation[1]
		check(archive.restore(bindings,cat,library,invalid)==null and not archive.error.is_empty(),"The captured checkpoint accepted invalid data: "+str(mutation[0]))
	check(station.snapshot()==original,"Detached restoration changed the earned checkpoint")
	var directory:=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	if directory.is_empty() or not Checkpoint.private_path(directory+"/save.bin"):check(false,"Set a private campaign save directory");return
	var file:=SaveFile.new();var path:=SaveFile.path_for(directory.path_join("16"),bindings)
	check(file.save(path,station,bindings,cat,library),file.error)
	check(file.load_document(path,bindings,cat,library)==document,"The captured checkpoint changed on disk: "+file.error)
	print("Saved earned Alioth checkpoint: ",path)

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
