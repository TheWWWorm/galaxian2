extends RefCounted
## Native inventory owner for the starter tutorial and supported station services.
## Stock, cargo and installed slots have separate ownership. Each accepted
## operation publishes all three together; snapshots and forks are detached.
const Definitions=preload("res://src/content/station_equipment_definitions.gd")
const Loadout=preload("res://src/simulation/opening_loadout.gd")
const Training=preload("res://src/content/combat_training_story_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Contracts=preload("res://src/content/early_contract_definitions.gd")
const GateArrival=preload("res://src/content/gate_arrival_definitions.gd")
const Shopping=preload("res://src/content/ordinary_shopping_definitions.gd")
const Prices=preload("res://src/simulation/station_prices.gd")
const FittingRules=preload("res://src/content/ordinary_fitting_definitions.gd")
const Fitting=preload("res://src/simulation/equipment_fitting.gd")
const RecoveryRules=preload("res://src/content/tractor_recovery_definitions.gd")
var error:=""
var _state:={}
var _rules:={}
var _items:={}
var _counts:=[]
var _completion_prices:=[]
var _mission_cargo_id:=-1
var _recovery_cargo_ids:=[]
var _fitting_assets:={}

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
		var item:=_item_metadata(catalogues,id,rules)
		if item.is_empty():return reject("Tutorial item has no category or subtype")
		items[id]=item
	var counts:=[]
	for name in Loadout.SLOT_PROPERTIES:counts.append(int(catalogues.tables.ships[seed.ship_id].stats[name]))
	var capacity:=int(catalogues.tables.ships[seed.ship_id].stats.cargo_capacity)
	if station.cargo.get("capacity")!=capacity:return reject("Tutorial cargo capacity differs from the ship catalogue")
	_rules=rules.duplicate(true);_items=items;_counts=counts;_completion_prices=[];_mission_cargo_id=-1;_fitting_assets={}
	_recovery_cargo_ids=RecoveryRules.cargo_marker_ids(bindings)
	_state={"loadout":seed,"stock":stock,"cargo":station.cargo.duplicate(true),"cargo_cache_stale":station.get("cargo_cache_stale",false),"credit_delta":0,"transactions":0}
	return true

func transact(action: String, item_id: int, credits: int=-1) -> bool:
	error=""
	if _state.get("ordinary_shopping_open",false):return _transact_ordinary(action,item_id,credits)
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
		var position:=_mount_position(slots,item_id)
		if position.has("error"):return reject(position.error)
		slots[position.index]={"item_id":item_id,"category":position.category,"slot":position.slot,"quantity":1}
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

func open_ordinary_shopping(bindings: RefCounted,cat: RefCounted,stock: Array,random_state: Dictionary,unix_seconds: Array,price_percent: int=0,library: RefCounted=null) -> Dictionary:
	error=""
	if _state.is_empty() or not _state.get("training_inventory_released",false) or not _state.get("prototype_drill_replaced",false) or _state.get("ordinary_shopping_open",false):reject("The ordinary hangar requires the earned inventory");return {}
	var place:=Shopping.location(bindings,cat,_state.loadout.station_id)
	if place.is_empty() or place.system_id!=_state.loadout.system_id or not Shopping.valid_stock(stock,cat.tables.items.size()):reject("The ordinary hangar has no supported current stock");return {}
	for key in ["base_content_id","binding_id"]:
		if _state.loadout.get(key)!=bindings.get(key) or _state.cargo.get(key)!=bindings.get(key):reject("The inventory belongs to another content identity");return {}
	if not cargo_cache_valid():return {}
	if not _state.get("prices") is Dictionary or not _state.prices.get("cargo") is Array or not _state.prices.get("installed") is Array or _state.prices.cargo.size()!=_state.cargo.entries.size() or _state.prices.installed.size()!=_state.loadout.slots.size():reject("The retained prices lost their cargo or installed order");return {}
	var lists:={"cargo":null if _state.cargo.entries.is_empty() else _state.prices.cargo,
		"installed":_state.prices.installed,"stock":null if stock.is_empty() else stock}
	var pricing:=Prices.new()
	if not pricing.prepare(bindings,cat,place.station_id,lists,random_state,unix_seconds,price_percent,false):reject(pricing.error);return {}
	var result:=pricing.snapshot();var quoted: Dictionary=result.lists
	var rows:=[];var index:={}
	for i in _state.cargo.entries.size():
		var cargo: Dictionary=_state.cargo.entries[i]
		if quoted.cargo[i].item_id!=cargo.item_id:reject("Cargo price order differs from the retained inventory");return {}
		index[cargo.item_id]=rows.size()
		rows.append({"item_id":cargo.item_id,"owned":cargo.quantity,"stock":0,"unit_price":quoted.cargo[i].unit_price,"mission":cargo.get("mission",false)})
	if quoted.stock!=null:
		for offer in quoted.stock:
			# Matching IDs use the station instance, retaining the owned count.
			# A repeated station ID replaces its earlier quote/quantity.
			if not index.has(offer.item_id):
				index[offer.item_id]=rows.size()
				rows.append({"item_id":offer.item_id,"owned":0,"stock":0,"unit_price":0,"mission":false})
			var row: Dictionary=rows[index[offer.item_id]]
			row.stock=offer.quantity;row.unit_price=offer.unit_price
	var items:={}
	for item in cat.tables.items:
		var data:=_item_metadata(cat,int(item.id),_rules)
		if data.is_empty():reject("The item catalogue lacks its category or subtype");return {}
		items[int(item.id)]=data
	var next:=_state.duplicate(true)
	next.ordinary_shopping_open=true;next.market_rows=rows;next.market_rules=bindings.mido_travel.ordinary_shopping.duplicate(true)
	next.stock_station_id=place.station_id;next.prices.installed=quoted.installed
	_retain_market_inventory(next,false)
	var staged:=fork();staged._state=next;staged._items=items
	if FittingRules.available(bindings):
		var fitting:=Fitting.new();staged._fitting_assets=fitting.prepare_assets(bindings,cat,library)
		if staged._fitting_assets.is_empty():reject(fitting.error);return {}
		if not staged._refresh_fitting(bindings,cat):reject(staged.error);return {}
	_state=staged._state;_items=items;_fitting_assets=staged._fitting_assets
	return result

func close_ordinary_shopping() -> bool:
	error=""
	if not _state.get("ordinary_shopping_open",false):return reject("The ordinary hangar is not open")
	_state.erase("ordinary_shopping_open");_state.erase("market_rows");_state.erase("market_rules")
	for key in ["fitting_support","fitting_conflicts","fitting_stats"]:_state.erase(key)
	_fitting_assets={}
	return true

func fit(bindings: RefCounted,cat: RefCounted,action: String,item_id: int,slot_index: int=-1,passengers: int=0) -> bool:
	error=""
	if not FittingRules.available(bindings) or not _state.get("ordinary_shopping_open",false) or action not in ["mount","unmount","replace"] or not _items.has(item_id) or passengers<0:return reject("The ordinary fitting action is unavailable")
	if cat==null or cat.content_id!=bindings.base_content_id or _state.loadout.binding_id!=bindings.binding_id:return reject("Fitting belongs to another content identity")
	var next:=_state.duplicate(true)
	if action=="unmount":
		if slot_index<0:
			for i in next.loadout.slots.size():
				if next.loadout.slots[i]!=null and next.loadout.slots[i].item_id==item_id:slot_index=i;break
		if slot_index<0 or slot_index>=next.loadout.slots.size() or next.loadout.slots[slot_index]==null or next.loadout.slots[slot_index].item_id!=item_id:return reject("The selected equipment slot no longer contains this item")
		if not _demount_to_market(next,slot_index):return false
	else:
		var row:=_market_row(next,item_id)
		if row.is_empty() or row.owned<1:return reject("Acquire the item before mounting it")
		if row.mission or item_id in next.get("protected_item_ids",[]):return reject("This item cannot be mounted at the moment.")
		var reason: String=next.get("fitting_support",{}).get(item_id,"Fitting this item is not yet supported")
		if not reason.is_empty():return reject(reason)
		var position:=_mount_position(next.loadout.slots,item_id)
		if action=="replace":
			if not position.has("conflict") or slot_index!=position.conflict:return reject("The replacement no longer matches the installed equipment")
			if not _demount_to_market(next,slot_index):return false
			position=_mount_position(next.loadout.slots,item_id)
		elif slot_index!=-1:return reject("Mounting selects the first free compatible slot")
		if position.has("error"):return reject(position.error)
		var quantity:=int(row.owned) if position.category==int(FittingRules.VALUES.stack_category) else int(FittingRules.VALUES.unit_quantity)
		next.loadout.slots[position.index]={"item_id":item_id,"category":position.category,"slot":position.slot,"quantity":quantity}
		next.prices.installed[position.index]={"item_id":item_id,"unit_price":row.unit_price}
		row.owned-=quantity
	next.loadout.equipment_ids=[]
	for slot in next.loadout.slots:
		if slot!=null:next.loadout.equipment_ids.append(slot.item_id)
	var staged:=fork();staged._state=next
	if not staged._refresh_fitting(bindings,cat):return reject(staged.error)
	if passengers>int(staged._state.fitting_stats.passenger_capacity):return reject("This item cannot be sold or demounted at the moment.")
	_retain_market_inventory(staged._state)
	staged._state.credit_delta=0;staged._state.transactions+=1
	_state=staged._state
	return true

func _demount_to_market(next: Dictionary,index: int) -> bool:
	var slot: Dictionary=next.loadout.slots[index]
	if slot.item_id in next.get("protected_item_ids",[]):return reject("This item cannot be sold or demounted at the moment.")
	var quantity:=int(slot.quantity) if slot.category==int(FittingRules.VALUES.stack_category) else int(FittingRules.VALUES.unit_quantity)
	if quantity<1 or quantity>2147483647-_used(next.cargo.entries):return reject("The demounted quantity exceeds the supported cargo range")
	var row:=_market_row(next,slot.item_id)
	if row.is_empty():
		var price: Variant=next.prices.installed[index]
		if not price is Dictionary or price.item_id!=slot.item_id:return reject("Installed equipment lost its retained price")
		row={"item_id":slot.item_id,"owned":0,"stock":0,"unit_price":price.unit_price,"mission":false}
		next.market_rows.append(row)
	if row.mission or row.owned>2147483647-quantity:return reject("The demounted item cannot join this cargo row")
	row.owned+=quantity;next.loadout.slots[index]=null;next.prices.installed[index]=null
	return true

static func _market_row(state: Dictionary,id: int) -> Dictionary:
	for row in state.market_rows:
		if row.item_id==id:return row
	return {}

func _mount_position(slots: Array,id: int) -> Dictionary:
	var category: int=_items[id].category;var subtype: int=_items[id].subtype
	if category<0 or category>=_counts.size() or subtype<0 or subtype>=64:return {"error":"Unsupported equipment category or subtype"}
	if (int(_rules.multiple_subtype_mask)&(1<<subtype))==0:
		for i in slots.size():
			if slots[i]!=null and _items[slots[i].item_id].subtype==subtype:return {"error":"You cannot install this type of equipment more than once.","conflict":i}
	var offset:=0
	for i in category:offset+=int(_counts[i])
	for i in int(_counts[category]):
		if slots[offset+i]==null:return {"index":offset+i,"category":category,"slot":i}
	return {"error":"No compatible ship slot is free"}

func _refresh_fitting(bindings: RefCounted,cat: RefCounted) -> bool:
	var fitting:=Fitting.new();var result:=fitting.inspect(bindings,cat,_state.loadout,_fitting_assets)
	if result.is_empty():return reject(fitting.error)
	_state.fitting_support=result.support;_state.fitting_stats=result.stats;_state.fitting_conflicts={}
	for id in result.support:
		var position:=_mount_position(_state.loadout.slots,id)
		if position.has("conflict"):_state.fitting_conflicts[id]={"index":position.conflict,"item_id":_state.loadout.slots[position.conflict].item_id}
	_state.cargo.capacity=result.stats.cargo_capacity
	_state.cargo.free_space=int(_state.cargo.capacity)-int(_state.cargo.used)
	return true

func _transact_ordinary(action: String,item_id: int,credits: int) -> bool:
	if action not in ["buy","sell"]:return reject("This item action needs supported equipment behavior")
	if not Shopping.parameters(_state.get("market_rules")) or _state.get("stock_station_id")!=_state.loadout.station_id or credits<0 or credits>2147483647:return reject("The ordinary transaction lost its station quote or wallet")
	var next:=_state.duplicate(true);var row: Dictionary={}
	for candidate in next.market_rows:
		if candidate.item_id==item_id:row=candidate;break
	if row.is_empty():return reject("This item is absent from the current stock and cargo")
	if row.mission or item_id in next.get("protected_item_ids",[]):return reject("This item cannot be sold or demounted at the moment.")
	var price: int=row.unit_price
	if price<0 or price>int(next.market_rules.transfer.maximum_credit_delta):return reject("This item price is outside the supported wallet range")
	if action=="buy":
		if row.stock<1:return reject("This offer is out of stock")
		if credits<price:return reject("Insufficient credits.")
		if row.owned==2147483647 or next.cargo.used==2147483647:return reject("This cargo quantity exceeds the supported source range")
		row.stock-=1;row.owned+=1;next.credit_delta=-price
	else:
		if row.owned<1:return reject("Move the item to cargo before selling it")
		if row.stock==2147483647:return reject("This stock quantity exceeds the supported source range")
		row.owned-=1;row.stock+=1;next.credit_delta=price
	_retain_market_inventory(next)
	next.transactions+=1;_state=next
	return true

func _retain_market_inventory(state: Dictionary,refresh_used:=true) -> void:
	var cargo:=[];var prices:=[];var stock:=[];var used:=0
	for row in state.market_rows:
		if row.owned>0:
			var item:={"item_id":row.item_id,"quantity":row.owned}
			if row.mission:item.mission=true
			cargo.append(item);prices.append({"item_id":row.item_id,"unit_price":row.unit_price});used+=row.owned
		if row.stock>0:stock.append({"item_id":row.item_id,"quantity":row.stock,"unit_price":row.unit_price})
	state.stock=stock;state.prices.cargo=prices;state.cargo.entries=cargo
	# Opening a hangar quotes retained lists without invoking the original
	# inventory setter. Purchases, sales and fitting explicitly refresh it.
	if refresh_used:state.cargo.used=used
	state.cargo.free_space=int(state.cargo.capacity)-int(state.cargo.used)
	state.cargo_cache_stale=state.cargo.used!=used

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

func relocate_convoy_arrival(bindings: RefCounted,catalogues: RefCounted,arrival: Dictionary) -> bool:
	error=""
	var definitions=load("res://src/content/alioth_arrival_definitions.gd")
	if not definitions.available(bindings) or catalogues==null or _state.is_empty():return reject("The capture destination is unavailable")
	if catalogues.content_id!=bindings.base_content_id or not _state.get("training_inventory_released",false) or not _state.get("prototype_drill_replaced",false):return reject("The capture lost its retained inventory")
	if not definitions.arrival_matches(bindings,arrival):return reject("The capture requested another station")
	var rules: Dictionary=bindings.mido_travel.alioth_arrival
	var seed: Dictionary=_state.loadout
	if seed.base_content_id!=bindings.base_content_id or seed.binding_id!=bindings.binding_id or seed.station_id!=int(rules.from_station_id) or seed.system_id!=int(rules.from_system_id):return reject("The capture inventory belongs to another location")
	var station: Dictionary=catalogues.tables.stations[int(rules.station_id)]
	var system: Dictionary=catalogues.tables.systems[int(rules.system_id)]
	if station.system_id!=int(rules.system_id) or station.planet_type!=int(rules.planet_type) or system.sky_index!=int(rules.sky_index) or system.fields[2]!=int(rules.faction):return reject("Alioth's catalogue context differs from the source declaration")
	_state.loadout.station_id=int(rules.station_id);_state.loadout.system_id=int(rules.system_id)
	return true

func prepare_alioth_return(bindings: RefCounted) -> bool:
	# Stage the original ship-affiliation assignment on the station's fork.
	# The station commits it only with its final acknowledged return line.
	error=""
	var definitions=load("res://src/content/alioth_return_definitions.gd")
	if not definitions.available(bindings) or _state.is_empty() or not _state.get("training_inventory_released",false) or not _state.get("prototype_drill_replaced",false):return reject("The Alioth return lost its earned inventory")
	var rules: Dictionary=bindings.mido_travel.alioth_return
	var seed: Dictionary=_state.loadout
	if seed.base_content_id!=bindings.base_content_id or seed.binding_id!=bindings.binding_id or seed.station_id!=int(rules.station_id) or seed.system_id!=int(rules.system_id):return reject("The Alioth return inventory belongs to another station")
	_state.ship_affiliation=int(rules.next_player_ship_affiliation)
	return true

func relocate_local_arrival(bindings: RefCounted, catalogues: RefCounted, arrival: Dictionary) -> bool:
	error=""
	if bindings==null or catalogues==null or not Travel.parameters(bindings.mido_travel) or _state.is_empty():return reject("Local arrival requires its retained equipment")
	if not _state.get("training_inventory_released",false) or not _state.get("prototype_drill_replaced",false):return reject("Local arrival requires the completed drill exchange")
	var data: Dictionary=bindings.mido_travel
	if not arrival.get("campaign_cursor") is int:return reject("Local arrival has no mission context")
	if not arrival.get("from_station_id") is int or not arrival.get("station_id") is int:return reject("Local arrival requires catalogue station IDs")
	var trip:=Travel.route(data,arrival.campaign_cursor,arrival.from_station_id,arrival.station_id)
	if trip.is_empty():return reject("Unsupported local destination mission")
	var expected:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"campaign_cursor":arrival.campaign_cursor,"from_station_id":int(trip.from_station_id),
		"station_id":int(trip.station_id),"system_id":int(trip.system_id),"source_state":int(data.travel.source_state),
		"world_type":int(data.travel.world_type),"audio_selector":int(data.travel.audio_selector)}
	if arrival!=expected or catalogues.content_id!=bindings.base_content_id:return reject("Local arrival changed its content or destination")
	var seed: Dictionary=_state.loadout
	if seed.base_content_id!=bindings.base_content_id or seed.binding_id!=bindings.binding_id or seed.station_id!=arrival.from_station_id or seed.system_id!=arrival.system_id:return reject("Local arrival does not follow this inventory's location")
	if arrival.station_id>=catalogues.tables.stations.size():return reject("The destination station is absent")
	var station: Dictionary=catalogues.tables.stations[arrival.station_id]
	if not Travel.location_supported(data,arrival.station_id,station.system_id,station.planet_type):return reject("The destination environment is unsupported")
	# Callers prepare this on a fork, committing it with the complete new world.
	# Moving the location does not buy, sell, refill or reprice any inventory.
	_state.loadout.station_id=arrival.station_id
	return true

