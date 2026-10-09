extends RefCounted
## Versioned, data-only station records. Restore detached native owners before
## presenting or replacing a running game. Imported rules are never read from saves.
const Difficulty=preload("res://src/content/difficulty_definitions.gd")
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
const Dekato=preload("res://src/content/dekato_convoy_definitions.gd")
const Nehma=preload("res://src/content/nehma_return_definitions.gd")
const Valkyrie=preload("res://src/content/valkyrie_campaign_definitions.gd")
const StationContext=preload("res://src/simulation/mission_station_context.gd")
const STATION_KEYS=["base_content_id","binding_id","language","campaign_cursor","phase","line_index","loadout","source_ship_configuration","display_ship_configuration","source_marked_item_ids","progress","mission","cargo","player_cache","arrival_player","docking","flight_elapsed_ms","return_visit","delivery_acknowledged","acknowledged","reward_credits","mining_completed","alioth_return","completed_side_missions","alioth_return_acknowledged","station_response_flags","local_visit","contract_station","local_visit_acknowledged","hangar_open","cargo_cache_stale"]
const CHAPTER_KEYS=["campaign_conversation","next_course"]
const INVENTORY_KEYS=["loadout","stored_ship","stock","cargo","cargo_cache_stale","credit_delta","transactions","prices","protected_item_ids","training_inventory_released","prototype_drill_replaced","ship_affiliation","stock_station_id"]
const CAREER_KEYS=["base_content_id","binding_id","campaign_cursor","station_id","rank","reputation","difficulty","credits","passengers","mission","active_offer_id","offers","progress","completed_side_missions","delivery_statistics","pending_result","result_serial","accepted_contact","travel_statistics","last_result","population"]
const OPTIONAL_CAREER_KEYS=["contract_phase","station_outcome","wingmen","base_medals","conversations","rejected_jobs","stats","medal_notices","elite_medals"]
var error:=""
var restored_locations: RefCounted
var _expansion:=false

static func available(bindings: RefCounted) -> bool:return Delivery.available(bindings)

static func can_capture(state: Dictionary) -> bool:
	if state.get("hangar_open",false) or state.get("lounge_open",false) or not state.get("acknowledged",false):return false
	if not state.get("contracts",{}).get("pending_result",{}).is_empty():return false
	return Opening.accepts(state) or (state.get("phase")=="free_play_required" and state.get("alioth_return_acknowledged")==true)

func capture(station: RefCounted,bindings: RefCounted,locations: RefCounted=null) -> Dictionary:
	error=""
	if not station is Station or not available(bindings):return fail("This game has no supported station save")
	var state: Dictionary=station.snapshot()
	var continuation: RefCounted=station.mission_station_context_owner()
	if Valkyrie.saved_story(bindings,state.get("campaign_cursor")):
		if not can_capture(state) or not _expansion_station(bindings,state):return fail("Finish the station conversation before saving")
		return _capture_career(station,bindings,12)
	if continuation!=null:
		if not can_capture(state):return fail("Finish the station conversation before saving")
		if not _continuation_station(bindings,state,continuation):return {}
		return _capture_career(station,bindings,11)
	if Opening.accepts(state):return Opening.new().capture(self,station,bindings,locations)
	if state.has("nehma_source_receipt"):
		if not can_capture(state) or not _onward_station(bindings,state):return fail("The onward checkpoint requires its actual docking and both explicit sources")
		return _capture_career(station,bindings,10)
	if state.get("campaign_cursor")==39:
		if not can_capture(state) or not _dekato_station(bindings,state):return fail("The post-convoy station requires its acknowledged docking and explicit source")
		var retained: RefCounted=station.contract_owner()
		if retained==null or not retained.retain_dekato_station(bindings,station.equipment_owner(),state.dekato_source_receipt):return fail("The post-convoy station lost its full native career")
		return _capture_career(station,bindings,9)
	if not can_capture(state) or not FreeFlight.Campaign.supported(bindings.mido_travel,state.get("campaign_cursor")):return fail("Finish the station conversation before saving")
	# The completed contest retains the actual source/blueprint career. A
	# detached encounter alone cannot produce a durable campaign checkpoint.
	if FreeFlight.Campaign.BakkaReturn.parameters(bindings.mido_travel.get("bakka_return")) and state.mission==FreeFlight.Campaign.PostProbe.mission_values(bindings.mido_travel.bakka_return.next_mission) and not state.get("contracts",{}).has("void_source"):return fail("The B'akka checkpoint requires its retained Void career")
	if state.get("contracts",{}).has("void_source"):return _capture_career(station,bindings,8)
	return _capture_career(station,bindings,7 if state.campaign_cursor==32 else 6 if state.campaign_cursor in [28,31] else 5 if state.campaign_cursor==27 else (1 if state.campaign_cursor==18 else (3 if state.campaign_cursor==19 else 4)))

