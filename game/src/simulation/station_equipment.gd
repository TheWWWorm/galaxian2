extends RefCounted
## Native owner for the three source-defined Var Hastra tutorial offers.
## Stock, cargo and installed slots have separate ownership. Each accepted
## operation publishes all three together; snapshots and forks are detached.
const Definitions=preload("res://src/content/station_equipment_definitions.gd")
const Loadout=preload("res://src/simulation/opening_loadout.gd")
const Training=preload("res://src/content/combat_training_story_definitions.gd")
var error:=""
var _state:={}
var _rules:={}
var _items:={}
var _counts:=[]
var _completion_prices:=[]

func configure(bindings: RefCounted, catalogues: RefCounted, station: Dictionary) -> bool:
	error=""
	if bindings==null or catalogues==null or not Definitions.parameters(bindings.station_equipment):return reject("This pack has no supported equipment tutorial")
	if station.get("base_content_id")!=bindings.base_content_id or station.get("binding_id")!=bindings.binding_id or catalogues.content_id!=bindings.base_content_id:return reject("Equipment belongs to another content identity")
	var rules: Dictionary=bindings.station_equipment
	if station.get("campaign_cursor")!=int(rules.campaign_cursor) or station.get("phase")!="station_equipment_required" or station.get("mission",{}).get("kind")!=int(rules.mission_kind) or not station.get("delivery_acknowledged",false):return reject("Finish the mining delivery before entering this equipment tutorial")
	var loadout:=Loadout.new()
	if not loadout.configure_station(bindings,catalogues,bindings.base_content_id):return reject(loadout.error)
	var seed:=loadout.snapshot()
	if station.get("loadout")!=seed or seed.station_id!=int(rules.station_id) or station.get("source_marked_item_ids")!=[90,81]:return reject("Equipment tutorial needs its retained starter ship")
	if not station.get("cargo") is Dictionary or station.cargo.get("entries")!=[]:return reject("Equipment tutorial still has undelivered ore")
	var items:={};var stock:=[];var ids: Array=rules.protected_item_ids.duplicate()
	for row in rules.stock:ids.append(row.item_id);stock.append({"item_id":int(row.item_id),"quantity":int(row.quantity),"unit_price":int(row.unit_price)})
	for value in ids:
		var id:=int(value)
		if id<0 or id>=catalogues.tables.items.size():return reject("Tutorial equipment is absent from this catalogue")
		var arrays: Array=catalogues.tables.items[id].arrays
		if arrays.size()!=3 or arrays[2].size()<=int(rules.item_subtype_value_index):return reject("Tutorial item has no category or subtype")
		items[id]={"category":int(arrays[2][int(rules.item_category_value_index)]),"subtype":int(arrays[2][int(rules.item_subtype_value_index)])}
	var counts:=[]
	for name in Loadout.SLOT_PROPERTIES:counts.append(int(catalogues.tables.ships[seed.ship_id].stats[name]))
	var capacity:=int(catalogues.tables.ships[seed.ship_id].stats.cargo_capacity)
	if station.cargo.get("capacity")!=capacity:return reject("Tutorial cargo capacity differs from the ship catalogue")
	_rules=rules.duplicate(true);_items=items;_counts=counts;_completion_prices=[]
	_state={"loadout":seed,"stock":stock,"cargo":station.cargo.duplicate(true),"cargo_cache_stale":station.get("cargo_cache_stale",false),"credit_delta":0,"transactions":0}
	return true

