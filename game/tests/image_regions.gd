extends SceneTree
const Definitions = preload("res://src/content/image_region_definitions.gd")
const Fixture = preload("res://tests/image_region_fixture.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Library = preload("res://src/content/library.gd")
var failures := 0

func _initialize() -> void:
	for mac in [true, false]:
		var data := Fixture.definition(mac)
		var arch := "x86_64" if mac else "armv7"
		check(Definitions.validate(data, 4096, arch).is_empty(), "Valid image aliases rejected")
		for bad in ["id", "region", "extent", "duplicate_extent", "range_count", "range_overflow", "range_region"]:
			var invalid := data.duplicate(true)
			match bad:
				"id": invalid.records[0].id = 65535
				"region": invalid.records[0].region = -1
				"extent": invalid.records[0].source_offset = 4095
				"duplicate_extent": invalid.records[1].source_offset = invalid.records[0].source_offset
				"range_count": invalid.ranges[0].count = 0
				"range_overflow": invalid.ranges[0].first_texture_id = 65534
				"range_region": invalid.ranges[0].region = 1
			check(not Definitions.validate(invalid, 4096, arch).is_empty(), "Malformed alias accepted: " + bad)
		var binding := Bindings.new()
		binding.image_regions = data
		check(binding.resolve_image_region(200).is_empty() and not binding.error.is_empty(), "Conflicting aliases silently selected")
		check(binding.resolve_image_region(200, 600) == {"texture_id": 600, "region": 3}, "Explicit alias choice failed")
		var resolved := binding.resolve_image_region(202)
		resolved.region = 99
		check(binding.resolve_image_region(202).region == 7, "Returned alias mutated source data")
		for index in 3:
			check(binding.resolve_image_region(500 + index) == {"texture_id": 900 + index, "region": 0}, "Source range index changed")
		for id in [-1, 199, 499, 503, 65535]: check(binding.resolve_image_region(id).is_empty() and not binding.error.is_empty(), "Unknown alias guessed")
		check(binding.resolve_image_region(200, 777).is_empty(), "Unknown texture selector substituted")
		var repeated: Dictionary = data.records[0].duplicate(true)
		repeated.source_offset = 1500
		data.records.append(repeated)
		check(binding.resolve_image_region(200, 600).region == 3, "Identical repeated declarations became ambiguous")
		binding.open("/missing-image-fixture", {})
		check(binding.image_regions.is_empty(), "Failed load retained image aliases")
	var args := OS.get_cmdline_user_args()
	for i in range(0, args.size() - 1, 2):
		var library := Library.new()
		var binding := Bindings.new()
		check(library.open(args[i]) and binding.open(args[i + 1], library.manifest), "Actual image alias bindings failed: " + binding.error)
		var ios: bool = library.manifest.profile.edition == "ios-hd"
		check(binding.image_regions.get("records", []).size() == (281 if ios else 203), "Actual record count changed")
		for row in binding.image_regions.get("records", []):
			var candidates := Definitions.candidates(binding.image_regions, int(row.id))
			check(candidates.has({"texture_id": int(row.texture_id), "region": int(row.region)}), "Imported alias lost from native alternatives")
		for index in 152:
			check(binding.resolve_image_region(5000 + index) == {"texture_id": 10200 + index, "region": 0}, "Actual portrait alias range failed")
		check(binding.resolve_image_region(1157, 10063).region == 104 and binding.resolve_image_region(1297, 10063).region == 42, "Atlas-2 frame aliases changed")
		if ios:
			check(binding.resolve_image_region(1157).is_empty() and binding.resolve_image_region(1297).is_empty(), "iOS alternatives silently selected")
			check(binding.resolve_image_region(1157, 10062).region == 56 and binding.resolve_image_region(1297, 10062).region == 196, "iOS atlas-1 frame aliases changed")
	print("Image region checks: %d failures" % failures)
	quit(1 if failures else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
