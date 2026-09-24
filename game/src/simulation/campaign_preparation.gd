extends RefCounted
## Resolve a declared station reserve and inspect the caller's installed slots.
## The station owner commits stock; the career owner acknowledges completion.
## Neither operation grants equipment, advances a career or consumes randomness.
const Definitions=preload("res://src/content/kappa_preparation_definitions.gd")
const Departure=preload("res://src/content/kappa_departure_definitions.gd")
const Shopping=preload("res://src/content/ordinary_shopping_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
var error:=""
var _rules:={}
var _items:=[]
var _stations:=0
var _identity:={}
var _departure_rules:={}
var _cursor:=-1

func configure(bindings: RefCounted,cat: RefCounted,cursor: Variant,mission: Variant) -> bool:
	error=""
	if not Definitions.selected(bindings,cursor,mission,"fitting") or cat==null or cat.content_id!=bindings.base_content_id:return reject("Unsupported campaign equipment preparation")
	_retain_inventory(bindings,cat,cursor)
	return true

func configure_departure(bindings: RefCounted,cat: RefCounted,cursor: Variant,mission: Variant) -> bool:
	error=""
	if not Departure.available(bindings) or cat==null or cat.content_id!=bindings.base_content_id:return reject("Campaign departure requirements are unavailable")
	if not Definitions.selected(bindings,cursor,mission,"fitting") and not Departure.Outcome.selected(bindings,cursor,mission):return reject("Unsupported campaign departure mission")
	_retain_inventory(bindings,cat,cursor)
	return true

func _retain_inventory(bindings: RefCounted,cat: RefCounted,cursor: int) -> void:
	_rules=bindings.mido_travel.kappa_preparation.duplicate(true)
	_items=cat.tables.items.duplicate(true);_stations=cat.tables.stations.size()
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_cursor=cursor
	_departure_rules=bindings.mido_travel.kappa_departure.duplicate(true) if Departure.available(bindings) else {}
	if not _departure_rules.is_empty():_departure_rules.installed_item_ids=_departure_rules.installed_item_ids.map(func(id):return int(id))

func station_stock(station_id: Variant,rows: Variant) -> Dictionary:
	error=""
	if _rules.is_empty() or _cursor!=int(_rules.fitting.campaign_cursor):return fail("Configure campaign preparation before supplying station stock")
	if not Numbers.integer(station_id,0,_stations-1) or not Shopping.valid_stock(rows,_items.size()):return fail("Invalid station or retained market stock")
	var items: Array=rows.duplicate(true)
	if station_id!=int(_rules.fitting.mission.station_id):return {"items":items,"applied":false}
	var id:=int(_rules.stock.item_id);var quantity:=int(_rules.stock.quantity)
	var first:=-1
	for i in items.size():
		if items[i].item_id!=id:continue
		items[i].unit_price=int(_rules.stock.unit_price)
		if first<0:first=i
	if first>=0:
		if items[first].quantity>2147483647-quantity:return fail("Campaign ammunition would exceed the stock quantity limit")
		items[first].quantity+=quantity
	else:
		if items.size()>=4096:return fail("Campaign ammunition would exceed the stock row limit")
		items.append({"item_id":id,"quantity":quantity,"unit_price":int(_rules.stock.unit_price)})
	return {"items":items,"applied":true}

func installed_equipment(loadout: Variant,docked: Variant) -> Dictionary:
	error=""
	if _rules.is_empty():return fail("Configure campaign preparation before inspecting equipment")
	if not docked is bool:return fail("Invalid campaign equipment context")
	var result:=_inspect_installed(loadout,[],int(_rules.fitting.required_subtype))
	if result.is_empty():return {}
	result.ready=result.ready and docked
	return result

## The source tests exact installed IDs at the mission's station. Cargo and
## the broader subtype predicate used by the fitting lesson are independent.
func departure_equipment(loadout: Variant) -> Dictionary:
	error=""
	if _departure_rules.is_empty():return fail("Configure campaign departure before inspecting its requirements")
	if not loadout is Dictionary or not Numbers.integer(loadout.get("station_id"),0,_stations-1):return fail("Invalid departure station")
	var result:=_inspect_installed(loadout,_departure_rules.installed_item_ids)
	if result.is_empty():return {}
	var at_target: bool=loadout.station_id==int(_rules.fitting.mission.station_id)
	var allowed: bool=not at_target or (_cursor==int(_departure_rules.rescue_cursor) and result.ready)
	return {"allowed":allowed,"text_id":-1 if allowed else int(_departure_rules.refusal_text_id)}

func _inspect_installed(loadout: Variant,item_ids: Array,subtype: int=-1) -> Dictionary:
	if not loadout is Dictionary:return fail("Invalid campaign equipment context")
	for key in _identity:
		if loadout.get(key)!=_identity[key]:return fail("Installed equipment belongs to another content identity")
	var slots: Variant=loadout.get("slots")
	if not slots is Array or slots.size()>1020:return fail("Invalid installed equipment slots")
	var matching_slot:=-1;var matching_item:=-1
	for i in slots.size():
		var slot: Variant=slots[i]
		if slot==null:continue
		if not slot is Dictionary or slot.size()!=4 or not Numbers.integer(slot.get("item_id"),0,_items.size()-1) or not Numbers.integer(slot.get("quantity"),1,2147483647) or not Numbers.integer(slot.get("slot"),0,254):return fail("Malformed installed equipment")
		var values: Variant=_items[slot.item_id].arrays[2]
		if not slot.get("category") is int or slot.category!=values[3]:return fail("Installed equipment has a different category")
		var matches: bool=int(values[5])==subtype if subtype>=0 else slot.item_id in item_ids and slot.quantity>=int(_departure_rules.minimum_quantity)
		if matching_slot<0 and matches:
			matching_slot=i;matching_item=slot.item_id
	return {"ready":matching_slot>=0,"slot":matching_slot,"item_id":matching_item}

func fork() -> RefCounted:
	var result: RefCounted=get_script().new()
	result._rules=_rules.duplicate(true);result._items=_items.duplicate(true)
	result._stations=_stations;result._identity=_identity.duplicate(true)
	result._departure_rules=_departure_rules.duplicate(true);result._cursor=_cursor
	return result

func reject(message: String) -> bool:error=message;return false
func fail(message: String) -> Dictionary:reject(message);return {}
