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
const Medals=preload("res://src/simulation/base_medal_progress.gd")
const Dialogue=preload("res://src/simulation/lounge_dialogue.gd")
const ValkyrieWorlds=preload("res://src/content/valkyrie_world_definitions.gd")
var error:=""
var _state:={}
var _deep_science:={}
# Frozen observation of _state; every mutator clears it before changing state.
var _read:={}
var _social_used: Array=[]

func begin_social_visit() -> void:
	_read={};_social_used=[]

func configure(bindings: RefCounted) -> bool:
	_read={}
	error=""
	if not _state.is_empty() or not Definitions.available(bindings):return reject("This content has no supported contact retention")
	if DeepScience.available(bindings):_deep_science=bindings.deep_science_stock.duplicate(true)
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"capacity":int(bindings.early_contracts.station_lounges.capacity),"locations":[],"history":[]}
	if Stock.available(bindings):
		_state.history=bindings.early_contracts.station_generation.initial_history.duplicate()
		_state.current_station_id=-1;_state.random={}
	return true

func select_location(bindings: RefCounted,cat: RefCounted,library: RefCounted,context: Variant,settings: Variant,random_state: Variant,unix_seconds: Variant,station_context: RefCounted=null,medal_progress: Dictionary={},all_medals:=false,wanted_ships: Array=[]) -> bool:
	_read={}
	error=""
	if _state.is_empty() or not Stock.available(bindings) or cat==null or library==null:return reject("This cache cannot generate early station stock")
	if bindings.base_content_id!=_state.base_content_id or bindings.binding_id!=_state.binding_id or cat.content_id!=_state.base_content_id or library.manifest.get("content_id")!=_state.base_content_id:return reject("The selected location belongs to another content identity")
	var rules: Dictionary=bindings.early_contracts.station_generation
	var alioth_return: bool=context is Dictionary and context.get("campaign_cursor")==17 and context.get("station_id")==98 and load("res://src/content/alioth_return_definitions.gd").available(bindings)
	var ordinary: bool=context is Dictionary and Ordinary.location_supported(bindings,cat,context.get("campaign_cursor"),context.get("station_id"))
	if context is Dictionary and load("res://src/simulation/mission_station_context.gd").permits(bindings,context.get("campaign_cursor"),context.get("station_id"),station_context):ordinary=true
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
		var gold: Variant=Medals.all_base_gold(context.campaign_cursor,medal_progress)
		if gold==null:return reject("Deep Science requires the career's retained medal progress")
		stock_context.all_base_medals_gold=gold
	if Stock.medal_station(context.station_id,context.campaign_cursor):stock_context.all_supernova_medals=all_medals
	if int(context.station_id)==int(ValkyrieWorlds.WANTED_SHIPS.station_id) and not wanted_ships.is_empty():stock_context.wanted_ships=wanted_ships.duplicate()
	var stock:=Stock.new()
	if not stock.prepare(bindings,cat,stock_context,random.snapshot(),unix_seconds):return reject(stock.error)
	var contacts:=Contacts.new()
	var contact_context: Dictionary=context.duplicate(true)
	if base or ordinary:contact_context.system_availability=availability.duplicate()
	if ordinary:contact_context.difficulty=settings.difficulty
	if not contacts.prepare(bindings,cat,library,contact_context,stock.snapshot().random,_state.history,station_context):return reject(contacts.error)
	if not remember(contacts,stock,medal_progress if stock_context.has("all_base_medals_gold") else {}):return false
	if not availability.is_empty():_state.system_availability=availability
	_state.current_station_id=context.station_id;_state.random=contacts.snapshot().random
	return true

