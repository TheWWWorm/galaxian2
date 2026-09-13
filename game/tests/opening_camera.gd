extends SceneTree
const Definitions = preload("res://src/content/opening_camera_definitions.gd")
const Director = preload("res://src/simulation/opening_camera.gd")
const Fixture = preload("res://tests/opening_camera_fixture.gd")
const StagingFixture = preload("res://tests/opening_staging_fixture.gd")
const Staging = preload("res://src/simulation/opening_staging.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Radio = preload("res://src/simulation/radio_sequence.gd")
const Library = preload("res://src/content/library.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
var failures := 0

func _initialize() -> void:
	for mac in [true, false]:
		var data: Dictionary = JSON.parse_string(JSON.stringify(Fixture.definition(mac)))
		var arch := "x86_64" if mac else "armv7"
		check(Definitions.validate(data, 65536, arch).is_empty(), "Camera definitions rejected")
		for bad in ["missing", "nan", "eye", "actor", "mode", "up", "order", "fraction", "extent", "overlap"]:
			var broken := data.duplicate(true)
			match bad:
				"missing": broken.erase("pan")
				"nan": broken.pan.velocity_per_ms[0] = NAN
				"eye": broken.actor_cut.eye = [0, 1]
				"actor": broken.actor_cut.actor_id = 3
				"mode": broken.initial_fixed_eye = false
				"up": broken.inherit_target_up = 1
				"order": broken.pan.follow_player_after_event_finished = 5
				"fraction": broken.actor_cut.after_event_finished = 5.5
				"extent": broken.provenance.defaults.offset = 65535
				"overlap": broken.provenance.pan2.offset = broken.provenance.cut.offset
			check(not Definitions.validate(broken, 65536, arch).is_empty(), "Invalid camera declarations accepted: " + bad)
	var bindings := Bindings.new()
	bindings.base_content_id = "a".repeat(64)
	bindings.binding_id = "b".repeat(64)
	bindings.opening_camera = Fixture.definition()
	bindings.opening_staging = StagingFixture.definition()
	bindings.opening_dialogue = StagingFixture.dialogue()
	var director := Director.new()
	check(director.configure(bindings), director.error)
	var radio := {"base_content_id": bindings.base_content_id, "binding_id": bindings.binding_id, "finished": [], "started": []}
	radio.finished.resize(23); radio.finished.fill(false)
	radio.started.resize(23); radio.started.fill(true)
	var scene := {"base_content_id": bindings.base_content_id, "binding_id": bindings.binding_id,
		"player_pose": Transform3D(Basis.IDENTITY, Vector3(0, 0, -90)), "actors": [{"actor_id": 1, "pose": Transform3D(Basis.IDENTITY, Vector3(-789, 896, 0))}]}
	check(director.view(scene).has("pose"), "Initial view unavailable")
	check(director.advance(16, radio) and director.snapshot().phase == 0, "Started events changed camera phase")
	radio.finished[2] = true
	check(director.advance(16, radio) and director.snapshot().phase == 1 and director.snapshot().eye == Vector3(-234, 512, -640), "Formation camera cut failed")
	radio.finished[5] = true
	var saved := director.snapshot()
	check(director.advance(0, radio) and director.snapshot().phase == 2 and director.snapshot().eye == Vector3(-123, 192, -123), "Zero-time cue handling changed or introduced movement")
	check(director.advance(16, radio), director.error)
	check(director.snapshot().phase == 2 and director.snapshot().actor_id == 1 and director.snapshot().eye == Vector3(-111, 192, -143), "Cut did not pan once in the same frame")
	var first := director.view(scene)
	check(first.has("pose"), "Actor camera view missing")
	scene.actors[0].pose.origin += Vector3(100, -80, 210)
	var moved := director.view(scene)
	check(moved.has("pose") and moved.pose.origin == first.pose.origin and not moved.pose.basis.is_equal_approx(first.pose.basis), "View did not track the supplied moving actor")
	var local: Vector3 = moved.pose.affine_inverse() * scene.actors[0].pose.origin
	check(absf(local.x) < 0.001 and absf(local.y) < 0.001 and local.z < 0, "Moving target is not centered")
	for bad in ["time", "fraction", "identity", "binding", "flags", "boolean", "regression"]:
		var copy := radio.duplicate(true)
		var delta: Variant = 16
		match bad:
			"time": delta = -1
			"fraction": delta = 1.5
			"identity": copy.base_content_id = "c".repeat(64)
			"binding": copy.binding_id = "c".repeat(64)
			"flags": copy.finished.pop_back()
			"boolean": copy.finished[0] = 1
			"regression": copy.finished[2] = false
		saved = director.snapshot()
		check(not director.advance(delta, copy) and director.snapshot() == saved, "Invalid frame changed camera: " + bad)
	for bad in ["identity", "missing", "duplicate", "degenerate"]:
		var copy := scene.duplicate(true)
		match bad:
			"identity": copy.binding_id = "c".repeat(64)
			"missing": copy.actors = []
			"duplicate": copy.actors.append(copy.actors[0].duplicate(true))
			"degenerate": copy.actors[0].pose.origin = director.snapshot().eye
		check(not director.view(copy).has("pose"), "Invalid view accepted: " + bad)
	radio.finished[8] = true
	saved = director.snapshot()
	check(director.advance(10, radio) and director.snapshot().phase == 3 and director.snapshot().eye == saved.eye + Vector3(7.5, 0, -12.5), "Engagement cue panned twice or skipped pan")
	radio.finished[10] = true
	check(director.advance(10, radio) and director.snapshot().phase == 4 and director.snapshot().mode == "follow" and director.snapshot().target == "player", "Player-follow handoff failed")
	check(not director.view(scene).has("pose"), "Unimplemented follow mode fabricated a view")
	saved = director.snapshot()
	check(director.advance(16, radio) and director.snapshot() == saved, "Completed handoff repeated camera movement")
	saved.eye.x = 200
	check(director.snapshot().eye.x != 200, "Snapshot mutated director")
	check(director.configure(bindings), director.error)
	radio.finished.fill(true)
	check(director.advance(10, radio) and director.snapshot().phase == 1, "Skipped formation update with accumulated cues")
	check(director.advance(10, radio) and director.snapshot().phase == 3, "Cut/engagement cue ordering changed")
	check(director.snapshot().eye == Vector3(-115.5, 192, -135.5), "Entering phase 2 did not pan exactly once in the cut frame")
	for bad in ["missing", "order", "range", "identity"]:
		bindings.opening_camera = Fixture.definition()
		match bad:
			"missing": bindings.opening_camera = {}
			"order": bindings.opening_camera.actor_cut.after_event_finished = 1
			"range": bindings.opening_camera.pan.follow_player_after_event_finished = 24
			"identity": bindings.binding_id = ""
		check(not director.configure(bindings) and director.snapshot().is_empty(), "Failed reconfiguration retained camera")
	var args := OS.get_cmdline_user_args()
	check(args.size() % 2 == 0, "Expected content/binding pairs")
	for i in range(0, args.size() - 1, 2): verify_source(args[i], args[i + 1])
	print("Opening camera checks: %d failures" % failures)
	quit(1 if failures else 0)

func verify_source(content: String, pack: String) -> void:
	var library := Library.new()
	var bindings := Bindings.new()
	var catalogues := Catalogues.new()
	check(library.open(content) and library.select_language("gb"), library.error)
	check(bindings.open(pack, library.manifest), bindings.error)
	check(catalogues.open(library), catalogues.error)
	var staging := Staging.new()
	var director := Director.new()
	check(staging.configure(bindings, catalogues, catalogues.content_id), staging.error)
	check(director.configure(bindings), director.error)
	if director.snapshot().is_empty(): return
	check(director.view(staging.snapshot()).has("pose"), "Actual initial camera unavailable")
	var radio := Radio.new()
	var counts := []; counts.resize(23); counts.fill(1)
	check(radio.configure(bindings, library, counts), radio.error)
	var time := 1500
	for event in 9:
		radio.step(time, {}, 0)
		check(staging.update(radio.snapshot()) and director.advance(16, radio.snapshot()), director.error)
		time += 5501
		radio.step(time, {}, 0)
		check(staging.update(radio.snapshot()) and director.advance(16, radio.snapshot()), director.error)
		var expected := 0 if event < 2 else 1 if event < 6 else event - 4
		check(director.snapshot().phase == expected, "Actual camera used wrong finished-event gate")
		if event < 8: check(director.view(staging.snapshot()).has("pose"), "Actual fixed-eye camera unavailable")
	check(director.snapshot().mode == "follow" and not director.view(staging.snapshot()).has("pose"), "Actual follow handoff fabricated a fixed-eye view")
	print(library.manifest.profile.edition, ": radio-driven camera cuts, pans and player-follow handoff verified")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
