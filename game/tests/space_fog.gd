extends SceneTree
## Spatial persistence and visible cloud depth, using the player's cloud asset.
const Field=preload("res://src/presentation/space_fog_field.gd")
const Clouds=preload("res://src/presentation/space_fog_geometry.gd")
const Background=preload("res://src/presentation/opening_sky.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	create_timer(90).timeout.connect(func():push_error("Space cloud checks timed out");quit(1))
	call_deferred("run")

func run() -> void:
	check_field()
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3 or DisplayServer.get_name()=="headless":check(false,"Space clouds require GPU and content/binding/visuals");quit(1);return
	var library=load("res://src/content/library.gd").new()
	var bindings=load("res://src/content/resource_bindings.gd").new()
	var visuals=load("res://src/content/visual_library.gd").new()
	var catalogues=load("res://src/content/catalogues.gd").new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not visuals.open(args[2],library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+visuals.error+catalogues.error);quit(1);return
	var viewport:=SubViewport.new();viewport.size=Vector2i(384,216);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var world:=WorldEnvironment.new();world.environment=Environment.new()
	world.environment.background_mode=Environment.BG_COLOR;world.environment.background_color=Color.BLACK;viewport.add_child(world)
	var camera:=Camera3D.new();camera.current=true;camera.near=1;camera.far=40000;viewport.add_child(camera)
	var parent:=Node3D.new();viewport.add_child(parent)
	var fog:=Clouds.new();parent.add_child(fog)
	check(fog.build(library,visuals,bindings,9,78),fog.error)
	fog.commit_view(fog.prepare_view(camera.global_transform))
	var accepted:=fog.snapshot()
	var pending: RefCounted=fog.prepare_view(Transform3D(Basis.IDENTITY,Vector3(500,0,0)))
	check(pending!=null and fog.snapshot()==accepted,"Preparing a view moved accepted clouds")
	check(fog.prepare_view(Transform3D(Basis.IDENTITY,Vector3(NAN,0,0)))==null and fog.snapshot()==accepted,"Rejected view changed the cloud field")
	parent.transform=Transform3D(Basis(Vector3.UP,0.8),Vector3(90000,20000,-70000))
	check(fog.global_transform==Transform3D.IDENTITY,"Sky orientation moved world-space clouds")
	# One controlled cloud makes depth ordering independently observable.
	fog.multimesh.visible_instance_count=1
	fog.multimesh.set_instance_transform(0,Transform3D(Basis.IDENTITY,Vector3(0,0,-5000)))
	fog.multimesh.set_instance_color(0,Color.WHITE)
	var cloud:=await capture(viewport)
	check(changed(cloud,Color.BLACK)>100,"Imported cloud texture was invisible")
	check(variation(cloud)>20,"Cloud became a flat screen wash")
	check(cloud.get_data()==(await capture(viewport)).get_data(),"Paused clouds changed appearance")
	var blocker:=MeshInstance3D.new();blocker.mesh=QuadMesh.new();blocker.mesh.size=Vector2(30000,30000)
	var green:=StandardMaterial3D.new();green.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;green.albedo_color=Color(0,0.2,0)
	blocker.material_override=green;blocker.position.z=-1000;viewport.add_child(blocker)
	var foreground:=await capture(viewport)
	fog.hide();var foreground_clear:=await capture(viewport);fog.show()
	check(foreground.get_data()==foreground_clear.get_data(),"Cloud behind opaque geometry covered the foreground")
	blocker.position.z=-10000
	var background:=await capture(viewport)
	fog.hide();var background_clear:=await capture(viewport);fog.show()
	check(difference(background,background_clear)>100,"Cloud in front of distant geometry did not contribute")
	blocker.hide();camera.rotation.y=0.5
	check(difference(cloud,await capture(viewport))>100,"Camera rotation locked the cloud to the screen")
	camera.rotation.y=0
	check(cloud.get_data()==(await capture(viewport)).get_data(),"Camera rotation reseeded the cloud")
	# Shared backgrounds opt in; building a station sky alone is also used indoors.
	var sky:=Background.new();viewport.add_child(sky)
	check(sky.build_station(library,visuals,bindings,catalogues,78),sky.error)
	check(sky.space_fog==null,"Interior sky silently acquired an exterior field")
	var retained_id: String=bindings.binding_id;bindings.binding_id="0".repeat(64)
	check(not sky.enable_space_fog(library,visuals,bindings,catalogues) and sky.space_fog==null,"Another binding pack supplied this location's cloud art")
	bindings.binding_id=retained_id
	check(sky.enable_space_fog(library,visuals,bindings,catalogues) and sky.apply_view({"pose":camera.global_transform}),sky.error)
	check(sky.space_fog!=null and not sky.space_fog.snapshot().positions.is_empty(),"Exterior background did not prepare its nearby clouds")
	var sky_state: Dictionary=sky.space_fog.snapshot()
	var unaccepted: Dictionary=sky.prepare_view({"pose":Transform3D(Basis.IDENTITY,Vector3(1000000,0,0))})
	check(not unaccepted.is_empty() and sky.space_fog.snapshot()==sky_state and sky.global_position==camera.global_position,"Preparing a distant sky view consumed accepted placement")
	check(sky.apply_view({"pose":camera.global_transform}) and sky.space_fog.snapshot()==sky_state,"Discarded scene preparation changed the next accepted sky frame")
	check(not sky.apply_view({"pose":Transform3D(Basis.IDENTITY,Vector3(INF,0,0))}) and sky.space_fog.snapshot()==sky_state,"Invalid sky camera changed accepted clouds")
	sky.clear();check(sky.space_fog==null and sky.get_child_count()==0,"Changing locations retained old cloud geometry")
	if bindings.mido_travel.has("post_sahi"):
		var environment=load("res://src/simulation/void_environment.gd").new()
		if not environment.configure(bindings,{"state":4096}):check(false,environment.error);viewport.free();quit(1);return
		check(sky.build_void(library,visuals,bindings,environment) and sky.space_fog!=null,"The admitted Void omitted its cloud field: "+sky.error)
		if sky.space_fog!=null:
			check(sky.apply_view({"pose":camera.global_transform},{},0),sky.error)
			var first: Dictionary=sky.space_fog.snapshot()
			check(first.tint.is_equal_approx(Color(146.0/255.0,116.0/255.0,212.0/255.0,187.0/255.0)),"Void clouds inherited ordinary palette dimming")
			var flowed: Dictionary=sky.prepare_view({"pose":camera.global_transform},{},500)
			check(not flowed.is_empty() and sky.space_fog.snapshot()==first,"Preparing Void flow changed the displayed frame")
			sky.commit_view(flowed)
			var flowing: Dictionary=sky.space_fog.snapshot()
			var moved_count:=0
			for index in first.positions.size():
				if flowing.positions[index].is_equal_approx(first.positions[index]+Vector3(0,0,1000)):moved_count+=1
			check(moved_count>first.positions.size()/2,"Void clouds did not drift on their fixed world axis")
			check(sky.apply_view({"pose":Transform3D(Basis(Vector3.UP,0.7),camera.position)},{},500) and sky.space_fog.snapshot()==flowing,"Camera rotation advanced or redirected Void clouds")
			check(not sky.apply_view({"pose":camera.global_transform},{},499) and sky.space_fog.snapshot()==flowing,"A rejected Void time damaged the accepted field")
	# Ginoya (supernova system, no cursor = burning): clouds dimmed x0.5 and drifting away from the sun.
	var ginoya:=-1
	for index in catalogues.tables.stations.size():
		if int(catalogues.tables.stations[index].get("system_id",-1))==27:ginoya=index;break
	if ginoya>=0:
		sky.clear()
		check(sky.build_station(library,visuals,bindings,catalogues,ginoya) and sky.enable_space_fog(library,visuals,bindings,catalogues),"Ginoya clouds: "+sky.error)
		if sky.space_fog!=null:
			var nova: Dictionary=sky.space_fog.snapshot()
			var sun: Dictionary=load("res://src/simulation/sun_placement.gd").new().for_station(ginoya,int(catalogues.tables.stations[ginoya].get("planet_type",0)))
			var expected:=Field.new();expected.configure(int(catalogues.tables.systems[27].sky_index),0,Vector3.ZERO,0.5)
			check(nova.velocity.is_equal_approx(-Vector3(sun.direction_to_sun)*2000.0),"Ginoya clouds do not drift away from the sun")
			check(nova.tint==expected.tint,"Ginoya clouds kept the ordinary x0.6 tint")
	viewport.free()
	print("Space clouds: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func check_field() -> void:
	check_drift()
	var field:=Field.new();check(field.configure(9,78),field.error)
	var initial: RefCounted=field.sample(Vector3.ZERO)
	check(initial!=null and field.snapshot().positions.is_empty(),"Preparing clouds mutated their previous frame")
	var state: Dictionary=initial.snapshot()
	check(state.positions.size()>0 and state.positions.size()<=20,"Nearby cloud population is unbounded")
	check(initial.sample(Vector3.ZERO)==initial,"An unchanged camera rebuilt its cloud field")
	var shifted: RefCounted=initial.sample(Vector3(100,0,0))
	var retained:=0
	for index in state.positions.size():
		if shifted.snapshot().positions[index]==state.positions[index]:retained+=1
	check(retained>state.positions.size()/2,"Nearby clouds followed the camera instead of showing parallax")
	check(initial.snapshot()==state,"Moving the camera mutated the prior cloud field")
	var center: Vector3=state.positions[0]
	var strengths:=[]
	for distance in [0.0,500.0,2000.0,4000.0,7000.0,10000.0]:
		strengths.append(initial.sample(center+Vector3.RIGHT*distance).snapshot().weights[0])
	check(strengths[0]==0 and strengths[1]>0 and strengths[1]<strengths[2],"Approaching a cloud did not fade it out near the camera")
	check(strengths[2]==strengths[3] and strengths[4]<strengths[3] and strengths[5]==0,"Far clouds did not fade out beyond their bright middle range")
	var teleported: RefCounted=initial.sample(Vector3(1000000,0,0))
	var jump: Dictionary=teleported.snapshot()
	check(jump.positions.size()==state.positions.size(),"Teleport grew the cloud population")
	var dark:=true;var bounded:=true
	for index in jump.positions.size():
		dark=dark and jump.weights[index]==0
		bounded=bounded and jump.positions[index].distance_to(jump.camera)<11000
	check(dark and bounded,"Recycled clouds popped in brightly or stayed behind the camera")
	check(initial.sample(Vector3(NAN,0,0))==null and initial.snapshot()==state,"Invalid camera damaged the accepted field")

func check_drift() -> void:
	var field:=Field.new();check(field.configure(10,21,Vector3(0,0,2000),1.0),field.error)
	var initial: RefCounted=field.sample(Vector3.ZERO,0)
	# One known center isolates flow from outer-boundary recycling.
	initial._positions[0]=Vector3(0,0,-4000)
	var before: Dictionary=initial.snapshot()
	var moved: RefCounted=initial.sample(Vector3.ZERO,500)
	check(moved.snapshot().positions[0]==Vector3(0,0,-3000) and initial.snapshot()==before,"Cloud flow followed the camera or changed its parent")
	check(moved.sample(Vector3.ZERO,500)==moved,"A repeated or paused cloud view advanced time")
	check(moved.sample(Vector3.ZERO,499)==null and moved.snapshot().positions[0]==Vector3(0,0,-3000),"A rejected clock sample moved clouds")
	var split: RefCounted=initial.sample(Vector3.ZERO,137).sample(Vector3.ZERO,500)
	check(split.snapshot().positions[0].is_equal_approx(moved.snapshot().positions[0]),"Variable steps changed the visible flow speed")
	var parallax: RefCounted=moved.sample(Vector3(100,0,0),500)
	check(parallax.snapshot().positions[0]==moved.snapshot().positions[0],"Camera translation dragged the flowing cloud")
	var recycled: RefCounted=moved.sample(Vector3(1000000,0,0),600)
	var dark:=true
	for value in recycled.snapshot().weights:dark=dark and value==0.0
	check(dark,"Moving clouds recycled brightly")

func capture(viewport: SubViewport) -> Image:
	for tick in 12:await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func changed(image: Image,color: Color) -> int:
	var count:=0
	for y in range(0,image.get_height(),4):
		for x in range(0,image.get_width(),4):
			if Vector3(image.get_pixel(x,y).r-color.r,image.get_pixel(x,y).g-color.g,image.get_pixel(x,y).b-color.b).length()>0.02:count+=1
	return count

func difference(a: Image,b: Image) -> int:
	var count:=0
	for y in range(0,a.get_height(),4):
		for x in range(0,a.get_width(),4):
			var delta:=a.get_pixel(x,y)-b.get_pixel(x,y)
			if Vector3(delta.r,delta.g,delta.b).length()>0.02:count+=1
	return count

func variation(image: Image) -> int:
	var colors:={}
	for y in range(0,image.get_height(),4):
		for x in range(0,image.get_width(),4):colors[image.get_pixel(x,y).to_rgba32()]=true
	return colors.size()

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
