extends RefCounted
const Kappa=preload("res://src/content/kappa_population_definitions.gd")
const Alioth=preload("res://src/content/alioth_population_definitions.gd")
const AliothSequence=preload("res://src/simulation/alioth_attack.gd")
## Decisions for verified ordinary NPC target lists. Produces pre-motion
## firing intent and inputs to the shared native NPC flight owner.
## The world owns scheduling, weapons, death, collision and mission consequences.
const Training=preload("res://src/content/combat_training_control_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const AmbientLife=preload("res://src/content/ambient_lifecycle_definitions.gd")
const TrainingDeath=preload("res://src/content/combat_training_destruction_definitions.gd")
const Targeting=preload("res://src/simulation/ordinary_npc_targeting.gd")
const FullHold=preload("res://src/content/full_hold_control_definitions.gd")
const Definitions = preload("res://src/content/opening_npc_guidance_definitions.gd")
const Route = preload("res://src/simulation/npc_route.gd")
const Holding = preload("res://src/content/npc_holding_definitions.gd")
const Initial = preload("res://src/simulation/opening_combat_actor.gd")
const OpeningContext = preload("res://src/content/opening_sky_definitions.gd")
const Flight = preload("res://src/simulation/npc_flight.gd")
const Random = preload("res://src/simulation/seeded_random.gd")
const Vectors = preload("res://src/simulation/source_vectors.gd")
const Vitals = preload("res://src/simulation/combat_vitals.gd")
const ContractCombat=preload("res://src/content/contract_ship_combat_definitions.gd")
const ContractLife=preload("res://src/content/contract_ship_lifecycle_definitions.gd")
const Convoy=preload("res://src/content/convoy_world_definitions.gd")
const NPCConstruction=preload("res://src/simulation/opening_npc_construction.gd")
const DeathDefinitions = preload("res://src/content/npc_destruction_definitions.gd")
var error := ""
var _definition := {}
var _identity := {}
var _state := {}
var _holding := {}
var _route: RefCounted
var _started := false
var _has_destruction := false
var _full_hold := {}
var _pirate := {}
var _training := {}
var _training_death := {}
var _ambient := {}
var _frame_limit:=0
var _recycling:=false
var _boost_enabled:=true

func configure(bindings: RefCounted, catalogues: RefCounted, actor_id: Variant, difficulty: Variant) -> bool:
	clear()
	if bindings==null or not OpeningContext.parameters(bindings.opening_sky): return reject("NPC guidance requires the fresh source opening context")
	var data: Variant = bindings.opening_actors.get("npc_initialization",{}).get("guidance",{})
	if not Definitions.parameters(data): return reject("Opening NPC guidance is unavailable in this pack")
	var actor := Initial.new()
	if not actor.configure(bindings,catalogues,actor_id,difficulty): return reject(actor.error)
	var population: Array = bindings.opening_actors.actors
	var hull_ids := [2,23,2]
	if population.size()!=hull_ids.size(): return reject("NPC guidance requires the source opening target membership")
	for i in population.size():
		if population[i].actor_id!=i or population[i].actor_kind!=data.actor_kind or population[i].hull_catalogue_id!=hull_ids[i]:
			return reject("NPC guidance requires the source opening target membership")
	var body: Dictionary = actor.snapshot()
	if body.actor_kind!=data.actor_kind: return reject("NPC guidance requires the source opening enemy kind")
	var base := Vitals.single(float(data.fresh_hull_base))
	var adjustment := Vitals.single(Vitals.single(float(difficulty))+float(data.difficulty_offset))
	var factory_hull := int(Vitals.single(Vitals.single(adjustment*base)+base))
	# Current Mac hull declarations supersede the historical rank-one fallback.
	# The source constructor samples factory health before the Opening override.
	if bindings.source_architecture=="x86_64" and body.has("factory_hull"):
		factory_hull=int(body.factory_hull)
	if factory_hull<1: return reject("Unsupported fresh NPC hull scale")
	return _configure_state(bindings,data,body,factory_hull)

func configure_full_hold(bindings: RefCounted, catalogues: RefCounted, construction: RefCounted, difficulty: Variant) -> bool:
	clear()
	if bindings==null or not FullHold.parameters(bindings.full_hold_control):return reject("Second-trip NPC control is unavailable")
	var actor:=Initial.new()
	if not actor.configure_full_hold(bindings,catalogues,construction,difficulty):return reject(actor.error)
	var body:=actor.snapshot()
	var data: Dictionary=bindings.opening_actors.npc_initialization.get("guidance",{})
	if not Definitions.parameters(data):return reject("Second-trip guidance lacks its ordinary tuning")
	if not _configure_state(bindings,data,body,int(body.factory_hull)):return false
	_full_hold=bindings.full_hold_control.duplicate(true);_pirate=bindings.full_hold_pirate.duplicate(true)
	_identity.campaign_cursor=int(_full_hold.campaign_cursor)
	var scenery: RefCounted=construction.scenery_owner()
	if not set_initial_route(scenery.initial_npc_route(int(_full_hold.actor_id))):
		var message:=error;clear();return reject(message)
	return true


func configure_combat_training(bindings: RefCounted, catalogues: RefCounted, world: RefCounted, actor_id: Variant, rank: Variant, difficulty: Variant) -> bool:
	clear()
	var actor:=Initial.new()
	if not actor.configure_combat_training(bindings,catalogues,world,actor_id,rank,difficulty):return reject(actor.error)
	var body:=actor.snapshot()
	var data: Dictionary=bindings.opening_actors.npc_initialization.get("guidance",{})
	if not Definitions.parameters(data) or not _configure_state(bindings,data,body,int(body.factory_hull)):return reject("Combat training lacks ordinary guidance tuning")
	_training=bindings.combat_training_control.duplicate(true)
	if TrainingDeath.parameters(bindings.combat_training_destruction):
		_training_death=bindings.combat_training_destruction.duplicate(true)
		_training_death.selection_skipped_modes=_training_death.selection_skipped_modes.map(func(mode):return int(mode))
	_identity.campaign_cursor=int(_training.campaign_cursor);_identity.rank=rank
	_state.target_index=int(_training.initial_target_index)
	_state.desired_position=Vector3.ZERO
	if int(body.actor_kind)!=int(data.actor_kind):_definition.boost_chance=int(_training.companion_boost_chance)
	if not set_initial_route(world.route(actor_id)):
		var message:=error;clear();return reject(message)
	return true

func _configure_state(bindings: RefCounted, data: Dictionary, body: Dictionary, factory_hull: int) -> bool:
	var holding: Variant = bindings.opening_actors.npc_initialization.get("holding",{})
	if not holding is Dictionary or (not holding.is_empty() and not Holding.parameters(holding)): return reject("Unsupported NPC holding declaration")
	_holding=holding.duplicate(true)
	_has_destruction=DeathDefinitions.parameters(bindings.opening_actors.npc_initialization.get("destruction"))
	_definition=data.duplicate(true)
	_identity={"base_content_id":body.base_content_id,"binding_id":body.binding_id,
		"actor_id":body.actor_id,"actor_kind":body.actor_kind,"hull_catalogue_id":body.hull_catalogue_id,
		"difficulty":body.difficulty}
	# The later authored current-hull setter raises the maximum if needed. The
	# constructor's previous-hull sample remains at the earlier factory value.
	_state={"maximum_hull":maxi(factory_hull,body.vitals.hull),"previous_hull":factory_hull,
		"damage_accumulated":0,"selection_elapsed_ms":0,"boost_elapsed_ms":0,
		"straight":false,"fire_desired":false,"target_selected":true,"boost_active":false,"damage_boost":false,
		"boost_duration_ms":0,"speed":float(data.cruise_speed),"speed_target":0.0}
	if not _holding.is_empty():
		_state.selection_elapsed_ms=int(_holding.selection_elapsed_ms)
		_state.boost_elapsed_ms=int(_holding.boost_elapsed_ms)
	return true

func configure_local_patrol(bindings: RefCounted, catalogues: RefCounted, world: RefCounted, actor_id: Variant, rank: Variant, difficulty: Variant) -> bool:
	clear()
	var actor:=Initial.new()
	if not actor.configure_local_patrol(bindings,catalogues,world,actor_id,rank,difficulty):return reject(actor.error)
	var body:=actor.snapshot()
	var data: Dictionary=bindings.opening_actors.npc_initialization.get("guidance",{})
	if not Definitions.parameters(data) or not _configure_state(bindings,data,body,int(body.factory_hull)):return reject("Local patrol lacks ordinary guidance tuning")
	_training=Travel.patrol(bindings,world.snapshot(),rank,difficulty)
	_training_death=bindings.mido_travel.traffic_combat.death.duplicate(true)
	_training_death.selection_skipped_modes=_training_death.selection_skipped_modes.map(func(mode):return int(mode))
	_identity.campaign_cursor=int(_training.campaign_cursor);_identity.rank=rank
	_state.target_index=int(_training.initial_target_index);_state.desired_position=Vector3.ZERO
	_definition.boost_chance=int(_training.boost_chance)
	if not set_initial_route(world.route(actor_id)):
		var message:=error;clear();return reject(message)
	return true

func configure_ambient(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,actor_id: Variant,rank: Variant,difficulty: Variant) -> bool:
	clear()
	if construction==null:return reject("Ambient guidance requires generated construction")
	var rules:=AmbientLife.guidance(bindings,construction.snapshot(),rank,difficulty)
	if rules.is_empty():return reject("Ambient guidance is unavailable in this pack")
	var actor:=Initial.new()
	if not actor.configure_ambient(bindings,catalogues,construction,actor_id,rank,difficulty):return reject(actor.error)
	var body:=actor.snapshot()
	if body.population_group=="freighter":return reject("Freighters require their own motion owner")
	var data: Dictionary=bindings.opening_actors.npc_initialization.get("guidance",{})
	if not Definitions.parameters(data) or not _configure_state(bindings,data,body,int(body.factory_hull)):return reject("Ambient guidance lacks ordinary tuning")
	_training=rules;_training_death=bindings.mido_travel.traffic_combat.death.duplicate(true)
	_frame_limit=int(bindings.frame_clock.max_frame_milliseconds)
	_training_death.selection_skipped_modes=_training_death.selection_skipped_modes.map(func(mode):return int(mode))
	_identity.campaign_cursor=int(rules.campaign_cursor);_identity.rank=rank
	_state.target_index=int(rules.initial_target_index);_state.desired_position=Vector3.ZERO
	_definition.boost_chance=int(rules.boost_chance)
	_recycling=AmbientLife.recycling_parameters(bindings.ambient_lifecycle)
	if _recycling:_state.spawn_generation=0
	if body.population_group=="travel":
		_ambient=bindings.ambient_lifecycle.duplicate(true)
		_state.route_elapsed_ms=0;_state.parked_elapsed_ms=0;_state.travel_cycle=0
	if not set_initial_route(construction.route(actor_id)):
		var message:=error;clear();return reject(message)
	return true

func configure_contract(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,actor_id: Variant) -> bool:
	clear()
	if not construction is NPCConstruction:return reject("Contract guidance requires its generated population")
	var rules:=ContractCombat.population(bindings,construction.snapshot())
	if rules.is_empty():return reject("Unsupported contract ship guidance")
	var actor:=Initial.new()
	if not actor.configure_contract(bindings,catalogues,construction,actor_id):return reject(actor.error)
	var body:=actor.snapshot()
	var data: Dictionary=bindings.opening_actors.npc_initialization.get("guidance",{})
	if not Definitions.parameters(data) or not _configure_state(bindings,data,body,int(body.factory_hull)):return reject("Contract guidance lacks ordinary ship tuning")
	_training=rules
	if ContractLife.available(bindings):_training_death=ContractLife.population(bindings,construction.snapshot())
	_identity.campaign_cursor=int(rules.campaign_cursor);_identity.rank=int(rules.rank)
	_state.target_index=int(rules.initial_target_index);_state.desired_position=Vector3.ZERO
	_frame_limit=int(bindings.frame_clock.max_frame_milliseconds)
	_boost_enabled=bool(rules.rival.boost_enabled if body.population_group=="rival" else rules.pirate.boost_enabled)
	if not _boost_enabled:_state.speed=float(rules.rival.motion_speed)
	if not set_initial_route(construction.route(actor_id)):
		var message:=error;clear();return reject(message)
	return true

func relaunch_ambient(actor: Dictionary) -> bool:
	error=""
	if (_ambient.is_empty() and not _recycling) or _route==null:return reject("Traffic relaunch requires its retained route and guidance")
	for key in _identity:
		if actor.get(key)!=_identity[key]:return reject("Traffic relaunch belongs to another actor")
	if actor.get("actor_mode")!=1 or actor.get("active")!=true or actor.get("vitals",{}).get("hull")!=_state.maximum_hull:return reject("Traffic relaunch requires restored source statistics")
	if _recycling and actor.get("spawn_generation")!=_state.spawn_generation+1:return reject("Traffic relaunch has not advanced to its next instance")
	if not _ambient.is_empty() and actor.get("travel_cycle")!=_state.travel_cycle+1:return reject("Traffic relaunch has not advanced its route cycle")
	var route: RefCounted=_route.fork_for_frame()
	if not route.restart_ambient_route():return reject(route.error)
	_state.previous_hull=_state.maximum_hull;_state.damage_accumulated=0
	_state.target_index=-1;_state.target_selected=false;_state.fire_desired=false
	# Reinitialization clears the damage-trigger flag, but retains any active
	# boost, its target/duration and both clocks while restoring cruise speed.
	_state.damage_boost=false;_state.speed=float(_definition.cruise_speed)
	if not _ambient.is_empty():_state.route_elapsed_ms=0;_state.parked_elapsed_ms=0;_state.travel_cycle=actor.travel_cycle
	if _recycling:_state.spawn_generation=actor.spawn_generation
	_route=route
	return true

func configure_convoy(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,actor_id: Variant) -> bool:
	clear()
	if not construction is NPCConstruction:return reject("Convoy guidance requires its generated encounter")
	var rules:=Convoy.lifecycle(bindings,construction.snapshot())
	if rules.is_empty():return reject("Unsupported convoy ship guidance")
	var actor:=Initial.new()
	if not actor.configure_convoy(bindings,catalogues,construction,actor_id):return reject(actor.error)
	return _configure_fighter_guidance(bindings,rules,actor.snapshot(),construction.route(actor_id))

func configure_alioth_attack(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,actor_id: Variant) -> bool:
	clear()
	if not construction is NPCConstruction:return reject("Alioth guidance requires its generated encounter")
	var rules:=Alioth.lifecycle(bindings,construction.snapshot())
	if rules.is_empty():return reject("Unsupported Alioth ship guidance")
	var actor:=Initial.new()
	if not actor.configure_alioth_attack(bindings,catalogues,construction,actor_id):return reject(actor.error)
	if not _configure_fighter_guidance(bindings,rules,actor.snapshot(),construction.route(actor_id)):return false
	_boost_enabled=bool(rules.alioth_lifecycle.boost_enabled)
	_state.alioth_targets_cleared=false
	return true

func configure_kappa_rescue(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,actor_id: Variant) -> bool:
	clear()
	if not construction is NPCConstruction:return reject("Kappa guidance requires its generated rescue")
	var rules:=Kappa.guidance(bindings,construction.snapshot())
	if rules.is_empty():return reject("Unsupported Kappa fighter guidance")
	var actor:=Initial.new()
	if not actor.configure_kappa_rescue(bindings,catalogues,construction,actor_id):return reject(actor.error)
	return _configure_fighter_guidance(bindings,rules,actor.snapshot(),construction.route(actor_id))

func _configure_fighter_guidance(bindings: RefCounted,rules: Dictionary,body: Dictionary,route: RefCounted) -> bool:
	if body.population_group!="fighter":return reject("Large ships require their own motion owner")
	var data: Dictionary=bindings.opening_actors.npc_initialization.get("guidance",{})
	if not Definitions.parameters(data) or not _configure_state(bindings,data,body,int(body.factory_hull)):return reject("Fighter guidance lacks ordinary ship tuning")
	_training=rules;_training_death=rules
	_identity.campaign_cursor=int(rules.campaign_cursor);_identity.rank=int(rules.rank)
	_state.target_index=int(rules.initial_target_index);_state.desired_position=Vector3.ZERO
	_frame_limit=int(bindings.frame_clock.max_frame_milliseconds)
	if not set_initial_route(route):
		var message:=error;clear();return reject(message)
	return true

func apply_alioth_escape(owner: RefCounted) -> bool:
	error=""
	if not owner is AliothSequence or not _training.has("alioth_lifecycle") or _state.get("alioth_targets_cleared",true) or _route==null:return reject("Alioth escape requires its retained combat guidance")
	var route: RefCounted=_route.fork_for_frame()
	if not route.replace_with_alioth_escape(owner):return reject(route.error)
	_route=route;_state.alioth_targets_cleared=true
	# Clearing the statistics target list does not reset selection/boost clocks,
	# firing desire, straight-flight state or the preceding desired position.
	return true

func update(delta_ms: Variant, actor: Dictionary, root_pose: Variant, player: Dictionary, random_state: Variant, target_actors: Array=[]) -> Dictionary:
	error=""
	if _state.is_empty(): return fail("Configure opening NPC guidance before updating")
	if not Vitals.integer(delta_ms): return fail("NPC guidance requires integer elapsed milliseconds")
	if _frame_limit>0 and delta_ms>_frame_limit:return fail("Ambient guidance duration exceeds its source frame limit")
	for key in _identity:
		if actor.get(key)!=_identity[key]: return fail("NPC guidance actor identity changed")
	if _recycling and actor.get("spawn_generation")!=_state.spawn_generation:return fail("NPC guidance belongs to another traffic instance")
	for key in ["base_content_id","binding_id"]:
		if player.get(key)!=_identity[key]: return fail("NPC target belongs to another content identity")
	if not actor.get("active") is bool: return fail("NPC guidance requires explicit activity")
	var held: bool = not _holding.is_empty() and not actor.active and actor.get("actor_mode")==_holding.actor_mode
	var pools: Variant = actor.get("vitals")
	if not pools is Dictionary or not Vitals.integer(pools.get("hull")) or pools.hull>_state.maximum_hull: return fail("NPC guidance requires supported hull state")
	var waiting: bool=not _ambient.is_empty() and not actor.active and actor.get("actor_mode")==int(_ambient.initial_mode) and pools.hull>0
	var outbound: bool=not _ambient.is_empty() and actor.active and actor.get("actor_mode")==int(_ambient.departure_mode)
	if not _ambient.is_empty() and actor.get("travel_cycle")!=_state.travel_cycle:return fail("Traffic body and guidance disagree about their launch cycle")
	var initializing: bool=not _training.is_empty() and actor.active and actor.get("actor_mode")==0
	var dying: bool=_has_destruction and pools.hull==0 and actor.active and actor.get("actor_mode") in [1,3,4]
	if outbound and pools.hull==0:dying=true
	if not _training_death.is_empty() and initializing and pools.hull==0:dying=true
	if not dying and not waiting and not outbound and (pools.hull==0 or (not held and not initializing and (not actor.active or actor.get("actor_mode")!=1))): return fail("NPC guidance requires supported holding, flight or death mode")
	if not root_pose is Transform3D or not actor.get("pose") is Transform3D or not root_pose.is_finite() or not actor.pose.is_finite() or (not outbound and not waiting and root_pose.origin!=actor.pose.origin): return fail("NPC root and combat poses must share a finite source position")
	if not dying and (not Flight.rigid_pose(root_pose) or not Flight.rigid_pose(actor.pose)): return fail("Live NPC guidance requires unscaled source axes")
	if not Flight.rigid_pose(player.get("pose")) or not player.get("active") is bool or not Vitals.integer(player.get("hull")) or not player.get("special_flight") is bool or not player.get("targeting_blocked") is bool: return fail("NPC guidance requires explicit player pose, activity, hull and targeting/flight state")
	if _full_hold.is_empty() and _training.is_empty() and held and (not player.targeting_blocked or actor.get("spatial_half_extent")!=_holding.spatial_half_extent): return fail("Opening holding mode requires its initial engagement range and player suppression")
	if not Vitals.integer(actor.get("spatial_half_extent")) or actor.spatial_half_extent<1: return fail("NPC engagement range is unavailable")
	if not _full_hold.is_empty() or not _training.is_empty():
		var context: Dictionary=_training if not _training.is_empty() else _full_hold
		if player.get("ship_id")!=context.player_ship_id or not player.has("alternate_position"):return fail("Second-trip targeting requires its source player and explicit alternate-body position")
		var alternate: Variant=player.alternate_position
		if alternate!=null and (not alternate is Vector3 or not alternate.is_finite()):return fail("Invalid alternate player position")
	var targets:=[]
	var without_targets: bool=_state.get("alioth_targets_cleared",false)
	if not _training.is_empty():
		targets=training_targets(player,target_actors)
		if not error.is_empty() or (targets.is_empty() and not without_targets):return {}
		if _identity.campaign_cursor==7 and actor.get("hostile")!=(int(actor.actor_kind)==8):return fail("Combat-training guidance requires refreshed source hostility")
	for key in ["selection_elapsed_ms","boost_elapsed_ms"]:
		if _state[key]>Vitals.MAX_INTEGER-delta_ms: return fail("NPC guidance timer overflow")
	var random := Random.new()
	if not random.restore(random_state): return fail(random.error)
	var next := _state.duplicate(true)
	if waiting:
		# A parked mode4 ship skips selection. Before its first relaunch, the
		# source still ages selection/boost clocks through the normal actor pass.
		if next.parked_elapsed_ms<=int(_ambient.parked_clock_limit_ms):
			next.selection_elapsed_ms+=delta_ms;next.boost_elapsed_ms+=delta_ms;next.parked_elapsed_ms+=delta_ms
		var dormant:=_identity.duplicate()
		dormant.merge({"direction":root_pose.basis.z,"speed":next.speed,"steering_enabled":false,"travel_enabled":false,
			"fire_requested":false,"holding":false,"initializing":false,"activation":"","node_draw_requested":false,
			"traffic_waiting":true,"random_state":random.snapshot()})
		_state=next;_started=true
		return dormant
	next.selection_elapsed_ms+=delta_ms
	next.boost_elapsed_ms+=delta_ms
	var separation := Vectors.added(player.pose.origin,-root_pose.origin)
	if not separation.is_finite(): return fail("NPC target separation exceeds source precision")
	var eligible: bool = player.active and player.hull>0
	var engaged := inside(separation,float(actor.spatial_half_extent))
	var target: Dictionary=player if _training.is_empty() or without_targets else targets[0]
	if without_targets:
		# A null membership bypasses target refresh and its random draws. Route
		# movement and ordinary boosts still run, including after the final point.
		target=player.duplicate();target.actor_id=-1;target.target_kind="route"
	elif not _training.is_empty():
		if _training_death.is_empty() or actor.get("actor_mode") not in _training_death.selection_skipped_modes:
			next=Targeting.select(next,actor,targets,random,_definition,_training)
		if next.target_index>=0:target=targets[int(next.target_index)]
	else:
		var refresh: bool = next.selection_elapsed_ms>int(_definition.selection_period_ms)
		# Source selection and firing desire are separate retained states. A range
		# refresh can clear selection while leaving desire set, so reacquisition then
		# waits for the next refresh even if the player reenters the engagement box.
		if not next.fire_desired: next.target_selected=false
		if next.fire_desired and not player.active: next.fire_desired=false
		if refresh:
			next.straight=false if next.straight else random.next_int(int(_definition.straight_roll_bound))<int(_definition.straight_chance)
			next.selection_elapsed_ms=0
			random.next_int(int(_definition.selection_roll_bound))
			next.target_selected=eligible and engaged
			if not eligible: next.fire_desired=false
		elif not next.fire_desired and eligible and engaged:
			next.fire_desired=true
			next.target_selected=true
	var activation:=""
	var steering_separation:=separation
	if (not _full_hold.is_empty() or not _training.is_empty()) and held:
		# Inactive source statistics bypass patrol advance and retain player0 even
		# when the preceding selection pass cleared the firing-desire/index pair.
		next.target_selected=true
		if not _training.is_empty():
			next.target_index=0;next.desired_position=player.pose.origin;target=targets[0]
		if actor.get("hostile")!=true and not _training.get("kappa_rescue",false):return fail("Second-trip holding requires its source hostility")
		if player.alternate_position!=null:
			steering_separation=Vectors.added(player.alternate_position,-root_pose.origin)
			if not steering_separation.is_finite():return fail("Alternate player separation exceeds source precision")
		var activation_rules: Dictionary=_training if not _training.is_empty() else _pirate
		if actor.get("hostile")==true and inside(steering_separation,float(activation_rules.proximity_half_extent)):
			activation="proximity";held=false
		elif not player.targeting_blocked and inside(steering_separation,float(activation_rules.target_activation_half_extent)):
			activation="target"
	# Continued training death skips selection and patrol. A first lethal pass
	# still resolves the route fallback before the later source hull guard.
	if dying and (_training_death.is_empty() or actor.actor_mode in [3,4]):
		return _death_decision(next,root_pose,random.snapshot())
	# Holding enemies still select targets and consume refresh draws. The source
	# mode dispatch returns before damage boosts, aiming, firing and movement.
	# Player suppression preserves this authored hold until the activation cue.
	if held:
		next.target_selected=true
		var held_result := _identity.duplicate()
		held_result.merge({"target_kind":"player","direction":root_pose.basis.z,"speed":next.speed,
			"steering_enabled":false,"travel_enabled":false,"fire_requested":false,
			"random_state":random.snapshot(),"holding":true})
		if not _full_hold.is_empty() or not _training.is_empty():
			held_result.activation=activation
			held_result.node_draw_requested=not activation.is_empty()
			if _training.get("kappa_rescue",false) and not actor.hostile and activation.is_empty():held_result.node_draw_requested=bool(actor.node_draw_requested)
		if not _training.is_empty():held_result.initializing=false;held_result.target_actor_id=-1
		_state=next
		_started=true
		return held_result
	var routed: bool = without_targets or not next.target_selected
	var has_target: bool=not routed
	var target_kind: String="player" if _training.is_empty() else String(target.target_kind)
	var staged_route: RefCounted = null if _route==null else _route.fork_for_frame()
	var route_event := {}
	var target_position: Vector3 = target.pose.origin
	if routed:
		if staged_route==null: return fail("NPC route fallback requires its generated constructor state")
		var previous_route: Dictionary=staged_route.snapshot()
		route_event=staged_route.advance(root_pose.origin)
		if route_event.is_empty(): return fail(staged_route.error)
		if not _training.is_empty() and route_event.target==null:
			if without_targets:
				target_position=next.desired_position;target_kind="retained_position"
			elif previous_route.get("completed",false):
				routed=false
				target=targets[0];target_position=target.pose.origin;target_kind="player";has_target=true
				next.target_index=0;next.target_selected=true
			else:
				routed=false
				# Advancing the last point preserves the preceding desired position
				# for one pass. The next pass falls back to target zero.
				target_position=next.desired_position;target_kind="retained_position"
		else:
			target_position=route_event.target;target_kind="route"
	if not _training.is_empty():
		next.desired_position=target_position
		if initializing and not dying:
			var initial_result:=_identity.duplicate()
			initial_result.merge({"target_kind":target_kind,"target_actor_id":int(target.actor_id) if has_target else -1,
				"route_event":route_event,"direction":root_pose.basis.z,"speed":next.speed,"steering_enabled":false,"travel_enabled":false,
				"fire_requested":false,"holding":false,"initializing":true,"activation":"","node_draw_requested":true,"random_state":random.snapshot()})
			_state=next;_route=staged_route;_started=true
			return initial_result
	if dying:
		_route=staged_route
		return _death_decision(next,root_pose,random.snapshot())
	if not _ambient.is_empty():
		next.route_elapsed_ms=next.route_elapsed_ms+delta_ms if routed else 0
		if outbound or next.route_elapsed_ms>=int(_ambient.departure_after_route_ms):
			if not outbound:next.route_elapsed_ms=0
			next.speed=Vitals.single(next.speed*float(_ambient.departure_speed_multiplier))
			var departing:=_identity.duplicate()
			departing.merge({"target_kind":target_kind,"target_actor_id":-1,"route_event":route_event,
				"direction":root_pose.basis.z,"speed":next.speed,"steering_enabled":false,"travel_enabled":true,
				"fire_requested":false,"holding":false,"initializing":false,"activation":"","node_draw_requested":true,
				"traffic_departure":true,"traffic_parked":next.speed>float(_ambient.park_above_speed),"random_state":random.snapshot()})
			if departing.traffic_parked:next.parked_elapsed_ms=0
			_state=next;_route=staged_route;_started=true
			return departing
	separation=Vectors.added(target_position,-root_pose.origin)
	if not separation.is_finite():return fail("Selected NPC target separation exceeds source precision")
	if activation!="proximity":steering_separation=separation
	eligible=target.active and target.hull>0
	if _boost_enabled and pools.hull<next.previous_hull:
		next.damage_accumulated+=next.previous_hull-pools.hull
		next.previous_hull=pools.hull
		var percent := Vitals.single(Vitals.single(Vitals.single(float(next.damage_accumulated))/Vitals.single(float(next.maximum_hull)))*float(_definition.damage_percent_scale))
		if percent>float(_definition.boost_damage_percent):
			next.damage_accumulated=0
			next.boost_elapsed_ms=int(_definition.damage_boost_elapsed_ms)
			next.damage_boost=true
	if _boost_enabled and next.boost_elapsed_ms>int(_definition.boost_period_ms) and not next.boost_active:
		next.boost_elapsed_ms=0
		if next.damage_boost or random.next_int(int(_definition.boost_roll_bound))<int(_definition.boost_chance):
			next.boost_duration_ms=int(_definition.boost_duration_base_ms)+random.next_int(int(_definition.boost_duration_bound_ms))
			next.boost_active=true
			next.speed_target=float(_definition.boost_speed)
	if next.boost_active:
		if next.boost_elapsed_ms>next.boost_duration_ms:
			next.boost_elapsed_ms=0
			next.damage_boost=false
			next.speed_target=float(_definition.cruise_speed)
		if next.speed_target>0:
			var factor: float = _definition.speed_increase if next.speed_target>next.speed else _definition.speed_decrease
			next.speed=Vitals.single(next.speed*factor)
			if next.speed>=float(_definition.boost_speed) or next.speed<float(_definition.cruise_speed):
				next.speed=next.speed_target
				if next.speed_target==float(_definition.cruise_speed): next.boost_active=false
				next.speed_target=0.0
	var desired := steering_separation if activation=="proximity" else Vectors.added(target_position,-root_pose.origin)
	var near_range := float(_definition.special_close_half_extent if target.special_flight else _definition.close_half_extent)
	var close := has_target and not routed and inside(steering_separation,near_range)
	if close: desired=root_pose.basis.z
	desired=Vectors.normalized(desired)
	if not desired.is_finite(): return fail("NPC desired heading exceeds source precision")
	# The source transposes the combat basis and transforms a direction, with no
	# translation contribution. It then negates the local vertical component.
	var aim := Vector3(Vectors.dot(actor.pose.basis.x,desired),-Vectors.dot(actor.pose.basis.y,desired),Vectors.dot(actor.pose.basis.z,desired))
	var aligned := absf(aim.x)<float(_definition.fire_alignment) and absf(aim.y)<float(_definition.fire_alignment)
	var fire: bool = has_target and not routed and next.fire_desired and aligned and inside(separation,float(_definition.fire_half_extent))
	if has_target and not routed and target.targeting_blocked:
		fire=false
		next.fire_desired=false
	if fire and (not eligible or (target.special_flight and target.pose.origin.y>root_pose.origin.y)):
		fire=false
		next.fire_desired=false
	var result := _identity.duplicate()
	result.merge({"target_kind":target_kind,"route_event":route_event,"direction":desired,"speed":next.speed,
		"steering_enabled":not next.straight,"fire_requested":fire,"local_aim":aim,
		"travel_enabled":true,"holding":false,"close_heading_preserved":close,"random_state":random.snapshot()})
	if not _full_hold.is_empty() or not _training.is_empty():
		result.activation=activation;result.node_draw_requested=true
	if not _training.is_empty():
		result.initializing=false;result.target_actor_id=int(target.actor_id) if has_target else -1
	_state=next
	_route=staged_route
	_started=true
	return result

func _death_decision(next: Dictionary, root_pose: Transform3D, random_state: Dictionary) -> Dictionary:
	var result:=_identity.duplicate()
	result.merge({"target_kind":"player","direction":root_pose.basis.z,"speed":next.speed,
		"steering_enabled":false,"travel_enabled":false,"fire_requested":false,
		"random_state":random_state,"holding":false,"dying":true})
	_state=next;_started=true
	return result


func training_targets(player: Dictionary, actors: Array) -> Array:
	if actors.size()!=int(_training.actor_count):fail("Ordinary NPC targeting requires the complete configured population");return []
	for id in actors.size():
		var row: Variant=actors[id]
		if not row is Dictionary or row.get("actor_id")!=id or row.get("actor_kind")!=_training.actor_kinds[id] or row.get("hull_catalogue_id")!=_training.hull_catalogue_ids[id]:fail("Combat-training target membership changed");return []
		for key in ["base_content_id","binding_id","campaign_cursor","rank"]:
			if row.get(key)!=_identity[key]:fail("Combat-training target belongs to another encounter");return []
		if not row.get("active") is bool or not row.get("statistics_targeting_blocked") is bool or not Vitals.integer(row.get("vitals",{}).get("hull")) or not row.get("pose") is Transform3D or not row.pose.is_finite():fail("Invalid combat-training target statistics");return []
		if not Vectors.added(row.pose.origin,-player.pose.origin).is_finite():fail("Combat-training target exceeds source precision");return []
	var result:=[]
	if _state.get("alioth_targets_cleared",false):return result
	for id in _training.target_memberships[int(_identity.actor_id)]:
		if int(id)==int(_training.player_target_id):
			# The source's nonplayer scan classifies player statistics as kind0.
			# Challenge memberships can place that entry after an NPC.
			var target:=player.duplicate(true);target.actor_id=-1;target.actor_kind=0;target.target_kind="player";result.append(target)
		else:
			var row: Dictionary=actors[int(id)]
			result.append({"actor_id":int(id),"actor_kind":int(row.actor_kind),"target_kind":"npc","pose":row.pose,
				"active":row.active,"hull":int(row.vitals.hull),"targeting_blocked":row.statistics_targeting_blocked,"special_flight":false})
	return result

func set_initial_route(route: RefCounted) -> bool:
	error=""
	if _state.is_empty() or _started or _route!=null or not route is Route: return reject("Attach one generated route before the first NPC update")
	var state: Dictionary = route.snapshot()
	for key in ["base_content_id","binding_id","actor_id"]:
		if state.get(key)!=_identity[key]: return reject("NPC route belongs to another actor or content identity")
	if state.get("waypoints",[]).is_empty() or state.get("index")!=0: return reject("NPC route must have its fresh generated state")
	_route=route.fork_for_frame()
	return true

func snapshot() -> Dictionary:
	if _state.is_empty(): return {}
	var result := _identity.duplicate()
	result.merge(_state.duplicate(true))
	result.route={} if _route==null else _route.snapshot()
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._definition=_definition.duplicate(true);copy._identity=_identity.duplicate();copy._state=_state.duplicate(true)
	copy._holding=_holding.duplicate(true)
	copy._route=null if _route==null else _route.fork_for_frame()
	copy._started=_started
	copy._has_destruction=_has_destruction
	copy._full_hold=_full_hold.duplicate(true);copy._pirate=_pirate.duplicate(true);copy._training=_training.duplicate(true)
	copy._training_death=_training_death.duplicate(true)
	copy._ambient=_ambient.duplicate(true)
	copy._frame_limit=_frame_limit
	copy._recycling=_recycling
	copy._boost_enabled=_boost_enabled
	return copy

static func inside(separation: Vector3, half_extent: float) -> bool:
	return absf(separation.x)<half_extent and absf(separation.y)<half_extent and absf(separation.z)<half_extent

func clear() -> void:
	error="";_definition={};_identity={};_state={};_holding={};_route=null;_started=false
	_has_destruction=false;_full_hold={};_pirate={};_training={};_training_death={}
	_ambient={}
	_frame_limit=0
	_recycling=false
	_boost_enabled=true

func reject(message: String) -> bool:
	error=message
	return false

func fail(message: String) -> Dictionary:
	reject(message)
	return {}
