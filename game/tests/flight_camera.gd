extends SceneTree
const Camera = preload("res://src/presentation/flight_camera.gd")
const Definitions = preload("res://src/content/flight_projection_definitions.gd")
const Fixture = preload("res://tests/flight_projection_fixture.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Library = preload("res://src/content/library.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Motion = preload("res://src/simulation/opening_scene_motion.gd")
const View = preload("res://src/simulation/camera_view.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for mac in [true, false]:
		var data: Dictionary = JSON.parse_string(JSON.stringify(Fixture.definition(mac)))
		var arch := "x86_64" if mac else "armv7"
		check(Definitions.validate(data, 65536, arch).is_empty(), "Valid projection rejected")
		for bad in ["missing", "fov", "near", "far", "extended", "axis", "cursor", "extent", "overlap"]:
			var copy := data.duplicate(true)
			match bad:
				"missing": copy.erase("far")
				"fov": copy.vertical_fov_radians = NAN
				"near": copy.near = true
				"far": copy.far = copy.near
				"extended": copy.matching_location_early_far = -1
				"axis": copy.fov_axis = "horizontal"
				"cursor": copy.early_cursor_limit = 0.5
				"extent": copy.provenance.start.offset = 65536
				"overlap": copy.provenance.start.offset = copy.provenance.setter.offset
			check(not Definitions.validate(copy, 65536, arch).is_empty(), "Malformed projection accepted: " + bad)
		verify_camera(data)
	var args := OS.get_cmdline_user_args()
	check(args.size() % 2 == 0, "Expected content/bindings pairs")
	for i in range(0, args.size()-1, 2):
		var library := Library.new(); var bindings := Bindings.new()
		check(library.open(args[i]), library.error)
		check(bindings.open(args[i+1], library.manifest), bindings.error)
		if bindings.flight_projection.is_empty():
			check(false, "Original profile missing projection")
			continue
		verify_camera(bindings.flight_projection)
		verify_opening(library, bindings)
		print(library.manifest.profile.edition + ": native flight perspective verified")
	print("Flight camera checks: %d failures" % failures)
	quit(1 if failures else 0)

func verify_opening(library: RefCounted, bindings: RefCounted) -> void:
	var catalogues := Catalogues.new()
	check(catalogues.open(library), catalogues.error)
	var motion := Motion.new()
	check(motion.configure(bindings,catalogues,catalogues.content_id), motion.error)
	if motion.snapshot().is_empty(): return
	var presentation := Camera.new()
	# This is an explicit test state, not a claim about the opening location flag.
	check(presentation.configure(bindings.flight_projection,0,false).is_empty(), "Source projection configuration failed")
	var camera := Camera3D.new()
	root.add_child(camera)
	var flags := []; flags.resize(23); flags.fill(false)
	var radio := {"base_content_id": bindings.base_content_id, "binding_id": bindings.binding_id, "finished": flags}
	for event in [-1,2,6,7,8]:
		if event >= 0: flags[event] = true
		check(motion.update(16,1000,radio), motion.error)
		var view: Dictionary = motion.snapshot().camera.view
		check(presentation.apply(camera,view).is_empty(), "Opening view could not be presented")
		check(camera.global_transform.is_equal_approx(view.pose), "Opening view pose changed")
	camera.free()

func verify_camera(data: Dictionary) -> void:
	var presentation := Camera.new()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	var view := View.fixed_eye(Vector3(17, 23, 41), Transform3D(Basis.IDENTITY, Vector3(-5, 4, 2)), true)
	var limit: int = data.early_cursor_limit
	for matching in [true, false]:
		for cursor in [0, maxi(0, limit-1), limit, limit+1]:
			check(presentation.configure(data, cursor, matching).is_empty(), "Valid state rejected")
			var expected: float = data.matching_location_early_far if matching and cursor < limit else data.far
			check(presentation.settings().far == expected, "Far-plane threshold mismatch")
			check(presentation.apply(camera, view).is_empty(), "Camera apply failed")
			check(is_equal_approx(camera.far, expected) and is_equal_approx(camera.near, data.near), "Clip planes were not applied")
			check(camera.global_transform.is_equal_approx(view.pose), "Camera pose changed during presentation")
	# Check actual Camera3D projection, including live viewport resizes. The test
	# oracle uses analytic frustum corners independently of Godot's matrix builder.
	for size in [Vector2i(1600,900), Vector2i(900,1600), Vector2i(1024,1024)]:
		viewport.size = size
		var projection := camera.get_camera_projection()
		var tangent := tan(float(data.vertical_fov_radians) / 2.0)
		var aspect: float = float(size.x) / size.y
		var depth := float(data.near) * 3.0
		var top := project(projection, Vector3(0, depth*tangent, -depth))
		var right := project(projection, Vector3(depth*tangent*aspect, 0, -depth))
		check(absf(top.y-1.0) < 0.00001 and absf(top.x) < 0.00001, "Vertical FOV changed with aspect")
		check(absf(right.x-1.0) < 0.00001 and absf(right.y) < 0.00001, "Horizontal FOV ignores viewport aspect")
		check(absf(project(projection, Vector3(0,0,-camera.near)).z+1.0) < 0.00001, "Near clip plane mismatch")
		check(absf(project(projection, Vector3(0,0,-camera.far)).z-1.0) < 0.00001, "Far clip plane mismatch")
	var before := camera.global_transform
	for bad in [{}, {"pose": Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)}, {"pose": Transform3D(Basis.IDENTITY, Vector3(NAN,0,0))}]:
		check(not presentation.apply(camera,bad).is_empty() and camera.global_transform == before, "Invalid view mutated camera")
	for state in [[-1,true], [0,1], [true,false], [0.5,true]]:
		check(not presentation.configure(data,state[0],state[1]).is_empty() and presentation.settings().is_empty(), "Invalid state retained camera configuration")
		check(not presentation.apply(camera,view).is_empty(), "Unconfigured camera applied a view")
	viewport.free()

func project(projection: Projection, point: Vector3) -> Vector3:
	var clip := projection * Vector4(point.x,point.y,point.z,1)
	return Vector3(clip.x,clip.y,clip.z) / clip.w

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
