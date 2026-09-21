extends RefCounted
const Travel=preload("res://src/content/mido_travel_definitions.gd")
## Owns scenery for supported Opening/rescue worlds. The caller provides Unix
## seconds separately from the monotonic frame clock; count RNG is never reused.
const Detail = preload("res://src/presentation/scenery_detail_group.gd")
const Motion = preload("res://src/simulation/scenery_motion.gd")
const Field = preload("res://src/simulation/scenery_field.gd")
const Loadout = preload("res://src/simulation/opening_loadout.gd")
const Generator = preload("res://src/simulation/seeded_random.gd")
const Opening = preload("res://src/content/opening_sky_definitions.gd")
const Bodies = preload("res://src/simulation/scenery_bodies.gd")
const Destruction = preload("res://src/simulation/scenery_destruction.gd")
const EffectResources = preload("res://src/content/scenery_effect_resources.gd")
const WorldInitialization = preload("res://src/simulation/opening_world_initialization.gd")
const ArrivalLocation = preload("res://src/simulation/arrival_location.gd")
const Population = preload("res://src/simulation/scenery_population.gd")
const Primaries = preload("res://src/simulation/primary_weapons.gd")
const Combat=preload("res://src/simulation/opening_combat_group.gd")
var error := ""
var _motion: RefCounted
var _detail: RefCounted
var _bodies: RefCounted
var _seed_seconds := 0
var _destruction: Array = []
var _random_state := {}
var _remaining_count := 0
var _destroyed_count := 0
var _mined_count := 0
var _events: Array = []
var _presentation_identity: RefCounted
var _world_initialization: RefCounted
var _initialization_open := false
var _escape_available:=false
var _escape_relocated:=false
var _arrival_cache:={}
var _arrival_conditions:={}
var _arrival_population:={}
var _departure_cache:={}
var _departure_conditions:={}
var _departure_population:={}
var _spin_disabled:={}
var _read_snapshot:={}
var _initialization_snapshot:={}

func configure(bindings: RefCounted, catalogues: RefCounted, unix_seconds: Variant, large_display := true, body_resources: RefCounted = null, effect_resources: RefCounted = null) -> bool:
	clear()
	if bindings==null or catalogues==null or not Opening.parameters(bindings.opening_sky):
		return reject("Opening scenery requires the verified fresh opening context")
	var loadout := Loadout.new()
	if not loadout.configure(bindings,catalogues,bindings.base_content_id):return reject(loadout.error)
	var source := loadout.snapshot()
	# Fresh cursor zero, ordinary world type three, no active mission override.
	# The source zeroes all three center coordinates in precisely this context.
	if not _configure_field(bindings,catalogues,unix_seconds,source.station_id,0,Vector3.ZERO,large_display,body_resources,effect_resources):return false
	_escape_available=not bindings.opening_staging.get("escape_camera",{}).is_empty()
	return true

func configure_arrival(bindings: RefCounted, catalogues: RefCounted, cache: Variant, entry_conditions: Variant, unix_seconds: Variant, large_display:=true, body_resources: RefCounted=null, effect_resources: RefCounted=null) -> bool:
	clear()
	var location:=ArrivalLocation.new()
	var context:=location.resolve(bindings,catalogues,cache)
	if context.is_empty():return reject(location.error)
	var world:=WorldInitialization.new()
	if not world.configure_arrival(bindings,catalogues,cache,entry_conditions):return reject(world.error)
	var population:=Population.new()
	if not population.configure(bindings):return reject(population.error)
	var selected:=population.for_arrival(context.station_id,entry_conditions)
	if selected.is_empty():return reject(population.error)
	if not _configure_field(bindings,catalogues,unix_seconds,context.station_id,context.campaign_cursor,selected.center,large_display,body_resources,effect_resources):return false
	_arrival_cache=cache.duplicate(true);_arrival_conditions=entry_conditions.duplicate(true)
	_arrival_population=selected
	return true

