extends SceneTree
const FontMetrics = preload("res://src/content/image_font.gd")
const Layout = preload("res://src/presentation/source_text_layout.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Radio = preload("res://src/simulation/radio_sequence.gd")
var failures := 0

func _initialize() -> void:
	var font := FontMetrics.new()
	var bytes := font_fixture()
	var groups := font.parse(bytes)
	check(font.error.is_empty() and groups.size() == 1, "Synthetic AEI font rejected")
	if groups.size() == 1:
		check(groups[0][65] == Rect2i(0, 0, 6, 8) and groups[0][32].size.x == 11, "Font rectangles changed")
	for length in bytes.size():
		check(font.parse(bytes.slice(0, length)).is_empty() and not font.error.is_empty(), "Truncation accepted at %d" % length)
	for mutation in ["duplicate", "bounds", "empty", "compressed", "trailer", "font_count"]:
		var bad := bytes.duplicate()
		match mutation:
			"duplicate": bad.encode_u16(2071, 65)
			"bounds": bad.encode_u16(2077, 33)
			"empty": bad.encode_u16(2081, 0)
			"compressed": bad[8] = 18
			"trailer": bad.append(0)
			"font_count": bad.encode_u16(2063, 33)
		check(font.parse(bad).is_empty() and not font.error.is_empty(), "Invalid font accepted: " + mutation)
	font.glyphs = groups[0]
	font.spacing = -1
	check(font.advance(32) == 8 and font.advance(65) == 5 and font.advance(10) == 0, "Source spacing/space exception changed")
	font.glyphs[32] = Rect2i(0, 0, 3, 8)
	font.content_id = "a".repeat(64)
	font.language = "gb"
	var layout := Layout.new()
	check(layout.configure(font, 15, 5), layout.error)
	check(layout.wrap("AA") == PackedStringArray(["AA", "\n"]), "Exact width must wrap")
	check(layout.wrap("AAA") == PackedStringArray(["AA", "A\n"]), "Long-word overflow changed")
	check(layout.wrap("A A") == PackedStringArray(["A", "A\n"]), "Space break changed")
	check(layout.wrap("A  B") == PackedStringArray(["A", "B\n"]), "Repeated spaces changed")
	check(layout.wrap(" A") == PackedStringArray(["A\n"]), "Leading space trim changed")
	check(layout.wrap("A\r\nB") == PackedStringArray(["A\r", "\n", "B\n"]), "CR/LF boundaries changed")
	check(layout.wrap("") == PackedStringArray(["\n"]), "Empty source string must retain terminator")
	check(layout.wrap("A😀").is_empty() and not layout.error.is_empty(), "Missing non-BMP glyph silently accepted")
	check(layout.wrap("A".repeat(65535)).is_empty() and not layout.error.is_empty(), "Oversized layout accepted")
	check(layout.configure(font, 16, 5) and layout.wrap("AA") == PackedStringArray(["AA\n"]), "Below-width boundary changed")
	check(layout.configure(font, 25, 15) and layout.wrap("国国") == PackedStringArray(["国国", "\n"]), "CJK margin changed")
	var alias_bindings := Bindings.new()
	alias_bindings.base_content_id = font.content_id
	alias_bindings.binding_id = "d".repeat(64)
	var aliases := [[65, 66], [1072, 65]]
	for i in 18: aliases.append([512 + i, 65])
	alias_bindings.text_aliases = {"aliases": aliases}
	font.glyphs[66] = Rect2i(0, 0, 8, 8)
	check(layout.configure_from_bindings(font, 12, 5, alias_bindings), layout.error)
	check(layout.wrap("A") == PackedStringArray(["A", "\n"]), "Source alias must override even an existing glyph")
	check(layout.wrap("а") == PackedStringArray(["а\n"]), "Aliases must apply once without changing Unicode text")
	alias_bindings.text_aliases.aliases[0][1] = 0x9999
	check(layout.wrap("A") == PackedStringArray(["A", "\n"]), "Mutable alias source changed configured metrics")
	check(layout.configure_from_bindings(font, 12, 5, alias_bindings) and layout.wrap("A").is_empty() and not layout.error.is_empty(), "Missing alias target accepted by wrapping")
	check(layout.wrap("B") == PackedStringArray(["B", "\n"]), "Unused missing aliases rejected supported text")
	alias_bindings.text_aliases.aliases[0][1] = 66
	alias_bindings.base_content_id = "f".repeat(64)
	check(not layout.configure_from_bindings(font, 12, 5, alias_bindings) and layout.binding_id.is_empty(), "Cross-content aliases accepted")
	check(layout.configure(font, 15, 5), layout.error)
	font.clear()
	check(layout.wrap("AA") == PackedStringArray(["AA", "\n"]) and layout.content_id == "a".repeat(64), "Layout retained mutable font metrics")
	var library := Library.new()
	library.manifest = {"content_id": "a".repeat(64)}
	library.active_language = "gb"
	library.strings = ["AA"]
	var bindings := Bindings.new()
	bindings.base_content_id = library.manifest.content_id
	bindings.binding_id = "b".repeat(64)
	var events := []
	for i in 23: events.append({"text_id": 0, "speaker_id": 0, "condition": 5, "values": [0]})
	bindings.opening_dialogue = {"campaign_cursor": 0, "events": events, "timing": {"display_delay_ms": 2000, "base_duration_ms": 1500, "per_line_ms": 2000}}
	var radio := Radio.new()
	check(radio.configure_from_layout(bindings, library, layout), radio.error)
	radio.step(0, {}, 0)
	radio.step(7500, {}, 0)
	check(not radio.snapshot().finished[0], "Two-line timing finished at strict boundary")
	radio.step(7501, {}, 0)
	check(radio.snapshot().finished[0], "Derived two-line timing did not finish")
	library.active_language = "de"
	check(not radio.configure_from_layout(bindings, library, layout) and radio.snapshot().is_empty(), "Cross-language radio layout accepted")
	library.active_language = "gb"
	library.strings = ["?"]
	check(not radio.configure_from_layout(bindings, library, layout) and radio.snapshot().is_empty(), "Missing glyph configured radio")
	check(not layout.configure(font, 15, 5) and layout.wrap("AA").is_empty() and layout.content_id.is_empty(), "Failed layout retained state")
	check(not font.open(library, "resources/missing.aei", 0, -2) and font.glyphs.is_empty() and font.content_id.is_empty(), "Failed font retained state")
	print("Source font/layout checks: %d failures" % failures)
	quit(1 if failures else 0)

func font_fixture() -> PackedByteArray:
	var bytes := PackedByteArray([65, 69, 105, 109, 97, 103, 101, 0])
	bytes.resize(15 + 32 * 16 * 4 + 4 + 4 * 10)
	bytes[8] = 1
	bytes.encode_u16(9, 32)
	bytes.encode_u16(11, 16)
	bytes.encode_u16(2063, 1)
	bytes.encode_u16(2065, 4)
	var codes := [65, 66, 32, 22269]
	for i in 4:
		bytes.encode_u16(2067 + 2 * i, codes[i])
		bytes.encode_u16(2075 + 8 * i + 4, 11 if i == 2 else 6)
		bytes.encode_u16(2075 + 8 * i + 6, 8)
	return bytes

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
