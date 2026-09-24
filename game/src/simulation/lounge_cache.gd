extends RefCounted
## Native location retention. Supported selections generate stock before contacts;
## all inputs remain explicit and failed preparations leave the cache intact.
const Definitions=preload("res://src/content/lounge_lifecycle_definitions.gd")
const Contacts=preload("res://src/simulation/lounge_contacts.gd")
const Stock=preload("res://src/simulation/station_stock.gd")
const Navigation=preload("res://src/simulation/contract_navigation.gd")
const NavigationDefinitions=preload("res://src/content/base_contract_navigation_definitions.gd")
const Ordinary=preload("res://src/content/ordinary_generation_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Reputation=preload("res://src/simulation/faction_reputation.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Shopping=preload("res://src/content/ordinary_shopping_definitions.gd")
const DeepScience=preload("res://src/content/deep_science_stock_definitions.gd")
var error:=""
var _state:={}
var _deep_science:={}

func configure(bindings: RefCounted) -> bool:
	error=""
	if not _state.is_empty() or not Definitions.available(bindings):return reject("This content has no supported contact retention")
	if DeepScience.available(bindings):_deep_science=bindings.deep_science_stock.duplicate(true)
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"capacity":int(bindings.early_contracts.station_lounges.capacity),"locations":[],"history":[]}
	if Stock.available(bindings):
		_state.history=bindings.early_contracts.station_generation.initial_history.duplicate()
		_state.current_station_id=-1;_state.random={}
	return true

func select_location(bindings: RefCounted,cat: RefCounted,library: RefCounted,context: Variant,settings: Variant,random_state: Variant,unix_seconds: Variant) -> bool:
	error=""
	if _state.is_empty() or not Stock.available(bindings) or cat==null or library==null:return reject("This cache cannot generate early station stock")
	if bindings.base_content_id!=_state.base_content_id or bindings.binding_id!=_state.binding_id or cat.content_id!=_state.base_content_id or library.manifest.get("content_id")!=_state.base_content_id:return reject("The selected location belongs to another content identity")
	var rules: Dictionary=bindings.early_contracts.station_generation
	var alioth_return: bool=context is Dictionary and context.get("campaign_cursor")==17 and context.get("station_id")==98 and load("res://src/content/alioth_return_definitions.gd").available(bindings)
	var ordinary: bool=context is Dictionary and Ordinary.location_supported(bindings,cat,context.get("campaign_cursor"),context.get("station_id"))
	if not context is Dictionary or context.size()!=4 or (not ordinary and not Numbers.integer(context.get("campaign_cursor"),int(rules.first_cursor),17 if alioth_return else int(rules.last_cursor))) or not Numbers.integer(context.get("rank"),0,bindings.opening_handoff.rank_thresholds.size()-1) or not Reputation.valid_state(context.get("reputation")):return reject("Retain the career at the time of location selection")
	var mido: bool=context.get("station_id") in cat.tables.systems[int(rules.system_id)].station_ids
	var base: bool=NavigationDefinitions.available(bindings) and context.get("station_id")==int(bindings.early_contracts.base_navigation.arrival_station_id) and context.campaign_cursor==int(bindings.early_contracts.base_navigation.arrival_cursor)
	if not mido and not base and not alioth_return and not ordinary:return reject("The selected location has no supported contact generation")
	var random:=Random.new()
	if not random.restore(random_state):return reject(random.error)
	var cached:=location(context.station_id)
	if not cached.is_empty():
		if not cached.has("stock"):return reject("This previously supplied population lacks its original stock")
		_state.current_station_id=context.station_id;_state.random=random.snapshot()
		return true
	if alioth_return:return reject("Alioth return requires its retained original stock and contacts")
	if not settings is Dictionary or settings.size()!=(6 if base or ordinary else 5) or not settings.get("valkyrie_owned") is bool:return reject("Retain explicit stock settings")
	var availability: Array=_state.get("system_availability",[]).duplicate()
	if NavigationDefinitions.available(bindings):
		if availability.is_empty():availability=Navigation.initial_availability(bindings,cat,settings.valkyrie_owned)
		if not Navigation.valid_availability(bindings.early_contracts.base_navigation,availability):return reject("Retain the career's available systems")
	var stock_context: Dictionary=settings.duplicate(true)
	stock_context.station_id=context.station_id;stock_context.campaign_cursor=context.campaign_cursor
	if not _deep_science.is_empty() and context.station_id==int(_deep_science.station_id):
		# Native careers start with a fresh profile and do not import original or
		# global medals. One required gold medal cannot be earned before this
		# source-defined story cursor. Later profiles need a retained medal owner.
		if context.campaign_cursor>=int(_deep_science.required_campaign_cursor):return reject("Deep Science requires the career's retained medal progress")
		stock_context.all_base_medals_gold=false
	var stock:=Stock.new()
	if not stock.prepare(bindings,cat,stock_context,random.snapshot(),unix_seconds):return reject(stock.error)
	var contacts:=Contacts.new()
	var contact_context: Dictionary=context.duplicate(true)
	if base or ordinary:contact_context.system_availability=availability.duplicate()
	if ordinary:contact_context.difficulty=settings.difficulty
	if not contacts.prepare(bindings,cat,library,contact_context,stock.snapshot().random,_state.history):return reject(contacts.error)
	if not remember(contacts,stock):return false
	if not availability.is_empty():_state.system_availability=availability
	_state.current_station_id=context.station_id;_state.random=contacts.snapshot().random
	return true