func _capture_career(station: RefCounted,bindings: RefCounted,version: int) -> Dictionary:
	var equipment: RefCounted=station.equipment_owner();var contracts: RefCounted=station.contract_owner()
	if equipment==null or contracts==null:return fail("The station has no retained inventory or career")
	var owned: Dictionary=equipment.snapshot();var career: Dictionary=contracts.snapshot()
	if owned.get("ordinary_shopping_open",false):return fail("Close the hangar before saving")
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
	if not data is Dictionary or data.size()!=8+int(data.has("import_update")) or data.get("format")!="gof2-native-station" or data.get("version") not in [1,2,3,4,5,6,7,8,9,10,11,12] or not data.version is int:return reject("Unsupported station save format")
	if not _identity(data,bindings):return reject("This save belongs to different content or gameplay bindings")
	if data.has("import_update") and not bindings.accepts_import_update(data.import_update):return reject("Update the game files to restore this saved career's additional source data")
	if not bindings.bind_catalogues(cat):return reject(bindings.error)
	if not data_tree(data):return reject("The save contains unsupported or oversized data")
	if data.version==2:return Opening.new().restore(self,bindings,cat,library,data)
	_expansion=data.version==12
	var career_keys: Array=CAREER_KEYS+OPTIONAL_CAREER_KEYS+(["void_source","blueprints"] if data.version in [8,9,10,11,12] else [])
	var station_keys: Array=STATION_KEYS+(CHAPTER_KEYS if data.version in [4,6,7,8,10,11,12] else [])+(["dekato_source_receipt"] if data.version in [9,10,11,12] else [])+(["nehma_source_receipt"] if data.version in [10,11,12] else [])+(["mission_station_return"] if data.version in [11,12] else [])
	if not _keys(data.get("station"),station_keys) or not _keys(data.get("inventory"),INVENTORY_KEYS) or not _keys(data.get("career"),career_keys):return reject("The save contains an unknown station, inventory or career field")
	if data.version in [8,9,10,11,12] and not data.career.get("void_source") is Dictionary:return reject("The save is missing its retained Void source")
	if data.version in [8,9,10,11,12] and not data.career.get("blueprints") is Dictionary:return reject("The save is missing its retained blueprint progress")
	var continuation: RefCounted
	if data.version==11:
		continuation=StationContext.new()
		if not continuation.restore(bindings,cat,data.station.get("mission_station_return")):return reject(continuation.error)
		if not _continuation_station(bindings,data.station,continuation):return null
	elif data.version==12 and data.station.has("mission_station_return"):
		# The finished main chapter remains only as history for its lounges.
		continuation=StationContext.new()
		if not continuation.restore(bindings,cat,data.station.mission_station_return) or not continuation.recipe().is_empty():return reject("The expansion career has an invalid finished chapter")
	if data.version==9 and not _dekato_station(bindings,data.station):return reject("The v9 checkpoint requires its exact explicitly attached source and actual station boundary")
	if data.version==10 and not _onward_station(bindings,data.station):return reject("The v10 checkpoint requires its exact explicit sources and actual onward station boundary")
	if not _required(data.inventory,INVENTORY_KEYS.filter(func(key):return key not in ["stock_station_id","ship_affiliation","stored_ship"])) or not _required(data.career,CAREER_KEYS):return reject("The save is missing required inventory or career data")
	var owned:=_inventory(bindings,cat,data.inventory)
	if owned==null:return null
	var locations:=_locations(bindings,cat,library,data.locations,continuation)
	if locations==null:return null
	var cursor: Variant=data.station.get("campaign_cursor")
	if not cursor is int or (data.version==1 and cursor!=18) or (data.version==3 and cursor!=19) or (data.version==4 and (cursor not in [20,21,22,23,24] or not FreeFlight.Campaign.chapter_available(bindings.mido_travel))) or (data.version==5 and (cursor!=27 or not FreeFlight.Campaign.Post.available(bindings))):return reject("The station save version does not support this campaign stage")
	if data.version==6 and (cursor not in [28,31] or not FreeFlight.Campaign.expedition_available(bindings.mido_travel)):return reject("The station save requires its supported expedition chapter")
	if data.version==7 and (cursor!=32 or not FreeFlight.Campaign.post_probe_available(bindings.mido_travel)):return reject("The station save requires its supported post-probe chapter")
	if data.version==8 and (cursor not in [28,31,32,33,34,35,36,38] or not Contracts.VoidAccess.parameters(bindings.mido_travel.get("void_access")) or not FreeFlight.Campaign.supported(bindings.mido_travel,cursor)):return reject("The station save requires its supported Void source chapter")
	if data.version==9 and (not Dekato.station_supported(bindings,cursor,data.station.loadout.station_id) or not Contracts.VoidAccess.parameters(bindings.mido_travel.get("void_access"))):return reject("The station save requires its supported supplemental chapter")
	if data.version==10 and not Nehma.station_supported(bindings,cursor,data.station.loadout.station_id):return reject("The station save requires its sourced onward chapter")
	if data.version==12 and not _expansion_station(bindings,data.station):return reject("The station save requires a docked expansion story career")
	var contracts:=_career(bindings,cat,data.career,owned,locations,cursor,continuation)
	if contracts==null:return null
	var saved: Dictionary=data.station
	var inventory: Dictionary=owned.snapshot();var career: Dictionary=contracts.snapshot()
	if not _identity(saved,bindings) or saved.get("campaign_cursor")!=cursor or saved.get("phase")!="free_play_required" or saved.get("acknowledged")!=true or saved.get("alioth_return_acknowledged")!=true:return reject("The save has not reached an acknowledged ordinary station")
	if saved.get("loadout")!=inventory.loadout or saved.get("cargo")!=inventory.cargo or saved.get("progress")!=career.progress or saved.get("completed_side_missions")!=career.completed_side_missions:return reject("The saved station differs from its inventory or career")
	if not saved.get("mission") is Dictionary:return reject("The saved station has no campaign mission")
	var mission_supported:=FreeNavigation.destination_supported(bindings,cursor,saved.mission,int(inventory.loadout.station_id))
	if data.version==9:mission_supported=Dekato.station_mission(bindings,cursor,inventory.loadout.station_id,saved.mission)
	if data.version==10:mission_supported=Nehma.station_mission(bindings,cursor,inventory.loadout.station_id,saved.mission)
	if data.version==12:mission_supported=Valkyrie.saved_mission(cursor,saved.mission)
	if continuation!=null and data.version==11:mission_supported=StationContext.permits(bindings,cursor,inventory.loadout.station_id,continuation) and saved.mission==continuation.snapshot().mission
	if not mission_supported or not FreeFlight.response_flags(bindings,saved.get("station_response_flags",{})):return reject("The saved station has an unsupported story or response state")
	if saved.get("source_ship_configuration")!=int(bindings.station_entry.source_ship_configuration) or saved.get("display_ship_configuration")!=int(bindings.station_entry.display_ship_configuration) or saved.get("source_marked_item_ids")!=[]:return reject("The station's ship presentation disagrees with its content")
	if not saved.get("language") is String or not Numbers.integer(saved.get("line_index"),0,128) or not Numbers.integer(saved.get("flight_elapsed_ms"),0,2147483647):return reject("The station has invalid retained conversation or flight metadata")
	for key in ["return_visit","delivery_acknowledged","mining_completed","alioth_return","local_visit","contract_station","local_visit_acknowledged"]:
		if saved.has(key) and not saved[key] is bool:return reject("Invalid station acknowledgement flag")
	# Imported JSON IDs are numbers; native archive coordinates remain integers.
	var expected_course:={}
	if data.version==4:
		var source_course: Dictionary=bindings.mido_travel.kappa_return.conversations[-1].next_course
		for key in source_course:expected_course[key]=int(source_course[key])
	if not saved.get("reward_credits") is int:return reject("The saved story reward is not an integer")
	if saved.has("next_course"):
		if not saved.next_course is Dictionary:return reject("The saved campaign course is not a coordinate record")
		for key in expected_course:
			if not saved.next_course.get(key) is int:return reject("The saved campaign course has an invalid coordinate")
	if saved.get("reward_credits")!=0 and continuation==null and not _expansion:
		var reward: Dictionary={} if data.version!=4 else bindings.mido_travel.kappa_return.conversations[-1]
		if data.version in [7,8] and cursor==32:reward=FreeFlight.Campaign.dialogue_rules(bindings,31,FreeFlight.Campaign.mission(bindings.mido_travel,31),true)
		if reward.is_empty() or cursor!=int(reward.next_cursor) or inventory.loadout.station_id!=int(reward.mission.station_id) or saved.get("reward_credits")!=int(reward.reward_credits):return reject("The acknowledged station retains an unknown story reward")
		if data.version==4 and saved.get("next_course")!=expected_course:return reject("The acknowledged station lost its paid destination")
	if saved.has("campaign_conversation") and saved.campaign_conversation!=false:return reject("Acknowledge the saved campaign conversation before loading")
	if saved.has("next_course"):
		var course: Dictionary=bindings.mido_travel.kappa_return.conversations[-1]
		if cursor!=int(course.next_cursor) or saved.next_course!=expected_course or saved.get("reward_credits")!=int(course.reward_credits) or inventory.loadout.station_id!=int(course.mission.station_id):return reject("The saved campaign course differs from its acknowledged destination or payment")
	if saved.has("cargo_cache_stale") and (not saved.cargo_cache_stale is bool or saved.cargo_cache_stale!=inventory.cargo_cache_stale):return reject("The station cargo cache differs from its retained inventory")
	if saved.has("hangar_open") and saved.hangar_open!=false:return reject("Close the saved station's hangar before loading")
	if not _player_cache(bindings,cat,saved.get("player_cache"),inventory.loadout,cursor):return null
	var station:=Station.new()
	station._state=saved.duplicate(true);station._rules=bindings.station_entry.duplicate(true)
	station._progress_rules=bindings.opening_handoff.duplicate(true)
	station._equipment=owned;station._contracts=contracts
	station._mission_station_context=continuation
	if saved.get("alioth_return",false):
		station._return_rules=load("res://src/content/ordinary_flight_definitions.gd").station_return(bindings,17)
		station._local_rules=bindings.mido_travel.alioth_return.duplicate(true)
		station._lines=station._read_lines(bindings,library,station._return_rules.events)
		if station._lines.is_empty():return reject(station.error)
		if saved.line_index!=station._lines.size()-1:return reject("The saved Alioth conversation is not acknowledged through its final line")
	else:
		station._return_rules=Dekato.docking(bindings) if data.version==9 else FreeFlight.docking(bindings,int(inventory.loadout.station_id),39 if data.version in [10,12] else cursor)
		if saved.line_index!=0:return reject("An ordinary station retained an unknown conversation")
	if data.version==9 and not contracts.retain_dekato_station(bindings,owned,saved.dekato_source_receipt):return reject(contracts.error)
	station._state.language=library.active_language
	restored_locations=locations
	return station

