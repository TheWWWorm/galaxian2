extends SceneTree
const TargetProjection = preload("res://src/presentation/target_projection.gd")
const Fixture = preload("res://tests/flight_projection_fixture.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Motion = preload("res://src/simulation/opening_scene_motion.gd")
const FlightCamera = preload("res://src/presentation/flight_camera.gd")
var failures := 0

func _initialize() -> void: call_deferred("run")

func run() -> void:
	verify_edges()
	verify_camera_plane()
	verify_invalid()
	var args := OS.get_cmdline_user_args()
	check(args.size() % 3 == 0,"Expected content/binding/visual triples")
	for index in range(0,args.size()-2,3):
		var library := Library.new(); var bindings := Bindings.new()
		if not library.open(args[index]) or not bindings.open(args[index+1],library.manifest):
			check(false,library.error+bindings.error); continue
		verify_perspective(bindings.flight_projection)
		verify_opening(library,bindings)
		print(library.manifest.profile.edition,": ordinary target perspective verified")
	print("Target projection checks: %d failures" % failures)
	quit(1 if failures else 0)

func verify_edges() -> void:
	var data: Dictionary = Fixture.definition(true)
	data.vertical_fov_radians = PI / 2.0
	data.near = 20.0
	var geometry := TargetProjection.new()
	check(geometry.configure(data,Vector2i(800,600),Vector2(100,75)),geometry.error)
	# Analytic 90-degree perspective; integer half-screen centers and inclusive
	# left/top, exclusive right/bottom edges are visible without an ellipse clamp.
	for row in [
		[Vector3(0,0,-300),Vector2i(400,300),true,true,false],
		[Vector3(300,0,-300),Vector2i(700,300),true,true,false],
		[Vector3(-400,0,-300),Vector2i(0,300),true,true,false],
		[Vector3(400,0,-300),Vector2i(500,300),true,false,true],
		[Vector3(0,300,-300),Vector2i(400,0),true,true,false],
		[Vector3(0,-300,-300),Vector2i(400,375),true,false,true],
		[Vector3(0,0,20),Vector2i(400,300),true,true,false],
		[Vector3(0,0,-1),Vector2i(400,300),true,true,false],
		[Vector3(0,0,-1000000),Vector2i(400,300),true,true,false],
	]:
		var result := geometry.project(Transform3D.IDENTITY,row[0])
		check(not result.has("error"),geometry.error)
		if result.has("error"): continue
		check(result.pixels==row[1] and result.projected==row[2] and result.in_view==row[3] and result.ellipse_clamped==row[4],"Target frustum boundary mismatch: %s -> %s" % [row[0],result])
	# Early rejection keeps camera-space data. For a point within the ellipse,
	# the source retains X/-Y rather than manufacturing a screen-border marker.
	for position in [Vector3(400,300,21),Vector3(400,300,0),Vector3(350,280,21)]:
		var result := geometry.project(Transform3D.IDENTITY,position)
		check(not result.has("error") and not result.projected and not result.in_view and not result.ellipse_clamped,"Early rejection changed its visibility or ellipse branch")
		if not result.has("error"): check(result.pixels==Vector2i(int(position.x),-int(position.y)),"Early rejection lost its camera-space fallback")
	# A rear target outside the ellipse contracts onto the center frame. These
	# two axis cases avoid relying on an oracle that repeats the implementation.
	for position in [Vector3(800,300,21),Vector3(400,600,21)]:
		var result := geometry.project(Transform3D.IDENTITY,position)
		var expected := Vector2i(500,300) if position.x==800 else Vector2i(400,375)
		check(not result.has("error") and result.pixels==expected and result.ellipse_clamped and not result.in_view,"Rear marker did not use the center-frame ellipse")
	check(geometry.configure(data,Vector2i(801,601),Vector2(100,75)),geometry.error)
	check(geometry.project(Transform3D.IDENTITY,Vector3(0,0,-300)).pixels==Vector2i(400,300),"Odd viewport did not retain integer center")
	check(geometry.configure(data,Vector2i(800,600),Vector2(50,37.5)),geometry.error)
	check(geometry.project(Transform3D.IDENTITY,Vector3(800,300,21)).pixels==Vector2i(450,300),"Compact desktop ellipse ignored native frame sizing")
	var negative_edge := geometry.project(Transform3D.IDENTITY,Vector3(-400.5,0,-300))
	check(not negative_edge.has("error") and not negative_edge.in_view and negative_edge.ellipse_clamped,"Pixel truncation incorrectly made a negative projection visible")

func verify_opening(library: RefCounted, bindings: RefCounted) -> void:
	var catalogues := Catalogues.new()
	check(catalogues.open(library),catalogues.error)
	var motion := Motion.new()
	if not motion.configure(bindings,catalogues,catalogues.content_id): check(false,motion.error); return
	var geometry := TargetProjection.new()
	check(geometry.configure(bindings.flight_projection,Vector2i(800,600),Vector2(152,114)),geometry.error)
	var viewport := SubViewport.new(); viewport.size=Vector2i(800,600); root.add_child(viewport)
	var camera := Camera3D.new(); viewport.add_child(camera); camera.current=true
	var presentation := FlightCamera.new()
	check(presentation.configure(bindings.flight_projection,0,false).is_empty(),"Opening camera configuration failed")
	var flags := []; flags.resize(23); flags.fill(false)
	var radio := {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"finished":flags}
	var observed := 0
	for event in [-1,2,6,7,8]:
		if event>=0: flags[event]=true
		check(motion.update(16,1000,radio),motion.error)
		var state: Dictionary=motion.snapshot()
		var view: Dictionary=state.camera.view
		check(presentation.apply(camera,view).is_empty(),"Opening camera could not be presented")
		for actor in state.scene.actors:
			var result := geometry.project(view.pose,actor.position)
			check(not result.has("error"),geometry.error)
			if result.has("error") or not result.projected: continue
			# Camera3D computes its perspective independently of this HUD helper.
			var rendered := camera.unproject_position(actor.position)
			check(result.screen_position.distance_to(rendered)<0.05,"Authored actor marker disagrees with its rendered camera")
			observed+=1
	check(observed>=9,"Opening projection checks missed authored target/camera pairs")
	viewport.free()

func verify_camera_plane() -> void:
	var data: Dictionary=Fixture.definition(true)
	data.near=20.0
	var geometry:=TargetProjection.new()
	check(geometry.configure(data,Vector2i(800,600),Vector2(100,75)),geometry.error)
	# These finite targets cross beside the camera. Tiny nonzero depth can
	# produce billions of pixels (or overflow a float32), but remains offscreen.
	for z in [-0.01,-0.0001,-1e-12,-1e-30,-1e-40,1e-40,1e-30,1e-12,0.0001,0.01]:
		for xy in [Vector2(1000,0),Vector2(-1000,0),Vector2(0,1000),Vector2(0,-1000),Vector2(1000,1000)]:
			var point:=Vector3(xy.x,xy.y,z)
			var raw:=geometry.project_point(Transform3D.IDENTITY,point)
			check(not raw.has("error"),"Finite camera-plane target failed raw projection: %s"%[raw])
			if raw.has("error"):continue
			check(not raw.in_view and raw.projected and TargetProjection.safe_pixel(raw.screen_position.x) and TargetProjection.safe_pixel(raw.screen_position.y),"Camera-plane projection reached unsafe pixels or became visible")
			var result:=geometry.project(Transform3D.IDENTITY,point)
			check(not result.has("error"),"Finite camera-plane target stopped marker projection: %s"%[result])
			if result.has("error"):continue
			# Independent analytic ellipse intersection. Magnitude and perspective
			# depth cancel; a positive depth reverses the projected direction.
			var direction:=Vector2(xy.x,-xy.y)*(-1.0 if z>0 else 1.0)
			var unit:=Vector2(direction.x/100.0,direction.y/75.0).normalized()
			var expected:=Vector2(400+unit.x*100.0,300+unit.y*75.0)
			check(result.ellipse_clamped and not result.in_view and Vector2(result.pixels).distance_to(expected)<1.5,"Camera-plane marker lost its ellipse direction: %s"%[result])
	for point in [Vector3(-2147483520.0,200,21),Vector3(2147483648.0,0,21),Vector3(0,-2147483648.0,21),Vector3(1000,0,0)]:
		var result:=geometry.project(Transform3D.IDENTITY,point)
		check(not result.has("error") and not result.in_view and not result.projected and result.ellipse_clamped,"Finite early-rejected target did not retain an offscreen marker")

func verify_perspective(data: Dictionary) -> void:
	# Compare independently against the analytic vertical frustum in several
	# aspect ratios and translated/rolled cameras. Pixel truncation allows <1 px;
	# source float32 camera cancellation at these magnitudes adds a small margin.
	var geometry := TargetProjection.new()
	var camera := Transform3D(Basis.from_euler(Vector3(0.3,-0.7,0.25)),Vector3(31000,-21000,9000))
	for size in [Vector2i(801,601),Vector2i(1280,720),Vector2i(901,601)]:
		check(geometry.configure(data,size,Vector2(152,114)),geometry.error)
		for x in [-0.8,-0.35,0.0,0.45,0.8]:
			for y in [-0.8,-0.3,0.0,0.4,0.8]:
				var depth := 2200.0
				var tangent := tan(float(data.vertical_fov_radians)*0.5)
				var local := Vector3(x*depth*tangent*float(size.x)/size.y,y*depth*tangent,-depth)
				var result := geometry.project(camera,camera*local)
				check(not result.has("error"),geometry.error)
				if result.has("error"): continue
				var expected := Vector2((size.x>>1)+x*size.x*0.5,(size.y>>1)-y*size.y*0.5)
				check(result.in_view and not result.ellipse_clamped and result.projected,"Interior target was hidden or clamped")
				check(result.screen_position.distance_to(expected)<0.01 and Vector2(result.pixels).distance_to(expected)<1.43,"Translated target perspective differs from analytic frustum")

func verify_invalid() -> void:
	var geometry := TargetProjection.new()
	var data: Dictionary = Fixture.definition(false)
	check(geometry.project(Transform3D.IDENTITY,Vector3.FORWARD).has("error"),"Unconfigured target projection accepted a target")
	for state in [[{},Vector2i(800,600),Vector2(100,75)],[data,Vector2i(0,600),Vector2(100,75)],[data,Vector2i(800,600),Vector2(0,75)],[data,Vector2i(800,600),Vector2(INF,75)],[data,Vector2i(40000,600),Vector2(100,75)]]:
		check(geometry.configure(data,Vector2i(800,600),Vector2(100,75)),geometry.error)
		check(not geometry.configure(state[0],state[1],state[2]),"Invalid target geometry retained configuration")
		check(geometry.project(Transform3D.IDENTITY,Vector3.FORWARD).has("error"),"Rejected geometry left an active projector")
	check(geometry.configure(data,Vector2i(800,600),Vector2(100,75)),geometry.error)
	for pose in [Transform3D(Basis.IDENTITY.scaled(Vector3(2,1,1)),Vector3.ZERO),Transform3D(Basis.IDENTITY.scaled(Vector3(-1,1,1)),Vector3.ZERO),Transform3D(Basis.IDENTITY,Vector3(NAN,0,0))]:
		check(geometry.project(pose,Vector3.FORWARD).has("error"),"Invalid camera pose projected a target")
	for position in [Vector3(INF,0,0),Vector3(NAN,0,0)]:
		check(geometry.project(Transform3D.IDENTITY,position).has("error"),"Unsupported target coordinates reached pixel conversion")
	check(not geometry.project(Transform3D.IDENTITY,Vector3.FORWARD).has("error"),"Rejected target damaged projector configuration")
	geometry.clear()
	check(geometry.project(Transform3D.IDENTITY,Vector3.FORWARD).has("error"),"Clear retained target configuration")

func check(condition: bool,message: String) -> void:
	if not condition: failures+=1; push_error(message)
