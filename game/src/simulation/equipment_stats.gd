extends RefCounted
## Shared source-derived equipment capacities and ship pool inputs.
const Definitions=preload("res://src/content/player_initialization_definitions.gd")
const RepairDefinitions=preload("res://src/content/player_repair_definitions.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Fitting=preload("res://src/content/ordinary_fitting_definitions.gd")

static func cargo_capacity(bindings: RefCounted,cat: RefCounted,loadout: Dictionary) -> int:
	var ship: int=loadout.get("ship_id",-1)
	if ship<0 or ship>=cat.tables.ships.size():return -1
	var capacity: Variant=cat.tables.ships[ship].stats.get("cargo_capacity")
	if not Numbers.integer(capacity,0,2147483647):return -1
	if not Fitting.available(bindings):return int(capacity)
	var extra:=capacity_sum(cat,loadout.equipment_ids,int(Fitting.VALUES.cargo_subtype),int(Fitting.VALUES.cargo_property))
	if extra<0 or extra>2147483647-int(capacity):return -1
	return int(capacity)+extra

static func capacity_sum(cat: RefCounted,ids: Array,subtype: int,property: int) -> int:
	var result:=0
	for id in ids:
		if not id is int or id<0 or id>=cat.tables.items.size():return -1
		var item: Dictionary=cat.tables.items[id]
		if item.arrays[2][5]!=subtype:continue
		var value: Variant=item.properties.get(property)
		if not Numbers.integer(value,0,2147483647-result):return -1
		result+=int(value)
	return result

static func resolve_ship_hull(base: Variant, upgrade_tags: Array, parameters: Dictionary) -> int:
	if not RepairDefinitions.parameters(parameters) or not Vitals.integer(base) or upgrade_tags.size()>4096: return -1
	var result: int=base
	for tag in upgrade_tags:
		if not Vitals.integer(tag): return -1
		if tag==int(parameters.upgrade_tag):
			if result>Vitals.MAX_INTEGER-int(parameters.upgrade_bonus): return -1
			result+=int(parameters.upgrade_bonus)
	return result

static func resolve_repair_device(items: Array, equipment_ids: Array, parameters: Dictionary) -> Dictionary:
	if not RepairDefinitions.parameters(parameters) or equipment_ids.size()>4096: return {}
	var result := {"mode":int(parameters.missing_device_mode),"item_id":-1}
	for item_id in equipment_ids:
		if not Vitals.integer(item_id) or item_id>=items.size() or not items[item_id] is Dictionary: return {}
		var arrays: Variant=items[item_id].get("arrays")
		if not arrays is Array or arrays.size()!=3 or not (arrays[2] is Array or arrays[2] is PackedInt32Array) or arrays[2].size()<=int(parameters.item_type_value_index): return {}
		var kind: Variant=arrays[2][int(parameters.item_type_value_index)]
		if not Vitals.integer(kind): return {}
		if kind!=int(parameters.equipment_type): continue
		var source_id: Variant=arrays[2][int(parameters.item_id_value_index)]
		if not Vitals.integer(source_id): return {}
		result={"mode":0 if source_id==int(parameters.slow_item_id) else 1,"item_id":item_id}
	return result

static func resolve_capacities(items: Array, equipment_ids: Array, parameters: Dictionary) -> Dictionary:
	if not Definitions.parameters(parameters) or equipment_ids.size()>4096: return {}
	var result := {"shield":int(parameters.missing_capacity),"armor":int(parameters.missing_capacity),
		"shield_item_id":-1,"armor_item_id":-1}
	for item_id in equipment_ids:
		if not item_id is int or item_id<0 or item_id>=items.size() or not items[item_id] is Dictionary: return {}
		var item: Dictionary=items[item_id]
		var arrays: Variant=item.get("arrays")
		if not arrays is Array or arrays.size()!=3 or not (arrays[2] is Array or arrays[2] is PackedInt32Array) or arrays[2].size()<=int(parameters.item_type_value_index): return {}
		var type_id: Variant=arrays[2][int(parameters.item_type_value_index)]
		if not Numbers.integer(type_id,0,2147483647): return {}
		for pool in ["shield","armor"]:
			if int(type_id)!=int(parameters[pool+"_equipment_type"]): continue
			var properties: Variant=item.get("properties")
			if not properties is Dictionary: return {}
			var value: Variant=properties.get(int(parameters[pool+"_property"]))
			if not value is int or value<0 or value>Vitals.MAX_INTEGER or (pool=="shield" and value>Vitals.MAX_SHIELD): return {}
			result[pool]=value
			result[pool+"_item_id"]=item_id
	return result
