extends SceneTree
## Retain native source state around genuine pre32 and paid32 saves. These checks
## do not select a mission, grant cargo, move the player or claim earned travel.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Archive=preload("res://src/simulation/station_archive.gd")
const SaveFile=preload("res://src/simulation/station_save_file.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=6:check(false,"Expected content/bindings/visuals, earned pre32 and paid32 saves, and a private output directory")
	else:verify(args)
	print("Ordinary Void source saves: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not library.select_language("gb") or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var file:=SaveFile.new();var archive:=Archive.new()
	var original: Dictionary=file.read_document(args[3])
	var station: RefCounted=archive.restore(bindings,cat,library,original)
	if station==null:check(false,archive.error);return
	check(original.version==6 and original.station.campaign_cursor in [28,31] and not original.career.has("void_source"),"The pre32 input is not the genuine legacy fixture")
	var source: Dictionary=station.contract_owner().void_source_state()
	check(source.get("eligible_selection_count")==0 and source.get("source_system_id")==18 and source.get("source_station_id")==91,"The pre32 native source did not initialize before eligible travel")
	var blueprints: Dictionary=station.contract_owner().blueprint_state()
	check(blueprints.get("entries",[]).size()==25,"The career lost its source blueprint recipes")
	for entry in blueprints.get("entries",[]):
		check(not entry.available and entry.material_value==0,"The unimplemented blueprint path invented a purchase or material credit")
	var retained: Dictionary=archive.capture(station,bindings)
	check(retained.get("version")==8 and retained.career.void_source==source and retained.career.blueprints==blueprints,"The Void career was not captured in its versioned archive")
	if retained.is_empty():check(false,archive.error);return
	var projected: Dictionary=retained.duplicate(true)
	projected.version=original.version;projected.career.erase("void_source");projected.career.erase("blueprints")
	check(projected==original,"Adding source retention changed earned inventory, progress, locations or identity")
	var restored: RefCounted=archive.restore(bindings,cat,library,retained)
	check(restored!=null,archive.error)
	if restored==null:return
	check(archive.capture(restored,bindings)==retained,"The native source changed across archive restoration")
	var fork: RefCounted=station.contract_owner().fork()
	var observed: Dictionary=fork.void_source_state();observed.source_station_id=93
	check(fork.void_source_state()==source and station.contract_owner().void_source_state()==source,"A source observation changed the retained career")
	var observed_recipes: Dictionary=fork.blueprint_state();observed_recipes.entries[0].available=true
	check(fork.blueprint_state()==blueprints and station.contract_owner().blueprint_state()==blueprints,"A blueprint observation changed the retained career")
	for mutation in [{"eligible_selection_count":1},{"eligible_selection_count":-1},{"eligible_selection_count":11},{"eligible_selection_count":0.0},{"source_system_id":6},{"source_station_id":93},{"binding_id":"foreign"}]:
		var invalid: Dictionary=retained.duplicate(true)
		invalid.career.void_source.merge(mutation,true)
		check(archive.restore(bindings,cat,library,invalid)==null and not archive.error.is_empty(),"Invalid/pre32 source was accepted: "+str(mutation))
	for absent in [null,{},false]:
		var invalid: Dictionary=retained.duplicate(true);invalid.career.void_source=absent
		check(archive.restore(bindings,cat,library,invalid)==null,"A v8 source fell back to fresh initialization")
		invalid=retained.duplicate(true);invalid.career.blueprints=absent
		check(archive.restore(bindings,cat,library,invalid)==null,"A v8 blueprint list fell back to fresh initialization")
	for bad_recipe in [{"base_content_id":"foreign"},{"entries":[]}]:
		var invalid: Dictionary=retained.duplicate(true);invalid.career.blueprints.merge(bad_recipe,true)
		check(archive.restore(bindings,cat,library,invalid)==null,"Invalid saved blueprint progress was accepted")
	var downgraded: Dictionary=retained.duplicate(true);downgraded.version=6
	check(archive.restore(bindings,cat,library,downgraded)==null,"An older archive silently accepted a newer source field")
	var output: String=SaveFile.path_for(args[5],bindings)
	check(output.is_absolute_path() and file.save(output,station,bindings,cat,library),file.error)
	check(file.load_document(output,bindings,cat,library)==retained,"Disk save lost the native source: "+file.error)
	check(file.read_document(args[3])==original,"The immutable pre32 save was rewritten")
	var legacy: Dictionary=file.read_document(args[4])
	var paid: RefCounted=archive.restore(bindings,cat,library,legacy)
	check(paid!=null,archive.error)
	if paid==null:return
	check(legacy.version==7 and legacy.station.campaign_cursor==32 and not legacy.career.has("void_source"),"The paid32 input is not the genuine legacy fixture")
	check(paid.contract_owner().void_source_state().is_empty(),"The older32 save invented unrecorded source history")
	check(paid.contract_owner().blueprint_state().is_empty(),"The unchanged legacy32 save acquired a newer chapter owner")
	check(archive.capture(paid,bindings)==legacy and not paid.prepare_departure(bindings,cat).is_empty(),"Legacy paid32 changed or lost its supported ordinary departure")
	check(file.read_document(args[4])==legacy,"The immutable paid32 save was rewritten")

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