func relocate_gate_arrival(bindings: RefCounted,catalogues: RefCounted,arrival: Dictionary) -> bool:
	error=""
	if not GateArrival.packet_matches(bindings,catalogues,arrival) or _state.is_empty():return reject("The gate destination is unavailable")
	if not _state.get("training_inventory_released",false) or not _state.get("prototype_drill_replaced",false):return reject("Gate arrival requires the earned inventory")
	var seed: Dictionary=_state.loadout
	for key in ["base_content_id","binding_id"]:
		if seed.get(key)!=arrival[key]:return reject("Gate inventory belongs to another content identity")
	if seed.station_id!=arrival.from_station_id or seed.system_id!=arrival.from_system_id:return reject("The gate arrival does not follow this inventory's location")
	# The world transaction owns this fork. Preserve all cargo, prices and slots.
	_state.loadout.station_id=arrival.station_id;_state.loadout.system_id=arrival.system_id
	return true

## The cursor25 factory marks only the first retained Void-crystal row. It
## neither creates a missing item nor changes quantities, prices or hold caches.
func protect_sahi_cargo(bindings: RefCounted) -> bool:
	error=""
	if not load("res://src/content/post_sahi_definitions.gd").available(bindings) or not load("res://src/content/sahi_stage_definitions.gd").coherent(bindings.mido_travel) or not cargo_cache_valid():return reject("Sahi cargo protection requires its retained source inventory")
	var seed: Dictionary=_state.loadout
	if seed.base_content_id!=bindings.base_content_id or seed.binding_id!=bindings.binding_id or seed.station_id!=48 or seed.system_id!=9:return reject("Sahi cargo protection belongs to another entry")
	var id:=int(bindings.mido_travel.sahi_stage.next_factory.protected_cargo_item_id)
	var markers:=RecoveryRules.cargo_marker_ids(bindings)
	if id not in markers:return reject("Sahi cargo protection requires its supported story marker")
	_recovery_cargo_ids=markers
	for row in _state.cargo.entries:
		if row.item_id==id:
			row.mission=true
			break
	return true