func _inventory(bindings: RefCounted,cat: RefCounted,data: Dictionary) -> RefCounted:
	var equipment:=_inventory_base(bindings,cat,data)
	if equipment==null:return null
	var seed: Dictionary=data.loadout;var hold: Dictionary=data.cargo
	if Shopping.location(bindings,cat,seed.station_id).is_empty() or not data.get("prices") is Dictionary:return reject("The saved inventory has no supported market or prices")
	if data.get("training_inventory_released")!=true or data.get("prototype_drill_replaced")!=true or data.get("protected_item_ids")!=[]:return reject("The save lost its earned equipment transitions")
	if not seed.has("ship_instance") and data.get("ship_affiliation")!=int(bindings.mido_travel.alioth_return.next_player_ship_affiliation):return reject("The save lost its earned ship affiliation")
	if not equipment.cargo_cache_valid():return reject(equipment.error)
	if data.has("stored_ship"):
		var stored: Variant=data.stored_ship
		if not stored is Dictionary or stored.size()!=3 or not stored.get("loadout") is Dictionary or not stored.get("cargo") is Dictionary or not stored.get("prices") is Dictionary:return reject("The save has an invalid ship waiting for its owner")
		if not _identity(stored.loadout,bindings) or not preload("res://src/simulation/mission_context.gd").base_player_hull(bindings,stored.loadout.get("ship_id")) or stored.cargo.get("ship_id")!=stored.loadout.ship_id:return reject("The stored ship belongs to another content or hull")
		if not stored.loadout.get("slots") is Array or not stored.cargo.get("entries") is Array or not _price_list(stored.prices.get("installed"),stored.loadout.slots) or not _price_list(stored.prices.get("cargo"),stored.cargo.entries):return reject("The stored ship lost its installed items, cargo or prices")
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
		if not row is Dictionary or row.size()!=4 or not Numbers.integer(row.get("item_id"),0,cat.tables.items.size()-1) or not Numbers.integer(row.get("slot"),0,254) or not Numbers.integer(row.get("category"),0,3) or not row.get("quantity") is int or not Numbers.integer(row.quantity,1,2147483647):return reject("The saved ship contains an invalid installed slot")
		# Only ammunition uses installed stacks. Reassembly still verifies
		# the catalogue category, slot position and exact ordered loadout.
		if row.category!=1 and row.quantity!=1:return reject("The saved ship contains an invalid installed quantity")
		installed.append({"item_id":row.item_id,"slot":row.slot,"quantity":row.quantity})
	var loadout:=Loadout.new()
	if not loadout.assemble({"ship_id":seed.ship_id,"station_id":seed.station_id,"equipment":installed,"item_category_value_index":int(bindings.station_equipment.item_category_value_index)},cat,bindings.base_content_id,bindings.binding_id):return reject(loadout.error)
	var expected:=loadout.snapshot()
	if seed.has("ship_instance"):
		if data.has("ship_affiliation") or not preload("res://src/simulation/ship_instance.gd").valid(seed.ship_instance) or not preload("res://src/simulation/mission_context.gd").base_player_hull(bindings,seed.ship_id):return reject("The save contains invalid ship ownership")
		expected.ship_instance=seed.ship_instance.duplicate(true)
	if expected!=seed:return reject("The saved slots disagree with the original ship and item catalogues")
	if hold.get("ship_id")!=seed.ship_id or hold.get("capacity")!=Stats.cargo_capacity(bindings,cat,seed):return reject("Saved cargo capacity disagrees with the equipped ship")
	if not Numbers.integer(data.get("transactions"),0,2147483647) or not Numbers.integer(data.get("credit_delta"),-2147483648,2147483647):return reject("The inventory has an invalid transaction counter")
	if data.has("stock_station_id") and not Numbers.integer(data.stock_station_id,0,cat.tables.stations.size()-1):return reject("The inventory's last quote names an unknown station")
	if not _stock_rows(data.get("stock"),cat.tables.items.size(),true):return reject("Invalid retained inventory stock")
	var equipment:=Equipment.new()
	equipment._rules=bindings.station_equipment.duplicate(true);equipment._state=data.duplicate(true)
	equipment._completion_prices=Equipment.prototype_prices(bindings,cat)
	equipment._catalogue_size=cat.tables.items.size()
	if equipment._completion_prices.is_empty():return reject("The source inventory prices are unavailable")
	for item in cat.tables.items:equipment._items[int(item.id)]=Equipment._item_metadata(cat,int(item.id),equipment._rules)
	equipment._counts.append_array(Loadout.slot_counts(cat.tables.ships[seed.ship_id].stats,seed))
	equipment._mission_cargo_id=int(bindings.early_contracts.courier.cargo_item_id)
	equipment._recovery_cargo_ids=Equipment.RecoveryRules.cargo_marker_ids(bindings)
	return equipment