func transact(action: String, item_id: int) -> bool:
	error=""
	if _state.get("training_inventory_released",false):return reject("The completed tutorial no longer offers free equipment transactions")
	if _state.is_empty() or not _items.has(item_id) or action not in ["buy","sell","mount","unmount"]:return reject("Unsupported tutorial inventory action")
	if item_id in _rules.protected_item_ids:return reject("This item cannot be sold or demounted at the moment.")
	var next: Dictionary=_state.duplicate(true)
	var cargo: Array=next.cargo.entries
	var row: Dictionary={}
	for offer in next.stock:
		if offer.item_id==item_id:row=offer;break
	if row.is_empty() or row.unit_price!=0:return reject("This tutorial has no supported offer for that item")
	var owned: Dictionary={}
	for entry in cargo:
		if entry.item_id==item_id:owned=entry;break
	var slots: Array=next.loadout.slots
	var installed:=-1
	for i in slots.size():
		if slots[i]!=null and slots[i].item_id==item_id:installed=i;break
	if action=="buy":
		if row.quantity<1:return reject("This offer is out of stock")
		# Only three one-unit offers exist. Use actual owned quantities while
		# the source's post-delivery cargo cache is awaiting its next setter.
		if _used(cargo)>=int(next.cargo.capacity):return reject("Cargo hold is full.")
		row.quantity-=1;_add(cargo,item_id)
	elif action=="sell":
		if owned.is_empty():return reject("Move the item to cargo before selling it")
		owned.quantity-=1;row.quantity+=1
	elif action=="mount":
		if owned.is_empty():return reject("Acquire the item before mounting it")
		var category: int=_items[item_id].category;var subtype: int=_items[item_id].subtype
		if category<0 or category>=_counts.size() or subtype<0 or subtype>=64:return reject("Unsupported equipment category or subtype")
		if (int(_rules.multiple_subtype_mask)&(1<<subtype))==0:
			for slot in slots:
				if slot!=null and _items[slot.item_id].subtype==subtype:return reject("You cannot install this type of equipment more than once.")
		var offset:=0
		for i in category:offset+=int(_counts[i])
		var free:=-1
		for i in int(_counts[category]):
			if slots[offset+i]==null:free=i;break
		if free<0:return reject("No compatible ship slot is free")
		slots[offset+free]={"item_id":item_id,"category":category,"slot":free,"quantity":1}
		owned.quantity-=1
	else:
		if installed<0:return reject("The item is not mounted")
		if _used(cargo)>=int(next.cargo.capacity):return reject("Cargo hold is full.")
		slots[installed]=null;_add(cargo,item_id)
	next.cargo.entries=cargo.filter(func(entry):return entry.quantity>0)
	next.cargo.used=_used(next.cargo.entries)
	next.cargo.free_space=int(next.cargo.capacity)-int(next.cargo.used)
	next.cargo_cache_stale=false
	next.loadout.equipment_ids=[]
	for slot in slots:
		if slot!=null:next.loadout.equipment_ids.append(slot.item_id)
	next.transactions+=1
	_state=next
	return true

func requirements() -> Dictionary:
	var weapon:=false;var armor:=false
	if not _state.is_empty():
		for slot in _state.loadout.slots:
			if slot==null:continue
			var item: Dictionary=_items[slot.item_id]
			if item.category==int(_rules.weapon_category):weapon=true
			elif item.subtype==int(_rules.armor_subtype):armor=true
	return {"weapon_installed":weapon,"armor_installed":armor,"satisfied":weapon and armor}

func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	var result:=_state.duplicate(true);result.requirements=requirements()
	return result

@warning_ignore("integer_division")
func prepare_training_completion(bindings: RefCounted, catalogues: RefCounted) -> bool:
	error=""
	if _state.is_empty() or bindings==null or catalogues==null or not Training.parameters(bindings.combat_training_story) or not requirements().satisfied:return reject("Training inventory requires the earned equipped ship and source transition")
	if _state.cargo.base_content_id!=bindings.base_content_id or _state.cargo.binding_id!=bindings.binding_id or catalogues.content_id!=bindings.base_content_id:return reject("Training inventory prices belong to another content identity")
	var rules: Dictionary=bindings.combat_training_story
	var prices:=[]
	for item in catalogues.tables.items:
		var values: Array=item.arrays[2]
		if values.size()<=int(rules.price_maximum_value_index):return reject("Item prototype price fields are unavailable")
		var low:=int(values[int(rules.price_minimum_value_index)])
		var high:=int(values[int(rules.price_maximum_value_index)])
		prices.append(low+(high-low)/2)
	_completion_prices=prices
	return true