func remember(contacts: RefCounted,stock: RefCounted=null,medal_progress: Dictionary={}) -> bool:
	_read={}
	error=""
	if _state.is_empty() or not contacts is Contacts:return reject("Retain a prepared lounge population")
	var population: Dictionary=contacts.snapshot()
	for key in ["base_content_id","binding_id"]:
		if population.get(key)!=_state[key]:return reject("The contacts belong to another content identity")
	var station: int=population.context.station_id
	if not medal_progress.is_empty() and (_deep_science.is_empty() or station!=int(_deep_science.station_id) or not Medals.valid_counts(medal_progress)):return reject("Invalid retained native career medal progress")
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
			var gold: Variant=Medals.all_base_gold(inventory.context.campaign_cursor,medal_progress)
			if gold==null or inventory.context.get("all_base_medals_gold")!=gold:return reject("This native career has no retained medal result for Deep Science stock")
	var offers:={}
	for contact in population.contacts:
		if not contact.offer.is_empty():offers[int(contact.contact_id)]={"offer":contact.offer.duplicate(true),"consumed":false}
	# Hits never reach this insertion path. FIFO retains the original terms even
	# if the pilot's rank or standing changes during a later visit.
	if _state.locations.size()==_state.capacity:_state.locations.pop_front()
	var entry:={"station_id":station,"population":population,"offers":offers}
	if not inventory.is_empty():entry.stock=inventory
	if not _deep_science.is_empty() and station==int(_deep_science.station_id) and not medal_progress.is_empty():entry.medal_progress=medal_progress.duplicate(true)
	_state.locations.append(entry)
	_state.history=population.history.duplicate()
	return true

func inspect_contact(bindings: RefCounted,cat: RefCounted,context: Dictionary,contact_id: int,station_context: RefCounted=null,library: RefCounted=null) -> bool:
	_read={}
	error=""
	if context.get("station_id")!=_state.get("current_station_id"):return reject("Inspect the currently retained lounge")
	for entry in _state.locations:
		if entry.station_id!=context.station_id:continue
		var matches: Array=entry.population.contacts.filter(func(contact):return contact.contact_id==contact_id)
		if matches.size()!=1:return reject("This lounge has no such contact")
		if entry.offers.has(contact_id):return true
		var contact: Dictionary=matches[0]
		if contact.role==1 and Dialogue.available(bindings):
			var previous: Dictionary=entry.get("dialogues",{}).get(contact_id,{})
			var prepared:={};var record:={}
			if previous.is_empty():
				prepared=Dialogue.prepare(contact,_state.random,_social_used)
				if prepared.is_empty():return reject("This lounge has no unused social topic")
				record=prepared.dialogue
			else:
				if not Dialogue.valid(previous,contact,cat,library):return reject("This contact lost its retained dialogue")
				record=Dialogue.revisit(previous,contact,int(context.station_id),library)
			if not Dialogue.valid(record,contact,cat,library):return reject("The original social dialogue is unavailable")
			if not entry.has("dialogues"):entry.dialogues={}
			entry.dialogues[contact_id]=record
			if not prepared.is_empty():
				_social_used.append(prepared.raw_topic);_state.random=prepared.random
			return true
		if Contacts.Recipe.contact_request(bindings.early_contracts,int(contact.role)).is_empty():return true
		var offer_context:=context.duplicate(true)
		offer_context.client_faction=contact.faction;offer_context.system_availability=_state.system_availability.duplicate()
		var sampler:=Contacts.new()
		var requested:=sampler.request_offer(bindings,cat,offer_context,contact,_state.random,_state.history,station_context)
		if requested.is_empty():return reject(sampler.error)
		if not entry.has("requested_offers"):entry.requested_offers={}
		entry.requested_offers[contact_id]=requested
		entry.offers[contact_id]={"offer":requested.offer.duplicate(true),"consumed":false}
		_state.random=requested.random.duplicate(true);_state.history=requested.history.duplicate()
		return true
	return reject("The inspected contact has no retained lounge")