func _locations(bindings: RefCounted,cat: RefCounted,library: RefCounted,data: Variant,station_context: RefCounted=null) -> RefCounted:
	if not data is Dictionary or data.size()!=8 or not _identity(data,bindings) or not data.get("locations") is Array:return reject("The save has no valid station cache")
	var cache:=Locations.new()
	if not cache.configure(bindings):return reject(cache.error)
	if not Numbers.integer(data.get("capacity"),1,3) or data.capacity!=cache.snapshot().capacity or not Numbers.integer(data.get("current_station_id"),0,cat.tables.stations.size()-1) or data.locations.is_empty() or data.locations.size()>data.capacity or not Navigation.valid_availability(bindings.early_contracts.base_navigation,data.get("system_availability")):return reject("Invalid retained station count or system availability")
	var random:=Random.new()
	if not random.restore(data.get("random")):return reject(random.error)
	for index in data.locations.size():
		var row: Variant=data.locations[index]
		if not _keys(row,["station_id","population","offers","stock","market_items","market_ships","requested_offers","medal_progress","purchased_goods","dialogues","used_diplomats"]) or not row.get("population") is Dictionary or not row.get("offers") is Dictionary or not row.get("medal_progress",{}) is Dictionary:return reject("Invalid saved lounge entry")
		var stock:=Stock.new();var contacts:=Contacts.new()
		var generation_context: RefCounted=null if station_context==null else station_context.historical(bindings,row.population.get("context",{}).get("campaign_cursor"))
		if not stock.restore(bindings,cat,row.get("stock")) or not contacts.restore(bindings,cat,library,row.population,generation_context):return reject(stock.error+contacts.error)
		if row.get("station_id")!=row.population.context.station_id:return reject("The cached lounge names another station")
		# Requested jobs can change history between visits to any cached lounge.
		# Each population and request is independently checked from its inputs.
		cache._state.history=row.population.initial_history.duplicate()
		if not cache.remember(contacts,stock,row.get("medal_progress",{})):return reject(cache.error)
		if row.has("requested_offers"):
			if not row.requested_offers is Dictionary or not cache.restore_requested_offers(bindings,cat,int(row.station_id),row.requested_offers,generation_context):return reject(cache.error if row.requested_offers is Dictionary else "Invalid saved requested offers")
		if row.has("dialogues") and not cache.restore_dialogues(bindings,cat,library,int(row.station_id),row.dialogues):return reject(cache.error)
		var generated: Dictionary=cache.location(row.station_id)
		if row.offers.size()!=generated.offers.size():return reject("The saved lounge changed its generated contacts")
		for id in generated.offers:
			var offer: Variant=row.offers.get(id)
			if not offer is Dictionary or offer.size()!=2 or offer.get("offer")!=generated.offers[id].offer or not offer.get("consumed") is bool:return reject("The saved contact changed its original offer")
			if offer.consumed and not cache.consume(row.station_id,id):return reject(cache.error)
		if row.has("purchased_goods"):
			if not row.purchased_goods is Array or row.purchased_goods.is_empty() or row.purchased_goods.size()>row.population.contacts.size():return reject("Invalid purchased lounge goods")
			for id in row.purchased_goods:
				var captain: bool=row.population.contacts.any(func(contact):return contact.contact_id==id and contact.get("role")==6)
				if not id is int or not (cache.consume_kaamo(row.station_id,id) if not cache.kaamo_contact(row.station_id,id).is_empty() else cache.consume_wingmen(row.station_id,id) if captain else cache.consume_goods(row.station_id,id)):return reject("The saved purchase lost its merchant or was repeated")
		if row.has("used_diplomats"):
			if not row.used_diplomats is Dictionary or row.used_diplomats.is_empty() or row.used_diplomats.size()>row.population.contacts.size():return reject("Invalid saved diplomat services")
			for id in row.used_diplomats:
				var response: Variant=row.used_diplomats[id]
				if not id is int or not response is int or response<843 or response>845 or not cache.consume_diplomat(row.station_id,id,response):return reject("The saved service lost its diplomat or response")
		if row.has("market_items"):
			if not Shopping.valid_stock(row.market_items,cat.tables.items.size()):return reject("Invalid mutable station stock")
			cache._state.locations.back().market_items=row.market_items.duplicate(true)
		if row.has("market_ships"):
			if not preload("res://src/simulation/ship_instance.gd").valid_offers(row.market_ships,cat):return reject("Invalid retained ship market")
			cache._state.locations.back().market_ships=row.market_ships.duplicate(true)
	if not data.get("history") is Array or data.history.size()!=int(bindings.early_contracts.generation.mission_history.size) or not data.history.all(func(value):return value is bool) or cache.location(data.get("current_station_id",-1)).is_empty():return reject("The saved station cache lost its history or current location")
	cache._read={};cache._state.history=data.history.duplicate()
	cache._state.current_station_id=data.current_station_id;cache._state.random=random.snapshot()
	cache._state.system_availability=data.system_availability.duplicate()
	if cache.snapshot()!=data:return reject("The saved location cache differs from its validated entries")
	return cache

