extends RefCounted
## Completes supported flight initialization from the post-scenery RNG.
## Every NPC constructor precedes the shared weapon-effect allocation sequence.
const FirstFlight=preload("res://src/content/first_flight_definitions.gd")
const MiningFlight=preload("res://src/content/full_hold_flight_definitions.gd")
const Training=preload("res://src/content/combat_training_definitions.gd")
const Loadout=preload("res://src/simulation/opening_loadout.gd")
const Definitions = preload("res://src/content/opening_world_initialization_definitions.gd")
const ArrivalDefinitions = preload("res://src/content/arrival_world_initialization_definitions.gd")
const ArrivalLocation = preload("res://src/simulation/arrival_location.gd")
const Construction = preload("res://src/simulation/opening_npc_construction.gd")
const Random = preload("res://src/simulation/seeded_random.gd")
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
		var assignments := []
		var items: Array=_definition.weapon_item_sequence
		var resources: Array=_definition.weapon_effect_sequence
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
