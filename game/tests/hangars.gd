extends SceneTree
const Library = preload("res://src/content/library.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Visuals = preload("res://src/content/visual_library.gd")
const Definitions = preload("res://src/content/hangar_definitions.gd")
const Geometry = preload("res://src/presentation/hangar_geometry.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var args := OS.get_cmdline_user_args()
	check(args.size() % 3 == 0, "Pass base/bindings/visuals argument triples")
	for i in range(0, args.size() - 2, 3):
		var library := Library.new()
		var catalogues := Catalogues.new()
		var bindings := Bindings.new()
		var visuals := Visuals.new()
		check(library.open(args[i]), library.error)
		check(catalogues.open(library), catalogues.error)
		check(bindings.open(args[i + 1], library.manifest), bindings.error)
		check(visuals.open(args[i + 2], library.manifest), visuals.error)
		check(not bindings.hangars.is_empty(), "Real hangar definitions missing")
		if bindings.hangars.is_empty(): continue
		for corruption in ["rotation", "id", "count", "override", "extent", "empty_parent"]:
			var value: Dictionary = bindings.hangars.duplicate(true)
			match corruption:
				"rotation": value.rotation_y = NAN
				"id": value.rows[0].resource_ids[0] = 1.5
				"count": value.rows.pop_back()
				"override": value.station_overrides[1] = value.station_overrides[0]
				"extent": value.provenance[0].offset = 64000000
				"empty_parent": value.rows[0].resource_ids = [-1, -1, -1, -1]
			check(not Definitions.validate(value, 16000000).is_empty(), "Malformed hangar accepted: " + corruption)
		var rows := {}
		var unsupported := []
		for station in catalogues.tables.stations:
			var selected := bindings.resolve_hangar(station.id, catalogues)
			if selected.is_empty():
				unsupported.append({"station": station.id, "error": bindings.error})
				continue
			var expected: int = catalogues.tables.systems[station.system_id].fields[2]
			if station.id == 100: expected = 7
			if station.id == 101: expected = 8
			check(selected.row == expected, "Wrong source hangar row for station " + str(station.id))
			rows[selected.row] = selected
		check(rows.size() == 6, "Expected six distinct populated source hangar rows")
		for row in rows:
			var scene := Geometry.new()
			root.add_child(scene)
			check(scene.build(rows[row], library, visuals, bindings), scene.error)
			if scene.models.is_empty():
				scene.free()
				continue
			var expected_models := 0
			for layer in rows[row].layers: expected_models += 1 + layer.children.size()
			check(scene.models.size() == expected_models, "Source layer/child instances omitted")
			check(scene.get_child_count() == rows[row].layers.size(), "Extra geometry lost its layer hierarchy")
			for layer in scene.get_children():
				check(absf(layer.rotation.y - rows[row].rotation_y) < 0.000001, "Source root rotation lost")
			if scene.get_child_count() > 1 and scene.get_child(0).get_child_count() > 1:
				var templates := {}
				for model in scene.models:
					var id: int = model.get_meta("source_resource_id")
					if templates.has(id):
						check(model.instances[0].mesh == templates[id].instances[0].mesh, "Repeated geometry did not share meshes")
						check(model.materials[0] != templates[id].materials[0], "Repeated geometry shared mutable material state")
					else: templates[id] = model
			scene.set_source_time(1500.0)
			print(library.manifest.profile.edition, " row ", row, ": ", scene.models.size(), " models / ", scene.instances.size(), " surfaces / bounds ", scene.source_bounds)
			# A failed rebuild must remove the previous geometry atomically.
			check(not scene.build({}, library, visuals, bindings) and scene.get_child_count() == 0, "Failed build retained a previous hangar")
			scene.free()
		print(library.manifest.profile.edition, " stations with unsupported hangar geometry: ", JSON.stringify(unsupported))
		check(bindings.resolve_hangar(-1, catalogues).is_empty() and bindings.resolve_hangar(135, catalogues).is_empty(), "Invalid station selected")
		catalogues.content_id = "different"
		check(bindings.resolve_hangar(0, catalogues).is_empty(), "Cross-edition catalogues accepted")
		check(not bindings.open("user://does-not-exist", library.manifest) and bindings.hangars.is_empty(), "Failed binding open retained a hangar")
	print("Hangar checks: %d failures" % failures)
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
