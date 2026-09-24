extends RefCounted
## Native generated coordinate patrol. The caller supplies the shared RNG at the
## source constructor's route-draw boundary, before any actor updates.
const Definitions = preload("res://src/content/npc_route_definitions.gd")
const OpeningContext = preload("res://src/content/opening_sky_definitions.gd")
const ArrivalConstruction = preload("res://src/content/arrival_actor_construction_definitions.gd")
const FullHold = preload("res://src/content/full_hold_flight_definitions.gd")
const Training = preload("res://src/content/combat_training_definitions.gd")
const Travel = preload("res://src/content/mido_travel_definitions.gd")
const Contracts = preload("res://src/content/early_contract_definitions.gd")
const Convoy = preload("res://src/content/convoy_world_definitions.gd")
const Kappa = preload("res://src/content/kappa_rescue_definitions.gd")
const Alioth = preload("res://src/content/alioth_attack_definitions.gd")
const Sahi = preload("res://src/content/sahi_encounter_definitions.gd")
const Dima = preload("res://src/content/dima_encounter_definitions.gd")
const VoidCrystals = preload("res://src/content/void_crystal_definitions.gd")
const TrafficPopulation = preload("res://src/simulation/traffic_population.gd")
const AliothSequence = preload("res://src/simulation/alioth_attack.gd")
const Random = preload("res://src/simulation/seeded_random.gd")
const Vectors = preload("res://src/simulation/source_vectors.gd")
const Vitals = preload("res://src/simulation/combat_vitals.gd")
var error := ""
var _identity := {}
var _definition := {}
var _points := []
var _candidates := []
var _index := 0
var _loop := true
var _authored := false
var _ambient_restart := false
var _kappa_patrol := {}
var _sahi_patrol := {}

func configure(bindings: RefCounted, actor_id: Variant) -> bool:
	clear()
	if bindings==null or not OpeningContext.parameters(bindings.opening_sky): return reject("NPC routes require the fresh opening context")
	var data: Variant = bindings.opening_actors.get("npc_initialization",{}).get("routes",{})
	if not Definitions.parameters(data): return reject("Generated NPC routes are unavailable in this pack")
	if not Vitals.integer(actor_id) or actor_id>2: return reject("Unknown opening NPC route owner")
	var actors: Variant = bindings.opening_actors.get("actors")
	if not actors is Array or actors.size()!=3: return reject("NPC route population is unsupported")
	for id in 3:
		if not actors[id] is Dictionary or actors[id].get("actor_id")!=id or actors[id].get("actor_kind")!=8 or actors[id].get("hull_catalogue_id")!=[2,23,2][id]:
			return reject("NPC routes require the source opening enemy population")
	return _configure_generated(bindings,actor_id,data)

func configure_arrival_generated(bindings: RefCounted) -> bool:
	clear()
	if bindings==null or not ArrivalConstruction.parameters(bindings.arrival_actor_construction):
		return reject("Generated rescue route construction is unavailable in this pack")
	var data: Variant=bindings.opening_actors.get("npc_initialization",{}).get("routes",{})
	if not Definitions.parameters(data):return reject("Generated NPC routes are unavailable in this pack")
	_configure_generated(bindings,0,data)
	_identity.campaign_cursor=1
	return true

func _configure_generated(bindings: RefCounted, actor_id: int, data: Dictionary) -> bool:
	_definition=data.duplicate(true)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"actor_id":actor_id}
	_index=int(data.initial_index)
	return true

func configure_full_hold_generated(bindings: RefCounted) -> bool:
	clear()
	if bindings==null or not FullHold.parameters(bindings.full_hold_flight):return reject("Second-flight generated route is unavailable")
	var data: Variant=bindings.opening_actors.get("npc_initialization",{}).get("routes",{})
	if not Definitions.parameters(data):return reject("Generated NPC routes are unavailable in this pack")
	_configure_generated(bindings,0,data)
	_identity.campaign_cursor=int(bindings.full_hold_flight.campaign_cursor)
	return true