func relocate_post_sahi(bindings: RefCounted,cursor: int) -> bool:
	error=""
	if bindings==null:return reject("The portal requires its source declarations")
	var location: Dictionary=load("res://src/simulation/flight_player_cache.gd").post_sahi_entry(bindings.mido_travel,cursor,int(_state.get("loadout",{}).get("ship_id",-1)))
	if location.is_empty() or not _state.get("training_inventory_released",false) or not _state.get("prototype_drill_replaced",false):return reject("The portal requires the retained earned inventory")
	var seed: Dictionary=_state.loadout
	for key in ["base_content_id","binding_id"]:
		if seed.get(key)!=bindings.get(key):return reject("Portal equipment belongs to another source")
	if seed.station_id!=(48 if cursor==25 else 91 if cursor==29 else -1) or seed.system_id!=(9 if cursor==25 else 18 if cursor==29 else -1):return reject("The portal does not leave this inventory's location")
	_state.loadout.station_id=int(location.station_id);_state.loadout.system_id=int(location.system_id)
	return true

@warning_ignore("integer_division")
func prepare_training_completion(bindings: RefCounted, catalogues: RefCounted) -> bool:
	error=""
	if _state.is_empty() or bindings==null or catalogues==null or not Training.parameters(bindings.combat_training_story) or not requirements().satisfied:return reject("Training inventory requires the earned equipped ship and source transition")
	if _state.cargo.base_content_id!=bindings.base_content_id or _state.cargo.binding_id!=bindings.binding_id or catalogues.content_id!=bindings.base_content_id:return reject("Training inventory prices belong to another content identity")
	var prices:=prototype_prices(bindings,catalogues)
	if prices.is_empty():return reject("Item prototype price fields are unavailable")
	_completion_prices=prices
	return true

