extends SceneTree
const Definitions = preload("res://src/content/portrait_layer_definitions.gd")
const Fixture = preload("res://tests/portrait_layer_fixture.gd")
const PortraitComposer = preload("res://src/presentation/portrait_compositor.gd")
var failures := 0

func _initialize() -> void:
	for mac in [true, false]:
		var data := Fixture.definition(mac)
		var arch := "x86_64" if mac else "armv7"
		check(Definitions.validate(data, 4096, arch).is_empty(), "Valid portrait placements rejected")
		check(Definitions.validate(JSON.parse_string(JSON.stringify(data)), 4096, arch).is_empty(), "Serialized portrait placements rejected")
		for bad in ["families", "parts", "id", "anchor", "offset", "variant", "order", "provenance", "overlap"]:
			var invalid := data.duplicate(true)
			match bad:
				"families": invalid.part_bases.pop_back()
				"parts": invalid.part_bases[0].pop_back()
				"id": invalid.part_bases[0][0] = 65535
				"anchor": invalid.variants.baseline[0][0].anchor = 64
				"offset": invalid.variants.baseline[0][0].y = 8193
				"variant": invalid.variants.erase("baseline")
				"order": invalid.draw_order = [0, 1, 2, 3]
				"provenance": invalid.provenance.baseline.offset = 4000
				"overlap": invalid.provenance.expanded.offset = invalid.provenance.baseline.offset
			check(not Definitions.validate(invalid, 4096, arch).is_empty(), "Malformed portrait placements accepted: " + bad)
		var fixed := {"status": "fixed", "family": 0, "parts": [1, 2, 3, 4]}
		var plan := Definitions.plan(data, fixed, "baseline")
		check(plan.get("layers") == [{"part": 2, "image_id": 523, "anchor": 16, "y": -2}, {"part": 1, "image_id": 512, "anchor": 32, "y": 8}, {"part": 0, "image_id": 501, "anchor": 16, "y": 3}], "Source draw order or part selection changed")
		plan.layers[0].y = 999
		check(data.variants.baseline[0][2].y == -2, "Plan mutated source definitions")
		fixed.parts[1] = -1
		check(Definitions.plan(data, fixed, "baseline").layers.size() == 2, "Absent part was invented")
		check(Definitions.plan(data, fixed, "unknown").has("error"), "Unknown size substituted")
		fixed.family = 13
		check(Definitions.plan(data, fixed, "baseline").has("error"), "Unknown family substituted")
	var compositor := PortraitComposer.new()
	var blue := solid(Vector2i(2, 3), Color(0, 0, 1, 0.5))
	var red := solid(Vector2i(2, 1), Color(1, 0, 0, 0.5))
	var result := compositor.blend([{"image": blue, "anchor": 32, "y": 1}, {"image": red, "anchor": 16, "y": -1}])
	check(not result.is_empty(), compositor.error)
	if not result.is_empty():
		check(result.bounds == Rect2i(0, -2, 2, 3), "Negative source origin or bottom anchor lost")
		var pixels: Image = result.image
		var mixed := pixels.get_pixel(0, 1)
		check(absf(mixed.r - 2.0 / 3.0) < 0.01 and absf(mixed.b - 1.0 / 3.0) < 0.01 and absf(mixed.a - 0.75) < 0.01, "Straight-alpha composition or layer order changed")
		check(pixels.get_pixel(0, 0).b == 1 and pixels.get_pixel(0, 2).r == 0, "Bottom anchoring shifted the layer")
	check(compositor.blend([]).is_empty() and not compositor.error.is_empty(), "Empty portrait invented")
	check(compositor.blend([{"image": blue, "anchor": 64, "y": 0}]).is_empty(), "Unknown alignment guessed")
	check(compositor.blend([{"image": blue, "anchor": 16, "y": -8192}, {"image": red, "anchor": 16, "y": 8192}]).is_empty(), "Oversize composition accepted")
	check(compositor.compose(null, null, null, 0, "baseline").is_empty(), "Unbound portrait accepted")
	print("Portrait placement/composition checks: %d failures" % failures)
	quit(1 if failures else 0)

func solid(size: Vector2i, color: Color) -> Image:
	var pixels := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	pixels.fill(color)
	return pixels

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
