extends SceneTree
## Explicit presentation samples do not admit or advance a playable mission.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Geometry=preload("res://src/presentation/sahi_portal_geometry.gd")
const Alioth=preload("res://src/presentation/alioth_portal_geometry.gd")
const Stage=preload("res://src/content/sahi_stage_definitions.gd")
const Resources=preload("res://src/content/scenery_effect_resources.gd")
var checks:=0
var failures:=0
var _library: RefCounted
var _bindings: RefCounted
var _visuals: RefCounted
var _geometry: Node3D
var _alioth: Node3D
var _viewport: SubViewport

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()<3 or args.size()>4:check(false,"Expected content, bindings, visuals and optional capture folder");quit(1);return
	_library=Library.new();_bindings=Bindings.new();_visuals=Visuals.new()
	if not _library.open(args[0]) or not _bindings.open(args[1],_library.manifest) or not _visuals.open(args[2],_library.manifest):
		check(false,_library.error+_bindings.error+_visuals.error);quit(1);return
	var unbuilt:=Geometry.new()
	check(unbuilt.prepare_state({}).is_empty(),"Unbuilt portal accepted a presentation frame")
	unbuilt.free()
	verify_admission()
	if not Stage.selected(_bindings.mido_travel,context()):
		print("Sahi portal geometry: %d checks; %d failures (missing capability guard only)"%[checks,failures]);quit(1 if failures else 0);return
	_viewport=SubViewport.new();_viewport.size=Vector2i(1280,720);_viewport.own_world_3d=true
	_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(_viewport)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color.BLACK;_viewport.add_child(environment)
	var camera:=Camera3D.new();camera.near=10;camera.far=200000;camera.current=true
	_viewport.add_child(camera);camera.look_at_from_position(Vector3(45000,0,-90000),Vector3(45000,0,0))
	_geometry=Geometry.new();_alioth=Alioth.new();_viewport.add_child(_geometry);_viewport.add_child(_alioth)
	var selected:=context();var retained:=selected.duplicate(true)
	if not _geometry.build(_library,_visuals,_bindings,selected) or not _alioth.build(_library,_visuals,_bindings):
		check(false,_geometry.error+_alioth.error);_viewport.free();quit(1);return
	_alioth.hide()
	check(selected==retained,"Renderer mutated selected mission context")
	check(not _geometry.visible,"Sahi portal flashed before its first native frame")
	verify_resource()
	verify_samples()
	verify_rejection()
	if failures==0 and DisplayServer.get_name()!="headless":await verify_rendering(args[3] if args.size()==4 else "")
	_viewport.free()
	print("Sahi portal geometry: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func context() -> Dictionary:
	return {"campaign_cursor":24,"system_id":9,"station_id":48,"mission_kind":4,
		"mission_story":true,"mission_completed":false,"mission_failed":false}

func verify_admission() -> void:
	for changes in [{"station_id":49},{"system_id":8},{"campaign_cursor":16},
		{"mission_kind":11},{"mission_completed":true},{"mission_story":false}]:
		var selected:=context();selected.merge(changes,true)
		var rejected:=Geometry.new()
		check(not rejected.build(_library,_visuals,_bindings,selected) and rejected.model==null,"Unselected world built Sahi portal geometry")
		rejected.free()
	if not Stage.selected(_bindings.mido_travel,context()):
		var missing:=Geometry.new()
		check(not missing.build(_library,_visuals,_bindings,context()) and missing.model==null,"An older pack inferred missing Sahi support")
		missing.free()

func verify_resource() -> void:
	var path: String=_bindings.resolve(16994,"mesh")
	var material: Dictionary=_bindings.material_for_mesh(path,"high")
	var timing:=Resources.playback_range(_geometry.model.surfaces)
	check(_geometry.model.instances.size()==2 and _geometry.model.surfaces.size()==2,"Portal lost its original two surfaces")
	check(timing.get("start_ms")==50 and timing.get("end_ms")==20000,"Portal lost its original animation range")
	check(material.get("render_type")==2,"Portal source material is no longer additive")
	var original: Image=_visuals.load_image(material.texture_paths[0])
	for surface in _geometry.model.materials:
		var texture: Texture2D=surface.get_shader_parameter("diffuse_texture")
		check(texture!=null and texture.get_image().get_data()==original.get_data(),"Portal surface substituted its original texture")
	print("Portal source: "+JSON.stringify({"base_content_id":_bindings.base_content_id,
		"binding_id":_bindings.binding_id,"model_id":16994,"path":path,
		"texture_paths":material.texture_paths,"animation":timing}))

func sample(phase: int,elapsed: int,scale: float,time_ms: int) -> Dictionary:
	return {"base_content_id":_bindings.base_content_id,"binding_id":_bindings.binding_id,
		"campaign_cursor":24,"system_id":9,"station_id":48,"mission_kind":4,"model_id":16994,"slot":3,
		"phase":phase,"elapsed_ms":elapsed,"visible":phase==2 and elapsed<63001,
		"pose":Transform3D(Basis(Vector3.LEFT,Vector3.UP,Vector3.FORWARD),Vector3(45000,0,0)),
		"scale":scale,"animation":{"time_ms":time_ms}}

func surfaces() -> Array:
	var result:=[]
	for i in _geometry.model.instances.size():
		result.append({"pose":_geometry.model.instances[i].transform,
			"tint":_geometry.model.materials[i].get_shader_parameter("effect_tint")})
	return result

func verify_samples() -> void:
	# Appearance and model playback are separate caller-owned clocks. In
	# particular neither a hidden portal nor a newly opened one resets playback.
	var samples:=[sample(0,0,1.0,50),sample(1,0,1.0,3050),sample(2,-3000,0.0,3050),
		sample(2,-1500,0.5,4550),sample(2,0,1.0,6050),sample(2,60000,1.0,8750),
		sample(2,61500,0.5,10250),sample(2,63000,0.0,11750),sample(2,63001,-1.0/4096.0,11751)]
	for state in samples:
		var retained: Dictionary=state.duplicate(true);var before:=surfaces();var shown: bool=_geometry.visible
		var frame: Dictionary=_geometry.prepare_state(state)
		check(not frame.is_empty(),_geometry.error)
		check(state==retained and surfaces()==before and _geometry.visible==shown,"Preparing a portal frame changed accepted state")
		if frame.is_empty():continue
		var alioth_state: Dictionary=state.duplicate(true);alioth_state.campaign_cursor=16;alioth_state.visible=false
		var alioth_frame: Dictionary=_alioth.prepare_state(alioth_state)
		check(not alioth_frame.is_empty() and frame.surfaces==alioth_frame.get("surfaces"),"Shared original surface sampling differs by mission")
		_geometry.commit_state(frame)
		if not alioth_frame.is_empty():_alioth.commit_state(alioth_frame)
		check(_geometry.visible==state.visible,"Accepted native portal visibility was ignored")
		for i in frame.surfaces.size():
			check(_geometry.model.instances[i].transform==frame.surfaces[i].pose,"Accepted native portal pose/scale was ignored")
		check(state==retained,"Committing a portal frame advanced a caller-owned clock or phase")

func verify_rejection() -> void:
	var accepted:=sample(2,0,1.0,6050)
	var frame: Dictionary=_geometry.prepare_state(accepted);_geometry.commit_state(frame)
	var before:=surfaces();var shown: bool=_geometry.visible
	for changes in [{"base_content_id":"wrong"},{"binding_id":"wrong"},{"campaign_cursor":16},
		{"system_id":8},{"station_id":49},{"mission_kind":11},{"model_id":16995},{"slot":2},
		{"phase":0},{"phase":1},{"phase":3},{"phase":2.0},{"phase":null},
		{"elapsed_ms":-3001},{"elapsed_ms":0.0},{"elapsed_ms":null},{"elapsed_ms":63001},
		{"visible":false},{"visible":1},{"pose":null},{"pose":Transform3D(Basis.IDENTITY,Vector3(INF,0,0))},
		{"scale":null},{"scale":NAN},{"scale":true},{"animation":null},{"animation":{}},
		{"animation":{"time_ms":-1}},{"animation":{"time_ms":50.0}}]:
		var wrong:=accepted.duplicate(true);wrong.merge(changes,true)
		check(_geometry.prepare_state(wrong).is_empty(),"Malformed portal state was accepted: "+str(changes))
		check(surfaces()==before and _geometry.visible==shown,"Rejected portal frame changed the accepted scene")
	var pending:=sample(2,61500,0.5,10250)
	var ignored: Dictionary=_geometry.prepare_state(pending)
	check(not ignored.is_empty() and surfaces()==before,"Uncommitted sample altered the portal")
	var restored: Dictionary=_geometry.prepare_state(accepted)
	check(not restored.is_empty() and restored.surfaces==frame.surfaces,"Discarded sample contaminated the retained animation state")

func verify_rendering(directory: String) -> void:
	if not directory.is_empty():DirAccess.make_dir_recursive_absolute(directory)
	var samples:=[{"name":"hidden","state":sample(1,0,1.0,3050)},
		{"name":"opening-zero","state":sample(2,-3000,0.0,3050)},
		{"name":"opening-half","state":sample(2,-1500,0.5,4550)},
		{"name":"open","state":sample(2,0,1.0,6050)},
		{"name":"open-animated","state":sample(2,8000,1.0,14050)},
		{"name":"closing-half","state":sample(2,61500,0.5,10250)},
		{"name":"closed","state":sample(2,63001,-1.0/4096.0,11751)}]
	var counts:={};var open_pixels:=PackedByteArray()
	for entry in samples:
		var frame: Dictionary=_geometry.prepare_state(entry.state)
		if frame.is_empty():check(false,_geometry.error);continue
		_geometry.commit_state(frame)
		await process_frame;await RenderingServer.frame_post_draw
		var picture:=_viewport.get_texture().get_image();var count:=0
		for y in range(0,picture.get_height(),4):
			for x in range(0,picture.get_width(),4):
				var pixel:=picture.get_pixel(x,y)
				if pixel.r+pixel.g+pixel.b>0.09:count+=1
		counts[entry.name]=count
		if entry.name=="open":open_pixels=picture.get_data()
		if entry.name=="open-animated":check(picture.get_data()!=open_pixels,"Original portal animation remained static")
		if not directory.is_empty():check(picture.save_png(directory.path_join("sahi-portal-"+entry.name+".png"))==OK,"Portal capture failed")
	check(counts.hidden==0 and counts["opening-zero"]==0 and counts.closed==0,"Hidden or zero-extent portal left visible surfaces")
	check(counts.open>100 and counts["opening-half"]>50 and counts["closing-half"]>50,"Original portal surfaces failed to render")
	check(counts["opening-half"]<counts.open and counts["closing-half"]<counts.open,"Native portal opening/closing scale was lost")
	_viewport.size=Vector2i(844,390)
	_geometry.commit_state(_geometry.prepare_state(sample(2,0,1.0,6050)))
	await process_frame;await RenderingServer.frame_post_draw
	var landscape:=_viewport.get_texture().get_image()
	check(landscape.get_width()==844 and landscape.get_height()==390,"Short landscape viewport was not applied")
	if not directory.is_empty():check(landscape.save_png(directory.path_join("sahi-portal-open-landscape.png"))==OK,"Landscape portal capture failed")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
