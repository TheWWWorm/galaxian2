extends SceneTree
const AEM = preload("res://src/content/aem.gd")
const Tracks = preload("res://src/content/animation_tracks.gd")
const Visuals = preload("res://src/content/visual_library.gd")
var failures := 0

func _initialize() -> void:
	var fixture := mesh_fixture()
	var reader := AEM.new()
	var result := reader.decode(fixture)
	check(not result.is_empty(), "Synthetic V4 mesh rejected: " + reader.error)
	if not result.is_empty():
		check(result.vertices == 3 and result.keyframes == 2, "Geometry/key count mismatch")
		check(result.surfaces[0].positions[1] == Vector3(1, 0, 0), "Source coordinates changed")
		check(result.surfaces[0].uvs[2] == Vector2(0, 1), "Source UV coordinates changed")
		check(Tracks.vector(result.surfaces[0].tracks.translation, 5, Vector3.ZERO) == Vector3(5, 10, 15), "Linear keyframe interpolation failed")
		check(Tracks.vector(result.surfaces[0].tracks.translation, -5, Vector3.ZERO) == Vector3.ZERO, "Before-first clamp failed")
		check(Tracks.vector(result.surfaces[0].tracks.translation, 25, Vector3.ZERO) == Vector3(10, 20, 30), "After-last clamp failed")
	for end in fixture.size():
		check(reader.decode(fixture.slice(0, end)).is_empty(), "Truncated AEM accepted at %d" % end)
	var broken := fixture.duplicate()
	broken.encode_u16(26, 3)
	check(reader.decode(broken).is_empty(), "Out-of-range vertex index accepted")
	broken = fixture.duplicate()
	broken.encode_float(34, NAN)
	check(reader.decode(broken).is_empty(), "NaN position accepted")
	broken = fixture.duplicate()
	broken.append(0)
	check(reader.decode(broken).is_empty(), "Unexpected mesh trailer accepted")
	var duplicate := {"dimensions": 1, "keys": PackedFloat32Array([0, 1, 0, 2, 10, 4])}
	check(Tracks.sample(duplicate, 0, PackedFloat32Array([0]))[0] == 2, "Equal-time keys should use the final authored value")
	var negative := {"dimensions": 1, "keys": PackedFloat32Array([-10, 0, 0, 10])}
	check(Tracks.sample(negative, -5, PackedFloat32Array([0]))[0] == 5, "Negative source time lost")
	var texture := texture_fixture()
	var visuals := Visuals.new()
	var image := visuals.decode_image(texture)
	check(image != null and image.get_pixel(0, 0).is_equal_approx(Color(1, 0, 0, 1)), "Native RGBA texture decoding failed")
	broken = texture.duplicate()
	broken.encode_u32(20, 0x7fffffff)
	check(visuals.decode_image(broken) == null, "Unbounded texture output size accepted")
	broken = texture.duplicate()
	broken.encode_u32(16, 2)
	check(visuals.decode_image(broken) == null, "Missing mip payload accepted")
	print("Asset reader/sampler checks: %d failures" % failures)
	quit(1 if failures else 0)

func mesh_fixture() -> PackedByteArray:
	var stream := StreamPeerBuffer.new()
	stream.big_endian = false
	stream.put_data("V4AEMesh".to_ascii_buffer())
	stream.put_u8(0)
	stream.put_u8(7)
	stream.put_u16(1)
	floats(stream, [0, 0, 0])
	stream.put_u16(3)
	for i in 3: stream.put_u16(i)
	stream.put_u16(3)
	floats(stream, [0, 0, 0, 1, 0, 0, 0, 1, 0])
	floats(stream, [0, 0, 1, 0, 0, 1])
	floats(stream, [0, 0, 1, 0, 0, 1, 0, 0, 1])
	floats(stream, [0, 0, 0, 2])
	stream.put_u16(1)
	stream.put_u16(2)
	floats(stream, [0, 0, 0, 0, 10, 10, 20, 30])
	stream.put_u16(0)
	for i in 3: stream.put_u16(0)
	stream.put_u16(1)
	stream.put_u16(0)
	stream.put_u16(65535)
	stream.put_u16(0)
	return stream.data_array

func texture_fixture() -> PackedByteArray:
	var result := "G2TX".to_ascii_buffer()
	result.resize(24)
	for item in [[4, 1], [8, 1], [12, 1], [16, 1], [20, 4]]:
		result.encode_u32(item[0], item[1])
	result.append_array(PackedByteArray([255, 0, 0, 255]).compress(FileAccess.COMPRESSION_DEFLATE))
	return result

func floats(stream: StreamPeerBuffer, values: Array) -> void:
	for value in values: stream.put_float(float(value))

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
