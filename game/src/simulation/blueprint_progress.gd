extends RefCounted
## Career blueprint quantities are independent of player cargo and equipment.
## The caller stages the story acknowledgement and cargo debit as one transaction.
const MAX_I32 := 2147483647
const MIN_I32 := -2147483648
const STORY_BLUEPRINT_ID := 85
const STORY_MATERIAL_ID := 164
const STORY_MATERIAL_QUANTITY := 50
const Catalogues = preload("res://src/content/catalogues.gd")
const Library = preload("res://src/content/library.gd")
var error := ""
var _recipes: Dictionary = {}
var _material_unit_value := 0
var _state: Dictionary = {}


func configure(catalogues: RefCounted, binding_id: String) -> bool:
	error = ""
	var definitions := _read_catalogue(catalogues, binding_id)
	if definitions.is_empty(): return false
	var entries := []
	for item_id in definitions.ids:
		entries.append({"item_id": item_id, "available": false,
			"remaining": definitions.recipes[item_id].quantities.duplicate(), "material_value": 0})
	_recipes = definitions.recipes
	_material_unit_value = definitions.material_unit_value
	_state = {"base_content_id": catalogues.content_id, "binding_id": binding_id, "entries": entries}
	return true


func restore(catalogues: RefCounted, binding_id: String, saved: Dictionary) -> bool:
	error = ""
	var definitions := _read_catalogue(catalogues, binding_id)
	if definitions.is_empty(): return false
	if saved.size() != 3 or saved.get("base_content_id") != catalogues.content_id or saved.get("binding_id") != binding_id or not saved.get("entries") is Array:
		return reject("Blueprint progress has another content identity or an incomplete state")
	var entries: Array = saved.entries
	if entries.size() != definitions.ids.size():
		return reject("Blueprint progress lost a source recipe entry")
	for index in entries.size():
		var row: Variant = entries[index]
		var item_id: int = definitions.ids[index]
		if not row is Dictionary or row.size() != 4 or not row.get("item_id") is int or row.item_id != item_id or not row.get("available") is bool or not row.get("material_value") is int or row.material_value < 0 or row.material_value > MAX_I32 or not row.get("remaining") is Array:
			return reject("Blueprint progress contains an invalid entry")
		var remaining: Array = row.remaining
		if remaining.size() != definitions.recipes[item_id].quantities.size():
			return reject("Blueprint progress changed its source recipe extent")
		for amount in remaining:
			if not amount is int or amount < MIN_I32 or amount > MAX_I32:
				return reject("Blueprint progress contains an invalid material count")
	_recipes = definitions.recipes
	_material_unit_value = definitions.material_unit_value
	_state = saved.duplicate(true)
	return true


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func entry(item_id: int) -> Dictionary:
	for row in _state.get("entries", []):
		if row.item_id == item_id: return row.duplicate(true)
	return {}


func fork_for_transaction() -> RefCounted:
	var copy: RefCounted = get_script().new()
	copy._recipes = _recipes
	copy._material_unit_value = _material_unit_value
	copy._state = _state.duplicate(true)
	return copy


