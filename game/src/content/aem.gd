extends RefCounted
## Independently implemented AEM data reader; values retain source coordinates/times.
const Cursor = preload("res://src/content/binary_cursor.gd")
const MAX_BYTES := 128 * 1024 * 1024
const MAX_SUBMESHES := 1024
const MAX_VERTICES := 4 * 1024 * 1024
const MAX_KEYS := 200000
var error := ""
var cursor: RefCounted
var total_vertices := 0
var total_keys := 0

func decode(data: PackedByteArray) -> Dictionary:
	error = ""
	total_vertices = 0
	total_keys = 0
	if data.size() < 12 or data.size() > MAX_BYTES:
		return fail("Empty, truncated or oversized AEM")
	cursor = Cursor.new(data)
	var signature: String = cursor.bytes(9).get_string_from_ascii()
	if signature not in ["V2AEMesh", "V3AEMesh", "V4AEMesh", "V5AEMesh"] or data[8] != 0:
		return fail("Unsupported AEM signature")
	var version := int(signature.substr(1, 1))
	var flags: int = cursor.u8()
	if flags & 1 == 0 or flags & ~31 != 0:
		return fail("Unsupported AEM flags")
	var count: int = cursor.u16() if version >= 3 else 1
	if count < 1 or count > MAX_SUBMESHES:
		return fail("Invalid AEM submesh count")
	var surfaces: Array = []
	for index in count:
		var surface := read_surface(version, flags)
		if not cursor.error.is_empty():
			return fail("Submesh %d: %s" % [index, cursor.error])
		surfaces.append(surface)
	var legacy_marker := -1
	if version == 2 and cursor.remaining() == 1:
		legacy_marker = cursor.u8()
		if legacy_marker not in [0, 1]:
			return fail("Unsupported V2 trailer")
	if cursor.remaining() != 0:
		return fail("Unrecognized AEM trailing bytes: %d" % cursor.remaining())
	return {"version": version, "flags": flags, "surfaces": surfaces,
		"vertices": total_vertices, "keyframes": total_keys, "legacy_marker": legacy_marker,
		"coordinate_space": "source", "time_units": "source_unverified"}

func read_surface(version: int, flags: int) -> Dictionary:
	var pivot := vector3() if version >= 3 else Vector3.ZERO
	var index_count: int = cursor.u16()
	if index_count % 3 != 0 or index_count == 0:
		cursor.reject("Empty or non-triangular index buffer")
		return {}
	var indices := PackedInt32Array()
	if not cursor.available(index_count * 2):
		return {}
	indices.resize(index_count)
	for i in index_count:
		indices[i] = cursor.u16()
	var vertex_count: int = cursor.u16()
	total_vertices += vertex_count
	if vertex_count < 1 or total_vertices > MAX_VERTICES:
		cursor.reject("Invalid vertex count or mesh budget exceeded")
		return {}
	for vertex in indices:
		if vertex >= vertex_count:
			cursor.reject("Vertex index outside the vertex buffer")
			return {}
	var positions: PackedVector3Array = vectors(vertex_count, 3, version >= 4, 1.0, true)
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var legacy_attributes := PackedByteArray()
	if flags & 2:
		uvs = vectors(vertex_count, 2, version >= 4, 1.0 if version >= 4 else 1.0 / 4096.0)
	if flags & 4:
		normals = vectors(vertex_count, 3, version >= 4, 1.0 if version >= 4 else 1.0 / 32768.0)
	if flags & 8:
		if version < 4:
			# Extent is known; retain packed data without inventing its color semantics.
			legacy_attributes = cursor.bytes(vertex_count * 4)
		else:
			var values: PackedFloat32Array = cursor.floats(vertex_count * 4)
			if not cursor.error.is_empty():
				return {}
			colors.resize(vertex_count)
			for i in vertex_count:
				colors[i] = Color(values[i * 4], values[i * 4 + 1], values[i * 4 + 2], values[i * 4 + 3])
	var sphere := Vector4.ZERO
	var tracks := {}
	if version >= 3:
		var values: PackedFloat32Array = cursor.floats(4)
		if not cursor.error.is_empty():
			return {}
		sphere = Vector4(values[0], values[1], values[2], values[3])
		if sphere.w < 0:
			cursor.reject("Negative bounding sphere radius")
		for group in ["translation", "rotation", "scale"]:
			tracks[group] = group_tracks(3)
		if version >= 4:
			var mode: int = cursor.u16()
			if mode == 2:
				tracks["scalar"] = [read_track(1)]
			elif mode not in [0, 65535]:
				cursor.reject("Unsupported scalar animation mode")
		if version >= 5:
			var enabled: int = cursor.u16()
			if enabled not in [0, 1]:
				cursor.reject("Unsupported UV animation mode")
			elif enabled == 1:
				var uv_tracks: Array = []
				for i in 7:
					uv_tracks.append(read_track(1))
				tracks["uv"] = uv_tracks
		if cursor.u16() != 0:
			cursor.reject("Unsupported animation trailer")
	return {"pivot": pivot, "indices": indices, "positions": positions, "uvs": uvs,
		"normals": normals, "colors": colors, "legacy_attributes": legacy_attributes,
		"sphere": sphere, "tracks": tracks}

func vectors(count: int, dimensions: int, floating: bool, scale: float, positions := false) -> Variant:
	var values := PackedFloat32Array()
	if floating:
		values = cursor.floats(count * dimensions)
	else:
		var component_bytes := 4 if positions else 2
		var block: PackedByteArray = cursor.bytes(count * dimensions * component_bytes)
		if cursor.error.is_empty():
			values.resize(count * dimensions)
			for i in values.size():
				values[i] = block.decode_s32(i * 4) if positions else block.decode_s16(i * 2)
	if dimensions == 2:
		var result := PackedVector2Array()
		if cursor.error.is_empty():
			result.resize(count)
			for i in count:
				result[i] = Vector2(values[i * 2], values[i * 2 + 1]) * scale
		return result
	var result := PackedVector3Array()
	if cursor.error.is_empty():
		result.resize(count)
		for i in count:
			result[i] = Vector3(values[i * 3], values[i * 3 + 1], values[i * 3 + 2]) * scale
	return result

func vector3() -> Vector3:
	var values: PackedFloat32Array = cursor.floats(3)
	return Vector3(values[0], values[1], values[2]) if values.size() == 3 else Vector3.ZERO

func group_tracks(dimensions: int) -> Array:
	var mode: int = cursor.u16()
	if mode == 65535:
		return []
	if mode == 1:
		return [read_track(dimensions)]
	if mode == 0:
		var result: Array = []
		for axis in dimensions:
			result.append(read_track(1))
		return result
	cursor.reject("Unsupported transform animation mode")
	return []

func read_track(dimensions: int) -> Dictionary:
	var count: int = cursor.u16()
	total_keys += count
	if total_keys > MAX_KEYS:
		cursor.reject("Animation key budget exceeded")
		return {}
	var values: PackedFloat32Array = cursor.floats(count * (dimensions + 1))
	if not cursor.error.is_empty():
		return {}
	var previous := -INF
	for i in count:
		var time := values[i * (dimensions + 1)]
		if time < previous:
			cursor.reject("Animation timestamps are out of order")
			return {}
		previous = time
	return {"dimensions": dimensions, "keys": values}

func fail(message: String) -> Dictionary:
	error = message
	return {}
