extends SceneTree
const Radio = preload("res://src/simulation/radio_sequence.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Library = preload("res://src/content/library.gd")
var failures := 0

func _initialize() -> void:
	var binding := Bindings.new()
	binding.base_content_id = "a".repeat(64)
	binding.binding_id = "b".repeat(64)
	binding.opening_dialogue = fixture()
	var library := Library.new()
	library.manifest = {"content_id": binding.base_content_id}
	library.active_language = "gb"
	for i in 23: library.strings.append("Synthetic line %d" % i)
	var counts := []
	counts.resize(23)
	counts.fill(1)
	var radio := Radio.new()
	check(radio.configure(binding, library, counts), radio.error)
	check(radio.step(49, {}, 0).is_empty(), "Elapsed trigger fired early")
	check(radio.step(50, {}, 0) == [{"kind": "started", "event": 0}], "Elapsed trigger boundary")
	check(radio.snapshot().started[0] and not radio.snapshot().finished[0], "Started conflated with finished")
	check(radio.step(2050, {}, 0).is_empty(), "Radio display delay must be strict")
	check(radio.step(2051, {}, 0).size() == 1 and radio.snapshot().visible, "Radio failed to become visible")
	check(radio.step(5550, {}, 0).is_empty(), "Radio finished at inclusive boundary")
	check(radio.step(5551, {}, 0) == [{"kind": "finished", "event": 0}], "Radio completion boundary")
	check(radio.snapshot().active_event == -1, "Next event started within completion frame")
	check(radio.step(5551, {}, 0) == [{"kind": "started", "event": 1}], "Dependent event missing")
	var snap := radio.snapshot()
	snap.finished[0] = false
	check(radio.snapshot().finished[0], "Mutable radio snapshot")
	check(radio.step(5550, {}, 0).is_empty() and not radio.error.is_empty() and radio.snapshot().active_event == 1, "Backward time changed state")
	# One large advance completes only the active line. It never earns a mission.
	var changes := radio.step(50000, {}, 0)
	check(changes.size() == 2 and changes[0].kind == "display" and changes[1].kind == "finished", "Long frame lost display/completion")
	check(radio.step(50000, {}, 0).is_empty(), "Missing actors treated as destroyed")
	check(radio.step(50000, {0: 0, 1: 0, 2: 1}, 0).is_empty(), "Live actor ignored")
	check(radio.step(50000, {0: 0, 1: 0, 2: -1}, 0) == [{"kind": "started", "event": 2}], "Hull gate not satisfied")
	radio.step(55501, {}, 0)
	check(radio.step(55501, {}, 11).is_empty(), "Phase equality used as greater-than")
	check(radio.step(55501, {}, 12) == [{"kind": "started", "event": 3}], "Phase gate not satisfied")
	# The reader accepts edition text IDs; runtime binds to the selected language.
	for bad in ["identity", "language", "text", "line_count", "self_dependency"]:
		binding.opening_dialogue = fixture()
		binding.base_content_id = library.manifest.content_id
		library.active_language = "gb"
		counts[0] = 1
		match bad:
			"identity": binding.base_content_id = "c".repeat(64)
			"language": library.active_language = ""
			"text": binding.opening_dialogue.events[0].text_id = 23
			"line_count": counts[0] = 0
			"self_dependency": binding.opening_dialogue.events[1].values = [1]
		check(not radio.configure(binding, library, counts) and radio.snapshot().is_empty(), "Invalid configuration retained radio: " + bad)
	var args := OS.get_cmdline_user_args()
	check(args.size() % 2 == 0, "Pass content/binding pairs")
	for i in range(0, args.size() - 1, 2):
		check(library.open(args[i]) and library.select_language("gb"), library.error)
		check(binding.open(args[i + 1], library.manifest), binding.error)
		counts.fill(1) # Isolated scheduling fixture. Bitmap-derived counts are checked by source_text_layout.
		check(radio.configure(binding, library, counts), radio.error)
		var rows: Array = binding.opening_dialogue.get("events", [])
		check(rows.size() == 23, "Source opening event count")
		if rows.size() != 23: continue
		# Both supplied Mac layouts use the same profile name but have different
		# source text tables. The guarded declaration offset identifies the one
		# imported with this binding; the voice table independently names its row.
		var first_text_id:=1668 if library.manifest.profile.edition=="ios-hd" else -1
		if first_text_id<0:
			match int(binding.opening_dialogue.get("provenance",{}).get("declaration",{}).get("offset",-1)):
				839618:first_text_id=1649
				845802:first_text_id=1657
		check(first_text_id>=0 and rows[0].text_id==first_text_id,"Imported opening text differs from its guarded source layout")
		var voice: Dictionary=binding.opening_dialogue.get("voice",{})
		if not voice.is_empty():check(voice.get("text_ids",[]).size()==rows.size() and int(voice.text_ids[0])==first_text_id,"Opening voice table names another source text row")
		check(rows[9].values.map(func(value): return int(value)) == [0, 1, 2] and rows[16].values.map(func(value): return int(value)) == [12], "Source combat/phase gates changed")
		check(radio.step(1500, {}, 0) == [{"kind": "started", "event": 0}], "Real declarations did not activate")
		check(radio.snapshot().text == library.strings[int(rows[0].text_id)], "Localized radio binding failed")
		var time := 1500
		for event in 9:
			if event > 0:
				check(radio.step(time, {}, 0) == [{"kind": "started", "event": event}], "Real pre-combat dialogue order changed")
			time += 5501
			radio.step(time, {}, 0)
			check(radio.snapshot().finished[event], "Real radio line did not finish")
		check(radio.step(time, {}, 0).is_empty(), "Missing combat was treated as won")
		check(radio.step(time, {0: 0, 1: 0, 2: 0}, 0) == [{"kind": "started", "event": 9}], "Real combat radio gate failed")
		print(library.manifest.profile.edition, ": 23 radio events bound to selected language")
	print("Radio checks: %d failures" % failures)
	quit(1 if failures else 0)

func fixture() -> Dictionary:
	var rows := []
	for i in 23:
		rows.append({"text_id": i, "speaker_id": i, "condition": 5, "values": [100000]})
	rows[0].values = [50]
	rows[1].condition = 6
	rows[1].values = [0]
	rows[2].condition = 9
	rows[2].values = [0, 1, 2]
	rows[3].condition = 27
	rows[3].values = [12]
	return {"campaign_cursor": 0, "events": rows, "timing": {"display_delay_ms": 2000, "base_duration_ms": 1500, "per_line_ms": 2000}}

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
