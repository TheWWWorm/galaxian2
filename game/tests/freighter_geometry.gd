extends SceneTree
## Original freighter hull, cargo modules and both distance levels. This fixture
## validates presentation; live encounter control has a separate owner.
const Geometry=preload("res://src/presentation/ship_geometry.gd")
const Detail=preload("res://src/presentation/ship_detail.gd")
const Models=preload("res://src/presentation/model_resources.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
var checks:=0
var failures:=0

func _initialize():
	create_timer(60).timeout.connect(func():push_error("Freighter geometry checks timed out");quit(1))
	call_deferred("run")

func run():
	var args:=OS.get_cmdline_user_args()
	if args.size() in [3,4]:await verify(args)
	else:check(false,"Expected explicit content, bindings, visuals and optional captures")
	print("Freighter geometry: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not visuals.open(args[2],library.manifest):check(false,library.error+bindings.error+visuals.error);return
	if bindings.ambient_population.is_empty():check(false,"This fixture requires original mixed-traffic declarations");return
	var assembly: Dictionary=bindings.ambient_population.freighter.assembly.duplicate(true)
	var paths:=[]
	for id in [17049,17050,17052,17053,17054,17055]:paths.append(bindings.resolve(id,"mesh"))
	var shared:=Models.new()
	if not shared.prepare(paths,library,visuals,bindings,"high",true):check(false,shared.error);return
	var viewport:=SubViewport.new();viewport.size=Vector2i(960,540);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera:=Camera3D.new();viewport.add_child(camera);camera.current=true;camera.near=10;camera.far=250000
	camera.look_at_from_position(Vector3(10500,8000,-13500),Vector3(0,0,900))
	var light:=DirectionalLight3D.new();light.rotation=Vector3(-0.65,-0.6,0);viewport.add_child(light)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.4
	viewport.add_child(environment)
	var ship:=Geometry.new();viewport.add_child(ship)
	var selector:=Detail.new()
	check(selector.configure_freighter(bindings.ambient_population,bindings.ship_lod),selector.error)
	# Independent binary32 thresholds: square-to-float, then detail factor.
	for pair in [[0.0,612499968.0],[0.5,918749952.0],[1.0,1224999936.0]]:
		var detail: float=pair[0]
		var boundary: float=pair[1]
		check(selector.select(boundary,detail)=={"visible":true,"level":0},"Freighter LOD changed at threshold equality")
		check(selector.select(boundary+256,detail)=={"visible":true,"level":1},"Freighter LOD ignored the source detail band")
	check(selector.select(90000.0*90000.0,1.0).visible,"Freighter borrowed the ordinary fighter distance cull")
	var module_pixels:=[]
	for count in 4:
		assembly.container_count=count
		if not ship.build_freighter(assembly,library,visuals,bindings,"high",shared):check(false,ship.error);break
		check(ship.levels.size()==2 and ship.get_meta("source_ship_id")==15 and ship.engine_glow==null,"Freighter lost its special hull or acquired a player glow")
		for index in 2:
			var body: Node3D=ship.levels[index]
			check(not body.visible and body.get_meta("source_resource_id")==[17049,17050][index],"Freighter starts visible or uses the wrong original hull")
			var parts: Array=body.get_children().filter(func(node):return node.has_meta("source_resource_id"))
			check(parts.size()==count+(2 if index==0 else 1),"Freighter lost or duplicated a cargo module, engine or light")
			var containers:=[]
			for part in parts:
				var id: int=part.get_meta("source_resource_id")
				if id in [17052,17053]:
					check(id==[17052,17053][index] and part.position==Vector3(0,0,[-2150,2150,4300][containers.size()]),"Container used an invented location or wrong detail mesh")
					containers.append(part)
				else:check(id in ([17054,17055] if index==0 else [17054]) and part.transform==Transform3D.IDENTITY,"Unexpected shared child or transform")
			check(containers.size()==count,"Cargo module count changed with LOD")
		for index in 2:
			check(ship.apply_selection({"visible":true,"level":index}),ship.error)
			check(ship.levels.filter(func(node):return node.visible).size()==1 and ship.levels[index].visible,"Freighter drew overlapping LODs")
			if DisplayServer.get_name()!="headless":
				var image:=await rendered(viewport)
				var foreground:=0
				var background:=image.get_pixel(0,0)
				for y in range(0,image.get_height(),2):
					for x in range(0,image.get_width(),2):
						var pixel:=image.get_pixel(x,y)
						if absf(pixel.r-background.r)+absf(pixel.g-background.g)+absf(pixel.b-background.b)>0.09:foreground+=1
				check(foreground>100,"Original freighter did not render appreciable geometry")
				if index==0:module_pixels.append(foreground)
				if args.size()==4:
					DirAccess.make_dir_recursive_absolute(args[3])
					check(image.save_png(args[3].path_join("midorian-freighter-%d-modules-lod-%d.png"%[count,index]))==OK,"Freighter capture failed")
		var before:=ship.selection.duplicate(true)
		check(not ship.apply_detail(-1,1) and ship.selection==before,"Invalid freighter detail changed rendered state")
		check(ship.apply_selection({"visible":false,"level":-1}) and ship.levels.all(func(node):return not node.visible),"Hidden freighter retained floating parts")
	if module_pixels.size()==4:check(module_pixels[3]>module_pixels[0]+100,"Additional original cargo modules did not affect the rendered silhouette")
	for invalid in [-1,4,1.5,true]:
		assembly.container_count=invalid
		check(not ship.build_freighter(assembly,library,visuals,bindings) and ship.get_child_count()==0,"Invalid cargo-module count left a partial freighter")
	assembly.container_count=2
	assembly.container_lod_model_id=17055
	check(not ship.build_freighter(assembly,library,visuals,bindings) and ship.get_child_count()==0,"Freighter accepted lights as its container LOD")
	assembly=bindings.ambient_population.freighter.assembly.duplicate(true);assembly.container_count=2
	shared.clear()
	check(not ship.build_freighter(assembly,library,visuals,bindings,"high",shared) and ship.get_child_count()==0,"Missing shared assets left a partial freighter")
	ship.free();viewport.free()

func rendered(viewport: SubViewport) -> Image:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)