func _career(bindings: RefCounted,cat: RefCounted,data: Dictionary,equipment: RefCounted,locations: RefCounted,cursor: int=18,station_context: RefCounted=null) -> RefCounted:
	var dekato: bool=Dekato.station_supported(bindings,cursor,data.get("station_id"))
	var onward: bool=Nehma.station_supported(bindings,cursor,data.get("station_id"))
	var continuation:=StationContext.permits(bindings,cursor,data.get("station_id"),station_context)
	var expansion: bool=_expansion and Valkyrie.saved_story(bindings,cursor)
	if (cursor not in [13,14,16] and not FreeFlight.Campaign.supported(bindings.mido_travel,cursor) and not dekato and not onward and not continuation and not expansion) or not _identity(data,bindings) or data.get("campaign_cursor")!=cursor or data.get("station_id")!=equipment.snapshot().loadout.station_id or data.get("station_id")!=locations.snapshot().current_station_id:return reject("The saved career belongs to another station")
	if not Difficulty.valid(data.get("difficulty")) or not data.get("difficulty") is float or not data.get("progress") is Dictionary or not Reputation.valid_state(data.get("reputation")):return reject("The saved difficulty or career is invalid")
	var progress: Dictionary=data.progress
	if data.has("wingmen"):
		if not Contracts.Wingmen.valid_state(data.wingmen,bindings):return reject("The saved wingman contract is invalid")
		if not data.wingmen.active.is_empty() and data.wingmen.active.station_id>=cat.tables.stations.size():return reject("The saved wingmen have no hiring station")
	if not Opening.new().valid_progress(self,bindings,progress,cursor):return null
	if (dekato or onward or continuation or expansion or FreeFlight.Campaign.supported(bindings.mido_travel,cursor)) and progress.size()!=9+int(progress.has("mining_failure_hint_seen"))+int(progress.has("cargo_recovered"))+int(progress.has("asteroids_destroyed"))+int(progress.has("mined_ore_tons"))+int(progress.has("mined_cores"))+int(progress.has("mined_ore_types_mask"))+int(progress.has("mined_core_types_mask"))+int(progress.has("nuclear_bomb_detonations"))+int(progress.has("purchased_booze_quantity"))+int(progress.has("booze_types_mask"))+int(progress.has("story_stations_mask"))+int(progress.has("story_counter"))+int(progress.has("wanted"))+int(progress.has("nag_heard"))+int(progress.has("hints_seen"))+int(progress.has("kaamo_state"))+int(progress.has("kaamo_storage"))+int(progress.has("pirate_bases"))+int(progress.has("loma_toll"))+int(progress.has("bar_heard")):return reject("The saved unlocked career lacks its counters")
	var earned:=Career.calculate_progress(bindings.opening_handoff,cursor,progress.player_kills,progress.pirate_kills,progress.other_score)
	if earned.is_empty() or progress.get("reputation")!=data.reputation or data.get("rank")!=earned.rank:return reject("The saved rank or faction standing disagrees with its career")
	for key in earned:
		if progress.get(key)!=earned[key]:return reject("The saved career disagrees with its earned counters")
	for key in ["credits","passengers","completed_side_missions","result_serial"]:
		if not Numbers.integer(data.get(key),0,2147483647):return reject("The saved wallet or contract counter is invalid")
	if data.has("conversations") and not Numbers.integer(data.conversations,0,2147483647):return reject("The saved conversation count is invalid")
	if data.has("medal_notices") and not Locations.Medals.valid_notices(data.medal_notices):return reject("The saved medal notices are invalid")
	if data.has("stats") and not Locations.Medals.valid_stats(data.stats):return reject("The saved career stats are invalid")
	if data.has("elite_medals") and not preload("res://src/simulation/elite_medal_progress.gd").valid_earned(data.elite_medals):return reject("The saved add-on medals are invalid")
	if data.has("rejected_jobs") and not Numbers.integer(data.rejected_jobs,0,2147483647):return reject("The saved refused-job count is invalid")
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
		if data.passengers!=0 or data.active_offer_id!=-1 or not data.accepted_contact.is_empty() or data.has("contract_phase") or data.has("station_outcome"):return reject("The empty contract slot retains passengers, a client or a continuation")
	else:
		var contact: Dictionary=data.accepted_contact
		if not _keys(contact,["offer_id","station_id","offer","name","portrait"]) or contact.size()!=5 or not Numbers.integer(contact.get("offer_id"),0,4095) or contact.offer_id!=data.get("active_offer_id") or not contact.get("name") is String or not contact.get("portrait") is Dictionary:return reject("The accepted contract lost its original client")
		var offer:=Offer.new()
		if not offer.restore(bindings,cat,contact.get("offer")):return reject(offer.error)
		# Capture retains an independent job accepted before leaving Mido. It
		# neither re-accepts it at Alioth nor changes its original generated terms.
		var accepted_cursor:=mini(cursor,int(bindings.early_contracts.last_cursor)) if cursor<18 else cursor
		# Validate the independently carried earlier job at its already supported
		# preceding stage. This grants no new39 acceptance or flight capability.
		if dekato:accepted_cursor=int(Dekato.declarations(bindings).mission.campaign_cursor)
		if onward:accepted_cursor=int(Nehma.declarations(bindings).mission.campaign_cursor)
		# Expansion careers carry jobs quoted under the finished main career's
		# free-play rules.
		if expansion:accepted_cursor=mini(int(offer.snapshot().context.get("campaign_cursor",-1)),Valkyrie.FIRST_CURSOR)
		if continuation:
			# The accepted job keeps its original quotation, not permission to
			# accept a different job at the new station-only campaign stage.
			var quoted: Variant=offer.snapshot().context.get("campaign_cursor")
			var quote_limit: int=cursor if station_context.completed_career(bindings) else station_context.snapshot().source_cursor
			if not Numbers.integer(quoted,0,quote_limit):return reject("The carried job has no preceding quotation context")
			accepted_cursor=quoted
		if not Contracts.ContractProgress.matches(data,offer.snapshot(),cat) or not Contracts.acceptance_supported(bindings.early_contracts,accepted_cursor,offer.snapshot(),bindings) or contact.station_id!=offer.snapshot().context.station_id:return reject("The accepted contract changed its generated terms")
		# The three-location FIFO may have evicted and regenerated this station.
		# Its current contact IDs then name new offers. Restore the independently
		# retained accepted terms above; cached offers/consumption belong to their
		# own validated population and must not be joined by station and row ID.
		var passengers: int=Contracts.ContractProgress.occupied_passengers(data)
		if data.passengers!=passengers or passengers>Contracts.passenger_capacity(Contracts.cabin_catalogue(cat,bindings.early_contracts.acceptance),equipment.snapshot().get("stored_ship",{}).get("loadout",equipment.snapshot().loadout)):return reject("The accepted passengers disagree with their mission or installed berths")
	var career:=Contracts.new()
	career._state=data.duplicate(true);career._rules=bindings.early_contracts.duplicate(true)
	career._cabins=Contracts.cabin_catalogue(cat,bindings.early_contracts.acceptance)
	career._progress_rules=bindings.opening_handoff.duplicate(true)
	career._stations=cat.tables.systems[int(bindings.early_contracts.system_id)].station_ids.duplicate()
	career._lounges=locations
	career._station_context=station_context
	career._state.erase("void_source")
	career._state.erase("blueprints")
	if not career.restore_void_career(bindings,cat,data.get("void_source"),data.get("blueprints")):return reject(career.error)
	if data.has("base_medals"):
		if not Locations.Medals.valid_retained(data.base_medals,data,career.blueprint_state()):return reject("The saved medals disagree with the earned native career")
	elif not career.settle_base_medals():return reject(career.error)
	if FreeFlight.Campaign.supported(bindings.mido_travel,cursor) and career.retained_station_context(bindings,data.station_id).is_empty():return reject(career.error)
	if onward and cursor==int(Nehma.declarations(bindings).mission.campaign_cursor) and career.retained_station_context(bindings,data.station_id).is_empty():return reject(career.error)
	if cursor in [13,14] and career.flight_context(data.station_id,bindings).is_empty():return reject(career.error)
	return career

