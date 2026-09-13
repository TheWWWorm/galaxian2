extends SceneTree
const Region = preload("res://src/content/atlas_region.gd")
var failures := 0

class Source extends RefCounted:
	var error := ""
	var bytes := PackedByteArray()
	var manifest := {"content_id": "a".repeat(64), "files": {"synthetic": {"kind": "texture"}}}
	func read_resource(_resource: String, _maximum: int) -> PackedByteArray: return bytes

class Pixels extends RefCounted:
	var error := ""
	var base_content_id := "a".repeat(64)
	var image: Image
	func load_image(_resource: String) -> Image: return image

func _initialize() -> void:
	var source := Source.new()
	var pixels := Pixels.new()
	var bytes := PackedByteArray()
	bytes.resize(23 + 8 * 8 * 4 + 2)
	var magic := PackedByteArray([65, 69, 105, 109, 97, 103, 101, 0])
	for i in 8: bytes[i] = magic[i]
	bytes[8] = 1
	bytes.encode_u16(9, 8)
	bytes.encode_u16(11, 8)
	bytes.encode_u16(13, 1)
	bytes.encode_u16(15, 2)
	bytes.encode_u16(17, 1)
	bytes.encode_u16(19, 3)
	bytes.encode_u16(21, 4)
	source.bytes = bytes
	pixels.image = Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	pixels.image.fill(Color.TRANSPARENT)
	pixels.image.fill_rect(Rect2i(2, 1, 3, 4), Color(0.2, 0.4, 0.6, 0.5))
	var loader := Region.new()
	var texture := loader.load(source, pixels, "synthetic", 0)
	check(texture != null and texture.get_size() == Vector2(3, 4) and texture.filter_clip, "Source region dimensions lost")
	if texture != null:
		var crop: Image = texture.get_image()
		check(crop.get_size() == Vector2i(3, 4) and crop.get_data() == pixels.image.get_region(Rect2i(2, 1, 3, 4)).get_data(), "Atlas crop changed original pixels or alpha")
	for bad in ["magic", "cube", "bounds", "empty", "truncated", "index", "identity", "pixels"]:
		source.bytes = bytes.duplicate()
		pixels.base_content_id = source.manifest.content_id
		pixels.image = Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
		var index := 0
		match bad:
			"magic": source.bytes[0] = 0
			"cube": source.bytes[8] = 129
			"bounds": source.bytes.encode_u16(19, 8)
			"empty": source.bytes.encode_u16(21, 0)
			"truncated": source.bytes.resize(22)
			"index": index = 1
			"identity": pixels.base_content_id = "b".repeat(64)
			"pixels": pixels.image = Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
		check(loader.load(source, pixels, "synthetic", index) == null and not loader.error.is_empty(), "Invalid crop accepted: " + bad)
	print("Atlas region checks: %d failures" % failures)
	quit(1 if failures else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
