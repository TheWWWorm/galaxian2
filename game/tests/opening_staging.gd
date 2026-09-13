extends SceneTree
const Definitions = preload("res://src/content/opening_staging_definitions.gd")
const Staging = preload("res://src/simulation/opening_staging.gd")
const Fixture = preload("res://tests/opening_staging_fixture.gd")
const ActorFixture = preload("res://tests/opening_actor_fixture.gd")
const Radio = preload("res://src/simulation/radio_sequence.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Library = preload("res://src/content/library.gd")
var failures := 0

func _initialize() -> void:
	for mac in [true, false]:
		var scope: Dictionary = JSON.parse_string(JSON.stringify(Fixture.definition(mac)))
		var arch := "x86_64" if mac else "armv7"
		check(Definitions.validate(scope, 65536, arch).is_empty(), "Serialized staging rejected: " + Definitions.validate(scope, 65536, arch))
		for bad in ["missing", "count", "id", "nan", "camera", "axes", "nonunit", "hidden", "gate", "visibility", "extent", "overlap"]:
			var data := scope.duplicate(true)
			match bad:
				"missing": data.erase("formation")
				"count": data.formation.actors.pop_back()
				"id": data.formation.actors[1].actor_id = 0
				"nan": data.initial.player_position[2] = NAN
				"camera": data.formation.camera_position_parameter = [1, 2]
				"axes": data.initial.player_up = data.initial.player_forward
				"nonunit": data.formation.actors[0].forward = [2, 0, 0]
				"hidden": data.initial.hidden_actor_ids[1] = 1.1
				"gate": data.formation.after_event_finished = -1
				"visibility": data.formation.actors[0].visible = 1
				"extent": data.provenance.initial.offset = 65530
				"overlap": data.provenance.formation.offset = 100
			check(not Definitions.validate(data, 65536, arch).is_empty(), "Bad staging accepted: " + bad)
	var bindings := Bindings.new()
	var catalogues := Catalogues.new()
	var library := Library.new()
	bindings.base_content_id = "a".repeat(64)
	bindings.binding_id = "b".repeat(64)
	catalogues.content_id = bindings.base_content_id
	catalogues.tables = {"ships": [{}, {}]}
	bindings.ship_model_resources = [100, 101]
	for id in [100, 101]:
		var path := "resources/data/meshes/example%d.aem" % id
		bindings.records[id] = [{"resource": path, "kind": "mesh", "registration_type": 4}]
		bindings.base_files[path] = {"kind": "mesh"}
	bindings.opening_actors = ActorFixture.definition()
	bindings.opening_actors.actors.append(bindings.opening_actors.actors[1].duplicate(true))
	bindings.opening_actors.actors[2].actor_id = 2
	bindings.opening_staging = Fixture.definition()
	bindings.opening_dialogue = Fixture.dialogue()
	library.manifest = {"content_id": bindings.base_content_id}
	library.active_language = "gb"
	for i in 23: library.strings.append("Synthetic transmission %d" % i)
	var state := Staging.new()
	check(state.configure(bindings, catalogues, catalogues.content_id), state.error)
	var before := state.snapshot()
	check(before.player_pose.origin == Vector3(0, 0, -90) and before.player_pose.basis == Basis.IDENTITY, "Initial player pose changed")
	for actor in before.actors: check(not actor.visible and not actor.has("pose"), "Initial actor visibility/orientation invented")
	check(before.camera_position_parameter == Vector3(12, -34, -56) and not before.has("camera_pose"), "Camera parameter was treated as a view pose")
	var radio := Radio.new()
	var counts := []; counts.resize(23); counts.fill(1)
	check(radio.configure(bindings, library, counts), radio.error)
	var time := 0
	for event in 3:
		radio.step(time, {}, 0)
		check(state.update(radio.snapshot()) and not state.snapshot().formation_revealed, "Formation revealed on started transmission")
		radio.step(time + 5500, {}, 0)
		check(state.update(radio.snapshot()) and not state.snapshot().formation_revealed, "Formation revealed at inclusive radio boundary")
		time += 5501
		radio.step(time, {}, 0)
		check(state.update(radio.snapshot()), state.error)
		check(state.snapshot().formation_revealed == (event == 2), "Formation ignored its finished-event gate")
	var after := state.snapshot()
	check(after.player_pose.origin == Vector3(321, -234, -456) and after.player_pose.basis == before.player_pose.basis, "Relocation reset player heading")
	for i in 3:
		var actor: Dictionary = after.actors[i]
		check(actor.visible and actor.pose.origin == actor.position and actor.pose.basis.z == Vector3.RIGHT and actor.pose.basis.y == Vector3.UP and is_equal_approx(actor.pose.basis.determinant(), 1), "Wrong actor formation pose")
		check(actor.current_hull == before.actors[i].current_hull and actor.hull_resource == before.actors[i].hull_resource, "Formation changed gameplay or catalogue identity")
	check(state.update(radio.snapshot()) and state.snapshot() == after, "Repeated finished event reapplied formation")
	after.actors[0].visible = false
	check(state.snapshot().actors[0].visible, "Snapshot mutates staging")
	for bad in ["identity", "binding", "flags", "type"]:
		var snapshot := radio.snapshot()
		match bad:
			"identity": snapshot.base_content_id = "c".repeat(64)
			"binding": snapshot.binding_id = "c".repeat(64)
			"flags": snapshot.finished = []
			"type": snapshot.finished[2] = 1
		var saved := state.snapshot()
		check(not state.update(snapshot) and state.snapshot() == saved, "Invalid radio update changed formation")
	for bad in ["missing", "gate", "actors", "identity"]:
		bindings.opening_staging = Fixture.definition()
		var identity := catalogues.content_id
		match bad:
			"missing": bindings.opening_staging = {}
			"gate": bindings.opening_staging.formation.after_event_finished = 23
			"actors": bindings.opening_actors.actors.pop_back()
			"identity": identity = "c".repeat(64)
		check(not state.configure(bindings, catalogues, identity) and state.snapshot().is_empty(), "Failed configuration retained staging")
	var args := OS.get_cmdline_user_args()
	check(args.size() % 2 == 0, "Expected content/binding pairs")
	for i in range(0, args.size() - 1, 2):
		check(library.open(args[i]) and library.select_language("gb"), library.error)
		check(bindings.open(args[i + 1], library.manifest), bindings.error)
		check(catalogues.open(library), catalogues.error)
		check(state.configure(bindings, catalogues, catalogues.content_id), state.error)
		if state.snapshot().is_empty(): continue
		before = state.snapshot()
		check(before.player_pose.origin == Vector3(0, 0, -60000), "Actual initial pose changed")
		check(radio.configure(bindings, library, counts), radio.error)
		time = 1500
		for event in 3:
			radio.step(time, {}, 0)
			check(state.update(radio.snapshot()) and not state.snapshot().formation_revealed, "Actual formation revealed early")
			time += 5501
			radio.step(time, {}, 0)
			check(state.update(radio.snapshot()), state.error)
		after = state.snapshot()
		check(after.formation_revealed and after.player_pose.origin == Vector3(18000, -12000, -40000), "Actual first relocation changed")
		check(after.camera_position_parameter == Vector3(-12000, 2000, -500), "Actual camera parameter changed")
		check(after.actors[0].position == Vector3(-10000, 500, 0) and after.actors[1].position == Vector3(-10000, -300, -1700) and after.actors[2].position == Vector3(-10000, -200, 2000), "Actual formation coordinates changed")
		print(library.manifest.profile.edition, ": initial placement and finished-event formation verified")
	print("Opening staging checks: %d failures" % failures)
	quit(1 if failures else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
