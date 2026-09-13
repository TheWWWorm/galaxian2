extends RefCounted
## Shared supported factory records from the RNG before the first NPC.
## Rescue and Gunant replace generated routes; ordinary pirates keep theirs.
## Live combat and target decisions have separate owners.
const Definitions = preload("res://src/content/npc_construction_definitions.gd")
const ArrivalDefinitions = preload("res://src/content/arrival_actor_construction_definitions.gd")
const FullHold = preload("res://src/content/full_hold_flight_definitions.gd")
const Training = preload("res://src/content/combat_training_definitions.gd")
const Equipment = preload("res://src/simulation/station_equipment.gd")
const ArrivalStaging = preload("res://src/content/arrival_staging_definitions.gd")
const ArrivalLocation = preload("res://src/simulation/arrival_location.gd")
const Poses = preload("res://src/simulation/opening_staging.gd")
const Route = preload("res://src/simulation/npc_route.gd")
const Random = preload("res://src/simulation/seeded_random.gd")
const Loadout = preload("res://src/simulation/opening_loadout.gd")
const Vitals = preload("res://src/simulation/combat_vitals.gd")
var error := ""
var _identity := {}
var _definition := {}
var _items := []
var _routes := []
var _actors := []
var _random_state := {}
var _arrival := {}
var _full_hold := {}
var _training := {}
var _authored_route: RefCounted

func configure(bindings: RefCounted, catalogues: RefCounted) -> bool:
	clear()
	if bindings==null or catalogues==null: return reject("NPC construction requires content and bindings")
	var loadout := Loadout.new()
	if not loadout.configure(bindings,catalogues,bindings.base_content_id): return reject(loadout.error)
	var seed: Dictionary = loadout.snapshot()
	return _configure(bindings,catalogues,seed,{})

func configure_arrival(bindings: RefCounted, catalogues: RefCounted, cache: Variant) -> bool:
	clear()
	if bindings==null or not ArrivalDefinitions.parameters(bindings.arrival_actor_construction):
		return reject("Rescue actor construction is unavailable; prepare current resource bindings")
	if not ArrivalStaging.parameters(bindings.arrival_staging):return reject("Prepare current resource bindings for corrected rescue visibility")
	var location:=ArrivalLocation.new()
	var context:=location.resolve(bindings,catalogues,cache)
	if context.is_empty():return reject(location.error)
	if bindings.resolve_ship_model(int(bindings.arrival_actor_construction.hull_catalogue_id)).is_empty():return reject(bindings.error)
	return _configure(bindings,catalogues,context,bindings.arrival_actor_construction)

func configure_full_hold(bindings: RefCounted, catalogues: RefCounted, cache: Variant) -> bool:
	clear()
	if bindings==null or not FullHold.parameters(bindings.full_hold_flight):return reject("Second-flight NPC construction is unavailable")
	var location:=ArrivalLocation.new()
	var context:=location.resolve_departure(bindings,catalogues,cache)
	if context.is_empty():return reject(location.error)
	if context.campaign_cursor!=int(bindings.full_hold_flight.campaign_cursor):return reject("Second-flight NPC requires its own departure cache")
	if bindings.resolve_ship_model(int(bindings.full_hold_flight.hull_catalogue_id)).is_empty():return reject(bindings.error)
	return _configure(bindings,catalogues,context,{},bindings.full_hold_flight)

func configure_combat_training(bindings: RefCounted, catalogues: RefCounted, equipment: RefCounted, player_position: Variant) -> bool:
	clear()
	if bindings==null or catalogues==null or not Training.parameters(bindings.combat_training):return reject("Combat-training construction is unavailable")
	if not equipment is Equipment or not equipment.requirements().satisfied:return reject("Combat training requires owned and installed tutorial equipment")
	var seed: Dictionary=equipment.snapshot().loadout
	if seed.base_content_id!=bindings.base_content_id or seed.binding_id!=bindings.binding_id or catalogues.content_id!=bindings.base_content_id:return reject("Combat-training equipment belongs to another content identity")
	if not player_position is Vector3 or not player_position.is_finite():return reject("Combat training requires a finite source player position")
	var position:=Vector3.ZERO
	for axis in 3:position[axis]=Vitals.single(Vitals.single(player_position[axis])+float(bindings.combat_training.companion_position_offset[axis]))
	if not position.is_finite():return reject("Companion placement exceeds source precision")
	for id in [bindings.combat_training.pirate_hull_catalogue_id,bindings.combat_training.companion_hull_catalogue_id]:
		if bindings.resolve_ship_model(int(id)).is_empty():return reject(bindings.error)
	var route:=Route.new()
	if not route.configure_training_authored(bindings):return reject(route.error)
	if not _configure(bindings,catalogues,seed,{},{},bindings.combat_training):return false
	_training.companion_position=position;_authored_route=route
	return true

