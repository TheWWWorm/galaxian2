extends RefCounted
## Shared population selection. Actor construction consumes the returned stream.
## This owner does not change missions, locations, equipment or career progress.
const Free=preload("res://src/content/free_population_definitions.gd")
const Delivery=preload("res://src/content/ordinary_contracts_definitions.gd")
const Contracts=preload("res://src/content/early_contract_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
const Definitions=preload("res://src/content/ambient_population_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Library=preload("res://src/content/library.gd")
var error:=""
var _identity:={}
var _common:={}
var _groups:={}
var _ordinary:={}
var _result:={}
var _seconds:=0

func configure(bindings: RefCounted,context: Dictionary,unix_seconds: Variant) -> bool:
	error="";_identity={};_common={};_groups={};_ordinary={};_result={}
	if bindings==null or not Travel.parameters(bindings.mido_travel) or not Definitions.parameters(bindings.ambient_population):return reject("Ambient population requires current imported declarations")
	if not unix_seconds is int or unix_seconds<0 or unix_seconds>2147483647:return reject("Ambient population requires supported Unix seconds")
	for key in ["base_content_id","binding_id"]:
		if not Library.valid_hash(bindings.get(key)):return reject("Ambient population requires an imported content identity")
	var data: Dictionary=bindings.ambient_population
	var chosen:={}
	for candidate in Definitions.contexts(bindings):
		if context.get("station_id")==candidate.station_id and context.get("campaign_cursor")==candidate.campaign_cursor:chosen=candidate
	if chosen.is_empty() or context.get("system_id")!=data.system_id:return reject("This location and campaign context has no supported ambient population")
	if context.get("mission_kind")!=data.mission_kind or context.get("mission_completed")!=true or context.get("mission_story")!=data.mission_story:return reject("Ambient traffic requires the completed default world mission")
	if context.get("companions_empty")!=true or context.get("station_response")!=data.station_response:return reject("This population does not support companion or station-response overrides")
	var difficulty: Variant=context.get("difficulty")
	if (not difficulty is float and not difficulty is int) or not data.supported_difficulties.any(func(value):return float(value)==float(difficulty)):return reject("Unsupported ambient population difficulty")
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"system_id":int(data.system_id),"station_id":int(chosen.station_id),"campaign_cursor":int(chosen.campaign_cursor)}
	_common=bindings.mido_travel.departure_traffic.duplicate(true)
	_groups=data.duplicate(true) if chosen.mixed else {}
	_seconds=unix_seconds
	return true

func configure_free(bindings: RefCounted,catalogues: RefCounted,context: Dictionary,unix_seconds: Variant) -> bool:
	error="";_identity={};_common={};_groups={};_ordinary={};_result={}
	if not Free.available(bindings) or catalogues==null:return reject("Ordinary traffic requires its imported population and catalogue declarations")
	if catalogues.content_id!=bindings.base_content_id:return reject("Ordinary population catalogues belong to another content")
	if not unix_seconds is int or unix_seconds<0 or unix_seconds>2147483647:return reject("Ordinary traffic requires supported Unix seconds")
	var data: Dictionary=bindings.mido_travel.free_population
	var world: Dictionary=load("res://src/content/ordinary_world_definitions.gd").catalogue_location(bindings,catalogues,context.get("station_id"))
	if world.is_empty() or context.get("system_id")!=world.system_id or context.get("campaign_cursor")!=int(data.campaign_cursor):return reject("This location and campaign context has no ordinary population support")
	if not Delivery.mission_context_valid(bindings,context):return reject("Ordinary traffic requires its retained empty or supported delivery mission")
	# These are explicit source inputs. Mission/session owners must produce them;
	# construction never infers missing retained state or grants campaign progress.
	if context.get("companions_empty")!=true:return reject("This population does not support companion overrides")
	for key in ["station_response","void_encounter"]:
		if context.get(key)!=false:return reject("This population does not support encounter or response overrides")
	if not load("res://src/content/free_arrival_definitions.gd").context_supported(bindings,context):return reject("Ordinary arrival placement requires its verified flag and player position")
	if not Numbers.integer(context.get("rank"),0,bindings.opening_handoff.rank_thresholds.size()-1):return reject("Ordinary traffic requires a supported rank")
	var difficulty: Variant=context.get("difficulty")
	if (not difficulty is float and not difficulty is int) or not data.supported_difficulties.any(func(value):return float(value)==float(difficulty)):return reject("Unsupported ordinary population difficulty")
	for key in ["base_content_id","binding_id"]:
		if not Library.valid_hash(bindings.get(key)):return reject("Ordinary population requires an imported content identity")
	var system: Dictionary=catalogues.tables.systems[int(context.system_id)]
	if not system.station_ids.has(context.station_id):return reject("Ordinary population station does not belong to its system")
	var security: int=system.fields[int(data.security_field)]
	var faction: int=system.fields[int(data.faction_field)]
	if security!=world.security or faction!=world.faction:return reject("The ordinary system security or faction changed")
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"system_id":int(context.system_id),"station_id":int(context.station_id),"campaign_cursor":int(context.campaign_cursor)}
	_common=bindings.mido_travel.departure_traffic.duplicate(true)
	_groups=bindings.ambient_population.duplicate(true)
	_ordinary=data.duplicate(true)
	_ordinary.merge({"security":security,"faction":faction,"rank":int(context.rank),"difficulty":float(difficulty)})
	if not context.side_missions_empty:
		_ordinary.delivery_count=Delivery.extra_count(bindings,context)
		_ordinary.active_courier=Delivery.active_courier(context)
		_ordinary.encounter=bindings.early_contracts.encounter_construction.duplicate(true)
	_seconds=unix_seconds
	return true

