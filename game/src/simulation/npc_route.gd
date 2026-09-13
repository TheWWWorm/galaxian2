extends RefCounted
## Native generated coordinate patrol. The caller supplies the shared RNG at the
## source constructor's route-draw boundary, before any actor updates.
const Definitions = preload("res://src/content/npc_route_definitions.gd")
const OpeningContext = preload("res://src/content/opening_sky_definitions.gd")
const ArrivalConstruction = preload("res://src/content/arrival_actor_construction_definitions.gd")
const FullHold = preload("res://src/content/full_hold_flight_definitions.gd")
const Training = preload("res://src/content/combat_training_definitions.gd")
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

func configure_training_authored(bindings: RefCounted) -> bool:
	if not configure_training_generated(bindings,3):return false
	var data: Dictionary=bindings.combat_training
	_points=data.waypoints.map(func(point):return Vector3(point[0],point[1],point[2]))
	_index=int(data.authored_route_initial_index);_loop=bool(data.authored_route_loop);_authored=true
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
	return copy

func clear() -> void:
	error="";_identity={};_definition={};_points=[];_candidates=[];_index=0;_loop=true;_authored=false

func reject(message: String) -> bool:
	error=message
	return false

func fail(message: String) -> Dictionary:
	reject(message)
	return {}
