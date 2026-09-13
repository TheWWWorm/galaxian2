extends SceneTree
const View = preload("res://src/simulation/opening_view.gd")
const Rig = preload("res://src/simulation/camera_rig.gd")
const CameraFixture = preload("res://tests/opening_camera_fixture.gd")
const FollowFixture = preload("res://tests/camera_follow_fixture.gd")
const StagingFixture = preload("res://tests/opening_staging_fixture.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Library = preload("res://src/content/library.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Staging = preload("res://src/simulation/opening_staging.gd")
const Radio = preload("res://src/simulation/radio_sequence.gd")
var failures := 0

func _initialize() -> void:
	var bindings := Bindings.new()
	bindings.base_content_id = "a".repeat(64); bindings.binding_id = "b".repeat(64)
	bindings.opening_camera = CameraFixture.definition()
	bindings.opening_staging = StagingFixture.definition()
	bindings.opening_dialogue = StagingFixture.dialogue()
	bindings.camera_follow = FollowFixture.definition()
	bindings.frame_clock = {"max_frame_milliseconds": 150, "time_unit": "milliseconds"}
	var flags := []; flags.resize(23); flags.fill(false)
	var radio := {"base_content_id": bindings.base_content_id, "binding_id": bindings.binding_id, "finished": flags}
	var scene := {"base_content_id": bindings.base_content_id, "binding_id": bindings.binding_id,
		"player_pose": Transform3D(Basis.from_euler(Vector3(0.1, 0.3, -0.2)), Vector3(500, 40, 800)),
		"actors": [{"actor_id": 1, "pose": Transform3D(Basis.IDENTITY, Vector3(-900, 80, 600))}]}
	for handoff_ms in [0, 16]:
		flags.fill(false)
		var camera := View.new()
		check(camera.configure(bindings), camera.error)
		check(camera.update(16, radio, scene), camera.error)
		var initial := camera.snapshot()
		flags[2] = true
		check(camera.update(0, radio, scene), camera.error)
		check(camera.snapshot().shot.phase == 1 and camera.snapshot().view.eye == camera.snapshot().shot.eye, "Zero-time formation did not translate the view")
		check(camera.snapshot().view.pose.basis == initial.view.pose.basis and camera.snapshot().view.look == initial.view.look, "Zero-time formation recomputed the view orientation")
		flags[5] = true
		check(camera.update(0, radio, scene), camera.error)
		check(camera.snapshot().shot.phase == 2 and camera.snapshot().view.eye == Vector3(-123, 192, -123), "Zero-time cut did not refresh the fixed-eye view")
		scene.actors[0].pose.origin += Vector3(31, 7, -23)
		check(camera.update(0, radio, scene), camera.error)
		check(camera.snapshot().view.look == scene.actors[0].pose.origin, "Zero-displacement pan did not track the current actor")
		flags[8] = true
		check(camera.update(20, radio, scene), camera.error)
		check(camera.snapshot().shot.phase == 3, "Engagement gate did not advance")
		flags[10] = true
		var saved := camera.snapshot()
		var broken := scene.duplicate(true); broken.actors = []
		check(not camera.update(handoff_ms, radio, broken) and camera.snapshot() == saved, "Missing pre-handoff actor consumed the follow cue")
		scene.actors[0].pose.origin += Vector3(200, 60, 100)
		var refreshed_eye: Vector3 = saved.shot.eye + Vector3(0.75, 0, -1.25) * handoff_ms
		var refreshed_look: Vector3 = scene.actors[0].pose.origin
		check(camera.update(handoff_ms, radio, scene), camera.error)
		var state := camera.snapshot()
		check(state.shot.mode == "follow" and state.shot.phase == 4, "Follow mode did not activate")
		var expected_eye := refreshed_eye
		var expected_look := refreshed_look
		if handoff_ms > 0:
			expected_eye = expected_eye.lerp(scene.player_pose * Vector3(-18, 45, -220), 0.5)
			expected_look = expected_look.lerp(scene.player_pose * Vector3(12, 30, 100), 0.25)
		near(state.view.eye, expected_eye, "Handoff eye used the previous frame instead of the pan refresh")
		near(state.view.look, expected_look, "Handoff look used the previous frame or wrong target")
		check(state.view.mode == ("fixed_eye" if handoff_ms == 0 else "follow"), "Zero-time handoff incorrectly applied follow response")
		scene.actors = []
		check(camera.update(16, radio, scene), camera.error)
		near(camera.snapshot().view.eye, expected_eye.lerp(scene.player_pose * Vector3(-18, 45, -220), 0.5), "Next frame replayed the handoff refresh")
		saved = camera.snapshot()
		check(not camera.update(151, radio, scene) and camera.snapshot() == saved, "Oversized frame changed camera state")
		flags[5] = false
		check(not camera.update(16, radio, scene) and camera.snapshot() == saved, "Radio regression changed combined state")
		scene.actors = [{"actor_id": 1, "pose": Transform3D(Basis.IDENTITY, Vector3(-900, 80, 600))}]
		bindings.camera_follow = {}
		check(not camera.configure(bindings) and camera.snapshot().is_empty(), "Failed configuration retained combined state")
		bindings.camera_follow = FollowFixture.definition()
	var args := OS.get_cmdline_user_args()
	check(args.size() % 2 == 0, "Expected content/bindings pairs")
	for i in range(0, args.size() - 1, 2): verify_source(args[i], args[i + 1])
	print("Opening view sequencing checks: %d failures" % failures)
	quit(1 if failures else 0)

func verify_source(content: String, pack: String) -> void:
	var library := Library.new(); var bindings := Bindings.new(); var catalogues := Catalogues.new()
	check(library.open(content) and library.select_language("gb"), library.error)
	check(bindings.open(pack, library.manifest), bindings.error)
	check(catalogues.open(library), catalogues.error)
	var staging := Staging.new(); var camera := View.new(); var radio := Radio.new()
	check(staging.configure(bindings, catalogues, catalogues.content_id), staging.error)
	check(camera.configure(bindings), camera.error)
	if camera.snapshot().is_empty(): return
	var counts := []; counts.resize(23); counts.fill(1)
	check(radio.configure(bindings, library, counts), radio.error)
	var time := 1500
	for event in 9:
		for finishing in [false, true]:
			if finishing: time += 5501
			radio.step(time, {}, 0)
			check(staging.update(radio.snapshot()), staging.error)
			var before := camera.snapshot()
			var world := staging.snapshot()
			check(camera.update(16, radio.snapshot(), world), camera.error)
			var after := camera.snapshot()
			if event == 8 and finishing:
				check(after.shot.mode == "follow", "Actual source handoff missing")
				var eye: Vector3 = before.shot.eye + Staging.vec(bindings.opening_camera.pan.velocity_per_ms) * 16
				var look: Vector3 = world.actors[int(bindings.opening_camera.actor_cut.actor_id)].pose.origin
				var ew := Rig.weight(Rig.coefficients(bindings.camera_follow.response_matrix, bindings.camera_follow.eye_rate), 16, bindings.camera_follow.reciprocal_numerator)
				var lw := Rig.weight(Rig.coefficients(bindings.camera_follow.response_matrix, bindings.camera_follow.look_rate), 16, bindings.camera_follow.reciprocal_numerator)
				near(after.view.eye, eye.lerp(world.player_pose * Staging.vec(bindings.camera_follow.eye_offset), ew), "Actual handoff eye skipped the immediate refresh")
				near(after.view.look, look.lerp(world.player_pose * Staging.vec(bindings.camera_follow.look_offset), lw), "Actual handoff look skipped the actor refresh")
	print(library.manifest.profile.edition, ": ordered pan refresh and ordinary follow verified")

func near(actual: Vector3, expected: Vector3, message: String) -> void:
	check(actual.distance_to(expected) < 0.002, message + ": " + str(actual) + " vs " + str(expected))

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