func restore_dialogues(bindings: RefCounted,cat: RefCounted,library: RefCounted,station_id: int,records: Variant) -> bool:
	_read={};error=""
	if not Dialogue.available(bindings) or not records is Dictionary or records.is_empty():return reject("Invalid saved social dialogue")
	for entry in _state.locations:
		if entry.station_id!=station_id:continue
		if records.size()>entry.population.contacts.size():return reject("Invalid social contact count")
		for id in records:
			if not id is int:return reject("Invalid saved social contact")
			var contacts: Array=entry.population.contacts.filter(func(contact):return contact.contact_id==id)
			if contacts.size()!=1 or not Dialogue.valid(records[id],contacts[0],cat,library):return reject("The saved dialogue lost its contact or original text")
		entry.dialogues=records.duplicate(true)
		return true
	return reject("The social dialogue has no retained lounge")

## Save entry verifies lazy quotes against their own sampling inputs. Requests
## may interleave visits to older cached stations, so population order alone
## does not describe the current mission history.
func restore_requested_offers(bindings: RefCounted,cat: RefCounted,station_id: int,requests: Dictionary,station_context: RefCounted=null) -> bool:
	_read={}
	error=""
	for entry in _state.locations:
		if entry.station_id!=station_id:continue
		if requests.is_empty() or requests.size()>entry.population.contacts.size():return reject("Invalid requested-offer count")
		var prepared:={}
		for id in requests:
			var record: Variant=requests[id]
			if not id is int or not record is Dictionary or not record.get("offer") is Dictionary or not record.offer.get("context") is Dictionary or not record.get("initial_random") is Dictionary or not record.get("initial_history") is Array:return reject("Invalid requested-offer inputs")
			var contacts: Array=entry.population.contacts.filter(func(contact):return contact.contact_id==id)
			if contacts.size()!=1 or entry.offers.has(id) or record.offer.context.get("station_id")!=station_id:return reject("The requested offer lost its original contact")
			var sampler:=Contacts.new()
			var expected:=sampler.request_offer(bindings,cat,record.offer.context,contacts[0],record.initial_random,record.initial_history,station_context)
			if expected.is_empty() or expected!=record:return reject("The requested offer changed its retained terms")
			prepared[id]=expected
		entry.requested_offers=prepared
		for id in prepared:entry.offers[id]={"offer":prepared[id].offer.duplicate(true),"consumed":false}
		return true
	return reject("The requested offers have no retained lounge")

func consume(station_id: int,offer_id: int) -> bool:
	_read={}
	error=""
	for entry in _state.get("locations",[]):
		if entry.station_id!=station_id:continue
		if not entry.offers.has(offer_id) or entry.offers[offer_id].consumed:return reject("This cached contact has no available offer")
		entry.offers[offer_id].consumed=true
		return true
	return reject("The accepted contact has no retained lounge")

func diplomat_contact(station_id: int,contact_id: int) -> Dictionary:
	var entry:=location(station_id)
	for contact in entry.get("population",{}).get("contacts",[]):
		if contact.contact_id!=contact_id or contact.get("role")!=7:continue
		if not Numbers.integer(contact.get("faction"),0,3):return {}
		var response: int=entry.get("used_diplomats",{}).get(contact_id,-1)
		return {"faction":int(contact.faction),"consumed":response>=0,"response_text_id":response}
	return {}

func consume_diplomat(station_id: int,contact_id: int,response_text_id: int=-1) -> bool:
	_read={};error=""
	var contact:=diplomat_contact(station_id,contact_id)
	if contact.is_empty() or contact.consumed:return reject("This diplomat is absent or has already been used")
	if response_text_id!=-1 and (response_text_id<843 or response_text_id>845):return reject("Invalid retained diplomat response")
	var random:=Random.new()
	if response_text_id<0:
		if not random.restore(_state.random):return reject(random.error)
		response_text_id=843+random.next_int(3)
	for entry in _state.locations:
		if entry.station_id!=station_id:continue
		if not entry.has("used_diplomats"):entry.used_diplomats={}
		entry.used_diplomats[contact_id]=response_text_id
		if not random.snapshot().is_empty():_state.random=random.snapshot()
		return true
	return reject("The diplomat lost its retained lounge")