func _configure(bindings: RefCounted, catalogues: RefCounted, seed: Dictionary, arrival: Dictionary, full_hold: Dictionary={}, training: Dictionary={}) -> bool:
	var data: Variant = bindings.opening_actors.get("npc_initialization",{}).get("construction",{})
	if not Definitions.parameters(data): return reject("NPC construction is unavailable in this pack")
	if bindings.resolve(int(data.fragment_resource),"mesh").is_empty(): return reject(bindings.error)
	var expected_ship:=10 if full_hold.is_empty() else 0
	var expected_equipment: Array=[2,2,36,54,59,82,73] if full_hold.is_empty() else [90,81]
	if (training.is_empty() and (seed.ship_id!=expected_ship or seed.equipment_ids!=expected_equipment)) or (not training.is_empty() and seed.ship_id!=0) or seed.station_id!=78:
		return reject("NPC construction requires its supported retained loadout")
	var items: Variant = catalogues.tables.get("items")
	if not items is Array or items.size()!=233: return reject("Unsupported NPC cargo catalogue")
	var staged := []
	for id in items.size():
		if not items[id] is Dictionary or items[id].get("id")!=id: return reject("Invalid NPC cargo catalogue row")
		var arrays: Variant = items[id].get("arrays")
		if not arrays is Array or arrays.size()!=3 or not (arrays[0] is Array or arrays[0] is PackedInt32Array) or not (arrays[2] is Array or arrays[2] is PackedInt32Array):
			return reject("Missing NPC cargo properties")
		var p: Variant = arrays[2]
		if p.size()<=int(data.price_high_index): return reject("Incomplete NPC cargo properties")
		for index in [data.category_index,data.rank_index,data.chance_index,data.price_low_index,data.price_high_index,5]:
			var value: Variant = p[int(index)]
			if not value is int or value<-2147483648 or value>2147483647: return reject("Invalid NPC cargo property")
		var category: int = p[int(data.category_index)]
		if category<0 or category>=data.category_weights.size(): return reject("Unknown NPC cargo category")
		# Widen before subtraction, then reject values outside the recovered signed domain.
		var low: int=p[int(data.price_low_index)];var delta: int=p[int(data.price_high_index)]-low
		if delta<-2147483648 or delta>2147483647: return reject("NPC cargo price range overflows its source field")
		@warning_ignore("integer_division")
		var average: int=low+delta/2
		if average<-2147483648 or average>2147483647: return reject("NPC cargo average price overflows its source field")
		staged.append({"category":category,"restricted":not arrays[0].is_empty(),"rank":p[int(data.rank_index)],"chance":p[int(data.chance_index)],"price":average,"type":p[5]})
	# The source special-drop predicate depends on ship identity or equipment type 18.
	# Neither applies to this exact fresh loadout; arbitrary loadouts are unsupported.
	if data.special_ship_ids.any(func(value): return int(value)==int(seed.ship_id)): return reject("Special cargo override is outside fresh opening construction")
	for id in seed.equipment_ids:
		if staged[id].type==int(data.special_equipment_type): return reject("Special cargo override is outside fresh opening construction")
	var routes := []
	for id in (int(training.actor_count) if not training.is_empty() else (3 if arrival.is_empty() and full_hold.is_empty() else 1)):
		var route := Route.new()
		var ready: bool
		if not training.is_empty():ready=route.configure_training_generated(bindings,id)
		elif not full_hold.is_empty():ready=route.configure_full_hold_generated(bindings)
		elif not arrival.is_empty():ready=route.configure_arrival_generated(bindings)
		else:ready=route.configure(bindings,id)
		if not ready: return reject(route.error)
		routes.append(route)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	if not training.is_empty():
		_identity.campaign_cursor=int(training.campaign_cursor)
		_training=training.duplicate(true)
	if not full_hold.is_empty():
		_identity.campaign_cursor=int(full_hold.campaign_cursor)
		_full_hold=full_hold.duplicate(true)
	if not arrival.is_empty():
		_identity.campaign_cursor=int(arrival.campaign_cursor)
		_arrival=arrival.duplicate(true)
		_arrival.position=Poses.vec(bindings.arrival_staging.actor_initial_position)
		_arrival.waypoints=bindings.arrival_staging.actor_route_points.map(func(point):return Poses.vec(point))
		_arrival.model_draw_enabled=bool(bindings.arrival_staging.actor_model_draw_enabled)
		_arrival.engine_draw_enabled=bool(bindings.arrival_staging.actor_engine_draw_enabled)
		_arrival.engine_resource_id=int(bindings.arrival_staging.actor_engine_resource_id)
	_definition=data.duplicate(true)
	# JSON number arrays are floats; Array membership is type-sensitive.
	_definition.excluded_items=data.excluded_items.map(func(value): return int(value))
	_items=staged;_routes=routes
	return true

