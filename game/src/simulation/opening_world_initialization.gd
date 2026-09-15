extends RefCounted
## Completes supported flight initialization from the post-scenery RNG.
## Every NPC constructor precedes the shared weapon-effect allocation sequence.
const FirstFlight=preload("res://src/content/first_flight_definitions.gd")
const MiningFlight=preload("res://src/content/full_hold_flight_definitions.gd")
const Training=preload("res://src/content/combat_training_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Loadout=preload("res://src/simulation/opening_loadout.gd")
const Definitions = preload("res://src/content/opening_world_initialization_definitions.gd")
const ArrivalDefinitions = preload("res://src/content/arrival_world_initialization_definitions.gd")
const ArrivalLocation = preload("res://src/simulation/arrival_location.gd")
const Construction = preload("res://src/simulation/opening_npc_construction.gd")
const Random = preload("res://src/simulation/seeded_random.gd")
const ContractWorld=preload("res://src/content/contract_world_definitions.gd")
const Convoy=preload("res://src/content/convoy_world_definitions.gd")
const Alioth=preload("res://src/content/alioth_population_definitions.gd")
var error := ""
var _identity := {}
var _definition := {}
var _construction: RefCounted
var _state := {}

func configure(bindings: RefCounted, catalogues: RefCounted) -> bool:
	clear()
	if bindings==null or catalogues==null: return reject("World initialization requires content and bindings")
	var data: Variant=bindings.opening_actors.get("npc_initialization",{}).get("world_initialization",{})
	if not Definitions.parameters(data): return reject("World initialization is unavailable in this pack")
	var construction := Construction.new()
	if not construction.configure(bindings,catalogues): return reject(construction.error)
	var hulls: Array=bindings.opening_actors.actors.map(func(actor):return int(actor.hull_catalogue_id))
	return _configure(bindings,catalogues,data,construction,hulls)

func configure_arrival(bindings: RefCounted, catalogues: RefCounted, cache: Variant, entry_conditions: Variant) -> bool:
	clear()
	if bindings==null or not ArrivalDefinitions.parameters(bindings.arrival_world_initialization):
		return reject("Rescue world initialization is unavailable; prepare current resource bindings")
	if not ArrivalDefinitions.entry_conditions(entry_conditions):
		return reject("Rescue initialization requires its retained ordinary location and no companions")
	var location:=ArrivalLocation.new()
	var context:=location.resolve(bindings,catalogues,cache)
	if context.is_empty():return reject(location.error)
	var construction:=Construction.new()
	if not construction.configure_arrival(bindings,catalogues,cache):return reject(construction.error)
	if not _configure(bindings,catalogues,bindings.arrival_world_initialization,construction,[int(bindings.arrival_actor_construction.hull_catalogue_id)]):return false
	_identity.campaign_cursor=int(bindings.arrival_world_initialization.campaign_cursor)
	_identity.entry_conditions=entry_conditions.duplicate(true)
	return true

func configure_departure(bindings: RefCounted, catalogues: RefCounted, cache: Variant, entry_conditions: Variant) -> bool:
	clear()
	if bindings==null or not cache is Dictionary or not FirstFlight.entry_conditions(entry_conditions):return reject("Mining-flight initialization requires its ordinary departure context")
	var data:=MiningFlight.flight(bindings,cache.get("campaign_cursor"))
	if data.is_empty():return reject("This mining departure has no supported world construction")
	var location:=ArrivalLocation.new()
	if location.resolve_departure(bindings,catalogues,cache).is_empty():return reject(location.error)
	var loadout:=Loadout.new()
	if not loadout.configure_station(bindings,catalogues,bindings.base_content_id):return reject(loadout.error)
	var construction: RefCounted
	var hulls:=[]
	if int(data.actor_count)>0:
		construction=Construction.new()
		if not construction.configure_full_hold(bindings,catalogues,cache):return reject(construction.error)
		hulls.append(int(data.hull_catalogue_id))
	if not _configure(bindings,catalogues,data,construction,hulls,loadout.snapshot().slots.filter(func(slot):return slot!=null)):return false
	_identity.campaign_cursor=int(data.campaign_cursor)
	_identity.entry_conditions=entry_conditions.duplicate(true)
	return true

func configure_combat_training(bindings: RefCounted, catalogues: RefCounted, equipment: RefCounted, player_position: Variant, entry_conditions: Variant) -> bool:
	clear()
	if bindings==null or not Training.parameters(bindings.combat_training):return reject("Combat-training world initialization is unavailable")
	if not FirstFlight.entry_conditions(entry_conditions):return reject("Combat-training initialization requires the ordinary location and no additional companions")
	var data: Dictionary=bindings.combat_training
	for resource_id in data.companion_weapon_effect_sequence:
		if bindings.resolve(int(resource_id),"mesh").is_empty():return reject(bindings.error)
	var construction:=Construction.new()
	if not construction.configure_combat_training(bindings,catalogues,equipment,player_position):return reject(construction.error)
	var hulls: Array=[]
	for id in int(data.actor_count):hulls.append(int(data.companion_hull_catalogue_id if id==int(data.companion_actor_id) else data.pirate_hull_catalogue_id))
	if not _configure(bindings,catalogues,data,construction,hulls,equipment.snapshot().loadout.slots.filter(func(slot):return slot!=null)):return false
	_identity.campaign_cursor=int(data.campaign_cursor);_identity.entry_conditions=entry_conditions.duplicate(true)
	return true

func configure_contract(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,contracts: RefCounted,player_cache: Dictionary,entry_conditions: Dictionary,unix_seconds: Variant,player_position: Vector3,field_center: Vector3) -> bool:
	clear()
	if not ContractWorld.available(bindings) or not is_instance_of(contracts,load("res://src/simulation/contract_session.gd")) or not FirstFlight.entry_conditions(entry_conditions):return reject("Ordinary contract construction needs its retained session and entry conditions")
	var location:=ArrivalLocation.new()
	var context:=location.resolve_local_travel(bindings,catalogues,equipment,player_cache)
	if context.is_empty():return reject(location.error)
	var data:=ContractWorld.flight(bindings,int(context.station_id),int(context.campaign_cursor))
	if data.is_empty() or contracts.snapshot().campaign_cursor!=context.campaign_cursor:return reject("Unsupported ordinary contract world location")
	var accepted: Dictionary=contracts.flight_context(int(context.station_id))
	if accepted.is_empty():return reject(contracts.error)
	var construction:=Construction.new()
	if accepted.mission.is_empty():
		var ambient:={"system_id":int(context.system_id),"station_id":int(context.station_id),"campaign_cursor":int(context.campaign_cursor),
			"difficulty":accepted.difficulty,"mission_kind":-1,"mission_completed":true,"mission_story":false,
			"companions_empty":true,"station_response":false}
		if not construction.configure_ambient_traffic(bindings,catalogues,equipment,ambient,unix_seconds):return reject(construction.error)
		data.weapon_groups=Travel.journey(bindings.mido_travel,11).weapon_groups.duplicate()
	else:
		if not construction.configure_contract(bindings,catalogues,equipment,contracts,player_position,field_center):return reject(construction.error)
		data.weapon_groups=["pirate","rival"]
	if not _bind_faction_weapon_effects(bindings,data):return false
	if not _configure(bindings,catalogues,data,construction,[],equipment.snapshot().loadout.slots.filter(func(slot):return slot!=null)):return false
	_identity.merge({"campaign_cursor":int(context.campaign_cursor),"station_id":int(context.station_id),"entry_conditions":entry_conditions.duplicate(true),"contract_context":accepted})
	return true

func configure_free_factory(bindings: RefCounted,catalogues: RefCounted,player_ship_id: int,equipment_ids: Array,context: Dictionary,unix_seconds: Variant,entry_conditions: Dictionary) -> bool:
	clear()
	if not FirstFlight.entry_conditions(entry_conditions):return reject("Ordinary population requires normal placement and no additional companions")
	var construction:=Construction.new()
	if not construction.configure_free_factory(bindings,catalogues,player_ship_id,equipment_ids,context,unix_seconds):return reject(construction.error)
	return _configure_free(bindings,catalogues,construction,player_ship_id,equipment_ids,context,entry_conditions)

func configure_free_traffic(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,context: Dictionary,unix_seconds: Variant,entry_conditions: Dictionary) -> bool:
	clear()
	if not FirstFlight.entry_conditions(entry_conditions):return reject("Ordinary initialization requires ordinary entry with no additional companions")
	var construction:=Construction.new()
	if not construction.configure_free_traffic(bindings,catalogues,equipment,context,unix_seconds):return reject(construction.error)
	var seed: Dictionary=equipment.snapshot().loadout
	return _configure_free(bindings,catalogues,construction,int(seed.ship_id),seed.equipment_ids,context,entry_conditions)

func _configure_free(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,player_ship_id: int,equipment_ids: Array,context: Dictionary,entry_conditions: Dictionary) -> bool:
	var data:={"scope":"ordinary_population_initialization","weapon_groups":["patrol","travel","hostile"]}
	if not context.side_missions_empty:data.weapon_groups.append("delivery_pirate")
	if not _bind_faction_weapon_effects(bindings,data):return false
	var equipment: Array=equipment_ids.map(func(id):return {"item_id":id})
	if not _configure(bindings,catalogues,data,construction,[player_ship_id],equipment):return false
	_identity.merge({"campaign_cursor":int(context.campaign_cursor),"station_id":int(context.station_id),"entry_conditions":entry_conditions.duplicate(true)})
	return true

func _bind_faction_weapon_effects(bindings: RefCounted,data: Dictionary) -> bool:
	# Each armed ship allocates a default item0 pool and then its faction pool.
	# Both allocate their own four impact flips after all actors are constructed.
	var shared: Dictionary=bindings.opening_actors.npc_initialization.world_initialization
	for key in ["weapon_effect_capacity","weapon_effect_random_bound","zero_means_flipped"]:data[key]=shared[key]
	data.weapon_item_sequence=[];data.weapon_effect_sequence=[];data.faction_weapon_effects={}
	var default_model:=ContractWorld.impact_model(bindings,0)
	if default_model<0 or bindings.resolve(default_model,"mesh").is_empty():return reject("Default weapon impact art is unavailable")
	for row in bindings.early_contracts.ship_combat.weapons.factions:
		var model:=ContractWorld.impact_model(bindings,int(row.item_id))
		if model<0 or bindings.resolve(model,"mesh").is_empty():return reject("Faction weapon impact art is unavailable")
		data.faction_weapon_effects[int(row.actor_kind)]={"items":[0,int(row.item_id)],"resources":[default_model,model]}
	return true

func configure_convoy(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,context: Dictionary,entry_conditions: Dictionary) -> bool:
	clear()
	if not FirstFlight.entry_conditions(entry_conditions):return reject("Convoy initialization requires an ordinary flight with no extra companions")
	var construction:=Construction.new()
	if not construction.configure_convoy(bindings,catalogues,equipment,context):return reject(construction.error)
	var data:=Convoy.initialization(bindings)
	for row in data.faction_weapon_effects.values():
		for resource in row.resources:
			if resource<0 or bindings.resolve(int(resource),"mesh").is_empty():return reject("Convoy weapon effects are unavailable")
	var hulls: Array=data.actors.map(func(actor):return int(actor.hull_catalogue_id))
	if not _configure(bindings,catalogues,data,construction,hulls,equipment.snapshot().loadout.slots.filter(func(slot):return slot!=null)):return false
	_identity.merge({"campaign_cursor":context.campaign_cursor,"station_id":context.station_id,"entry_conditions":entry_conditions.duplicate(true)})
	return true

func configure_alioth_attack(bindings: RefCounted,catalogues: RefCounted,seed: Dictionary,context: Dictionary,player_position: Vector3,entry_conditions: Dictionary) -> bool:
	clear()
	if not FirstFlight.entry_conditions(entry_conditions):return reject("Alioth initialization requires ordinary entry with no additional companions")
	var construction:=Construction.new()
	if not construction.configure_alioth_attack(bindings,catalogues,seed,context,player_position):return reject(construction.error)
	var data:=Alioth.initialization(bindings)
	if data.is_empty():return reject("Alioth weapon-effect construction is unavailable")
	for row in data.faction_weapon_effects.values():
		for resource in row.resources:
			if resource<0 or bindings.resolve(int(resource),"mesh").is_empty():return reject("Alioth weapon effects are unavailable")
	var hulls: Array=data.actors.map(func(actor):return int(actor.hull_catalogue_id))
	var equipment: Array=seed.equipment_ids.map(func(id):return {"item_id":id})
	if not _configure(bindings,catalogues,data,construction,hulls,equipment):return false
	_identity.merge({"campaign_cursor":context.campaign_cursor,"station_id":context.station_id,"entry_conditions":entry_conditions.duplicate(true)})
	return true

func _configure(bindings: RefCounted, catalogues: RefCounted, data: Dictionary, construction: RefCounted, hulls: Array, equipment: Array=[]) -> bool:
	var shared: Dictionary=bindings.opening_actors.get("npc_initialization",{}).get("world_initialization",{})
	if not Definitions.parameters(shared):return reject("Shared world initialization is unavailable in this pack")
	# The retained initial equipment excludes both optional population groups.
	for item in (bindings.opening_loadout.equipment if equipment.is_empty() else equipment):
		var equipment_type: int=catalogues.tables.items[int(item.item_id)].arrays[2][5]
		if shared.absent_equipment_types.any(func(value): return int(value)==equipment_type):
			return reject("Initial equipment does not exclude the optional population")
	for hull in hulls:
		if shared.absent_hull_ids.any(func(value): return int(value)==hull):
			return reject("Initial hull does not exclude attached actors")
	for resource_id in data.weapon_effect_sequence:
		if bindings.resolve(int(resource_id),"mesh").is_empty(): return reject(bindings.error)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_definition=data.duplicate(true);_construction=construction
	return true

func configure_local_arrival(bindings: RefCounted, catalogues: RefCounted, equipment: RefCounted, player_cache: Dictionary, entry_conditions: Dictionary) -> bool:
	clear()
	if not FirstFlight.entry_conditions(entry_conditions):return reject("Local arrival requires ordinary placement and no companions")
	var location:=ArrivalLocation.new()
	var context:=location.resolve_local_travel(bindings,catalogues,equipment,player_cache)
	if context.is_empty():return reject(location.error)
	var trip:=Travel.journey(bindings.mido_travel,int(context.campaign_cursor))
	if trip.is_empty() or int(context.station_id)!=int(trip.station_id):return reject("The empty story population belongs only to its mission arrival")
	var data:=Travel.flight(bindings,int(context.station_id),int(context.campaign_cursor))
	if data.is_empty():return reject("This local location has no supported story population")
	if not _configure(bindings,catalogues,data,null,[],equipment.snapshot().loadout.slots.filter(func(slot):return slot!=null)):return false
	_identity.campaign_cursor=int(context.campaign_cursor);_identity.station_id=int(context.station_id);_identity.entry_conditions=entry_conditions.duplicate(true)
	return true

func configure_local_traffic(bindings: RefCounted, catalogues: RefCounted, equipment: RefCounted, unix_seconds: Variant, entry_conditions: Dictionary, difficulty:=0.5, cursor: int=10) -> bool:
	clear()
	if bindings==null or not Travel.parameters(bindings.mido_travel):return reject("Local departure traffic is unavailable")
	if not FirstFlight.entry_conditions(entry_conditions):return reject("Local departure requires ordinary placement and no companions")
	var trip:=Travel.journey(bindings.mido_travel,cursor)
	if trip.is_empty():return reject("Unsupported local traffic mission context")
	var data:=Travel.flight(bindings,int(trip.from_station_id),cursor)
	if data.is_empty():return reject("Local traffic lacks its verified lifecycle")
	if not data.supported_difficulties.any(func(value):return float(value)==difficulty):return reject("This local traffic profile does not support that difficulty")
	var construction:=Construction.new()
	if cursor in [11,12]:
		var context:={"system_id":int(trip.system_id),"station_id":int(trip.from_station_id),"campaign_cursor":cursor,"difficulty":difficulty,
			"mission_kind":-1,"mission_completed":true,"mission_story":false,"companions_empty":true,"station_response":false}
		if not construction.configure_ambient_traffic(bindings,catalogues,equipment,context,unix_seconds):return reject(construction.error)
		data.weapon_groups=trip.weapon_groups.duplicate()
	elif not construction.configure_local_traffic(bindings,catalogues,equipment,unix_seconds):return reject(construction.error)
	if not _configure(bindings,catalogues,data,construction,data.hull_candidates,equipment.snapshot().loadout.slots.filter(func(slot):return slot!=null)):return false
	_identity.campaign_cursor=int(data.campaign_cursor);_identity.station_id=int(data.station_id)
	_identity.entry_conditions=entry_conditions.duplicate(true)
	return true

func generate(random_state: Variant) -> Dictionary:
	error=""
	if _identity.is_empty() or not _state.is_empty(): return fail("Configure fresh world initialization before generating once")
	var random := Random.new()
	if not random.restore(random_state): return fail(random.error)
	var input := random.snapshot()
	if _construction==null:
		# This profile creates no NPC list. In particular it must not create the
		# rescue actor, assign its weapons, or consume its construction draws.
		_state=_identity.duplicate(true)
		_state.merge({"input_random_state":input,"npc_construction":{"actors":[],"random_state":input.duplicate(true)},"weapon_effects":[],"random_state":input.duplicate(true)})
		return snapshot()
	var generated: Dictionary=_construction.generate(input)
	if generated.is_empty(): return fail(_construction.error)
	# Construction validates its own RNG result. All following bounds are fixed
	# validated declarations, so no fallible operation follows this owner commit.
	random.restore(generated.random_state)
	var effects := []
	for id in generated.actors.size():
		if _definition.has("weapon_groups") and not _definition.weapon_groups.has(generated.actors[id].get("population_group")):
			effects.append({"actor_id":id,"unarmed":true});continue
		var assignments := []
		var items: Array=_definition.weapon_item_sequence
		var resources: Array=_definition.weapon_effect_sequence
		if _definition.has("faction_weapon_effects"):
			var armory: Dictionary=_definition.faction_weapon_effects[int(generated.actors[id].actor_kind)]
			items=armory.items;resources=armory.resources
		if _definition.get("scope")=="combat_training_encounter_construction" and id==int(_definition.companion_actor_id):
			items=_definition.companion_weapon_item_sequence;resources=_definition.companion_weapon_effect_sequence
		for index in items.size():
			var flipped := []
			for slot in int(_definition.weapon_effect_capacity):
				flipped.append(random.next_int(int(_definition.weapon_effect_random_bound))==0)
			assignments.append({"item_id":int(items[index]),"resource_id":int(resources[index]),"flipped":flipped})
		effects.append({"actor_id":id,"discarded_default":assignments[0],"primary":assignments[1]})
	_state=_identity.duplicate()
	_state.merge({"input_random_state":input,"npc_construction":generated,"weapon_effects":effects,"random_state":random.snapshot()})
	return snapshot()

func route(actor_id: int) -> RefCounted:
	error=""
	if _state.is_empty():
		reject("Generate world initialization before requesting an NPC route")
		return null
	if _construction==null:
		reject("This flight has no initial NPC routes");return null
	var result: RefCounted=_construction.route(actor_id)
	if result==null: reject(_construction.error)
	return result

func arrival_motion_construction() -> Dictionary:
	error=""
	if _state.is_empty() or _construction==null or _identity.get("campaign_cursor")!=1:return fail("Generate rescue initialization before requesting actor poses")
	var result: Dictionary=_construction.arrival_motion_construction()
	if result.is_empty():return fail(_construction.error)
	return result

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func npc_construction_owner() -> RefCounted:
	# A completed constructor cannot generate again and exposes detached routes.
	return _construction if not _state.is_empty() else null

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	if _state.is_empty():return copy
	copy._identity=_identity.duplicate(true);copy._definition=_definition.duplicate(true);copy._state=_state.duplicate(true)
	# A generated constructor rejects a second generation and only returns
	# detached routes. Reconfiguration replaces it rather than mutating it.
	copy._construction=_construction
	return copy

func clear() -> void:
	error="";_identity={};_definition={};_construction=null;_state={}

func reject(message: String) -> bool:
	error=message
	return false

func fail(message: String) -> Dictionary:
	reject(message)
	return {}