static func prototype_prices(bindings: RefCounted,catalogues: RefCounted) -> Array:
	# Shared by the earned training transition and native save restoration.
	if bindings==null or catalogues==null or catalogues.content_id!=bindings.base_content_id or not Training.parameters(bindings.combat_training_story):return []
	var rules: Dictionary=bindings.combat_training_story
	var prices:=[]
	for item in catalogues.tables.items:
		var values: Array=item.arrays[2]
		if values.size()<=int(rules.price_maximum_value_index):return []
		var low:=int(values[int(rules.price_minimum_value_index)])
		var high:=int(values[int(rules.price_maximum_value_index)])
		prices.append(low+(high-low)/2)
	return prices

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

## Flight consumption removes only the installed stack and its matching price.
## Cargo, stock, wallet accounting and the other installed prices are retained.
func retain_secondary_ammunition(owner: RefCounted) -> bool:
	error=""
	if _state.is_empty() or not _state.get("training_inventory_released",false) or _state.get("ordinary_shopping_open",false):return reject("Secondary consumption requires the released flight inventory")
	if not is_instance_of(owner,load("res://src/simulation/secondary_weapons.gd")):return reject("Secondary consumption requires the actual launcher history")
	var next_loadout: Dictionary=owner.reconcile_loadout(_state.loadout)
	if next_loadout.is_empty():return reject(owner.error)
	if not _state.get("prices") is Dictionary or not _state.prices.get("installed") is Array or _state.prices.installed.size()!=_state.loadout.slots.size():return reject("Secondary consumption lost installed price order")
	var prices: Array=_state.prices.installed.duplicate(true)
	for index in prices.size():
		var prior: Variant=_state.loadout.slots[index]
		var price: Variant=prices[index]
		if prior==null:
			if price!=null:return reject("An empty equipment slot retained a price")
		elif not price is Dictionary or price.get("item_id")!=prior.item_id or not price.get("unit_price") is int or price.unit_price<0 or price.unit_price>2147483647:return reject("Installed ammunition has an invalid retained price")
		if next_loadout.slots[index]==null:prices[index]=null
	var next:=_state.duplicate(true)
	next.loadout=next_loadout;next.prices.installed=prices
	_state=next
	return true

