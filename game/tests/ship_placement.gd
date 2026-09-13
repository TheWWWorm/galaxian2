extends SceneTree
const Library = preload("res://src/content/library.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Visuals = preload("res://src/content/visual_library.gd")
const Geometry = preload("res://src/presentation/hangar_geometry.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var args := OS.get_cmdline_user_args()
	check(args.size() % 3 == 0, "Pass base/bindings/visuals triples")
	var shared_positions: Array = []
	for i in range(0, args.size() - 2, 3):
		var library := Library.new()
		var catalogues := Catalogues.new()
		var bindings := Bindings.new()
		var visuals := Visuals.new()
		check(library.open(args[i]), library.error)
		check(catalogues.open(library), catalogues.error)
		check(bindings.open(args[i + 1], library.manifest), bindings.error)
		check(visuals.open(args[i + 2], library.manifest), visuals.error)
		if bindings.ship_placement.is_empty():
			check(false, "Real placement definitions missing")
			continue
		var count: int = catalogues.tables.ships.size()
		check(bindings.ship_placement.y_positions.size() == count, "Placement catalogue mismatch")
		if shared_positions.is_empty(): shared_positions = bindings.ship_placement.y_positions.slice(0, 61)
		else: check(shared_positions == bindings.ship_placement.y_positions.slice(0, 61), "Shared edition positions differ")
		var supported := 0
		for ship_id in count:
			var ship := bindings.resolve_hangar_ship(ship_id)
			if ship.is_empty(): continue
			supported += 1
			check(ship.position == Vector3(0, bindings.ship_placement.y_positions[ship_id], 0), "Placement axis/index mismatch")
		var unresolved := 4 if bindings.ship_lights.is_empty() else 6
		check(supported == count - unresolved, "Unexpected positioned hull/layer coverage")
		if not bindings.ship_lights.is_empty():
			for id in [42, 43]:
				check(bindings.resolve_hangar_ship(id).is_empty() and "light layer" in bindings.error, "Missing declared light was silently omitted")
		var examples := [0, 37, 55]
		if count == 64: examples.append_array([61, 63])
		for ship_id in examples:
			var selected := bindings.resolve_hangar(100 if ship_id == 37 else 0, catalogues)
			selected.ship = bindings.resolve_hangar_ship(ship_id)
			var scene := Geometry.new()
			root.add_child(scene)
			check(scene.build(selected, library, visuals, bindings), scene.error)
			if is_instance_valid(scene.ship_model):
				check(scene.ship_model.get_parent() == scene, "Hull incorrectly parented to a rotated hangar layer")
				check(scene.ship_model.position == selected.ship.position and scene.ship_model.basis == Basis.IDENTITY, "Source height was transformed by the hangar rotation")
				check(scene.ship_model.get_meta("source_ship_id") == ship_id, "Wrong catalogue hull instantiated")
				check(scene.ship_light_models.size() == selected.ship.get("lights", []).size(), "Declared ship lights omitted")
				for light in scene.ship_light_models:
					check(light.get_parent() == scene.ship_model and light.transform == Transform3D.IDENTITY, "Light layer lost its hull-local transform")
				if ship_id == 55 and scene.ship_light_models.size() == 2:
					check(scene.ship_light_models[0] != scene.ship_light_models[1], "Two light slots share one node")
					check(scene.ship_light_models[0].instances[0].mesh == scene.ship_light_models[1].instances[0].mesh, "Repeated light mesh was not shared")
				var expected_bounds: AABB = scene.ship_model.transform * scene.ship_model.source_bounds
				check(scene.source_bounds.grow(0.1).encloses(expected_bounds), "Placed hull omitted from combined bounds")
				print(library.manifest.profile.edition, " hull ", ship_id, " at ", scene.ship_model.position, " in hangar row ", selected.row, " with ", scene.ship_light_models.size(), " light layers")
			else: check(false, "Ship geometry not instantiated")
			scene.clear()
			check(scene.ship_model == null and scene.models.is_empty(), "Cleared scene retained placed ship")
			scene.free()
		print(library.manifest.profile.edition, ": ", supported, "/", count, " table hulls have usable placement; special assemblies remain separate")
	print("Ship placement checks: %d failures" % failures)
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