func configure_departure(bindings: RefCounted, catalogues: RefCounted, cache: Variant, entry_conditions: Variant, unix_seconds: Variant, large_display:=true, body_resources: RefCounted=null, effect_resources: RefCounted=null) -> bool:
	clear()
	var location:=ArrivalLocation.new()
	var context:=location.resolve_departure(bindings,catalogues,cache)
	if context.is_empty():return reject(location.error)
	var world:=WorldInitialization.new()
	if not world.configure_departure(bindings,catalogues,cache,entry_conditions):return reject(world.error)
	var population:=Population.new()
	if not population.configure(bindings):return reject(population.error)
	var selected:=population.for_departure(context.station_id,entry_conditions,context.campaign_cursor)
	if selected.is_empty():return reject(population.error)
	if not _configure_field(bindings,catalogues,unix_seconds,context.station_id,context.campaign_cursor,selected.center,large_display,body_resources,effect_resources):return false
	_departure_cache=cache.duplicate(true);_departure_conditions=entry_conditions.duplicate(true);_departure_population=selected
	return true

func _configure_field(bindings: RefCounted, catalogues: RefCounted, unix_seconds: Variant, station_id: int, campaign_cursor: int, center: Vector3, large_display: bool, body_resources: RefCounted, effect_resources: RefCounted) -> bool:
	_read_snapshot={}
	if not unix_seconds is int or unix_seconds<0 or unix_seconds>2147483647:
		return reject("Scenery requires explicit supported Unix seconds")
	var field:=Field.new()
	# These supported early trips cannot enter the later special-ore override.
	if not field.configure(bindings,catalogues,station_id,false,false,campaign_cursor):return reject(field.error)
	var random := Generator.new()
	random.seed_from(unix_seconds)
	var generated := field.generate(center,random.snapshot())
	if generated.is_empty():return reject(field.error)
	var motion := Motion.new()
	if not motion.configure(bindings,generated):return reject(motion.error)
	var detail := Detail.new()
	if not detail.configure(bindings,generated,large_display) or not detail.refresh(Vector3.ZERO,1.0):return reject(detail.error)
	var bodies: RefCounted
	if body_resources!=null:
		bodies=Bodies.new()
		if not bodies.configure(bindings,generated,body_resources):return reject(bodies.error)
	var destruction := []
	if effect_resources!=null:
		if bodies==null or effect_resources.get_script()!=EffectResources:return reject("Scenery lifecycle requires native bodies and effect resources")
		var body_state: Dictionary=bodies.snapshot()
		for row in generated.objects:
			var descriptor: Dictionary=effect_resources.effect_for_model(row.model_id)
			var actor := Destruction.new()
			if not actor.configure(bindings,catalogues,body_state,row.index,descriptor):return reject(actor.error)
			destruction.append(actor)
	_motion=motion;_detail=detail;_seed_seconds=unix_seconds
	_bodies=bodies
	_destruction=destruction;_random_state=generated.random_state.duplicate(true)
	_remaining_count=generated.objects.size()
	_presentation_identity=RefCounted.new()
	_initialization_open=true
	return true

func configure_combat_training(bindings: RefCounted, catalogues: RefCounted, equipment: RefCounted, player_position: Vector3, entry_conditions: Dictionary, unix_seconds: Variant, large_display:=true, body_resources: RefCounted=null, effect_resources: RefCounted=null) -> bool:
	clear()
	var world:=WorldInitialization.new()
	if not world.configure_combat_training(bindings,catalogues,equipment,player_position,entry_conditions):return reject(world.error)
	var population:=Population.new()
	if not population.configure(bindings):return reject(population.error)
	var selected:=population.for_departure(int(bindings.combat_training.station_id),entry_conditions,7)
	if selected.is_empty():return reject(population.error)
	if not _configure_field(bindings,catalogues,unix_seconds,selected.station_id,7,selected.center,large_display,body_resources,effect_resources):return false
	if not _finish_world_initialization(world):
		var message:=error;clear();return reject(message)
	_departure_population=selected
	return true

func configure_local_arrival(bindings: RefCounted, catalogues: RefCounted, equipment: RefCounted, player_cache: Dictionary, entry_conditions: Dictionary, unix_seconds: Variant, large_display:=true, body_resources: RefCounted=null, effect_resources: RefCounted=null) -> bool:
	if bindings==null or not player_cache.get("campaign_cursor") is int:return reject("Local arrival requires its current player cache")
	var trip:=Travel.journey(bindings.mido_travel,player_cache.campaign_cursor)
	if trip.is_empty():return reject("Unsupported local scenery arrival")
	return _configure_local(bindings,catalogues,equipment,player_cache,entry_conditions,unix_seconds,int(trip.station_id),large_display,body_resources,effect_resources,0.5,player_cache.campaign_cursor)

