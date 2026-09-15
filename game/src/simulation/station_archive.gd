extends RefCounted
## Versioned, data-only station records. Restore detached native owners before
## presenting or replacing a running game. Imported rules are never read from saves.
const Station=preload("res://src/simulation/station_entry.gd")
const Equipment=preload("res://src/simulation/station_equipment.gd")
const Contracts=preload("res://src/simulation/contract_session.gd")
const Locations=preload("res://src/simulation/lounge_cache.gd")
const Contacts=preload("res://src/simulation/lounge_contacts.gd")
const Stock=preload("res://src/simulation/station_stock.gd")
const Offer=preload("res://src/simulation/contract_offer.gd")
const Loadout=preload("res://src/simulation/opening_loadout.gd")
const Stats=preload("res://src/simulation/equipment_stats.gd")
const Career=preload("res://src/simulation/opening_handoff.gd")
const Reputation=preload("res://src/simulation/faction_reputation.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Cache=preload("res://src/simulation/flight_player_cache.gd")
const Navigation=preload("res://src/simulation/contract_navigation.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Delivery=preload("res://src/content/ordinary_contracts_definitions.gd")
const FreeFlight=preload("res://src/content/free_flight_definitions.gd")
const FreeNavigation=preload("res://src/content/free_navigation_definitions.gd")
const Shopping=preload("res://src/content/ordinary_shopping_definitions.gd")
const Opening=preload("res://src/simulation/opening_station_archive.gd")
const STATION_KEYS=["base_content_id","binding_id","language","campaign_cursor","phase","line_index","loadout","source_ship_configuration","display_ship_configuration","source_marked_item_ids","progress","mission","cargo","player_cache","arrival_player","docking","flight_elapsed_ms","return_visit","delivery_acknowledged","acknowledged","reward_credits","mining_completed","alioth_return","completed_side_missions","alioth_return_acknowledged","station_response_flags","local_visit","contract_station","local_visit_acknowledged","hangar_open","cargo_cache_stale"]
const INVENTORY_KEYS=["loadout","stock","cargo","cargo_cache_stale","credit_delta","transactions","prices","protected_item_ids","training_inventory_released","prototype_drill_replaced","ship_affiliation","stock_station_id"]
const CAREER_KEYS=["base_content_id","binding_id","campaign_cursor","station_id","rank","reputation","difficulty","credits","passengers","mission","active_offer_id","offers","progress","completed_side_missions","delivery_statistics","pending_result","result_serial","accepted_contact","travel_statistics","last_result","population"]
var error:=""
var restored_locations: RefCounted

static func available(bindings: RefCounted) -> bool:return Delivery.available(bindings)

static func can_capture(state: Dictionary) -> bool:
	if state.get("hangar_open",false) or state.get("lounge_open",false) or not state.get("acknowledged",false):return false
	if not state.get("contracts",{}).get("pending_result",{}).is_empty():return false
	return Opening.accepts(state) or (state.get("phase")=="free_play_required" and state.get("campaign_cursor")==18 and state.get("alioth_return_acknowledged")==true and state.get("contracts",{}).get("pending_result",{}).is_empty())

func capture(station: RefCounted,bindings: RefCounted,locations: RefCounted=null) -> Dictionary:
	error=""
	if not station is Station or not available(bindings):return fail("This game has no supported station save")
	var state: Dictionary=station.snapshot()
	if Opening.accepts(state):return Opening.new().capture(self,station,bindings,locations)
	if state.get("phase")!="free_play_required" or state.get("campaign_cursor")!=18 or state.get("acknowledged")!=true or state.get("alioth_return_acknowledged")!=true:return fail("Finish the station conversation before saving")
	return _capture_career(station,bindings,1)

func _capture_career(station: RefCounted,bindings: RefCounted,version: int) -> Dictionary:
	var state: Dictionary=station.snapshot()
	var equipment: RefCounted=station.equipment_owner();var contracts: RefCounted=station.contract_owner()
	if equipment==null or contracts==null:return fail("The station has no retained inventory or career")
	var owned: Dictionary=equipment.snapshot();var career: Dictionary=contracts.snapshot()
	if owned.get("ordinary_shopping_open",false) or state.get("hangar_open",false):return fail("Close the hangar before saving")
	if not career.get("pending_result",{}).is_empty() or career.has("flight") or not contracts._pending_flight.is_empty():return fail("Acknowledge the delivery result before saving")
	if not contracts._result_inventory.is_empty():return fail("The station still owns an unresolved result")
	var locations: RefCounted=contracts.location_owner()
	if locations==null:return fail("The station has no retained locations")
	owned.erase("requirements");career.erase("lounges")
	return {"format":"gof2-native-station","version":version,"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"station":station._state.duplicate(true),"inventory":owned,"career":career,"locations":locations.snapshot()}

func restore(bindings: RefCounted,cat: RefCounted,library: RefCounted,data: Variant) -> RefCounted:
	error="";restored_locations=null
	if not available(bindings) or cat==null or library==null or cat.content_id!=bindings.base_content_id or library.manifest.get("content_id")!=bindings.base_content_id:return reject("Select the game's content and current bindings before loading")
	if not data is Dictionary or data.size()!=8 or data.get("format")!="gof2-native-station" or data.get("version") not in [1,2] or not data.version is int:return reject("Unsupported station save format")
	if not _identity(data,bindings):return reject("This save belongs to different content or gameplay bindings")
	if not data_tree(data):return reject("The save contains unsupported or oversized data")
	if data.version==2:return Opening.new().restore(self,bindings,cat,library,data)
	if not _keys(data.get("station"),STATION_KEYS) or not _keys(data.get("inventory"),INVENTORY_KEYS) or not _keys(data.get("career"),CAREER_KEYS):return reject("The save contains an unknown station, inventory or career field")
	if not _required(data.inventory,INVENTORY_KEYS.filter(func(key):return key!="stock_station_id")) or not _required(data.career,CAREER_KEYS):return reject("The save is missing required inventory or career data")
	var owned:=_inventory(bindings,cat,data.inventory)
	if owned==null:return null
	var locations:=_locations(bindings,cat,library,data.locations)
	if locations==null:return null
	var contracts:=_career(bindings,cat,data.career,owned,locations)
	if contracts==null:return null
	var saved: Dictionary=data.station
	var inventory: Dictionary=owned.snapshot();var career: Dictionary=contracts.snapshot()
	if not _identity(saved,bindings) or saved.get("campaign_cursor")!=18 or saved.get("phase")!="free_play_required" or saved.get("acknowledged")!=true or saved.get("alioth_return_acknowledged")!=true:return reject("The save has not reached an acknowledged ordinary station")
	if saved.get("loadout")!=inventory.loadout or saved.get("cargo")!=inventory.cargo or saved.get("progress")!=career.progress or saved.get("completed_side_missions")!=career.completed_side_missions:return reject("The saved station differs from its inventory or career")
	if not saved.get("mission") is Dictionary or not FreeNavigation.ordinary_departure_at(bindings,18,saved.mission,int(inventory.loadout.station_id)) or not FreeFlight.response_flags(bindings,saved.get("station_response_flags",{})):return reject("The saved station has an unsupported story or response state")
	if saved.get("source_ship_configuration")!=int(bindings.station_entry.source_ship_configuration) or saved.get("display_ship_configuration")!=int(bindings.station_entry.display_ship_configuration) or saved.get("source_marked_item_ids")!=[]:return reject("The station's ship presentation disagrees with its content")
	if not saved.get("language") is String or not Numbers.integer(saved.get("line_index"),0,128) or not Numbers.integer(saved.get("flight_elapsed_ms"),0,2147483647):return reject("The station has invalid retained conversation or flight metadata")
	for key in ["return_visit","delivery_acknowledged","mining_completed","alioth_return","local_visit","contract_station","local_visit_acknowledged"]:
		if saved.has(key) and not saved[key] is bool:return reject("Invalid station acknowledgement flag")
	if saved.get("reward_credits")!=0:return reject("The acknowledged station retains an unclaimed story reward")
	if saved.has("cargo_cache_stale") and saved.cargo_cache_stale!=false:return reject("The station cargo cache is not current")
	if saved.has("hangar_open") and saved.hangar_open!=false:return reject("Close the saved station's hangar before loading")
	if not _player_cache(bindings,cat,saved.get("player_cache"),inventory.loadout):return null
	var station:=Station.new()
	station._state=saved.duplicate(true);station._rules=bindings.station_entry.duplicate(true)
	station._progress_rules=bindings.opening_handoff.duplicate(true)
	station._equipment=owned;station._contracts=contracts
	if saved.get("alioth_return",false):
		station._return_rules=load("res://src/content/ordinary_flight_definitions.gd").station_return(bindings,17)
		station._local_rules=bindings.mido_travel.alioth_return.duplicate(true)
		station._lines=station._read_lines(bindings,library,station._return_rules.events)
		if station._lines.is_empty():return reject(station.error)
		if saved.line_index!=station._lines.size()-1:return reject("The saved Alioth conversation is not acknowledged through its final line")
	else:
		station._return_rules=FreeFlight.docking(bindings,int(inventory.loadout.station_id))
		if saved.line_index!=0:return reject("An ordinary station retained an unknown conversation")
	station._state.language=library.active_language
	restored_locations=locations
	return station

func _inventory(bindings: RefCounted,cat: RefCounted,data: Dictionary) -> RefCounted:
	var equipment:=_inventory_base(bindings,cat,data)
	if equipment==null:return null
	var seed: Dictionary=data.loadout;var hold: Dictionary=data.cargo
	if Shopping.location(bindings,cat,seed.station_id).is_empty() or not data.get("prices") is Dictionary:return reject("The saved inventory has no supported market or prices")
	if data.get("training_inventory_released")!=true or data.get("prototype_drill_replaced")!=true or data.get("cargo_cache_stale")!=false or data.get("protected_item_ids")!=[] or data.get("ship_affiliation")!=int(bindings.mido_travel.alioth_return.next_player_ship_affiliation):return reject("The save lost its earned equipment transitions")
	if not equipment._valid_cargo(hold,true):return reject(equipment.error)
	if not _price_list(data.prices.get("cargo"),hold.entries) or not _price_list(data.prices.get("installed"),seed.slots) or data.prices.size()!=2:return reject("Saved prices differ from the retained inventory order")
	return equipment

func _inventory_base(bindings: RefCounted,cat: RefCounted,data: Dictionary) -> RefCounted:
	if not data.get("loadout") is Dictionary or not data.get("cargo") is Dictionary:return reject("The save lacks its loadout or cargo")
	var seed: Dictionary=data.loadout;var hold: Dictionary=data.cargo
	if not _identity(seed,bindings) or not _identity(hold,bindings) or not Numbers.integer(seed.get("ship_id"),0,cat.tables.ships.size()-1):return reject("The saved inventory belongs to another ship or content")
	if not Numbers.integer(seed.get("station_id"),0,cat.tables.stations.size()-1) or not seed.get("slots") is Array or seed.slots.size()>1024 or not seed.get("equipment_ids") is Array:return reject("The saved ship has no supported location or slot layout")
	var installed:=[]
	for row in seed.slots:
		if row==null:continue
		if not row is Dictionary or row.size()!=4 or not Numbers.integer(row.get("item_id"),0,cat.tables.items.size()-1) or not Numbers.integer(row.get("slot"),0,254) or not Numbers.integer(row.get("category"),0,3) or row.get("quantity")!=1 or not row.quantity is int:return reject("The saved ship contains an invalid installed slot")
		installed.append({"item_id":row.item_id,"slot":row.slot,"quantity":1})
	var loadout:=Loadout.new()
	if not loadout.assemble({"ship_id":seed.ship_id,"station_id":seed.station_id,"equipment":installed,"item_category_value_index":int(bindings.station_equipment.item_category_value_index)},cat,bindings.base_content_id,bindings.binding_id) or loadout.snapshot()!=seed:return reject("The saved slots disagree with the original ship and item catalogues")
	if hold.get("ship_id")!=seed.ship_id or hold.get("capacity")!=Stats.cargo_capacity(bindings,cat,seed):return reject("Saved cargo capacity disagrees with the equipped ship")
	if not Numbers.integer(data.get("transactions"),0,2147483647) or not Numbers.integer(data.get("credit_delta"),-2147483648,2147483647):return reject("The inventory has an invalid transaction counter")
	if data.has("stock_station_id") and not Numbers.integer(data.stock_station_id,0,cat.tables.stations.size()-1):return reject("The inventory's last quote names an unknown station")
	if not _stock_rows(data.get("stock"),cat.tables.items.size(),true):return reject("Invalid retained inventory stock")
	var equipment:=Equipment.new()
	equipment._rules=bindings.station_equipment.duplicate(true);equipment._state=data.duplicate(true)
	equipment._completion_prices=Equipment.prototype_prices(bindings,cat)
	if equipment._completion_prices.is_empty():return reject("The source inventory prices are unavailable")
	for item in cat.tables.items:equipment._items[int(item.id)]=Equipment._item_metadata(cat,int(item.id),equipment._rules)
	for key in Loadout.SLOT_PROPERTIES:equipment._counts.append(int(cat.tables.ships[seed.ship_id].stats[key]))
	equipment._mission_cargo_id=int(bindings.early_contracts.courier.cargo_item_id)
	return equipment

func _locations(bindings: RefCounted,cat: RefCounted,library: RefCounted,data: Variant) -> RefCounted:
	if not data is Dictionary or data.size()!=8 or not _identity(data,bindings) or not data.get("locations") is Array:return reject("The save has no valid station cache")
	var cache:=Locations.new()
	if not cache.configure(bindings):return reject(cache.error)
	if not Numbers.integer(data.get("capacity"),1,3) or data.capacity!=cache.snapshot().capacity or not Numbers.integer(data.get("current_station_id"),0,cat.tables.stations.size()-1) or data.locations.is_empty() or data.locations.size()>data.capacity or not Navigation.valid_availability(bindings.early_contracts.base_navigation,data.get("system_availability")):return reject("Invalid retained station count or system availability")
	var random:=Random.new()
	if not random.restore(data.get("random")):return reject(random.error)
	for index in data.locations.size():
		var row: Variant=data.locations[index]
		if not _keys(row,["station_id","population","offers","stock","market_items"]) or not row.get("population") is Dictionary or not row.get("offers") is Dictionary:return reject("Invalid saved lounge entry")
		var stock:=Stock.new();var contacts:=Contacts.new()
		if not stock.restore(bindings,cat,row.get("stock")) or not contacts.restore(bindings,cat,library,row.population):return reject(stock.error+contacts.error)
		if row.get("station_id")!=row.population.context.station_id:return reject("The cached lounge names another station")
		if index==0:cache._state.history=row.population.initial_history.duplicate()
		if not cache.remember(contacts,stock):return reject(cache.error)
		var generated: Dictionary=cache.location(row.station_id)
		if row.offers.size()!=generated.offers.size():return reject("The saved lounge changed its generated contacts")
		for id in generated.offers:
			var offer: Variant=row.offers.get(id)
			if not offer is Dictionary or offer.size()!=2 or offer.get("offer")!=generated.offers[id].offer or not offer.get("consumed") is bool:return reject("The saved contact changed its original offer")
			if offer.consumed and not cache.consume(row.station_id,id):return reject(cache.error)
		if row.has("market_items"):
			if not Shopping.valid_stock(row.market_items,cat.tables.items.size()):return reject("Invalid mutable station stock")
			cache._state.locations.back().market_items=row.market_items.duplicate(true)
	if cache.snapshot().history!=data.get("history") or cache.location(data.get("current_station_id",-1)).is_empty():return reject("The saved station cache lost its history or current location")
	cache._state.current_station_id=data.current_station_id;cache._state.random=random.snapshot()
	cache._state.system_availability=data.system_availability.duplicate()
	if cache.snapshot()!=data:return reject("The saved location cache differs from its validated entries")
	return cache

func _career(bindings: RefCounted,cat: RefCounted,data: Dictionary,equipment: RefCounted,locations: RefCounted,cursor: int=18) -> RefCounted:
	if cursor not in [13,14,16,18] or not _identity(data,bindings) or data.get("campaign_cursor")!=cursor or data.get("station_id")!=equipment.snapshot().loadout.station_id or data.get("station_id")!=locations.snapshot().current_station_id:return reject("The saved career belongs to another station")
	if data.get("difficulty") not in [0.5,1.0,1.5] or not data.get("difficulty") is float or not data.get("progress") is Dictionary or not Reputation.valid_state(data.get("reputation")):return reject("The saved difficulty or career is invalid")
	var progress: Dictionary=data.progress
	if not Opening.new().valid_progress(self,bindings,progress,cursor):return null
	if cursor==18 and progress.size()!=9:return reject("The saved unlocked career lacks its counters")
	var earned:=Career.calculate_progress(bindings.opening_handoff,cursor,progress.player_kills,progress.pirate_kills,progress.other_score)
	if earned.is_empty() or progress.get("reputation")!=data.reputation or data.get("rank")!=earned.rank:return reject("The saved rank or faction standing disagrees with its career")
	for key in earned:
		if progress.get(key)!=earned[key]:return reject("The saved career disagrees with its earned counters")
	for key in ["credits","passengers","completed_side_missions","result_serial"]:
		if not Numbers.integer(data.get(key),0,2147483647):return reject("The saved wallet or contract counter is invalid")
	if (cursor!=13 and data.completed_side_missions<4) or not data.get("mission") is Dictionary or data.get("pending_result")!={} or not data.get("accepted_contact") is Dictionary:return reject("The save has an unresolved result or unsupported career boundary")
	if not preload("res://src/content/gate_arrival_definitions.gd").valid_statistics(data.get("travel_statistics")):return reject("The saved career lost its travel statistics")
	if not data.get("delivery_statistics") is Dictionary or data.delivery_statistics.size()!=2:return reject("Missing delivery statistics")
	for key in ["cargo","passengers"]:
		if not Numbers.integer(data.delivery_statistics.get(key),0,2147483647):return reject("Invalid delivery statistics")
	var current: Dictionary=locations.location(data.station_id)
	if data.get("population")!=current.population or data.get("offers")!=current.offers:return reject("The current lounge differs from the saved cache")
	if data.has("last_result"):
		if not data.last_result is Dictionary or not Numbers.integer(data.last_result.get("serial"),1,data.result_serial) or data.last_result.get("acknowledgement_required")!=false:return reject("Invalid acknowledged result history")
	if data.mission.is_empty():
		if data.passengers!=0 or data.active_offer_id!=-1 or not data.accepted_contact.is_empty():return reject("The empty contract slot retains passengers or a client")
	else:
		var contact: Dictionary=data.accepted_contact
		if not _keys(contact,["offer_id","station_id","offer","name","portrait"]) or contact.size()!=5 or not Numbers.integer(contact.get("offer_id"),0,4095) or contact.offer_id!=data.get("active_offer_id") or not contact.get("name") is String or not contact.get("portrait") is Dictionary:return reject("The accepted contract lost its original client")
		var offer:=Offer.new()
		if not offer.restore(bindings,cat,contact.get("offer")):return reject(offer.error)
		# Capture retains an independent job accepted before leaving Mido. It
		# neither re-accepts it at Alioth nor changes its original generated terms.
		var accepted_cursor:=mini(cursor,int(bindings.early_contracts.last_cursor)) if cursor<18 else cursor
		if offer.snapshot().mission!=data.mission or not Contracts.acceptance_supported(bindings.early_contracts,accepted_cursor,offer.snapshot(),bindings) or contact.station_id!=offer.snapshot().context.station_id:return reject("The accepted contract changed its generated terms")
		var original: Dictionary=locations.location(contact.station_id)
		if not original.is_empty() and (not original.offers.has(contact.offer_id) or not original.offers[contact.offer_id].consumed or original.offers[contact.offer_id].offer!=contact.offer):return reject("The accepted client is unconsumed or changed in its retained lounge")
		var passengers: int=int(data.mission.quantity) if data.mission.kind==11 else 0
		if data.passengers!=passengers or passengers>Contracts.passenger_capacity(Contracts.cabin_catalogue(cat,bindings.early_contracts.acceptance),equipment.snapshot().loadout):return reject("The accepted passengers disagree with their mission or installed berths")
	var career:=Contracts.new()
	career._state=data.duplicate(true);career._rules=bindings.early_contracts.duplicate(true)
	career._cabins=Contracts.cabin_catalogue(cat,bindings.early_contracts.acceptance)
	career._progress_rules=bindings.opening_handoff.duplicate(true)
	career._stations=cat.tables.systems[int(bindings.early_contracts.system_id)].station_ids.duplicate()
	career._lounges=locations
	if cursor==18 and career.free_flight_context(bindings,data.station_id).is_empty():return reject(career.error)
	if cursor in [13,14] and career.flight_context(data.station_id,bindings).is_empty():return reject(career.error)
	return career

func _player_cache(bindings: RefCounted,cat: RefCounted,value: Variant,loadout: Dictionary,cursor: int=18) -> bool:
	if not value is Dictionary or not _identity(value,bindings) or not value.get("equipment_ids") is Array:return _invalid("The station lost its retained player pools")
	# A station fit can change installed IDs after the arrival cache was captured.
	var seed:=loadout.duplicate(true);seed.equipment_ids=value.equipment_ids.duplicate()
	for id in seed.equipment_ids:
		if not Numbers.integer(id,0,cat.tables.items.size()-1):return _invalid("The saved player cache contains an unknown item")
	if not Cache.matches(value,seed,cursor) or value.values.hull==0:return _invalid("The save has no viable station player cache")
	return true

static func _identity(data: Dictionary,bindings: RefCounted) -> bool:return data.get("base_content_id")==bindings.base_content_id and data.get("binding_id")==bindings.binding_id

static func _keys(data: Variant,names: Array) -> bool:
	if not data is Dictionary or data.is_empty():return false
	for key in data:
		if key not in names:return false
	return true

static func _required(data: Dictionary,names: Array) -> bool:
	for key in names:
		if not data.has(key):return false
	return true

static func _price_list(prices: Variant,items: Array) -> bool:
	if not prices is Array or prices.size()!=items.size():return false
	for index in items.size():
		if items[index]==null:
			if prices[index]!=null:return false
		elif not prices[index] is Dictionary or prices[index].size()!=2 or prices[index].get("item_id")!=items[index].item_id or not Numbers.integer(prices[index].get("unit_price"),0,2147483647):return false
	return true

static func _stock_rows(rows: Variant,item_count: int,allow_empty_quantity: bool) -> bool:
	if not rows is Array or rows.size()>item_count:return false
	var seen:=[]
	for row in rows:
		if not row is Dictionary or row.size()!=3 or not Numbers.integer(row.get("item_id"),0,item_count-1) or row.item_id in seen or not Numbers.integer(row.get("quantity"),0 if allow_empty_quantity else 1,2147483647) or not Numbers.integer(row.get("unit_price"),0,2147483647):return false
		seen.append(row.item_id)
	return true

static func data_tree(value: Variant,depth: int=0,budget: Array=[]) -> bool:
	if depth==0:budget=[200000]
	budget[0]-=1
	if depth>32 or budget[0]<0:return false
	if value==null or value is bool or value is int:return true
	if value is float:return is_finite(value)
	if value is String or value is StringName:return String(value).length()<=16384
	if value is Vector3:return value.is_finite()
	if value is Array:
		if value.size()>4096:return false
		for child in value:
			if not data_tree(child,depth+1,budget):return false
		return true
	if value is Dictionary:
		if value.size()>4096:return false
		for key in value:
			if not (key is String or key is StringName or key is int) or not data_tree(value[key],depth+1,budget):return false
		return true
	return false

func reject(message: String) -> RefCounted:error=message;return null
func fail(message: String) -> Dictionary:error=message;return {}
func _invalid(message: String) -> bool:error=message;return false
