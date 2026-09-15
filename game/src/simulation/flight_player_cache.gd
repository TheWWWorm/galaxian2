extends RefCounted
## Native cache/restoration arithmetic for verified flight entries. Location
## transitions and persistent saves have separate authorization and lifecycles.
const Definitions=preload("res://src/content/flight_player_cache_definitions.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
const Library=preload("res://src/content/library.gd")
const Departure=preload("res://src/content/station_departure_definitions.gd")
const FullHoldDeparture=preload("res://src/content/full_hold_departure_definitions.gd")
const FlightRules=preload("res://src/content/ordinary_flight_definitions.gd")
const TrainingWeapons=preload("res://src/content/combat_training_weapon_definitions.gd")
const Alioth=preload("res://src/content/alioth_lifecycle_definitions.gd")
const FreeFlight=preload("res://src/content/free_flight_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const GateArrival=preload("res://src/content/gate_arrival_definitions.gd")
const IDENTITY_KEYS=["base_content_id","binding_id","ship_id","station_id","system_id","equipment_ids"]
const POOL_KEYS=["hull","armor","shield","gamma"]

static func base_cache(parameters: Dictionary, seed: Dictionary, hull: int, capacities: Dictionary, cursor: int) -> Dictionary:
	if not Definitions.parameters(parameters) or cursor not in [0,int(parameters.arrival_cursor)]:return {}
	if not valid_seed(seed) or not valid_capacities(hull,capacities):return {}
	if seed.station_id>=int(parameters.hazard_station_min) and seed.station_id<=int(parameters.hazard_station_max):return {}
	var result:={"campaign_cursor":cursor,"values":{"hull":hull,"armor":capacities.armor,"shield":capacities.shield,"gamma":int(parameters.gamma_full)}}
	for key in IDENTITY_KEYS:result[key]=seed[key]
	return result.duplicate(true)

static func departure_cache(parameters: Dictionary, departure: Dictionary, seed: Dictionary, hull: int, capacities: Dictionary, reset: bool=false) -> Dictionary:
	if not Departure.parameters(departure) and not FullHoldDeparture.parameters(departure):return {}
	return _departure_cache(parameters,departure,seed,hull,capacities,reset)

static func combat_training_cache(parameters: Dictionary, training: Dictionary, seed: Dictionary, hull: int, capacities: Dictionary, reset: bool=false) -> Dictionary:
	if not TrainingWeapons.parameters(training):return {}
	return _departure_cache(parameters,training.player_entry,seed,hull,capacities,reset)

static func local_travel_cache(parameters: Dictionary, travel: Dictionary, seed: Dictionary, hull: int, capacities: Dictionary, reset: bool=false, cursor: int=10) -> Dictionary:
	var entry:=Travel.player_entry(travel,int(seed.get("station_id",-1)),cursor)
	if entry.is_empty():return {}
	return _departure_cache(parameters,entry,seed,hull,capacities,reset)

static func alioth_entry(travel: Dictionary) -> Dictionary:
	if not Travel.parameters(travel) or not Alioth.parameters(travel.get("alioth_lifecycle")):return {}
	var data: Dictionary=travel.player_entry.duplicate(true)
	for key in ["campaign_cursor","station_id","system_id"]:data[key]=int(travel.alioth_attack[key])
	return data

static func alioth_attack_cache(parameters: Dictionary,travel: Dictionary,seed: Dictionary,hull: int,capacities: Dictionary,reset: bool=false) -> Dictionary:
	var entry:=alioth_entry(travel)
	if entry.is_empty():return {}
	return _departure_cache(parameters,entry,seed,hull,capacities,reset)

static func free_flight_cache(parameters: Dictionary,travel: Dictionary,seed: Dictionary,hull: int,capacities: Dictionary,reset: bool=false) -> Dictionary:
	var entry:=FreeFlight.player_entry(travel,int(seed.get("station_id",-1)),int(seed.get("ship_id",-1)))
	if entry.is_empty():return {}
	return _departure_cache(parameters,entry,seed,hull,capacities,reset)

static func capture_local_arrival(travel: Dictionary, source: Dictionary, destination: Dictionary, player: Dictionary) -> Dictionary:
	if not Travel.parameters(travel) or not valid_seed(source) or not valid_seed(destination):return {}
	if not player.get("campaign_cursor") is int:return {}
	var trip:=Travel.route(travel,player.campaign_cursor,source.station_id,destination.station_id)
	if trip.is_empty() or source.station_id!=int(trip.from_station_id) or destination.station_id!=int(trip.station_id) or destination.system_id!=int(trip.system_id):return {}
	for key in IDENTITY_KEYS:
		if key!="station_id" and source[key]!=destination[key]:return {}
	return _capture_arrival(travel,source,destination,player)

static func capture_gate_arrival(travel: Dictionary,source: Dictionary,destination: Dictionary,player: Dictionary) -> Dictionary:
	if not Travel.parameters(travel) or not valid_seed(source) or not valid_seed(destination) or player.get("campaign_cursor")!=18:return {}
	var trip:=GateArrival.route(travel,source.station_id,destination.station_id)
	if trip.is_empty() or source.system_id!=trip.from_system_id or destination.system_id!=trip.system_id:return {}
	for key in IDENTITY_KEYS:
		if key not in ["station_id","system_id"] and source[key]!=destination[key]:return {}
	return _capture_arrival(travel,source,destination,player)

static func _capture_arrival(travel: Dictionary,source: Dictionary,destination: Dictionary,player: Dictionary) -> Dictionary:
	for key in ["base_content_id","binding_id","ship_id","equipment_ids"]:
		if player.get(key)!=source[key]:return {}
	var pools: Variant=player.get("vitals")
	if not pools is Dictionary or not Vitals.integer(pools.get("hull")) or pools.hull<=0 or not Vitals.integer(pools.get("armor")):return {}
	var values:={"hull":pools.hull,"armor":pools.armor}
	for key in travel.player_entry.cache_truncates:
		var value: Variant=pools.get(key) if key=="shield" else player.get(key)
		if not (value is int or value is float) or not is_finite(value) or value<0 or value>2147483647.0:return {}
		values[key]=int(value)
	if not valid_values(values):return {}
	var result:={"campaign_cursor":player.campaign_cursor,"values":values}
	for key in IDENTITY_KEYS:result[key]=destination[key]
	return result.duplicate(true)

static func _departure_cache(parameters: Dictionary, departure: Dictionary, seed: Dictionary, hull: int, capacities: Dictionary, reset: bool) -> Dictionary:
	for key in ["ship_id","station_id","system_id"]:
		if seed.get(key)!=int(departure[key]):return {}
	# Share the normal pool/identity checks without extending base_cache to
	# arbitrary campaign cursors or allowing rescue caches on the new ship.
	var result:=base_cache(parameters,seed,hull,capacities,0)
	if result.is_empty():return {}
	result.campaign_cursor=int(departure.campaign_cursor)
	if reset:
		for key in POOL_KEYS:result.values[key]=int(departure.cache_reset)
	return result

static func matches(cache: Variant, seed: Dictionary, cursor: int) -> bool:
	if not cache is Dictionary or cache.size()!=IDENTITY_KEYS.size()+2 or not valid_seed(seed):return false
	if not cache.get("campaign_cursor") is int or cache.campaign_cursor!=cursor or not valid_values(cache.get("values")):return false
	for key in IDENTITY_KEYS:
		if typeof(cache.get(key))!=typeof(seed[key]) or cache[key]!=seed[key]:return false
	return true

static func station_arrival_cache(rules: Dictionary, seed: Dictionary, player: Dictionary) -> Dictionary:
	if not FlightRules.docking_parameters(rules) or not valid_seed(seed):return {}
	if seed.station_id!=int(rules.station_id) or seed.system_id!=int(rules.system_id):return {}
	for key in ["base_content_id","binding_id","ship_id","equipment_ids"]:
		if player.get(key)!=seed[key]:return {}
	var pools: Variant=player.get("vitals")
	if not pools is Dictionary or not Vitals.integer(pools.get("hull")) or not Vitals.integer(pools.get("armor")):return {}
	var values:={"hull":pools.hull,"armor":pools.armor}
	for key in rules.cache_truncates:
		var value: Variant=pools.get(key) if key=="shield" else player.get(key)
		if not (value is int or value is float) or not is_finite(value) or value < -2147483648.0 or value>2147483647.0:return {}
		values[key]=int(value)
	if not valid_values(values):return {}
	var result:={"campaign_cursor":int(rules.campaign_cursor),"values":values}
	for key in IDENTITY_KEYS:result[key]=seed[key]
	return result.duplicate(true)

static func restore_values(parameters: Dictionary, hull: int, capacities: Dictionary, cached: Variant) -> Dictionary:
	if not Definitions.parameters(parameters) or not valid_capacities(hull,capacities) or not valid_values(cached):return {}
	# A negative cache entry leaves its newly constructed pool alone. Zero is an
	# actual restored value. Shield conversion occurs before its binary32 clamp.
	var result:={"hull":hull,"armor":capacities.armor,"shield":Vitals.single(capacities.shield),"gamma":Vitals.single(parameters.gamma_full),"max_hull":hull}
	if cached.hull>=int(parameters.cache_minimum):
		result.hull=cached.hull;result.max_hull=maxi(hull,cached.hull)
	if cached.armor>=int(parameters.cache_minimum):result.armor=mini(cached.armor,capacities.armor)
	if cached.shield>=int(parameters.cache_minimum):result.shield=minf(Vitals.single(cached.shield),Vitals.single(capacities.shield))
	if cached.gamma>=int(parameters.cache_minimum):
		result.gamma=Vitals.single(cached.gamma)
		if cached.gamma!=int(parameters.gamma_sentinel):result.gamma=minf(result.gamma,Vitals.single(parameters.gamma_full))
	return result

static func valid_values(values: Variant) -> bool:
	if not values is Dictionary or values.size()!=POOL_KEYS.size():return false
	for key in POOL_KEYS:
		var value: Variant=values.get(key)
		if not value is int or value < -2147483648 or value>Vitals.MAX_INTEGER:return false
	return true

static func valid_seed(seed: Dictionary) -> bool:
	for key in ["base_content_id","binding_id"]:
		if not seed.get(key) is String or not Library.valid_hash(seed[key]):return false
	for key in ["ship_id","station_id","system_id"]:
		if not Vitals.integer(seed.get(key)):return false
	if not seed.get("equipment_ids") is Array or seed.equipment_ids.size()>4096:return false
	for item in seed.equipment_ids:
		if not Vitals.integer(item):return false
	return true

static func valid_capacities(hull: int, capacities: Dictionary) -> bool:
	return Vitals.integer(hull) and Vitals.integer(capacities.get("armor")) and Vitals.integer(capacities.get("shield")) and capacities.shield<=Vitals.MAX_SHIELD
