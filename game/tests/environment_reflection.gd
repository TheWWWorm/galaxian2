extends SceneTree
const Definitions = preload("res://src/content/reflection_definitions.gd")
const Reflection = preload("res://src/presentation/environment_reflection.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
var failures := 0

func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("Reflection checks timed out"); quit(1))
	var declaration := {"texture_base":22000,"special_id":31000}
	check(Definitions.texture_id(declaration,9,false)==22009,"System sky index was not added to the imported base")
	check(Definitions.texture_id(declaration,9,true)==31000,"Special location ignored its own imported resource")
	check(Definitions.texture_id(declaration,null,true)==31000,"Special branch unnecessarily depends on sky lookup")
	check(Definitions.texture_id({"texture_base":65533,"special_id":1},8,false)==5,"Source unsigned ID narrowing changed")
	for bad in [-1,19,null,"9"]:check(Definitions.texture_id(declaration,bad,false)==-1,"Invalid sky index accepted")
	for bad in [0,1,null,"false"]:check(Definitions.texture_id(declaration,9,bad)==-1,"Implicit location condition accepted")
	for field in declaration:
		var broken := declaration.duplicate();broken[field]=65534
		check(Definitions.texture_id(broken,9,false)==-1,"Invalid reflection ID declaration accepted")
	var args := OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%2==0,"Expected content/binding pairs")
	for index in range(0,args.size()-1,2):verify_source(args[index],args[index+1])
	print("Environment reflection checks: %d failures" % failures)
	quit(1 if failures else 0)

func verify_source(content: String,pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new()
	check(library.open(content),library.error)
	check(bindings.open(pack,library.manifest),bindings.error)
	check(catalogues.open(library),catalogues.error)
	var data: Dictionary = bindings.reflection_selection
	check(not data.is_empty(),"Source reflection selection unavailable")
	if data.is_empty():return
	var header: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	for key in data.provenance:
		var broken := data.duplicate(true);broken.provenance[key].bytes+=1
		check(not Definitions.validate(broken,int(header.source_executable_bytes),header.architecture,bindings.flight_projection,bindings.opening_sky).is_empty(),"Wrong reflection extent accepted")
	for key in ["predicate","system","load_context"]:
		var broken := data.duplicate(true);broken.provenance[key].offset+=1
		check(not Definitions.validate(broken,int(header.source_executable_bytes),header.architecture,bindings.flight_projection,bindings.opening_sky).is_empty(),"Unlinked reflection declaration accepted")
	var reflection := Reflection.new()
	check(reflection.build_opening(library,bindings,catalogues,0,3,false),reflection.error)
	check(reflection.selection.get("texture_id")==12039 and reflection.selection.get("system_id")==15,"Fresh opening selected the wrong reflection resource")
	check(reflection.texture!=null,"Opening cube was not prepared")
	check(reflection.build(library,bindings,catalogues,15,true),reflection.error)
	check(reflection.selection.get("texture_id")==12040,"Matching location did not select its source override")
	var supported := 0;var unavailable := 0
	for system in catalogues.tables.systems:
		var id := Definitions.texture_id(data,system.sky_index,false)
		var path := bindings.resolve_texture(id)
		var success := reflection.build(library,bindings,catalogues,system.id,false)
		if path.is_empty():
			check(not success and reflection.texture==null and reflection.selection.is_empty(),"Missing reflection binding retained a substitute texture");unavailable+=1
		else:
			check(success,reflection.error)
			check(reflection.selection.get("texture_id")==id and reflection.selection.get("texture_path")==path,"Reflection resource differs from the active system binding");supported+=1
	for bad in [-1,34,null,"15"]:
		check(not reflection.build(library,bindings,catalogues,bad,false) and reflection.texture==null,"Unknown system retained a cube")
	check(not reflection.build(library,bindings,catalogues,15,false,"ultra"),"Invalid texture preference accepted")
	check(not reflection.build_opening(library,bindings,catalogues,1,3,false),"Later campaign silently reused opening state")
	check(not reflection.build_opening(library,bindings,catalogues,0,2,false),"Other world reused opening reflection")
	check(not reflection.build_opening(library,bindings,catalogues,0,3,true),"Unknown opening location-match state accepted")
	check(reflection.build_opening(library,bindings,catalogues,0,3,false),reflection.error)
	var original_record: Variant = bindings.records.get(12039)
	bindings.records.erase(12039)
	check(not reflection.build_opening(library,bindings,catalogues,0,3,false) and reflection.texture==null and reflection.selection.is_empty(),"Missing opening cube reused another location's texture")
	bindings.records[12039]=original_record
	check(reflection.build_opening(library,bindings,catalogues,0,3,false),reflection.error)
	bindings.base_content_id="0".repeat(64)
	check(not reflection.build(library,bindings,catalogues,15,false) and reflection.texture==null and reflection.selection.is_empty(),"Cross-edition/base reflection retained its old cube")
	check(not bindings.open("",library.manifest) and bindings.reflection_selection.is_empty(),"Failed binding open retained a reflection selector")
	print("Reflections ",library.manifest.profile.edition,": ",supported," systems resolved; ",unavailable," missing source bindings")

func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