func generate(random_state: Variant) -> Dictionary:
	error=""
	if _identity.is_empty() or not _actors.is_empty(): return fail("Configure fresh NPC construction before generating once")
	var random := Random.new()
	if not random.restore(random_state): return fail(random.error)
	var actors := [];var routes := []
	for id in _routes.size():
		var position := Vector3.ZERO
		var origin:=Vector3.ZERO
		if not _training.is_empty() and id<int(_training.pirate_count):origin=Poses.vec(_training.waypoints[int(_training.pirate_waypoint_index)])
		for axis in 3: position[axis]=origin[axis]+int(_definition.spawn_origin[axis])+random.next_int(int(_definition.spawn_bound))
		var route: RefCounted = _routes[id].fork_for_frame()
		var generated: Dictionary = route.generate(random.snapshot())
		if generated.is_empty(): return fail(route.error)
		if not random.restore(generated.random_state): return fail(random.error)
		var cargo := _sample_cargo(random)
		var fragments := []
		var count: int = int(_definition.fragment_count_minimum)+random.next_int(int(_definition.fragment_count_bound))
		for fragment in count:
			var rotation := Vector3.ZERO
			for axis in 3:
				rotation[axis]=Vitals.single(Vitals.single(float(random.next_int(int(_definition.rotation_bound)))/float(_definition.rotation_divisor))*float(_definition.rotation_multiplier))
			var scale_value: float=Vitals.single(float(int(_definition.scale_minimum)+random.next_int(int(_definition.scale_bound)))/float(_definition.scale_divisor))
			fragments.append({"rotation_radians":rotation,"scale":scale_value,"resource_id":int(_definition.fragment_resource)})
		var actor: Dictionary={"actor_id":id,"factory_position":position,"discarded_cargo":cargo,"cargo":[],"fragments":fragments,"route":route.snapshot()}
		if not _arrival.is_empty():
			var body:=Transform3D(Basis.IDENTITY,_arrival.position)
			var authored_route:=_identity.duplicate()
			authored_route.merge({"actor_id":id,"waypoints":_arrival.waypoints.duplicate(),"index":int(_arrival.authored_route_initial_index),"loop":bool(_arrival.authored_route_loop)})
			actor.merge({"actor_kind":int(_arrival.actor_kind),"hull_catalogue_id":int(_arrival.hull_catalogue_id),"subtype":int(_arrival.subtype),
				"discarded_cargo":[],"cargo":cargo,"discarded_route":actor.route,"route":authored_route,
				"body_pose":body,"statistics_pose":body,"model_local_pose":Transform3D.IDENTITY,"model_draw_enabled":_arrival.model_draw_enabled,
				"engine_draw_enabled":_arrival.engine_draw_enabled,"engine_resource_id":_arrival.engine_resource_id},true)
		elif not _full_hold.is_empty():
			var body:=Transform3D(Basis.IDENTITY,Poses.vec(_full_hold.actor_position))
			actor.merge({"actor_kind":int(_full_hold.actor_kind),"hull_catalogue_id":int(_full_hold.hull_catalogue_id),"subtype":int(_full_hold.subtype),
				"discarded_cargo":[],"cargo":cargo,"body_pose":body,"statistics_pose":body,"model_local_pose":Transform3D.IDENTITY,
				"mode":int(_full_hold.actor_mode),"active":bool(_full_hold.actor_active),"targeting_blocked":bool(_full_hold.actor_targeting_blocked)},true)
		elif not _training.is_empty():
			var companion: bool=id==int(_training.companion_actor_id)
			var body:=Transform3D(Basis.IDENTITY,_training.companion_position if companion else position)
			actor.merge({"actor_kind":int(_training.companion_actor_kind if companion else _training.pirate_actor_kind),
				"hull_catalogue_id":int(_training.companion_hull_catalogue_id if companion else _training.pirate_hull_catalogue_id),
				"subtype":int(_training.subtype),"discarded_cargo":[],"cargo":cargo,
				"body_pose":body,"statistics_pose":body,"model_local_pose":Transform3D.IDENTITY},true)
			if companion:
				actor.discarded_route=actor.route
				route=_authored_route.fork_for_frame();actor.route=route.snapshot()
				actor.friendly=bool(_training.companion_friendly)
				actor.current_hull_override=int(_training.companion_current_hull_override)
				actor.name_text_id=int(_training.companion_name_text_id)
			else:
				actor.mode=int(_training.pirate_mode);actor.active=bool(_training.pirate_active);actor.targeting_blocked=bool(_training.pirate_targeting_blocked)
		actors.append(actor)
		routes.append(route)
	_actors=actors;_routes=routes;_random_state=random.snapshot()
	return snapshot()

