extends "res://tests/gate_transit_geometry.gd"
## Original destination resources in diagnostic views, without an earned arrival.
const Planets=preload("res://src/presentation/opening_planet_geometry.gd")
const SkyGeometry=preload("res://src/presentation/opening_sky.gd")
const Exterior=preload("res://src/presentation/station_exterior_geometry.gd")
const ExteriorResources=preload("res://src/content/station_exterior_resources.gd")
const Hangar=preload("res://src/presentation/hangar_geometry.gd")
const StationView=preload("res://src/content/station_presentation_definitions.gd")
const StationMotion=preload("res://src/simulation/station_camera.gd")
const StationScene=preload("res://src/presentation/station_session.gd")

func _initialize():
	create_timer(120).timeout.connect(func():push_error("Destination geometry timed out");quit(1))
	call_deferred("run")

func run():
	var args:=OS.get_cmdline_user_args()
	if args.size() in [3,4]:await render_worlds(args)
	else:check(false,"Expected content, bindings, visuals and optional captures")
	print("Ordinary destination geometry: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func render_worlds(args: PackedStringArray):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new();var visuals:=Visuals.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not visuals.open(args[2],lib.manifest):check(false,lib.error+bindings.error+cat.error+visuals.error);return
	if not load("res://src/content/ordinary_world_definitions.gd").available(bindings):check(false,"Supply ordinary destination declarations");return
	var viewport:=SubViewport.new();viewport.size=Vector2i(1280,720);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera:=Camera3D.new();camera.current=true;camera.near=10;camera.far=250000;viewport.add_child(camera)
	var flight_light:=Node3D.new();viewport.add_child(flight_light)
	var light:=DirectionalLight3D.new();light.rotation=Vector3(-0.65,-0.6,0);flight_light.add_child(light)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.4
	flight_light.add_child(environment)
	var sky:=SkyGeometry.new();var planets:=Planets.new();var exterior:=Exterior.new();var gates:=Geometry.new()
	for node in [sky,planets,exterior,gates]:viewport.add_child(node)
	for station in [70,71,72,73,74]:
		if not sky.build_lounge(lib,visuals,bindings,cat,station,18) or not planets.build_lounge(lib,visuals,bindings,cat,station,18):check(false,sky.error+planets.error);break
		var index: int=planets.selection.selected_index-1
		check(planets.models.size()==5 and planets.selection.system_id==14 and sky.selection.system_id==14,"Destination rendered the wrong world")
		camera.position=Vector3.ZERO;camera.look_at(planets._layout.entries[index+1].origin)
		check(sky.apply_view({"pose":camera.transform}) and planets.apply_view({"pose":camera.transform}),sky.error+planets.error)
		await capture(viewport,args,"magnetar-%d-planet"%station)
		var with_planet:=await pixels(viewport)
		planets.models[index].hide()
		check((await pixels(viewport))!=with_planet,"Current planet contributed no pixels at%d"%station)
		planets.models[index].show()
		var resources:=ExteriorResources.new()
		if not resources.configure_ordinary_location(lib,bindings,cat,station) or not exterior.build(lib,visuals,bindings,resources):check(false,resources.error+exterior.error);break
		var state:=resources.snapshot();var radius:=float(state.sphere.w)
		camera.look_at_from_position(Vector3(radius*1.5,radius*0.75,-radius*1.8),state.pose.origin)
		check(sky.apply_view({"pose":camera.transform}) and planets.apply_view({"pose":camera.transform}),sky.error+planets.error)
		check(exterior.layers.size()==3 and exterior.station.get_meta("source_station_id")==station,"Destination exterior layer identity changed")
		await capture(viewport,args,"magnetar-%d-exterior"%station)
		var with_exterior:=await pixels(viewport)
		exterior.hide()
		check((await pixels(viewport))!=with_exterior,"Station exterior contributed no pixels at%d"%station)
		exterior.show()
		exterior.clear()
		if station==70:
			var clock:=GateAnimation.new()
			if not clock.configure(bindings,cat,lib,station) or not gates.build(lib,visuals,bindings,cat,clock.snapshot().layout):check(false,clock.error+gates.error);break
			check(gates.apply_animation(clock),gates.error)
			var gate: Dictionary=clock.snapshot().layout.objects[0]
			camera.look_at_from_position(gate.pose.origin+Vector3(17000,13000,-21000),gate.pose.origin)
			check(sky.apply_view({"pose":camera.transform}) and planets.apply_view({"pose":camera.transform}),sky.error+planets.error)
			await capture(viewport,args,"magnetar-70-gate")
			gates.clear()
	flight_light.free();sky.free();planets.free();exterior.free();gates.free()
	# Each destination independently resolves the original Terran row. Use the
	# same native camera and lighting adapter as actual station presentation.
	var lighting:=StationScene.new();viewport.add_child(lighting)
	var hangar:=Hangar.new();viewport.add_child(hangar)
	for station in [70,71,72,73,74]:
		var selected: Dictionary=bindings.resolve_hangar(station,cat)
		selected.ship=bindings.resolve_hangar_ship(0)
		var view:=StationView.select(bindings,station,18)
		var motion:=StationMotion.new()
		if not motion.configure(view,13) or not hangar.build(selected,lib,visuals,bindings):check(false,motion.error+hangar.error);break
		if station==70:lighting.build_lighting(view.light)
		camera.set_perspective(rad_to_deg(view.camera.projection[0]),view.camera.projection[1],view.camera.projection[2])
		camera.transform=motion.snapshot().pose
		check(selected.row==0 and selected.station_id==station and not hangar.models.is_empty(),"Destination hangar lost its original selection")
		await capture(viewport,args,"magnetar-%d-hangar"%station)
	viewport.free()

func pixels(viewport: SubViewport) -> PackedByteArray:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image().get_data()
