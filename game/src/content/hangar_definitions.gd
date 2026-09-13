extends RefCounted
## Geometry selection declarations, independent of campaign/docking state.
## Empty source rows are unsupported here; never substitute a generic hangar.

static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and value >= low and value <= high and value == floor(value)

static func validate(data: Variant, executable_bytes: int) -> String:
	if not data is Dictionary:
		return "Invalid hangar declarations"
	if data.is_empty():
		return ""
	if data.get("system_field") != 2 or not data.get("rows") is Array or data.rows.size() != 10:
		return "Unsupported hangar table layout"
	var rotation: Variant = data.get("rotation_y")
	if not (rotation is float or rotation is int) or not is_finite(rotation) or absf(rotation) > TAU:
		return "Invalid hangar rotation"
	for row in data.rows:
		if not row is Dictionary or not row.get("resource_ids") is Array or row.resource_ids.size() != 4 \
				or not row.get("extra_resource_ids") is Array or row.extra_resource_ids.size() > 128:
			return "Invalid hangar geometry row"
		for id in row.resource_ids:
			if not integer(id, -1, 65534):
				return "Invalid hangar layer resource"
		var seen := {}
		for id in row.extra_resource_ids:
			if not integer(id, 0, 65534) or seen.has(id):
				return "Invalid or repeated hangar extra resource"
			seen[id] = true
		if row.resource_ids.all(func(id): return id == -1) and not row.extra_resource_ids.is_empty():
			return "Hangar extra geometry has no parent layer"
	if not data.get("station_overrides") is Array or data.station_overrides.size() != 2:
		return "Invalid hangar station overrides"
	var station_ids := {}
	for override in data.station_overrides:
		if not override is Dictionary or not integer(override.get("station_id"), 0, 4095) \
				or not integer(override.get("row"), 0, 9) or station_ids.has(override.station_id):
			return "Invalid or repeated hangar station override"
		station_ids[override.station_id] = true
	if not data.get("provenance") is Array or data.provenance.size() != 4:
		return "Missing hangar provenance"
	for i in 4:
		var record: Variant = data.provenance[i]
		if not record is Dictionary or not integer(record.get("bytes"), 1, 4096) \
				or not integer(record.get("offset"), 0, executable_bytes - int(record.bytes)):
			return "Invalid hangar source extent"
		if i < 3 and record.bytes != (160 if i == 0 else 16):
			return "Invalid hangar table extent"
	return ""

static func select_row(data: Dictionary, station: Dictionary, system: Dictionary) -> int:
	for override in data.get("station_overrides", []):
		if override.station_id == station.id:
			return int(override.row)
	var field: int = data.get("system_field", -1)
	if field < 0 or field >= system.get("fields", []).size():
		return -1
	return int(system.fields[field])

static func validate_ship_placement(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary:
		return "Invalid ship placement definitions"
	if data.is_empty():
		return ""
	var count := 64 if architecture == "armv7" else 61
	if not data.get("y_positions") is Array or data.y_positions.size() != count:
		return "Ship placement table does not match this edition's catalogue"
	for value in data.y_positions:
		if not integer(value, -1000000, 1000000):
			return "Invalid ship hangar position"
	if not data.get("provenance") is Array or data.provenance.size() != 3:
		return "Missing ship placement provenance"
	for i in 3:
		var record: Variant = data.provenance[i]
		if not record is Dictionary or not integer(record.get("bytes"), 1, 4096) \
				or not integer(record.get("offset"), 0, executable_bytes - int(record.bytes)):
			return "Invalid ship placement source extent"
		var expected := [count * 4, 112 if architecture == "armv7" else 123, 4 if architecture == "armv7" else 8]
		if record.bytes != expected[i]:
			return "Unsupported ship placement reader layout"
	return ""

static func validate_ship_lights(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary:
		return "Invalid ship light definitions"
	if data.is_empty(): return ""
	var count := 64 if architecture == "armv7" else 61
	if not data.get("resource_ids") is Array or data.resource_ids.size() != count:
		return "Ship light table does not match this edition's catalogue"
	for row in data.resource_ids:
		if not row is Array or row.size() != 2:
			return "Invalid ship light layer layout"
		for id in row:
			if not integer(id, 0, 65535):
				return "Invalid ship light resource ID"
	# Duplicate IDs in separate slots are meaningful source layers.
	if not data.get("provenance") is Array or data.provenance.size() != 5:
		return "Missing ship light provenance"
	var sizes := [42, count * 2, 102, count * 2, 78] if architecture == "armv7" else [35, count * 2, 119, count * 2, 91]
	for i in sizes.size():
		var record: Variant = data.provenance[i]
		if not record is Dictionary or record.get("bytes") != sizes[i] \
				or not integer(record.get("offset"), 0, executable_bytes - sizes[i]):
			return "Invalid ship light source extent"
	return ""