func blueprint_quote(station_id: int,contact_id: int) -> Dictionary:
	for contact in location(station_id).get("population",{}).get("contacts",[]):
		if contact.contact_id!=contact_id or contact.get("role")!=3 or contact.get("generated",true) or not contact.has("blueprint"):continue
		var terms: Dictionary=contact.blueprint
		if not Numbers.integer(terms.get("item_id"),0,2147483647) or not Numbers.integer(terms.get("price"),0,2147483647):return {}
		return {"item_id":int(terms.item_id),"total_price":int(terms.price)}
	return {}

func coordinate_quote(station_id: int,contact_id: int) -> Dictionary:
	var available: Array=_state.get("system_availability",[])
	for contact in location(station_id).get("population",{}).get("contacts",[]):
		if contact.contact_id!=contact_id or contact.get("role")!=4 or not contact.has("service"):continue
		var terms: Dictionary=contact.service
		if not Numbers.integer(terms.get("parameter"),0,available.size()-1) or not Numbers.integer(terms.get("price"),0,2147483647):return {}
		var system_id:=int(terms.parameter)
		return {"system_id":system_id,"total_price":int(terms.price),"consumed":bool(available[system_id])}
	return {}

func purchase_coordinates(station_id: int,contact_id: int) -> bool:
	error=""
	if station_id!=_state.get("current_station_id") :return reject("Buy coordinates from the current station lounge")
	var quote:=coordinate_quote(station_id,contact_id)
	if quote.is_empty() or quote.consumed:return reject("This contact has no unknown coordinates for sale")
	# Known coordinates outlive the FIFO lounge cache and already survive saves.
	# Never charge again after revisiting or restoring an older earned career.
	var available: Array=_state.system_availability.duplicate()
	available[int(quote.system_id)]=true
	_read={};_state.system_availability=available
	return true

func merchant_quote(station_id: int,contact_id: int) -> Dictionary:
	var entry:=location(station_id)
	for contact in entry.get("population",{}).get("contacts",[]):
		if contact.contact_id==contact_id and contact.has("trade"):
			var result: Dictionary=contact.trade.duplicate(true)
			result.consumed=contact_id in entry.get("purchased_goods",[])
			return result
	return {}

func kaamo_contact(station_id: int,contact_id: int) -> Dictionary:
	var entry:=location(station_id)
	for contact in entry.get("population",{}).get("contacts",[]):
		if contact.contact_id==contact_id and contact.has("kaamo"):
			var result: Dictionary=contact.kaamo.duplicate(true)
			result.consumed=contact_id in entry.get("purchased_goods",[])
			return result
	return {}

## A Kaamo dealer sells once per bar generation ("nothing left" afterwards).
func consume_kaamo(station_id: int,contact_id: int) -> bool:
	_read={};error=""
	var contact:=kaamo_contact(station_id,contact_id)
	if contact.is_empty():return reject("This Kaamo agent is not in the lounge")
	if contact.consumed:return reject("This Kaamo agent has nothing left")
	for entry in _state.locations:
		if entry.station_id==station_id:
			if not entry.has("purchased_goods"):entry.purchased_goods=[]
			entry.purchased_goods.append(contact_id)
			return true
	return reject("The Kaamo agent lost its retained lounge")

func consume_goods(station_id: int,contact_id: int) -> bool:
	_read={};error=""
	var quote:=merchant_quote(station_id,contact_id)
	if quote.is_empty() or quote.consumed:return reject("This merchant has no remaining goods")
	for entry in _state.locations:
		if entry.station_id==station_id:
			if not entry.has("purchased_goods"):entry.purchased_goods=[]
			entry.purchased_goods.append(contact_id)
			return true
	return reject("The merchant lost its retained lounge")