func generate(random_state: Variant) -> Dictionary:
	error=""
	if _identity.is_empty() or not _result.is_empty():return fail("Configure a fresh ambient population before generating once")
	var random:=Random.new()
	if not random.restore(random_state):return fail(random.error)
	var result:=_sample(_common,_groups,_seconds,random,_ordinary)
	result.merge(_identity)
	_result=result
	return snapshot()

func snapshot() -> Dictionary:
	return _result.duplicate(true)

static func first_departure(data: Dictionary,random: RefCounted) -> Dictionary:
	# The caller has already validated the old departure declaration. Preserve
	# its snapshot shape and stream for existing content packs and scenarios.
	var result:=_sample(data,{},int(data.unix_seconds),random)
	result.erase("groups")
	return result

static func _sample(common: Dictionary,groups: Dictionary,seconds: int,random: RefCounted,ordinary: Dictionary={}) -> Dictionary:
	if ordinary.get("active_courier",false):
		var incoming: Dictionary=random.snapshot()
		var enemy:=Contracts.draw_enemy_faction(ordinary.encounter,random,int(ordinary.enemy_factions[int(ordinary.faction)]))
		return {"mission_kind":0,"incoming_random_state":incoming,"system_faction":int(ordinary.faction),"security":int(ordinary.security),
			"hostile_selected":false,"hostile_faction":enemy,"unused_route_origin":Vector3.ZERO,"spawn_center":Vector3.ZERO,
			"groups":{"patrol":0,"travel":0,"freighter":0,"hostile":0,"delivery_pirate":0},"actor_count":0,"before_actors_random_state":random.snapshot()}
	# Scenery has consumed the incoming stream, but a completed default mission
	# starts a fresh Unix-seeded population. Dormant hostile choices still draw.
	random.seed_from(seconds)
	var result:={"unix_seconds":seconds,"seed_random_state":random.snapshot()}
	result.hostile_chance_draw=random.next_int(int(common.hostile_chance_bound))
	var unused:=Vector3.ZERO
	for axis in 3:
		unused[axis]=int(common.unused_route_offsets[axis])
		if int(common.unused_route_bounds[axis])>0:unused[axis]+=random.next_int(int(common.unused_route_bounds[axis]))
	result.unused_route_origin=unused
	result.hostile_faction_draw=random.next_int(int(common.hostile_faction_bound))
	var counts:={"patrol":0,"travel":0,"freighter":0}
	var extra_patrol:=0
	if not ordinary.is_empty():
		result.hostile_selected=int(result.hostile_chance_draw)<int(ordinary.hostile_chance_thresholds[int(ordinary.security)])
		result.hostile_faction=int(ordinary.pirate_faction) if int(result.hostile_faction_draw)<int(common.hostile_faction_threshold) else int(ordinary.enemy_factions[int(ordinary.faction)])
		counts.hostile=0
		if result.hostile_selected:
			var drawn: int=random.next_int(int(ordinary.hostile_count_bound))
			result.hostile_count_draw=drawn
			if drawn>0:
				var adjusted: float=Vitals.single(Vitals.single(float(ordinary.difficulty)+float(ordinary.hostile_difficulty_offset))*float(drawn))
				counts.hostile=int(Vitals.single(adjusted+float(drawn)))+int(float(ordinary.rank)/float(ordinary.hostile_rank_divisor))
			if int(ordinary.security)==int(ordinary.easy_security) and float(ordinary.difficulty)<float(ordinary.easy_difficulty_threshold):counts.hostile=int(ordinary.easy_count_offset)+random.next_int(int(ordinary.easy_count_bound))
	if not groups.is_empty():
		counts.travel=random.next_int(int(groups.travel_count_bound))
		counts.freighter=random.next_int(int(groups.freighter_count_bound))
		extra_patrol=random.next_int(int(groups.extra_patrol_count_bound))
	if ordinary.is_empty():
		result.count_draw=random.next_int(int(common.actor_count_bound))
		counts.patrol=int(result.count_draw)+extra_patrol
	else:
		counts.patrol=int(ordinary.security)+extra_patrol
		result.system_faction=int(ordinary.faction)
		result.security=int(ordinary.security)
	if not groups.is_empty():
		@warning_ignore("integer_division")
		counts.patrol+=int(counts.freighter)/int(groups.freighters_per_patrol)
	if ordinary.has("delivery_count"):counts.delivery_pirate=int(ordinary.delivery_count)
	if counts.patrol+counts.travel+counts.freighter+int(counts.get("hostile",0))+int(counts.get("delivery_pirate",0))==0:counts.patrol=int(common.empty_population_fallback)
	result.groups=counts
	result.actor_count=counts.patrol+counts.travel+counts.freighter+int(counts.get("hostile",0))+int(counts.get("delivery_pirate",0))
	var center:=Vector3.ZERO
	for axis in 3:center[axis]=int(common.spawn_center_offsets[axis])+random.next_int(int(common.spawn_center_bounds[axis]))
	result.spawn_center=center
	result.before_actors_random_state=random.snapshot()
	return result

func reject(message: String) -> bool:
	error=message
	return false

func fail(message: String) -> Dictionary:
	reject(message)
	return {}
