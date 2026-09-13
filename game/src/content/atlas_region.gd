extends RefCounted
## Crops original atlas regions using checksum-verified source metadata and
## decoded pixels from the same base. No filename or region-index inference.
const Library = preload("res://src/content/library.gd")
const MAX_BYTES := 192 * 1024 * 1024
var error := ""

func load(library: RefCounted, visuals: RefCounted, resource: String, index: int) -> AtlasTexture:
	error = ""
	if library == null or visuals == null or not Library.valid_hash(library.manifest.get("content_id", "")) or visuals.base_content_id != library.manifest.content_id:
		return invalid("Atlas pixels and metadata must belong to the active content base")
	if library.manifest.get("files", {}).get(resource, {}).get("kind") != "texture": return invalid("Atlas resource is not a source texture")
	var bytes: PackedByteArray = library.read_resource(resource, MAX_BYTES)
	if bytes.is_empty(): return invalid(library.error)
	var metadata := region(bytes, index)
	if metadata.is_empty(): return null
	var pixels: Image = visuals.load_image(resource)
	if pixels == null: return invalid(visuals.error)
	if pixels.get_size() != metadata.size: return invalid("Atlas pixels differ from the source image dimensions")
	var result := AtlasTexture.new()
	result.atlas = ImageTexture.create_from_image(pixels)
	result.region = Rect2(metadata.rect)
	result.filter_clip = true
	return result

func region(bytes: PackedByteArray, index: int) -> Dictionary:
	error = ""
	if bytes.size() < 17 or bytes.size() > MAX_BYTES or bytes.slice(0, 8) != PackedByteArray([65, 69, 105, 109, 97, 103, 101, 0]):
		error = "Invalid atlas envelope"
		return {}
	if bytes[8] not in [1, 3, 13, 16, 18, 32, 34, 36, 38]:
		error = "Unsupported or cube atlas layout"
		return {}
	var width := bytes.decode_u16(9)
	var height := bytes.decode_u16(11)
	var count := bytes.decode_u16(13)
	if width < 1 or height < 1 or width > 8192 or height > 8192 or width * height > 32 * 1024 * 1024 or index < 0 or index >= count or 15 + count * 8 >= bytes.size():
		error = "Missing or invalid source atlas region"
		return {}
	var at := 15 + index * 8
	var rect := Rect2i(bytes.decode_u16(at), bytes.decode_u16(at + 2), bytes.decode_u16(at + 4), bytes.decode_u16(at + 6))
	if rect.size.x < 1 or rect.size.y < 1 or rect.end.x > width or rect.end.y > height:
		error = "Source atlas region is empty or outside its image"
		return {}
	return {"size": Vector2i(width, height), "rect": rect}

func invalid(message: String) -> AtlasTexture:
	error = message
	return null
