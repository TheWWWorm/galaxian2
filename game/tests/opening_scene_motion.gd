extends SceneTree
const Motion = preload("res://src/simulation/opening_scene_motion.gd")
const Drift = preload("res://src/simulation/opening_drift.gd")
const Definitions = preload("res://src/content/opening_drift_definitions.gd")
const Fixture = preload("res://tests/opening_drift_fixture.gd")
const ActorFixture = preload("res://tests/opening_actor_fixture.gd")
const StagingFixture = preload("res://tests/opening_staging_fixture.gd")
const CameraFixture = preload("res://tests/opening_camera_fixture.gd")
const FollowFixture = preload("res://tests/camera_follow_fixture.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Library = preload("res://src/content/library.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Radio = preload("res://src/simulation/radio_sequence.gd")
var failures := 0

func _initialize() -> void:
	for mac in [true, false]:
		var data: Dictionary = JSON.parse_string(JSON.stringify(Fixture.definition(mac)))
		var arch := "x86_64" if mac else "armv7"
		check(Definitions.validate(data, 65536, arch).is_empty(), "Valid drift definitions rejected")
		for bad in ["missing", "frequency", "bias", "count", "id", "duplicate", "phase", "skip", "application", "extent", "overlap"]:
			var copy := data.duplicate(true)
			match bad:
				"missing": copy.erase("actor_ids")
				"frequency": copy.frequency_per_millisecond = NAN
				"bias": copy.bias = true
				"count": copy.actor_ids = []
				"id": copy.actor_ids[0] = -1
				"duplicate": copy.actor_ids[0] = copy.actor_ids[1]
				"phase": copy.through_phase = 1.5
				"skip": copy.skip_formation_update = 1
				"application": copy.application = "per_second"
				"extent": copy.provenance.wave.offset = 65536
				"overlap": copy.provenance.wave.offset = copy.provenance.cut.offset
			check(not Definitions.validate(copy, 65536, arch).is_empty(), "Malformed drift accepted: " + bad)
		check(Drift.displacement(data, 0, 0, false).value == Vector3(0, -0.25, 0), "Zero elapsed displacement changed")
		for time in [1, 50, 200, 500, 1000, 100000000]:
			var result := Drift.displacement(data, time, 2, false)
			var angle := PackedFloat32Array([PackedFloat32Array([time])[0] * 0.03125])[0]
			var expected := PackedFloat32Array([absf(PackedFloat32Array([sin(angle)])[0]) - 0.25])[0]
			check(result.value == Vector3(0, expected, 0) and result.apply, "Wave/time float boundaries changed")
		check(not Drift.displacement(data, 0, 3, false).apply and not Drift.displacement(data, 0, 0, true).apply, "Drift applied outside its phase or on formation")
		for bad in [-1, 0.5, NAN, true]: check(Drift.displacement(data, bad, 0, false).has("error"), "Invalid elapsed value accepted")
	var bindings := Bindings.new(); var catalogues := Catalogues.new()
	bindings.base_content_id = "a".repeat(64); bindings.binding_id = "b".repeat(64)
	catalogues.content_id = bindings.base_content_id; catalogues.tables = {"ships": [{}, {}]}
	bindings.ship_model_resources = [100, 101]
	for id in [100, 101]:
		var path := "resources/data/meshes/example%d.aem" % id
		bindings.records[id] = [{"resource": path, "kind": "mesh", "registration_type": 4}]
		bindings.base_files[path] = {"kind": "mesh"}
	bindings.opening_actors = ActorFixture.definition()
	bindings.opening_actors.actors.append(bindings.opening_actors.actors[1].duplicate(true)); bindings.opening_actors.actors[2].actor_id = 2
	bindings.opening_staging = StagingFixture.definition(); bindings.opening_dialogue = StagingFixture.dialogue()
	bindings.opening_camera = CameraFixture.definition(); bindings.camera_follow = FollowFixture.definition()
	bindings.opening_drift = Fixture.definition(); bindings.frame_clock = {"max_frame_milliseconds": 150, "time_unit": "milliseconds"}
	var motion := Motion.new()
	check(motion.configure(bindings, catalogues, catalogues.content_id), motion.error)
	var flags := []; flags.resize(23); flags.fill(false)
	var radio := {"base_content_id": bindings.base_content_id, "binding_id": bindings.binding_id, "finished": flags}
	var initial := motion.snapshot()
	check(motion.update(16, 0, radio) and motion.update(0, 0, radio), motion.error)
	for i in 3:
		check(motion.snapshot().scene.actors[i].position == initial.scene.actors[i].position + Vector3(0, -0.5, 0), "Per-update drift was converted to delta velocity")
		check(not motion.snapshot().scene.actors[i].has("pose"), "Hidden actor orientation invented")
	check(motion.snapshot().scene.player_pose == initial.scene.player_pose, "Actor drift moved the player")
	flags[2] = true
	check(motion.update(16, 0, radio), motion.error)
	for i in 3:
		var p: Array = bindings.opening_staging.formation.actors[i].position
		check(motion.snapshot().scene.actors[i].position == Vector3(p[0], p[1], p[2]), "Formation received unwanted drift")
	flags[5] = true
	check(motion.update(16, 0, radio), motion.error)
	check(motion.snapshot().camera.view.look == motion.snapshot().scene.actors[1].position, "Camera did not observe current-frame actor drift")
	flags[8] = true
	var before := motion.snapshot()
	check(motion.update(16, 0, radio), motion.error)
	check(motion.snapshot().scene.actors[0].position.y == before.scene.actors[0].position.y - 0.25 and motion.snapshot().camera.shot.phase == 3, "Engagement omitted the final drift update")
	before = motion.snapshot()
	check(motion.update(16, 10, radio), motion.error)
	check(motion.snapshot().scene.actors == before.scene.actors, "Drift continued after the phase boundary")
	for bad in ["delta", "time", "identity", "regression", "boolean"]:
		var copy := radio.duplicate(true); var delta: Variant = 16; var elapsed: Variant = 10
		match bad:
			"delta": delta = 151
			"time": elapsed = 9
			"identity": copy.binding_id = "c".repeat(64)
			"regression": copy.finished[2] = false
			"boolean": elapsed = true
		before = motion.snapshot()
		check(not motion.update(delta, elapsed, copy) and motion.snapshot() == before, "Failed frame partially changed scene: " + bad)
	bindings.opening_drift = {}
	check(not motion.configure(bindings, catalogues, catalogues.content_id) and motion.snapshot().is_empty(), "Reconfiguration retained scene state")
	var args := OS.get_cmdline_user_args()
	check(args.size() % 2 == 0, "Expected content/bindings pairs")
	for i in range(0, args.size() - 1, 2): verify_source(args[i], args[i + 1])
	print("Opening scene motion checks: %d failures" % failures)
	quit(1 if failures else 0)

func verify_source(content: String, pack: String) -> void:
	var library := Library.new(); var bindings := Bindings.new(); var catalogues := Catalogues.new()
	check(library.open(content) and library.select_language("gb"), library.error)
	check(bindings.open(pack, library.manifest), bindings.error)
	check(catalogues.open(library), catalogues.error)
	var motion := Motion.new(); var radio := Radio.new()
	check(motion.configure(bindings, catalogues, catalogues.content_id), motion.error)
	if motion.snapshot().is_empty(): return
	var counts := []; counts.resize(23); counts.fill(1)
	check(radio.configure(bindings, library, counts), radio.error)
	var time := 1500
	for event in 9:
		for finishing in [false, true]:
			if finishing: time += 5501
			radio.step(time, {}, 0)
			var before := motion.snapshot()
			check(motion.update(16, time, radio.snapshot()), motion.error)
			var after := motion.snapshot()
			var reveal: bool = not before.scene.formation_revealed and after.scene.formation_revealed
			if reveal:
				check(after.scene.actors[0].position.y == 500, "Actual formation drifted in its reveal frame")
			elif before.camera.shot.phase <= 2:
				var amount: float = Drift.displacement(bindings.opening_drift, time, before.camera.shot.phase, false).value.y
				for i in 3:
					check(after.scene.actors[i].position == before.scene.actors[i].position + Vector3(0, amount, 0), "Actual actor displacement changed")
			else: check(after.scene.actors == before.scene.actors, "Actual drift continued after phase 2")
	check(motion.snapshot().camera.shot.mode == "follow", "Actual moving-scene handoff failed")
	print(library.manifest.profile.edition, ": source drift, formation, actor tracking and follow handoff verified")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
