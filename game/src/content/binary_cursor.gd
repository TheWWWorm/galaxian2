extends RefCounted
## A bounded cursor. Mesh scalars are little-endian; catalogue methods are explicit.
## Failed reads never advance or allocate a block.
var data: PackedByteArray
var offset := 0
var error := ""

func _init(source: PackedByteArray = PackedByteArray()) -> void:
	data = source

func remaining() -> int:
	return data.size() - offset

func reject(message: String) -> void:
	if error.is_empty():
		error = "%s at byte %d" % [message, offset]

func available(count: int) -> bool:
	if not error.is_empty():
		return false
	if count < 0 or count > remaining():
		reject("Truncated or oversized data block")
		return false
	return true

func bytes(count: int) -> PackedByteArray:
	if not available(count):
		return PackedByteArray()
	var value := data.slice(offset, offset + count)
	offset += count
	return value

func u8() -> int:
	if not available(1):
		return 0
	var value := int(data[offset])
	offset += 1
	return value

func u16() -> int:
	if not available(2):
		return 0
	var value := data.decode_u16(offset)
	offset += 2
	return value

func be_u16() -> int:
	if not available(2):
		return 0
	var value := (int(data[offset]) << 8) | int(data[offset + 1])
	offset += 2
	return value

func be_i32() -> int:
	if not available(4):
		return 0
	var value := (int(data[offset]) << 24) | (int(data[offset + 1]) << 16) \
		| (int(data[offset + 2]) << 8) | int(data[offset + 3])
	offset += 4
	return value - 0x100000000 if value >= 0x80000000 else value

func be_ints(count: int) -> PackedInt32Array:
	if not available(count * 4):
		return PackedInt32Array()
	var result := PackedInt32Array()
	result.resize(count)
	for i in count:
		result[i] = be_i32()
	return result

func be_array(limit: int) -> PackedInt32Array:
	var count := be_i32()
	if count < 0 or count > limit:
		reject("Invalid catalogue array count")
		return PackedInt32Array()
	return be_ints(count)

func be_string(limit: int) -> String:
	var count := be_u16()
	if count < 1 or count > limit:
		reject("Invalid catalogue name length")
		return ""
	var block := bytes(count)
	# Round-trip detects invalid UTF-8 without accepting replacement characters.
	# Names are retained byte-for-byte, including accents and authored whitespace.
	var value := block.get_string_from_utf8()
	if value.to_utf8_buffer() != block or block.has(0):
		reject("Invalid UTF-8 catalogue name")
		return ""
	return value

func floats(count: int) -> PackedFloat32Array:
	var block := bytes(count * 4)
	if not error.is_empty():
		return PackedFloat32Array()
	var result := block.to_float32_array()
	for value in result:
		if not is_finite(value):
			reject("Non-finite floating point value")
			return PackedFloat32Array()
	return result
