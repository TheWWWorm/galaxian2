extends RefCounted
## Native quotation from explicit sampled choices and retained availability.
## Contact generation, acceptance, objectives and settlement have separate owners.
const Definitions=preload("res://src/content/early_contract_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Reputation=preload("res://src/simulation/faction_reputation.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
const Navigation=preload("res://src/simulation/contract_navigation.gd")
var error:=""
var _state:={}

static func available(bindings: RefCounted) -> bool:
	return bindings!=null and Definitions.parameters(bindings.early_contracts)

func configure(bindings: RefCounted,catalogues: RefCounted,context: Variant,choices: Variant) -> bool:
	error=""
	if not available(bindings) or catalogues==null or catalogues.content_id!=bindings.base_content_id:
		return reject("Early contract terms are unavailable for this content")
	var rules: Dictionary=bindings.early_contracts
	if not context is Dictionary:return reject("An offer requires its retained campaign context")
	var ordinary: bool=context.size()==6 and Navigation.ordinary_context(bindings,catalogues,context)
	var base: bool=context.size()==6 and Navigation.arrival_context(bindings,catalogues,context)
	if not ordinary and (not Numbers.integer(context.get("campaign_cursor"),Definitions.first_generation_cursor(rules),int(rules.last_cursor)) or (not base and context.size()!=5)):return reject("Unsupported quotation context")
	if not Numbers.integer(context.get("rank"),0,bindings.opening_handoff.get("rank_thresholds",[]).size()-1) or not Reputation.valid_state(context.get("reputation")) or not Numbers.integer(context.get("client_faction"),0,7):
		return reject("An offer requires the retained rank and faction standing")
	var systems: Array=catalogues.tables.get("systems",[])
	var stations: Array=catalogues.tables.get("stations",[])
	var system_id:=int(rules.base_navigation.arrival_system_id) if base else int(rules.system_id)
	if ordinary:system_id=int(stations[context.station_id].system_id)
	if systems.size()<=system_id or not Numbers.integer(context.get("station_id"),0,stations.size()-1):
		return reject("The offer station is absent from this catalogue")
	var station_ids: Array=systems[system_id].station_ids
	if (not ordinary and station_ids.size()<int(rules.initial_destination_count)) or context.station_id not in station_ids or stations[context.station_id].system_id!=system_id:
		return reject("The offer location is outside its supported system")
	var extra: Dictionary=rules.ordinary_generation.offers if ordinary else {}
	if not choices is Dictionary:return reject("Unsupported contract selection")
	if ordinary:
		if choices.size()!=5 or not Numbers.integer(choices.get("kind"),0,int(extra.kind_count)-1) or not Numbers.integer(choices.get("difficulty_index"),0,int(extra.difficulty_draw_bound)-1):return reject("Unsupported ordinary contract selection")
	elif choices.size()!=4 or not Numbers.integer(choices.get("kind_index"),0,rules.kind_choices.size()-1) or not Numbers.integer(choices.get("difficulty_index"),0,int(rules.difficulty_draw_bound)-1):return reject("Unsupported early contract selection")
	var kind:=int(choices.kind) if ordinary else int(rules.kind_choices[choices.kind_index])
	var difficulty:=int(choices.difficulty_index)+int(rules.difficulty_add)
	var destination: Variant=choices.get("destination_station_id")
	if not Numbers.integer(destination,0,stations.size()-1):return reject("The contract destination is absent")
	var navigable:=base or ordinary
	if not navigable and (destination not in station_ids or stations[destination].system_id!=system_id):return reject("An early Mido destination must remain in Mido")
	if navigable and kind!=int(rules.local_challenge_kind) and not Navigation.eligible(rules.base_navigation,catalogues,system_id,context.system_availability,int(destination)):return reject("This destination is excluded or unavailable")
	if kind==int(rules.local_challenge_kind):
		if destination!=context.station_id:return reject("The challenge takes place outside its contact's station")
	elif (extra.different_destination_kinds if ordinary else rules.delivery_kinds).any(func(value):return int(value)==kind):
		if destination==context.station_id:return reject("A delivery cannot finish at its origin station")
		if not navigable and destination not in station_ids.slice(0,int(rules.initial_destination_count)):return reject("This destination is excluded from early Mido delivery offers")
	elif not navigable and destination not in station_ids.slice(0,int(rules.initial_destination_count)):
		return reject("The early encounter destination is outside its source selection")
	if ordinary and kind==int(extra.faction_destination_kind) and context.client_faction<int(extra.major_faction_count):
		if systems[system_id].arrays[int(extra.faction_required_system_array)].is_empty() or int(systems[stations[destination].system_id].fields[int(rules.generation.system_faction_field)])!=context.client_faction:return reject("The faction offer requires a destination of its client's faction")
	var description_limit:=int(rules.courier.description_draw_bound)-1 if kind==int(rules.courier.kind) else 0
	var description: Variant=choices.get("parameter_index") if ordinary else choices.get("cargo_description_index")
	var collection:={}
	if ordinary and kind==int(extra.collection.kind):
		collection=collection_item(rules,catalogues,description)
		if collection.is_empty():return reject("The collection offer requires an eligible original item")
		difficulty=mini(int(collection.difficulty),int(extra.difficulty_maximum))
	elif not Numbers.integer(description,0,description_limit):
		return reject("Invalid courier cargo description")
	if ordinary:
		var quantity_bound:=int(extra.collection.quantity_bound) if not collection.is_empty() else (int(extra.random_quantity.bound) if kind==int(extra.random_quantity.kind) else 1)
		if not Numbers.integer(choices.get("quantity_index"),0,quantity_bound-1):return reject("Invalid ordinary quantity selection")
	var quantity:=0
	var requirements:={"cargo_tons":0,"passenger_places":0,"cargo_item_id":-1,"capacity_text_id":-1}
	var source_parameter:=0
	var cargo_text_id:=-1
	if kind==int(rules.courier.kind):
		quantity=scaled_quantity(difficulty,extra.courier_quantity,float(rules.reward.difficulty_divisor)) if ordinary else int(rules.courier.quantity_by_difficulty[choices.difficulty_index])
		source_parameter=int(description)
		cargo_text_id=int(rules.courier.description_text_base)+source_parameter
		requirements={"cargo_tons":quantity,"passenger_places":0,"cargo_item_id":int(rules.courier.cargo_item_id),"capacity_text_id":int(rules.courier.capacity_text_id)}
	elif kind==int(rules.passenger.kind):
		quantity=scaled_quantity(difficulty,extra.passenger_quantity,float(rules.reward.difficulty_divisor)) if ordinary else int(rules.passenger.quantity_by_difficulty[choices.difficulty_index])
		requirements.passenger_places=quantity
		requirements.capacity_text_id=int(rules.passenger.capacity_text_id)
	elif ordinary:
		if not collection.is_empty():
			source_parameter=int(description);quantity=int(choices.quantity_index)+int(extra.collection.quantity_add)
		elif kind==int(extra.random_quantity.kind):quantity=int(choices.quantity_index)+int(extra.random_quantity.add)
		else:
			for index in extra.item_quantity.kinds.size():
				if kind==int(extra.item_quantity.kinds[index]):
					source_parameter=int(extra.item_quantity.parameters[index])
					quantity=scaled_quantity(difficulty,extra.item_quantity,float(rules.reward.difficulty_divisor))
	var pricing: Dictionary=rules.reward
	var raw:=float(int(Vitals.single(Vitals.single(float(difficulty)/float(pricing.difficulty_divisor))*float(pricing.difficulty_multiplier)))+int(pricing.base))
	if navigable:
		var distance:=Navigation.distance(rules.base_navigation,catalogues,system_id,int(stations[destination].system_id))
		var factor:=Vitals.single(Vitals.single(distance/float(pricing.distance_divisor))+1.0)
		raw=Vitals.single(raw*factor)
	if kind==int(pricing.junk_kind):raw=Vitals.single(raw*float(pricing.junk_multiplier))
	if ordinary and extra.reward_multipliers.has(str(kind)):raw=Vitals.single(raw*float(extra.reward_multipliers[str(kind)]))
	if not collection.is_empty():raw=Vitals.single(float(int(collection.price)*quantity)*float(extra.collection.reward_multiplier))
	if kind==int(rules.passenger.kind):
		raw=Vitals.single(raw*float(pricing.passenger_multiplier))
		var per_passenger:=Vitals.single(raw/float(pricing.passenger_quantity_divisor))
		raw=Vitals.single(raw+Vitals.single(float(quantity)*per_passenger))
	var rank: int=context.rank
	var rank_reward:=rank*rank*rank*int(pricing.rank_cubic_multiplier)
	var gross:=Vitals.single(raw+float(rank_reward))
	var bonus:=0
	if not (extra.bonus_excluded_kinds if ordinary else rules.bonus.excluded_kinds).any(func(value):return int(value)==kind):
		var faction: int=context.client_faction
		if faction<rules.bonus.faction_axes.size():
			var standing:=int(context.reputation.axes[int(rules.bonus.faction_axes[faction])])*int(rules.bonus.faction_signs[faction])
			var ratio:=maxf(float(rules.bonus.minimum),Vitals.single(float(standing)/float(rules.bonus.divisor)))
			bonus=quantize_credits(Vitals.single(gross*ratio),int(pricing.credit_step))
	var mission:={"kind":kind,"story":false,"station_id":int(destination),"system_id":int(stations[destination].system_id),
		"difficulty":difficulty,"source_parameter":source_parameter,"quantity":quantity,
		"reward":quantize_credits(gross,int(pricing.credit_step)),"bonus":bonus,
		"title_text_id":int(rules.title_text_base)+kind,"briefing_text_id":int(rules.briefing_text_base)+kind,
		"cargo_text_id":cargo_text_id}
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"context":context.duplicate(true),"choices":choices.duplicate(true),"mission":mission,"requirements":requirements}
	return true

