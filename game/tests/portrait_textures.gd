extends SceneTree
const Definitions = preload("res://src/content/portrait_texture_definitions.gd")
const Fixture = preload("res://tests/portrait_fixture.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Library = preload("res://src/content/library.gd")
var failures := 0

func _initialize() -> void:
	for mac in [true, false]:
		var data := Fixture.definition(mac)
		var arch := "x86_64" if mac else "armv7"
		check(Definitions.validate(data, 65536, arch).is_empty(), "Synthetic declarations rejected")
		var binding := Bindings.new()
		binding.portrait_textures = data
		for key in Definitions.VARIANTS:
			var path: String = data.rows[0].variants[key]
			binding.base_files[path] = {"kind": "texture"}
			check(binding.resolve_portrait_texture(600, key) == path, "Explicit portrait variant did not resolve")
		check(binding.resolve_portrait_texture(601).is_empty() and not binding.error.is_empty(), "Absent portrait silently substituted")
		check(binding.resolve_portrait_texture(999).is_empty() and binding.resolve_portrait_texture(600, "unknown").is_empty(), "Unknown portrait ID/variant guessed")
		for bad in ["count", "duplicate", "stem", "suffix", "variant", "extent", "overlap", "provenance"]:
			var invalid := data.duplicate(true)
			match bad:
				"count": invalid.rows.pop_back()
				"duplicate": invalid.rows[1].id = invalid.rows[0].id
				"stem": invalid.rows[0].stem = "data/../escape"
				"suffix": invalid.suffixes.expanded.value = "../escape"
				"variant": invalid.rows[0].variants.baseline = invalid.rows[0].variants.large
				"extent": invalid.rows[0].source_offset = 65535
				"overlap": invalid.rows[1].source_offset = invalid.rows[0].source_offset
				"provenance": invalid.provenance.selection.bytes = 1
			check(not Definitions.validate(invalid, 65536, arch).is_empty(), "Bad portrait scope accepted: " + bad)
	var args := OS.get_cmdline_user_args()
	for i in range(0, args.size() - 1, 2):
		var library := Library.new()
		var binding := Bindings.new()
		check(library.open(args[i]) and binding.open(args[i + 1], library.manifest), "Real portrait bindings did not load: " + binding.error)
		check(binding.portrait_textures.get("rows", []).size() == 152, "Real texture declaration count")
		var found := 0
		var missing := 0
		for row in binding.portrait_textures.get("rows", []):
			for variant in Definitions.VARIANTS:
				var path: String = row.variants[variant]
				var resolved := binding.resolve_portrait_texture(int(row.id), variant)
				if library.manifest.files.has(path):
					check(resolved == path, "Source-present variant rejected")
					found += 1
				else:
					check(resolved.is_empty() and not binding.error.is_empty(), "Missing source variant fabricated")
					missing += 1
		print(library.manifest.profile.edition, ": ", found, " source-present portrait paths; ", missing, " absent variants reported")
	print("Portrait texture checks: %d failures" % failures)
	quit(1 if failures else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
