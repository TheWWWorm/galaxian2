extends RefCounted
## Native lounge population assembled from imported names, portrait parts,
## catalogue offers and verified distributions. The supplied random state and
## mission-type history are retained explicitly, including discarded draws.
const Terms=preload("res://src/content/early_contract_definitions.gd")
const Offer=preload("res://src/simulation/contract_offer.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Cursor=preload("res://src/content/binary_cursor.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Reputation=preload("res://src/simulation/faction_reputation.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
const Navigation=preload("res://src/simulation/contract_navigation.gd")
const MAX_DRAWS=65536
var error:=""
var _state:={}
var _rules:={}
var _names:=[]
var _rng: RefCounted
var _history:=[]
var _draws:=0
var _stations:=[]
var _items:=[]
var _navigation:={}
var _context:={}
var _catalogues: RefCounted
var _ordinary:={}

static func available(bindings: RefCounted) -> bool:
	return bindings!=null and Terms.generation_parameters(bindings.early_contracts)

func prepare(bindings: RefCounted,cat: RefCounted,library: RefCounted,context: Variant,random_state: Variant,history: Variant) -> bool:
	error=""
	if not available(bindings) or cat==null or library==null or cat.content_id!=bindings.base_content_id or library.manifest.get("content_id")!=bindings.base_content_id:return reject("Early lounge population requires matching supported content")
	var rules: Dictionary=bindings.early_contracts.generation
	if not context is Dictionary or not Numbers.integer(context.get("rank"),0,bindings.opening_handoff.rank_thresholds.size()-1) or not Reputation.valid_state(context.get("reputation")):return reject("Lounge population requires its retained career")
	var ordinary: bool=context.size()==6 and Navigation.ordinary_context(bindings,cat,context) and context.get("difficulty") in [0.5,1.0,1.5]
	var base: bool=context.size()==5 and Navigation.arrival_context(bindings,cat,context)
	if not ordinary and (not Numbers.integer(context.get("campaign_cursor"),Terms.first_generation_cursor(bindings.early_contracts),int(rules.last_cursor)) or (not base and context.size()!=4)):return reject("Unsupported lounge generation context")
	var system_id:=int(bindings.early_contracts.base_navigation.arrival_system_id) if base else int(rules.system_id)
	if ordinary:system_id=int(cat.tables.stations[context.station_id].system_id)
	var stations: Array=cat.tables.systems[system_id].station_ids
	if not Numbers.integer(context.get("station_id"),0,cat.tables.stations.size()-1) or context.station_id not in stations:return reject("The early lounge must be in Mido")
	if not history is Array or history.size()!=int(rules.mission_history.size) or not history.all(func(value):return value is bool):return reject("Retain the source mission-type history between lounge visits")
	var candidate: RefCounted=get_script().new()
	candidate._rng=Random.new()
	if not candidate._rng.restore(random_state):return reject(candidate._rng.error)
	candidate._rules=rules.duplicate(true);candidate._history=history.duplicate();candidate._stations=stations.duplicate()
	candidate._context=context.duplicate(true);candidate._catalogues=cat
	if ordinary:
		candidate._ordinary=bindings.early_contracts.ordinary_generation.duplicate(true)
		var persistent: Dictionary=candidate._ordinary.persistent
		var data: PackedByteArray=library.read_resource(persistent.resource,1024*1024)
		if data.is_empty():return reject(library.error)
		var records:=decode_persistent_contacts(data,persistent)
		if records.is_empty():return reject("Invalid original persistent contact table")
		if records.any(func(record):return record.fields[int(persistent.station_field)]==context.station_id):return reject("This location requires an unsupported persistent contact")
	if base or ordinary:
		candidate._navigation=bindings.early_contracts.base_navigation.duplicate(true)
		if not range(cat.tables.stations.size()).any(func(id):return Navigation.eligible(candidate._navigation,cat,system_id,context.system_availability,id)):return reject("No source contract destination is available")
	for resource in rules.names.resources:
		var data: PackedByteArray=library.read_resource(resource,1024*1024)
		if data.is_empty():return reject(library.error)
		var names:=decode_names(data)
		if names.is_empty():return reject("Invalid original name table: "+resource)
		candidate._names.append(names)
	for item in cat.tables.items:
		var values: Array=item.arrays[2]
		if values.size()<=int(rules.merchant.maximum_price_value_index):return reject("Contact trade item properties are unavailable")
		candidate._items.append({"blueprint":not item.arrays[int(rules.merchant.blueprint_array)].is_empty(),
			"category":int(values[int(rules.merchant.category_value_index)]),"availability":int(values[int(rules.merchant.availability_value_index)]),
			"price":prototype_price(int(values[int(rules.merchant.minimum_price_value_index)]),int(values[int(rules.merchant.maximum_price_value_index)]))})
	if not range(candidate._items.size()).any(func(id):return candidate._merchant_eligible(id)):return reject("There are no eligible source contact trade items")
	var system_faction:=int(cat.tables.systems[system_id].fields[int(rules.system_faction_field)])
	var contacts:=[]
	# Early locations have no persistent contacts. Ordinary supported locations
	# are checked against the original catalogue before using this zero-count path.
	for ignored in int(rules.count.preliminary_draws):candidate._draw(int(rules.count.draw_bound))
	var count: int=int(rules.count.minimum)+candidate._draw(int(rules.count.draw_bound))
	var roster_seen:=false
	for id in count:
		var contact: Dictionary=candidate._contact(system_faction)
		if not candidate.error.is_empty():return reject(candidate.error)
		contact.contact_id=id;contact.offer={}
		if ordinary and contact.role==int(candidate._ordinary.roster.role):
			if roster_seen:contact.role=int(candidate._ordinary.roster.duplicate_role)
			roster_seen=true
		if contact.role==int(rules.identity.contract_role):
			var offer_context: Dictionary=context.duplicate(true);offer_context.client_faction=contact.faction
			if ordinary:offer_context.erase("difficulty")
			var quote: Dictionary=candidate._offer(bindings,cat,offer_context)
			if quote.is_empty():return reject(candidate.error)
			contact.offer=quote
			var reward:=int(quote.mission.reward)
			var roll: int=candidate._draw(auxiliary_bound(reward,int(rules.auxiliary_amount.draw_divisor)))
			var amount:=int(Vitals.single(float(roll)+Vitals.single(float(reward)/float(rules.auxiliary_amount.divisor))))
			contact.source_auxiliary_amount=Offer.quantize_credits(float(amount),int(bindings.early_contracts.reward.credit_step))
		contacts.append(contact)
	if candidate._draw(int(rules.hostile_replacement.percentage_bound))<int(rules.hostile_replacement.threshold):
		for value in rules.hostile_replacement.factions:
			var faction:=int(value)
			if not is_hostile(context.reputation,faction,int(rules.hostile_replacement.reputation_threshold)):continue
			for id in contacts.size():
				if contacts[id].role==int(rules.hostile_replacement.role):continue
				contacts[id]={"contact_id":id,"faction":faction,"male":true,"role":int(rules.hostile_replacement.role),
					"name":candidate._name(faction,true),"portrait":candidate._portrait(faction,true),"offer":{}}
				break
	if not candidate.error.is_empty():return reject(candidate.error)
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"context":context.duplicate(true),"initial_random":random_state.duplicate(true),"initial_history":history.duplicate(),
		"random":candidate._rng.snapshot(),"history":candidate._history.duplicate(),"draw_calls":candidate._draws,"contacts":contacts}
	return true