func configure_local_departure(bindings: RefCounted, catalogues: RefCounted, equipment: RefCounted, player_cache: Dictionary, entry_conditions: Dictionary, unix_seconds: Variant, large_display:=true, body_resources: RefCounted=null, effect_resources: RefCounted=null, difficulty:=0.5, cursor: int=10) -> bool:
	if bindings==null:return reject("Local scenery requires content definitions")
	var trip:=Travel.journey(bindings.mido_travel,cursor)
	if trip.is_empty():return reject("Unsupported local scenery departure")
	return _configure_local(bindings,catalogues,equipment,player_cache,entry_conditions,unix_seconds,int(trip.from_station_id),large_display,body_resources,effect_resources,difficulty,cursor)

func _configure_local(bindings: RefCounted, catalogues: RefCounted, equipment: RefCounted, player_cache: Dictionary, entry_conditions: Dictionary, unix_seconds: Variant, station_id: int, large_display: bool, body_resources: RefCounted, effect_resources: RefCounted, difficulty: float, cursor: int=10) -> bool:
	clear()
	var location:=ArrivalLocation.new()
	var context:=location.resolve_local_travel(bindings,catalogues,equipment,player_cache)
	if context.is_empty():return reject(location.error)
	if int(context.station_id)!=station_id or context.campaign_cursor!=cursor:return reject("Local scenery requires its own departure or arrival location")
	var world:=WorldInitialization.new()
	var departure:=station_id==int(Travel.journey(bindings.mido_travel,cursor).from_station_id)
	var ready:=world.configure_local_traffic(bindings,catalogues,equipment,unix_seconds,entry_conditions,difficulty,cursor) if departure else world.configure_local_arrival(bindings,catalogues,equipment,player_cache,entry_conditions)
	if not ready:return reject(world.error)
	var population:=Population.new()
	if not population.configure(bindings):return reject(population.error)
	var selected:=population.for_departure(int(context.station_id),entry_conditions,cursor)
	if selected.is_empty():return reject(population.error)
	if not _configure_field(bindings,catalogues,unix_seconds,selected.station_id,cursor,selected.center,large_display,body_resources,effect_resources):return false
	if not _finish_world_initialization(world):
		var message:=error;clear();return reject(message)
	_departure_population=selected
	return true

func configure_contract(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,contracts: RefCounted,player_cache: Dictionary,player_position: Vector3,entry_conditions: Dictionary,unix_seconds: Variant,large_display:=true,body_resources: RefCounted=null,effect_resources: RefCounted=null) -> bool:
	clear()
	var location:=ArrivalLocation.new()
	var context:=location.resolve_local_travel(bindings,catalogues,equipment,player_cache)
	if context.is_empty():return reject(location.error)
	var population:=Population.new()
	if not population.configure(bindings):return reject(population.error)
	var selected:=population.for_departure(int(context.station_id),entry_conditions,int(context.campaign_cursor))
	if selected.is_empty():return reject(population.error)
	var world:=WorldInitialization.new()
	if not world.configure_contract(bindings,catalogues,equipment,contracts,player_cache,entry_conditions,unix_seconds,player_position,selected.center):return reject(world.error)
	if not _configure_field(bindings,catalogues,unix_seconds,selected.station_id,int(context.campaign_cursor),selected.center,large_display,body_resources,effect_resources):return false
	if not _finish_world_initialization(world):
		var message:=error;clear();return reject(message)
	_departure_population=selected
	return true

func configure_convoy(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,context: Dictionary,entry_conditions: Dictionary,unix_seconds: Variant,large_display:=true,body_resources: RefCounted=null,effect_resources: RefCounted=null) -> bool:
	clear()
	var world:=WorldInitialization.new()
	if not world.configure_convoy(bindings,catalogues,equipment,context,entry_conditions):return reject(world.error)
	var population:=Population.new()
	if not population.configure(bindings):return reject(population.error)
	var selected:=population.for_departure(int(context.station_id),entry_conditions,int(context.campaign_cursor))
	if selected.is_empty():return reject(population.error)
	if not _configure_field(bindings,catalogues,unix_seconds,selected.station_id,context.campaign_cursor,selected.center,large_display,body_resources,effect_resources):return false
	if not _finish_world_initialization(world):
		var message:=error;clear();return reject(message)
	_departure_population=selected
	return true

