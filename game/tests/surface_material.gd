extends SceneTree
const Definitions = preload("res://src/content/surface_material_definitions.gd")
const MaterialLights = preload("res://src/presentation/material_light_state.gd")
const OpeningLighting = preload("res://src/presentation/opening_lighting.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
var failures := 0

func _initialize() -> void:
	var source := {"ambient_rgb":[2,0.5,1],"diffuse_rgb":[0,2,0.5],"specular_rgb":[1,0,4],"specular_power":32}
	var environment := {"global_ambient":Vector3(0.1,0.2,0.3),"rim_color":Vector3(2,1,0.5),
		"lights":[{"direction_to_light":Vector3.UP,"ambient":Vector3(0.2,0.4,0.6),"diffuse":Vector3(1,2,4),"specular":Vector3(0.1,0.5,1)},
			{"direction_to_light":Vector3.BACK,"ambient":Vector3.ZERO,"diffuse":Vector3(4,2,1),"specular":Vector3(1,2,4)}]}
	var original := environment.duplicate(true)
	var material := MaterialLights.new()
	check(material.build(source,environment),material.error)
	check(environment==original,"Preparation mutated input light colors")
	check(material.state.lights[0].ambient.is_equal_approx(Vector3(0.6,0.3,0.9)),"Per-light ambient or material channels were lost")
	check(material.state.lights[1].ambient.is_equal_approx(Vector3(0.2,0.1,0.3)),"Second ambient term was omitted or merged")
	check(material.state.lights[0].diffuse==Vector3(0,4,2) and material.state.lights[1].diffuse==Vector3(0,4,0.5),"Diffuse RGB multipliers were replaced by scalar intensity")
	check(material.state.lights[0].specular.is_equal_approx(Vector3(0.1,0,4)) and material.state.lights[1].specular==Vector3(1,0,16),"Independent specular channels were lost")
	check(material.state.specular_power==32 and material.state.rim_color==Vector3(2,1,0.5),"Exponent or rim color changed")
	environment.lights.resize(1)
	check(material.build(source,environment) and material.state.lights.size()==1,"One light retained a stale second contribution")
	for bad in [null,"1",true,-1,NAN,INF,17]:
		var broken := source.duplicate(true);broken.diffuse_rgb[0]=bad
		check(not material.build(broken,original) and material.state.is_empty(),"Invalid material RGB retained prepared state")
	for bad in [null,0,-1,1025,NAN,"20"]:
		var broken := source.duplicate(true);broken.specular_power=bad
		check(not material.build(broken,original) and material.state.is_empty(),"Invalid exponent retained prepared state")
	for bad in ["missing_ambient","missing_color","negative_color","infinite_color","direction","empty","excess"]:
		check(material.build(source,original),material.error)
		var broken := original.duplicate(true)
		if bad=="missing_ambient":broken.erase("global_ambient")
		elif bad=="missing_color":broken.lights[1].erase("ambient")
		elif bad=="negative_color":broken.lights[0].diffuse=Vector3(-1,1,1)
		elif bad=="infinite_color":broken.rim_color=Vector3(INF,0,0)
		elif bad=="direction":broken.lights[0].direction_to_light=Vector3(1,2,3)
		elif bad=="empty":broken.lights.clear()
		else:broken.lights.append(broken.lights[0])
		check(not material.build(source,broken) and material.state.is_empty(),"Invalid light input retained prepared state: "+bad)
	var args := OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%2==0,"Expected content/binding pairs")
	for index in range(0,args.size()-1,2):verify_source(args[index],args[index+1])
	print("Surface material checks: %d failures" % failures)
	quit(1 if failures else 0)

func verify_source(content: String,pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new()
	check(library.open(content),library.error)
	check(bindings.open(pack,library.manifest),bindings.error)
	check(catalogues.open(library),catalogues.error)
	var data: Dictionary = bindings.surface_material
	check(not data.is_empty(),"No source material parameters")
	if data.is_empty():return
	var header: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	var validate := func(value):return Definitions.validate(value,int(header.source_executable_bytes),header.architecture,bindings.environment_colors)
	for key in data:
		var broken := data.duplicate(true);broken.erase(key)
		check(not validate.call(broken).is_empty(),"Missing surface material field accepted: "+key)
	for group in ["provenance","value_sources"]:
		for key in data[group]:
			var broken := data.duplicate(true);broken[group][key].bytes+=1
			check(not validate.call(broken).is_empty(),"Invalid material extent accepted")
	for key in ["rim","setup"]:
		var broken := data.duplicate(true);broken.provenance[key].offset+=1
		check(not validate.call(broken).is_empty(),"Disconnected material context accepted")
	var overlap := data.duplicate(true);overlap.provenance.power.offset=overlap.provenance.ambient.offset
	check(not validate.call(overlap).is_empty(),"Overlapping material contexts accepted")
	var wrong_value := data.duplicate(true)
	wrong_value.value_sources.diffuse.offset+=1
	check(not validate.call(wrong_value).is_empty(),"Unlinked/partially overlapping source value accepted")
	var adapter := OpeningLighting.new();root.add_child(adapter)
	check(adapter.build(bindings,catalogues,library.manifest.content_id,0,3,false),adapter.error)
	var material := MaterialLights.new()
	check(material.build(data,adapter.state),material.error)
	check(material.state.specular_power==20,"Source specular power differs")
	for i in 2:
		check(material.state.lights[i].ambient.is_equal_approx(adapter.state.global_ambient),"Source unit ambient or zero local ambient differs")
		check(material.state.lights[i].diffuse==adapter.state.lights[i].diffuse,"Source unit diffuse differs")
		check(material.state.lights[i].specular==adapter.state.lights[i].specular,"Source unit specular differs")
	adapter.free()
	check(not bindings.open("",library.manifest) and bindings.surface_material.is_empty(),"Failed open retained surface material data")
	print("Surface material: ",library.manifest.profile.edition," values, provenance and opening colors verified")

func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