func remember(contacts: RefCounted,stock: RefCounted=null) -> bool:
	error=""
	if _state.is_empty() or not contacts is Contacts:return reject("Retain a prepared lounge population")
	var population: Dictionary=contacts.snapshot()
	for key in ["base_content_id","binding_id"]:
		if population.get(key)!=_state[key]:return reject("The contacts belong to another content identity")
	var station: int=population.context.station_id
	if not location(station).is_empty():return reject("Keep the existing location's contacts")
	if not _state.history.is_empty() and population.initial_history!=_state.history:return reject("The lounge lost the retained mission-type history")
	var inventory:={}
	if stock!=null:
		if not stock is Stock:return reject("Retain a prepared station stock owner")
		inventory=stock.snapshot()
		for key in ["base_content_id","binding_id"]:
			if inventory.get(key)!=_state[key]:return reject("Stock and contacts belong to different content identities")
		for key in ["station_id","campaign_cursor"]:
			if inventory.context[key]!=population.context[key]:return reject("Stock and contacts came from different selections")
		if inventory.random!=population.initial_random:return reject("Stock must advance the shared stream before contacts")
		if not _deep_science.is_empty() and station==int(_deep_science.station_id):
			if inventory.context.campaign_cursor>=int(_deep_science.required_campaign_cursor) or inventory.context.get("all_base_medals_gold")!=false:return reject("This native career cannot retain all-gold Deep Science stock")
	var offers:={}
	for contact in population.contacts:
		if not contact.offer.is_empty():offers[int(contact.contact_id)]={"offer":contact.offer.duplicate(true),"consumed":false}
	# Hits never reach this insertion path. FIFO retains the original terms even
	# if the pilot's rank or standing changes during a later visit.
	if _state.locations.size()==_state.capacity:_state.locations.pop_front()
	var entry:={"station_id":station,"population":population,"offers":offers}
	if not inventory.is_empty():entry.stock=inventory
	_state.locations.append(entry)
	_state.history=population.history.duplicate()
	return true

func consume(station_id: int,offer_id: int) -> bool:
	error=""
	for entry in _state.get("locations",[]):
		if entry.station_id!=station_id:continue
		if not entry.offers.has(offer_id) or entry.offers[offer_id].consumed:return reject("This cached contact has no available offer")
		entry.offers[offer_id].consumed=true
		return true
	return reject("The accepted contact has no retained lounge")