func configure_alioth(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,context: Dictionary,player_position: Vector3,entry_conditions: Dictionary,unix_seconds: Variant,large_display:=true,body_resources: RefCounted=null,effect_resources: RefCounted=null) -> bool:
	clear()
	var world:=WorldInitialization.new()
	if not world.configure_alioth_attack(bindings,catalogues,equipment.snapshot().loadout,context,player_position,entry_conditions):return reject(world.error)
	var population:=Population.new()
	if not population.configure(bindings):return reject(population.error)
	var selected:=population.for_departure(int(context.station_id),entry_conditions,int(context.campaign_cursor))
	if selected.is_empty():return reject(population.error)
	if not _configure_field(bindings,catalogues,unix_seconds,selected.station_id,context.campaign_cursor,selected.center,large_display,body_resources,effect_resources):return false
	if not _finish_world_initialization(world):
		var message:=error;clear();return reject(message)
	_departure_population=selected
	return true

func configure_free(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,context: Dictionary,entry_conditions: Dictionary,unix_seconds: Variant,large_display:=true,body_resources: RefCounted=null,effect_resources: RefCounted=null) -> bool:
	clear()
	if not load("res://src/content/free_flight_definitions.gd").available(bindings) or not is_instance_of(equipment,load("res://src/simulation/station_equipment.gd")):return reject("Ordinary scenery requires its verified equipped entry")
	var world:=WorldInitialization.new()
	if not world.configure_free_traffic(bindings,catalogues,equipment,context,unix_seconds,entry_conditions):return reject(world.error)
	var population:=Population.new()
	if not population.configure(bindings):return reject(population.error)
	var selected:=population.for_departure(int(context.station_id),entry_conditions,int(context.campaign_cursor))
	if selected.is_empty():return reject(population.error)
	if not _configure_field(bindings,catalogues,unix_seconds,selected.station_id,context.campaign_cursor,selected.center,large_display,body_resources,effect_resources):return false
	if not _finish_world_initialization(world):
		var message:=error;clear();return reject(message)
	_departure_population=selected
	return true

func complete_world_initialization(bindings: RefCounted, catalogues: RefCounted) -> bool:
	error=""
	if not _initialization_open or _motion==null or _world_initialization!=null:
		return reject("Complete world initialization once, before the first scenery update")
	var field: Dictionary=_motion.snapshot()
	if bindings==null or field.base_content_id!=bindings.base_content_id or field.binding_id!=bindings.binding_id:
		return reject("World initialization belongs to another scenery population")
	var owner := WorldInitialization.new()
	var ready: bool
	if not _departure_cache.is_empty():ready=owner.configure_departure(bindings,catalogues,_departure_cache,_departure_conditions)
	elif not _arrival_cache.is_empty():ready=owner.configure_arrival(bindings,catalogues,_arrival_cache,_arrival_conditions)
	else:ready=owner.configure(bindings,catalogues)
	if not ready:return reject(owner.error)
	return _finish_world_initialization(owner)

func _finish_world_initialization(owner: RefCounted) -> bool:
	_read_snapshot={}
	var result: Dictionary=owner.generate(_random_state)
	if result.is_empty(): return reject(owner.error)
	_world_initialization=owner;_random_state=result.random_state.duplicate(true)
	_initialization_snapshot=preload("res://src/simulation/readonly_state.gd").freeze(owner.snapshot())
	_initialization_open=false
	return true

func world_initialization_owner() -> RefCounted:
	return null if _world_initialization==null else _world_initialization.fork_for_frame()

func initial_npc_route(actor_id: int) -> RefCounted:
	error=""
	if _world_initialization==null:
		reject("Opening world initialization is unavailable")
		return null
	var route: RefCounted=_world_initialization.route(actor_id)
	if route==null: reject(_world_initialization.error)
	return route

func arrival_motion_construction() -> Dictionary:
	error=""
	if _world_initialization==null:
		reject("Complete rescue world initialization before requesting actor poses")
		return {}
	var result: Dictionary=_world_initialization.arrival_motion_construction()
	if result.is_empty():reject(_world_initialization.error)
	return result

