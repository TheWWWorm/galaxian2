extends RefCounted
## Shared catalogue-based destination and distance rules. Availability is retained
## career data; these helpers cannot reveal a system or move the player's ship.
const Definitions=preload("res://src/content/base_contract_navigation_definitions.gd")
const Ordinary=preload("res://src/content/ordinary_generation_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")

static func initial_availability(bindings: RefCounted,cat: RefCounted,valkyrie_owned: bool) -> Array:
	if not Definitions.available(bindings) or cat==null or cat.content_id!=bindings.base_content_id:return []
	var rules: Dictionary=bindings.early_contracts.base_navigation
	if cat.tables.systems.size()!=int(rules.system_count):return []
	var result:=[]
	for system in cat.tables.systems:result.append(int(system.fields[int(rules.availability_field)])==1)
	if valkyrie_owned:result[int(rules.valkyrie_system_id)]=true
	return result

static func valid_availability(rules: Dictionary,flags: Variant) -> bool:
	return flags is Array and flags.size()==int(rules.system_count) and flags.all(func(value):return value is bool)

static func arrival_context(bindings: RefCounted,cat: RefCounted,context: Dictionary) -> bool:
	if not Definitions.available(bindings):return false
	var rules: Dictionary=bindings.early_contracts.base_navigation
	return context.get("campaign_cursor")==int(rules.arrival_cursor) and context.get("station_id")==int(rules.arrival_station_id) and cat.tables.stations[int(rules.arrival_station_id)].system_id==int(rules.arrival_system_id) and valid_availability(rules,context.get("system_availability"))

static func ordinary_context(bindings: RefCounted,cat: RefCounted,context: Dictionary) -> bool:
	return Definitions.available(bindings) and Ordinary.location_supported(bindings,cat,context.get("campaign_cursor"),context.get("station_id")) and valid_availability(bindings.early_contracts.base_navigation,context.get("system_availability"))

static func eligible(rules: Dictionary,cat: RefCounted,current_system: int,flags: Array,station: int) -> bool:
	if not Numbers.integer(station,0,cat.tables.stations.size()-1) or not valid_availability(rules,flags):return false
	if rules.excluded_station_ids.any(func(value):return int(value)==station):return false
	if station>=int(rules.excluded_station_range[0]) and station<=int(rules.excluded_station_range[1]):return false
	var system_id:=int(cat.tables.stations[station].system_id)
	return flags[system_id] and (system_id==current_system or not cat.tables.systems[system_id].arrays[int(rules.links_array)].is_empty())

static func distance(rules: Dictionary,cat: RefCounted,from_system: int,to_system: int) -> float:
	if from_system==to_system:return 0.0
	var delta:=[]
	for axis in 3:
		var index:=int(rules.position_fields[axis])
		var a:=int(cat.tables.systems[from_system].fields[index])
		var b:=int(cat.tables.systems[to_system].fields[index])
		if axis==2:
			@warning_ignore("integer_division")
			a=a/int(rules.depth_divisor)
			@warning_ignore("integer_division")
			b=b/int(rules.depth_divisor)
		var difference:=Vitals.single(Vitals.single(float(a))-Vitals.single(float(b)))
		delta.append(Vitals.single(difference*difference))
	var length:=Vitals.single(sqrt(Vitals.single(float(delta[2])+Vitals.single(float(delta[0])+float(delta[1])))))
	return Vitals.single(length*float(rules.distance_multiplier))