func configure_training_generated(bindings: RefCounted, actor_id: Variant) -> bool:
	clear()
	if bindings==null or not Training.parameters(bindings.combat_training):return reject("Combat-training routes are unavailable")
	if not actor_id is int or actor_id<0 or actor_id>=int(bindings.combat_training.actor_count):return reject("Unknown combat-training route owner")
	var data: Variant=bindings.opening_actors.get("npc_initialization",{}).get("routes",{})
	if not Definitions.parameters(data):return reject("Generated NPC routes are unavailable in this pack")
	_configure_generated(bindings,actor_id,data)
	_identity.campaign_cursor=int(bindings.combat_training.campaign_cursor)
	return true

func configure_local_generated(bindings: RefCounted, actor_id: int) -> bool:
	clear()
	if bindings==null or not Travel.parameters(bindings.mido_travel):return reject("Local traffic routes are unavailable")
	if actor_id<0 or actor_id>=int(bindings.mido_travel.departure_traffic.empty_population_fallback):return reject("Unknown local traffic route owner")
	var data: Dictionary=bindings.opening_actors.get("npc_initialization",{}).get("routes",{})
	if not Definitions.parameters(data):return reject("Generated NPC routes are unavailable in this pack")
	_configure_generated(bindings,actor_id,data)
	_identity.campaign_cursor=int(bindings.mido_travel.departure_traffic.campaign_cursor)
	return true

func configure_ambient_generated(bindings: RefCounted,actor_id: int,cursor: int) -> bool:
	clear()
	var rules=preload("res://src/content/ambient_population_definitions.gd")
	if bindings==null or not rules.parameters(bindings.ambient_population):return reject("Ambient routes require imported population declarations")
	var population: Dictionary=bindings.ambient_population
	if not rules.contexts(bindings).any(func(row):return int(row.campaign_cursor)==cursor):return reject("Unsupported ambient route context")
	var maximum: int=rules.maximum_actor_count(population,bindings.mido_travel.departure_traffic)
	if actor_id<0 or actor_id>=maximum:return reject("Unknown ambient route owner")
	var data: Dictionary=bindings.opening_actors.get("npc_initialization",{}).get("routes",{})
	if not Definitions.parameters(data):return reject("Generated NPC routes are unavailable in this pack")
	_configure_generated(bindings,actor_id,data)
	_identity.campaign_cursor=cursor
	_ambient_restart=rules.contexts(bindings).any(func(row):return int(row.campaign_cursor)==cursor and row.mixed)
	return true

func configure_free_generated(bindings: RefCounted,actor_id: int,context: Dictionary) -> bool:
	clear()
	var rules=preload("res://src/content/free_population_definitions.gd")
	if not rules.available(bindings):return reject("Ordinary routes require imported population declarations")
	var limits=preload("res://src/content/opening_definitions.gd")
	var population: Dictionary=bindings.mido_travel.free_population
	if not load("res://src/content/free_campaign_definitions.gd").supported(bindings.mido_travel,context.get("campaign_cursor")) or not limits.integer(context.get("rank"),0,bindings.opening_handoff.rank_thresholds.size()-1):return reject("Invalid ordinary route context")
	var difficulty: Variant=context.get("difficulty")
	if (not difficulty is float and not difficulty is int) or not population.supported_difficulties.any(func(value):return float(value)==float(difficulty)):return reject("Invalid ordinary route difficulty")
	if actor_id<0 or actor_id>=rules.maximum_actor_count(bindings,int(context.rank),float(context.difficulty),context):return reject("Unknown ordinary traffic route owner")
	var data: Dictionary=bindings.opening_actors.get("npc_initialization",{}).get("routes",{})
	if not Definitions.parameters(data):return reject("Generated NPC routes are unavailable in this pack")
	_configure_generated(bindings,actor_id,data)
	_identity.campaign_cursor=int(context.campaign_cursor)
	_ambient_restart=true
	return true

func configure_void_generated(bindings: RefCounted,actor_id: int,context: Dictionary) -> bool:
	clear()
	if bindings==null or not VoidCrystals.selected_void(bindings.mido_travel,context):return reject("Void route requires its selected and retained nonstory world")
	var population:=TrafficPopulation.new()
	if not population.configure_void(bindings,context) or actor_id<0 or actor_id>=population.maximum_void_actor_count():return reject("Unknown ordinary Void route owner")
	var data: Dictionary=bindings.opening_actors.get("npc_initialization",{}).get("routes",{})
	if not Definitions.parameters(data):return reject("Generated Void routes are unavailable in this pack")
	_configure_generated(bindings,actor_id,data)
	_identity.campaign_cursor=int(context.campaign_cursor)
	return true