func snapshot() -> Dictionary:
	_read_snapshot={}
	return _build_snapshot()

## Borrowed immutable state for simulation queries and presentation. A branch
## invalidates this cache before changing its private owners.
func read_snapshot() -> Dictionary:
	if _read_snapshot.is_empty():_read_snapshot=preload("res://src/simulation/readonly_state.gd").freeze(_build_snapshot(true))
	return _read_snapshot

func _build_snapshot(shared:=false) -> Dictionary:
	if _motion==null:return {}
	var field: Dictionary = _motion.frame_snapshot() if shared else _motion.snapshot()
	field.detail=_detail.snapshot()
	if _escape_relocated:field.escape_relocated=true
	if _bodies!=null:field.bodies=_bodies.read_snapshot() if shared else _bodies.snapshot()
	field.random_state=_random_state.duplicate(true)
	field.world_initialization=_initialization_snapshot if shared else ({} if _world_initialization==null else _world_initialization.snapshot())
	if not _arrival_population.is_empty():field.arrival_population=_arrival_population.duplicate(true)
	if not _departure_population.is_empty():field.departure_population=_departure_population.duplicate(true)
	if not _spin_disabled.is_empty():field.spin_disabled_indices=_spin_disabled.keys()
	if not _destruction.is_empty():
		field.destruction=[]
		for actor in _destruction:field.destruction.append(actor.read_snapshot() if shared else actor.snapshot())
		field.remaining_count=_remaining_count;field.destroyed_count=_destroyed_count
		field.mined_count=_mined_count
	return field

func random_state() -> Dictionary:return _random_state.duplicate(true)

func clock_snapshot() -> Dictionary:
	var state: Dictionary={} if _motion==null else _motion.identity()
	state.random_state=random_state()
	return state

func mining_snapshot() -> Dictionary:
	var state: Dictionary={} if _motion==null else _motion.identity()
	if _bodies!=null:state.bodies=_bodies.mining_snapshot()
	if not _destruction.is_empty():state.mined_count=_mined_count
	return state

func _consume_mined(drill: Dictionary) -> bool:
	_read_snapshot={}
	error=""
	if _bodies==null or _destruction.is_empty() or _remaining_count<=0:return reject("Mining retirement requires live bodies and scenery lifecycles")
	var state: Dictionary=_bodies.read_snapshot()
	for key in ["base_content_id","binding_id"]:
		if drill.get(key)!=state.get(key):return reject("Mined asteroid belongs to another content identity")
	var index: Variant=drill.get("object_index")
	if not index is int or index<0 or index>=_destruction.size() or index>=state.objects.size() or drill.get("phase") not in ["extracted","failed","stopped"]:return reject("Mining retirement requires a finished drill and existing asteroid")
	var row: Dictionary=state.objects[index]
	if row.item_id!=drill.get("item_id") or row.source_size_value!=drill.get("layer_count") or _destruction[index].actor_state()!=0:return reject("Mined asteroid content or lifecycle changed")
	var bodies: RefCounted=_bodies.fork_for_frame()
	var actor: RefCounted=_destruction[index].fork_for_frame()
	if not bodies.retire_mined(index):return reject(bodies.error)
	if not actor.retire_without_destruction():return reject(actor.error)
	actor.disable_drop()
	var destruction:=_destruction.duplicate();destruction[index]=actor
	_bodies=bodies;_destruction=destruction;_remaining_count-=1;_mined_count+=1
	# Mining has no ordinary destruction count, combat pickup, explosion or RNG
	# draw. Cargo is committed by MiningExtraction together with this candidate.
	return true

func set_spin_enabled(object_index: int, enabled: bool) -> bool:
	_read_snapshot={}
	error=""
	if _motion==null or _bodies==null:return reject("Scenery spin requires an owned field with bodies")
	var rows: Array=_bodies.read_snapshot().objects
	if object_index<0 or object_index>=rows.size():return reject("Scenery spin target is outside this field")
	# Spin is independent of lifecycle updates. Disabling it must not freeze
	# destruction, effects, detail selection, or any other asteroid's rotation.
	if enabled:_spin_disabled.erase(object_index)
	else:_spin_disabled[object_index]=true
	return true

