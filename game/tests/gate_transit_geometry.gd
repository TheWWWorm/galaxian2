extends "res://tests/gate_transit.gd"
## Diagnostic original gate animation captures, without changing any location.
const Geometry=preload("res://src/presentation/gate_geometry.gd")
const Visuals=preload("res://src/content/visual_library.gd")

func _initialize() -> void:
	create_timer(90).timeout.connect(func():push_error("Gate transit geometry timed out");quit(1))
	call_deferred("run")

func run():
	var args:=OS.get_cmdline_user_args()
	if args.size() in [3,4]:await render_transit(args)
	else:check(false,"Expected content, bindings, visuals and optional captures")
	print("Gate transit geometry: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func render_transit(args: PackedStringArray):
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new();var visuals:=Visuals.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library) or not visuals.open(args[2],library.manifest):check(false,library.error+bindings.error+cat.error+visuals.error);return
	var viewport:=SubViewport.new();viewport.size=Vector2i(1280,720);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera:=Camera3D.new();camera.current=true;camera.near=10;camera.far=250000;viewport.add_child(camera)
	var light:=DirectionalLight3D.new();light.rotation=Vector3(-0.65,-0.6,0);viewport.add_child(light)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.4
	viewport.add_child(environment)
	var geometry:=Geometry.new();viewport.add_child(geometry)
	var seen:={}
	for system in [cat.tables.systems[19]]+cat.tables.systems:
		var type:=int(system.fields[2]);var station:=int(system.fields[6])
		if type not in [0,1,2,3] or station<0 or seen.has(type):continue
		seen[type]=true;var clock:=GateAnimation.new()
		if not clock.configure(bindings,cat,library,station):check(false,clock.error);continue
		var state:=clock.snapshot();var gate: Dictionary=state.layout.objects[0]
		if not geometry.build(library,visuals,bindings,cat,state.layout):check(false,geometry.error);continue
		camera.look_at_from_position(gate.pose.origin+Vector3(17000,13000,-21000),gate.pose.origin)
		check(geometry.apply_animation(clock),geometry.error)
		await capture(viewport,args,"gate-%d-idle"%type)
		var original_poses:=layer_poses(geometry.objects[1])
		var other:=GateAnimation.new()
		check(other.configure(bindings,cat,library,station),other.error)
		check(not geometry.apply_animation(other) and layer_poses(geometry.objects[1])==original_poses,"Unrelated clock changed gate presentation")
		check(clock.activate(1) and geometry.apply_animation(clock),clock.error+geometry.error)
		var outgoing: Dictionary=geometry.objects[1];var incoming: Dictionary=geometry.objects[2]
		check(outgoing.layers[0].visible and outgoing.layers[1].visible and not outgoing.layers[2].visible,"Jump replacement hid the gate body or retained its old child")
		check(outgoing.animated[gate.jump_mesh_id].model.visible and incoming.layers[2].visible,"Jump replacement lost the new or incoming layer")
		await capture(viewport,args,"gate-%d-start"%type)
		for time in [1050,3000,5000]:
			var remaining: int=time-clock.object_state(1).models[3].time_ms
			while remaining>0:
				var step:=mini(remaining,150)
				if not clock.advance(step):check(false,clock.error);break
				remaining-=step
			var before:=clock.snapshot()
			check(geometry.apply_animation(clock) and clock.snapshot()==before,"Rendering mutated accepted gate clocks")
			check(layer_poses(outgoing)!=original_poses,"Animated source layers remained frozen")
			await capture(viewport,args,"gate-%d-%d"%[type,time])
			var accepted:=layer_poses(outgoing)
			check(geometry.apply_animation(clock) and layer_poses(outgoing)==accepted,"Repeated drawing advanced animation")
		check(clock.advance(1) and clock.completed() and geometry.apply_animation(clock),clock.error+geometry.error)
	check(seen.size()==4,"Gate rendering omitted an original faction")
	geometry.free();viewport.free()

func layer_poses(instance: Dictionary) -> Array:
	var poses:=[]
	for row in instance.animated.values():
		for surface in row.model.instances:poses.append(surface.transform)
	return poses

func capture(viewport: SubViewport,args: PackedStringArray,name: String):
	if DisplayServer.get_name()=="headless":return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image:=viewport.get_texture().get_image()
	var foreground:=0;var background:=image.get_pixel(0,0)
	for y in range(0,image.get_height(),4):
		for x in range(0,image.get_width(),4):
			var pixel:=image.get_pixel(x,y)
			if absf(pixel.r-background.r)+absf(pixel.g-background.g)+absf(pixel.b-background.b)>0.09:foreground+=1
	check(foreground>100,"Original animated gate did not render: "+name)
	if args.size()==4:
		DirAccess.make_dir_recursive_absolute(args[3])
		check(image.save_png(args[3].path_join(name+".png"))==OK,"Gate animation capture failed")
