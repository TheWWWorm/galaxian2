extends RefCounted
## Lazy loading of validated, base-bound texture derivatives.
const MAX_BYTES := 192 * 1024 * 1024
const MAX_PIXELS := 32 * 1024 * 1024
var error := ""
var root := ""
var base_content_id := ""
var textures := {}

func open(directory: String, base_manifest: Dictionary) -> bool:
	error = ""
	root = ""
	base_content_id = ""
	textures = {}
	var file := FileAccess.open(directory.path_join("visuals.json"), FileAccess.READ)
	if file == null or file.get_length() > 16 * 1024 * 1024:
		return fail("Missing or oversized visual manifest")
	var value: Variant = JSON.parse_string(file.get_as_text())
	if not value is Dictionary or value.get("schema") != 1:
		return fail("Unsupported visual schema")
	if not value.get("recipe") is Dictionary or not value.get("textures") is Dictionary:
		return fail("Incomplete visual manifest")
	if value.recipe.get("base_content_id") != base_manifest.get("content_id"):
		return fail("These textures belong to a different base content identity")
	for name in value.textures:
		var row: Variant = value.textures[name]
		if not row is Dictionary or not base_manifest.files.has(name):
			return fail("Unknown source texture")
		if row.get("source_sha256") != base_manifest.files[name].get("sha256"):
			return fail("Source texture provenance mismatch")
		var expected: String = "textures/" + str(name).sha256_text() + ".g2tx"
		if row.get("path") != expected:
			return fail("Invalid normalized texture path")
		if not row.get("bytes") is float and not row.get("bytes") is int:
			return fail("Invalid normalized texture size")
		if row.bytes < 24 or row.bytes > MAX_BYTES:
			return fail("Oversized normalized texture")
	root = directory
	base_content_id = value.recipe.base_content_id
	textures = value.textures
	return true

func load_image(name: String) -> Image:
	error = ""
	if not textures.has(name):
		fail("This texture has not been prepared")
		return null
	var row: Dictionary = textures[name]
	var file := FileAccess.open(root.path_join(row.path), FileAccess.READ)
	if file == null or file.get_length() != int(row.bytes):
		fail("Texture derivative is missing or changed")
		return null
	var data := file.get_buffer(int(row.bytes))
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(data)
	if hash.finish().hex_encode() != row.get("sha256"):
		fail("Texture derivative checksum mismatch")
		return null
	return decode_image(data)

func decode_image(data: PackedByteArray) -> Image:
	error = ""
	if data.size() < 24 or data.size() > MAX_BYTES or data.slice(0, 4).get_string_from_ascii() != "G2TX":
		fail("Invalid native texture envelope")
		return null
	var version := data.decode_u32(4)
	var width := data.decode_u32(8)
	var height := data.decode_u32(12)
	var levels := data.decode_u32(16)
	var expected := data.decode_u32(20)
	if version != 1 or width < 1 or height < 1 or width > 8192 or height > 8192 or width * height > MAX_PIXELS:
		fail("Unsupported native texture dimensions")
		return null
	if levels < 1 or levels > 14:
		fail("Invalid native mip level count")
		return null
	var size := 0
	var w := width
	var h := height
	for i in levels:
		size += w * h * 4
		if i + 1 < levels and w == 1 and h == 1:
			fail("Too many native mip levels")
			return null
		if i + 1 < levels:
			w = maxi(1, w / 2)
			h = maxi(1, h / 2)
	if size != expected or size > MAX_BYTES or (levels > 1 and (w != 1 or h != 1)):
		fail("Invalid native mip payload extent")
		return null
	var pixels := data.slice(24).decompress(size, FileAccess.COMPRESSION_DEFLATE)
	if pixels.size() != size:
		fail("Native texture decompression failed")
		return null
	return Image.create_from_data(width, height, levels > 1, Image.FORMAT_RGBA8, pixels)

func fail(message: String) -> bool:
	error = message
	return false
