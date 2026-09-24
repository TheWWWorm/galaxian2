extends SceneTree
const Library = preload("res://src/content/library.gd")
var failures := 0


func _initialize() -> void:
	var directories := OS.get_cmdline_user_args()
	if directories.is_empty():
		push_error("Supply one or more imported cache directories after --")
		quit(2)
		return
	var identities := {}
	for directory in directories:
		var library := Library.new()
		check(library.open(directory), library.error)
		if library.manifest.is_empty():
			continue
		for code in library.manifest.languages:
			check(library.select_language(code), library.error)
			check(library.strings.size() == Library.catalogue_layout(library.manifest).strings, "Unexpected localization count")
		var malformed: Dictionary = library.manifest.duplicate(true)
		malformed.ship_table.records = 63
		check(Library.catalogue_layout(malformed).is_empty(), "Unknown ship extent accepted")
		malformed = library.manifest.duplicate(true)
		malformed.languages[malformed.languages.keys()[0]].records = 3402 if malformed.profile.edition == "mac-full-hd" else 3385
		check(Library.catalogue_layout(malformed).is_empty(), "Another edition's language extent accepted")
		malformed = library.manifest.duplicate(true)
		malformed.files["resources/data/bin/ships.bin"].bytes += 36
		check(Library.catalogue_layout(malformed).is_empty(), "Ship byte extent disagrees with its catalogue")
		check(library.save_directory().contains(library.manifest.content_id), "Save identity is missing")
		check(not identities.has(library.save_directory()), "Different bases share a save namespace")
		identities[library.save_directory()] = true
		check(not library.select_language("absent"), "Missing language accepted")
		check(library.strings.is_empty(), "Failed language change retained stale strings")
		check(not library.open("relative/path"), "Relative cache path accepted")
		check(library.manifest.is_empty(), "Failed content change retained stale manifest")
	print("Native content checks: %d profiles; %d failures" % [directories.size(), failures])
	quit(1 if failures else 0)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
