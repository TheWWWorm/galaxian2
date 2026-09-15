extends RefCounted
const Alioth=preload("res://src/content/alioth_population_definitions.gd")
const FreeFlight=preload("res://src/content/free_flight_definitions.gd")
## Content-bound Opening, rescue and supported departure player pools.
## The world owner supplies ordering; full player lifecycle remains separate.
const Definitions = preload("res://src/content/player_initialization_definitions.gd")
const Actors = preload("res://src/content/opening_actor_definitions.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const Loadout = preload("res://src/simulation/opening_loadout.gd")
const Vitals = preload("res://src/simulation/combat_vitals.gd")
const Damage = preload("res://src/simulation/ordinary_player_damage.gd")
const HitDefinitions = preload("res://src/content/player_hit_definitions.gd")
const NPCWeapons = preload("res://src/content/opening_npc_weapon_definitions.gd")
const OrdinaryHits = preload("res://src/content/ordinary_hit_definitions.gd")
const Recharge = preload("res://src/simulation/shield_recharge.gd")
const Repair = preload("res://src/simulation/equipment_repair.gd")
const RepairDefinitions = preload("res://src/content/player_repair_definitions.gd")
const FlightCache = preload("res://src/simulation/flight_player_cache.gd")
const CacheDefinitions = preload("res://src/content/flight_player_cache_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Entry = preload("res://src/content/player_entry_definitions.gd")
const Stats=preload("res://src/simulation/equipment_stats.gd")
const Fitting=preload("res://src/content/ordinary_fitting_definitions.gd")
const StationEquipment = preload("res://src/simulation/station_equipment.gd")
const Construction=preload("res://src/simulation/opening_npc_construction.gd")
const Convoy=preload("res://src/content/convoy_world_definitions.gd")
const ContractLife=preload("res://src/content/contract_ship_lifecycle_definitions.gd")
const Junk=preload("res://src/content/contract_junk_definitions.gd")
var error := ""
var _state := {}
var _hit_policy := {}
var _npc_weapons := []
var _loadout := {}
var _recharge: RefCounted
var _repair: RefCounted
var _flight_cache := {}

func configure(bindings: RefCounted, catalogues: RefCounted) -> bool:
	return _configure(bindings,catalogues,0,{})

func configure_arrival(bindings: RefCounted, catalogues: RefCounted, previous_cache: Variant) -> bool:
	return _configure(bindings,catalogues,1,previous_cache)

func configure_departure(bindings: RefCounted, catalogues: RefCounted, cursor: int=2) -> bool:
	if cursor not in [2,4]:clear();return reject("Unsupported mining departure cursor")
	return _configure(bindings,catalogues,cursor,{})

func configure_combat_training(bindings: RefCounted, catalogues: RefCounted, equipment: RefCounted) -> bool:
	return _configure(bindings,catalogues,7,{},equipment)

func configure_local_travel(bindings: RefCounted, catalogues: RefCounted, equipment: RefCounted, previous_cache: Variant=null, cursor: int=10) -> bool:
	if cursor not in [10,11,12] and not Travel.navigation_available(bindings.mido_travel,cursor):clear();return reject("Unsupported local player cursor")
	return _configure(bindings,catalogues,cursor,previous_cache,equipment)

func configure_contract(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,construction: RefCounted,previous_cache: Variant=null) -> bool:
	clear()
	if not construction is Construction:return reject("Contract player requires its accepted generated encounter")
	var data:=ContractLife.population(bindings,construction.snapshot())
	if data.is_empty():data=Junk.population(bindings,construction.snapshot())
	if data.is_empty() or not equipment is StationEquipment or equipment.snapshot().loadout.station_id!=int(data.station_id):return reject("Contract player belongs to another equipped station")
	if not _configure(bindings,catalogues,int(data.campaign_cursor),previous_cache,equipment,data):return false
	_state.contract_encounter=construction.snapshot().contract_encounter.duplicate(true)
	return true

func configure_convoy(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,construction: RefCounted,previous_cache: Variant=null) -> bool:
	clear()
	if not construction is Construction:return reject("Convoy player requires its generated encounter")
	var data:=Convoy.lifecycle(bindings,construction.snapshot())
	if data.is_empty() or not equipment is StationEquipment or equipment.snapshot().loadout.station_id!=int(data.station_id):return reject("Convoy player belongs to another equipped station")
	if not _configure(bindings,catalogues,int(data.campaign_cursor),previous_cache,equipment,data):return false
	_state.convoy_context=construction.snapshot().convoy_context.duplicate(true)
	return true

func configure_alioth_attack(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,construction: RefCounted,previous_cache: Variant=null) -> bool:
	clear()
	if not construction is Construction:return reject("Alioth player requires its generated encounter")
	var data:=Alioth.lifecycle(bindings,construction.snapshot())
	if data.is_empty() or not equipment is StationEquipment or equipment.snapshot().loadout.station_id!=int(data.station_id):return reject("Alioth player belongs to another equipped station")
	if not _configure(bindings,catalogues,int(data.campaign_cursor),previous_cache,equipment,data):return false
	_state.alioth_context=construction.snapshot().alioth_context.duplicate(true)
	return true

func configure_free(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,construction: RefCounted,previous_cache: Variant=null) -> bool:
	clear()
	if not FreeFlight.available(bindings) or not construction is Construction:return reject("Ordinary player requires its source-bound population")
	var packet: Dictionary=construction.snapshot()
	var data:=FreeFlight.Life.population(bindings,packet)
	if data.is_empty() or not equipment is StationEquipment:return reject("Ordinary player differs from its retained equipment or population")
	var owned: Dictionary=equipment.snapshot();var loadout: Dictionary=owned.get("loadout",{})
	if owned.get("cargo_cache_stale",true) or loadout.get("station_id")!=int(data.station_id) or loadout.get("ship_id")!=packet.player_ship_id:return reject("Ordinary player differs from its retained equipment or population")
	if not _configure(bindings,catalogues,int(data.campaign_cursor),previous_cache,equipment,data):return false
	_state.free_context=packet.free_context.duplicate(true)
	return true


func _configure(bindings: RefCounted, catalogues: RefCounted, cursor: int, previous_cache: Variant, equipment: RefCounted=null,contract: Dictionary={}) -> bool:
	clear()
	if bindings==null or catalogues==null: return reject("Player initialization requires content definitions")
	var entry:=Entry.new()
	var station_id:=int(equipment.snapshot().get("loadout",{}).get("station_id",-1)) if equipment is StationEquipment else -1
	var ship_id:=int(equipment.snapshot().get("loadout",{}).get("ship_id",-1)) if equipment is StationEquipment else -1
	if not entry.configure(bindings,cursor,station_id,previous_cache!=null and not (previous_cache is Dictionary and previous_cache.is_empty()),ship_id):return reject(entry.error)
	var arrival:=entry.is_arrival
	var departure:=entry.is_departure
	if entry.uses_equipment and not equipment is StationEquipment:return reject("Combat-training player requires the actual equipped tutorial ship")
	var parameters: Dictionary=bindings.opening_actors.get("player_initialization",{})
	if not Definitions.parameters(parameters) or not Actors.parameters(bindings.opening_actors):
		return reject("This profile has no supported fresh player initialization")
	var seed: Dictionary
	if entry.uses_equipment:
		if cursor in [10,11,12,13,14,16,18] and (not equipment.snapshot().get("training_inventory_released",false) or not equipment.snapshot().get("prototype_drill_replaced",false)):return reject("Complete the station drill exchange before local flight")
		if not (cursor==18 and Fitting.available(bindings)) and not equipment.requirements().satisfied:return reject("Install the required weapon and armor before combat training")
		seed=equipment.snapshot().loadout
		if seed.get("base_content_id")!=bindings.base_content_id or seed.get("binding_id")!=bindings.binding_id or catalogues.content_id!=bindings.base_content_id:return reject("Equipped player belongs to another source identity")
		for key in ["ship_id","station_id","system_id"]:
			if seed.get(key)!=int(entry.equipped_entry[key]):return reject("Equipped player has an unsupported ship or location")
		seed.campaign_cursor=cursor
	else:
		var loadout := Loadout.new()
		if not (loadout.configure_station(bindings,catalogues,bindings.base_content_id) if departure else loadout.configure(bindings,catalogues,bindings.base_content_id)): return reject(loadout.error)
		seed=loadout.snapshot()
	var capacities := resolve_capacities(catalogues.tables.items,seed.equipment_ids,parameters)
	if capacities.is_empty(): return reject("Equipped player items lack valid shield or armor capacity bindings")
	var cache_parameters: Variant=parameters.get("flight_cache",{})
	if not cache_parameters is Dictionary or (not cache_parameters.is_empty() and not CacheDefinitions.parameters(cache_parameters)):
		return reject("Invalid flight player cache capability")
	if arrival and (cache_parameters.is_empty() or bindings.arrival_staging.is_empty()):
		return reject("This profile has no supported rescue player restoration")
	if departure and cache_parameters.is_empty():return reject("First departure requires ordinary player restoration")
	var recharge: RefCounted
	var recharge_parameters: Variant=parameters.get("recharge",{})
	if not recharge_parameters is Dictionary: return reject("Invalid shield recharge capability")
	if not recharge_parameters.is_empty():
		var duration: Variant=0
		if capacities.shield_item_id>=0:
			duration=catalogues.tables.items[capacities.shield_item_id].properties.get(int(recharge_parameters.get("equipment_property",-1)))
		if not Vitals.integer(duration): return reject("Equipped shield lacks a valid recharge duration")
		recharge=Recharge.new()
		if not recharge.configure(recharge_parameters,capacities.shield,duration): return reject(recharge.error)
	var repair: RefCounted
	var max_hull := -1
	var base_hull := -1
	var device := {}
	var repair_parameters: Variant=parameters.get("repair",{})
	if not repair_parameters is Dictionary: return reject("Invalid equipment repair capability")
	if not repair_parameters.is_empty():
		if recharge==null: return reject("Equipment repair requires supported ordinary player update ordering")
		if not RepairDefinitions.parameters(repair_parameters): return reject("Invalid repair declarations")
		var fields: Variant=catalogues.tables.ships[seed.ship_id].get("fields")
		if not (fields is Array or fields is PackedInt32Array) or fields.size()<=int(repair_parameters.base_hull_field): return reject("Ship lacks its source base hull field")
		base_hull=resolve_ship_hull(fields[int(repair_parameters.base_hull_field)],repair_parameters.initial_upgrades,repair_parameters)
		device=resolve_repair_device(catalogues.tables.items,seed.equipment_ids,repair_parameters)
		if base_hull<0 or device.is_empty(): return reject("Invalid source hull or equipped repair device")
	var current:={"hull":int(bindings.opening_actors.player_current_hull_override),"armor":capacities.armor,"shield":capacities.shield}
	var next_cache:={}
	if not cache_parameters.is_empty():
		next_cache=entry.player_cache(cache_parameters,seed,base_hull,capacities)
		if next_cache.is_empty():return reject("Flight cache lacks verified ship capacities or location")
	if departure:
		var reset:=entry.player_cache(cache_parameters,seed,base_hull,capacities,true)
		if reset.is_empty():return reject("First departure lacks its cleared pool cache")
		current=FlightCache.restore_values(cache_parameters,base_hull,capacities,reset.values)
		if current.is_empty():return reject("Unsupported first-departure player capacities")
	if arrival:
		if not FlightCache.matches(previous_cache,seed,0):return reject("Rescue cache belongs to another content, loadout, location or scene")
		current=FlightCache.restore_values(cache_parameters,base_hull,capacities,previous_cache.values)
		if current.is_empty():return reject("Unsupported cached player values")
		# This verified fresh path is outside the gamma environment. Entry resets
		# the restored gamma level after refreshing the ordinary ship cache.
		current.gamma=Vitals.single(cache_parameters.gamma_full)
	if entry.restores_local:
		if not FlightCache.matches(previous_cache,seed,cursor):return reject("Local arrival cache belongs to another equipped location")
		current=FlightCache.restore_values(cache_parameters,base_hull,capacities,previous_cache.values)
		if current.is_empty():return reject("Unsupported local arrival player values")
		current.gamma=Vitals.single(cache_parameters.gamma_full)
	if base_hull>=0:
		max_hull=maxi(base_hull,current.hull)
		repair=Repair.new()
		if not repair.configure(repair_parameters,max_hull,capacities.armor,device.mode): return reject(repair.error)
	var pools := Vitals.new()
	if not pools.configure(current.hull,current.armor,current.shield):return reject(pools.error)
	var policy: Variant=bindings.weapon_parameters.get("player_hit_policy",{})
	if not policy is Dictionary: return reject("Invalid player hit capability")
	var weapons := []
	if not policy.is_empty():
		var npc: Variant=bindings.opening_actors.get("npc_initialization",{}).get("primary_weapon",{})
		var ordinary: Variant=bindings.weapon_parameters.get("ordinary_hit_policy",{})
		if not HitDefinitions.parameters(policy) or not NPCWeapons.parameters(npc) or not OrdinaryHits.parameters(ordinary) or ordinary.is_empty():
			return reject("Player contact requires verified NPC weapons and hit declarations")
		var contacts:=entry.contact_weapons(npc)
		if not contract.is_empty():contacts={"candidates":contract.npc_weapons,"enabled":true,"context":{"campaign_cursor":cursor,"nonplayer_source":true}}
		if contacts.is_empty():return reject(entry.error)
		var candidates: Array=contacts.candidates
		for candidate in candidates:
			if candidate.get("unarmed",false):continue
			if int(candidate.item_id)>=catalogues.tables.items.size(): return reject("Player contact weapon is absent from this catalogue")
			var properties: Variant=catalogues.tables.items[int(candidate.item_id)].get("properties")
			if not properties is Dictionary: return reject("NPC contact weapon lacks source properties")
			var extra: Variant=properties.get(int(ordinary.additional_damage_property),int(ordinary.missing_additional_damage))
			if not extra is int or extra!=int(ordinary.missing_additional_damage): return reject("NPC contact requires an unsupported additional damage path")
			var weapon:={"base_content_id":seed.base_content_id,"binding_id":seed.binding_id,"launch_mode":"ordinary"}
			for key in ["item_id","category","kind","damage"]: weapon[key]=int(candidate[key])
			weapon.merge(contacts.context)
			weapons.append(weapon)
		if not contacts.enabled:weapons=[]
	_state={"base_content_id":seed.base_content_id,"binding_id":seed.binding_id,"ship_id":seed.ship_id,
		"equipment_ids":seed.equipment_ids.duplicate(),"vitals":pools.snapshot(),"capacities":capacities,
		"half_extent":int(parameters.half_extent),"active":parameters.initial_active,
		"damage_allowed":parameters.initial_damage_allowed,"is_player":parameters.is_player}
	_hit_policy=policy.duplicate(true);_npc_weapons=weapons;_loadout=seed.duplicate(true)
	_recharge=recharge
	_repair=repair
	_flight_cache=next_cache
	if repair!=null: _state.max_hull=max_hull
	if arrival or departure or entry.restores_local:_state.gamma=current.gamma;_state.campaign_cursor=cursor
	if not policy.is_empty():
		_state.contact=false;_state.impact_vector=Vector3.ZERO
	return true

func advance_recharge(delta_ms: Variant) -> Dictionary:
	error=""
	if _recharge==null: reject("This player has no supported shield recharge");return {}
	var result: Dictionary=_recharge.advance(_state.vitals.hull,_state.vitals.shield,delta_ms)
	if result.is_empty(): reject(_recharge.error);return {}
	_state.vitals.shield=result.after
	return result

func advance_repair(delta_ms: Variant) -> Dictionary:
	error=""
	if _repair==null: reject("This player has no supported equipment repair");return {}
	var result: Dictionary=_repair.advance(_state.vitals.hull,_state.vitals.armor,delta_ms)
	if result.is_empty(): reject(_repair.error);return {}
	_state.vitals.hull=result.after.hull;_state.vitals.armor=result.after.armor
	return result

static func resolve_ship_hull(base: Variant, upgrade_tags: Array, parameters: Dictionary) -> int:
	return Stats.resolve_ship_hull(base,upgrade_tags,parameters)

static func resolve_repair_device(items: Array, equipment_ids: Array, parameters: Dictionary) -> Dictionary:
	return Stats.resolve_repair_device(items,equipment_ids,parameters)

func supports_weapon_hit(weapon: Variant) -> bool:
	error=""
	if _state.is_empty() or _hit_policy.is_empty() or _npc_weapons.is_empty() or not weapon is Dictionary: return reject("Player contacts require a supported initialized player and encounter weapon")
	for candidate in _npc_weapons:
		var matches:=true
		for key in candidate:
			if typeof(weapon.get(key))!=typeof(candidate[key]) or weapon.get(key)!=candidate[key]:matches=false
		if matches:return true
	return reject("Player contact weapon differs from its source NPC declaration")

func loadout() -> Dictionary:return _loadout.duplicate(true)

func weapon_hit(weapon: Variant, shooter_present: Variant, shooter_hostile: Variant, special_flight: Variant) -> Dictionary:
	if not supports_weapon_hit(weapon): return {}
	var resolver := Damage.new()
	var resolved := resolver.resolve(weapon.damage,_hit_policy,shooter_present,shooter_hostile,special_flight)
	if resolved.is_empty(): reject(resolver.error);return {}
	var pools := Vitals.new()
	if not pools.configure(_state.vitals.hull,_state.vitals.armor,_state.vitals.shield): reject(pools.error);return {}
	var result: Dictionary=pools.normal_hit(resolved.amount,_state.active and _state.damage_allowed)
	if result.is_empty(): reject(pools.error);return {}
	_state.vitals=pools.snapshot()
	result.resolution=resolved
	return result

func collision_context(pose: Variant) -> Dictionary:
	error=""
	if _state.is_empty() or _hit_policy.is_empty() or not pose is Transform3D or not pose.is_finite():
		reject("Player contacts require supported statistics and an explicit finite source pose");return {}
	var center := Vector3(Vitals.single(pose.origin.x),Vitals.single(pose.origin.y),Vitals.single(pose.origin.z))
	if not center.is_finite(): reject("Player collision center exceeds source precision");return {}
	# Fresh player statistics have no linked NPC actor. Player eligibility bypasses
	# the NPC actor's collision flag; the ordinary path uses statistics bounds.
	return {"base_content_id":_state.base_content_id,"binding_id":_state.binding_id,
		"eligible":_state.active and _state.vitals.hull>0,"path":"bounds","center":center,"half_extent":_state.half_extent}

func set_permissions(active: Variant, damage_allowed: Variant) -> bool:
	error=""
	if _state.is_empty() or not active is bool or not damage_allowed is bool: return reject("Player lifecycle requires explicit activity and damage permission")
	_state.active=active;_state.damage_allowed=damage_allowed
	return true

func record_contact(velocity: Variant) -> bool:
	error=""
	if _state.is_empty() or _hit_policy.is_empty() or not velocity is Vector3 or not velocity.is_finite(): return reject("Player contact requires supported statistics and a finite velocity")
	var impact := Vector3(Vitals.single(-velocity.x),Vitals.single(-velocity.y),Vitals.single(-velocity.z))
	if not impact.is_finite(): return reject("Player impact vector exceeds source precision")
	_state.contact=true;_state.impact_vector=impact
	return true

static func resolve_capacities(items: Array, equipment_ids: Array, parameters: Dictionary) -> Dictionary:
	return Stats.resolve_capacities(items,equipment_ids,parameters)

func snapshot() -> Dictionary:
	var result := _state.duplicate(true)
	if _recharge!=null: result.recharge=_recharge.snapshot()
	if _repair!=null: result.repair=_repair.snapshot()
	return result

func cache_snapshot() -> Dictionary:
	return _flight_cache.duplicate(true)

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._state=_state.duplicate(true)
	copy._flight_cache=_flight_cache.duplicate(true)
	copy._hit_policy=_hit_policy.duplicate(true);copy._npc_weapons=_npc_weapons.duplicate(true);copy._loadout=_loadout.duplicate(true)
	if _recharge!=null: copy._recharge=_recharge.fork_for_frame()
	if _repair!=null: copy._repair=_repair.fork_for_frame()
	return copy

func clear() -> void:
	error="";_state={};_hit_policy={};_npc_weapons=[];_loadout={};_flight_cache={}
	_recharge=null
	_repair=null

func reject(message: String) -> bool:
	error=message
	return false
