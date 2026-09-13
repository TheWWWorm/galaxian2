extends RefCounted
## Authored ship attachment positions, read from each base edition's own table.
## Category 3 records retain their additional vector without implying an effect.
const Cursor = preload("res://src/content/binary_cursor.gd")
const Library = preload("res://src/content/library.gd")
const RESOURCE := "resources/data/bin/weapons_hd.bin"
const MAX_BYTES := 1024 * 1024
const MAX_SHIPS := 4096
const MAX_PARTS := 1024
var error := ""
var _content_id := ""
var _provenance := {}
var _ships := {}

func clear() -> void:
	error = ""
	_content_id = ""
	_provenance = {}
	_ships = {}

func open(library: RefCounted, catalogues: RefCounted) -> bool:
	clear()
	var identity: Variant = library.manifest.get("content_id")
	if not Library.valid_hash(identity) or catalogues.content_id != identity:
		return reject("Mounts require catalogues from the same base content")
	var bytes: PackedByteArray = library.read_resource(RESOURCE, MAX_BYTES)
	if bytes.is_empty(): return reject(library.error)
	var decoded := decode(bytes, catalogues.tables.get("ships", []).size())
	if decoded.is_empty(): return false
	_ships = decoded
	_content_id = identity
	_provenance = {"resource": RESOURCE, "sha256": library.manifest.files[RESOURCE].sha256}
	return true

func decode(bytes: PackedByteArray, ship_count: int) -> Dictionary:
	error = ""
	if bytes.is_empty() or bytes.size() > MAX_BYTES or ship_count < 1 or ship_count > MAX_SHIPS:
		return fail("Unsupported weapon attachment table extent")
	var cursor := Cursor.new(bytes)
	var ships := {}
	while cursor.remaining() > 0:
		var start: int = cursor.offset
		if not cursor.available(4): return fail(cursor.error)
		var ship_id := signed_short(cursor)
		var count := signed_short(cursor)
		if ship_id < 0 or ship_id >= ship_count or ships.has(ship_id):
			return fail("Duplicate or out-of-range attachment ship at byte %d" % start)
		if count < 0 or count > MAX_PARTS or not cursor.available(count * 8):
			return fail("Invalid attachment count at byte %d" % start)
		var groups := [[], [], [], []]
		for i in count:
			var part_start: int = cursor.offset
			if not cursor.available(8): return fail(cursor.error)
			var category := signed_short(cursor)
			if category < 0 or category > 3:
				return fail("Unsupported attachment category at byte %d" % part_start)
			var x := signed_short(cursor)
			var y := signed_short(cursor)
			var z := signed_short(cursor)
			# Source table axes become native source-space X, Z, -Y.
			var part := {"category": category, "slot": groups[category].size(),
				"position": Vector3(x, z, -y), "source_offset": part_start}
			if category == 3:
				var extra: PackedFloat32Array = cursor.floats(3)
				if not cursor.error.is_empty(): return fail(cursor.error)
				part.additional_vector = Vector3(extra[0], extra[2], extra[1])
			part.source_bytes = cursor.offset - part_start
			groups[category].append(part)
		ships[ship_id] = {"ship_id": ship_id, "groups": groups,
			"source_offset": start, "source_bytes": cursor.offset - start}
	return ships

func snapshot() -> Dictionary:
	if _content_id.is_empty(): return {}
	return {"base_content_id": _content_id, "provenance": _provenance.duplicate(true),
		"ships": _ships.duplicate(true)}

func resolve(ship_id: int, category: int, slot: int) -> Dictionary:
	error = ""
	if _content_id.is_empty(): return fail("Open weapon attachments before selecting a mount")
	if not _ships.has(ship_id): return fail("No authored attachment record for this ship")
	if category < 0 or category > 2 or slot < 0 or slot >= _ships[ship_id].groups[category].size():
		return fail("No authored weapon mount for this category and equipment slot")
	var mount: Dictionary = _ships[ship_id].groups[category][slot].duplicate(true)
	mount.ship_id = ship_id
	mount.base_content_id = _content_id
	mount.provenance = _provenance.duplicate(true)
	return mount

static func signed_short(cursor: RefCounted) -> int:
	var value: int = cursor.u16()
	return value - 65536 if value >= 32768 else value

func reject(message: String) -> bool:
	error = message
	return false

func fail(message: String) -> Dictionary:
	error = message
	return {}
