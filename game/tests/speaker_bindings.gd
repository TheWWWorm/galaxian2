extends SceneTree
const Definitions = preload("res://src/content/speaker_definitions.gd")
const Fixture = preload("res://tests/speaker_fixture.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Library = preload("res://src/content/library.gd")
var failures := 0

func _initialize() -> void:
	for mac in [true, false]:
		var data := Fixture.definition(mac)
		var arch := "x86_64" if mac else "armv7"
		check(Definitions.validate(data, 65536, arch).is_empty(), "Synthetic speaker scope rejected")
		for bad in ["count", "offset", "boundary", "duplicate", "status", "invented", "parts", "extent", "table"]:
			var invalid := data.duplicate(true)
			match bad:
				"count": invalid.fixed_speaker_count = 4
				"offset": invalid.first_name_id = -1
				"boundary": invalid.agent_speaker_start = 4
				"duplicate": invalid.portraits[2].speaker_id = 1
				"status": invalid.portraits[3].status = "fixed"
				"invented": invalid.portraits[0].parts = [0, 0, 0, 0]
				"parts": invalid.portraits[1].parts[0] = -2
				"extent": invalid.portraits[1].source_offset = 65535
				"table": invalid.provenance.portrait_table.bytes = 1
			check(not Definitions.validate(invalid, 65536, arch).is_empty(), "Invalid speaker scope accepted: " + bad)
		var binding := Bindings.new()
		binding.base_content_id = "a".repeat(64)
		binding.binding_id = "b".repeat(64)
		binding.speaker_bindings = data
		var library := Library.new()
		library.manifest = {"content_id": binding.base_content_id}
		library.active_language = "aa"
		library.strings.resize(206)
		library.strings[201] = "Original [name] Я"
		check(binding.resolve_speaker_name(1, library) == "Original [name] Я", "Source name or literal Unicode changed")
		var portrait := binding.resolve_speaker_portrait(1)
		check(portrait.parts == [0, -1, 3, 4], "Fixed portrait parts changed")
		portrait.parts[0] = 99
		check(binding.resolve_speaker_portrait(1).parts[0] == 0, "Returned portrait mutates loaded definitions")
		for id in [-1, 0, 3, 5, 500]:
			check(binding.resolve_speaker_portrait(id).is_empty() and not binding.error.is_empty(), "Unsupported portrait guessed")
		for id in [-1, 6, 500]:
			check(binding.resolve_speaker_name(id, library).is_empty() and not binding.error.is_empty(), "Unsupported name guessed")
		library.manifest.content_id = "c".repeat(64)
		check(binding.resolve_speaker_name(1, library).is_empty() and not binding.error.is_empty(), "Cross-content name accepted")
		binding.open("/missing-speaker-fixture", {})
		check(binding.speaker_bindings.is_empty(), "Old speaker scope retained")
	var args := OS.get_cmdline_user_args()
	for i in range(0, args.size() - 1, 2):
		var library := Library.new()
		var binding := Bindings.new()
		check(library.open(args[i]) and binding.open(args[i + 1], library.manifest), "Real speaker scope failed: " + binding.error)
		check(binding.speaker_bindings.get("portraits", []).size() == 63, "Incomplete source speaker table")
		for language in library.manifest.languages:
			check(library.select_language(language), library.error)
			for event in binding.opening_dialogue.events:
				var speaker_name: String = binding.resolve_speaker_name(int(event.speaker_id), library)
				check(not speaker_name.is_empty() and binding.error.is_empty(), "Opening speaker name unavailable")
		check(binding.resolve_speaker_portrait(0).is_empty() and binding.resolve_speaker_portrait(21).is_empty(), "Unknown or procedural portrait fabricated")
		for id in [9, 10, 11, 15, 17]: check(not binding.resolve_speaker_portrait(id).is_empty(), "Source-present fixed portrait missing")
	print("Speaker binding checks: %d failures" % failures)
	quit(1 if failures else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