func complete_training(hold: Dictionary) -> bool:
	error=""
	if _completion_prices.is_empty() or _state.get("training_inventory_released",false):return reject("Prepare the training inventory transition exactly once")
	if not _valid_flight_cargo(hold):return false
	var cargo_prices:=[];var installed_prices:=[]
	for index in hold.entries.size():
		cargo_prices.append({"item_id":hold.entries[index].item_id,"unit_price":_completion_prices[index]})
	for index in _state.loadout.slots.size():
		var slot: Variant=_state.loadout.slots[index]
		installed_prices.append(null if slot==null else {"item_id":slot.item_id,"unit_price":_completion_prices[index]})
	# The source indexes prototype prices by list position, including empty
	# installed slots. Cargo is compact; its actual retained order is preserved.
	_state.cargo=hold.duplicate(true);_state.cargo_cache_stale=false
	_state.prices={"installed":installed_prices,"cargo":cargo_prices}
	_state.protected_item_ids=[];_state.training_inventory_released=true
	return true

func retain_flight_cargo(hold: Dictionary) -> bool:
	error=""
	if _state.is_empty() or _completion_prices.is_empty():return reject("Prepare the equipped flight before retaining its cargo")
	if not _valid_flight_cargo(hold):return false
	if hold==_state.cargo:return true
	if _state.get("training_inventory_released",false):
		var existing:={};var prices:=[]
		for row in _state.prices.cargo:existing[row.item_id]=row.unit_price
		# A newly acquired item starts with its own catalogue prototype price.
		# Retained rows keep the price assigned at the training transition.
		for row in hold.entries:prices.append({"item_id":row.item_id,"unit_price":existing.get(row.item_id,_completion_prices[row.item_id])})
		_state.prices.cargo=prices
	_state.cargo=hold.duplicate(true);_state.cargo_cache_stale=false
	return true

func _valid_flight_cargo(hold: Dictionary) -> bool:
	for key in ["base_content_id","binding_id","ship_id","capacity"]:
		if hold.get(key)!=_state.cargo[key]:return reject("Completed training cargo belongs to another ship")
	if not hold.get("entries") is Array or hold.entries.size()>_completion_prices.size() or _state.loadout.slots.size()>_completion_prices.size():return reject("Completed training inventory has an unsupported extent")
	var used:=0;var seen:=[]
	for index in hold.entries.size():
		var row: Variant=hold.entries[index]
		if not row is Dictionary or row.size()!=2 or not row.get("item_id") is int or row.item_id<0 or row.item_id>=_completion_prices.size() or seen.has(row.item_id) or not row.get("quantity") is int or row.quantity<1 or row.quantity>int(hold.capacity)-used:return reject("Completed training cargo contains invalid or repeated rows")
		seen.append(row.item_id);used+=row.quantity
	if hold.get("used")!=used or hold.get("free_space")!=int(hold.capacity)-used:return reject("Completed training cargo quantities disagree with its capacity")
	return true

func fork() -> RefCounted:
	var result: RefCounted=get_script().new()
	result._state=_state.duplicate(true);result._rules=_rules.duplicate(true);result._items=_items.duplicate(true);result._counts=_counts.duplicate()
	result._completion_prices=_completion_prices.duplicate()
	return result

func _used(entries: Array) -> int:
	var used:=0
	for entry in entries:used+=int(entry.quantity)
	return used

func _add(entries: Array, item_id: int) -> void:
	for entry in entries:
		if entry.item_id==item_id:entry.quantity+=1;return
	entries.append({"item_id":item_id,"quantity":1})

func reject(message: String) -> bool:error=message;return false
