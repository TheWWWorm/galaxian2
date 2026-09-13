extends SceneTree
const CameraView = preload("res://src/simulation/camera_view.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Library = preload("res://src/content/library.gd")
const Staging = preload("res://src/simulation/opening_staging.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var base := CameraView.fixed_eye(Vector3(0, 0, 10), Transform3D.IDENTITY, false)
	check(base.has("pose") and base.pose == Transform3D(Basis.IDENTITY, Vector3(0, 0, 10)), "Axis-aligned view is mirrored")
	var rolled := Transform3D(Basis(Vector3.BACK, PI / 2), Vector3.ZERO)
	var level := CameraView.fixed_eye(Vector3(0, 0, 10), rolled, false)
	var inherited := CameraView.fixed_eye(Vector3(0, 0, 10), rolled, true)
	check(level.pose == base.pose, "World-up view inherited target roll")
	check(inherited.pose.basis.y.is_equal_approx(Vector3.LEFT) and inherited.pose.basis.x.is_equal_approx(Vector3.UP), "Target up was not preserved")
	for i in 128:
		var eye := Vector3(230 * cos(i * 0.71), -100 + i * 3, 175 * sin(i * 0.41))
		var target := Transform3D(Basis.from_euler(Vector3(i * 0.02, i * -0.03, i * 0.04)), Vector3(i * 7, i * -9, i * 11))
		for inherit in [false, true]:
			var result := CameraView.fixed_eye(eye, target, inherit)
			check(result.has("pose"), result.get("error", "Missing camera pose"))
			if not result.has("pose"): continue
			var pose: Transform3D = result.pose
			var local_target: Vector3 = pose.affine_inverse() * target.origin
			check(absf(local_target.x) < 0.001 and absf(local_target.y) < 0.001 and local_target.z < 0, "Target is not centered in front of camera")
			check(pose.origin == eye and pose.basis.is_equal_approx(pose.basis.orthonormalized()) and is_equal_approx(pose.basis.determinant(), 1), "View changed eye or introduced scale/reflection")
			var shifted := CameraView.fixed_eye(eye + Vector3(20000, -17000, 31000), Transform3D(target.basis, target.origin + Vector3(20000, -17000, 31000)), inherit)
			# Float32 coordinates around 31000 quantize the shortest (35-unit)
			# eye/target separation enough to change direction by 16 microradians.
			# Bound axis error directly; relative component comparisons near zero
			# reject this harmless coordinate rounding.
			for axis in 3:
				check(shifted.pose.basis[axis].distance_to(pose.basis[axis]) < 0.00002, "World translation changed the view rotation beyond coordinate precision")
	for bad in ["same", "parallel", "eye_nan", "target_nan", "basis_nan", "scale", "reflection"]:
		var eye := Vector3(0, 0, 10)
		var target := Transform3D.IDENTITY
		match bad:
			"same": eye = Vector3.ZERO
			"parallel": eye = Vector3(0, 10, 0)
			"eye_nan": eye.x = NAN
			"target_nan": target.origin.z = NAN
			"basis_nan": target.basis.y.x = NAN
			"scale": target.basis = Basis.from_scale(Vector3(2, 2, 2))
			"reflection": target.basis.x = Vector3.LEFT
		var result := CameraView.fixed_eye(eye, target, true)
		check(result.has("error") and not result.has("pose"), "Invalid camera pose accepted: " + bad)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	await process_frame
	var cases := [{"eye": Vector3(0, 0, 10), "target": Transform3D.IDENTITY, "name": "axis"},
		{"eye": Vector3(-1000, -500, -40000), "target": Transform3D(Basis.IDENTITY, Vector3(0, 0, -60000)), "name": "opening initial geometry"}]
	var args := OS.get_cmdline_user_args()
	check(args.size() % 2 == 0, "Expected content/binding pairs")
	for i in range(0, args.size() - 1, 2):
		var library := Library.new()
		var bindings := Bindings.new()
		check(library.open(args[i]), library.error)
		check(bindings.open(args[i + 1], library.manifest), bindings.error)
		if bindings.opening_staging.is_empty(): continue
		var data: Dictionary = bindings.opening_staging
		var target := Staging.pose(data.initial.player_position, data.initial.player_forward, data.initial.player_up)
		cases.append({"eye": Staging.vec(data.initial.camera_position_parameter), "target": target, "name": library.manifest.profile.edition + " initial"})
		target.origin = Staging.vec(data.formation.player_position)
		cases.append({"eye": Staging.vec(data.formation.camera_position_parameter), "target": target, "name": library.manifest.profile.edition + " formation"})
	for row in cases:
		var result := CameraView.fixed_eye(row.eye, row.target, true)
		check(result.has("pose"), "Source geometry rejected: " + row.name)
		if not result.has("pose"): continue
		camera.transform = result.pose
		var screen := camera.unproject_position(row.target.origin)
		check(screen.distance_to(Vector2(320, 180)) < 0.01 and not camera.is_position_behind(row.target.origin), "Camera3D projects target incorrectly: " + row.name)
		var right_point: Vector3 = row.target.origin + camera.basis.x * 5
		check(camera.unproject_position(right_point).x > screen.x, "Camera3D right axis is mirrored: " + row.name)
		print(row.name, ": eye preserved, target centered, screen right verified")
	viewport.free()
	print("Camera view checks: %d failures" % failures)
	quit(1 if failures else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
