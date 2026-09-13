extends SceneTree
const Motion = preload("res://src/simulation/flight_motion.gd")
const Definitions = preload("res://src/content/motion_definitions.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Library = preload("res://src/content/library.gd")
var failures := 0

func _initialize() -> void:
	var pose := Transform3D(Basis.IDENTITY, Vector3(17, -23, 80))
	var motion := Motion.new()
	check(motion.advance(pose, Vector2.ZERO, 1, 1) == pose and not motion.error.is_empty(), "Unconfigured flight advanced")
	var bindings := Bindings.new()
	bindings.base_content_id = "a".repeat(64)
	bindings.binding_id = "b".repeat(64)
	bindings.cruise = {"speed_units_per_millisecond": 2.0, "forward_axis": [0, 0, 1]}
	bindings.manual_rotation = {"angle_unit_scale": 1.0 / 65536.0, "radians_per_turn": TAU,
		"time_scale": 0.033, "rotation_order": "local_x_y"}
	check(motion.configure(bindings, bindings.base_content_id), motion.error)
	# A quarter turn in one second expressed in source angular control units.
	var quarter := 65536.0 / (33.0 * 4.0)
	var yaw := motion.advance(pose, Vector2(0, quarter), 1, 1)
	check(yaw.basis.z.distance_to(Vector3.RIGHT) < 0.00001, "Positive local yaw has wrong direction")
	check(yaw.origin.distance_to(pose.origin + Vector3(2000, 0, 0)) < 0.01, "Forward displacement did not follow the updated heading")
	var pitch := motion.advance(pose, Vector2(quarter, 0), 0, 1)
	check(pitch.basis.z.distance_to(Vector3.DOWN) < 0.00001 and pitch.origin == pose.origin, "Pitch or zero-throttle rotation failed")
	var both := motion.advance(pose, Vector2(quarter, quarter), 0, 1)
	check(both.basis.z.distance_to(Vector3.RIGHT) < 0.00001, "Local X/Y composition order changed")
	var tilted := Transform3D(Basis(Vector3.BACK, PI * 0.5), pose.origin)
	var local_yaw := motion.advance(tilted, Vector2(0, quarter), 0, 1)
	check(local_yaw.basis.z.distance_to(Vector3.UP) < 0.00001, "Rotation incorrectly applied around a world axis")
	var divided := pose
	for i in 60: divided = motion.advance(divided, Vector2(0, quarter), 0, 1.0 / 60.0)
	check(divided.basis.is_equal_approx(yaw.basis), "Single-axis heading depends on timestep subdivision")
	var circle := pose
	for i in 240: circle = motion.advance(circle, Vector2(0, quarter), 1, 1.0 / 60.0)
	check(circle.origin.distance_to(pose.origin) < 0.2 and circle.basis.is_equal_approx(pose.basis), "Constant yaw failed a full closed flight circle")
	check(circle.basis.is_equal_approx(circle.basis.orthonormalized()), "Rotation accumulated basis drift")
	check(motion.advance(tilted, Vector2(quarter, quarter), 1, 0) == tilted and motion.error.is_empty(), "Paused simulation changed the pose")
	for values in [[Vector2(NAN, 0), 1.0, 1.0], [Vector2.ZERO, -1.0, 1.0], [Vector2.ZERO, 1.0, -1.0], [Vector2.ZERO, 1.0, INF]]:
		check(motion.advance(pose, values[0], values[1], values[2]) == pose and not motion.error.is_empty(), "Invalid flight input mutated the pose")
	for basis in [Basis.from_scale(Vector3(2, 1, 1)), Basis.from_scale(Vector3(-1, 1, 1))]:
		var invalid := Transform3D(basis, pose.origin)
		check(motion.advance(invalid, Vector2(0, quarter), 1, 1) == invalid and not motion.error.is_empty(), "Visual scale/reflection accepted as flight orientation")
	bindings.manual_rotation.time_scale = 0.1
	check(motion.advance(pose, Vector2(0, quarter), 0, 1).basis.is_equal_approx(yaw.basis), "Configured motion retained a mutable parameter reference")
	check(not motion.configure(bindings, "c".repeat(64)) and motion.binding_id.is_empty(), "Cross-content flight configuration retained state")
	bindings.manual_rotation = {}
	check(not motion.configure(bindings, bindings.base_content_id), "Missing rotation definition replaced by a default")
	check(motion.advance(pose, Vector2.ZERO, 1, 1) == pose, "Failed rotation setup retained usable cruise state")
	for architecture in ["armv7", "x86_64"]:
		var data := {"angle_unit_scale": 0.1, "radians_per_turn": 6.0, "time_scale": 0.02, "rotation_order": "local_x_y", "provenance": []}
		var sizes := [90, 4, 4, 4, 28] if architecture == "armv7" else [24, 61, 4, 4, 4, 45]
		for i in sizes.size(): data.provenance.append({"offset": 100 * i, "bytes": sizes[i]})
		check(Definitions.validate_manual_rotation(data, 1024, architecture).is_empty(), "Valid rotation provenance rejected")
		for bad in [NAN, INF, -1.0, 0.0, "0.1", true]:
			data.time_scale = bad
			check(not Definitions.validate_manual_rotation(data, 1024, architecture).is_empty(), "Invalid rotation scalar accepted")
	var args := OS.get_cmdline_user_args()
	check(args.size() % 2 == 0, "Pass content/bindings pairs")
	for i in range(0, args.size() - 1, 2):
		var library := Library.new()
		check(library.open(args[i]), library.error)
		check(bindings.open(args[i + 1], library.manifest), bindings.error)
		check(motion.configure(bindings, library.manifest.content_id), motion.error)
		if motion.binding_id.is_empty(): continue
		var result := motion.advance(pose, Vector2(0, quarter), 1, 1)
		check(result.origin.distance_to(pose.origin + Vector3(2000, 0, 0)) < 0.01, "Real edition angular-unit conversion differs from source evidence")
		print(library.manifest.profile.edition, ": quarter-turn native motion = ", result.origin - pose.origin)
	motion.clear()
	check(motion.base_content_id.is_empty() and motion.binding_id.is_empty(), "Cleared motion retained content identity")
	print("Flight motion checks: %d failures" % failures)
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