func retain_flight_cargo(hold: Dictionary) -> bool:
	error=""
	if _state.is_empty() or _completion_prices.is_empty():return reject("Prepare the equipped flight before retaining its cargo")
	if not _valid_flight_cargo(hold):return false
	if hold==_state.cargo:return true
	if _state.get("training_inventory_released",false):
		var existing:={};var prices:=[]
		for row in _state.prices.cargo:
			if not existing.has(row.item_id):existing[row.item_id]=[]
			existing[row.item_id].append(row.unit_price)
		# A newly acquired item starts with its own catalogue prototype price.
		# Retained rows keep the price assigned at the training transition.
		for row in hold.entries:
			var retained: Array=existing.get(row.item_id,[])
			prices.append({"item_id":row.item_id,"unit_price":_completion_prices[row.item_id] if retained.is_empty() else retained.pop_front()})
		_state.prices.cargo=prices
	_state.cargo=hold.duplicate(true);_state.cargo_cache_stale=hold.used!=_used(hold.entries)
	return true

func prepare_contract_cargo(bindings: RefCounted) -> bool:
	error=""
	if bindings==null or not Contracts.acceptance_parameters(bindings.early_contracts) or not _state.get("training_inventory_released",false):return reject("Contract cargo requires supported offers and the released inventory")
	if _state.loadout.base_content_id!=bindings.base_content_id or _state.loadout.binding_id!=bindings.binding_id:return reject("Contract cargo belongs to another content identity")
	var id:=int(bindings.early_contracts.courier.cargo_item_id)
	if id<0 or id>=_completion_prices.size():return reject("The mission cargo prototype is absent")
	_mission_cargo_id=id
	_recovery_cargo_ids=RecoveryRules.cargo_marker_ids(bindings)
	return true

