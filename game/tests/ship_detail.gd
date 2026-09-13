extends SceneTree
const Detail = preload("res://src/presentation/ship_detail.gd")
const Definitions = preload("res://src/content/ship_lod_definitions.gd")
const Geometry = preload("res://src/presentation/ship_geometry.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Visuals = preload("res://src/content/visual_library.gd")
var failures := 0

func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("Ship detail checks timed out"); quit(1))
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Expected content/bindings/visuals triples")
	for i in range(0,args.size()-2,3): await verify_source(args[i],args[i+1],args[i+2])
	print("Ship detail checks: %d failures" % failures)
	quit(1 if failures else 0)

func verify_source(content: String, pack: String, texture_pack: String) -> void:
	var library := Library.new(); var bindings := Bindings.new(); var visuals := Visuals.new()
	check(library.open(content),library.error)
	check(bindings.open(pack,library.manifest),bindings.error)
	check(visuals.open(texture_pack,library.manifest),visuals.error)
	var data: Dictionary = bindings.ship_lod
	check(not data.is_empty(),"Missing original LOD declarations")
	if data.is_empty(): return
	var detail := Detail.new()
	check(detail.configure(data,2),detail.error)
	var mac: bool = library.manifest.profile.edition=="mac-full-hd"
	check(data.detail_boundaries.size()==(2 if mac else 0),"Edition detail policy was replaced")
	var first := float(data.distances[0]*data.distances[0])
	var second := float(data.distances[1]*data.distances[1])
	for value in [-1.0,0.0,0.2,0.5,0.9,1.0,2.0]:
		var factor := 0.5 if mac and value<0.33 else (0.75 if mac and value<0.66 else 1.0)
		var lower := Detail.single(first*factor)
		var upper := Detail.single(second*factor)
		check(detail.select(lower,value)=={"visible":true,"level":0},"Equality selected lower-detail mesh too early")
		check(detail.select(lower+128,value)=={"visible":true,"level":1},"First LOD did not start beyond threshold")
		check(detail.select(upper,value)=={"visible":true,"level":1},"Second threshold equality mismatch")
		check(detail.select(upper+128,value)=={"visible":true,"level":2},"Second LOD did not start beyond threshold")
		var maximum := float(data.maximum_distance*data.maximum_distance)
		check(detail.select(maximum,value)=={"visible":false,"level":-1},"Maximum-distance equality remained visible")
		check(detail.select(maximum-1024,value).visible,"Model disappeared before maximum distance")
	if mac:
		for i in 2:
			var boundary: float = data.detail_boundaries[i]
			var distance: float = first*(data.squared_distance_factors[i]+data.squared_distance_factors[i+1])*0.5
			check(detail.select(distance,boundary).level==1 and detail.select(distance,boundary+0.0001).level==0,"Detail band boundary used the wrong inequality")
	for bad in [[-1,1],[NAN,1],[true,1],[0,INF],[0,true],[0,1e100]]:
		check(detail.select(bad[0],bad[1]).is_empty(),"Invalid distance/detail accepted")
	var changed := data.duplicate(true)
	changed.distances=[100,200];changed.maximum_distance=1000
	check(detail.configure(changed,2) and detail.select(10001,1).level==1,"Native selector ignored changed imported thresholds")
	for invalid in ["distance","gap","child","factors","provenance"]:
		var copy := data.duplicate(true)
		match invalid:
			"distance": copy.distances=[10,9]
			"gap": copy.body_resource_ids[2][0]=65535
			"child": copy.child_resource_ids[2]=[1,65535]
			"factors": copy.squared_distance_factors[0]=NAN
			"provenance": copy.provenance.body.offset=copy.provenance.fill.offset
		check(not Definitions.validate(copy,10000000,"x86_64" if mac else "armv7").is_empty(),"Invalid LOD definition accepted: "+invalid)
	for id in [13,14,15,60 if mac else 63]:
		check(bindings.resolve_ship_detail(id).is_empty(),"Unsupported special/zero-ID LOD was invented")
	var viewport := SubViewport.new();viewport.size=Vector2i(640,480);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera := Camera3D.new();camera.position=Vector3(0,200,1800);camera.look_at_from_position(camera.position,Vector3.ZERO);camera.near=1;camera.far=10000;camera.current=true;viewport.add_child(camera)
	var environment := WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=1
	viewport.add_child(environment)
	var light := DirectionalLight3D.new();viewport.add_child(light)
	for id in [2,8,10,23,37]:
		var scene := Geometry.new();viewport.add_child(scene)
		var built := scene.build(id,library,visuals,bindings)
		if id==37:
			check(not built and "animation" in scene.error and scene.get_child_count()==0,"Animated source hull bypassed the verified static-geometry restriction")
			check(detail.configure(data,id) and detail.select(second+1024,1).level==0,"Empty LOD table invented a replacement mesh")
			scene.free()
			continue
		check(built,scene.error)
		if scene.levels.is_empty(): scene.free();continue
		var selected := bindings.resolve_ship_detail(id)
		check(scene.levels.size()==selected.levels.size(),"LOD assembly size mismatch")
		for level in scene.levels:
			check(not level.visible,"Unselected LOD initially rendered")
		for level in scene.levels.size():
			var distance := 0.0 if level==0 else float(data.distances[level-1]*data.distances[level-1])+1024
			check(scene.apply_detail(distance,1),scene.error)
			for j in scene.levels.size(): check(scene.levels[j].visible==(j==level),"LOD assembly rendered overlapping levels")
			var body: Node3D = scene.levels[level]
			check(body.get_meta("source_resource_id")==selected.levels[level].resource_id,"Wrong replacement mesh")
			var child_count := 0
			for child in body.get_children():
				if child.has_meta("source_resource_id"):
					child_count+=1
					check(child.transform==Transform3D.IDENTITY,"LOD light acquired a placement offset")
			check(child_count==selected.levels[level].lights.size(),"LOD light assembly mismatch")
			if DisplayServer.get_name()!="headless":
				await process_frame; await process_frame; await RenderingServer.frame_post_draw
				var image := viewport.get_texture().get_image()
				var background := image.get_pixel(0,0)
				var foreground := 0
				for y in range(0,image.get_height(),2):
					for x in range(0,image.get_width(),2):
						var pixel := image.get_pixel(x,y)
						if absf(pixel.r-background.r)+absf(pixel.g-background.g)+absf(pixel.b-background.b)>0.03: foreground+=1
				check(foreground>10,"Selected source LOD did not render appreciable geometry")
				var output := OS.get_environment("GOF2_CAPTURE_DIR")
				if not output.is_empty():
					DirAccess.make_dir_recursive_absolute(output)
					check(image.save_png(output.path_join("%s-ship-%d-lod-%d.png" % [library.manifest.profile.edition,id,level]))==OK,"LOD capture failed")
		check(scene.apply_detail(data.maximum_distance*data.maximum_distance,1),scene.error)
		for body in scene.levels: check(not body.visible,"Culled geometry still rendered")
		check(scene.apply_detail(0,1) and scene.levels[0].visible,"Returning near the ship did not restore full detail")
		var before := scene.selection.duplicate()
		check(not scene.apply_detail(NAN,1) and scene.selection==before and scene.levels[0].visible,"Invalid LOD input changed geometry")
		scene.free()
	viewport.free()
	print(library.manifest.profile.edition+": imported LOD meshes, children, detail bands and threshold boundaries verified")

func check(ok: bool,message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)
