extends SceneTree
const Definitions = preload("res://src/content/opening_actor_definitions.gd")
const Fixture = preload("res://tests/opening_actor_fixture.gd")
const Actors = preload("res://src/simulation/opening_actor_state.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Library = preload("res://src/content/library.gd")
var failures := 0

func _initialize() -> void:
	for mac in [true, false]:
		var scope := Fixture.definition(mac)
		var arch := "x86_64" if mac else "armv7"
		check(Definitions.validate(JSON.parse_string(JSON.stringify(scope)), 4096, arch).is_empty(), "Serialized actor declarations rejected")
		for bad in ["actors", "id", "hull", "kind", "hp", "player_hp", "position", "nonfinite", "provenance", "overlap"]:
			var data := scope.duplicate(true)
			match bad:
				"actors": data.actors.clear()
				"id": data.actors[1].actor_id = 0
				"hull": data.actors[0].hull_catalogue_id = -1
				"kind": data.actors[0].actor_kind = 256
				"hp": data.actors[0].current_hull_override = 0
				"player_hp": data.player_current_hull_override = -1
				"position": data.actors[0].position = [1, 2]
				"nonfinite": data.actors[0].position[0] = NAN
				"provenance": data.provenance.hull_setter.offset = 4095
				"overlap": data.provenance.dispatch.offset = 100
			check(not Definitions.validate(data, 4096, arch).is_empty(), "Malformed actor data accepted: " + bad)
	var bindings := Bindings.new()
	var catalogues := Catalogues.new()
	var state := Actors.new()
	bindings.base_content_id = "a".repeat(64)
	bindings.binding_id = "b".repeat(64)
	catalogues.content_id = bindings.base_content_id
	catalogues.tables = {"ships": [{}, {}]}
	bindings.ship_model_resources = [100, 101]
	for id in [100, 101]:
		var path := "resources/data/meshes/example%d.aem" % id
		bindings.records[id] = [{"resource": path, "kind": "mesh", "registration_type": 4}]
		bindings.base_files[path] = {"kind": "mesh"}
	bindings.opening_actors = Fixture.definition()
	check(state.configure(bindings, catalogues, catalogues.content_id), state.error)
	var snapshot := state.snapshot()
	check(snapshot.get("player_current_hull_override") == 9999, "Prologue override lost")
	check(snapshot.actors[0].position == Vector3(10, -20, 30) and snapshot.actors[1].current_hull == 321, "Actor position/hull changed")
	check(snapshot.actors[1].hull_resource.ends_with("example101.aem"), "Wrong catalogue hull selected")
	snapshot.actors[0].current_hull = 0
	check(state.snapshot().actors[0].current_hull == 123, "Snapshot mutated initial actors")
	for bad in ["identity", "catalogue", "model", "unsupported"]:
		bindings.opening_actors = Fixture.definition()
		bindings.base_content_id = catalogues.content_id
		match bad:
			"identity": bindings.base_content_id = "c".repeat(64)
			"catalogue": bindings.opening_actors.actors[0].hull_catalogue_id = 2
			"model": bindings.ship_model_resources = []
			"unsupported": bindings.opening_actors = {}
		check(not state.configure(bindings, catalogues, catalogues.content_id) and state.snapshot().is_empty() and not state.error.is_empty(), "Failed actor configuration retained state: " + bad)
		bindings.ship_model_resources = [100, 101]
	var args := OS.get_cmdline_user_args()
	check(args.size() % 2 == 0, "Expected content/bindings pairs")
	for i in range(0, args.size() - 1, 2):
		var library := Library.new()
		check(library.open(args[i]), library.error)
		check(bindings.open(args[i + 1], library.manifest), bindings.error)
		check(catalogues.open(library), catalogues.error)
		check(state.configure(bindings, catalogues, catalogues.content_id), state.error)
		snapshot = state.snapshot()
		if snapshot.is_empty(): continue
		check(snapshot.actors.size() == 3 and snapshot.player_current_hull_override == 9999999, "Actual prologue setup changed")
		for index in 3:
			var row: Dictionary = snapshot.actors[index]
			check(row.hull_catalogue_id == (23 if index == 1 else 2) and row.actor_kind == 8 and row.current_hull == 150 and row.position == Vector3(50000, 50000, 50000), "Actual opening actor changed")
			check(not row.has("max_hull") and not row.has("visible"), "Unverified actor state inferred")
		print(library.manifest.profile.edition, ": ", JSON.stringify(snapshot))
	print("Opening actor checks: %d failures" % failures)
	quit(1 if failures else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