func apply_station_exchange(bindings: RefCounted, catalogues: RefCounted, cursor: int) -> bool:
	error=""
	if bindings==null or catalogues==null or not Travel.parameters(bindings.mido_travel):return reject("This pack has no supported station equipment exchange")
	var rules: Dictionary=bindings.mido_travel.exchange
	if cursor!=int(rules.campaign_cursor) or not _state.get("training_inventory_released",false) or _state.get("prototype_drill_replaced",false):return reject("The station drill exchange requires the completed training inventory and occurs once")
	var seed: Dictionary=_state.loadout
	if seed.base_content_id!=bindings.base_content_id or seed.binding_id!=bindings.binding_id or catalogues.content_id!=bindings.base_content_id or seed.station_id!=int(bindings.mido_travel.station_ids[0]) or seed.system_id!=int(bindings.mido_travel.system_id):return reject("The station exchange belongs to another location or content identity")
	var id:=int(rules.replacement_item_id)
	var item:=_item_metadata(catalogues,id,_rules)
	if item.is_empty() or item.category<0 or item.category>=_counts.size() or id>=_completion_prices.size():return reject("The replacement drill lacks its compatible slot or prototype price")
	if _state.prices.installed.size()!=seed.slots.size():return reject("Installed inventory prices lost their slot order")
	var next:=_state.duplicate(true)
	var replaced_id:=-1
	for slot in next.loadout.slots:
		if slot!=null and _items[slot.item_id].subtype==int(rules.find_subtype):
			replaced_id=slot.item_id;break
	# The lookup and removal each stop at their first match; cargo is untouched.
	if replaced_id>=0:
		for index in next.loadout.slots.size():
			var slot: Variant=next.loadout.slots[index]
			if slot!=null and slot.item_id==replaced_id:
				next.loadout.slots[index]=null;next.prices.installed[index]=null
				break
	var offset:=0
	for category in item.category:offset+=int(_counts[category])
	var selected:=-1
	for index in int(_counts[item.category]):
		if next.loadout.slots[offset+index]==null:selected=index;break
	if selected<0:return reject("The replacement drill has no free compatible slot")
	next.loadout.slots[offset+selected]={"item_id":id,"category":item.category,"slot":selected,"quantity":int(rules.quantity)}
	next.prices.installed[offset+selected]={"item_id":id,"unit_price":_completion_prices[id]}
	next.loadout.equipment_ids=[]
	for slot in next.loadout.slots:
		if slot!=null:next.loadout.equipment_ids.append(slot.item_id)
	next.prototype_drill_replaced=true
	_items=_items.duplicate(true);_items[id]=item
	_state=next
	return true

