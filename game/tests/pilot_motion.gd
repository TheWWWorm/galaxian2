extends SceneTree
const Response = preload("res://src/simulation/pilot_response.gd")
const Motion = preload("res://src/simulation/pilot_motion.gd")
const Definitions = preload("res://src/content/motion_definitions.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Library = preload("res://src/content/library.gd")
var failures := 0

func _initialize() -> void:
	var bindings := Bindings.new()
	bindings.base_content_id = "a".repeat(64)
	bindings.binding_id = "b".repeat(64)
	bindings.cruise = {"speed_units_per_millisecond": 2.0, "forward_axis": [0, 0, 1]}
	bindings.manual_rotation = {"angle_unit_scale": 1.0 / 65536.0, "radians_per_turn": TAU,
		"time_scale": 0.033, "rotation_order": "local_x_y"}
	bindings.pilot_response = parameters()
	var response := Response.new()
	check(response.next_units(Vector2.ONE, Vector2.ONE, 1) == Vector2.ONE and not response.error.is_empty(), "Unconfigured response accepted commands")
	check(response.configure(bindings, bindings.base_content_id, 12.6, 0.5), response.error)
	check_response(response)
	# Configuration snapshots declarations; changing a source object is not a live tuning API.
	bindings.pilot_response.target_gain = 63
	check(response.next_units(Vector2.ZERO, Vector2.ONE, 10) == Vector2(150, 150), "Response retained mutable declarations")
	bindings.pilot_response = parameters()
	for invalid in [0.0, -1.0, NAN, INF, 1e20]:
		check(not response.set_response_factor(invalid), "Invalid response factor accepted")
		check(response.next_units(Vector2.ZERO, Vector2.ONE, 10) == Vector2(150, 150), "Rejected factor changed configuration")
	for invalid in [-1.0, 3.3, NAN, INF]:
		check(not response.configure(bindings, bindings.base_content_id, 12.6, invalid) and response.binding_id.is_empty(), "Invalid preference retained response configuration")
	check(not response.configure(bindings, "c".repeat(64), 12.6, 0.5), "Cross-edition response configuration accepted")
	check_motion(bindings)
	for architecture in ["armv7", "x86_64"]:
		var data := parameters()
		data.provenance = []
		var sizes := [54, 58, 28, 28, 28, 28] if architecture == "armv7" else [54, 33, 33, 32, 32, 32, 32]
		for i in (7 if architecture == "armv7" else 9): sizes.append(4)
		for i in sizes.size(): data.provenance.append({"offset": i * 60, "bytes": sizes[i]})
		check(Definitions.validate_pilot_response(data, 1024, architecture).is_empty(), "Valid response source extents rejected")
		for bad in [0, -1, NAN, INF, "126", true]:
			data.neutral_divisor = bad
			check(not Definitions.validate_pilot_response(data, 1024, architecture).is_empty(), "Invalid neutral parameter accepted")
	var args := OS.get_cmdline_user_args()
	check(args.size() % 2 == 0, "Pass content/bindings pairs")
	for i in range(0, args.size() - 1, 2):
		var library := Library.new()
		check(library.open(args[i]), library.error)
		check(bindings.open(args[i + 1], library.manifest), bindings.error)
		# Explicit test parameters exercise imported response constants; they do
		# not assign an original ship's handling, equipment or saved preference.
		check(response.configure(bindings, library.manifest.content_id, 12.6, 0.5), response.error)
		if response.binding_id.is_empty(): continue
		check_response(response)
		check_motion(bindings)
		print(library.manifest.profile.edition, ": source pilot-response checks passed")
	print("Pilot motion checks: %d failures" % failures)
	quit(1 if failures else 0)

func parameters() -> Dictionary:
	return {"target_gain": 750.0, "target_divisor": 63, "ramp_bias": 3.3,
		"ramp_scale": 20.0, "neutral_divisor": 126.0, "mode": "elapsed", "command_curve": "signed_square"}

func check_response(response: RefCounted) -> void:
	near(response.next_units(Vector2.ZERO, Vector2(1, -1), 0.1), Vector2(22.5, -22.5), "Initial signed response")
	near(response.next_units(Vector2(22.5, -22.5), Vector2(1, -1), 0.1), Vector2(35, -35), "Held input must include neutral return")
	near(response.next_units(Vector2(150, -150), Vector2.ZERO, 0.1), Vector2(140, -140), "Release rate differs from driven rate")
	near(response.next_units(Vector2.ZERO, Vector2(0.5, -0.5), 10), Vector2(37, -37), "Squared input or signed target quantization changed")
	near(response.next_units(Vector2(150, -150), Vector2(0.5, -0.5), 0.1), Vector2(140, -140), "Smaller held command snapped to target")
	near(response.next_units(Vector2(50, -50), Vector2(-1, 1), 0.1), Vector2(17.5, -17.5), "Direction reversal response")
	near(response.next_units(Vector2(-5, 5), Vector2(0.001, -0.001), 0.001), Vector2(-4.675, 4.675), "Zero-quantized target lost directional braking")
	near(response.next_units(Vector2(12, -24), Vector2.ONE, 0), Vector2(12, -24), "Paused response changed state")
	near(response.next_units(Vector2(12, -24), Vector2.ZERO, 10), Vector2.ZERO, "Neutral return overshot zero")
	for invalid in [[Vector2(1.1, 0), 1.0], [Vector2(0, -1.1), 1.0], [Vector2(NAN, 0), 1.0], [Vector2.ZERO, -1.0], [Vector2.ZERO, INF], [Vector2.ZERO, 1e308]]:
		check(response.next_units(Vector2.ONE, invalid[0], invalid[1]) == Vector2.ONE and not response.error.is_empty(), "Invalid command or time consumed response state")

func check_motion(bindings: RefCounted) -> void:
	var motion := Motion.new()
	var pose := Transform3D.IDENTITY
	check(motion.configure(bindings, bindings.base_content_id, 12.6, 0.5), motion.error)
	var first := motion.advance(pose, Vector2(0, 1), 1, 0.1)
	check(first.basis == Basis.IDENTITY and first.origin == Vector3(0, 0, 200), "New command affected preceding movement")
	near(motion.angular_units, Vector2(0, 22.5), "First response state")
	var second := motion.advance(first, Vector2(0, 1), 1, 0.1)
	check(second.basis.z.x > 0 and second.origin.x > 0 and motion.error.is_empty(), "Prepared response failed to turn next movement")
	var before := motion.angular_units
	check(motion.advance(second, Vector2.ONE, -1, 0.1) == second and not motion.error.is_empty() and motion.angular_units == before, "Failed flight consumed a command")
	var invalid := Transform3D(Basis.from_scale(Vector3(2, 1, 1)), Vector3.ZERO)
	check(motion.advance(invalid, Vector2.ONE, 1, 0.1) == invalid and not motion.error.is_empty() and motion.angular_units == before, "Invalid pose consumed a command")
	check(motion.advance(second, Vector2.ONE, 1, 0) == second and motion.angular_units == before, "Paused step consumed a command")
	check(motion.set_response_factor(6.3) and motion.angular_units == before, "Vehicle change reset established angular state")
	for i in 100: second = motion.advance(second, Vector2.ZERO, 1, 0.1)
	check(motion.angular_units == Vector2.ZERO and motion.error.is_empty(), "Released controls did not settle")
	check_lateral(bindings)
	check(not motion.configure(bindings, "c".repeat(64), 12.6, 0.5) and motion.angular_units == Vector2.ZERO and motion.binding_id.is_empty(), "Failed configuration retained pilot state")
	check(motion.advance(second, Vector2.ONE, 1, 1) == second and not motion.error.is_empty(), "Failed configuration retained usable flight")
	motion.clear()

func check_lateral(bindings: RefCounted) -> void:
	var motion := Motion.new()
	check(motion.configure(bindings, bindings.base_content_id, 12.6, 0.5), motion.error)
	var pose := Transform3D.IDENTITY
	var left := motion.advance(pose, Vector2.ZERO, 0, 0.1, -1.0)
	check(left.origin.distance_to(Vector3(7.56, 0, 0)) < 0.0001, "Source response factor and initial lateral gain changed")
	check(absf(motion.lateral_units_per_millisecond - 0.05292) < 0.00001, "Source lateral retention changed")
	var held := motion.advance(left, Vector2.ZERO, 0, 0.1, -1.0)
	check(held.origin.distance_to(Vector3(18.9, 0, 0)) < 0.0001, "Held lateral gain failed to ramp by source factor")
	var fork := motion.fork_for_frame()
	var released := motion.advance(held, Vector2.ZERO, 0, 0.1)
	check(released.origin.distance_to(Vector3(26.838, 0, 0)) < 0.0001, "Released lateral rate failed to coast")
	check(fork.advance(held, Vector2.ZERO, 0, 0.1).origin.distance_to(released.origin) < 0.0001, "Fork lost pending lateral motion")
	var retained := motion.lateral_units_per_millisecond
	check(motion.advance(released, Vector2.ZERO, 0, 0, 1.0) == released and motion.lateral_units_per_millisecond == retained, "Paused lateral input moved or consumed state")
	for invalid in [0.5, 1.01, NAN, INF]:
		check(motion.advance(released, Vector2.ZERO, 0, 0.1, invalid) == released and not motion.error.is_empty() and motion.lateral_units_per_millisecond == retained, "Invalid lateral command consumed state")
	var right := Motion.new()
	check(right.configure(bindings, bindings.base_content_id, 12.6, 0.5), right.error)
	check(right.advance(pose, Vector2.ZERO, 0, 0.1, 1.0).origin.distance_to(Vector3(-7.56, 0, 0)) < 0.0001, "Right strafe sign changed")
	check(motion.set_response_factor(6.3), motion.error)
	check(motion.advance(released, Vector2.ZERO, 0, 0.1, -1.0).origin.x > released.origin.x, "Response change broke lateral control")

func near(actual: Vector2, expected: Vector2, message: String) -> void:
	check(actual.distance_to(expected) < 0.0001, message + ": " + str(actual))

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
