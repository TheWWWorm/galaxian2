extends SceneTree
const Resources = preload("res://src/content/scenery_body_resources.gd")
const Fixture = preload("res://tests/scenery_fixture.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
var failures := 0

class MemoryLibrary extends RefCounted:
	var manifest := {"content_id":"a".repeat(64)}
	var files := {}
	var error := ""
	func read_resource(path: String, _limit: int) -> PackedByteArray:
		error="Synthetic missing resource"
		return files.get(path,PackedByteArray())

func _initialize() -> void:
	check_synthetic()
	var args := OS.get_cmdline_user_args()
	check(args.size()%2==0,"Expected content/binding pairs")
	for index in range(0,args.size()-1,2):
		var library := Library.new();var bindings := Bindings.new()
		if not library.open(args[index]) or not bindings.open(args[index+1],library.manifest):
			check(false,library.error+bindings.error);continue
		var resources := Resources.new()
		check(resources.configure(library,bindings),resources.error)
		var state := resources.snapshot()
		check(state.get("base_content_id")==bindings.base_content_id and state.get("binding_id")==bindings.binding_id,"Actual body resources lost content identity")
		check(state.get("radii",{}).size()==4,"Actual body resources did not resolve every base")
		for variant in 4:
			var id := int(bindings.scenery_resources.model_ids[variant])
			check(resources.model_radius(id)>0.0,"Actual base radius missing")
			check(resources.model_radius(id+1)==-1.0,"LOD radius exposed as a body base")
		print(JSON.stringify({"edition":library.manifest.profile.edition,"state":state}))
	print("Scenery body resource checks: %d failures" % failures)
	quit(1 if failures else 0)

func make_source() -> Array:
	var library := MemoryLibrary.new();var bindings: RefCounted = Fixture.make()[0]
	for index in 4:
		var path: String = Resources.BASE_PATHS[index]
		var id := int(bindings.scenery_resources.model_ids[index])
		bindings.records[id]=[{"resource":path,"kind":"mesh","registration_type":4}]
		bindings.base_files[path]={"kind":"mesh"}
		library.files[path]=mesh(Resources.VERSIONS[index],{"radius":float(17+index),"identity":index==3})
	return [library,bindings]

func check_synthetic() -> void:
	var pair := make_source();var library: RefCounted = pair[0];var bindings: RefCounted = pair[1]
	var resources := Resources.new()
	check(resources.model_radius(400)==-1.0 and not resources.error.is_empty(),"Unconfigured radius lookup accepted")
	check(resources.configure(library,bindings),resources.error)
	for index in 4:
		check(resources.model_radius(400+index*100)==float(17+index),"Stored radius replaced by vertex bound or sphere center length")
	var before := resources.snapshot();var changed := resources.snapshot()
	changed.radii[400]=9000.0
	check(resources.snapshot()==before,"Body radius snapshot aliases provider state")
	library.files.clear();bindings.scenery_resources.model_ids[0]=999
	check(resources.model_radius(400)==17.0 and resources.snapshot()==before,"Body radius lookup retains mutable source state")
	for invalid in [true,400.0,"400",-1,401,null]:
		check(resources.model_radius(invalid)==-1.0 and not resources.error.is_empty() and resources.snapshot()==before,"Invalid model lookup changed prepared state")
	check(resources.model_radius(400)==17.0 and resources.error.is_empty(),"Successful radius lookup retained a stale error")
	for label in ["identity","binding","missing","duplicate","path","version","surface","pivot","motion","scale","scalar","uv","zero","negative","nan","truncated","trailer"]:
		pair=make_source();library=pair[0];bindings=pair[1]
		var path: String = Resources.BASE_PATHS[3]
		match label:
			"identity":library.manifest.content_id="c".repeat(64)
			"binding":bindings.binding_id=""
			"missing":library.files.erase(path)
			"duplicate":bindings.scenery_resources.model_ids[3]=400
			"path":bindings.records[700][0].resource=Resources.BASE_PATHS[2]
			"version":library.files[path]=mesh(4,{})
			"surface":library.files[path]=mesh(5,{"surfaces":2})
			"pivot":library.files[path]=mesh(5,{"pivot":1.0})
			"motion":library.files[path]=mesh(5,{"translation":1.0})
			"scale":library.files[path]=mesh(5,{"scale":2.0})
			"scalar":library.files[path]=mesh(5,{"scalar":true})
			"uv":library.files[path]=mesh(5,{"uv":true})
			"zero":library.files[path]=mesh(5,{"radius":0.0})
			"negative":library.files[path]=mesh(5,{"radius":-1.0})
			"nan":library.files[path]=mesh(5,{"radius":NAN})
			"truncated":library.files[path]=PackedByteArray([1,2,3])
			"trailer":library.files[path]=mesh(5,{"trailer":1})
		check(not resources.configure(library,bindings) and not resources.error.is_empty() and resources.snapshot().is_empty(),"Unsupported scenery body retained prepared state: "+label)
	check(not resources.configure(null,null) and resources.snapshot().is_empty(),"Missing body resource inputs accepted")

func mesh(version: int, options: Dictionary) -> PackedByteArray:
	var output := StreamPeerBuffer.new()
	output.put_data(("V%dAEMesh" % version).to_ascii_buffer());output.put_u8(0);output.put_u8(1)
	output.put_u16(options.get("surfaces",1))
	for surface in options.get("surfaces",1):
		for value in [options.get("pivot",0.0),0.0,0.0]:output.put_float(value)
		output.put_u16(3)
		for index in 3:output.put_u16(index)
		output.put_u16(3)
		# Deliberately different from the authored sphere to catch AABB substitution.
		for value in [0.0,0.0,0.0,1000.0,0.0,0.0,0.0,1000.0,0.0]:output.put_float(value)
		for value in [111.0,222.0,333.0,options.get("radius",17.0)]:output.put_float(value)
		for name in ["translation","rotation","scale"]:
			if options.get("identity",false) or options.has(name):
				output.put_u16(1);output.put_u16(1);output.put_float(1150.0)
				for component in 3:output.put_float(options.get(name,1.0 if name=="scale" else 0.0))
			else:output.put_u16(65535)
		output.put_u16(2 if options.get("scalar",false) else 0)
		if options.get("scalar",false):output.put_u16(1);output.put_float(0.0);output.put_float(0.0)
		if version>=5:
			output.put_u16(1 if options.get("uv",false) else 0)
			if options.get("uv",false):
				for channel in 7:output.put_u16(1);output.put_float(0.0);output.put_float(0.0)
		output.put_u16(options.get("trailer",0))
	return output.data_array

func check(ok: bool, message: String) -> void:
	if not ok:failures+=1;push_error(message)