func update(presentation_delta_ms: Variant, previous_reference: Variant, detail_value: Variant = 1.0, immediate_reference: Variant = null, shared_random_state: Variant = null) -> bool:
	_read_snapshot={}
	error=""
	if _motion==null:return reject("Configure opening scenery before updating")
	if _destruction.is_empty() and has_pending_destruction():return reject("Scenery destruction requires its verified effect and lifecycle owner")
	var detail: RefCounted = _detail.fork_for_frame()
	var motion: RefCounted = _motion.fork_for_frame()
	if not detail.update(presentation_delta_ms,previous_reference,detail_value,false):return reject(detail.error)
	if immediate_reference!=null and not detail.refresh(immediate_reference,detail_value):return reject(detail.error)
	var destruction := _destruction.duplicate()
	var random_state := _random_state.duplicate(true)
	if shared_random_state!=null:
		if _world_initialization==null: return reject("Shared frame RNG requires complete opening world initialization")
		var random := Generator.new()
		if not random.restore(shared_random_state): return reject(random.error)
		random_state=random.snapshot()
	var events := [];var mask := [];var bodies: RefCounted=_bodies
	if not destruction.is_empty():
		var body_state: Dictionary=_bodies.read_snapshot()
		var field: Dictionary=_motion.snapshot()
		for index in destruction.size():
			var body: Dictionary=body_state.objects[index]
			if body.motion_scalar!=0.0:return reject("Scenery displacement requires a separate motion owner")
			# Intact actors have no lifecycle mutation or RNG consumption.
			if body.vitals.hull>0 and destruction[index].actor_state()==0:
				mask.append(_spin_disabled.has(index));continue
			var actor: RefCounted=destruction[index].fork_for_frame()
			var row: Dictionary=field.objects[index]
			var result: Dictionary=actor.update(presentation_delta_ms,body_state,Transform3D(row.basis.scaled(Vector3.ONE*row.scale),row.position),random_state)
			if result.is_empty():return reject(actor.error)
			if result.motion_scalar!=body.motion_scalar:return reject("Scenery displacement requires a separate motion owner")
			if result.statistics_active!=body.active:
				if bodies==_bodies:bodies=_bodies.fork_for_frame()
				if not bodies.set_permissions(index,result.statistics_active,body.damage_allowed):return reject(bodies.error)
			random_state=result.random_state;events.append_array(result.events)
			mask.append(result.skip_motion or _spin_disabled.has(index));destruction[index]=actor
	elif not _spin_disabled.is_empty():
		for index in motion.snapshot().objects.size():mask.append(_spin_disabled.has(index))
	if not motion.update(presentation_delta_ms,mask):return reject(motion.error)
	_motion=motion;_detail=detail
	_bodies=bodies;_destruction=destruction;_random_state=random_state
	for event in events:
		_remaining_count+=event.world_scenery_count_delta
		_destroyed_count+=event.destruction_count_delta
	_events.append_array(events)
	_initialization_open=false
	return true

func apply_escape_environment(escape: Dictionary) -> bool:
	_read_snapshot={}
	error=""
	if not _escape_available or _motion==null or _bodies==null or _destruction.is_empty():return reject("Escape environment requires configured scenery bodies and lifecycles")
	var field: Dictionary=_motion.snapshot()
	for key in ["base_content_id","binding_id"]:
		if escape.get(key)!=field[key]:return reject("Escape environment belongs to another scenery population")
	var cue: Variant=escape.get("frame",{}).get("world_change",{})
	if escape.get("phase")!=10 or cue!={"sky_mesh_id":17809,"sky_texture_id":10074,"planet_texture_id":10042,"planet_scale_multiplier":2.0}:
		return reject("Unsupported escape relocation cue")
	if _escape_relocated:return reject("Escape scenery has already relocated")
	var bodies: RefCounted=_bodies.fork_for_frame()
	var body_state: Dictionary=bodies.snapshot()
	var destruction:=[]
	if body_state.objects.size()!=_destruction.size():return reject("Escape scenery lifecycle population changed")
	for index in _destruction.size():
		var actor: RefCounted=_destruction[index].fork_for_frame()
		if not actor.retire_without_destruction():return reject(actor.error)
		if not bodies.set_permissions(index,false,body_state.objects[index].damage_allowed):return reject(bodies.error)
		destruction.append(actor)
	# Preserve hulls, cargo, damage permission, membership, counters and RNG. The
	# following ordinary update clears update-enabled on inactive state 4.
	_bodies=bodies;_destruction=destruction;_escape_relocated=true
	return true