static func _item_metadata(catalogues: RefCounted, id: int, rules: Dictionary) -> Dictionary:
	if id<0 or id>=catalogues.tables.items.size():return {}
	var arrays: Array=catalogues.tables.items[id].arrays
	if arrays.size()!=3 or arrays[2].size()<=maxi(int(rules.item_category_value_index),int(rules.item_subtype_value_index)):return {}
	return {"category":int(arrays[2][int(rules.item_category_value_index)]),"subtype":int(arrays[2][int(rules.item_subtype_value_index)])}

func _valid_flight_cargo(hold: Dictionary) -> bool:
	return _valid_cargo(hold,false)

func cargo_cache_valid() -> bool:
	if _state.is_empty() or not _state.get("cargo_cache_stale") is bool or not _valid_cargo(_state.cargo,true):return reject("The equipped inventory has an invalid retained cargo cache")
	if _state.cargo_cache_stale!=(_state.cargo.used!=_used(_state.cargo.entries)):return reject("The cargo cache marker disagrees with its retained quantities")
	return true

func _valid_cargo(hold: Dictionary,station_only: bool) -> bool:
	for key in ["base_content_id","binding_id","ship_id","capacity"]:
		if hold.get(key)!=_state.cargo[key]:return reject("Completed training cargo belongs to another ship")
	if not hold.get("entries") is Array or hold.entries.size()>_completion_prices.size() or _state.loadout.slots.size()>_completion_prices.size():return reject("Completed training inventory has an unsupported extent")
	var used:=0;var seen:=[]
	var recovery: bool=not _recovery_cargo_ids.is_empty()
	for index in hold.entries.size():
		var row: Variant=hold.entries[index]
		if not row is Dictionary or row.size()!=2+int(row.has("mission")) or not row.get("item_id") is int or row.item_id<0 or row.item_id>=_completion_prices.size() or (not recovery and seen.has(row.item_id)) or not row.get("quantity") is int or row.quantity<1 or row.quantity>(2147483647 if station_only or recovery else int(hold.capacity))-used:return reject("Retained cargo contains invalid or unsupported repeated rows")
		if row.has("mission") and (not row.mission is bool or not row.mission or (row.item_id!=_mission_cargo_id and row.item_id not in _recovery_cargo_ids)):return reject("Unsupported mission cargo marker")
		seen.append(row.item_id);used+=row.quantity
	if not hold.get("used") is int or hold.used<0 or hold.used>2147483647 or (not recovery and hold.used!=used) or not hold.get("free_space") is int or hold.free_space!=int(hold.capacity)-hold.used:return reject("Retained cargo quantities disagree with its used-space cache")
	return true

func fork() -> RefCounted:
	var result: RefCounted=get_script().new()
	result._state=_state.duplicate(true);result._rules=_rules.duplicate(true);result._items=_items.duplicate(true);result._counts=_counts.duplicate()
	result._completion_prices=_completion_prices.duplicate()
	result._mission_cargo_id=_mission_cargo_id
	result._recovery_cargo_ids=_recovery_cargo_ids.duplicate()
	result._fitting_assets=_fitting_assets.duplicate(true)
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