func _player_cache(bindings: RefCounted,cat: RefCounted,value: Variant,loadout: Dictionary,cursor: int=18) -> bool:
	if not value is Dictionary or not _identity(value,bindings) or not value.get("equipment_ids") is Array:return _invalid("The station lost its retained player pools")
	# A station fit can change installed IDs after the arrival cache was captured.
	var seed:=_arrival_loadout(loadout,value)
	if not Numbers.integer(seed.get("ship_id"),0,cat.tables.ships.size()-1):return _invalid("The arriving player cache names an unknown hull")
	for id in seed.equipment_ids:
		if not Numbers.integer(id,0,cat.tables.items.size()-1):return _invalid("The saved player cache contains an unknown item")
	if not Cache.matches(value,seed,cursor) or value.values.hull==0:return _invalid("The save has no viable station player cache")
	return true

static func _arrival_loadout(loadout: Dictionary,arrival: Dictionary) -> Dictionary:
	# Equipment fitting and hull exchanges leave the actual arrival untouched.
	# Location/content identity still belongs to the current station.
	if not arrival.get("equipment_ids") is Array:return {}
	var seed:=loadout.duplicate(true)
	seed.ship_id=arrival.get("ship_id",-1)
	seed.equipment_ids=arrival.equipment_ids.duplicate()
	return seed

