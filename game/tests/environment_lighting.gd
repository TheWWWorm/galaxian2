extends SceneTree
const Definitions = preload("res://src/content/environment_color_definitions.gd")
const Lighting = preload("res://src/simulation/environment_lighting.gd")
const Adapter = preload("res://src/presentation/opening_lighting.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
var failures := 0

func _initialize() -> void:
	create_timer(15).timeout.connect(func(): push_error("Environment lighting checks timed out"); quit(1))
	var colors := {}
	for key in Definitions.COUNTS:
		colors[key]=[]
		for i in Definitions.COUNTS[key]: colors[key].append([0.03125,0.125,0.5])
	var model := Lighting.new()
	var value := model.for_station(colors,78,0,9)
	check(value.lights[0].diffuse==Vector3(0.46875,1.875,2),"Diffuse scaling or upper clamp changed")
	check(value.lights[1].diffuse==Vector3(0.046875,0.1875,0.75),"Planet contribution changed")
	check(value.rim_color==Vector3(0.09375,0.375,1.5),"Rim color was conflated with global ambient")
	check(value.global_ambient.is_equal_approx(Vector3(0.0046875,0.01875,0.075)),"Global ambient factor changed")
	for bad in [-1,15,19,null,"9"]:check(model.for_station(colors,78,0,bad).is_empty(),"Unsupported sky accepted")
	for bad in [-1,27,null,"0"]:check(model.for_station(colors,78,bad,9).is_empty(),"Unknown planet type accepted")
	for key in Definitions.COUNTS:
		var broken := colors.duplicate(true);broken[key][0][0]=NAN
		check(not Definitions.parameters(broken),"Nonfinite color accepted")
		broken=colors.duplicate(true);broken[key].pop_back()
		check(not Definitions.parameters(broken),"Truncated color table accepted")
	var args := OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected source/binding/visual triples")
	for i in range(0,args.size()-2,3):
		var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new()
		check(library.open(args[i]),library.error)
		check(bindings.open(args[i+1],library.manifest),bindings.error)
		check(catalogues.open(library),catalogues.error)
		var header: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[i+1].path_join("bindings.json")))
		var imported: Dictionary = bindings.environment_colors
		check(not imported.is_empty(),"No source environment colors")
		if imported.is_empty(): continue
		check(imported.has("rim_rgb") and not imported.has("material_ambient_rgb"),"Loader retained historical rim mislabel")
		var legacy := imported.duplicate(true)
		legacy.material_ambient_rgb=legacy.rim_rgb;legacy.erase("rim_rgb")
		legacy.provenance.material_ambient_rgb=legacy.provenance.rim_rgb;legacy.provenance.erase("rim_rgb")
		legacy.provenance.material=legacy.provenance.rim;legacy.provenance.erase("rim")
		var before := legacy.duplicate(true)
		var canonical: Variant = Definitions.normalize_v30(legacy)
		check(canonical==imported and legacy==before,"Legacy normalization changed values, provenance or input")
		check(Definitions.validate(legacy,int(header.source_executable_bytes),header.architecture)!="","New schema accepted historical aliases")
		for conflict in ["table","provenance_table","provenance_lookup","missing"]:
			var bad_legacy := legacy.duplicate(true)
			if conflict=="table": bad_legacy.rim_rgb=legacy.material_ambient_rgb
			elif conflict=="provenance_table": bad_legacy.provenance.rim_rgb=legacy.provenance.material_ambient_rgb
			elif conflict=="provenance_lookup": bad_legacy.provenance.rim=legacy.provenance.material
			else: bad_legacy.erase("material_ambient_rgb")
			check(Definitions.normalize_v30(bad_legacy)==null,"Ambiguous/incomplete legacy color declarations accepted")
		for key in imported.provenance:
			var broken := imported.duplicate(true);broken.provenance[key].bytes+=1
			check(not Definitions.validate(broken,int(header.source_executable_bytes),header.architecture).is_empty(),"Wrong declaration extent accepted")
		var overlap := imported.duplicate(true);overlap.provenance.planet_rgb.offset=overlap.provenance.sun_rgb.offset
		check(not Definitions.validate(overlap,int(header.source_executable_bytes),header.architecture).is_empty(),"Overlapping source table accepted")
		var adapter := Adapter.new();root.add_child(adapter)
		check(adapter.build(bindings,catalogues,library.manifest.content_id,0,3,false),adapter.error)
		check(adapter.state.lights[0].diffuse==Vector3(2,2,2),"Original opening sun contribution differs")
		check(adapter.state.rim_color.is_equal_approx(Vector3(1.29,1.41,1.41)),"Original rim color differs")
		for index in adapter.lights.size():
			var light := adapter.lights[index]
			check(light.basis.z.is_equal_approx(adapter.state.lights[index].direction_to_light),"Directional light is reversed")
			var linear := light.light_color.srgb_to_linear()
			check((Vector3(linear.r,linear.g,linear.b)*light.light_energy).is_equal_approx(adapter.state.lights[index].diffuse),"Light adapter changed linear RGB energy")
		check(not adapter.build(bindings,catalogues,"0".repeat(64),0,3,false) and adapter.state.is_empty() and adapter.get_child_count()==0,"Mixed content retained light state")
		check(not adapter.build(bindings,catalogues,library.manifest.content_id,1,3,false),"Later campaign silently reused opening lighting")
		adapter.free()
		check(not bindings.open("",library.manifest) and bindings.environment_colors.is_empty(),"Failed open retained environment colors")
		print("Environment lighting: ",library.manifest.profile.edition," tables, state and adapter verified")
	print("Environment lighting checks: %d failures" % failures)
	quit(1 if failures else 0)

func check(ok: bool,message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)
