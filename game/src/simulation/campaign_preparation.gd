extends RefCounted
## Resolve a declared station reserve and inspect the caller's installed slots.
## The station owner commits stock; the career owner acknowledges completion.
## Neither operation grants equipment, advances a career or consumes randomness.
const Definitions=preload("res://src/content/kappa_preparation_definitions.gd")
const Shopping=preload("res://src/content/ordinary_shopping_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
var error:=""
var _rules:={}
var _items:=[]
var _stations:=0
var _identity:={}

func configure(bindings: RefCounted,cat: RefCounted,cursor: Variant,mission: Variant) -> bool:
	error=""
	if not Definitions.selected(bindings,cursor,mission,"fitting") or cat==null or cat.content_id!=bindings.base_content_id:return reject("Unsupported campaign equipment preparation")
	_rules=bindings.mido_travel.kappa_preparation.duplicate(true)
	_items=cat.tables.items.duplicate(true);_stations=cat.tables.stations.size()
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	return true

func station_stock(station_id: Variant,rows: Variant) -> Dictionary:
	error=""
	if _rules.is_empty():return fail("Configure campaign preparation before supplying station stock")
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
	if not loadout is Dictionary or not docked is bool:return fail("Invalid campaign equipment context")
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
		if matching_slot<0 and int(values[5])==int(_rules.fitting.required_subtype):
			matching_slot=i;matching_item=slot.item_id
	return {"ready":docked and matching_slot>=0,"slot":matching_slot,"item_id":matching_item}

func reject(message: String) -> bool:error=message;return false
func fail(message: String) -> Dictionary:reject(message);return {}
