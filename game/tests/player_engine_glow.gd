extends SceneTree
## Inspect original Betty geometry from behind. This isolated view tests its
## additive nozzle mesh and LOD ownership, not the missing exhaust emitters.
const Geometry=preload("res://src/presentation/ship_geometry.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
var failures:=0
var checks:=0
var viewport: SubViewport

func _initialize():
	create_timer(30).timeout.connect(func():push_error("Player engine-glow checks timed out");quit(1))
	call_deferred("run")

func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected explicit Mac content, bindings, visuals and optional captures")
	if args.size() in [3,4]:await verify(args)
	print("Player engine glow: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not visuals.open(args[2],library.manifest):
		check(false,library.error+bindings.error+visuals.error);return
	check(bindings.source_architecture=="x86_64","This fixture only verifies the Mac player")
	if bindings.source_architecture!="x86_64":return
	viewport=SubViewport.new();viewport.size=Vector2i(960,540);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera:=Camera3D.new();viewport.add_child(camera)
	camera.look_at_from_position(Vector3(0,320,-1400),Vector3(0,30,0));camera.near=1;camera.far=10000;camera.current=true
	var light:=DirectionalLight3D.new();light.rotation=Vector3(-0.3,PI,0);viewport.add_child(light)
	var ship:=Geometry.new();viewport.add_child(ship)
	check(ship.build(0,library,visuals,bindings,"high",null,true),ship.error)
	if ship.engine_glow==null:ship.free();viewport.free();return
	var glow: Node3D=ship.engine_glow
	check(glow.get_meta("source_resource_id")==17900 and glow.transform==Transform3D.IDENTITY,"Player glow lost its original resource or inherited an invented offset")
	check(not glow.visible,"An unselected ship rendered its nozzle glow")
	for level in ship.levels.size():
		check(ship.apply_selection({"visible":true,"level":level}),ship.error)
		check(glow==ship.engine_glow and glow.visible and ship.levels.filter(func(node):return node.visible).size()==1,"LOD transition lost or duplicated the glow")
	check(ship.apply_selection({"visible":false,"level":-1}) and not glow.visible,"Culled ship retained its glow")
	check(not ship.apply_selection({"visible":true,"level":ship.levels.size()}) and not glow.visible,"Rejected detail selection changed glow visibility")
	check(ship.apply_selection({"visible":true,"level":0}),ship.error)
	ship.hide();check(not glow.is_visible_in_tree(),"Hidden player retained a floating nozzle glow");ship.show()
	if DisplayServer.get_name()!="headless":
		var with_glow:=await rendered()
		glow.hide()
		var without_glow:=await rendered()
		var changed:=0
		for y in with_glow.get_height():
			for x in with_glow.get_width():
				var a:=with_glow.get_pixel(x,y);var b:=without_glow.get_pixel(x,y)
				if a.r-b.r+a.g-b.g+a.b-b.b>0.08:changed+=1
		check(changed>100,"Original nozzle mesh contributed too few additive pixels: "+str(changed))
		check(ship.apply_selection(ship.selection),ship.error)
		var restored:=await rendered()
		check(restored.get_data()==with_glow.get_data(),"Restoring the same selection changed original glow appearance")
		if args.size()==4:
			DirAccess.make_dir_recursive_absolute(args[3])
			check(with_glow.save_png(args[3].path_join("betty-original-nozzle-glow.png"))==OK,"Glow capture failed")
			check(without_glow.save_png(args[3].path_join("betty-without-nozzle-glow.png"))==OK,"Comparison capture failed")
		print("Original nozzle additive pixels: ",changed)
	check(not ship.build(2,library,visuals,bindings,"high",null,true) and ship.get_child_count()==0 and ship.engine_glow==null,"Unsupported player hull reused Betty's glow")
	var material: Array=bindings.materials[34813].duplicate(true)
	for row in bindings.materials[34813]:row.render_type=1
	check(not ship.build(0,library,visuals,bindings,"high",null,true) and ship.get_child_count()==0,"Changed source glow material built a partial ship")
	bindings.materials[34813]=material
	ship.free();viewport.free()

func rendered() -> Image:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)