static func decode_names(data: PackedByteArray) -> Array:
	var reader:=Cursor.new(data)
	var count:=reader.be_i32()
	if count<1 or count>4096:return []
	var result:=[]
	for index in count:result.append(reader.be_string(1024))
	return result if reader.error.is_empty() and reader.remaining()==0 else []

static func decode_persistent_contacts(data: PackedByteArray,rules: Dictionary) -> Array:
	var reader:=Cursor.new(data);var result:=[]
	for id in int(rules.count):
		var name:=reader.be_string(1024)
		var fields: PackedInt32Array=reader.be_ints(int(rules.field_count))
		var indicator:=reader.be_i32()
		if not reader.error.is_empty() or fields.is_empty() or fields[0]!=id or not rules.portrait_indicators.any(func(value):return int(value)==indicator):return []
		var portrait:=[]
		if indicator>0:
			for part in int(rules.portrait_bytes):
				var value:=reader.u8();portrait.append(value-256 if value>127 else value)
		result.append({"name":name,"fields":Array(fields),"portrait":portrait})
	return result if reader.error.is_empty() and reader.remaining()==0 else []

@warning_ignore("integer_division")
static func prototype_price(low: int,high: int) -> int:return low+(high-low)/2

@warning_ignore("integer_division")
static func auxiliary_bound(reward: int,divisor: int) -> int:return reward/divisor

static func is_hostile(reputation: Dictionary,faction: int,threshold: int) -> bool:
	var axis:=0 if faction<2 else 1
	var signed_value:=int(reputation.axes[axis])*(1 if faction in [0,2] else -1)
	return signed_value < -threshold