func location(station_id: int) -> Dictionary:
	for entry in _state.get("locations",[]):
		if entry.station_id==station_id:return entry.duplicate(true)
	return {}

func item_stock(station_id: int) -> Array:
	var entry:=location(station_id)
	if entry.is_empty() or not entry.has("stock"):return []
	# Keep generation evidence alongside the current mutable inventory. FIFO
	# retention owns both; revisiting a station does not regenerate either.
	return entry.get("market_items",entry.stock.items).duplicate(true)

func replace_item_stock(bindings: RefCounted,cat: RefCounted,station_id: int,expected: Array,items: Array,random_state: Dictionary={}) -> bool:
	error=""
	if Shopping.location(bindings,cat,station_id).is_empty() or _state.get("current_station_id")!=station_id:return reject("Shopping requires the currently retained station")
	for key in ["base_content_id","binding_id"]:
		if _state.get(key)!=bindings.get(key):return reject("The station inventory belongs to another content identity")
	if expected!=item_stock(station_id) or not Shopping.valid_stock(items,cat.tables.items.size()):return reject("The station quote changed or contains invalid stock")
	var rng:=Random.new()
	if not random_state.is_empty() and not rng.restore(random_state):return reject(rng.error)
	for entry in _state.locations:
		if entry.station_id!=station_id:continue
		entry.market_items=items.duplicate(true)
		if not random_state.is_empty():_state.random=rng.snapshot()
		return true
	return reject("This location has no retained stock")

func snapshot() -> Dictionary:return _state.duplicate(true)

func selection_state() -> Dictionary:
	return {"current_station_id":int(_state.get("current_station_id",-1)),"random":_state.get("random",{}).duplicate(),
		"system_availability":_state.get("system_availability",[]).duplicate()}

func adopt_selection_random(random_state: Dictionary) -> bool:
	error=""
	var random:=Random.new()
	if not random.restore(random_state):error=random.error;return false
	_state.random=random.snapshot()
	return true

func acknowledge_campaign_coordinates(bindings: RefCounted,visit: RefCounted) -> bool:
	# The career transaction supplies the same acknowledged native dialogue.
	# Availability is independent of visited locations and retained market stock.
	error=""
	if not is_instance_of(visit,load("res://src/simulation/campaign_visit.gd")):return reject("Coordinates require an acknowledged campaign conversation")
	var receipt: Dictionary=visit.transition()
	if receipt.is_empty():return reject("Acknowledge the complete conversation before receiving coordinates")
	var rules: Dictionary=load("res://src/content/kappa_return_definitions.gd").conversation(bindings,receipt.get("from_cursor"),receipt.get("previous_mission"))
	if rules.is_empty() or not load("res://src/content/opening_escape_definitions.gd").equal_value(receipt.get("unlock_system_ids"),rules.unlock_system_ids):return reject("The conversation changed its declared coordinates")
	for key in ["base_content_id","binding_id"]:
		if _state.get(key)!=bindings.get(key) or receipt.get(key)!=_state[key]:return reject("Coordinates belong to another content identity")
	if _state.get("current_station_id")!=receipt.get("station_id") or location(receipt.station_id).is_empty():return reject("Coordinates require the conversation's retained station")
	var available: Variant=_state.get("system_availability")
	if not Navigation.valid_availability(bindings.early_contracts.base_navigation,available):return reject("Coordinates lost the career's existing available systems")
	var next: Array=available.duplicate()
	for id in receipt.unlock_system_ids:
		if not id is int or id<0 or id>=next.size():return reject("The campaign names an invalid system")
		next[id]=true
	_state.system_availability=next
	return true

func fork() -> RefCounted:
	var result: RefCounted=get_script().new()
	result._state=_state.duplicate(true)
	result._deep_science=_deep_science.duplicate(true)
	return result
func reject(message: String) -> bool:error=message;return false
