extends RefCounted
## Declarative source records, decoded directly from checksum-checked resources.
## Unknown fields stay positional. This is not mission, economy or travel state.
const Cursor = preload("res://src/content/binary_cursor.gd")
const MAX_TABLE_BYTES := 1024 * 1024
const MAX_RECORDS := 4096
const TABLES := ["ships", "items", "systems", "stations"]
const SHIP_PROPERTIES := ["armor", "cargo_capacity", "base_price", "primary_slots",
	"secondary_slots", "turret_slots", "equipment_slots", "handling_factor"]
# Verified independently against each edition's ship statistics screen.
const SHIP_LABEL_IDS := {
	"ios-hd": [165, 166, 132, 265, 266, 267, 269, 164],
	"mac-full-hd": [164, 165, 131, 254, 255, 256, 258, 163],
}
var error := ""
var content_id := ""
var tables: Dictionary = {}
var provenance: Dictionary = {}


func open(library: RefCounted) -> bool:
	error = ""
	content_id = ""
	tables = {}
	provenance = {}
	if library.manifest.is_empty():
		return fail("Open imported content before its catalogues.")
	var counts := {"ships": 64 if library.manifest.profile.edition == "ios-hd" else 61,
		"items": 233, "systems": 34, "stations": 135}
	var staged := {}
	var origins := {}
	for name in TABLES:
		var path := "resources/data/bin/%s.bin" % name
		var bytes: PackedByteArray = library.read_resource(path, MAX_TABLE_BYTES)
		if bytes.is_empty():
			return fail(library.error)
		var rows := decode(name, bytes, counts[name])
		if rows.is_empty():
			return false
		staged[name] = rows
		origins[name] = {"resource": path, "sha256": library.manifest.files[path].sha256}
	if not validate_relationships(staged):
		return false
	# Publish only after every table and reference is valid; a failed open is empty.
	tables = staged
	provenance = origins
	content_id = library.manifest.content_id
	return true


func decode(kind: String, bytes: PackedByteArray, expected_records: int) -> Array:
	error = ""
	if kind not in TABLES or expected_records < 1 or expected_records > MAX_RECORDS \
			or bytes.is_empty() or bytes.size() > MAX_TABLE_BYTES:
		fail("Unsupported or oversized catalogue: " + kind)
		return []
	var cursor := Cursor.new(bytes)
	var rows := []
	for i in expected_records:
		var start: int = cursor.offset
		var row := {"id": i, "source_offset": start}
		match kind:
			"ships":
				row.fields = cursor.be_ints(9)
				if row.fields.size() == 9:
					if row.fields[0] != i:
						cursor.reject("Ship ID does not match record position")
					row.stats = {}
					for field in SHIP_PROPERTIES.size():
						var value: int = row.fields[field + 1]
						if value < 0:
							cursor.reject("Negative base ship property: " + SHIP_PROPERTIES[field])
						row.stats[SHIP_PROPERTIES[field]] = float(value) / 100.0 if field == 7 else value
			"stations":
				row.name = cursor.be_string(1024)
				row.fields = cursor.be_ints(4)
				if row.fields.size() == 4:
					if row.fields[0] != i:
						cursor.reject("Station ID does not match record position")
					row.system_id = row.fields[1]
					row.planet_type = row.fields[3]
			"systems":
				row.name = cursor.be_string(1024)
				row.fields = cursor.be_ints(8)
				if row.fields.size()==8:
					row.sky_index = row.fields[7]
				row.arrays = []
				for j in 4:
					row.arrays.append(cursor.be_array(MAX_RECORDS))
				if row.arrays[0].size() != 3:
					cursor.reject("Unsupported system vector extent")
				row.station_ids = row.arrays[1].duplicate()
				row.linked_system_ids = row.arrays[2].duplicate()
			"items":
				row.arrays = []
				for j in 3:
					row.arrays.append(cursor.be_array(MAX_RECORDS))
				if row.arrays[0].size() != row.arrays[1].size() or row.arrays[2].size() % 2:
					cursor.reject("Unpaired item arrays/properties")
				row.properties = {}
				for j in range(0, row.arrays[2].size() - 1, 2):
					var key: int = row.arrays[2][j]
					if row.properties.has(key):
						cursor.reject("Duplicate item property key")
					row.properties[key] = row.arrays[2][j + 1]
		if not cursor.error.is_empty():
			fail("%s record %d: %s" % [kind, i, cursor.error])
			return []
		row.source_bytes = cursor.offset - start
		rows.append(row)
	if cursor.remaining() != 0:
		fail("Unexpected trailing bytes in " + kind)
		return []
	return rows


func ship_stats(ship_id: int) -> Dictionary:
	error = ""
	if ship_id < 0 or ship_id >= tables.get("ships", []).size():
		fail("Ship catalogue ID is outside this content profile")
		return {}
	# A caller's loadout changes must never mutate the base catalogue.
	return tables.ships[ship_id].stats.duplicate(true)


func ship_stat_labels(library: RefCounted) -> Array[String]:
	var labels: Array[String] = []
	var edition: String = library.manifest.get("profile", {}).get("edition", "")
	if not SHIP_LABEL_IDS.has(edition) or library.strings.is_empty():
		return labels
	for id in SHIP_LABEL_IDS[edition]:
		if id >= library.strings.size():
			return []
		labels.append(library.strings[id])
	return labels


func validate_relationships(value: Dictionary) -> bool:
	# This is schema validation, not a determination of unlocked destinations.
	error = ""
	var systems: Array = value.systems
	var stations: Array = value.stations
	var membership := {}
	for system in systems:
		var seen_links := {}
		for station_id in system.station_ids:
			if station_id < 0 or station_id >= stations.size():
				return fail("Out-of-range station reference in system %d" % system.id)
			if membership.has(station_id) or stations[station_id].system_id != system.id:
				return fail("Inconsistent station membership in system %d" % system.id)
			membership[station_id] = system.id
		for target in system.linked_system_ids:
			if target < 0 or target >= systems.size() or target == system.id or seen_links.has(target):
				return fail("Invalid or duplicate system link in system %d" % system.id)
			if not systems[target].linked_system_ids.has(system.id):
				return fail("Nonreciprocal system link from %d to %d" % [system.id, target])
			seen_links[target] = true
	if membership.size() != stations.size():
		return fail("Station missing from system membership lists")
	return true


func fail(message: String) -> bool:
	error = message
	return false
