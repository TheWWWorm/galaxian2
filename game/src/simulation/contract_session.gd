extends RefCounted
## One native side-mission slot, independent of the retained story objective.
## Generated contacts are supplied by the lounge owner. Acceptance stages cargo
## and fees together. Delivery results require the destination inventory and
## acknowledgement; ordinary contract travel and combat have separate owners.
const Definitions=preload("res://src/content/early_contract_definitions.gd")
const Offer=preload("res://src/simulation/contract_offer.gd")
const Equipment=preload("res://src/simulation/station_equipment.gd")
const Reputation=preload("res://src/simulation/faction_reputation.gd")
const Contacts=preload("res://src/simulation/lounge_contacts.gd")
const Career=preload("res://src/simulation/opening_handoff.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Delivery=preload("res://src/content/delivery_result_definitions.gd")
const FlightResults=preload("res://src/content/contract_flight_result_definitions.gd")
const Junk=preload("res://src/content/contract_junk_definitions.gd")
const LoungeCache=preload("res://src/simulation/lounge_cache.gd")
const LoungeLifecycle=preload("res://src/content/lounge_lifecycle_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Story=preload("res://src/content/lounge_story_definitions.gd")
const GateArrival=preload("res://src/content/gate_arrival_definitions.gd")
const Shopping=preload("res://src/content/ordinary_shopping_definitions.gd")
const Campaign=preload("res://src/content/free_campaign_definitions.gd")
const OrdinaryContracts=preload("res://src/content/ordinary_contracts_definitions.gd")
var error:=""
var _state:={}
var _rules:={}
var _cabins:={}
var _progress_rules:={}
var _stations:=[]
var _result_inventory:={}
var _flight:={}
var _pending_flight:={}
var _flight_identity: RefCounted
var _lounges: RefCounted

static func available(bindings: RefCounted) -> bool:
	return bindings!=null and Definitions.acceptance_parameters(bindings.early_contracts)

func configure(bindings: RefCounted,catalogues: RefCounted,station: Dictionary,equipment: RefCounted,difficulty: float) -> bool:
	error=""
	if not _state.is_empty():return reject("Retain the current contract session instead of resetting it")
	if not available(bindings) or catalogues==null or catalogues.content_id!=bindings.base_content_id:return reject("Contract acceptance is unavailable for this content")
	if not is_finite(difficulty) or difficulty<=0.0:return reject("The game difficulty is invalid")
	var terms: Dictionary=bindings.early_contracts
	var visit: Dictionary=bindings.mido_travel.get("return_visit",{})
	var gate: Dictionary=visit.get("contract_gate",{})
	if gate.is_empty() or station.get("phase")!="contracts_required" or station.get("campaign_cursor")!=int(terms.first_cursor) or not station.get("local_visit_acknowledged",false) or not station.get("acknowledged",false):return reject("Acknowledge the lounge introduction before opening contracts")
	if station.get("base_content_id")!=bindings.base_content_id or station.get("binding_id")!=bindings.binding_id or not equipment is Equipment:return reject("Contracts require the retained station inventory and content identity")
	var owned: Dictionary=equipment.snapshot()
	if not owned.get("training_inventory_released",false) or not owned.get("prototype_drill_replaced",false) or owned.get("cargo_cache_stale",true) or owned.get("loadout")!=station.get("loadout") or owned.get("cargo")!=station.get("cargo"):return reject("Contracts lost the earned ship or cargo")
	if owned.loadout.station_id!=int(visit.station_id) or owned.loadout.system_id!=int(terms.system_id):return reject("The first lounge belongs to the Kernstal return")
	var progress: Dictionary=station.get("progress",{})
	if progress.get("campaign_cursor")!=int(terms.first_cursor) or not progress.get("rank") is int or not Reputation.valid_state(progress.get("reputation")):return reject("Contracts require the retained career")
	var mission: Dictionary=station.get("mission",{})
	if mission.get("kind")!=int(visit.next_kind) or station.get("completed_side_missions")!=int(gate.initial_completed_count) or mission.get("completed_contract_target")!=int(gate.initial_completed_count)+int(gate.additional_completions):return reject("The first lounge lost its pending story requirement")
	var cabins:=cabin_catalogue(catalogues,terms.acceptance)
	if cabins.is_empty():return reject("The catalogue has no supported passenger cabins")
	_rules=terms.duplicate(true);_cabins=cabins
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"campaign_cursor":int(terms.first_cursor),"station_id":owned.loadout.station_id,
		"rank":progress.rank,"reputation":progress.reputation.duplicate(true),"difficulty":difficulty,
		"credits":int(terms.acceptance.initial_credits),"passengers":int(terms.acceptance.initial_passengers),
		"mission":{},"active_offer_id":-1,"offers":{}}
	if Definitions.delivery_parameters(terms):
		_progress_rules=bindings.opening_handoff.duplicate(true)
		_stations=catalogues.tables.systems[int(terms.system_id)].station_ids.duplicate()
		_state.progress=progress.duplicate(true)
		_state.completed_side_missions=station.completed_side_missions
		_state.delivery_statistics={"cargo":0,"passengers":0}
		_state.pending_result={};_state.result_serial=0
		if Junk.available(bindings):_state.progress.debris_destroyed=int(terms.junk_lifecycle.initial_debris_destroyed)
	if terms.has("world_initialization"):_state.accepted_contact={}
	if GateArrival.available(bindings):_state.travel_statistics={"jumpgates_used":int(bindings.mido_travel.gate_arrival.career.initial_jumpgates_used)}
	if LoungeLifecycle.available(bindings):
		_lounges=LoungeCache.new()
		if not _lounges.configure(bindings):return reject(_lounges.error)
	return true

func complete_story_wait(bindings: RefCounted,story_mission: Dictionary) -> bool:
	# Stage this on the station's fork. The caller publishes it only when the
	# final original story line is acknowledged. A side job can remain accepted.
	error=""
	if not Story.available(bindings) or not Travel.parameters(bindings.mido_travel):return reject("The contract story continuation is unavailable")
	var rules: Dictionary=bindings.mido_travel.contract_completion
	if not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty():return reject("Resolve the current flight or result before the station conversation")
	if _state.get("base_content_id")!=bindings.base_content_id or _state.get("binding_id")!=bindings.binding_id or _state.get("campaign_cursor")!=int(rules.campaign_cursor):return reject("The story continuation belongs to another career")
	if not Travel.navigation_mission(bindings.mido_travel,int(rules.campaign_cursor),story_mission):return reject("The original contract requirement is missing")
	if not Numbers.integer(_state.get("completed_side_missions"),0,2147483647) or _state.completed_side_missions<int(story_mission.completed_contract_target):return reject("Complete the additional required contracts before continuing the story")
	var progress: Dictionary=_state.get("progress",{})
	if progress.get("campaign_cursor")!=_state.campaign_cursor:return reject("The story and retained career disagree")
	var earned:=Career.calculate_progress(_progress_rules,int(rules.next_cursor),progress.player_kills,progress.pirate_kills,progress.other_score)
	if earned.is_empty():return reject("The story continuation exceeds the supported career range")
	_state.campaign_cursor=int(rules.next_cursor);_state.progress.merge(earned,true);_state.rank=earned.rank
	return true

func register_offer(offer_id: int,offer: RefCounted) -> bool:
	error=""
	if not _flight.is_empty():return reject("Retain the current flight before changing lounge offers")
	if _state.is_empty() or offer_id<0 or not offer is Offer:return reject("A generated lounge contact needs a verified offer")
	if not _state.get("pending_result",{}).is_empty():return reject("Acknowledge the current result before changing lounge offers")
	var quote: Dictionary=offer.snapshot()
	if quote.is_empty() or quote.base_content_id!=_state.base_content_id or quote.binding_id!=_state.binding_id:return reject("The offer belongs to another content identity")
	for key in ["campaign_cursor","station_id","rank","reputation"]:
		if quote.context[key]!=_state[key]:return reject("The offer no longer matches the station career")
	if _state.has("population") and not _state.offers.has(offer_id):return reject("This generated lounge has no such contract contact")
	if _state.offers.has(offer_id):
		if _state.offers[offer_id].offer!=quote:return reject("A retained contact cannot change its offer")
		return true
	_state.offers[offer_id]={"offer":quote,"consumed":false}
	return true

func advance_capture_story(bindings: RefCounted,progress: Dictionary,next_cursor: int) -> bool:
	# Only the station transaction calls this after live capture or final dialogue
	# acknowledgement. Retain the independent job, wallet and historical contacts.
	error=""
	var definitions=load("res://src/content/alioth_arrival_definitions.gd")
	if not definitions.available(bindings) or _state.is_empty():return reject("The Alioth story continuation is unavailable")
	var rules: Dictionary=bindings.mido_travel.alioth_arrival
	var previous:=int(rules.departing_cursor) if next_cursor==int(rules.campaign_cursor) else int(rules.campaign_cursor)
	if next_cursor not in [int(rules.campaign_cursor),int(rules.next_cursor)]:return reject("The capture story has no such continuation")
	var relocated:=previous==int(rules.departing_cursor)
	return _retain_story_progress(bindings,progress,previous,next_cursor,int(rules.from_station_id) if relocated else int(rules.station_id),int(rules.station_id),relocated)

func advance_alioth_story(bindings: RefCounted,progress: Dictionary,next_cursor: int) -> bool:
	error=""
	var definitions=load("res://src/content/alioth_return_definitions.gd")
	if not definitions.available(bindings) or _state.is_empty():return reject("The Alioth return is unavailable")
	var rules: Dictionary=bindings.mido_travel.alioth_return
	if next_cursor not in [int(rules.campaign_cursor),int(rules.next_cursor)]:return reject("The Alioth return has no such continuation")
	return _retain_story_progress(bindings,progress,next_cursor-1,next_cursor,int(rules.station_id),int(rules.station_id),false)

func retain_alioth_return_progress(bindings: RefCounted,progress: Dictionary) -> bool:
	error=""
	var definitions=load("res://src/content/alioth_return_definitions.gd")
	if not definitions.available(bindings) or _state.is_empty():return reject("The Alioth return is unavailable")
	var rules: Dictionary=bindings.mido_travel.alioth_return
	return _retain_story_progress(bindings,progress,int(rules.campaign_cursor),int(rules.campaign_cursor),int(rules.station_id),int(rules.station_id),false)

func _retain_story_progress(bindings: RefCounted,progress: Dictionary,previous: int,next_cursor: int,from_station: int,to_station: int,relocated: bool) -> bool:
	if _state.campaign_cursor!=previous or progress.get("campaign_cursor")!=previous:return reject("The story is stale or already acknowledged")
	if not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty():return reject("The story cannot discard an unresolved contract result")
	if bindings.base_content_id!=_state.base_content_id or bindings.binding_id!=_state.binding_id:return reject("The story career belongs to another content identity")
	if _state.station_id!=from_station:return reject("The story career is at another station")
	var current:=Career.calculate_progress(_progress_rules,previous,progress.get("player_kills"),progress.get("pirate_kills"),progress.get("other_score"))
	if current.is_empty() or not Reputation.valid_state(progress.get("reputation")):return reject("The capture lost its earned career")
	for key in current:
		if progress.get(key)!=current[key]:return reject("The capture career counters disagree")
	for key in ["player_kills","pirate_kills","other_score","debris_destroyed","capital_ship_kills"]:
		if not Numbers.integer(progress.get(key,0),int(_state.progress.get(key,0)),2147483647):return reject("The capture lost a retained career counter")
	var earned:=Career.calculate_progress(_progress_rules,next_cursor,current.player_kills,current.pirate_kills,current.other_score)
	if earned.is_empty():return reject("The Alioth story exceeds the supported career range")
	var next:=progress.duplicate(true);next.merge(earned,true)
	_state.campaign_cursor=next_cursor;_state.progress=next;_state.rank=next.rank
	_state.reputation=next.reputation.duplicate(true);_state.station_id=to_station
	if relocated:
		_state.offers={};_state.erase("population");_state.location_generation_pending=true
	return true

func populate(bindings: RefCounted,cat: RefCounted,library: RefCounted,random_state: Variant,history: Variant) -> bool:
	error=""
	if not _flight.is_empty():return reject("Retain the current flight before opening another lounge")
	if _state.is_empty() or not _state.offers.is_empty() or _state.has("population"):return reject("Retain the existing contacts instead of regenerating their offers")
	if bindings==null or bindings.base_content_id!=_state.base_content_id or bindings.binding_id!=_state.binding_id:return reject("The lounge population belongs to another content identity")
	var context:={}
	for key in ["campaign_cursor","station_id","rank","reputation"]:context[key]=_state[key]
	var contacts:=Contacts.new()
	if not contacts.prepare(bindings,cat,library,context,random_state,history):return reject(contacts.error)
	var population: Dictionary=contacts.snapshot()
	var next: RefCounted=fork()
	for contact in population.contacts:
		if contact.offer.is_empty():continue
		var offer:=Offer.new()
		if not offer.restore(bindings,cat,contact.offer) or not next.register_offer(int(contact.contact_id),offer):return reject(offer.error+next.error)
	if next._lounges!=null and not next._lounges.remember(contacts):return reject(next._lounges.error)
	next._state.population=population
	_state=next._state;_lounges=next._lounges
	return true

func retain_locations(cache: RefCounted) -> bool:
	# Opening selections can precede access to the lounge. Keep the historical
	# quotation context; accepting a retained job uses its original terms.
	error=""
	if _state.is_empty() or not _state.offers.is_empty() or _state.has("population") or not _flight.is_empty() or not cache is LoungeCache:return reject("Supply the opening's retained locations before populating contracts")
	var retained: Dictionary=cache.snapshot()
	for key in ["base_content_id","binding_id"]:
		if retained.get(key)!=_state[key]:return reject("The retained locations belong to another content identity")
	if retained.get("current_station_id")!=_state.station_id:return reject("The retained locations do not select the current station")
	var local: Dictionary=cache.location(_state.station_id)
	if local.is_empty() or not local.has("stock") or local.population.context.campaign_cursor>_state.campaign_cursor:return reject("The current station lacks its earlier generated stock and contacts")
	_lounges=cache.fork();_state.population=local.population;_state.offers=local.offers
	_state.erase("location_generation_pending")
	return true

func rebase_station(equipment: RefCounted,bindings: RefCounted=null) -> bool:
	# The caller must first accept actual docking and detach the flight ledger.
	# Rebase never generates contacts, consumes RNG, pays or advances the story.
	error=""
	if _lounges==null or not _flight.is_empty() or not _state.get("pending_result",{}).is_empty():return reject("Station contracts require retained flight and result ownership")
	var owned:=_station_inventory(equipment,bindings)
	if owned.is_empty():return false
	var station: int=owned.loadout.station_id
	if station==_state.station_id:return true
	_state.station_id=station
	_state.offers={};_state.erase("population")
	var cached: Dictionary=_lounges.location(station)
	if not cached.is_empty():
		_state.offers=cached.offers;_state.population=cached.population
	return true

func location_owner() -> RefCounted:
	return null if _lounges==null else _lounges.fork()

func open_shopping(bindings: RefCounted,cat: RefCounted,equipment: RefCounted,unix_seconds: Array,library: RefCounted=null) -> RefCounted:
	error=""
	var owned:=_shopping_inventory(bindings,cat,equipment)
	if owned.is_empty():return null
	if unix_seconds.size()!=3:return _shopping_reject("Supply the three station price timestamps")
	for value in unix_seconds:
		if not value is int or value<0:return _shopping_reject("Station price timestamps must be nonnegative integers")
	var stock: Array=_lounges.item_stock(_state.station_id)
	var times:=unix_seconds.duplicate()
	if owned.cargo.entries.is_empty():times[0]=null
	if stock.is_empty():times[2]=null
	var inventory: RefCounted=equipment.fork()
	var receipt: Dictionary=inventory.open_ordinary_shopping(bindings,cat,stock,_lounges.snapshot().random,times,0,library)
	if receipt.is_empty():return _shopping_reject(inventory.error)
	var locations: RefCounted=_lounges.fork()
	if not locations.replace_item_stock(bindings,cat,_state.station_id,stock,inventory.snapshot().stock,receipt.random):return _shopping_reject(locations.error)
	_lounges=locations
	return inventory

func transact_shopping(bindings: RefCounted,cat: RefCounted,equipment: RefCounted,action: String,item_id: int,slot_index: int=-1) -> RefCounted:
	error=""
	var owned:=_shopping_inventory(bindings,cat,equipment)
	if owned.is_empty():return null
	if not owned.get("ordinary_shopping_open",false) or owned.stock!=_lounges.item_stock(_state.station_id):return _shopping_reject("Open the current station's hangar quote before trading")
	var inventory: RefCounted=equipment.fork()
	if action in ["mount","unmount","replace"]:
		if not _state.mission.is_empty():return _shopping_reject("Fitting with an active contract is not yet supported")
		if not inventory.fit(bindings,cat,action,item_id,slot_index,0):return _shopping_reject(inventory.error)
	elif not inventory.transact(action,item_id,_state.credits):return _shopping_reject(inventory.error)
	var accepted: Dictionary=inventory.snapshot()
	var locations: RefCounted=_lounges.fork()
	if not locations.replace_item_stock(bindings,cat,_state.station_id,owned.stock,accepted.stock):return _shopping_reject(locations.error)
	var credits:=credit_balance(_state.credits,accepted.credit_delta,_rules.delivery_results)
	_lounges=locations;_state.credits=credits
	return inventory

func _shopping_inventory(bindings: RefCounted,cat: RefCounted,equipment: RefCounted) -> Dictionary:
	if not equipment is Equipment or _lounges==null or not Campaign.supported(bindings.mido_travel,_state.get("campaign_cursor")) or _state.get("progress",{}).get("campaign_cursor")!=_state.get("campaign_cursor"):reject("Shopping requires the earned ordinary station career");return {}
	if not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty():reject("Resolve the current flight or result before shopping");return {}
	var place:=Shopping.location(bindings,cat,_state.station_id)
	if place.is_empty() or _state.get("mission",{}).get("kind",-1)==int(bindings.mido_travel.ordinary_shopping.pricing.special_mission_kind):reject("This station pricing context is not supported");return {}
	var owned: Dictionary=equipment.snapshot()
	if not owned.get("training_inventory_released",false) or not owned.get("prototype_drill_replaced",false) or owned.get("cargo_cache_stale",true):reject("Shopping lost the earned inventory");return {}
	for key in ["base_content_id","binding_id"]:
		if _state.get(key)!=bindings.get(key) or owned.loadout.get(key)!=bindings.get(key) or owned.cargo.get(key)!=bindings.get(key):reject("Shopping belongs to another content identity");return {}
	if owned.loadout.station_id!=place.station_id or owned.loadout.system_id!=place.system_id or _lounges.snapshot().current_station_id!=place.station_id or _lounges.location(place.station_id).is_empty():reject("Shopping lost the current cached station");return {}
	if not _state.get("credits") is int or _state.credits<0 or _state.credits>2147483647:reject("Shopping has an invalid retained wallet");return {}
	return owned

func _shopping_reject(message: String) -> RefCounted:
	reject(message);return null

func rebase_gate_arrival(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,arrival: Dictionary) -> bool:
	error=""
	if not GateArrival.packet_matches(bindings,catalogues,arrival) or _state.get("campaign_cursor")!=arrival.campaign_cursor or _state.get("station_id")!=arrival.from_station_id:return reject("Gate arrival must follow this retained career's location")
	if not equipment is Equipment or equipment.snapshot().get("loadout",{}).get("station_id")!=arrival.station_id or not _pending_flight.is_empty():return reject("Gate arrival requires its detached destination inventory and retired flight")
	var statistics: Variant=_state.get("travel_statistics")
	if not GateArrival.valid_statistics(statistics):return reject("Gate arrival lost its earned travel statistics")
	var count: int=statistics.jumpgates_used+int(bindings.mido_travel.gate_arrival.career.jump_increment)
	if not Numbers.integer(count,0,2147483647):return reject("The gate count exceeds its supported range")
	if not rebase_station(equipment,bindings):return false
	_state.travel_statistics={"jumpgates_used":count}
	return true

func select_location(bindings: RefCounted,cat: RefCounted,library: RefCounted,station_id: int,settings: Dictionary,random_state: Dictionary,unix_seconds: Variant) -> bool:
	# Called on the detached arrival career, after retiring its old flight
	# ledger and before constructing the destination world. Accepted jobs and
	# their original clients remain independent of the currently selected lounge.
	error=""
	if _lounges==null or not _flight.is_empty() or not _state.get("pending_result",{}).is_empty():return reject("Retain the completed flight before selecting its destination location")
	if settings.get("difficulty")!=_state.difficulty:return reject("Location generation changed the retained difficulty")
	var candidate: RefCounted=_lounges.fork()
	var context:={"station_id":station_id,"campaign_cursor":_state.campaign_cursor,"rank":_state.rank,"reputation":_state.reputation.duplicate(true)}
	if not candidate.select_location(bindings,cat,library,context,settings,random_state,unix_seconds):return reject(candidate.error)
	_lounges=candidate
	return true

@warning_ignore("integer_division")
static func acceptance_fee(terms: Dictionary,mission: Dictionary,difficulty: float) -> int:
	if difficulty!=float(terms.acceptance.fee_difficulty):return 0
	return (int(mission.reward)+int(mission.bonus))/int(terms.acceptance.fee_divisor)

static func cabin_catalogue(catalogues: RefCounted,rules: Dictionary) -> Dictionary:
	var result:={}
	for index in catalogues.tables.items.size():
		var properties: Dictionary=catalogues.tables.items[index].properties
		if int(properties.get(2,-1))==int(rules.cabin_subtype):
			var places:=int(properties.get(int(rules.cabin_places_property),0))
			if places>0:result[index]=places
	return result

static func passenger_capacity(cabins: Dictionary,loadout: Dictionary) -> int:
	var places:=0
	for slot in loadout.slots:
		if slot!=null:places+=int(cabins.get(slot.item_id,0))
	return places

func preview(offer_id: int,equipment: RefCounted,bindings: RefCounted=null) -> Dictionary:
	error=""
	if not _flight.is_empty():reject("Contract acceptance requires the retained station arrival");return {}
	if not _state.get("pending_result",{}).is_empty():reject("Acknowledge the current contract result first");return {}
	if _state.is_empty() or not _state.offers.has(offer_id) or _state.offers[offer_id].consumed:reject("This contact has no available offer");return {}
	var quote: Dictionary=_state.offers[offer_id].offer
	if not acceptance_supported(_rules,int(_state.campaign_cursor),quote,bindings):reject("This contract's mission or destination is not supported yet");return {}
	if not equipment is Equipment:reject("The contract requires the retained inventory");return {}
	var owned: Dictionary=equipment.snapshot()
	if owned.is_empty() or not owned.get("training_inventory_released",false) or owned.get("cargo_cache_stale",true):reject("The contract inventory is unavailable");return {}
	for key in ["base_content_id","binding_id","station_id"]:
		if owned.loadout[key]!=_state[key]:reject("The contract inventory belongs to another station");return {}
	var fee:=acceptance_fee(_rules,quote.mission,float(_state.difficulty))
	var places:=passenger_capacity(_cabins,owned.loadout)
	var reason:=-1
	# The source checks the offered quantity before discarding an old job.
	if int(quote.requirements.cargo_tons)>int(owned.cargo.free_space):reason=int(_rules.courier.capacity_text_id)
	elif int(quote.requirements.passenger_places)>places:reason=int(_rules.passenger.capacity_text_id)
	elif fee>int(_state.credits):reason=int(_rules.acceptance.insufficient_credits_text_id)
	var replacing: bool=not _state.mission.is_empty()
	return {"can_accept":reason<0,"reason_text_id":reason,"fee":fee,
		"missing_credits":maxi(0,fee-int(_state.credits)),"cargo_tons":int(quote.requirements.cargo_tons),
		"passenger_places":int(quote.requirements.passenger_places),"passenger_capacity":places,
		"replacement_required":replacing,"replacement_text_id":int(_rules.acceptance.replacement_text_id) if replacing else -1}

static func acceptance_supported(rules: Dictionary,cursor: int,quote: Dictionary,bindings: RefCounted=null) -> bool:
	# Quotation coverage can grow before the corresponding flight/objective
	# owners. Retained earlier contacts do not grant post-unlock acceptance.
	if OrdinaryContracts.available(bindings) and Campaign.supported(bindings.mido_travel,cursor):
		return rules==bindings.early_contracts and Numbers.integer(quote.get("context",{}).get("campaign_cursor"),Definitions.first_generation_cursor(rules),cursor) and OrdinaryContracts.delivery_mission(bindings,quote.get("mission"))
	return not rules.is_empty() and Numbers.integer(cursor,Definitions.first_generation_cursor(rules),int(rules.last_cursor)) and Numbers.integer(quote.get("context",{}).get("campaign_cursor"),Definitions.first_generation_cursor(rules),int(rules.last_cursor)) and quote.get("choices",{}).has("kind_index")

func accept(offer_id: int,equipment: RefCounted,replace_current: bool=false,bindings: RefCounted=null) -> RefCounted:
	var terms:=preview(offer_id,equipment,bindings)
	if terms.is_empty():return null
	if not terms.can_accept:reject("The contract requirements are not satisfied");return null
	if terms.replacement_required and not replace_current:reject("Confirm discarding the current mission first");return null
	var next: Dictionary=_state.duplicate(true)
	var quote: Dictionary=next.offers[offer_id].offer
	var candidate: RefCounted=equipment.fork()
	var hold: Dictionary=candidate.snapshot().cargo
	var mission_cargo:=int(_rules.courier.cargo_item_id)
	if not next.mission.is_empty():
		if _rules.acceptance.clear_cargo_kinds.any(func(value):return int(value)==int(next.mission.kind)):
			for index in hold.entries.size():
				var row: Dictionary=hold.entries[index]
				if row.item_id==mission_cargo and row.get("mission",false):hold.entries.remove_at(index);break
		elif int(next.mission.kind)==int(_rules.passenger.kind):next.passengers=0
	if int(quote.mission.kind)==int(_rules.courier.kind):
		var merged:=false
		for row in hold.entries:
			if row.item_id==mission_cargo:
				# Original cargo merging compares item IDs and keeps the existing
				# row's marker. Do not turn unrelated cargo into protected cargo.
				row.quantity+=int(quote.mission.quantity);merged=true;break
		if not merged:hold.entries.append({"item_id":mission_cargo,"quantity":int(quote.mission.quantity),"mission":true})
	elif int(quote.mission.kind)==int(_rules.passenger.kind):next.passengers=int(quote.mission.quantity)
	hold.used=0
	for row in hold.entries:hold.used+=int(row.quantity)
	hold.free_space=int(hold.capacity)-int(hold.used)
	if not candidate.retain_flight_cargo(hold):reject(candidate.error);return null
	next.credits-=int(terms.fee);next.active_offer_id=offer_id
	next.mission=quote.mission.duplicate(true);next.offers[offer_id].consumed=true
	if next.has("accepted_contact"):
		next.accepted_contact={"offer_id":offer_id,"station_id":int(next.station_id),"offer":quote.duplicate(true),"name":""}
		for contact in next.get("population",{}).get("contacts",[]):
			if contact.contact_id==offer_id:
				next.accepted_contact.name=contact.name
				next.accepted_contact.portrait=contact.portrait.duplicate(true)
				break
	var lounges: RefCounted=_lounges.fork() if _lounges!=null else null
	if lounges!=null and next.has("population") and not lounges.consume(int(next.station_id),offer_id):reject(lounges.error);return null
	# Procedural contacts have source ID -1. Their consumed flag remains set
	# when replaced; re-registering the same contact cannot duplicate its cargo.
	_state=next;_lounges=lounges
	return candidate

func active_mission_for(station_id: int,bindings: RefCounted=null) -> Dictionary:
	# The active world mission and the retained side slot are different things.
	# Passenger delivery is handled by the station even at its destination.
	var ordinary: bool=OrdinaryContracts.delivery_mission(bindings,_state.get("mission")) and Campaign.supported(bindings.mido_travel,_state.get("campaign_cursor"))
	if not _rules.has("delivery_results") or (station_id not in _stations and not ordinary) or _state.mission.is_empty() or not _state.pending_result.is_empty():return {}
	var mission: Dictionary=_state.mission
	if mission.station_id!=station_id or _rules.delivery_results.active_flight_excluded_kinds.any(func(value):return int(value)==int(mission.kind)):return {}
	return mission.duplicate(true)

func flight_context(station_id: int,bindings: RefCounted=null) -> Dictionary:
	error=""
	if not _flight.is_empty():reject("Retain the current contract flight before preparing another encounter");return {}
	var ordinary: bool=OrdinaryContracts.available(bindings) and Campaign.supported(bindings.mido_travel,_state.get("campaign_cursor")) and not load("res://src/content/free_flight_definitions.gd").flight(bindings,station_id,int(_state.get("campaign_cursor",-1))).is_empty()
	if _state.is_empty() or not Definitions.encounter_parameters(_rules) or (station_id not in _stations and not ordinary):
		reject("This contract session has no supported encounter context");return {}
	if not _state.pending_result.is_empty():reject("Acknowledge the contract result before preparing another encounter");return {}
	var mission:=active_mission_for(station_id,bindings)
	var result:={"base_content_id":_state.base_content_id,"binding_id":_state.binding_id,
		"campaign_cursor":_state.campaign_cursor,"station_id":station_id,
		"rank":_state.rank,"difficulty":_state.difficulty,"reputation":_state.reputation.duplicate(true),
		"mission":mission,"client_faction":-1,"contact_name":""}
	if mission.is_empty():return result
	var retained: Dictionary=_state.get("accepted_contact",{})
	var accepted: Dictionary=_state.offers.get(_state.active_offer_id,{}) if retained.is_empty() else {"consumed":true,"offer":retained.offer}
	if accepted.is_empty() or not accepted.consumed or accepted.offer.mission!=mission:
		reject("The flight mission has no retained accepted contact");return {}
	result.client_faction=int(accepted.offer.context.client_faction)
	if not retained.is_empty():result.contact_name=retained.name
	else:
		for contact in _state.get("population",{}).get("contacts",[]):
			if contact.contact_id==_state.active_offer_id:result.contact_name=contact.name;break
	return result

func free_flight_context(bindings: RefCounted,station_id: int) -> Dictionary:
	error=""
	var definitions=load("res://src/content/free_flight_definitions.gd")
	if not definitions.available(bindings) or definitions.flight(bindings,station_id,int(_state.get("campaign_cursor",-1))).is_empty() or not Campaign.supported(bindings.mido_travel,_state.get("campaign_cursor")) or _state.get("station_id")!=station_id:return fail("The ordinary flight requires its retained unlocked career")
	if _state.get("base_content_id")!=bindings.base_content_id or _state.get("binding_id")!=bindings.binding_id or _rules!=bindings.early_contracts:return fail("The ordinary career belongs to another content identity")
	if GateArrival.available(bindings) and not GateArrival.valid_statistics(_state.get("travel_statistics")):return fail("The ordinary career lost its earned travel statistics")
	if not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty():return fail("Resolve the retained flight or result before ordinary departure")
	var side: Dictionary=_state.get("mission",{})
	if not side.is_empty():
		if not OrdinaryContracts.delivery_mission(bindings,side):return fail("This accepted side mission has no supported ordinary flight")
		var contact: Dictionary=_state.get("accepted_contact",{})
		if contact.get("offer_id")!=_state.active_offer_id or contact.get("offer",{}).get("mission")!=side:return fail("The ordinary side mission lost its accepted contact")
		var selected:=flight_context(station_id,bindings)
		if selected.is_empty():return {}
		selected.side_mission=side.duplicate(true)
		return selected
	return {"base_content_id":_state.base_content_id,"binding_id":_state.binding_id,
		"campaign_cursor":_state.campaign_cursor,"station_id":station_id,"rank":_state.rank,
		"difficulty":_state.difficulty,"reputation":_state.reputation.duplicate(true),
		"mission":{},"client_faction":-1,"contact_name":""}

func poll_station(equipment: RefCounted,bindings: RefCounted=null) -> bool:
	error=""
	if not _flight.is_empty():return reject("Retain the current flight before polling station results")
	if not _rules.has("delivery_results"):return reject("This content has no supported delivery results")
	var owned:=_station_inventory(equipment,bindings)
	if owned.is_empty():return false
	if not _state.pending_result.is_empty():
		return true if owned==_result_inventory else reject("The pending delivery must retain its destination inventory")
	if _state.mission.is_empty():return true
	var rules: Dictionary=_rules.delivery_results
	var mission: Dictionary=_state.mission
	if not rules.delivery_kinds.any(func(value):return int(value)==int(mission.kind)) or mission.station_id!=owned.loadout.station_id:return true
	var retained: Dictionary=_state.get("accepted_contact",{})
	var accepted: Dictionary=_state.offers.get(_state.active_offer_id,{}) if retained.is_empty() else {"consumed":true,"offer":retained.offer}
	if accepted.is_empty() or not accepted.consumed:return reject("The delivery has no accepted contact")
	var quote: Dictionary=accepted.offer
	if mission!=quote.mission or mission.story:return reject("Only the retained non-story delivery can settle here")
	var reward:=int(mission.reward)+int(mission.bonus)
	if not Numbers.integer(reward,0,int(rules.maximum_station_reward)) or not Numbers.integer(_state.credits,0,2147483647):return reject("The delivery payment is outside the supported source range")
	if not Reputation.valid_state(_state.reputation):return reject("The delivery lost the retained faction standing")
	# Opening the source success result marks it completed and changes faction
	# standing. Money, delivered quantities and the success count wait for Close.
	var standing:=Delivery.standing_after(rules,_state.reputation,int(quote.context.client_faction),float(_state.difficulty))
	_state.reputation=standing;_state.progress.reputation=standing.duplicate(true)
	_state.result_serial+=1
	_state.pending_result={"serial":_state.result_serial,"offer_id":_state.active_offer_id,
		"station_id":int(mission.station_id),"kind":int(mission.kind),"mode":int(rules.success_result_mode),
		"acknowledgement_required":true,"reward_credits":reward,"completed":true}
	_result_inventory=owned
	return true

func acknowledge_delivery_result(equipment: RefCounted,bindings: RefCounted=null) -> RefCounted:
	error=""
	if not _flight.is_empty():reject("The current result belongs to flight");return null
	if not _rules.has("delivery_results") or _state.get("pending_result",{}).is_empty():reject("No delivery result awaits acknowledgement");return null
	var owned:=_station_inventory(equipment,bindings)
	if owned.is_empty():return null
	if owned!=_result_inventory:reject("The delivery result belongs to another destination inventory");return null
	var next:=_state.duplicate(true)
	var rules: Dictionary=_rules.delivery_results
	if not Numbers.integer(next.completed_side_missions,0,2147483646):reject("The contract success count is outside its supported range");return null
	var progress: Dictionary=next.progress
	var earned:=Career.calculate_progress(_progress_rules,next.campaign_cursor,progress.player_kills,progress.pirate_kills,
		int(progress.other_score)+int(rules.completion_rank_weight))
	if earned.is_empty():reject("The delivery score exceeds the supported career range");return null
	var hold: Dictionary=owned.cargo.duplicate(true)
	for index in hold.entries.size():
		var row: Dictionary=hold.entries[index]
		if row.get("mission",false) and rules.clear_first_marked_item_ids.any(func(value):return int(value)==int(row.item_id)):
			hold.used-=int(row.quantity);hold.free_space+=int(row.quantity)
			hold.entries.remove_at(index);break
	var inventory: RefCounted=equipment.fork()
	if not inventory.retain_flight_cargo(hold):reject(inventory.error);return null
	if int(next.mission.kind)==int(_rules.passenger.kind):
		next.passengers=0;next.delivery_statistics.passengers+=int(next.mission.quantity)
	else:next.delivery_statistics.cargo+=int(next.mission.quantity)
	var reward:=int(next.pending_result.reward_credits)
	next.credits=credit_balance(int(next.credits),reward,rules)
	next.completed_side_missions+=int(rules.completion_increment)
	next.progress.merge(earned,true);next.rank=earned.rank
	next.last_result=next.pending_result.duplicate(true)
	next.last_result.acknowledgement_required=false
	next.last_result.notification_sound_id=int(rules.notification_sound_id) if reward!=0 else -1
	next.mission={};next.active_offer_id=-1;next.pending_result={}
	if next.has("accepted_contact"):next.accepted_contact={}
	_state=next;_result_inventory={}
	return inventory

func bind_flight(controller: RefCounted) -> bool:
	error=""
	if not _flight.is_empty() or not FlightResults.parameters(_rules.get("flight_results")) or not is_instance_of(controller,load("res://src/simulation/combat_training_control.gd")):return reject("This contract session cannot bind a new flight")
	var scene: Dictionary=controller.snapshot()
	var clock: Dictionary=scene.get("contract_result",{})
	var encounter: Dictionary=scene.get("combat",{}).get("contract_encounter",{})
	if clock.is_empty() or clock.elapsed_ms!=0 or clock.mode!=0 or clock.retired or not scene.has("accounting"):return reject("Bind the prepared flight before its first actor update")
	var context:=flight_context(int(encounter.get("context",{}).get("station_id",-1)))
	var supported: bool=not context.is_empty() and (_rules.flight_results.ship_kinds.any(func(value):return int(value)==int(context.mission.get("kind",-1))) or (Junk.parameters(_rules.get("junk_lifecycle")) and context.mission.kind==7))
	if not supported or context!=encounter.get("context"):return reject("This flight does not belong to the accepted contract")
	if not scene.accounting.events.is_empty() or not scene.combat.reputation.events.is_empty() or not scene.combat.get("contract_settlement",{}).is_empty():return reject("A new flight cannot adopt unrecorded combat results")
	_flight={"encounter":encounter.duplicate(true),"accounting":scene.accounting.duplicate(true),
		"reputation_events":[],"settlement":{},"elapsed_ms":0,"retired":false}
	_flight_identity=controller.flight_identity()
	return true

func bind_world(controller: RefCounted,context: Dictionary,bindings: RefCounted=null) -> bool:
	error=""
	if not _rules.has("world_initialization") or not _flight.is_empty() or not is_instance_of(controller,load("res://src/simulation/combat_training_control.gd")):return reject("Bind an ordinary world to its retained contract session")
	var expected:=free_flight_context(bindings,int(context.get("station_id",-1))) if bindings!=null and Campaign.supported(bindings.mido_travel,context.get("campaign_cursor")) else flight_context(int(context.get("station_id",-1)))
	if expected.is_empty() or context!=expected:return reject("The prepared world changed its retained contract context")
	var scene: Dictionary=controller.snapshot()
	if not scene.get("contract_result",{}).is_empty():return bind_flight(controller)
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if scene.get(key)!=_state[key]:return reject("The ordinary world belongs to another career")
	if context.mission.get("kind",-1) not in [-1,0] or scene.get("combat",{}).get("provocation",{}).get("station_id")!=context.station_id or not scene.has("accounting"):return reject("This world cannot use ordinary contract-free accounting")
	if not scene.accounting.events.is_empty() or not scene.combat.reputation.events.is_empty() or controller.combat_owner().current_reputation()!=_state.reputation:return reject("Bind the ordinary world before combat changes its career")
	_flight={"ordinary_context":context.duplicate(true),"accounting":scene.accounting.duplicate(true),
		"reputation_events":[],"settlement":{},"elapsed_ms":0,"retired":false}
	_flight_identity=controller.flight_identity()
	return true

func evaluate_flight(controller: RefCounted,radio_active: bool=false,poll_results: bool=true,periodic_poll_allowed: bool=true) -> Dictionary:
	# The session and controller commit together. A failed result preparation
	# cannot pay, change career, discard actors or partially freeze a live flight.
	error=""
	if not _valid_flight(controller):return {}
	var next:=fork();var flight: RefCounted=controller.fork_for_frame()
	if not _pending_flight.is_empty():
		if controller.snapshot()!=_pending_flight:return fail("The pending result must retain its frozen flight")
		return {"session":next,"controller":flight,"opened":false}
	if not next._retain_combat_progress(flight):return fail(next.error)
	if _flight.has("ordinary_context") or not poll_results:return {"session":next,"controller":flight,"opened":false}
	var result: Dictionary=flight.poll_contract_result(radio_active,periodic_poll_allowed)
	if result.is_empty():return fail(flight.error)
	var opened: bool=result.mode!=0
	if opened:
		var rules: Dictionary=_rules.delivery_results
		var succeeded: bool=result.mode==int(_rules.flight_results.success_result_mode)
		var mission: Dictionary=next._state.mission
		var junk: bool=Junk.parameters(_rules.get("junk_lifecycle")) and int(mission.kind)==7
		var delta:=int(mission.reward)+int(mission.bonus) if succeeded else (int(_rules.junk_lifecycle.failure_credit_delta) if junk else -int(mission.reward))
		if (not succeeded and not junk and int(mission.kind)!=int(_rules.flight_results.penalty_kind)) or absi(delta)>int(rules.maximum_credit_delta):return fail("Unsupported contract settlement")
		if succeeded:
			if not Numbers.integer(next._state.completed_side_missions,0,2147483646):return fail("The contract count exceeds the supported career range")
			var progress: Dictionary=next._state.progress
			var earned:=Career.calculate_progress(_progress_rules,next._state.campaign_cursor,progress.player_kills,progress.pirate_kills,int(progress.other_score)+int(rules.completion_rank_weight))
			if earned.is_empty():return fail("The contract success exceeds the supported career range")
			next._state.progress.merge(earned,true);next._state.rank=earned.rank
			next._state.completed_side_missions+=int(rules.completion_increment)
		next._state.reputation=flight.combat_owner().current_reputation()
		next._state.progress.reputation=next._state.reputation.duplicate(true)
		next._state.result_serial+=1
		next._state.pending_result={"serial":next._state.result_serial,"offer_id":next._state.active_offer_id,
			"station_id":int(mission.station_id),"kind":int(mission.kind),"mode":int(result.mode),"flight":true,
			"acknowledgement_required":true,"credit_delta":delta,"completed":succeeded,"failed":not succeeded}
		next._pending_flight=flight.snapshot()
	next._flight.settlement=flight.snapshot().combat.get("contract_settlement",{}).duplicate(true)
	return {"session":next,"controller":flight,"opened":opened}

func acknowledge_flight_result(controller: RefCounted,serial: int) -> Dictionary:
	error=""
	if not _valid_flight(controller):return {}
	var pending: Dictionary=_state.get("pending_result",{})
	if pending.is_empty() or not pending.get("flight",false) or pending.serial!=serial or _pending_flight.is_empty() or controller.snapshot()!=_pending_flight:return fail("No matching frozen flight result awaits acknowledgement")
	var next:=fork();var flight: RefCounted=controller.fork_for_frame()
	if not flight.acknowledge_contract_result():return fail(flight.error)
	next._state.credits=credit_balance(int(next._state.credits),int(pending.credit_delta),_rules.delivery_results)
	next._state.last_result=pending.duplicate(true)
	next._state.last_result.acknowledgement_required=false
	next._state.last_result.notification_sound_id=int(_rules.delivery_results.notification_sound_id) if pending.completed and pending.credit_delta!=0 else -1
	next._state.mission={};next._state.active_offer_id=-1;next._state.pending_result={}
	if next._state.has("accepted_contact"):next._state.accepted_contact={}
	next._pending_flight={};next._flight.retired=true
	next._flight.settlement=flight.snapshot().combat.contract_settlement.duplicate(true)
	return {"session":next,"controller":flight,"clear_player_control":true,"clear_world_path":true}

func finish_flight(controller: RefCounted,retain_active_mission: bool=false) -> RefCounted:
	# Arrival retains any combat after acknowledgement before releasing the
	# flight ledger. Station relocation and scene disposal belong to the caller.
	error=""
	if not _valid_flight(controller):return null
	if (not _flight.retired and not (_rules.has("world_initialization") and retain_active_mission)) or not _state.pending_result.is_empty():reject("Resolve the current contract flight before releasing it");return null
	var next:=fork()
	if not next._retain_combat_progress(controller):reject(next.error);return null
	next._flight={}
	next._flight_identity=null
	return next

func acknowledge_campaign_visit(bindings: RefCounted,controller: RefCounted,visit: RefCounted) -> RefCounted:
	# Keep the existing world and its accounting ledger. The new story cursor
	# changes the career; it does not regenerate ships or reset the flight clock.
	error=""
	if not _valid_flight(controller):return null
	if not is_instance_of(visit,load("res://src/simulation/campaign_visit.gd")) or not _flight.has("ordinary_context") or _flight.has("story_transition") or not _state.pending_result.is_empty():reject("No campaign visit awaits acknowledgement in this flight");return null
	var transition: Dictionary=visit.transition()
	var scene: Dictionary=controller.snapshot()
	if transition.is_empty() or not Campaign.active_visit(bindings.mido_travel,scene.combat.get("free_context",{})):reject("The campaign visit does not belong to the active world");return null
	for key in ["base_content_id","binding_id"]:
		if transition.get(key)!=_state[key] or bindings.get(key)!=_state[key]:reject("The campaign visit belongs to another content identity");return null
	if transition.from_cursor!=_state.campaign_cursor or transition.station_id!=_state.station_id or transition.previous_mission!=Campaign.mission(bindings.mido_travel,_state.campaign_cursor) or transition.mission!=Campaign.mission(bindings.mido_travel,transition.campaign_cursor) or transition.reward_credits!=0:reject("The campaign visit changed its earned transition");return null
	var next:=fork()
	if not next._retain_combat_progress(controller):reject(next.error);return null
	var progress: Dictionary=next._state.progress
	var earned:=Career.calculate_progress(_progress_rules,transition.campaign_cursor,progress.player_kills,progress.pirate_kills,progress.other_score)
	if earned.is_empty():reject("The campaign visit exceeds the supported career range");return null
	next._state.progress.merge(earned,true);next._state.rank=earned.rank
	next._state.campaign_cursor=transition.campaign_cursor
	next._flight.story_transition=transition.duplicate(true)
	return next

func _valid_flight(controller: RefCounted) -> bool:
	if _flight.is_empty() or not is_instance_of(controller,load("res://src/simulation/combat_training_control.gd")):return reject("The retained contract has no matching flight owner")
	if _flight_identity==null or controller.flight_identity()!=_flight_identity:return reject("The contract lost its retained native flight")
	var scene: Dictionary=controller.snapshot()
	for key in ["base_content_id","binding_id"]:
		if scene.get(key)!=_state[key]:return reject("The contract flight belongs to another career")
	var transition: Dictionary=_flight.get("story_transition",{})
	if transition.is_empty():
		if scene.get("campaign_cursor")!=_state.campaign_cursor:return reject("The contract flight belongs to another campaign stage")
	elif not _flight.has("ordinary_context") or scene.get("campaign_cursor")!=transition.from_cursor or _state.campaign_cursor!=transition.campaign_cursor or _state.station_id!=transition.station_id:
		return reject("The retained world lost its acknowledged story transition")
	if _flight.has("ordinary_context"):
		if not scene.has("accounting") or scene.has("contract_result") or scene.get("combat",{}).get("provocation",{}).get("station_id")!=_flight.ordinary_context.station_id:return reject("The ordinary flight changed its retained station or accounting")
		return true
	if scene.get("combat",{}).get("contract_encounter")!=_flight.encounter or not scene.has("accounting") or not scene.has("contract_result"):return reject("The contract flight changed its accepted encounter")
	if scene.combat.get("contract_settlement",{})!=_flight.settlement or scene.contract_result.retired!=_flight.retired:return reject("The contract flight lost its retained result")
	if scene.contract_result.elapsed_ms<_flight.elapsed_ms:return reject("The contract flight regressed its clock")
	if _state.pending_result.is_empty() and scene.contract_result.mode!=0:return reject("The flight result was not opened by its retained contract owner")
	return true

func _retain_combat_progress(controller: RefCounted) -> bool:
	var scene: Dictionary=controller.snapshot()
	var accounting: Dictionary=scene.accounting
	var events: Array=scene.combat.reputation.events
	if accounting.events.slice(0,_flight.accounting.events.size())!=_flight.accounting.events or events.slice(0,_flight.reputation_events.size())!=_flight.reputation_events:return reject("The contract flight lost its retained combat history")
	var delta: Dictionary=accounting.counter_deltas
	var previous: Dictionary=_flight.accounting.counter_deltas
	var progress: Dictionary=_state.progress
	var earned:=Career.calculate_progress(_progress_rules,_state.campaign_cursor,
		int(progress.player_kills)+int(delta.player_kills)-int(previous.player_kills),
		int(progress.pirate_kills)+int(delta.pirate_kills)-int(previous.pirate_kills),int(progress.other_score))
	if earned.is_empty():return reject("Combat progress exceeds the supported career range")
	if delta.has("debris_destroyed"):
		var count:=int(progress.get("debris_destroyed",0))+int(delta.debris_destroyed)-int(previous.get("debris_destroyed",0))
		if not Numbers.integer(count,0,2147483647):return reject("Debris progress exceeds the supported career range")
		earned.debris_destroyed=count
	var standing: Dictionary=controller.combat_owner().current_reputation()
	if not Reputation.valid_state(standing):return reject("The flight lost its retained reputation")
	_state.progress.merge(earned,true);_state.rank=earned.rank
	_state.reputation=standing;_state.progress.reputation=standing.duplicate(true)
	_flight.accounting=accounting.duplicate(true);_flight.reputation_events=events.duplicate(true)
	_flight.elapsed_ms=scene.get("contract_result",{}).get("elapsed_ms",0)
	return true

static func credit_balance(current: int,delta: int,rules: Dictionary) -> int:
	if absi(delta)>int(rules.maximum_credit_delta):return current
	var signed:=(current+delta)&0xffffffff
	if signed>=0x80000000:signed-=0x100000000
	return maxi(int(rules.minimum_credits),signed)

func _station_inventory(equipment: RefCounted,bindings: RefCounted=null) -> Dictionary:
	if not equipment is Equipment:reject("A delivery result requires the retained station inventory");return {}
	var owned: Dictionary=equipment.snapshot()
	if not owned.get("training_inventory_released",false) or not owned.get("prototype_drill_replaced",false) or owned.get("cargo_cache_stale",true):reject("The delivery inventory is unavailable");return {}
	for key in ["base_content_id","binding_id"]:
		if owned.loadout.get(key)!=_state[key]:reject("The delivery inventory belongs to another content identity");return {}
	if bindings!=null and Campaign.supported(bindings.mido_travel,_state.campaign_cursor):
		var free_rules: Dictionary=load("res://src/content/free_flight_definitions.gd").flight(bindings,int(owned.loadout.station_id),_state.campaign_cursor)
		if free_rules.is_empty() or owned.loadout.system_id!=int(free_rules.system_id) or _state.base_content_id!=bindings.base_content_id or _state.binding_id!=bindings.binding_id:reject("The ordinary station is outside the supported content");return {}
	elif owned.loadout.system_id!=int(_rules.system_id) or owned.loadout.station_id not in _stations:reject("The delivery station is outside the supported system");return {}
	var candidate: RefCounted=equipment.fork()
	if not candidate.retain_flight_cargo(owned.cargo):reject(candidate.error);return {}
	return owned

func snapshot() -> Dictionary:
	var result:=_state.duplicate(true)
	if not _flight.is_empty():result.flight=_flight.duplicate(true)
	if _lounges!=null:result.lounges=_lounges.snapshot()
	return result

func fork() -> RefCounted:
	var result: RefCounted=get_script().new()
	result._state=_state.duplicate(true);result._rules=_rules.duplicate(true);result._cabins=_cabins.duplicate()
	result._progress_rules=_progress_rules.duplicate(true);result._stations=_stations.duplicate();result._result_inventory=_result_inventory.duplicate(true)
	result._flight=_flight.duplicate(true);result._pending_flight=_pending_flight.duplicate(true)
	result._flight_identity=_flight_identity
	result._lounges=_lounges.fork() if _lounges!=null else null
	return result

func reject(message: String) -> bool:error=message;return false
func fail(message: String) -> Dictionary:reject(message);return {}