func configure_contract_generated(bindings: RefCounted,actor_id: int,cursor:=13) -> bool:
	clear()
	if bindings==null or not Contracts.encounter_parameters(bindings.early_contracts):return reject("Contract routes require their source encounter declarations")
	# The early supported difficulty range creates at most four small ships.
	if actor_id<0 or actor_id>3 or not load("res://src/content/convoy_transit_definitions.gd").supports(bindings.mido_travel,cursor):return reject("Unknown early contract route owner")
	var data: Dictionary=bindings.opening_actors.get("npc_initialization",{}).get("routes",{})
	if not Definitions.parameters(data):return reject("Generated NPC routes are unavailable in this pack")
	_configure_generated(bindings,actor_id,data)
	_identity.campaign_cursor=cursor
	return true

func configure_convoy_generated(bindings: RefCounted,actor_id: int) -> bool:
	clear()
	if not Convoy.available(bindings):return reject("Convoy routes require their original population and factories")
	var actors: Array=bindings.mido_travel.convoy_capture.population.actors
	if actor_id<0 or actor_id>=actors.size() or int(actors[actor_id].subtype)!=0:return reject("This convoy actor has no generated patrol route")
	var data: Dictionary=bindings.opening_actors.get("npc_initialization",{}).get("routes",{})
	if not Definitions.parameters(data):return reject("Generated NPC routes are unavailable in this pack")
	_configure_generated(bindings,actor_id,data)
	_identity.campaign_cursor=int(bindings.mido_travel.convoy_capture.campaign_cursor)
	return true

func configure_alioth_generated(bindings: RefCounted,actor_id: int) -> bool:
	clear()
	if not Alioth.available(bindings):return reject("Alioth patrol routes require their original population")
	var actors: Array=bindings.mido_travel.alioth_attack.population.actors
	if actor_id<0 or actor_id>=actors.size() or int(actors[actor_id].subtype)!=0:return reject("This Alioth actor has no generated patrol")
	var data: Dictionary=bindings.opening_actors.get("npc_initialization",{}).get("routes",{})
	if not Definitions.parameters(data):return reject("Generated NPC routes are unavailable in this pack")
	_configure_generated(bindings,actor_id,data)
	_identity.campaign_cursor=int(bindings.mido_travel.alioth_attack.campaign_cursor)
	return true

func configure_kappa_generated(bindings: RefCounted,actor_id: int) -> bool:
	clear()
	if not Kappa.available(bindings) or actor_id<0 or actor_id>=int(bindings.mido_travel.kappa_rescue.population.actor_count):return reject("Unknown Kappa fighter route")
	var data: Dictionary=bindings.opening_actors.get("npc_initialization",{}).get("routes",{})
	if not Definitions.parameters(data):return reject("Generated fighter routes are unavailable")
	_configure_generated(bindings,actor_id,data)
	_identity.campaign_cursor=int(bindings.mido_travel.kappa_rescue.campaign_cursor)
	var population: Dictionary=bindings.mido_travel.kappa_rescue.population
	var point: Array=population.waypoints[int(population.actors[actor_id].waypoint_index)]
	_kappa_patrol={"point":Vector3(point[0],point[1],point[2]),"index":int(population.route_initial_index),"loop":bool(population.actor_route_loop)}
	return true

func replace_with_kappa_patrol() -> bool:
	error=""
	if _kappa_patrol.is_empty() or _points.is_empty() or _authored:return reject("Generate a Kappa fighter route before assigning its patrol")
	_points=[_kappa_patrol.point];_candidates=[]
	_index=_kappa_patrol.index;_loop=_kappa_patrol.loop;_authored=true
	return true

