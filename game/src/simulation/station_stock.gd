extends RefCounted
## Native inventory sampling. The scene supplies time and retained settings;
## stock generation never chooses expansion ownership or enables shopping itself.
const Definitions=preload("res://src/content/station_generation_definitions.gd")
const BaseStock=preload("res://src/content/base_station_stock_definitions.gd")
const DeepScience=preload("res://src/content/deep_science_stock_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Contacts=preload("res://src/simulation/lounge_contacts.gd")
const Ores=preload("res://src/simulation/scenery_ores.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
var error:=""
var _state:={}
var _rules:={}
var _context:={}
var _rng: RefCounted
var _draws:=0
var _tech:=0
var _faction:=0
var _system:=15
var _base:={}
var _deep_science:={}
const MAX_SELECTION_DRAWS:=65536

static func available(bindings: RefCounted) -> bool:return Definitions.available(bindings)

func prepare(bindings: RefCounted,cat: RefCounted,context: Variant,random_state: Variant,unix_seconds: Variant) -> bool:
	error=""
	if not available(bindings) or cat==null or cat.content_id!=bindings.base_content_id:return reject("Station stock requires matching supported content")
	var rules: Dictionary=bindings.early_contracts.station_generation
	if not context is Dictionary or not Numbers.integer(context.get("station_id"),0,cat.tables.stations.size()-1):return reject("Station stock requires its supported campaign location")
	var station: Dictionary=cat.tables.stations[context.station_id]
	var base:={}
	var deep_science:={}
	var early: bool=context.size()==7 and station.system_id==int(rules.system_id) and Numbers.integer(context.get("campaign_cursor"),int(rules.first_cursor),int(rules.last_cursor))
	if not early:
		if not BaseStock.available(bindings):return reject("This content does not support ordinary base station stock")
		base=bindings.early_contracts.base_station_stock
		if base.excluded_station_ids.any(func(id):return int(id)==int(context.station_id)):
			if not DeepScience.available(bindings):return reject("This special location's stock is not supported yet")
			deep_science=bindings.get("deep_science_stock")
			if int(context.station_id)!=int(deep_science.station_id) or not context.get("all_base_medals_gold") is bool or not Numbers.integer(context.get("campaign_cursor"),int(deep_science.first_cursor),int(deep_science.last_cursor)):return reject("Deep Science stock requires its supported cursor and retained base-medal result")
		if context.size()!=8+int(not deep_science.is_empty()) or not Numbers.integer(context.get("campaign_cursor"),int(base.first_cursor),int(base.last_cursor)) or not Numbers.integer(context.get("ship_price_percent"),-100,1000):return reject("Base station stock requires its supported cursor and retained ship price modifier")
		if int(context.station_id)>int(base.last_station_id) or int(station.system_id)>int(base.last_system_id):return reject("This special location's stock is not supported yet")
	if not context.get("valkyrie_owned") is bool or not context.get("supernova_owned") is bool or context.get("difficulty") not in [0.5,1.0,1.5]:return reject("Retain explicit expansion ownership and game difficulty")
	for key in ["energy_availability_percent","missile_availability_percent"]:
		if not Numbers.integer(context.get(key),-100,1000):return reject("Unsupported retained stock modifier")
	var candidate: RefCounted=get_script().new()
	candidate._rng=Random.new()
	if not candidate._rng.restore(random_state):return reject(candidate._rng.error)
	candidate._rules=rules.duplicate(true);candidate._context=context.duplicate(true)
	candidate._base=base.duplicate(true);candidate._deep_science=deep_science.duplicate(true);candidate._system=int(station.system_id)
	candidate._tech=int(station.fields[int(rules.catalogue.station_tech_field)])
	var system: Dictionary=cat.tables.systems[station.system_id]
	candidate._faction=int(system.fields[int(rules.catalogue.system_faction_field)])
	var tutorial: bool=context.station_id==int(rules.tutorial.station_id) and context.campaign_cursor<=int(rules.tutorial.last_cursor)
	var stock:=[]
	if tutorial:
		for row in rules.tutorial.stock:stock.append({"item_id":int(row.item_id),"quantity":int(row.quantity),"unit_price":int(row.unit_price)})
		# This branch does not reseed. Its unchanged stream goes to contacts.
	else:
		if not unix_seconds is int or unix_seconds<0:return reject("New ordinary stock requires its sampled Unix time")
		stock=candidate._temporary_stock(cat)
		candidate._rng.seed_from(unix_seconds)
		var here: Variant=Ores.map_position(system,rules.catalogue)
		if here==null:return reject("The stock origin lacks its map coordinates")
		for item in cat.tables.items:
			var metadata:=item_metadata(item,rules)
			if metadata.is_empty():return reject("The item catalogue lacks its stock properties")
			if not Numbers.integer(metadata.origin,0,cat.tables.systems.size()-1):return reject("The item's stock origin is absent")
			var there: Variant=Ores.map_position(cat.tables.systems[metadata.origin],rules.catalogue)
			if there==null:return reject("The item origin lacks its map coordinates")
			var dx: int=there[0]-here[0];var dy: int=there[1]-here[1]
			if absi(dx)>46340 or absi(dy)>46340 or dx*dx+dy*dy>2147483647:return reject("Stock distance exceeds supported source arithmetic")
			metadata.affinity=int(rules.quantity.affinity_base)-int(Vitals.single(sqrt(Vitals.single(float(dx*dx+dy*dy)))))
			var row: Dictionary=candidate._sample_item(metadata)
			if not row.is_empty():stock.append(row)
	var ships: Array=candidate._sample_ships(cat)
	if not candidate.error.is_empty():return reject(candidate.error)
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"context":context.duplicate(true),"initial_random":random_state.duplicate(true),
		"unix_seconds":null if tutorial else unix_seconds,"random":candidate._rng.snapshot(),
		"items":stock,"ships":ships,"draw_calls":candidate._draws}
	return true

func _temporary_stock(cat: RefCounted) -> Array:
	if _base.is_empty():return []
	var rule: Dictionary=_base.temporary_item
	if _context.campaign_cursor<int(rule.first_cursor) or _context.campaign_cursor>int(rule.last_cursor):return []
	if _draw(int(rule.draw_bound))>int(rule.maximum_roll):return []
	var item:=item_metadata(cat.tables.items[int(rule.item_id)],_rules)
	return [{"item_id":int(rule.item_id),"quantity":int(rule.quantity),"unit_price":item.unit_price}]

func _sample_ships(cat: RefCounted) -> Array:
	if _base.is_empty() or (_system==int(_rules.system_id) and _context.campaign_cursor<int(_rules.ships_before_cursor)):return []
	var rules: Dictionary=_base.ships
	if cat.tables.ships.size()!=rules.affiliations.size():reject("The ship catalogue does not match the imported affiliations");return []
	var all_gold: bool=not _deep_science.is_empty() and _context.all_base_medals_gold
	var count:=int(_deep_science.all_base_gold_count) if all_gold else _draw(int(rules.count_draw_bound))+int(_context.station_id==int(rules.additional_count_station))
	# A zero initial count returns before even the independent extra-ship rolls.
	if count==0:return []
	var chosen:=[];var result:=[]
	for slot in count:
		var fixed:=int(rules.fixed_first_ships.get(str(_context.station_id),-1)) if slot==0 else -1
		if all_gold:fixed=int(_deep_science.all_base_gold_ship_id)
		var id:=-1
		while id<0 or id in chosen:
			if _draws>=MAX_SELECTION_DRAWS:reject("Ship selection exceeded the native work limit");return []
			id=fixed if fixed>=0 else _select_ship(_faction)
			if not error.is_empty():return []
			if count>=int(rules.foreign_minimum_count) and _draw(int(rules.foreign_draw_bound))<=int(rules.foreign_maximum_roll):
				var faction:=_draw(int(rules.foreign_faction_bound))
				if fixed<0:
					if faction==_faction or faction==int(rules.foreign_excluded_faction):faction=int(rules.foreign_fallback_faction)
					id=_select_ship(faction)
					if not error.is_empty():return []
		chosen.append(id)
		result.append(_ship_offer(cat,id,int(rules.affiliations[id])))
	# Source-specific offers precede expansion and system offers.
	for extra in rules.get("faction_extras",[]):
		if _faction==int(extra.faction) and _draw(int(extra.draw_bound))==0:result.append(_ship_offer(cat,int(extra.ship_id),int(extra.faction_id)))
	if _context.supernova_owned:
		for extra in rules.owned_supernova_extras:
			if _faction==int(extra.faction) and _draw(int(extra.draw_bound))==0:result.append(_ship_offer(cat,int(extra.ship_id),int(extra.faction_id)))
	var special: Dictionary=rules.system_extras
	if _system==int(special.system_id):
		for extra in special.ships:
			if _draw(int(special.draw_bound))==0:result.append(_ship_offer(cat,int(extra.ship_id),int(extra.faction_id)))
	return result

func _select_ship(faction: int) -> int:
	var rules: Dictionary=_base.ships
	if faction==int(rules.vossk_faction):return int(rules.vossk_ship_id)
	while _draws<MAX_SELECTION_DRAWS:
		var id:=_draw(int(rules.selection_draw_bound))
		if rules.selection_excluded_ids.any(func(value):return int(value)==id):continue
		if int(rules.affiliations[id])==faction:return id
	reject("Ship selection exceeded the native work limit")
	return -1

func _ship_offer(cat: RefCounted,id: int,faction: int) -> Dictionary:
	var price:=int(cat.tables.ships[id].stats.base_price)
	if price>0:
		var rules: Dictionary=_base.ships
		var base_price:=Vitals.single(float(price))
		var discount:=Vitals.single(base_price*float(rules.local_price_multiplier)) if int(rules.affiliations[id])==_faction else 0.0
		var adjusted:=Vitals.single(base_price+discount)
		var modifier:=Vitals.single(Vitals.single(base_price*Vitals.single(float(_context.ship_price_percent)))*float(rules.percent_multiplier))
		price=int(Vitals.single(adjusted+modifier))
		if price<0:reject("The retained ship modifier produces an unsupported negative price")
	return {"ship_id":id,"faction_id":faction,"unit_price":price}

static func item_metadata(item: Dictionary,rules: Dictionary) -> Dictionary:
	if not item.get("properties") is Dictionary or not item.get("arrays") is Array:return {}
	var result:={"item_id":int(item.id),"blueprint":not item.arrays[int(rules.catalogue.blueprint_array)].is_empty()}
	for key in rules.catalogue.item_properties:
		var property:=int(rules.catalogue.item_properties[key])
		if key not in ["designated_station","vossk_only"] and not item.properties.has(property):return {}
		result[key]=int(item.properties.get(property,-1))
	result.unit_price=Contacts.prototype_price(result.min_price,result.max_price)
	return result

func _sample_item(item: Dictionary) -> Dictionary:
	var rules: Dictionary=_rules.availability
	var chance:=int(item.availability)
	if item.item_id==int(rules.energy_item):chance=_modified(chance,int(_context.energy_availability_percent))
	if item.category==int(rules.missile_category):chance=_modified(chance,int(_context.missile_availability_percent))
	# Expansion fallback occurs before the ordinary tech and blueprint filters.
	# Even an item rejected later can advance the shared random stream here.
	if chance==0 and _expansion_eligible(item):
		var fallback: Dictionary=_rules.expansion
		var roll:=_draw(int(fallback.draw_bound))
		var factor:=Vitals.single(Vitals.single(float(item.tech)/float(fallback.tech_divisor))+float(fallback.add))
		chance=int(Vitals.single(Vitals.single(factor*float(fallback.multiplier))+float(roll)))
	var forced: bool=item.designated_station==_context.station_id and (not rules.designated_gated_ids.any(func(value):return int(value)==item.item_id) or _context.campaign_cursor>=int(rules.designated_unlock_cursor))
	if not forced:
		if item.blueprint or rules.excluded_ids.any(func(value):return int(value)==item.item_id) or item.tech>_tech or chance==0 or item.unit_price==0:return {}
		if item.vossk_only==1 and _faction!=int(rules.vossk_faction):return {}
		if item.item_id>=int(rules.system_goods_first) and item.item_id<=int(rules.system_goods_last) and item.item_id!=int(rules.system_goods_first)+_system:return {}
	if _context.difficulty==float(rules.hard_difficulty) and rules.hard_excluded_subtypes.any(func(value):return int(value)==item.subtype):return {}
	if not forced:
		var factor:=minf(float(rules.progress_cap),Vitals.single(float(_context.campaign_cursor+int(rules.progress_add))/float(rules.progress_divisor)))
		if _draw(int(rules.draw_bound))>=int(Vitals.single(float(chance)*factor)):return {}
		var low_tech:=int(rules.low_tech_minimum) if _tech<int(rules.low_tech_boundary) else int(_tech/int(rules.low_tech_divisor))
		if item.item_id!=int(rules.energy_item) and item.tech<low_tech and _draw(int(rules.draw_bound))>int(rules.low_tech_max_roll):return {}
	return {"item_id":item.item_id,"quantity":_quantity(item),"unit_price":item.unit_price}

func _modified(chance: int,percent: int) -> int:
	return int(Vitals.single(float(chance)+Vitals.single(float(chance*percent)*float(_rules.availability.modifier_multiplier))))

func _expansion_eligible(item: Dictionary) -> bool:
	var rules: Dictionary=_rules.expansion
	var owned: bool=_context.supernova_owned if item.item_id>=int(rules.first_supernova_item) else _context.valkyrie_owned
	var excluded: bool=rules.excluded_ids.any(func(value):return int(value)==item.item_id)
	if not _base.is_empty() and item.item_id==int(_base.late_fallback_item.item_id):excluded=_context.campaign_cursor<int(_base.late_fallback_item.first_cursor)
	return owned and not item.blueprint and item.category!=int(rules.excluded_category) and not excluded and not rules.excluded_subtypes.any(func(value):return int(value)==item.subtype)

func _quantity(item: Dictionary) -> int:
	var rules: Dictionary=_rules.quantity
	var quantity:=_draw(int(rules.draw_bound))+int(rules.add)
	if item.category not in [int(rules.goods_category),int(rules.missile_category)]:return maxi(1,int(quantity/int(rules.single_divisor)))
	if item.item_id==int(rules.half_item):return maxi(1,int(quantity/int(rules.half_divisor)))
	if item.category==int(rules.missile_category):return quantity
	if item.affinity>int(rules.affinity_threshold):
		var multiplier:=float(rules.hard_multiplier) if _context.difficulty==float(_rules.availability.hard_difficulty) else float(rules.normal_multiplier)
		var factor:=Vitals.single(float(item.affinity-int(rules.affinity_threshold))/float(rules.affinity_divisor))
		quantity*=maxi(1,int(Vitals.single(factor*multiplier)))
	if item.item_id==int(rules.limited_item):
		var limit:=_draw(int(rules.limit_draw_bound))+int(rules.limit_add)
		if quantity>limit:quantity=_draw(int(rules.limit_draw_bound))+int(rules.limit_add)
	return quantity

func _draw(bound: int) -> int:
	_draws+=1
	return _rng.next_int(bound)

func restore(bindings: RefCounted,cat: RefCounted,data: Variant) -> bool:
	error=""
	if not data is Dictionary:return reject("Invalid retained station stock")
	var next: RefCounted=get_script().new()
	if not next.prepare(bindings,cat,data.get("context"),data.get("initial_random"),data.get("unix_seconds")):return reject(next.error)
	if next.snapshot()!=data:return reject("Retained stock disagrees with its original inputs")
	_state=next._state
	return true

func snapshot() -> Dictionary:return _state.duplicate(true)
func reject(message: String) -> bool:error=message;return false