func presentation_clock(object_index: int) -> RefCounted:
	return null if object_index<0 or object_index>=_destruction.size() else _destruction[object_index].presentation_clock()

func evaluate_primary_contacts(primaries: RefCounted, combat: RefCounted, inventory: RefCounted, delta_ms: Variant, shared_random_state: Variant=null, display_available:=true) -> Dictionary:
	error=""
	if _bodies==null or not primaries is Primaries or (combat!=null and not combat is Combat):
		reject("Opening weapon contacts require initialized scenery bodies and primaries");return {}
	var candidate: RefCounted=combat
	if combat!=null and combat.has_local_reactions():
		candidate=combat.fork_for_frame()
		if not shared_random_state is Dictionary or not candidate.begin_contact_pass(shared_random_state,display_available):reject("Local contacts require the shared frame stream: "+candidate.error);return {}
	var result: Dictionary=primaries.evaluate_opening_update(candidate,_bodies,inventory,delta_ms)
	if result.is_empty(): reject(primaries.error);return {}
	var next: RefCounted=fork_for_frame()
	next._read_snapshot={}
	next._bodies=result.bodies
	var operation:={"scenery":next,"primaries":result.primaries,"combat":result.combat,"weapons":result.weapons}
	if result.combat!=null and result.combat.has_local_reactions():
		next._random_state=result.combat.contact_random_state();operation.random_state=next._random_state.duplicate(true)
	return operation

func presentation_identity() -> RefCounted:
	return _presentation_identity

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	# update() copies each private owner before any mutation. Share unchanged
	# state here; copy the consumable queue and containers owned by this layer.
	copy._read_snapshot=_read_snapshot;copy._initialization_snapshot=_initialization_snapshot
	copy._motion=_motion;copy._detail=_detail;copy._bodies=_bodies
	copy._destruction=_destruction.duplicate();copy._random_state=_random_state.duplicate(true)
	copy._remaining_count=_remaining_count;copy._destroyed_count=_destroyed_count
	copy._mined_count=_mined_count
	copy._events=_events.duplicate(true);copy._seed_seconds=_seed_seconds
	copy._presentation_identity=_presentation_identity
	copy._world_initialization=_world_initialization;copy._initialization_open=_initialization_open
	copy._escape_available=_escape_available;copy._escape_relocated=_escape_relocated
	copy._arrival_cache=_arrival_cache.duplicate(true);copy._arrival_conditions=_arrival_conditions.duplicate(true)
	copy._arrival_population=_arrival_population.duplicate(true)
	copy._departure_cache=_departure_cache.duplicate(true);copy._departure_conditions=_departure_conditions.duplicate(true)
	copy._departure_population=_departure_population.duplicate(true)
	copy._spin_disabled=_spin_disabled.duplicate()
	return copy

func take_events() -> Array:
	var result := _events.duplicate(true);_events.clear();return result

func seed_seconds() -> int:
	return _seed_seconds

func has_pending_destruction() -> bool:
	if _bodies==null:return false
	if _destruction.is_empty():return _bodies.has_pending_destruction()
	var state: Dictionary=_bodies.read_snapshot()
	for index in _destruction.size():
		if state.objects[index].vitals.hull==0 and _destruction[index].actor_state()==0:return true
	return false

func clear() -> void:
	_read_snapshot={};_initialization_snapshot={}
	error="";_motion=null;_detail=null;_bodies=null;_seed_seconds=0
	_destruction=[];_random_state={};_remaining_count=0;_destroyed_count=0;_mined_count=0;_events=[]
	_presentation_identity=null
	_world_initialization=null;_initialization_open=false;_escape_available=false;_escape_relocated=false
	_arrival_cache={};_arrival_conditions={};_arrival_population={}
	_departure_cache={};_departure_conditions={};_departure_population={}
	_spin_disabled={}

func reject(message: String) -> bool:
	error=message;return false