func _continuation_station(bindings: RefCounted,state: Dictionary,context: RefCounted) -> bool:
	if not Dekato.source_receipt_matches(bindings,state.get("dekato_source_receipt")) or not Nehma.source_receipt_matches(bindings,state.get("nehma_source_receipt")):return _invalid("The mission station lost its explicit content sources")
	if not state.get("loadout") is Dictionary or not state.get("arrival_player") is Dictionary:return _invalid("The mission station lost its arriving player or equipment")
	var destination: Dictionary=context.snapshot();var seed: Dictionary=state.loadout;var player: Dictionary=state.arrival_player
	if state.has("docking") and context.completed_career(bindings):
		if not _identity(state,bindings) or not StationContext.permits(bindings,state.get("campaign_cursor"),seed.get("station_id"),context) or state.get("mission_station_return")!=destination or state.get("mission")!=destination.mission:return _invalid("The docked career lost its completed campaign history")
		return _ordinary_docked_station(bindings,state,int(destination.campaign_cursor)) or _invalid("The completed career lost its actual docking or player cache")
	if not StationContext.permits(bindings,state.get("campaign_cursor"),seed.get("station_id"),context) or seed.get("system_id")!=destination.system_id:return _invalid("The mission station differs from its admitted destination")
	if not _identity(state,bindings) or state.get("mission_station_return")!=destination or state.get("mission")!=destination.mission or state.get("reward_credits")!=destination.get("reward_credits",0) or state.get("phase")!="free_play_required" or state.get("line_index")!=0:return _invalid("The mission station changed its acknowledged result or reward")
	for key in ["return_visit","local_visit","contract_station","local_visit_acknowledged","acknowledged","alioth_return_acknowledged"]:
		if state.get(key)!=true:return _invalid("The mission station lost acknowledgement: "+key)
	if player.get("campaign_cursor")!=destination.source_cursor or not state.get("flight_elapsed_ms") is int:return _invalid("The mission station changed its arriving flight cursor or clock")
	var recipe:=StationContext.Recipe.select(bindings,destination.source_cursor)
	if state.flight_elapsed_ms<=recipe.result.success.after_ms:return _invalid("The mission station preceded its normal-space result")
	# The admitted station loadout owns location. Arrival equipment and pools
	# remain historical after a station refit; current inventory is separate.
	if not Cache.valid_seed(seed):return _invalid("The mission station has an invalid equipment identity")
	var arrival_seed:=_arrival_loadout(seed,player)
	if not Cache.valid_seed(arrival_seed):return _invalid("The mission station lost its arrival equipment identity")
	var cached:=Cache._capture_arrival(bindings.mido_travel,arrival_seed,arrival_seed,player)
	if cached.is_empty():return _invalid("The mission station lost its living player pools")
	cached.campaign_cursor=destination.campaign_cursor
	if cached!=state.get("player_cache") or not Cache.matches(cached,arrival_seed,destination.campaign_cursor):return _invalid("The mission station cache differs from its arriving player")
	return true

