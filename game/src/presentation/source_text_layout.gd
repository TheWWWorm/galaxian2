extends RefCounted
## Independent greedy layout using source bitmap advances. This controls authored
## timing; native UI may render the resulting lines with crisp vector text.
## The caller must supply the source layout width/margin for its selected profile.
const Text = preload("res://src/content/text_definitions.gd")
const Library = preload("res://src/content/library.gd")
var binding_id := ""
var error := ""
var _advances := {}
var _width := 0
var _margin := 0
var content_id := ""
var language := ""

func configure(font: RefCounted, source_width: int, source_margin: int) -> bool:
	error = ""
	binding_id = ""
	_advances = {}
	content_id = ""
	language = ""
	if font.glyphs.is_empty() or source_width < 1 or source_width > 16384 or source_margin not in [5, 15]:
		error = "Missing font metrics or unsupported source text layout"
		return false
	# Capture metrics: reopening the font must not change an active radio layout.
	for code in font.glyphs:
		_advances[code] = font.advance(code)
	_width = source_width
	_margin = source_margin
	content_id = font.content_id
	language = font.language
	binding_id = font.binding_id
	return true

func configure_from_bindings(font: RefCounted, source_width: int, source_margin: int, bindings: RefCounted) -> bool:
	if not configure(font, source_width, source_margin): return false
	if not Library.valid_hash(font.content_id) or bindings.base_content_id != font.content_id or not Library.valid_hash(bindings.binding_id) or (not font.binding_id.is_empty() and font.binding_id != bindings.binding_id) or not Text.valid_parameters(bindings.text_aliases):
		return fail("Text aliases belong to another or unavailable content identity")
	# Apply every alias once to the original glyph metrics, including characters
	# that exist in the atlas. Source language loading substitutes unconditionally.
	for row in bindings.text_aliases.aliases:
		var source := int(row[0])
		var target := int(row[1])
		if font.glyphs.has(target): _advances[source] = font.advance(target)
		else: _advances.erase(source) # Report a missing target only when text uses this alias.
	binding_id = bindings.binding_id
	return true

func fail(message: String) -> bool:
	_advances = {}
	content_id = ""
	language = ""
	binding_id = ""
	error = message
	return false

func wrap(text: String) -> PackedStringArray:
	error = ""
	if _advances.is_empty() or text.length() > 65534:
		error = "Text layout is unconfigured or too long"
		return []
	# No fallback advances are invented. Source fonts are UTF-16/BMP maps.
	for i in text.length():
		var code := text.unicode_at(i)
		if code not in [10, 13] and not _advances.has(code):
			error = "Selected font lacks glyph U+%04X" % code
			return []
	var pending := text + "\n"
	var lines := PackedStringArray()
	var start := 0
	while start < pending.length():
		var end := start
		var last_space := -1
		var width := _margin
		while end < pending.length():
			var code := pending.unicode_at(end)
			width += int(_advances.get(code, 0))
			if code == 32: last_space = end
			end += 1
			# The source includes the threshold-crossing glyph when a word cannot
			# break at a preceding space. Equality also triggers a break.
			if width >= _width:
				if last_space > start: end = last_space + 1
				break
			if code in [10, 13]: break
		# Only ASCII spaces are trimmed by the authored layout. Line delimiters
		# remain in each result, including the final synthetic newline.
		var left := start
		var right := end
		while left < right and pending.unicode_at(left) == 32: left += 1
		while right > left and pending.unicode_at(right - 1) == 32: right -= 1
		lines.append(pending.substr(left, right - left))
		start = end
	return lines