## Invoke on a fork after staging exactly 50 crystals out of the same career.
## expected_entry binds the proposal to the observed blueprint state; repeating
## the same proposal after this change is stale. Career owns once-only cursor33.
func precredit_story33(transaction: Dictionary) -> bool:
	error = ""
	if _state.is_empty() or transaction.size() != 8 or transaction.get("base_content_id") != _state.base_content_id or transaction.get("binding_id") != _state.binding_id or not transaction.get("from_cursor") is int or transaction.from_cursor != 33 or not transaction.get("to_cursor") is int or transaction.to_cursor != 34 or not transaction.get("item_id") is int or transaction.item_id != STORY_MATERIAL_ID or transaction.get("cargo_before") is not int or transaction.get("cargo_after") is not int or not transaction.get("expected_entry") is Dictionary:
		return reject("Blueprint credit requires the validated story33 final-Next transaction")
	if transaction.cargo_before < STORY_MATERIAL_QUANTITY or transaction.cargo_before > MAX_I32 or transaction.cargo_after != transaction.cargo_before - STORY_MATERIAL_QUANTITY:
		return reject("Blueprint credit requires the staged 50-crystal debit")
	var before := entry(STORY_BLUEPRINT_ID)
	if transaction.expected_entry != before:
		return reject("Blueprint credit proposal is stale")
	# The source's item85 branch is conditional. Valid native careers contain all
	# source recipes, but retain its harmless missing-entry behavior here.
	if before.is_empty(): return true
	var index: int = _recipes[STORY_BLUEPRINT_ID].material_ids.find(STORY_MATERIAL_ID)
	if index < 0: return reject("The source crystal recipe is unavailable")
	var material_value: int = STORY_MATERIAL_QUANTITY * _material_unit_value
	if before.remaining[index] < MIN_I32 + STORY_MATERIAL_QUANTITY or before.material_value > MAX_I32 - material_value:
		return reject("Blueprint material credit exceeds the source integer range")
	for row in _state.entries:
		if row.item_id == STORY_BLUEPRINT_ID:
			row.available = true
			row.remaining[index] -= STORY_MATERIAL_QUANTITY
			row.material_value += material_value
			return true
	return reject("Blueprint entry disappeared during the transaction")


func _read_catalogue(catalogues: RefCounted, binding_id: String) -> Dictionary:
	if not catalogues is Catalogues or not Library.valid_hash(catalogues.content_id) or not Library.valid_hash(binding_id):
		reject("Blueprint progress requires an imported item catalogue and binding identity")
		return {}
	var items: Variant = catalogues.tables.get("items")
	if not items is Array or items.size() <= STORY_MATERIAL_ID:
		reject("Blueprint progress requires the complete source item catalogue")
		return {}
	var ids := []
	var recipes := {}
	for item_id in items.size():
		var item: Variant = items[item_id]
		if not item is Dictionary or item.get("id") != item_id or not item.get("arrays") is Array or item.arrays.size() < 2 or not item.arrays[0] is PackedInt32Array or not item.arrays[1] is PackedInt32Array:
			reject("Blueprint progress received an invalid source item row")
			return {}
		var material_ids: Array = Array(item.arrays[0])
		if material_ids.is_empty(): continue
		var quantities: Array = Array(item.arrays[1])
		if material_ids.size() != quantities.size() or material_ids.size() > 64:
			reject("Blueprint progress received an invalid source recipe")
			return {}
		var seen := {}
		for index in material_ids.size():
			var material: Variant = material_ids[index]
			var quantity: Variant = quantities[index]
			if not material is int or material < 0 or material >= items.size() or seen.has(material) or not quantity is int or quantity < 1 or quantity > MAX_I32:
				reject("Blueprint progress received an invalid source material")
				return {}
			seen[material] = true
		ids.append(item_id)
		recipes[item_id] = {"material_ids": material_ids.duplicate(), "quantities": quantities.duplicate()}
	if not recipes.has(STORY_BLUEPRINT_ID):
		reject("The Khador Drive source recipe is missing")
		return {}
	var drive: Dictionary = recipes[STORY_BLUEPRINT_ID]
	if drive.material_ids.is_empty() or drive.material_ids[0] != STORY_MATERIAL_ID or drive.quantities[0] != STORY_MATERIAL_QUANTITY:
		reject("The Khador Drive crystal requirement changed")
		return {}
	var crystal: Dictionary = items[STORY_MATERIAL_ID]
	var properties: Variant = crystal.get("properties")
	if not properties is Dictionary or properties.get(7) != 400 or properties.get(8) != 400:
		reject("The source crystal material value changed")
		return {}
	return {"ids": ids, "recipes": recipes, "material_unit_value": 400}


func reject(message: String) -> bool:
	error = message
	return false
