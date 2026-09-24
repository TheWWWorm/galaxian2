extends RefCounted
const Definitions=preload("res://src/content/opening_definitions.gd")
const Categories=preload("res://src/simulation/opening_loadout.gd")
## Check actual ordered slots without granting ownership or choosing equipment.
## Primaries and secondaries share this catalogue/slot validation.
static func checked_slots(bindings: RefCounted,catalogues: RefCounted,loadout: Dictionary) -> Dictionary:
	if bindings==null or catalogues==null or loadout.get("base_content_id")!=bindings.base_content_id or catalogues.content_id!=bindings.base_content_id or loadout.get("binding_id")!=bindings.binding_id:return {}
	var ship_id: Variant=loadout.get("ship_id")
	if not Definitions.integer(ship_id,0,catalogues.tables.ships.size()-1):return {}
	var stats: Dictionary=catalogues.ship_stats(ship_id)
	var counts:=[];var total:=0
	for property in Categories.SLOT_PROPERTIES:
		var count: Variant=stats.get(property)
		if not Definitions.integer(count,0,255):return {}
		counts.append(count);total+=count
	var slots: Variant=loadout.get("slots")
	if not slots is Array or slots.size()!=total:return {}
	var ids:=[];var categories:=[];var index:=0
	var items: Array=catalogues.tables.items
	for category in counts.size():
		var members:=[]
		for slot in counts[category]:
			var entry: Variant=slots[index];index+=1
			if entry==null:continue
			if not entry is Dictionary:return {}
			for field in ["item_id","category","slot","quantity"]:
				if not Definitions.integer(entry.get(field),0,2147483647):return {}
			if entry.category!=category or entry.slot!=slot or entry.item_id>=items.size():return {}
			if items[entry.item_id].arrays[2][int(bindings.weapon_parameters.item_category_value_index)]!=category:return {}
			ids.append(entry.item_id);members.append(entry.duplicate(true))
		categories.append(members)
	if loadout.get("equipment_ids")!=ids:return {}
	return {"ship_id":ship_id,"slots":slots.duplicate(true),"equipment_ids":ids,"categories":categories,"counts":counts}