func configure_sahi_generated(bindings: RefCounted,actor_id: int,context: Dictionary) -> bool:
	clear()
	var post_rules=load("res://src/content/post_sahi_definitions.gd")
	var post: bool=bindings!=null and post_rules.selected(bindings.mido_travel,context)
	var dima: bool=bindings!=null and Dima.selected(bindings.mido_travel,context)
	if bindings==null or not (post or dima or Sahi.selected(bindings.mido_travel,context)):return reject("Story routes require their selected source encounter")
	var population: Dictionary=post_rules.population(bindings.mido_travel,context) if post else (Dima.population(bindings.mido_travel,context) if dima else bindings.mido_travel.sahi_encounter.population)
	if population.is_empty():return reject("Dima routes require the relocated portal position")
	if actor_id<0 or actor_id>=int(population.actor_count):return reject("Unknown Sahi route owner")
	var data: Dictionary=bindings.opening_actors.get("npc_initialization",{}).get("routes",{})
	if not Definitions.parameters(data):return reject("Generated Sahi routes are unavailable")
	_configure_generated(bindings,actor_id,data)
	_identity.campaign_cursor=int(context.campaign_cursor)
	if not post and not dima and population.actor_route_ids.any(func(value):return int(value)==actor_id):
		_sahi_patrol={"points":population.waypoints.map(func(point):return Vector3(point[0],point[1],point[2])),
			"index":int(population.route_initial_index),"loop":bool(population.actor_route_loop)}
	return true

func replace_with_sahi_patrol() -> bool:
	error=""
	if _sahi_patrol.is_empty() or _points.is_empty() or _authored:return reject("Generate a Sahi fighter route before assigning its authored patrol")
	_points=_sahi_patrol.points.duplicate();_candidates=[]
	_index=_sahi_patrol.index;_loop=_sahi_patrol.loop;_authored=true
	return true

func configure_kappa_player(bindings: RefCounted) -> bool:
	if not configure_kappa_generated(bindings,0):return false
	var data: Dictionary=bindings.mido_travel.kappa_rescue.population
	_points=data.waypoints.map(func(point):return Vector3(point[0],point[1],point[2]))
	_index=int(data.route_initial_index);_loop=bool(data.route_loop);_authored=true
	_identity.erase("actor_id");_identity.owner="player"
	return true

func replace_with_contract_path(points: Array) -> bool:
	error=""
	if _identity.get("campaign_cursor") not in [13,14] or _points.is_empty() or _authored or points.size()<3 or points.size()>4:return reject("Generate the rival route before replacing it with the mission path")
	if points.any(func(point):return not point is Vector3 or not point.is_finite()):return reject("The mission path contains an invalid waypoint")
	_points=points.duplicate();_candidates=[];_index=0;_loop=false;_authored=true
	return true

func replace_with_ambient_destination(point: Variant) -> bool:
	if _identity.is_empty() or _points.is_empty() or not point is Vector3 or not point.is_finite():return reject("Generate an ambient route before assigning its destination")
	_points=[point];_candidates=[];_index=0;_loop=false;_authored=true
	return true

func replace_with_alioth_escape(owner: RefCounted) -> bool:
	error=""
	if not owner is AliothSequence or _identity.get("campaign_cursor")!=16 or _points.is_empty() or _authored:return reject("Alioth escape requires its retained generated route")
	var sequence: Dictionary=owner.snapshot()
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if sequence.get(key)!=_identity[key]:return reject("Alioth escape route belongs to another encounter")
	if sequence.phase!=AliothSequence.Stage.ESCAPE_VIEW:return reject("No Alioth escape placement is pending")
	for row in sequence.frame.actor_overrides:
		if row.actor_id!=_identity.actor_id:continue
		if row.route_points.size()!=1 or not row.route_points[0] is Vector3 or not row.route_points[0].is_finite() or row.route_initial_index!=0 or row.route_loop:return reject("Unsupported Alioth escape waypoint")
		_points=row.route_points.duplicate();_candidates=[];_index=0;_loop=false;_authored=true
		return true
	return reject("Alioth escape does not replace this actor's route")

func restart_ambient_destination() -> bool:
	error=""
	if not _ambient_restart or not _authored or _loop or _points.size()!=1:return reject("Only the generated ambient destination can restart")
	_index=0
	return true

