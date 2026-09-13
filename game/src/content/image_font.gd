extends RefCounted
## Original AEI bitmap metrics, read from checksum-verified base resources.
## Pixels are skipped, not decoded. Compressed/cube font envelopes are unsupported.
const Library = preload("res://src/content/library.gd")
const MAX_BYTES := 192 * 1024 * 1024
var error := ""
var content_id := ""
var binding_id := ""
var font_id := -1
var source_mode := -1
var resource := ""
var language := ""
var glyphs := {}
var spacing := 0

func clear() -> void:
	error = ""
	content_id = ""
	binding_id = ""
	font_id = -1
	source_mode = -1
	resource = ""
	language = ""
	glyphs = {}
	spacing = 0

func open(library: RefCounted, source_resource: String, font_index: int, signed_spacing: int) -> bool:
	clear()
	var identity: String = library.manifest.get("content_id", "")
	if not Library.valid_hash(identity) or font_index < 0 or abs(signed_spacing) > 32: return fail("Invalid bitmap font context")
	var bytes: PackedByteArray = library.read_resource(source_resource, MAX_BYTES)
	if bytes.is_empty(): return fail(library.error)
	var fonts := parse(bytes)
	if not error.is_empty(): return false
	if font_index >= fonts.size(): return fail("The selected AEI has no such font group")
	glyphs = fonts[font_index]
	spacing = signed_spacing
	content_id = identity
	resource = source_resource
	language = library.active_language
	return true

func open_selected(library: RefCounted, bindings: RefCounted, mode := 0, role := "main") -> bool:
	clear()
	if bindings.base_content_id != library.manifest.get("content_id", "") or not Library.valid_hash(bindings.binding_id) or library.active_language.is_empty(): return fail("Select a font from the active content and language")
	var choice: Dictionary = bindings.resolve_font(library.active_language, mode, role)
	if choice.is_empty(): return fail(bindings.error)
	if not open(library, choice.resource, choice.font_group, choice.spacing): return false
	binding_id = bindings.binding_id
	font_id = choice.font_id
	source_mode = mode
	return true


func parse(bytes: PackedByteArray) -> Array:
	error = ""
	if bytes.size() < 17 or bytes.size() > MAX_BYTES or bytes.slice(0, 8) != PackedByteArray([65, 69, 105, 109, 97, 103, 101, 0]):
		return invalid("Invalid bitmap font AEI envelope")
	if bytes[8] not in [1, 3]: return invalid("This AEI font pixel layout is unsupported")
	var width := bytes.decode_u16(9)
	var height := bytes.decode_u16(11)
	if width < 1 or height < 1 or width > 8192 or height > 8192 or width * height > 32 * 1024 * 1024:
		return invalid("Invalid bitmap font image dimensions")
	var regions := bytes.decode_u16(13)
	var offset := 15 + regions * 8
	if offset > bytes.size(): return invalid("Truncated bitmap font atlas")
	for i in regions:
		if not valid_rect(bytes, 15 + i * 8, width, height, true): return invalid("Invalid bitmap font atlas region")
	offset += width * height * 4
	if offset + 2 > bytes.size(): return invalid("Truncated bitmap font pixels")
	var count := bytes.decode_u16(offset)
	offset += 2
	if count > 32: return invalid("Too many bitmap font groups")
	var fonts := []
	for group in count:
		if offset + 2 > bytes.size(): return invalid("Missing bitmap font group")
		var glyph_count := bytes.decode_u16(offset)
		offset += 2
		if glyph_count == 0 or offset + glyph_count * 10 > bytes.size(): return invalid("Truncated bitmap font glyphs")
		var font := {}
		for i in glyph_count:
			var code := bytes.decode_u16(offset + i * 2)
			var rect_at := offset + glyph_count * 2 + i * 8
			if font.has(code) or not valid_rect(bytes, rect_at, width, height, false): return invalid("Duplicate or invalid bitmap glyph")
			font[code] = Rect2i(bytes.decode_u16(rect_at), bytes.decode_u16(rect_at + 2), bytes.decode_u16(rect_at + 4), bytes.decode_u16(rect_at + 6))
		fonts.append(font)
		offset += glyph_count * 10
	if offset != bytes.size(): return invalid("Unrecognized bitmap font trailer")
	return fonts

static func valid_rect(bytes: PackedByteArray, at: int, width: int, height: int, empty: bool) -> bool:
	var x := bytes.decode_u16(at)
	var y := bytes.decode_u16(at + 2)
	var w := bytes.decode_u16(at + 4)
	var h := bytes.decode_u16(at + 6)
	return x + w <= width and y + h <= height and (empty or (w > 0 and h > 0))

func advance(code: int) -> int:
	if code in [10, 13]: return 0
	if not glyphs.has(code): return 0
	var width: int = glyphs[code].size.x
	# Source metric exception for an 11-pixel space, verified in both editions.
	return width + spacing - (2 if code == 32 and width == 11 else 0)

func invalid(message: String) -> Array:
	error = message
	return []

func fail(message: String) -> bool:
	error = message
	return false
