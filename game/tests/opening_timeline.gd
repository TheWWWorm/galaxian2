extends SceneTree
const Timeline = preload("res://src/simulation/opening_timeline.gd")
const Sequence = preload("res://src/simulation/opening_sequence.gd")
const Definitions = preload("res://src/content/opening_clock_definitions.gd")
const Fixture = preload("res://tests/opening_clock_fixture.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
var failures := 0

func _initialize() -> void:
	for mac in [true,false]:
		var data := Fixture.definition(mac)
		var arch := "x86_64" if mac else "armv7"
		check(Definitions.validate(data,65536,arch).is_empty(),"Valid clock rejected")
		for bad in ["seed","range","unit","order","extent","overlap"]:
			var copy := data.duplicate(true)
			match bad:
				"seed": copy.initial_elapsed_ms = true
				"range": copy.initial_elapsed_ms = 2147483648
				"unit": copy.time_unit = "seconds"
				"order": copy.advance_before_controller = false
				"extent": copy.provenance.frame.offset = 65536
				"overlap": copy.provenance.frame.offset = copy.provenance.reset.offset
			check(not Definitions.validate(copy,65536,arch).is_empty(),"Malformed clock accepted: "+bad)
	var args := OS.get_cmdline_user_args()
	check(args.size()%2==0,"Expected content/bindings pairs")
	for i in range(0,args.size()-1,2): verify_source(args[i],args[i+1])
	print("Opening timeline checks: %d failures" % failures)
	quit(1 if failures else 0)

func verify_source(content: String,pack: String) -> void:
	var library := Library.new(); var bindings := Bindings.new(); var catalogues := Catalogues.new()
	check(library.open(content) and library.select_language("gb"),library.error)
	check(bindings.open(pack,library.manifest),bindings.error)
	check(catalogues.open(library),catalogues.error)
	check(not bindings.opening_clock.is_empty(),"Original clock missing")
	if bindings.opening_clock.is_empty(): return
	var timeline := Timeline.new(); var control := Sequence.new()
	var counts := []; counts.resize(23); counts.fill(1)
	check(timeline.configure(bindings,catalogues,library,counts),timeline.error)
	check(control.configure(bindings,catalogues,library,counts),control.error)
	check(timeline.snapshot().elapsed_ms == 0,"Source new-game clock is not zero")
	check(timeline.update(100,true,false),timeline.error)
	check(control.update(100,100,true),control.error)
	check(timeline.snapshot()==control.snapshot(),"Clock increment did not precede scene and radio work")
	var before := timeline.snapshot()
	check(timeline.update(0,false,false),timeline.error)
	check(timeline.snapshot().elapsed_ms==100 and timeline.snapshot().scene.actors!=before.scene.actors,"Zero-time source update lost frame-based drift")
	for invalid in [[151,true,false],[NAN,true,false],[1,1,false],[1,true,1],[-1,true,true]]:
		before = timeline.snapshot()
		check(not timeline.update(invalid[0],invalid[1],invalid[2]) and timeline.snapshot()==before,"Invalid frame consumed time or state")
	var finished := []
	var first_start := -1
	var paused := false
	for frame in 700:
		check(timeline.update(100,true,false),timeline.error)
		var state := timeline.snapshot()
		for event in state.radio_changes:
			if event.kind=="started" and event.event==0: first_start=state.elapsed_ms
			if event.kind=="finished": finished.append(event.event)
		if state.radio.visible and not paused:
			before=state.duplicate(true); before.radio_changes=[]
			for pause_frame in 30:
				check(timeline.update(100,true,true),timeline.error)
				check(timeline.snapshot()==before,"Pause advanced drift, radio, camera or elapsed time")
			paused=true
		if finished.size()==9 and state.camera.shot.phase==4: break
	check(first_start==1500,"Ordinary milliseconds did not reach first radio gate at the source threshold")
	check(finished==[0,1,2,3,4,5,6,7,8],"Opening timeline skipped or reordered pre-combat radio")
	check(paused and timeline.snapshot().camera.shot.phase==4,"Timed sequence failed to reach follow handoff")
	for frame in 100: check(timeline.update(100,true,false),timeline.error)
	check(not timeline.snapshot().radio.started[9],"Unsupported combat gate was completed")
	var saved := bindings.opening_clock.duplicate(true)
	bindings.opening_clock.initial_elapsed_ms=2147483640
	check(timeline.configure(bindings,catalogues,library,counts),timeline.error)
	before=timeline.snapshot()
	check(not timeline.update(100,true,false) and timeline.snapshot()==before,"Clock overflow partially advanced state")
	bindings.opening_clock.initial_elapsed_ms=12
	check(timeline.configure(bindings,catalogues,library,counts),timeline.error)
	check(timeline.update(100,false,false) and timeline.snapshot().elapsed_ms==112,"Imported nonzero seed was replaced with a literal zero")
	bindings.opening_clock={}
	check(not timeline.configure(bindings,catalogues,library,counts) and timeline.snapshot().is_empty(),"Unsupported clock retained a live timeline")
	bindings.opening_clock=saved
	print(library.manifest.profile.edition+": fresh clock, paused radio and timed opening handoff verified")

func check(ok: bool,message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
