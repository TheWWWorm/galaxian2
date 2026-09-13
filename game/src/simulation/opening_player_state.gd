extends RefCounted
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
const Entry = preload("res://src/content/player_entry_definitions.gd")
const StationEquipment = preload("res://src/simulation/station_equipment.gd")
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

func _configure(bindings: RefCounted, catalogues: RefCounted, cursor: int, previous_cache: Variant, equipment: RefCounted=null) -> bool:
	clear()
	if bindings==null or catalogues==null: return reject("Player initialization requires content definitions")
	var entry:=Entry.new()
	if not entry.configure(bindings,cursor):return reject(entry.error)
	var arrival:=entry.is_arrival
	var departure:=entry.is_departure
	if entry.uses_equipment and not equipment is StationEquipment:return reject("Combat-training player requires the actual equipped tutorial ship")
	var parameters: Dictionary=bindings.opening_actors.get("player_initialization",{})
	if not Definitions.parameters(parameters) or not Actors.parameters(bindings.opening_actors):
		return reject("This profile has no supported fresh player initialization")
	var seed: Dictionary
	if entry.uses_equipment:
		if not equipment.requirements().satisfied:return reject("Install the required weapon and armor before combat training")
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
		if contacts.is_empty():return reject(entry.error)
		var candidates: Array=contacts.candidates
		for candidate in candidates:
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
	if arrival or departure:_state.gamma=current.gamma;_state.campaign_cursor=cursor
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
	if not RepairDefinitions.parameters(parameters) or not Vitals.integer(base) or upgrade_tags.size()>4096: return -1
	var result: int=base
	for tag in upgrade_tags:
		if not Vitals.integer(tag): return -1
		if tag==int(parameters.upgrade_tag):
			if result>Vitals.MAX_INTEGER-int(parameters.upgrade_bonus): return -1
			result+=int(parameters.upgrade_bonus)
	return result

static func resolve_repair_device(items: Array, equipment_ids: Array, parameters: Dictionary) -> Dictionary:
	if not RepairDefinitions.parameters(parameters) or equipment_ids.size()>4096: return {}
	var result := {"mode":int(parameters.missing_device_mode),"item_id":-1}
	for item_id in equipment_ids:
		if not Vitals.integer(item_id) or item_id>=items.size() or not items[item_id] is Dictionary: return {}
		var arrays: Variant=items[item_id].get("arrays")
		if not arrays is Array or arrays.size()!=3 or not (arrays[2] is Array or arrays[2] is PackedInt32Array) or arrays[2].size()<=int(parameters.item_type_value_index): return {}
		var kind: Variant=arrays[2][int(parameters.item_type_value_index)]
		if not Vitals.integer(kind): return {}
		if kind!=int(parameters.equipment_type): continue
		var source_id: Variant=arrays[2][int(parameters.item_id_value_index)]
		if not Vitals.integer(source_id): return {}
		result={"mode":0 if source_id==int(parameters.slow_item_id) else 1,"item_id":item_id}
	return result

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
	if not Definitions.parameters(parameters) or equipment_ids.size()>4096: return {}
	var result := {"shield":int(parameters.missing_capacity),"armor":int(parameters.missing_capacity),
		"shield_item_id":-1,"armor_item_id":-1}
	for item_id in equipment_ids:
		if not item_id is int or item_id<0 or item_id>=items.size() or not items[item_id] is Dictionary: return {}
		var item: Dictionary=items[item_id]
		var arrays: Variant=item.get("arrays")
		if not arrays is Array or arrays.size()!=3 or not (arrays[2] is Array or arrays[2] is PackedInt32Array) or arrays[2].size()<=int(parameters.item_type_value_index): return {}
		var type_id: Variant=arrays[2][int(parameters.item_type_value_index)]
		if not Numbers.integer(type_id,0,2147483647): return {}
		for pool in ["shield","armor"]:
			if int(type_id)!=int(parameters[pool+"_equipment_type"]): continue
			var properties: Variant=item.get("properties")
			if not properties is Dictionary: return {}
			var value: Variant=properties.get(int(parameters[pool+"_property"]))
			if not value is int or value<0 or value>Vitals.MAX_INTEGER or (pool=="shield" and value>Vitals.MAX_SHIELD): return {}
			result[pool]=value
			result[pool+"_item_id"]=item_id
	return result

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
