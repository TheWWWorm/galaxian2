extends SceneTree
const Vehicle = preload("res://src/simulation/vehicle_response.gd")
const Motion = preload("res://src/simulation/pilot_motion.gd")
const Definitions = preload("res://src/content/vehicle_definitions.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Library = preload("res://src/content/library.gd")
var failures := 0

func _initialize() -> void:
	var bindings := Bindings.new()
	bindings.base_content_id = "a".repeat(64)
	bindings.binding_id = "b".repeat(64)
	bindings.vehicle_response = parameters()
	bindings.cruise = {"speed_units_per_millisecond": 2.0, "forward_axis": [0, 0, 1]}
	bindings.manual_rotation = {"angle_unit_scale": 1.0 / 65536.0, "radians_per_turn": TAU, "time_scale": 0.033, "rotation_order": "local_x_y"}
	bindings.pilot_response = {"target_gain": 750.0, "target_divisor": 63, "ramp_bias": 3.3, "ramp_scale": 20.0, "neutral_divisor": 126.0, "mode": "elapsed", "command_curve": "signed_square"}
	var catalogues := Catalogues.new()
	catalogues.content_id = bindings.base_content_id
	catalogues.tables = {"ships": [{"stats": {"handling_factor": 1.0}}], "items": [item(16, 25), item(16, 40), item(7, 999), {"arrays": [[], [], [0, 3, 1, 0, 2, 16]], "properties": {}}]}
	var vehicle := Vehicle.new()
	check(vehicle.resolve(0, [], []).is_empty() and not vehicle.error.is_empty(), "Unconfigured vehicle resolved")
	check(vehicle.configure(bindings, catalogues, catalogues.content_id), vehicle.error)
	near(vehicle.resolve(0, [], []).get("response_factor", 0), 18, "Base conversion")
	var tuned := vehicle.resolve(0, [3, 99, 3], [0, 2, 1])
	near(tuned.get("effective_handling", 0), 1.4, "Only matching upgrade tags contribute")
	near(tuned.get("response_factor", 0), 39.2, "Percentage scales upgraded handling")
	check(tuned.get("handling_item_id") == 1 and tuned.get("equipment_percent") == 40, "Last matching equipment selection")
	near(vehicle.resolve(0, [], [1, 0]).get("response_factor", 0), 22.5, "Reversing equipment order must select the last bonus")
	for invalid in [[-1, [], []], [1, [], []], [0, [3.0], []], [0, [-1], []], [0, [], [4]], [0, [], [3]], [0, [], [0.0]]]:
		check(vehicle.resolve(invalid[0], invalid[1], invalid[2]).is_empty() and not vehicle.error.is_empty(), "Invalid vehicle state accepted")
	catalogues.tables.ships[0].stats.handling_factor = 3.0
	bindings.vehicle_response.response_scale = 1.0
	near(vehicle.resolve(0, [], []).get("response_factor", 0), 18, "Configured definitions retained mutable references")
	catalogues.tables.ships[0].stats.handling_factor = 1.0
	bindings.vehicle_response = parameters()
	check(not vehicle.configure(bindings, catalogues, "c".repeat(64)) and vehicle.binding_id.is_empty(), "Cross-content configuration retained vehicle state")
	var motion := Motion.new()
	check(motion.configure_vehicle(bindings, catalogues, catalogues.content_id, 0, [3, 3], [1], 0.5), motion.error)
	var pose := motion.advance(Transform3D.IDENTITY, Vector2(0, 1), 1, 0.1)
	near(motion.angular_units.y, 70.0, "Ship response did not reach pilot controls")
	var angular := motion.angular_units
	check(motion.set_vehicle(bindings, catalogues, 0, [], []) and motion.angular_units == angular, "Equipment change reset a turn")
	check(not motion.set_vehicle(bindings, catalogues, 0, [], [3]) and motion.angular_units == angular, "Invalid equipment change consumed angular state")
	motion.advance(pose, Vector2.ZERO, 1, 0.1)
	near(motion.angular_units.y, 70.0 - 1800.0 / 126.0, "Rejected equipment changed the established factor")
	check(not motion.configure_vehicle(bindings, catalogues, catalogues.content_id, 1, [], [], 0.5) and motion.binding_id.is_empty() and motion.angular_units == Vector2.ZERO, "Failed vehicle setup retained flight state")
	for architecture in ["armv7", "x86_64"]:
		var data := parameters()
		if architecture == "armv7":
			data.base_add = 0.0; data.base_divisor = 1.0; data.base_scale = 1.0; data.base_offset = 0.0
		data.provenance = {}
		var sizes := Definitions.provenance_sizes(architecture)
		var offset := 0
		for key in sizes:
			data.provenance[key] = {"offset": offset, "bytes": sizes[key]}
			offset += sizes[key]
		check(Definitions.validate(data, 2048, architecture).is_empty(), "Valid vehicle provenance rejected")
		for key in ["base_add", "base_divisor", "upgrade_bonus", "percent_divisor", "equipment_type"]:
			var bad := data.duplicate(true)
			bad[key] = NAN
			check(not Definitions.validate(bad, 2048, architecture).is_empty(), "Nonfinite vehicle parameter accepted")
	var args := OS.get_cmdline_user_args()
	check(args.size() % 2 == 0, "Pass content/bindings pairs")
	for i in range(0, args.size() - 1, 2):
		var library := Library.new()
		check(library.open(args[i]), library.error)
		check(bindings.open(args[i + 1], library.manifest), bindings.error)
		check(catalogues.open(library), catalogues.error)
		check(vehicle.configure(bindings, catalogues, catalogues.content_id), vehicle.error)
		if vehicle.binding_id.is_empty(): continue
		var devices := []
		for row in catalogues.tables.items:
			if row.arrays[2].size() > 5 and row.arrays[2][5] == 16: devices.append(row.id)
		check(not devices.is_empty(), "Source has no maneuverability devices")
		for ship in catalogues.tables.ships:
			var base := vehicle.resolve(ship.id, [], [])
			check(not base.is_empty(), vehicle.error)
			var h: float = ship.stats.handling_factor
			var expected := h if library.manifest.profile.edition == "ios-hd" else (h - 0.45) / 1.1 * 0.85 + 0.7
			near(base.get("response_factor", 0), expected * 20, "Real ship base handling conversion")
			for device in devices:
				var resolved := vehicle.resolve(ship.id, [3], [device])
				check(not resolved.is_empty(), vehicle.error)
				var percent: int = catalogues.tables.items[device].properties[28]
				near(resolved.get("response_factor", 0), (expected + 0.2) * (1 + percent / 100.0) * 20, "Real equipment/upgrade response")
		check(motion.configure_vehicle(bindings, catalogues, catalogues.content_id, 0, [], [], 0.5), motion.error)
		motion.advance(Transform3D.IDENTITY, Vector2(0, 1), 1, 0.1)
		check(motion.angular_units.y > 0 and motion.error.is_empty(), "Real ship did not drive pilot response")
		print(library.manifest.profile.edition, ": checked ", catalogues.tables.ships.size(), " ships and ", devices.size(), " handling devices")
	print("Vehicle response checks: %d failures" % failures)
	quit(1 if failures else 0)

func parameters() -> Dictionary:
	return {"base_add": -0.25, "base_divisor": 1.5, "base_scale": 0.8, "base_offset": 0.5,
		"upgrade_tag": 3, "upgrade_bonus": 0.25, "equipment_type": 16, "item_type_value_index": 5,
		"equipment_percent_property": 28, "percent_divisor": 100.0, "response_scale": 20.0, "equipment_rule": "last_matching"}

func item(type_id: int, percent: int) -> Dictionary:
	return {"arrays": [PackedInt32Array(), PackedInt32Array(), PackedInt32Array([0, 0, 1, 0, 2, type_id, 28, percent])], "properties": {28: percent}}

func near(actual: float, expected: float, message: String) -> void:
	check(absf(actual - expected) < 0.001, message + ": " + str(actual))

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