func _dekato_station(bindings: RefCounted,state: Dictionary) -> bool:
	if not Dekato.source_receipt_matches(bindings,state.get("dekato_source_receipt")) or not _identity(state,bindings):return false
	for key in ["loadout","mission","player_cache","arrival_player","docking"]:
		if not state.get(key) is Dictionary:return false
	var seed: Dictionary=state.loadout;var player: Dictionary=state.arrival_player;var dock: Dictionary=state.docking
	if not Dekato.station_mission(bindings,state.get("campaign_cursor"),seed.get("station_id"),state.mission) or seed.get("system_id")!=int(Dekato.declarations(bindings).mission.system_id):return false
	if state.get("phase")!="free_play_required" or state.get("line_index")!=0 or state.get("reward_credits")!=0 or state.get("alioth_return",false)!=false:return false
	for key in ["return_visit","local_visit","contract_station","local_visit_acknowledged","acknowledged","alioth_return_acknowledged"]:
		if not state.get(key) is bool or state[key]!=true:return false
	if player.get("campaign_cursor")!=int(Dekato.declarations(bindings).mission.campaign_cursor) or not player.get("campaign_cursor") is int:return false
	if not _keys(dock,["station_id","pre_motion_contact","post_motion_volume_index","position"]) or dock.size()!=4 or not dock.get("station_id") is int or dock.station_id!=seed.station_id or not dock.get("pre_motion_contact") is bool or not dock.get("post_motion_volume_index") is int or not dock.get("position") is Vector3:return false
	if not dock.position.is_finite() or (not dock.pre_motion_contact and dock.post_motion_volume_index<0):return false
	var arrival_seed:=_arrival_loadout(seed,player)
	var cached: Dictionary=Cache.station_arrival_cache(Dekato.docking(bindings),arrival_seed,player)
	return not cached.is_empty() and cached==state.player_cache and Cache.matches(state.player_cache,arrival_seed,39) and cached.values.hull>0

## An expansion story career docked at an ordinary station after its flight.
func _expansion_station(bindings: RefCounted,state: Dictionary) -> bool:
	var cursor: Variant=state.get("campaign_cursor")
	if not Valkyrie.saved_story(bindings,cursor) or not state.get("mission") is Dictionary or not Valkyrie.saved_mission(cursor,state.mission):return false
	var flight: Variant=state.get("arrival_player",{}).get("campaign_cursor") if state.get("arrival_player") is Dictionary else null
	if not flight is int or flight<39 or flight>cursor:return false
	# The last story payment is shown once; it is not part of the docked boundary.
	var docked: Dictionary=state.duplicate();docked.reward_credits=0;docked.line_index=0
	if not state.has("docking"):
		# A finished main career takes the first call at its final story station.
		var seed: Dictionary=state.get("loadout",{})
		if state.get("phase")!="free_play_required" or state.get("acknowledged")!=true or not state.get("player_cache") is Dictionary or load("res://src/content/ordinary_world_definitions.gd").location(bindings,int(seed.get("station_id",-1))).is_empty():return false
		return Cache.matches(state.player_cache,_arrival_loadout(seed,state.arrival_player),cursor) and state.player_cache.values.hull>0
	return _ordinary_docked_station(bindings,docked,flight)

func _onward_station(bindings: RefCounted,state: Dictionary) -> bool:
	if not Dekato.source_receipt_matches(bindings,state.get("dekato_source_receipt")) or not Nehma.source_receipt_matches(bindings,state.get("nehma_source_receipt")) or not _identity(state,bindings):return false
	for key in ["loadout","mission","player_cache","arrival_player","docking"]:
		if not state.get(key) is Dictionary:return false
	var seed: Dictionary=state.loadout
	var cursor: Variant=state.get("campaign_cursor")
	if not Nehma.station_mission(bindings,cursor,seed.get("station_id"),state.mission):return false
	if cursor==39 and seed.station_id==int(Nehma.declarations(bindings).mission.station_id):return false
	if cursor==40 and state.get("campaign_conversation")!=false:return false
	return _ordinary_docked_station(bindings,state,39)

func _ordinary_docked_station(bindings: RefCounted,state: Dictionary,flight_cursor: int) -> bool:
	for key in ["loadout","player_cache","arrival_player","docking"]:
		if not state.get(key) is Dictionary:return false
	var seed: Dictionary=state.loadout;var player: Dictionary=state.arrival_player;var dock: Dictionary=state.docking
	var cursor: Variant=state.get("campaign_cursor")
	for key in ["line_index","reward_credits"]:
		if not state.get(key) is int or state[key]!=0:return false
	var world: Dictionary=load("res://src/content/ordinary_world_definitions.gd").location(bindings,int(seed.station_id))
	if world.is_empty() or not seed.get("system_id") is int or seed.system_id!=int(world.system_id):return false
	if state.get("phase")!="free_play_required" or state.get("line_index")!=0 or state.get("reward_credits")!=0 or state.get("alioth_return",false)!=false:return false
	for key in ["return_visit","local_visit","contract_station","local_visit_acknowledged","acknowledged","alioth_return_acknowledged"]:
		if not state.get(key) is bool or state[key]!=true:return false
	if not player.get("campaign_cursor") is int or player.campaign_cursor!=flight_cursor:return false
	if not _keys(dock,["station_id","pre_motion_contact","post_motion_volume_index","position"]) or dock.size()!=4 or not dock.get("station_id") is int or dock.station_id!=seed.station_id or not dock.get("pre_motion_contact") is bool or not dock.get("post_motion_volume_index") is int or not dock.get("position") is Vector3:return false
	if not dock.position.is_finite() or (not dock.pre_motion_contact and dock.post_motion_volume_index<0):return false
	# Acknowledgement advances the career/cache, not the surviving flight. The
	# original living player and docking contact retain their arriving flight.
	var arrival_seed:=_arrival_loadout(seed,player)
	var cached: Dictionary=Cache.station_arrival_cache(FreeFlight.docking(bindings,int(seed.station_id),flight_cursor),arrival_seed,player)
	if cached.is_empty():return false
	cached.campaign_cursor=cursor
	return cached==state.player_cache and Cache.matches(state.player_cache,arrival_seed,cursor) and cached.values.hull>0

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