func _contact(system_faction: int) -> Dictionary:
	var rules: Dictionary=_rules.identity
	var faction:=system_faction
	if _draw(int(rules.percentage_bound))<int(rules.foreign_threshold):faction=_draw(int(rules.faction_bound))
	var role:=-1
	var excluded: Array=rules.vossk_excluded_roles if faction==int(rules.vossk_faction) else rules.other_excluded_roles
	while role<0 or excluded.any(func(value):return int(value)==role):
		role=_draw(int(rules.role_bound))
		if not error.is_empty():return {}
	if _draw(int(rules.percentage_bound))<int(rules.contract_threshold) or (_ordinary.is_empty() and rules.early_contract_roles.any(func(value):return int(value)==role)):role=int(rules.contract_role)
	var male:=true
	var roster: bool=not _ordinary.is_empty() and role==int(_ordinary.roster.role)
	if faction==int(rules.terran_faction) and not roster:male=_draw(int(rules.percentage_bound))<int(rules.terran_male_threshold)
	var result:={"faction":faction,"male":male,"role":role,"name":_name(faction,male),"portrait":_portrait(faction,male)}
	if role==int(rules.merchant_role):result.trade=_merchant()
	if roster:
		var extra_names:=[]
		for index in _draw(int(_ordinary.roster.extra_name_bound)):extra_names.append(_name(faction,true))
		var price:=(_draw(int(_ordinary.roster.price_bound))+int(_ordinary.roster.price_add))*(extra_names.size()+1)
		if _context.difficulty==float(_ordinary.roster.hard_difficulty):price*=int(_ordinary.roster.hard_multiplier)
		result.roster={"extra_names":extra_names,"price":price}
	return result

func _name(faction: int,male: bool) -> String:
	var pools: Array=_rules.names.pool_choices_by_faction[faction]
	var selected:=[]
	# Select both tables before drawing either name. Midorian table choices
	# themselves consume randomness independently of the selected names.
	for choices in pools:
		selected.append(-1 if choices.is_empty() else int(choices[_draw(choices.size()) if choices.size()>1 else 0]))
	if faction==int(_rules.identity.terran_faction) and not male:selected[0]=int(_rules.names.female_terran_pool)
	var first: Array=_names[selected[0]]
	var result: String=first[_draw(first.size())]
	if selected[1]>=0:
		var last: Array=_names[selected[1]]
		result+=String(_rules.names.separator)+String(last[_draw(last.size())])
	return result

func _portrait(faction: int,male: bool) -> Dictionary:
	var rules: Dictionary=_rules.portraits
	var family:=faction
	if faction==int(rules.midorian_faction):family=int(rules.midorian_zero_family) if _draw(int(rules.midorian_draw_bound))==0 else int(rules.midorian_other_family)
	if not male and family==int(_rules.identity.terran_faction):family=int(rules.female_terran_family)
	if family==int(rules.cyborg_faction):family=int(rules.cyborg_family)
	var parts:=[]
	for bound in rules.counts[family]:parts.append(_draw(int(bound)))
	return {"status":"fixed","family":family,"parts":parts}

func _draw(bound: int) -> int:
	_draws+=1
	if _draws>MAX_DRAWS:reject("Lounge generation exceeded its bounded draw budget");return 0
	# The original zero-bound branch consumes 31 bits and returns zero. A
	# one-element native choice has exactly the same result and random advance.
	return _rng.next_int(maxi(1,bound))

func _destination() -> int:
	var rules: Dictionary=_rules.destinations
	if not _navigation.is_empty():
		var system:=int(_catalogues.tables.stations[int(_context.station_id)].system_id)
		while error.is_empty():
			var selected:=int(_context.station_id)
			if _draw(int(rules.percentage_bound))>=int(rules.first_threshold):
				selected=int(_stations[_draw(_stations.size())]) if _draw(int(rules.percentage_bound))<int(rules.second_threshold) else _draw(int(_navigation.global_station_bound))
			if not error.is_empty():return -1
			if Navigation.eligible(_navigation,_catalogues,system,_context.system_availability,selected):return selected
		return -1
	var selected:=-1
	while selected<0 or rules.helper_excluded_station_ids.any(func(value):return int(value)==selected):
		if _draw(int(rules.percentage_bound))>=int(rules.first_threshold):
			if _draw(int(rules.percentage_bound))<int(rules.second_threshold):_draw(_stations.size())
			else:_draw(int(rules.global_bound))
		selected=int(_stations[_draw(_stations.size())])
		if not error.is_empty():return -1
	return selected

