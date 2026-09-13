extends SceneTree
const Appearance=preload("res://src/presentation/damage_particle_appearance.gd")
const Definitions=preload("res://src/content/damage_particle_definitions.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
var failures:=0

func _initialize() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/damage_particle_appearance_vectors.json"))
	var updates:=0
	for vector in fixture.vectors:
		var preset: Dictionary=fixture.presets[int(vector.preset_index)]
		var state:=Appearance.start(preset,int(vector.slot),int(vector.size_sample))
		check(not state.has("error"),"Synthetic sprite construction failed")
		if state.has("error"):continue
		for step in vector.steps:
			var before:=state.duplicate(true)
			var next:=Appearance.advance(preset,state,step.delta)
			check(state==before,"Appearance mutated the caller's retained state")
			check(next.get("slot")==step.state.slot and next.get("age_ms")==step.state.age_ms and next.get("size")==step.state["size"],"Particle growth or strict lifetime differs from mathematical vector")
			var got:=Appearance.sample(preset,next)
			var expected: Dictionary=step.appearance
			check(got.get("active")==expected.active,"Wrong sprite liveness")
			if expected.active and not got.has("error"):
				check(got.frame==expected.frame and got["size"]==expected["size"],"Wrong sprite animation or size")
				for index in 4:
					check(got.color[index]==Appearance.single(expected.color[index]),"Sprite fade differs from binary32 color vector")
					check(got.uv_rect[index]==expected.uv_rect[index],"Sprite frame or stable slot mirroring changed")
			check(Appearance.sample(preset,next)==got,"Sampling a sprite changed its state")
			state=next;updates+=1
	var preset: Dictionary=fixture.presets[0]
	var initial:=Appearance.start(preset,0,0)
	for invalid in [null,"1",-1,60001,INF,NAN]:
		check(Appearance.advance(preset,initial,invalid).has("error"),"Invalid interval accepted")
	check(Appearance.start(preset,int(preset.capacity),0).has("error"),"Out-of-pool slot accepted")
	check(Appearance.start(preset,0,int(preset.size_jitter)).has("error"),"Out-of-range size draw accepted")
	var bad:=initial.duplicate();bad.age_ms=int(preset.lifetime_ms)+1
	check(Appearance.advance(preset,bad,1).has("error") and Appearance.sample(preset,bad).has("error"),"Invalid retained lifetime accepted")
	bad=initial.duplicate();bad["size"]=32768
	check(Appearance.sample(preset,bad).has("error"),"Invalid retained size accepted")
	check(Appearance.sample({},initial).has("error"),"Missing declaration fabricated particles")
	var repeated:=Appearance.advance(preset,initial,0.5)
	check(repeated==initial,"Fractional update incorrectly accumulates age or growth")
	var large:=preset.duplicate();large.size_growth_per_second=32767
	var wrapped:=Appearance.advance(large,initial,1000)
	# Lifetime is shorter than this interval, so expiration precedes growth.
	check(wrapped.age_ms==-1 and wrapped["size"]==0,"Expired sprite continued growing")
	large.lifetime_ms=2000
	wrapped=Appearance.advance(large,initial,1000)
	check(wrapped["size"]==-32641,"Source signed-short growth no longer wraps")
	var args:=OS.get_cmdline_user_args()
	for index in range(0,args.size(),3):verify(args[index],args[index+1],args[index+2])
	print("Damage particle appearance: ",fixture.vectors.size()," cases, ",updates," mathematical updates; ",failures," failures")
	quit(0 if failures==0 else 1)

func verify(content: String,pack: String,textures: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	check(library.open(content),library.error);check(bindings.open(pack,library.manifest),bindings.error)
	check(visuals.open(textures,library.manifest),visuals.error)
	var data: Dictionary=bindings.damage_particles
	if data.is_empty():
		check(not Definitions.parameters(data),"Legacy pack fabricated particle declarations")
		print("Damage particles unavailable in legacy ",library.manifest.profile.edition);return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack+"/bindings.json"))
	check(Definitions.validate(data,int(header.source_executable_bytes),header.architecture).is_empty(),"Valid particle declaration rejected")
	for problem in ["scope","count","slot","material","size","fade","color","uv","extent","overlap"]:
		var copy:=data.duplicate(true)
		match problem:
			"scope":copy.scope="other"
			"count":copy.presets.pop_back()
			"slot":copy.presets[0].preset_id=0
			"material":copy.presets[1].material_id=copy.presets[0].material_id
			"size":copy.presets[0]["size"]=NAN
			"fade":copy.presets[0].fade_in_ms=1000000
			"color":copy.presets[0].start_rgba[0]=256
			"uv":copy.presets[0].uv_rect[2]=0
			"extent":copy.provenance.presets.bytes=1
			"overlap":copy.provenance.fire_material.offset=copy.provenance.smoke_material.offset
		check(not Definitions.validate(copy,int(header.source_executable_bytes),header.architecture).is_empty(),"Malformed particle definition accepted: "+problem)
	var resources:=[]
	for index in 2:
		var row: Dictionary=data.presets[index]
		var material: Dictionary=bindings.resolve_material(int(row.material_id))
		check(not material.is_empty(),bindings.error)
		if material.is_empty():continue
		check(material.render_type==[1,2][index],"Wrong smoke/fire material blend type")
		var image: Image=visuals.load_image(material.texture_paths[0])
		check(image!=null,visuals.error)
		if image!=null:resources.append({"preset_id":row.preset_id,"material_id":row.material_id,"texture_id":material.texture_ids[0],"size":image.get_size(),"path":material.texture_paths[0]})
		var state:=Appearance.start(row,0,0)
		check(not state.has("error"),"Source sprite appearance could not start")
		if state.has("error"):continue
		check(Appearance.sample(row,state).color.a==0,"New fading sprite is immediately opaque")
		state=Appearance.advance(row,state,int(row.lifetime_ms))
		check(state.age_ms==row.lifetime_ms and Appearance.sample(row,state).frame==int(row.animation_frames)-1,"Inclusive source lifetime lost its last tile")
		state=Appearance.advance(row,state,1)
		check(Appearance.sample(row,state)=={"active":false},"Expired sprite remained visible")
	print("Damage particle resources ",library.manifest.profile.edition," ",resources)

func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
