extends RefCounted
## Assemble the source opening loadout without advancing/completing a mission.
## Returned state is detached. Configure publishes nothing after a failed check.
const Definitions = preload("res://src/content/opening_definitions.gd")
const StationDefinitions = preload("res://src/content/station_entry_definitions.gd")
const Library = preload("res://src/content/library.gd")
const SLOT_PROPERTIES := ["primary_slots", "secondary_slots", "turret_slots", "equipment_slots"]
var error := ""
var _seed := {}

func clear() -> void:
	error = ""
	_seed = {}

func configure(bindings: RefCounted, catalogues: RefCounted, content_id: String) -> bool:
	clear()
	if not Library.valid_hash(content_id) or content_id != bindings.base_content_id or content_id != catalogues.content_id or not Library.valid_hash(bindings.binding_id):
		return fail("Opening loadout belongs to another or unavailable content identity")
	var data: Dictionary = bindings.opening_loadout
	if not Definitions.valid_parameters(data) or bindings.vehicle_response.is_empty():
		return fail("This profile has no supported opening loadout")
	return assemble(data,catalogues,content_id,bindings.binding_id)

func configure_station(bindings: RefCounted, catalogues: RefCounted, content_id: String) -> bool:
	clear()
	if not Library.valid_hash(content_id) or content_id!=bindings.base_content_id or content_id!=catalogues.content_id or not Library.valid_hash(bindings.binding_id):
		return fail("Station loadout belongs to another content identity")
	if not StationDefinitions.parameters(bindings.station_entry):return fail("First-station loadout is unavailable")
	return assemble(bindings.station_entry,catalogues,content_id,bindings.binding_id)

func assemble(data: Dictionary, catalogues: RefCounted, content_id: String, binding_id: String) -> bool:
	var ships: Variant = catalogues.tables.get("ships")
	var stations: Variant = catalogues.tables.get("stations")
	var systems: Variant = catalogues.tables.get("systems")
	var items: Variant = catalogues.tables.get("items")
	if not ships is Array or not stations is Array or not systems is Array or not items is Array or int(data.ship_id) >= ships.size() or int(data.station_id) >= stations.size():
		return fail("Opening ship or station is outside its content catalogue")
	var ship: Dictionary = ships[int(data.ship_id)]
	var station: Dictionary = stations[int(data.station_id)]
	if not Definitions.integer(station.get("system_id"), 0, systems.size() - 1):
		return fail("Opening station has no valid system")
	var counts := []
	var offsets := []
	var total := 0
	for name in SLOT_PROPERTIES:
		var count: Variant = ship.get("stats", {}).get(name)
		if not Definitions.integer(count, 0, 255): return fail("Opening ship has an unsupported slot layout")
		offsets.append(total)
		counts.append(int(count))
		total += int(count)
	var slots := []
	slots.resize(total)
	for entry in data.equipment:
		var item_id := int(entry.item_id)
		if item_id >= items.size(): return fail("Opening equipment is outside its content catalogue")
		var arrays: Variant = items[item_id].get("arrays")
		if not arrays is Array or arrays.size() != 3 or not (arrays[2] is Array or arrays[2] is PackedInt32Array) or arrays[2].size() < 4:
			return fail("Opening equipment has no source category")
		var category: Variant = arrays[2][int(data.item_category_value_index)]
		if not Definitions.integer(category, 0, counts.size() - 1): return fail("Opening equipment has an unsupported category")
		var slot := int(entry.slot)
		if slot >= counts[int(category)]: return fail("Opening equipment exceeds the ship's category slots")
		var position: int = offsets[int(category)] + slot
		if slots[position] != null: return fail("Opening declarations assign two items to the same slot")
		slots[position] = {"item_id": item_id, "category": int(category), "slot": slot, "quantity": int(entry.quantity)}
	var ordered_ids := []
	for slot in slots:
		if slot != null: ordered_ids.append(slot.item_id)
	_seed = {"base_content_id": content_id, "binding_id": binding_id, "ship_id": int(data.ship_id),
		"station_id": int(data.station_id), "system_id": int(station.system_id), "slots": slots,
		"equipment_ids": ordered_ids}
	return true

func snapshot() -> Dictionary:
	return _seed.duplicate(true)

func fail(message: String) -> bool:
	error = message
	return false