## A hired wingman captain has taken his offer (SpaceLounge::onKeyPress, offer
## 6: Agent::setOfferAccepted); kept with the lounge's purchases.
func consume_wingmen(station_id: int,contact_id: int) -> bool:
	_read={};error=""
	for entry in _state.locations:
		if entry.station_id!=station_id:continue
		if contact_id in entry.get("purchased_goods",[]) or not entry.population.contacts.any(func(contact):return contact.contact_id==contact_id and contact.get("role")==6):return reject("This wingman captain is absent or already hired")
		if not entry.has("purchased_goods"):entry.purchased_goods=[]
		entry.purchased_goods.append(contact_id)
		return true
	return reject("The wingmen lost their retained lounge")

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

func ship_stock(station_id: int) -> Array:
	var entry:=location(station_id)
	if entry.is_empty() or not entry.has("stock"):return []
	return entry.get("market_ships",entry.stock.ships).duplicate(true)

func replace_ship_stock(bindings: RefCounted,cat: RefCounted,station_id: int,expected: Array,ships: Array) -> bool:
	_read={}
	error=""
	if Shopping.location(bindings,cat,station_id).is_empty() or _state.get("current_station_id")!=station_id:return reject("Ship exchange requires the currently retained station")
	for key in ["base_content_id","binding_id"]:
		if _state.get(key)!=bindings.get(key):return reject("The ship market belongs to another content identity")
	if expected!=ship_stock(station_id) or not preload("res://src/simulation/ship_instance.gd").valid_offers(ships,cat):return reject("The ship quote changed or contains invalid stock")
	for entry in _state.locations:
		if entry.station_id!=station_id:continue
		entry.market_ships=ships.duplicate(true)
		return true
	return reject("This location has no retained ships")

func replace_item_stock(bindings: RefCounted,cat: RefCounted,station_id: int,expected: Array,items: Array,random_state: Dictionary={}) -> bool:
	_read={}
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
## Shared read-only observation for per-frame career snapshots.
func read_snapshot() -> Dictionary:
	if _read.is_empty():_read=preload("res://src/simulation/readonly_state.gd").freeze(_state.duplicate(true))
	return _read

func selection_state() -> Dictionary:
	return {"current_station_id":int(_state.get("current_station_id",-1)),"random":_state.get("random",{}).duplicate(),
		"system_availability":_state.get("system_availability",[]).duplicate()}

func adopt_selection_random(random_state: Dictionary) -> bool:
	_read={}
	error=""
	var random:=Random.new()
	if not random.restore(random_state):error=random.error;return false
	_state.random=random.snapshot()
	return true

## A story flight that moves the career on in space opens its systems here.
func unlock_story_systems(navigation: Dictionary,ids: Array) -> bool:
	_read={};error=""
	var available: Variant=_state.get("system_availability")
	if not Navigation.valid_availability(navigation,available):return reject("Story coordinates lost the career's existing available systems")
	var next: Array=available.duplicate()
	for id in ids:
		if not id is int or id<0 or id>=next.size():return reject("The story names an invalid system")
		next[id]=true
	_state.system_availability=next
	return true

func acknowledge_campaign_coordinates(bindings: RefCounted,visit: RefCounted) -> bool:
	_read={}
	# The career transaction supplies the same acknowledged native dialogue.
	# Availability is independent of visited locations and retained market stock.
	error=""
	if not is_instance_of(visit,load("res://src/simulation/campaign_visit.gd")):return reject("Coordinates require an acknowledged campaign conversation")
	var receipt: Dictionary=visit.transition()
	if receipt.is_empty():return reject("Acknowledge the complete conversation before receiving coordinates")
	var rules: Dictionary=load("res://src/content/free_campaign_definitions.gd").dialogue_rules(bindings,receipt.get("from_cursor"),receipt.get("previous_mission"),true)
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
	result._deep_science=_deep_science.duplicate(true);result._read=_read
	result._social_used=_social_used.duplicate()
	return result
func reject(message: String) -> bool:error=message;return false
