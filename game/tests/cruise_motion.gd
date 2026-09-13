extends SceneTree
const Motion = preload("res://src/simulation/cruise_motion.gd")
const Definitions = preload("res://src/content/motion_definitions.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Library = preload("res://src/content/library.gd")
var failures := 0

func _initialize() -> void:
	var motion := Motion.new()
	var pose := Transform3D(Basis.IDENTITY, Vector3(17, -23, 80))
	check(motion.advance(pose, 1.0, 1.0) == pose and not motion.error.is_empty(), "Unconfigured motion advanced")
	var bindings := Bindings.new()
	bindings.base_content_id = "a".repeat(64)
	bindings.binding_id = "b".repeat(64)
	bindings.cruise = {"speed_units_per_millisecond": 3.5, "forward_axis": [0, 0, 1]}
	check(motion.configure(bindings, bindings.base_content_id), motion.error)
	check(motion.advance(pose, 1.0, 2.0).origin == Vector3(17, -23, 7080), "Source units or positive forward direction lost")
	check(motion.advance(pose, 0.25, 2.0).origin == Vector3(17, -23, 1830), "Throttle did not scale source cruise")
	var divided := pose
	for i in 120: divided = motion.advance(divided, 0.4, 1.0 / 60.0)
	check(divided.origin.distance_to(motion.advance(pose, 0.4, 2.0).origin) < 0.01, "Travel depends on time subdivision")
	for angle in [-PI * 0.5, PI * 0.5, PI]:
		var basis := Basis(Vector3.UP, angle)
		var rotated := Transform3D(Basis(basis.x * 0.001, basis.y * 3.0, basis.z * 12.0), pose.origin)
		var next := motion.advance(rotated, 1.0, 1.0)
		check(next.origin.distance_to(pose.origin + basis.z * 3500.0) < 0.01, "Heading or render scale altered cruise distance")
		check(next.basis == rotated.basis, "Cruise unexpectedly changed heading")
	check(motion.advance(pose, 1.0, 0.0) == pose and motion.error.is_empty(), "Paused elapsed time moved the ship")
	check(motion.advance(pose, 0.0, 2.0) == pose and motion.error.is_empty(), "Zero throttle moved the ship")
	for values in [[-1.0, 1.0], [1.01, 1.0], [NAN, 1.0], [1.0, -0.01], [1.0, INF]]:
		check(motion.advance(pose, values[0], values[1]) == pose and not motion.error.is_empty(), "Invalid cruise input accepted")
	var singular := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
	check(motion.advance(singular, 1.0, 1.0) == singular and not motion.error.is_empty(), "Singular flight pose accepted")
	check(not motion.configure(bindings, "c".repeat(64)) and motion.binding_id.is_empty(), "Cross-content motion retained")
	check(motion.advance(pose, 1.0, 1.0) == pose, "Failed configure retained old cruise rate")
	bindings.cruise = {}
	check(not motion.configure(bindings, bindings.base_content_id), "Missing source rate replaced by a default")
	for architecture in ["armv7", "x86_64"]:
		var data := {"speed_units_per_millisecond": 2.0, "forward_axis": [0, 0, 1], "provenance": []}
		var sizes := [20, 30, 36, 32, 38] if architecture == "armv7" else [27, 23, 40, 42, 27]
		for i in 5: data.provenance.append({"offset": 100 * i, "bytes": sizes[i]})
		check(Definitions.validate_cruise(data, 1024, architecture).is_empty(), "Valid source provenance rejected")
		for invalid in [NAN, INF, 0, -2, "2", true]:
			data.speed_units_per_millisecond = invalid
			check(not Definitions.validate_cruise(data, 1024, architecture).is_empty(), "Invalid rate accepted")
	var args := OS.get_cmdline_user_args()
	check(args.size() % 2 == 0, "Pass content/bindings pairs")
	for i in range(0, args.size() - 1, 2):
		var library := Library.new()
		check(library.open(args[i]), library.error)
		check(bindings.open(args[i + 1], library.manifest), bindings.error)
		check(motion.configure(bindings, library.manifest.content_id), motion.error)
		if motion.binding_id.is_empty(): continue
		var next := motion.advance(Transform3D.IDENTITY, 1.0, 1.0)
		check(next.origin == Vector3(0, 0, 2000), "Real edition ordinary cruise differs from verified source")
		print(library.manifest.profile.edition, ": 1 simulation second = ", next.origin, " source units")
	motion.clear()
	check(motion.binding_id.is_empty() and motion.base_content_id.is_empty(), "Motion clear retained source context")
	print("Cruise motion checks: %d failures" % failures)
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
