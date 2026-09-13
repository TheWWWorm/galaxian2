extends RefCounted
## Resolve handling for an explicitly supplied ship, upgrade list and ordered
## equipment catalogue IDs. This computes response, not equipment eligibility.
const Definitions = preload("res://src/content/vehicle_definitions.gd")
const Library = preload("res://src/content/library.gd")
var error := ""
var binding_id := ""
var base_content_id := ""
var _parameters := {}
var _ships := []
var _items := []

func configure(bindings: RefCounted, catalogues: RefCounted, content_id: String) -> bool:
	clear()
	if not Library.valid_hash(content_id) or bindings.base_content_id != content_id or catalogues.content_id != content_id or not Library.valid_hash(bindings.binding_id):
		error = "Vehicle definitions belong to another or unavailable content identity"
		return false
	if not Definitions.valid_parameters(bindings.vehicle_response) or not catalogues.tables.get("ships") is Array or not catalogues.tables.get("items") is Array:
		error = "This content has no supported vehicle response or catalogues"
		return false
	_parameters = bindings.vehicle_response.duplicate(true)
	_ships = catalogues.tables.ships.duplicate(true)
	_items = catalogues.tables.items.duplicate(true)
	base_content_id = content_id
	binding_id = bindings.binding_id
	return true

func clear() -> void:
	error = ""
	binding_id = ""
	base_content_id = ""
	_parameters = {}
	_ships = []
	_items = []

func resolve(ship_id: int, upgrade_tags: Array, equipment_ids: Array, single_precision:=false) -> Dictionary:
	error = ""
	if binding_id.is_empty(): return fail("Configure vehicle response before selecting a ship")
	if ship_id < 0 or ship_id >= _ships.size(): return fail("Ship is outside this content's catalogue")
	if upgrade_tags.size() > 4096 or equipment_ids.size() > 4096: return fail("Vehicle state exceeds supported bounds")
	var base: Variant = _ships[ship_id].get("stats", {}).get("handling_factor")
	if not (base is int or base is float) or not is_finite(base) or base < 0: return fail("Ship has no valid handling rating")
	var handling := (float(base) + float(_parameters.base_add)) / float(_parameters.base_divisor) * float(_parameters.base_scale) + float(_parameters.base_offset)
	# New precision-sensitive owners can request source scalar rounding without
	# changing the established response API used by earlier content profiles.
	if single_precision:
		handling=single(single(single(single(float(base)+float(_parameters.base_add))/float(_parameters.base_divisor))*float(_parameters.base_scale))+float(_parameters.base_offset))
	var bonus:=0.0
	for tag in upgrade_tags:
		if not tag is int or tag < 0 or tag > 2147483647: return fail("Invalid vehicle upgrade tag")
		if tag == int(_parameters.upgrade_tag):
			if single_precision:bonus=single(bonus+float(_parameters.upgrade_bonus))
			else:handling += float(_parameters.upgrade_bonus)
	if single_precision:handling=single(handling+bonus)
	var percent := 0.0
	var selected_item := -1
	for item_id in equipment_ids:
		if not item_id is int or item_id < 0 or item_id >= _items.size(): return fail("Equipment is outside this content's catalogue")
		var item: Dictionary = _items[item_id]
		var arrays: Variant = item.get("arrays")
		if not arrays is Array or arrays.size() != 3 or not (arrays[2] is Array or arrays[2] is PackedInt32Array) or arrays[2].size() <= int(_parameters.item_type_value_index):
			return fail("Equipment lacks its source type binding")
		if arrays[2][int(_parameters.item_type_value_index)] != int(_parameters.equipment_type): continue
		var value: Variant = item.get("properties", {}).get(int(_parameters.equipment_percent_property))
		if not value is int or value < 0: return fail("Maneuverability equipment lacks its required percentage")
		percent = float(value)
		selected_item = item_id
	var factor := (handling + handling * percent / float(_parameters.percent_divisor)) * float(_parameters.response_scale)
	if single_precision:
		factor=single(single(handling+single(handling*single(single(percent)/float(_parameters.percent_divisor))))*float(_parameters.response_scale))
	if not is_finite(factor) or factor <= 0: return fail("Vehicle handling produces an unsupported response factor")
	return {"ship_id": ship_id, "effective_handling": handling, "equipment_percent": percent,
		"handling_item_id": selected_item, "response_factor": factor}

static func single(value: float) -> float:return PackedFloat32Array([value])[0]

func fail(message: String) -> Dictionary:
	error = message
	return {}