func _sample_cargo(random: RefCounted) -> Array:
	var count: int=random.next_int(int(_definition.cargo_count_bound))
	if count==0:
		if random.next_int(int(_definition.cargo_count_bound))==0: return []
		count=1
	var cargo := []
	for slot in count:
		var selected := -1
		for attempt in int(_definition.cargo_attempts):
			var id: int=random.next_int(_items.size())
			var item: Dictionary=_items[id]
			if item.restricted: continue
			if random.next_int(int(_definition.chance_bound))>=int(_definition.category_weights[item.category]): continue
			if random.next_int(int(_definition.chance_bound))>=item.chance: continue
			if item.price<=0 or id in _definition.excluded_items: continue
			if item.category!=int(_definition.commodity_category) and item.rank>int(_definition.maximum_rank): continue
			selected=id
			break
		var quantity_bound: int=int(_definition.quantity_bound)
		if selected<0:
			selected=int(_definition.fallback_item_minimum)+random.next_int(int(_definition.fallback_item_bound))
			quantity_bound=int(_definition.commodity_quantity_bound)
		elif _items[selected].category==int(_definition.commodity_category):
			quantity_bound=int(_definition.commodity_quantity_bound)
		cargo.append({"item_id":selected,"quantity":int(_definition.quantity_minimum)+random.next_int(quantity_bound)})
	return cargo

func route(actor_id: int) -> RefCounted:
	if not _arrival.is_empty():
		reject("The rescue replaces its generated route; use its authored construction record")
		return null
	if _actors.is_empty() or actor_id<0 or actor_id>=_routes.size():
		reject("Generate opening NPC construction before requesting a route")
		return null
	return _routes[actor_id].fork_for_frame()

func arrival_motion_construction() -> Dictionary:
	error=""
	if _arrival.is_empty() or _actors.size()!=1:return fail("Generate rescue construction before requesting its motion poses")
	var result:=_identity.duplicate()
	for key in ["actor_id","body_pose","statistics_pose","model_local_pose"]:result[key]=_actors[0][key]
	return result

func snapshot() -> Dictionary:
	if _identity.is_empty(): return {}
	var value := _identity.duplicate()
	value.merge({"actors":_actors.duplicate(true),"random_state":_random_state.duplicate()})
	return value

func clear() -> void:
	error="";_identity={};_definition={};_items=[];_routes=[];_actors=[];_random_state={};_arrival={};_full_hold={};_training={};_authored_route=null

func reject(message: String) -> bool:
	error=message
	return false

func fail(message: String) -> Dictionary:
	reject(message)
	return {}
