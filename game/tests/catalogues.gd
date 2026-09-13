extends SceneTree
const Catalogues = preload("res://src/content/catalogues.gd")
const Library = preload("res://src/content/library.gd")
var failures := 0


func _initialize() -> void:
	var reader := Catalogues.new()
	var fixture := fixtures()
	var decoded := {}
	for kind in fixture:
		var rows := reader.decode(kind, fixture[kind], 2)
		check(rows.size() == 2, kind + ": " + reader.error)
		decoded[kind] = rows
		for end in fixture[kind].size():
			check(reader.decode(kind, fixture[kind].slice(0, end), 2).is_empty(),
				"Accepted truncated %s at %d" % [kind, end])
		var extra: PackedByteArray = fixture[kind].duplicate()
		extra.append(0)
		check(reader.decode(kind, extra, 2).is_empty(), "Accepted trailing byte in " + kind)
	if decoded.systems.size() == 2 and decoded.stations.size() == 2:
		check(decoded.stations[0].planet_type==9 and decoded.stations[1].planet_type==26,
			"Station planet type is not the fourth scalar")
		check(decoded.systems[0].name == "Béhén ", "UTF-8/whitespace changed")
		check(decoded.systems[0].fields[6] == -1, "Signed catalogue field lost")
		check(reader.validate_relationships(decoded), reader.error)
		var broken: Dictionary = decoded.duplicate(true)
		broken.systems[1].linked_system_ids = PackedInt32Array()
		check(not reader.validate_relationships(broken), "Nonreciprocal link accepted")
		broken = decoded.duplicate(true)
		broken.stations[0].system_id = 1
		check(not reader.validate_relationships(broken), "Incorrect station parent accepted")
		broken = decoded.duplicate(true)
		broken.systems[0].station_ids = PackedInt32Array()
		check(not reader.validate_relationships(broken), "Unlisted station accepted")
		broken = decoded.duplicate(true)
		broken.systems[0].linked_system_ids = PackedInt32Array([2])
		check(not reader.validate_relationships(broken), "Out-of-range system accepted")
		broken = decoded.duplicate(true)
		broken.systems[0].station_ids = PackedInt32Array([0, 0])
		check(not reader.validate_relationships(broken), "Duplicate station accepted")
	reader.tables = decoded
	var base_stats := reader.ship_stats(0)
	check(base_stats == {"armor": 91, "cargo_capacity": 73, "base_price": 19003,
		"primary_slots": 2, "secondary_slots": 3, "turret_slots": 1,
		"equipment_slots": 8, "handling_factor": 1.37}, "Ship property semantics or handling scale changed")
	base_stats.armor = 1
	check(reader.ship_stats(0).armor == 91, "Mutable loadout leaked into base catalogue")
	check(reader.ship_stats(-1).is_empty() and reader.ship_stats(2).is_empty(), "Invalid ship selected")
	for field in range(1, 9):
		var negative: PackedByteArray = fixture.ships.duplicate()
		for byte in 4: negative[field * 4 + byte] = 255
		check(reader.decode("ships", negative, 2).is_empty(), "Negative ship property accepted")
	var zero_slots: PackedByteArray = fixture.ships.duplicate()
	for byte in range(16, 32): zero_slots[byte] = 0
	var unarmed := reader.decode("ships", zero_slots, 2)
	check(not unarmed.is_empty() and unarmed[0].stats.primary_slots == 0 \
		and unarmed[0].stats.equipment_slots == 0, "Zero slots must remain zero")
	var invalid: PackedByteArray = fixture.items.duplicate()
	invalid.fill(255)
	check(reader.decode("items", invalid, 2).is_empty(), "Negative array count accepted")
	invalid = fixture.items.duplicate()
	invalid[0] = 127
	check(reader.decode("items", invalid, 2).is_empty(), "Unbounded array count accepted")
	invalid = fixture.ships.duplicate()
	invalid[3] = 1
	check(reader.decode("ships", invalid, 2).is_empty(), "Misordered ship ID accepted")
	invalid = fixture.stations.duplicate()
	invalid[2] = 0
	check(reader.decode("stations", invalid, 2).is_empty(), "NUL name accepted")
	check(reader.decode("items", item_fixture([1, 2, 1, 3]), 1).is_empty(), "Duplicate property key accepted")
	check(reader.decode("items", item_fixture([1, 2, 3]), 1).is_empty(), "Odd property list accepted")
	for directory in OS.get_cmdline_user_args():
		var library := Library.new()
		if not library.open(directory):
			check(false, library.error)
			continue
		check(reader.open(library), reader.error)
		if not reader.tables.is_empty():
			var counts := {}
			for kind in Catalogues.TABLES: counts[kind] = reader.tables[kind].size()
			print("Catalogue fixture ", library.manifest.profile.edition, ": ", JSON.stringify(counts))
			check(reader.content_id == library.manifest.content_id, "Base identity missing")
			check(library.select_language("gb"), library.error)
			check(reader.ship_stat_labels(library) == ["Armor", "Cargo hold", "Price",
				"Primary weapons", "Secondary weapons", "Turrets", "Equipment", "Handling"],
				"Edition-local ship property labels do not match source UI")
			for ship in reader.tables.ships:
				check(ship.stats.size() == 8 and ship.source_bytes == 36, "Ship property/provenance coverage")
			check(reader.ship_stats(reader.tables.ships.size()).is_empty(), "Cross-edition index accepted")
			check(not reader.open(Library.new()) and reader.tables.is_empty() \
				and reader.content_id.is_empty() and reader.provenance.is_empty(), "Failed open retained content")
			check(reader.ship_stats(0).is_empty(), "Failed open retained ship properties")
	print("Catalogue checks: %d failures" % failures)
	quit(1 if failures else 0)


func fixtures() -> Dictionary:
	var ships := stream()
	var stations := stream()
	var systems := stream()
	var items := stream()
	for i in 2:
		for field in [i, 91, 73, 19003, 2, 3, 1, 8, 137]: ships.put_32(field)
		name_string(stations, "Station %d" % i)
		for field in [i, i, 0, 9+i*17]: stations.put_32(field)
		name_string(systems, "Béhén " if i == 0 else "System 1")
		for field in [1, 0, 2, 22, 55, 55, -1, 4]: systems.put_32(field)
		for array in [[1, 2, 3], [i], [1 - i], [0, 1, 2]]: int_array(systems, array)
		items.put_data(item_fixture([0, i, 1, 250, 5, -10]))
	return {"ships": ships.data_array, "stations": stations.data_array,
		"systems": systems.data_array, "items": items.data_array}


func item_fixture(properties: Array) -> PackedByteArray:
	var data := stream()
	int_array(data, [])
	int_array(data, [])
	int_array(data, properties)
	return data.data_array


func stream() -> StreamPeerBuffer:
	var result := StreamPeerBuffer.new()
	result.big_endian = true
	return result


func name_string(data: StreamPeerBuffer, value: String) -> void:
	var bytes := value.to_utf8_buffer()
	data.put_u16(bytes.size())
	data.put_data(bytes)


func int_array(data: StreamPeerBuffer, value: Array) -> void:
	data.put_32(value.size())
	for field in value: data.put_32(field)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
