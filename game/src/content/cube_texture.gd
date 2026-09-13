extends RefCounted
## Original raw AEI cube data, independently assembled into a native Cubemap.
## Both supported renderers upload strip faces as +Y,-X,+Z,+X,-Z,-Y.
## Keep pixel rows unchanged; the retained atlas cross does not control upload.
const Library = preload("res://src/content/library.gd")
const MAX_BYTES := 192 * 1024 * 1024
const MAX_PIXELS := 32 * 1024 * 1024
const NATIVE_FACE_ROWS := [3, 1, 0, 5, 2, 4] # +X,-X,+Y,-Y,+Z,-Z
var error := ""

func load(library: RefCounted, resource: String) -> Cubemap:
	error = ""
	if library == null or not Library.valid_hash(library.manifest.get("content_id")):
		return invalid("Cubemap requires an active content base")
	if library.manifest.get("files", {}).get(resource, {}).get("kind") != "texture":
		return invalid("Cubemap resource is not a source texture")
	var bytes: PackedByteArray = library.read_resource(resource, MAX_BYTES)
	if bytes.is_empty(): return invalid(library.error)
	return create(bytes)

func create(bytes: PackedByteArray) -> Cubemap:
	var faces := decode_faces(bytes)
	if faces.is_empty(): return null
	var result := Cubemap.new()
	if result.create_from_images(faces) != OK: return invalid("Native cubemap upload failed")
	return result

func decode_faces(bytes: PackedByteArray) -> Array[Image]:
	error = ""
	if bytes.size()<17 or bytes.size()>MAX_BYTES or bytes.slice(0,8)!=PackedByteArray([65,69,105,109,97,103,101,0]):
		return invalid_faces("Invalid source cubemap envelope")
	# The supplied Mac low Supernova 0xa6 strips are preserved by the importer,
	# but the verified source upload reader accepts only 0x81 as a raw cube.
	if bytes[8]!=129: return invalid_faces("Unsupported source cubemap format; verified raw cubes use 0x81")
	var width := bytes.decode_u16(9)
	var height := bytes.decode_u16(11)
	if width<1 or height!=width*6 or height>8192 or width*height>MAX_PIXELS:
		return invalid_faces("Cubemap must contain six bounded square faces")
	var count := bytes.decode_u16(13)
	var start := 15+count*8
	var face_bytes := width*width*4
	var end := start+face_bytes*6
	if end+2!=bytes.size(): return invalid_faces("Incomplete or unsupported cubemap payload/trailer")
	if bytes.decode_u16(end)!=0: return invalid_faces("Cubemap font metadata is unsupported")
	for index in count:
		var at := 15+index*8
		if bytes.decode_u16(at)+bytes.decode_u16(at+4)>width*4 or bytes.decode_u16(at+2)+bytes.decode_u16(at+6)>width*3:
			return invalid_faces("Cubemap atlas cross is out of bounds")
	var faces: Array[Image] = []
	for row in NATIVE_FACE_ROWS:
		var at: int = start+row*face_bytes
		faces.append(Image.create_from_data(width,width,false,Image.FORMAT_RGBA8,bytes.slice(at,at+face_bytes)))
	return faces

func invalid_faces(message: String) -> Array[Image]:
	error = message
	return []

func invalid(message: String) -> Cubemap:
	error = message
	return null
