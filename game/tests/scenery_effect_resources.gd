extends SceneTree
const Resources = preload("res://src/content/scenery_effect_resources.gd")
const Fixture = preload("res://tests/scenery_fixture.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
var failures := 0

class MemoryLibrary extends RefCounted:
	var manifest := {"content_id":"a".repeat(64)}
	var files := {}
	var error := ""
	func read_resource(path: String, _limit: int) -> PackedByteArray:
		error="Synthetic missing effect resource"
		return files.get(path,PackedByteArray())

func _initialize() -> void:
	check_ranges()
	check_synthetic()
	var args := OS.get_cmdline_user_args()
	check(args.size()%2==0,"Expected content/binding pairs")
	for index in range(0,args.size()-1,2): check_profile(args[index],args[index+1])
	print("Scenery effect resource checks: %d failures" % failures)
	quit(1 if failures else 0)

func fixture() -> Array:
	var library := MemoryLibrary.new();var bindings: RefCounted = Fixture.make()[0]
	bindings.scenery_effects={"variants":[],"speed_threshold":1.0,"speed_base":1.0,"speed_scale":3.0,"provenance":{}}
	var pairs := [[100,101],[100,102],[103,104],[105,106]]
	for index in 4:
		bindings.scenery_effects.variants.append({"base_model_id":400+index*100,"effect_type":index+2,"model_ids":pairs[index]})
		for model_index in 2:
			var path: String = Resources.PATHS[index][model_index]
			bindings.records[pairs[index][model_index]]=[{"resource":path,"kind":"mesh","registration_type":4}]
			bindings.base_files[path]={"kind":"mesh"}
			library.files[path]=mesh(4 if index<2 else 5,{"positive":33.75 if index==2 else 20.5,"end":103.9 if model_index==0 else 100.9})
	return [library,bindings]

func check_ranges() -> void:
	var surface := {"tracks":{"translation":[{"dimensions":3,"keys":PackedFloat32Array([0,0,0,0,33.75,1,2,3,100.9,4,5,6])}],
		"scalar":[{"dimensions":1,"keys":PackedFloat32Array([0,0,20.5,0.5,103.9,1])}]}}
	check(Resources.playback_range([surface])=={"start_ms":20,"end_ms":103},"Range did not use all channels, minimum positive time and truncation")
	var second := {"tracks":{"rotation":[{"dimensions":1,"keys":PackedFloat32Array([12.75,1])},{"dimensions":1,"keys":PackedFloat32Array([200.1,1])},{"dimensions":1,"keys":PackedFloat32Array()}]}}
	check(Resources.playback_range([surface,second])=={"start_ms":12,"end_ms":200},"Range ignored split channels or a later surface")
	var same_integer := {"tracks":{"scalar":[{"dimensions":1,"keys":PackedFloat32Array([0,0,0.25,1,1.75,2,1.9,3])}]}}
	check(Resources.playback_range([same_integer])=={"start_ms":0,"end_ms":1},"Submillisecond positive start or shared integer timestamps were changed")
	for invalid in ["negative","nan","unordered","large","no_positive","uv","unknown","shape","dimensions","value","empty"]:
		var bad: Dictionary = surface.duplicate(true)
		match invalid:
			"negative":bad.tracks.translation[0].keys[0]=-1
			"nan":bad.tracks.translation[0].keys[0]=NAN
			"unordered":bad.tracks.translation[0].keys[4]=-1
			"large":bad.tracks.translation[0].keys[8]=1000001
			"no_positive":bad.tracks={"scalar":[{"dimensions":1,"keys":PackedFloat32Array([0,0])}]}
			"uv":bad.tracks.uv=[]
			"unknown":bad.tracks.color=[]
			"shape":bad.tracks.translation[0].keys.append(0)
			"dimensions":bad.tracks.translation[0].dimensions=2
			"value":bad.tracks.translation[0].keys[1]=INF
			"empty":bad.tracks={}
		check(Resources.playback_range([bad]).is_empty(),"Unsupported effect timing accepted: "+invalid)
	check(Resources.playback_range([]).is_empty() and Resources.playback_range(null).is_empty(),"Absent effect tracks invented a range")

func check_synthetic() -> void:
	var pair := fixture();var resources := Resources.new()
	pair[0].files[Resources.PATHS[3][1]]=mesh(5,{"uv":true,"end":100.9})
	check(resources.effect_for_model(400).is_empty() and not resources.error.is_empty(),"Unconfigured effect lookup accepted")
	check(resources.configure(pair[0],pair[1]),resources.error)
	for index in 4:
		var effect := resources.effect_for_model(400+index*100)
		check(Resources.effect_parameters(effect,pair[1]),"Prepared effect descriptor invalid")
		check(effect.effect_type==index+2 and effect.duration_ms==103,"Source effect pair or authored maximum changed")
		check(effect.models[0].start_ms==(33 if index==2 else 20) and effect.models[1].end_ms==100,"Effect key range lost source truncation")
	var before := resources.snapshot();var changed := resources.snapshot()
	changed.effects[400].models[0].start_ms=99
	var effect := resources.effect_for_model(400);effect.models.clear()
	check(resources.snapshot()==before,"Returned effect metadata aliases the provider")
	pair[0].files.clear();pair[1].scenery_effects.variants[0].model_ids[0]=999
	check(resources.snapshot()==before and resources.effect_for_model(400).models.size()==2,"Provider retains mutable input definitions")
	for invalid in [true,400.0,"400",401,-1,null]: check(resources.effect_for_model(invalid).is_empty() and resources.snapshot()==before,"Invalid base lookup changed resources")
	for invalid in ["identity","binding","legacy","base","pair","path","missing","version","truncated","negative","all_zero","uv","trailer"]:
		pair=fixture()
		var path: String = Resources.PATHS[3][1]
		match invalid:
			"identity":pair[0].manifest.content_id="c".repeat(64)
			"binding":pair[1].binding_id=""
			"legacy":pair[1].scenery_effects={}
			"base":pair[1].scenery_effects.variants[3].base_model_id=999
			"pair":pair[1].scenery_effects.variants[3].model_ids=[105,105]
			"path":pair[1].records[106][0].resource=Resources.PATHS[3][0]
			"missing":pair[0].files.erase(path)
			"version":pair[0].files[path]=mesh(4,{})
			"truncated":pair[0].files[path]=PackedByteArray([1,2,3])
			"negative":pair[0].files[path]=mesh(5,{"positive":-1.0})
			"all_zero":pair[0].files[path]=mesh(5,{"positive":0.0,"end":0.0})
			"uv":pair[0].files[path]=mesh(5,{"uv":true,"keyed_uv":true})
			"trailer":pair[0].files[path]=mesh(5,{"trailer":1})
		check(not resources.configure(pair[0],pair[1]) and not resources.error.is_empty() and resources.snapshot().is_empty(),"Invalid source effect retained state: "+invalid)
	check(not resources.configure(null,null) and resources.snapshot().is_empty(),"Missing effect inputs accepted")
	check(not resources.configure(RefCounted.new(),RefCounted.new()) and not Resources.effect_parameters({},RefCounted.new()),"Unrelated effect owner types accepted")

func check_profile(content: String, pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var resources := Resources.new()
	if not library.open(content) or not bindings.open(pack,library.manifest):
		check(false,library.error+bindings.error);return
	if bindings.scenery_effects.is_empty():
		check(not resources.configure(library,bindings) and resources.snapshot().is_empty(),"Legacy bindings invented effect mappings")
		print(library.manifest.profile.edition,": legacy effect capability remains unavailable")
		return
	check(resources.configure(library,bindings),resources.error)
	var rows := []
	for index in 4:
		var effect := resources.effect_for_model(int(bindings.scenery_resources.model_ids[index]))
		if effect.is_empty(): check(false,resources.error);return
		check(effect.duration_ms==10050,"Actual authored effect duration changed")
		for model_index in 2:
			var model: Dictionary = effect.models[model_index]
			check(model.start_ms==(33 if index==2 else 50),"Actual effect minimum positive key changed")
			check(model.end_ms==(10000 if index==2 and model_index==1 else 10050),"Actual effect maximum key changed")
		rows.append(effect)
	print(JSON.stringify({"edition":library.manifest.profile.edition,"effects":rows}))

func mesh(version: int, options: Dictionary) -> PackedByteArray:
	var output := StreamPeerBuffer.new()
	output.put_data(("V%dAEMesh" % version).to_ascii_buffer());output.put_u8(0);output.put_u8(1);output.put_u16(1)
	for value in [0,0,0]: output.put_float(value)
	output.put_u16(3)
	for index in 3: output.put_u16(index)
	output.put_u16(3)
	for value in [0,0,0,1,0,0,0,1,0]: output.put_float(value)
	for value in [0,0,0,1]: output.put_float(value)
	output.put_u16(1);output.put_u16(3)
	for time in [0.0,options.get("positive",20.5),options.get("end",103.9)]:
		output.put_float(time)
		for value in [0,0,0]: output.put_float(value)
	output.put_u16(65535);output.put_u16(65535);output.put_u16(0)
	if version>=5:
		output.put_u16(1 if options.get("uv",false) else 0)
		if options.get("uv",false):
			for channel in 7:
				output.put_u16(1 if options.get("keyed_uv",false) else 0)
				if options.get("keyed_uv",false): output.put_float(0);output.put_float(0)
	output.put_u16(options.get("trailer",0))
	return output.data_array

func check(condition: bool, message: String) -> void:
	if not condition: failures+=1;push_error(message)
