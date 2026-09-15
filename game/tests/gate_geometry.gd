extends "res://tests/gate_environment.gd"
## Original gate assemblies in a diagnostic landscape viewport. This proves
## geometry and pose, not earned travel, activation animation or docking.
const Geometry=preload("res://src/presentation/gate_geometry.gd")
const Visuals=preload("res://src/content/visual_library.gd")

func _initialize() -> void:
	create_timer(90).timeout.connect(func():push_error("Gate geometry timed out");quit(1))
	call_deferred("run")

func run():
	var args:=OS.get_cmdline_user_args()
	if args.size() in [3,4]:await render_gates(args)
	else:check(false,"Expected content, bindings, visuals and optional capture path")
	print("Gate geometry: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func render_gates(args: PackedStringArray):
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new();var visuals:=Visuals.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library) or not visuals.open(args[2],library.manifest):check(false,library.error+bindings.error+cat.error+visuals.error);return
	var viewport:=SubViewport.new();viewport.size=Vector2i(960,540);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera:=Camera3D.new();camera.current=true;camera.near=10;camera.far=250000;viewport.add_child(camera)
	var light:=DirectionalLight3D.new();light.rotation=Vector3(-0.65,-0.6,0);viewport.add_child(light)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.4
	viewport.add_child(environment)
	var geometry:=Geometry.new();viewport.add_child(geometry)
	var seen:={}
	for station in [cat.tables.stations[95]]+cat.tables.stations:
		var type:=int(cat.tables.systems[station.system_id].fields[2])
		if type<0 or type>3 or seen.has(type):continue
		seen[type]=true
		var owner:=Gate.new()
		if not owner.configure(bindings,cat,int(station.id)):check(false,owner.error);continue
		var state:=owner.snapshot()
		if not geometry.build(library,visuals,bindings,cat,state):check(false,geometry.error);continue
		var gate: Dictionary=state.objects[0]
		check(geometry.objects.size()==state.objects.size(),"Gate renderer lost an environment object")
		for row in state.objects:
			var instance: Dictionary=geometry.objects[row.index]
			check(instance.assembly.transform==row.pose,"Gate renderer changed its source world position")
			check(instance.layers.map(func(node):return node.get_meta("source_resource_id"))==[row.mesh_id]+row.child_mesh_ids,"Gate renderer lost original model layers")
		camera.look_at_from_position(gate.pose.origin+Vector3(22000,16000,-28000),gate.pose.origin)
		if DisplayServer.get_name()!="headless":
			await process_frame;await process_frame;await RenderingServer.frame_post_draw
			var image:=viewport.get_texture().get_image()
			var foreground:=0;var background:=image.get_pixel(0,0)
			for y in range(0,image.get_height(),2):
				for x in range(0,image.get_width(),2):
					var pixel:=image.get_pixel(x,y)
					if absf(pixel.r-background.r)+absf(pixel.g-background.g)+absf(pixel.b-background.b)>0.09:foreground+=1
			check(foreground>200,"Original gate geometry did not render")
			if args.size()==4:
				DirAccess.make_dir_recursive_absolute(args[3])
				check(image.save_png(args[3].path_join("gate-type-%d.png"%type))==OK,"Gate capture failed")
		check(geometry.apply_state(state),geometry.error)
		var changed:=state.duplicate(true);changed.objects[0].pose.origin+=Vector3.ONE
		check(not geometry.apply_state(changed),"Changed gate pose was accepted")
		check(not geometry.build(library,visuals,bindings,cat,changed) and geometry.objects.is_empty(),"Changed gate left partial geometry")
	check(seen.size()==4,"A supplied gate faction was omitted")
	geometry.free();viewport.free()
