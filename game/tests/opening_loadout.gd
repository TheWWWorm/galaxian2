extends SceneTree
const Opening = preload("res://src/simulation/opening_loadout.gd")
const Definitions = preload("res://src/content/opening_definitions.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Library = preload("res://src/content/library.gd")
const Driver = preload("res://src/simulation/flight_driver.gd")
var failures := 0

func _initialize() -> void:
	var bindings := Bindings.new()
	bindings.binding_id = "b".repeat(64)
	bindings.base_content_id = "a".repeat(64)
	bindings.vehicle_response = {"item_type_value_index": 5}
	bindings.opening_loadout = fixture_seed()
	var catalogues := Catalogues.new()
	catalogues.content_id = bindings.base_content_id
	catalogues.tables = {"ships": [{"stats": {"primary_slots": 2, "secondary_slots": 1, "turret_slots": 1, "equipment_slots": 4}}],
		"stations": [{"system_id": 0}], "systems": [{}], "items": []}
	for category in [0, 1, 3, 3, 3, 3]:
		catalogues.tables.items.append({"arrays": [[], [], PackedInt32Array([0, 0, 1, category])]})
	var opening := Opening.new()
	check(opening.snapshot().is_empty(), "Unconfigured opening exists")
	check(opening.configure(bindings, catalogues, catalogues.content_id), opening.error)
	var state := opening.snapshot()
	check(state.get("equipment_ids") == [0, 0, 1, 2, 3, 4, 5], "Slot order differs from declaration order")
	check(state.get("slots", []).size() == 8 and state.slots[3] == null, "Empty turret slot lost")
	check(state.slots[2].quantity == 9, "Missile stack count lost")
	state.slots[0].quantity = 42
	check(opening.snapshot().slots[0].quantity == 1, "Snapshot mutates configured state")
	for corruption in ["ship", "station", "item", "slot", "collision", "quantity", "category", "cross_content", "unsupported"]:
		bindings.opening_loadout = fixture_seed()
		catalogues.tables.items[0].arrays[2][3] = 0
		match corruption:
			"ship": bindings.opening_loadout.ship_id = 1
			"station": bindings.opening_loadout.station_id = 1
			"item": bindings.opening_loadout.equipment[0].item_id = 6
			"slot": bindings.opening_loadout.equipment[0].slot = 2
			"collision": bindings.opening_loadout.equipment[1].slot = 0
			"quantity": bindings.opening_loadout.equipment[0].quantity = 0
			"category": catalogues.tables.items[0].arrays[2][3] = 4
			"cross_content": bindings.base_content_id = "c".repeat(64)
			"unsupported": bindings.opening_loadout = {}
		check(not opening.configure(bindings, catalogues, catalogues.content_id) and not opening.error.is_empty() and opening.snapshot().is_empty(), "Invalid opening retained state: " + corruption)
		bindings.base_content_id = catalogues.content_id
	var args := OS.get_cmdline_user_args()
	check(args.size() % 2 == 0, "Pass content/bindings pairs")
	for i in range(0, args.size() - 1, 2):
		var library := Library.new()
		check(library.open(args[i]), library.error)
		check(bindings.open(args[i + 1], library.manifest), bindings.error)
		check(catalogues.open(library), catalogues.error)
		check(opening.configure(bindings, catalogues, catalogues.content_id), opening.error)
		state = opening.snapshot()
		if state.is_empty(): continue
		check(state.ship_id == 10 and state.station_id == 78, "Source initial ship/station changed")
		check(state.equipment_ids == [2, 2, 36, 54, 59, 82, 73], "Source ordered equipment changed")
		check(state.slots[2].quantity == 6, "Source missile stack changed")
		var driver := Driver.new()
		# Explicit test sensitivity/pose/throttle: opening camera, control settings
		# and mission start are not inferred from a loadout declaration.
		check(driver.configure(bindings, catalogues, catalogues.content_id, state.ship_id, [], state.equipment_ids, 0.5, Transform3D.IDENTITY), driver.error)
		var event := InputEventKey.new()
		event.physical_keycode = KEY_RIGHT
		event.pressed = true
		driver.accept(event)
		driver.step(0, 1.0)
		var result := driver.step(100000, 1.0)
		check(result.seconds > 0, "Opening loadout did not configure flight driver")
		print(library.manifest.profile.edition, ": ", JSON.stringify(state), " station=", catalogues.tables.stations[state.station_id].name)
	print("Opening loadout checks: %d failures" % failures)
	quit(1 if failures else 0)

func fixture_seed() -> Dictionary:
	return {"ship_id": 0, "station_id": 0, "item_category_value_index": 3, "equipment": [
		{"item_id": 0, "slot": 0, "quantity": 1}, {"item_id": 0, "slot": 1, "quantity": 1},
		{"item_id": 2, "slot": 0, "quantity": 1}, {"item_id": 3, "slot": 1, "quantity": 1},
		{"item_id": 4, "slot": 2, "quantity": 1}, {"item_id": 5, "slot": 3, "quantity": 1},
		{"item_id": 1, "slot": 0, "quantity": 9}]}

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