func restart_ambient_route() -> bool:
	error=""
	if not _ambient_restart or _points.is_empty() or (not _loop and (not _authored or _points.size()!=1)):return reject("Only a retained ambient route can restart")
	_index=0
	return true

func configure_training_authored(bindings: RefCounted) -> bool:
	if not configure_training_generated(bindings,3):return false
	var data: Dictionary=bindings.combat_training
	_points=data.waypoints.map(func(point):return Vector3(point[0],point[1],point[2]))
	_index=int(data.authored_route_initial_index);_loop=bool(data.authored_route_loop);_authored=true
	return true

func configure_training_player(bindings: RefCounted) -> bool:
	if not configure_training_authored(bindings):return false
	# The world gives the player the original route. Gunant owns a separate copy;
	# neither actor's arrival advances the other's waypoint index.
	_identity.erase("actor_id")
	_identity.owner="player"
	return true

func generate(random_state: Variant) -> Dictionary:
	error=""
	if _identity.is_empty() or not _points.is_empty(): return fail("Configure a fresh NPC route before generating it once")
	var random := Random.new()
	if not random.restore(random_state): return fail(random.error)
	var candidates := []
	for origin in _definition.candidate_origins:
		var point := Vector3.ZERO
		for axis in 3: point[axis]=int(origin[axis])+random.next_int(int(_definition.coordinate_bounds[axis]))
		candidates.append(point)
	var count: int = int(_definition.count_minimum)+random.next_int(int(_definition.count_bound))
	var selected := []
	var points := []
	# Retry duplicate choices. Shuffling would consume a different random stream.
	while selected.size()<count:
		var choice := random.next_int(int(_definition.candidate_bound))
		if choice in selected: continue
		selected.append(choice)
		points.append(candidates[choice])
	_points=points;_candidates=selected
	return {"route":snapshot(),"random_state":random.snapshot()}

func advance(position: Variant) -> Dictionary:
	error=""
	if _points.is_empty(): return fail("Generate the NPC route before advancing it")
	if not position is Vector3 or not position.is_finite(): return fail("NPC route requires a finite source position")
	if _index==_points.size():return _arrival_result(false,false)
	var separation := Vectors.added(position,-_points[_index])
	if not separation.is_finite(): return fail("NPC route separation exceeds source precision")
	var extent := float(_definition.arrival_half_extent)
	var reached := absf(separation.x)<extent and absf(separation.y)<extent and absf(separation.z)<extent
	var previous := _index
	# One arrival per pass, including zero-time actor passes. A plain authored
	# route exhausts its index; only a looping patrol selects the first point.
	if reached:
		_index+=1
		if _loop:_index%=_points.size()
	return _arrival_result(reached,_loop and reached and previous==_points.size()-1)

func _arrival_result(arrived: bool, wrapped: bool) -> Dictionary:
	var result:=_identity.duplicate()
	result.merge({"target":null if _index==_points.size() else _points[_index],"index":_index,"arrived":arrived,"wrapped":wrapped})
	if _authored:result.completed=_index==_points.size()
	return result

func snapshot() -> Dictionary:
	if _identity.is_empty(): return {}
	var result := _identity.duplicate()
	result.merge({"waypoints":_points.duplicate(),"candidate_indices":_candidates.duplicate(),"index":_index,"loop":_loop})
	if _authored:result.completed=_index==_points.size()
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._identity=_identity.duplicate();copy._definition=_definition.duplicate(true)
	copy._points=_points.duplicate();copy._candidates=_candidates.duplicate();copy._index=_index
	copy._loop=_loop;copy._authored=_authored
	copy._ambient_restart=_ambient_restart
	copy._kappa_patrol=_kappa_patrol.duplicate(true);copy._sahi_patrol=_sahi_patrol.duplicate(true)
	return copy

func clear() -> void:
	error="";_identity={};_definition={};_points=[];_candidates=[];_index=0;_loop=true;_authored=false;_ambient_restart=false;_kappa_patrol={};_sahi_patrol={}

func reject(message: String) -> bool:
	error=message
	return false

func fail(message: String) -> Dictionary:
	reject(message)
	return {}