func _offer(bindings: RefCounted,cat: RefCounted,context: Dictionary) -> Dictionary:
	var sampled:=_destination() # The general candidate precedes the Mido override.
	if not error.is_empty():return {}
	var terms: Dictionary=bindings.early_contracts
	var destination:=int(_stations[0])+_draw(int(terms.initial_destination_count)) if _navigation.is_empty() else sampled
	var kind:=_history_kind(int(context.client_faction))
	var ordinary:=not _ordinary.is_empty()
	var extra: Dictionary=_ordinary.offers if ordinary else {}
	var kind_index:=-1
	if not ordinary:
		kind_index=_draw(terms.kind_choices.size())
		kind=int(terms.kind_choices[kind_index])
	if kind==int(terms.local_challenge_kind):destination=context.station_id
	elif (extra.different_destination_kinds if ordinary else terms.delivery_kinds).any(func(value):return int(value)==kind):
		while destination==context.station_id:
			destination=_destination()
			if not error.is_empty():return {}
	if ordinary and kind==int(extra.faction_destination_kind) and context.client_faction<int(extra.major_faction_count):
		var system:=int(cat.tables.stations[context.station_id].system_id)
		if cat.tables.systems[system].arrays[int(extra.faction_required_system_array)].is_empty():kind=int(extra.faction_fallback_kinds[_draw(extra.faction_fallback_kinds.size())])
		else:
			# This branch discards even an already matching initial destination.
			while error.is_empty():
				destination=_destination()
				if destination<0:return {}
				if int(cat.tables.systems[cat.tables.stations[destination].system_id].fields[int(_rules.system_faction_field)])==context.client_faction:break
	var difficulty:=_draw(int(extra.difficulty_draw_bound) if ordinary else int(terms.difficulty_draw_bound))
	var description:=_draw(int(terms.courier.description_draw_bound)) if kind==int(terms.courier.kind) else 0
	var quantity_index:=0
	if ordinary:
		if kind==int(extra.random_quantity.kind):quantity_index=_draw(int(extra.random_quantity.bound))
		elif kind==int(extra.collection.kind):
			while error.is_empty():
				description=_draw(cat.tables.items.size()-int(extra.collection.first_item_id))+int(extra.collection.first_item_id)
				if not Offer.collection_item(terms,cat,description).is_empty():break
			quantity_index=_draw(int(extra.collection.quantity_bound))
	if not error.is_empty():return {}
	var offer:=Offer.new()
	var choices:={"kind":kind,"difficulty_index":difficulty,"destination_station_id":destination,"parameter_index":description,"quantity_index":quantity_index} if ordinary else {"kind_index":kind_index,"difficulty_index":difficulty,"destination_station_id":destination,"cargo_description_index":description}
	if not offer.configure(bindings,cat,context,choices):reject(offer.error);return {}
	return offer.snapshot()

func _history_kind(faction: int) -> int:
	var rules: Dictionary=_rules.mission_history
	for attempt in int(rules.draw_limit):
		var kind:=_draw(int(rules.size))
		if not error.is_empty():return -1
		var excluded: bool=rules.always_excluded.any(func(value):return int(value)==kind) or (faction>=int(rules.major_faction_count) and rules.nonmajor_excluded.any(func(value):return int(value)==kind))
		if not excluded:
			if not _history[kind]:_history[kind]=true;return kind
			if _history.count(true)==int(rules.reset_count):_history.fill(false)
		# The source accepts the last draw after its finite rejection budget,
		# including excluded/previously used kinds, without marking them anew.
		if attempt==int(rules.draw_limit)-1:return kind
	return -1

func _merchant_eligible(id: int) -> bool:
	var item: Dictionary=_items[id]
	return not _rules.merchant.excluded_item_ids.any(func(value):return int(value)==id) and not item.blueprint and item.price!=0 and item.availability!=0

func _merchant() -> Dictionary:
	var rules: Dictionary=_rules.merchant
	var id:=_draw(_items.size())
	while not _merchant_eligible(id):
		id=_draw(_items.size())
		if not error.is_empty():return {}
	var item: Dictionary=_items[id]
	var quantity:=_draw(int(rules.quantity_draw_bound))+int(rules.quantity_add)
	if rules.single_categories.any(func(value):return int(value)==int(item.category)):quantity=1
	var percent:=_draw(int(rules.price_draw_bound))+int(rules.price_add)
	var factor:=Vitals.single(float(percent)/float(rules.price_divisor))
	var unit_price:=int(Vitals.single(float(item.price)*factor))
	return {"item_id":id,"quantity":quantity,"total_price":unit_price*quantity}

func restore(bindings: RefCounted,cat: RefCounted,library: RefCounted,data: Variant) -> bool:
	error=""
	if not data is Dictionary:return reject("Invalid retained lounge population")
	var next: RefCounted=get_script().new()
	if not next.prepare(bindings,cat,library,data.get("context"),data.get("initial_random"),data.get("initial_history")):return reject(next.error)
	if data!=next.snapshot():return reject("Retained contacts disagree with their source inputs")
	_state=next._state
	return true

func snapshot() -> Dictionary:return _state.duplicate(true)
func reject(message: String) -> bool:error=message;return false
