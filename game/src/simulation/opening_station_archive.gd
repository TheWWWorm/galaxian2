extends RefCounted
## Version 2 adds acknowledged opening stations. Version 1 remains the ordinary
## career format. Rebuild rules from the selected content, never from a save.
const Station=preload("res://src/simulation/station_entry.gd")
const Equipment=preload("res://src/simulation/station_equipment.gd")
const Loadout=preload("res://src/simulation/opening_loadout.gd")
const Ordinary=preload("res://src/content/ordinary_flight_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Career=preload("res://src/simulation/opening_handoff.gd")
const Reputation=preload("res://src/simulation/faction_reputation.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const CareerStations=preload("res://src/simulation/campaign_station_archive.gd")
const PHASES={2:"ready_to_launch",4:"ready_to_launch",6:"station_equipment_required",7:"combat_departure_required",10:"local_departure_required",11:"local_departure_required",12:"local_departure_required",13:"contracts_required",14:"convoy_departure_required",16:"alioth_departure_required"}
const EXTRA_KEYS=["rescue_disposition","equipment_conversation","equipment_acknowledged","training_return","training_return_acknowledged","station_reloaded","local_conversation","local_conversation_acknowledged","contract_conversation","contract_conversation_acknowledged","convoy_arrival","alioth_conversation_acknowledged"]
const INVENTORY_BASE=["loadout","stock","cargo","cargo_cache_stale","credit_delta","transactions"]
const PROGRESS_KEYS=["campaign_cursor","rank","rank_score","player_kills","pirate_kills","other_score","reputation","debris_destroyed","capital_ship_kills"]

static func accepts(state: Dictionary) -> bool:
	if state.get("campaign_cursor")==13:
		var mission: Variant=state.get("mission")
		if not mission is Dictionary or not Numbers.integer(state.get("completed_side_missions"),0,2147483647) or not Numbers.integer(mission.get("completed_contract_target"),1,2147483647):return false
		if state.completed_side_missions>=mission.completed_contract_target:return false
	return PHASES.has(state.get("campaign_cursor")) and state.get("phase")==PHASES[state.campaign_cursor] and state.get("acknowledged")==true and not state.get("hangar_open",false) and not state.get("lounge_open",false)

func capture(a: RefCounted,station: RefCounted,bindings: RefCounted,locations: RefCounted) -> Dictionary:
	if not accepts(station.snapshot()):return a.fail("Finish the opening station conversation and close its panels before saving")
	if station.snapshot().campaign_cursor>=13:return a._capture_career(station,bindings,2)
	if station.contract_owner()!=null:return a.fail("The early opening station has an unexpected contract career")
	if locations==null:return a.fail("The opening station has no retained locations")
	var equipment: RefCounted=station.equipment_owner()
	var inventory: Dictionary={} if equipment==null else equipment.snapshot()
	inventory.erase("requirements")
	return {"format":"gof2-native-station","version":2,"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"station":station._state.duplicate(true),"inventory":inventory,"career":{},"locations":locations.snapshot()}

func restore(a: RefCounted,bindings: RefCounted,cat: RefCounted,library: RefCounted,data: Dictionary) -> RefCounted:
	if not a._keys(data.get("station"),a.STATION_KEYS+EXTRA_KEYS) or not data.get("inventory") is Dictionary or not data.get("career") is Dictionary:return a.reject("Invalid opening station fields")
	var saved: Dictionary=data.station
	if not accepts(saved) or not saved.campaign_cursor is int or not a._identity(saved,bindings):return a.reject("The save has no acknowledged opening checkpoint")
	var cursor: int=saved.campaign_cursor
	if not a._required(saved,["loadout","progress","mission","language","line_index","source_ship_configuration","display_ship_configuration","source_marked_item_ids","reward_credits","mining_completed"]):return a.reject("The opening checkpoint is incomplete")
	if not saved.loadout is Dictionary or not saved.mission is Dictionary or not saved.language is String or not Numbers.integer(saved.line_index,0,128):return a.reject("Invalid opening station metadata")
	if saved.source_ship_configuration!=int(bindings.station_entry.source_ship_configuration) or saved.display_ship_configuration!=int(bindings.station_entry.display_ship_configuration) or saved.reward_credits!=0 or saved.mining_completed!=false:return a.reject("The opening station changed its ship or story reward")
	for key in a.STATION_KEYS+EXTRA_KEYS:
		if saved.has(key) and (key.ends_with("acknowledged") or key in ["return_visit","alioth_return","local_visit","contract_station","hangar_open","cargo_cache_stale","equipment_conversation","training_return","station_reloaded","local_conversation","contract_conversation","convoy_arrival"]):
			if not saved[key] is bool:return a.reject("Invalid opening acknowledgement flag")
	if not valid_progress(a,bindings,saved.progress,cursor):return null
	if cursor>=13:return CareerStations.new().restore(a,self,bindings,cat,library,data)
	if not data.career.is_empty():return a.reject("The early opening checkpoint has an unexpected contract career")
	var locations: RefCounted=a._locations(bindings,cat,library,data.get("locations"))
	if locations==null:return null
	var original:=Loadout.new()
	if not original.configure_station(bindings,cat,bindings.base_content_id):return a.reject(original.error)
	var seed: Dictionary=original.snapshot()
	var station:=Station.new()
	station._state=saved.duplicate(true);station._rules=bindings.station_entry.duplicate(true);station._progress_rules=bindings.opening_handoff.duplicate(true)
	var events: Array
	if cursor==2:
		if not data.inventory.is_empty() or saved.loadout!=seed or saved.has("return_visit") or saved.has("cargo") or saved.has("player_cache"):return a.reject("The first departure changed its replacement ship")
		var rules: Dictionary=bindings.opening_handoff
		var kills: int=saved.progress.player_kills
		var uncertainty:=kills*int(rules.pirate_reputation_change_maximum);var axis:=int(rules.rescue_reputation_axis)
		var disposition:={"actor_hostile":false,"reputation_axis":axis,"minimum":int(rules.initial_reputation[axis])-uncertainty,"maximum":int(rules.initial_reputation[axis])+uncertainty,"override":int(rules.initial_reputation_override)}
		if saved.get("rescue_disposition")!=disposition or kills>3 or saved.progress.pirate_kills!=kills or saved.progress.other_score!=0:return a.reject("The first station lost its rescue progress")
		var mission: Dictionary=bindings.station_entry.mission
		if saved.mission!={"kind":int(mission.next_kind),"station_id":seed.station_id,"reward":0,"bonus":0,"source_parameter":int(mission.next_parameter)}:return a.reject("The first departure changed its mining objective")
		events=bindings.station_entry.dialogue.events
	else:
		if saved.get("return_visit")!=true or not saved.get("cargo") is Dictionary or not Numbers.integer(saved.get("flight_elapsed_ms"),0,2147483647):return a.reject("The opening checkpoint lost its station return")
		if not a._player_cache(bindings,cat,saved.get("player_cache"),saved.loadout,cursor):return null
		if cursor in [4,6,7]:
			station._return_rules=(bindings.station_return if cursor==4 else bindings.full_hold_return).duplicate(true)
			if saved.get("delivery_acknowledged")!=true:return a.reject("The saved mining delivery was not acknowledged")
			events=station._return_rules.events
		else:
			station._return_rules=Ordinary.station_return(bindings,8 if cursor==10 else cursor-1)
			if station._return_rules.is_empty():return a.reject("The saved local visit has no supported return")
			events=station._return_rules.events
			if cursor==10:
				station._local_rules=bindings.mido_travel.conversations[0].duplicate(true)
				events=station._local_rules.events
				if saved.get("training_return_acknowledged")!=true or saved.get("station_reloaded")!=true or saved.get("local_conversation_acknowledged")!=true:return a.reject("The saved station skipped its training follow-up")
			elif saved.get("local_visit_acknowledged")!=true:return a.reject("The saved local visit was not acknowledged")
		if cursor==4 or (cursor==6 and data.inventory.is_empty()):
			if saved.loadout!=seed or not data.inventory.is_empty():return a.reject("Mining changed the replacement inventory")
			var hold: Dictionary=saved.cargo
			var capacity: int=cat.tables.ships[seed.ship_id].stats.cargo_capacity
			var used: int=capacity if cursor==6 else 0
			if hold!={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"ship_id":seed.ship_id,"capacity":capacity,"entries":[],"used":used,"free_space":capacity-used}:return a.reject("The saved delivery changed its cleared cargo cache")
			if cursor==6 and saved.get("cargo_cache_stale")!=true:return a.reject("The second delivery lost its deferred cargo refresh")
		else:
			station._equipment=inventory(a,bindings,cat,data.inventory,cursor)
			if station._equipment==null:return null
			var owned: Dictionary=station._equipment.snapshot()
			if saved.loadout!=owned.loadout or saved.cargo!=owned.cargo or saved.get("cargo_cache_stale",false)!=owned.cargo_cache_stale:return a.reject("The opening station differs from its retained inventory")
			if cursor in [6,7]:
				station._equipment_rules=bindings.station_equipment.duplicate(true)
				station._equipment_lines=station._read_lines(bindings,library,station._equipment_rules.events)
				if station._equipment_lines.is_empty():return a.reject(station.error)
				if cursor==7:events=station._equipment_rules.events
		if cursor==6:
			var rules: Dictionary=station._return_rules
			if saved.mission!={"kind":int(rules.next_mission_kind),"station_id":seed.station_id,"reward":0,"bonus":0,"source_parameter":int(rules.next_mission_parameter)}:return a.reject("The saved delivery skipped its equipment objective")
	if saved.source_marked_item_ids!=(bindings.station_entry.source_marked_item_ids.map(func(id):return int(id)) if cursor<8 else []):return a.reject("The saved station changed its protected items")
	if saved.loadout.get("station_id")!=locations.snapshot().current_station_id:return a.reject("The saved opening station lost its location cache")
	station._lines=station._read_lines(bindings,library,events)
	if station._lines.is_empty():return a.reject(station.error)
	if saved.line_index!=station._lines.size()-1:return a.reject("The opening conversation was not acknowledged through its final line")
	station._state.language=library.active_language
	if cursor!=6 and station.prepare_departure(bindings,cat).is_empty():return a.reject(station.error)
	a.restored_locations=locations
	return station

func valid_progress(a: RefCounted,bindings: RefCounted,data: Variant,cursor: int) -> bool:
	if not a._keys(data,PROGRESS_KEYS) or not a._required(data,PROGRESS_KEYS.slice(0,7)) or not Reputation.valid_state(data.reputation):return a._invalid("The opening checkpoint has invalid career data")
	for key in ["player_kills","pirate_kills","other_score","debris_destroyed","capital_ship_kills"]:
		if data.has(key) and not Numbers.integer(data[key],0,2147483647):return a._invalid("The opening checkpoint has invalid career counters")
	var earned:=Career.calculate_progress(bindings.opening_handoff,cursor,data.player_kills,data.pirate_kills,data.other_score)
	if earned.is_empty():return a._invalid("The opening checkpoint has invalid career progress")
	for key in earned:
		if data.get(key)!=earned[key]:return a._invalid("The opening checkpoint changed its earned rank")
	return true

func inventory(a: RefCounted,bindings: RefCounted,cat: RefCounted,data: Dictionary,cursor: int) -> RefCounted:
	var keys: Array=INVENTORY_BASE if cursor in [6,7] else INVENTORY_BASE+["prices","protected_item_ids","training_inventory_released","prototype_drill_replaced"]
	if not a._keys(data,keys) or not a._required(data,keys):return a.reject("Invalid opening inventory fields")
	var equipment: RefCounted=a._inventory_base(bindings,cat,data)
	if equipment==null:return null
	if not a._required(data.cargo,["entries","used","free_space"]) or not data.cargo.entries is Array or not Numbers.integer(data.cargo.used,0,2147483647) or not data.cargo.free_space is int:return a.reject("The opening inventory has invalid cargo quantities")
	if data.credit_delta!=0 or not data.cargo_cache_stale is bool:return a.reject("The free tutorial changed its wallet or cargo state")
	if cursor in [6,7]:
		var original:=Loadout.new()
		if not original.configure_station(bindings,cat,bindings.base_content_id):return a.reject(original.error)
		var seed: Dictionary=original.snapshot()
		if data.loadout.ship_id!=seed.ship_id or data.loadout.station_id!=seed.station_id or data.stock.size()!=bindings.station_equipment.stock.size():return a.reject("The equipment tutorial changed its ship or offers")
		var totals:={};var expected:={}
		for slot in seed.slots:
			if slot!=null:expected[slot.item_id]=int(expected.get(slot.item_id,0))+1
		for offer in bindings.station_equipment.stock:expected[int(offer.item_id)]=int(expected.get(int(offer.item_id),0))+int(offer.quantity)
		for index in data.stock.size():
			var row: Dictionary=data.stock[index];var offer: Dictionary=bindings.station_equipment.stock[index]
			if row.item_id!=int(offer.item_id) or row.unit_price!=0:return a.reject("The saved tutorial changed its free offers")
			if row.quantity>0:totals[row.item_id]=row.quantity
		for slot in data.loadout.slots:
			if slot!=null:totals[slot.item_id]=int(totals.get(slot.item_id,0))+1
		for row in data.cargo.get("entries",[]):
			if not row is Dictionary or not Numbers.integer(row.get("item_id"),0,cat.tables.items.size()-1) or not Numbers.integer(row.get("quantity"),1,25):return a.reject("The saved tutorial has invalid cargo")
			totals[row.item_id]=int(totals.get(row.item_id,0))+row.quantity
		if totals!=expected:return a.reject("The saved tutorial duplicated or lost its equipment")
		for index in seed.slots.size():
			if seed.slots[index]!=null and data.loadout.slots[index]!=seed.slots[index]:return a.reject("The saved tutorial changed a protected slot")
		if data.cargo_cache_stale:
			if cursor!=6 or data.transactions!=0 or data.cargo.entries!=[] or data.cargo.used!=data.cargo.capacity or data.cargo.free_space!=0:return a.reject("The tutorial changed its deferred cargo refresh")
		elif not equipment._valid_cargo(data.cargo,false):return a.reject(equipment.error)
		if cursor==7 and not equipment.requirements().satisfied:return a.reject("The saved equipment tutorial is incomplete")
	else:
		if data.training_inventory_released!=true or data.prototype_drill_replaced!=true or data.protected_item_ids!=[] or data.cargo_cache_stale!=false:return a.reject("The local journey lost its earned inventory transitions")
		if not equipment._valid_cargo(data.cargo,false):return a.reject(equipment.error)
		if not data.prices is Dictionary or data.prices.size()!=2 or not a._price_list(data.prices.get("cargo"),data.cargo.entries) or not a._price_list(data.prices.get("installed"),data.loadout.slots):return a.reject("The local journey lost its retained prices")
	return equipment
