extends RefCounted
## Native owner for the three source-defined Var Hastra tutorial offers.
## Stock, cargo and installed slots have separate ownership. Each accepted
## operation publishes all three together; snapshots and forks are detached.
const Definitions=preload("res://src/content/station_equipment_definitions.gd")
const Loadout=preload("res://src/simulation/opening_loadout.gd")
var error:=""
var _state:={}
var _rules:={}
var _items:={}
var _counts:=[]

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
	_rules=rules.duplicate(true);_items=items;_counts=counts
	_state={"loadout":seed,"stock":stock,"cargo":station.cargo.duplicate(true),"cargo_cache_stale":station.get("cargo_cache_stale",false),"credit_delta":0,"transactions":0}
	return true

func transact(action: String, item_id: int) -> bool:
	error=""
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

func fork() -> RefCounted:
	var result: RefCounted=get_script().new()
	result._state=_state.duplicate(true);result._rules=_rules.duplicate(true);result._items=_items.duplicate(true);result._counts=_counts.duplicate()
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
