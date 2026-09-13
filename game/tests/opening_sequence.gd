extends SceneTree
const Sequence = preload("res://src/simulation/opening_sequence.gd")
const Radio = preload("res://src/simulation/radio_sequence.gd")
const Motion = preload("res://src/simulation/opening_scene_motion.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Library = preload("res://src/content/library.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Actors = preload("res://tests/opening_actor_fixture.gd")
const Staging = preload("res://tests/opening_staging_fixture.gd")
const Camera = preload("res://tests/opening_camera_fixture.gd")
const Follow = preload("res://tests/camera_follow_fixture.gd")
const Drift = preload("res://tests/opening_drift_fixture.gd")
var failures := 0

func _initialize() -> void:
	var bindings := Bindings.new(); var library := Library.new(); var catalogues := Catalogues.new()
	bindings.base_content_id = "a".repeat(64); bindings.binding_id = "b".repeat(64)
	library.manifest = {"content_id": bindings.base_content_id}
	library.active_language = "gb"
	for i in 23: library.strings.append("Example transmission %d" % i)
	catalogues.content_id = bindings.base_content_id; catalogues.tables = {"ships": [{},{}]}
	bindings.ship_model_resources = [100,101]
	for id in [100,101]:
		var path := "resources/data/meshes/example%d.aem" % id
		bindings.records[id] = [{"resource": path,"kind": "mesh","registration_type": 4}]
		bindings.base_files[path] = {"kind": "mesh"}
	bindings.opening_actors = Actors.definition()
	bindings.opening_actors.actors.append(bindings.opening_actors.actors[1].duplicate(true))
	bindings.opening_actors.actors[2].actor_id = 2
	bindings.opening_staging = Staging.definition(); bindings.opening_camera = Camera.definition()
	bindings.camera_follow = Follow.definition(); bindings.opening_drift = Drift.definition()
	bindings.frame_clock = {"max_frame_milliseconds": 150,"time_unit": "milliseconds"}
	bindings.opening_dialogue = Staging.dialogue()
	bindings.opening_dialogue.events[3].condition = 27
	bindings.opening_dialogue.events[3].values = [1]
	bindings.opening_dialogue.events[11].condition = 9
	bindings.opening_dialogue.events[11].values = [0]
	verify(bindings,catalogues,library,11)
	verify_forks(bindings,catalogues,library)
	verify_phase_gate(bindings,catalogues,library)
	var args := OS.get_cmdline_user_args()
	check(args.size() % 2 == 0,"Expected content/bindings pairs")
	for i in range(0,args.size()-1,2):
		library = Library.new(); bindings = Bindings.new(); catalogues = Catalogues.new()
		check(library.open(args[i]) and library.select_language("gb"),library.error)
		check(bindings.open(args[i+1],library.manifest),bindings.error)
		check(catalogues.open(library),catalogues.error)
		verify(bindings,catalogues,library,9)
		print(library.manifest.profile.edition + ": scene-before-radio frame ownership verified")
	print("Opening sequence checks: %d failures" % failures)
	quit(1 if failures else 0)

func verify(bindings: RefCounted,catalogues: RefCounted,library: RefCounted,event_count: int) -> void:
	var sequence := Sequence.new()
	var counts := []; counts.resize(23); counts.fill(1)
	check(sequence.configure(bindings,catalogues,library,counts),sequence.error)
	if sequence.snapshot().is_empty(): return
	var elapsed: int = bindings.opening_dialogue.events[0].values[0]
	for event in event_count:
		check(sequence.update(16,elapsed,true),sequence.error)
		var start := sequence.snapshot()
		check(start.radio.active_event == event and start.radio.started[event],"Radio event did not start in source order: %d" % event)
		# Completion happens in presentation, after this frame's controller. Use
		# explicit time jumps to exercise boundaries without claiming frame pacing.
		elapsed += 5501
		check(not sequence.update(151,elapsed,true) and sequence.snapshot() == start,"Failed scene frame advanced radio or drift")
		check(sequence.update(16,elapsed,true),sequence.error)
		var finished := sequence.snapshot()
		check(finished.radio.finished[event],"Radio did not finish")
		var phase: int = start.camera.shot.phase
		check(finished.camera.shot.phase == phase,"Fresh radio completion cut the camera in the same frame")
		if event == int(bindings.opening_staging.formation.after_event_finished):
			check(not finished.scene.formation_revealed,"Formation revealed before the next scene update")
		# Suppressed radio still permits scene work and consumption of flags from
		# the preceding presentation. It cannot start a new transmission.
		elapsed += 1
		check(sequence.update(16,elapsed,false),sequence.error)
		var consumed := sequence.snapshot()
		check(consumed.radio == finished.radio and consumed.radio_changes.is_empty(),"Suppressed radio processed events")
		var expected := phase
		if event == int(bindings.opening_staging.formation.after_event_finished):
			expected = 1
			check(consumed.scene.formation_revealed,"Finished formation cue was not consumed")
		if event == int(bindings.opening_camera.actor_cut.after_event_finished): expected = 2
		if event == int(bindings.opening_camera.pan.engagement_after_event_finished): expected = 3
		if event == int(bindings.opening_camera.pan.follow_player_after_event_finished): expected = 4
		check(consumed.camera.shot.phase == expected,"Next update missed a camera transition")
		elapsed += 1
	# Living imported actors keep combat-dependent dialogue blocked. No test
	# fabricates damage, mission completion or an earned reward.
	check(sequence.update(16,elapsed+20000,true),sequence.error)
	var stopped := sequence.snapshot()
	check(stopped.camera.shot.phase == 4 and stopped.radio.active_event == -1 and not stopped.radio.started[event_count],"Unsupported combat was bypassed")
	for row in [[16,elapsed-1,true],[16,elapsed+20001,1],[NAN,elapsed+20001,true],[16,2147483648,true]]:
		check(not sequence.update(row[0],row[1],row[2]) and sequence.snapshot() == stopped,"Invalid frame changed composed sequence")
	var detached := sequence.snapshot()
	detached.scene.actors[0].current_hull = 0
	detached.radio.finished[0] = false
	detached.radio_changes.append({"kind":"invented"})
	check(sequence.snapshot() == stopped,"Sequence snapshot aliases owned state")
	counts.pop_back()
	check(not sequence.configure(bindings,catalogues,library,counts) and sequence.snapshot().is_empty(),"Failed configuration retained scene or radio")

func verify_forks(bindings: RefCounted,catalogues: RefCounted,library: RefCounted) -> void:
	var counts := []; counts.resize(23); counts.fill(1)
	var radio := Radio.new(); var motion := Motion.new()
	check(radio.configure(bindings,library,counts),radio.error)
	check(motion.configure(bindings,catalogues,catalogues.content_id),motion.error)
	radio.step(0,{},0)
	check(motion.update(16,0,radio.snapshot()),motion.error)
	var before_radio := radio.snapshot(); var before_motion := motion.snapshot()
	var next_radio: RefCounted = radio.fork_for_frame()
	var next_motion: RefCounted = motion.fork_for_frame()
	next_radio.step(5501,{},0)
	check(next_motion.update(16,5501,next_radio.snapshot()),next_motion.error)
	check(radio.snapshot() == before_radio and motion.snapshot() == before_motion,"Fork changed prior radio, actors or camera history")
	check(next_radio.snapshot().finished[0] and next_motion.snapshot().scene.actors != before_motion.scene.actors,"Fork did not advance independently")

func verify_phase_gate(bindings: RefCounted,catalogues: RefCounted,library: RefCounted) -> void:
	var sequence := Sequence.new()
	var counts := []; counts.resize(23); counts.fill(1)
	check(sequence.configure(bindings,catalogues,library,counts),sequence.error)
	var elapsed := 0
	for event in 3:
		check(sequence.update(16,elapsed,true),sequence.error)
		elapsed += 5501
		if event == 2:
			var active := sequence.snapshot()
			check(sequence.update(16,elapsed,false),sequence.error)
			check(sequence.snapshot().radio == active.radio,"Suppressed presentation finished an active transmission")
		check(sequence.update(16,elapsed,true),sequence.error)
		elapsed += 1
	check(sequence.snapshot().camera.shot.phase == 0,"Formation consumed a just-finished cue")
	check(sequence.update(16,elapsed,true),sequence.error)
	var state := sequence.snapshot()
	check(state.camera.shot.phase == 1 and state.radio.active_event == 3,"Radio did not observe the same frame's new cinematic phase")
	for row in bindings.opening_staging.formation.actors:
		check(state.scene.actors[int(row.actor_id)].position == Vector3(row.position[0],row.position[1],row.position[2]),"Formation drifted during its reveal frame")

func check(ok: bool,message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