static func scaled_quantity(difficulty: int,rule: Dictionary,divisor: float) -> int:
	return int(Vitals.single(Vitals.single(float(difficulty)/divisor)*float(rule.multiplier)))+int(rule.add)

@warning_ignore("integer_division")
static func collection_item(rules: Dictionary,cat: RefCounted,id: Variant) -> Dictionary:
	var rule: Dictionary=rules.get("ordinary_generation",{}).get("offers",{}).get("collection",{})
	if rule.is_empty() or not Numbers.integer(id,int(rule.first_item_id),cat.tables.items.size()-1) or rule.excluded_item_ids.any(func(value):return int(value)==id):return {}
	var merchant: Dictionary=rules.generation.merchant
	var item: Dictionary=cat.tables.items[id];var values: Array=item.arrays[2]
	if values.size()<=maxi(int(rule.price_value_index),int(rule.difficulty_value_index)) or not item.arrays[int(merchant.blueprint_array)].is_empty():return {}
	var low:=int(values[int(merchant.minimum_price_value_index)])
	var high:=int(values[int(merchant.maximum_price_value_index)])
	if int(values[int(merchant.availability_value_index)])==0 or low+(high-low)/2==0:return {}
	return {"difficulty":int(values[int(rule.difficulty_value_index)]),"price":int(values[int(rule.price_value_index)])}

static func quantize_credits(value: float,step: int) -> int:
	# Verified source behavior: discard the remainder, except an exact half-step
	# rounds upward. Ordinary nearest-integer rounding changes original offers.
	var credits:=int(value)
	var remainder:=credits%step
	return credits-remainder+(step if remainder*2==step else 0)

func restore(bindings: RefCounted,catalogues: RefCounted,data: Variant) -> bool:
	error=""
	if not data is Dictionary:return reject("Invalid retained contract offer")
	var next: RefCounted=get_script().new()
	if not next.configure(bindings,catalogues,data.get("context"),data.get("choices")):return reject(next.error)
	if data!=next.snapshot():return reject("Retained offer disagrees with its source terms or content identity")
	_state=next._state
	return true

func snapshot() -> Dictionary:return _state.duplicate(true)
func reject(message: String) -> bool:error=message;return false
