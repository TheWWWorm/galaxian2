extends RefCounted
const FreeLife=preload("res://src/content/free_lifecycle_definitions.gd")
## Native ordinary NPC bodies for verified encounter populations.
## Encounter logic supplies poses, lifecycle changes and already-resolved hits.
const TrainingControl=preload("res://src/content/combat_training_control_definitions.gd")
const TrainingDeath=preload("res://src/content/combat_training_destruction_definitions.gd")
const TrainingWorld=preload("res://src/simulation/opening_world_initialization.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const AmbientCombat=preload("res://src/content/ambient_combat_definitions.gd")
const AmbientLife=preload("res://src/content/ambient_lifecycle_definitions.gd")
const NPCConstruction=preload("res://src/simulation/opening_npc_construction.gd")
const ContractCombat=preload("res://src/content/contract_ship_combat_definitions.gd")
const ContractLife=preload("res://src/content/contract_ship_lifecycle_definitions.gd")
const ControlDefinitions=preload("res://src/content/full_hold_control_definitions.gd")
const Appearance=preload("res://src/content/full_hold_appearance_definitions.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const FullHold = preload("res://src/content/full_hold_pirate_definitions.gd")
const Construction = preload("res://src/simulation/first_flight_construction.gd")
const Library = preload("res://src/content/library.gd")
const Activation = preload("res://src/content/npc_activation_definitions.gd")
const Holding = preload("res://src/content/npc_holding_definitions.gd")
const Hostility = preload("res://src/content/npc_hostility_definitions.gd")
const DeathAccounting = preload("res://src/content/npc_death_accounting_definitions.gd")
const FreighterDeath=preload("res://src/simulation/freighter_destruction.gd")
const SmallShipDeath=preload("res://src/simulation/npc_destruction.gd")
const Junk=preload("res://src/content/contract_junk_definitions.gd")
const DebrisDeath=preload("res://src/simulation/debris_destruction.gd")
const Hull = preload("res://src/content/npc_hull_definitions.gd")
const InitialActors = preload("res://src/simulation/opening_actor_state.gd")
const Definitions = preload("res://src/content/npc_initialization_definitions.gd")
const Vitals = preload("res://src/simulation/combat_vitals.gd")
const Convoy = preload("res://src/content/convoy_world_definitions.gd")
const ConvoyShip = preload("res://src/content/convoy_ship_definitions.gd")
const ConvoyCapture = preload("res://src/simulation/convoy_capture.gd")
const Kappa = preload("res://src/content/kappa_population_definitions.gd")
const KappaFighters = preload("res://src/content/kappa_fighters_definitions.gd")
const KappaRescue = preload("res://src/simulation/kappa_rescue.gd")
const ShipSystems = preload("res://src/simulation/ship_systems.gd")
const NPCSystems = preload("res://src/content/npc_systems_definitions.gd")
const Alioth = preload("res://src/content/alioth_population_definitions.gd")
const AliothAttack = preload("res://src/simulation/alioth_attack.gd")
var error := ""
var _initial_training_death := false
var _state := {}
var _vitals: RefCounted
var _systems: RefCounted
var _hostility := {}
var _hull_percentage_scale := 0.0

func clear() -> void:
	_initial_training_death=false
	error = ""
	_state = {}
	_vitals = null
	_systems = null
	_hostility = {}
	_hull_percentage_scale = 0.0

func configure(bindings: RefCounted, catalogues: RefCounted, actor_id: Variant, difficulty: Variant) -> bool:
	clear()
	if bindings == null or catalogues == null: return reject("Opening combat actors require content bindings and catalogues")
	if not actor_id is int or actor_id < 0: return reject("Opening combat actors require an explicit actor ID")
	if (not difficulty is float and not difficulty is int) or not is_finite(difficulty) or difficulty < 0 or difficulty > 10:
		return reject("Opening combat actors require an explicit finite source difficulty value")
	var initial := InitialActors.new()
	if not initial.configure(bindings,catalogues,catalogues.content_id): return reject(initial.error)
	var data: Variant = bindings.opening_actors.get("npc_initialization",{})
	if not data is Dictionary or not Definitions.parameters(data): return reject("This content profile has no supported NPC initialization declarations")
	if data.is_player or data.initial_point_geometry or data.initial_special_impact_state:
		return reject("This opening actor requires an unsupported player, point-geometry or special-impact path")
	var actors: Array = initial.snapshot().actors
	if actor_id >= actors.size(): return reject("Opening actor ID is outside the authored population")
	var actor: Dictionary = actors[actor_id]
	var source_difficulty := Vitals.single(float(difficulty))
	var hull: Variant = data.get("hull",{})
	if not hull is Dictionary: return reject("Invalid NPC hull capability")
	if not hull.is_empty():
		if Hull.legacy_parameters(hull):return reject("Reprepare resource bindings to correct the flight-entry NPC rank")
		var world: Variant=data.get("world_initialization",{})
		if not Hull.parameters(hull) or not world is Dictionary or world.get("campaign_cursor")!=hull.campaign_cursor:
			return reject("NPC maximum hull requires its verified fresh campaign context")
		if actors.size()!=hull.hull_catalogue_ids.size() or actor.hull_catalogue_id!=hull.hull_catalogue_ids[actor_id]:
			return reject("NPC maximum hull belongs to another opening population")
	var factory_hull := -1
	var percentage_scale := 0.0
	if not hull.is_empty():
		factory_hull=scaled_hull(float(hull.base_hull),source_difficulty,float(hull.difficulty_offset))
		percentage_scale=float(hull.percentage_scale)
	return _initialize_body(bindings,data,actor,source_difficulty,factory_hull,percentage_scale)

func configure_full_hold(bindings: RefCounted, catalogues: RefCounted, construction: RefCounted, difficulty: Variant) -> bool:
	clear()
	var initial:=full_hold_initial(bindings,catalogues,construction)
	if initial.is_empty():return reject("Second pirate combat requires its matching detached flight construction")
	if (not difficulty is float and not difficulty is int) or not is_finite(difficulty) or difficulty<0 or difficulty>10:
		return reject("Second pirate requires an explicit finite source difficulty")
	var data: Dictionary=bindings.full_hold_pirate
	var source_difficulty:=Vitals.single(float(difficulty))
	var base:=int(data.rank_base)+int(data.rank_multiplier)*int(initial.rank)+int(data.cursor_multiplier)*int(data.campaign_cursor)
	var factory_hull:=scaled_hull(float(base),source_difficulty,float(data.difficulty_offset))
	var row: Dictionary=initial.actor
	var ships: Variant=catalogues.tables.get("ships")
	if not ships is Array or int(row.hull_catalogue_id)>=ships.size():return reject("Second pirate hull is absent from this catalogue")
	var model: String=bindings.resolve_ship_model(int(row.hull_catalogue_id))
	if model.is_empty():return reject(bindings.error)
	var actor:={"actor_id":int(row.actor_id),"actor_kind":int(row.actor_kind),"hull_catalogue_id":int(row.hull_catalogue_id),
		"hull_resource":model,"position":row.statistics_pose.origin,"current_hull":factory_hull}
	var common: Dictionary=bindings.opening_actors.npc_initialization
	if not _initialize_body(bindings,common,actor,source_difficulty,factory_hull,float(data.percentage_scale)):return false
	_state.campaign_cursor=int(data.campaign_cursor)
	if ControlDefinitions.parameters(bindings.full_hold_control):
		_state.model_draw_enabled=bool(bindings.full_hold_control.initial_model_draw_enabled)
		_state.node_draw_requested=bool(bindings.full_hold_control.initial_node_draw_requested)
		# The ordinary model factory's last child is the engine mesh. Its
		# instance starts drawable, separately from the actor and node gates.
		_state.engine_draw_enabled=true
	_state.hostile=bool(data.initial_hostile)
	_state.targeting_blocked=bool(row.targeting_blocked)
	_state.active=bool(row.active);_state.actor_mode=int(row.mode)
	return set_pose(row.statistics_pose)


func configure_combat_training(bindings: RefCounted, catalogues: RefCounted, world: RefCounted, actor_id: Variant, rank: Variant, difficulty: Variant) -> bool:
	clear()
	if bindings==null or catalogues==null or not world is TrainingWorld or not TrainingControl.parameters(bindings.combat_training_control):return reject("Combat-training bodies require verified world initialization")
	var data: Dictionary=bindings.combat_training_control
	if not actor_id is int or actor_id<0 or actor_id>=int(data.actor_count) or not rank is int or rank<0 or rank>1:return reject("Unsupported combat-training actor or entry rank")
	if (not difficulty is float and not difficulty is int) or not is_finite(difficulty) or difficulty<0 or difficulty>10:return reject("Combat training requires a finite source difficulty")
	var initial: Dictionary=world.snapshot()
	for key in ["base_content_id","binding_id"]:
		if not Library.valid_hash(bindings.get(key)) or initial.get(key)!=bindings.get(key):return reject("Combat-training initialization belongs to another content identity")
	if bindings.base_content_id!=catalogues.content_id or initial.get("campaign_cursor")!=data.campaign_cursor:return reject("Combat-training initialization belongs to another campaign context")
	var rows: Variant=initial.get("npc_construction",{}).get("actors")
	if not rows is Array or rows.size()!=int(data.actor_count):return reject("Combat-training population is incomplete")
	var row: Dictionary=rows[actor_id]
	if row.get("actor_id")!=actor_id or row.get("actor_kind")!=data.actor_kinds[actor_id] or row.get("hull_catalogue_id")!=data.hull_catalogue_ids[actor_id] or row.get("subtype")!=0:return reject("Combat-training actor identity changed")
	if not Flight.rigid_pose(row.get("body_pose")) or row.body_pose!=row.get("statistics_pose"):return reject("Combat-training actor poses disagree")
	var model: String=bindings.resolve_ship_model(int(row.hull_catalogue_id))
	if model.is_empty():return reject(bindings.error)
	var companion: bool=actor_id==int(bindings.combat_training.companion_actor_id)
	var source_difficulty:=Vitals.single(float(difficulty))
	var base: int=int(data.rank_base)+int(data.rank_multiplier)*rank+int(data.cursor_multiplier)*int(data.campaign_cursor)
	var factory_hull:=scaled_hull(float(base),source_difficulty,float(data.difficulty_offset))
	var actor:={"actor_id":actor_id,"actor_kind":int(row.actor_kind),"hull_catalogue_id":int(row.hull_catalogue_id),"hull_resource":model,"position":row.statistics_pose.origin,
		"current_hull":int(row.current_hull_override) if companion else factory_hull}
	var policy:={"initial_hostile":bool(data.companion_hostile if companion else data.pirate_initial_hostile),"updated_hostile":bool(data.companion_hostile if companion else data.pirate_updated_hostile)}
	if not _initialize_body(bindings,bindings.opening_actors.npc_initialization,actor,source_difficulty,factory_hull,float(data.percentage_scale),policy):return false
	_state.merge({"campaign_cursor":int(data.campaign_cursor),"rank":rank,"friendly":companion,
		"actor_mode":int(data.companion_mode) if companion else int(row.mode),"active":bool(data.companion_active) if companion else bool(row.active),
		"targeting_blocked":false if companion else bool(row.targeting_blocked),
		"statistics_targeting_blocked":bool(data.npc_statistics_targeting_blocked),"spatial_half_extent":int(data.engagement_half_extent),
		"model_draw_enabled":bool(data.initial_model_draw_enabled),"node_draw_requested":bool(data.initial_node_draw_requested),"engine_draw_enabled":bool(data.initial_engine_draw_enabled)},true)
	if companion:_state.name_text_id=int(row.name_text_id)
	_initial_training_death=companion and TrainingDeath.parameters(bindings.combat_training_destruction)
	return set_pose(row.statistics_pose,row.body_pose)

func configure_local_patrol(bindings: RefCounted, catalogues: RefCounted, world: RefCounted, actor_id: Variant, rank: Variant, difficulty: Variant) -> bool:
	clear()
	if not world is TrainingWorld or catalogues==null:return reject("Local patrol bodies require prepared source traffic")
	var data:=Travel.patrol(bindings,world.snapshot(),rank,difficulty)
	if data.is_empty() or bindings.base_content_id!=catalogues.content_id or not actor_id is int or actor_id<0 or actor_id>=int(data.actor_count):return reject("Unsupported local patrol population or context")
	var row: Dictionary=world.snapshot().npc_construction.actors[actor_id]
	if not Flight.rigid_pose(row.get("body_pose")) or row.body_pose!=row.get("statistics_pose"):return reject("Local patrol factory poses disagree")
	var model: String=bindings.resolve_ship_model(int(row.hull_catalogue_id))
	if model.is_empty():return reject(bindings.error)
	var base: int=int(data.rank_base)+int(data.rank_multiplier)*rank+int(data.cursor_multiplier)*int(data.campaign_cursor)
	var source_difficulty:=Vitals.single(float(difficulty))
	var factory_hull:=scaled_hull(float(base),source_difficulty,float(data.difficulty_offset))
	var actor:={"actor_id":actor_id,"actor_kind":int(row.actor_kind),"hull_catalogue_id":int(row.hull_catalogue_id),"hull_resource":model,"position":row.statistics_pose.origin,"current_hull":factory_hull}
	var policy:={"initial_hostile":bool(data.initial_hostile),"updated_hostile":bool(data.initial_hostile)}
	if not _initialize_body(bindings,bindings.opening_actors.npc_initialization,actor,source_difficulty,factory_hull,float(data.percentage_scale),policy):return false
	_state.merge({"campaign_cursor":int(data.campaign_cursor),"rank":rank,"friendly":bool(data.friendly),"local_patrol":true,
		"actor_mode":int(data.initial_actor_mode),"active":bool(data.initial_active),
		"targeting_blocked":bool(data.initial_actor_targeting_blocked),"statistics_targeting_blocked":bool(data.initial_statistics_targeting_blocked),
		"spatial_half_extent":int(data.engagement_half_extent),"model_draw_enabled":bool(data.initial_model_draw_enabled),
		"node_draw_requested":bool(data.initial_node_draw_requested),"engine_draw_enabled":bool(data.initial_engine_draw_enabled)},true)
	return set_pose(row.statistics_pose,row.body_pose)

func configure_ambient(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,actor_id: Variant,rank: Variant,difficulty: Variant) -> bool:
	clear()
	if not construction is NPCConstruction or catalogues==null:return reject("Ambient combat requires its generated population")
	var packet: Dictionary=construction.snapshot()
	var data:=AmbientCombat.population(bindings,packet,rank,difficulty)
	if data.is_empty() or catalogues.content_id!=bindings.base_content_id or not actor_id is int or actor_id<0 or actor_id>=data.actor_count:return reject("Unsupported ambient combat identity or context")
	var row: Dictionary=packet.actors[actor_id]
	if not Flight.rigid_pose(row.get("body_pose")) or row.body_pose!=row.get("statistics_pose"):return reject("Ambient actor poses disagree")
	var freight: bool=row.population_group=="freighter"
	var root_id: int=int(row.assembly.body_resource_ids[0] if data.has("free_traffic") else row.assembly.root_model_id) if freight else -1
	var model: String=bindings.resolve(root_id,"mesh") if freight else bindings.resolve_ship_model(int(row.hull_catalogue_id))
	if model.is_empty():return reject(bindings.error)
	var base: int=int(data.rank_base)+int(data.rank_multiplier)*rank+int(data.cursor_multiplier)*int(data.campaign_cursor)
	if freight:base*=int(data.freighter.hull_multiplier)
	var source_difficulty:=Vitals.single(float(difficulty))
	var factory_hull:=scaled_hull(float(base),source_difficulty,float(data.difficulty_offset))
	var actor:={"actor_id":actor_id,"actor_kind":int(row.actor_kind),"hull_catalogue_id":int(row.hull_catalogue_id),"hull_resource":model,"position":row.statistics_pose.origin,"current_hull":factory_hull}
	var policy:={"initial_hostile":bool(data.initial_hostile),"updated_hostile":row.actor_kind==8 if data.has("free_traffic") else bool(data.initial_hostile)}
	if not _initialize_body(bindings,bindings.opening_actors.npc_initialization,actor,source_difficulty,factory_hull,float(data.percentage_scale),policy):return false
	_state.merge({"campaign_cursor":int(data.campaign_cursor),"rank":rank,"friendly":bool(data.friendly),"ambient_traffic":true,
		"population_group":row.population_group,"subtype":int(row.subtype),"actor_mode":int(data.initial_actor_mode),"active":bool(data.initial_active),
		"targeting_blocked":bool(data.initial_actor_targeting_blocked),"statistics_targeting_blocked":bool(data.initial_statistics_targeting_blocked),
		"spatial_half_extent":int(data.engagement_half_extent),"model_draw_enabled":bool(data.initial_model_draw_enabled),
		"node_draw_requested":bool(data.initial_node_draw_requested),"engine_draw_enabled":bool(data.initial_engine_draw_enabled)},true)
	if data.has("free_traffic"):_state.free_traffic=true
	if freight:
		_state.point_boxes=[]
		var boxes: Array=data.freighter_boxes[row.actor_kind] if data.has("free_traffic") else data.freighter.boxes
		for box in boxes:
			_state.point_boxes.append({"offset":Vector3(box.offset[0],box.offset[1],box.offset[2]),"half_extents":Vector3(box.half_extents[0],box.half_extents[1],box.half_extents[2])})
		_state.point_box_index=0
	elif AmbientLife.parameters(bindings.ambient_lifecycle) and row.population_group=="travel":
		_state.actor_mode=int(bindings.ambient_lifecycle.initial_mode)
		_state.active=bool(bindings.ambient_lifecycle.initial_active)
		_state.travel_cycle=0
	if AmbientLife.recycling_parameters(bindings.ambient_lifecycle):_state.spawn_generation=0
	if not _configure_ordinary_systems(bindings,int(rank),int(row.subtype)):return false
	return set_pose(row.statistics_pose,row.body_pose)

func configure_convoy(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,actor_id: Variant) -> bool:
	clear()
	if not construction is NPCConstruction or catalogues==null:return reject("Convoy bodies require their generated original population")
	var packet: Dictionary=construction.snapshot()
	var data:=Convoy.population(bindings,packet)
	if data.is_empty() or catalogues.content_id!=bindings.base_content_id or not actor_id is int or actor_id<0 or actor_id>=data.actor_count:return reject("Unsupported convoy body identity or context")
	var row: Dictionary=packet.actors[actor_id]
	var capital: bool=row.population_group=="capital"
	var source: Dictionary=bindings.mido_travel.convoy_ship
	var model: String=bindings.resolve(int(source.assembly.body_resource_ids[0]),"mesh") if capital else bindings.resolve_ship_model(row.hull_catalogue_id)
	if model.is_empty():return reject(bindings.error)
	var base: int=int(data.rank_base)+int(data.rank_multiplier)*int(data.rank)+int(data.cursor_multiplier)*int(data.campaign_cursor)
	if capital:base*=int(source.combat.hull_multiplier)
	var factory_hull:=scaled_hull(float(base),float(data.difficulty),float(data.difficulty_offset))
	var initial:={"actor_id":actor_id,"actor_kind":row.actor_kind,"hull_catalogue_id":row.hull_catalogue_id,"hull_resource":model,"position":row.statistics_pose.origin,"current_hull":factory_hull}
	var policy:={"initial_hostile":bool(data.pirate_initial_hostile),"updated_hostile":bool(data.pirate_updated_hostile) if row.actor_kind==8 else false}
	if not _initialize_body(bindings,bindings.opening_actors.npc_initialization,initial,float(data.difficulty),factory_hull,float(data.percentage_scale),policy):return false
	var ordinary: Dictionary=bindings.mido_travel.traffic_control
	_state.merge({"campaign_cursor":int(data.campaign_cursor),"station_id":int(data.station_id),"rank":int(data.rank),"convoy":true,"convoy_script_retired":false,"convoy_phase":ConvoyCapture.Stage.INTERCEPTION,
		"population_group":row.population_group,"subtype":row.subtype,"friendly":bool(ordinary.friendly),"actor_mode":int(ordinary.initial_actor_mode),
		"active":bool(ordinary.initial_active),"targeting_blocked":bool(ordinary.initial_actor_targeting_blocked),"statistics_targeting_blocked":bool(data.npc_statistics_targeting_blocked),
		"spatial_half_extent":int(data.engagement_half_extent),"model_draw_enabled":bool(data.initial_model_draw_enabled),"node_draw_requested":bool(data.initial_node_draw_requested),"engine_draw_enabled":bool(data.initial_engine_draw_enabled)},true)
	if capital:
		_state.point_boxes=ConvoyShip.boxes(bindings);_state.point_box_index=0
	var capture: Dictionary=bindings.mido_travel.convoy_capture
	_state.convoy_retirement={"first_actor":int(capture.first_pulse_actor_id),"actor_kind":int(capture.disabled_actor_kind),"mode":int(capture.retired_actor_mode),"active":bool(capture.retired_actor_active),"hull":int(capture.retired_actor_hull)}
	_initial_training_death=true
	return set_pose(row.statistics_pose,row.body_pose)

func enable_convoy_combat() -> bool:
	if not _state.get("convoy",false):return reject("Convoy combat requires its generated body")
	_state.local_combat=true;_state.forced_hostile=false
	return true

func configure_kappa_rescue(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,actor_id: Variant) -> bool:
	clear()
	if not construction is NPCConstruction or catalogues==null:return reject("Kappa bodies require their generated rescue population")
	var packet: Dictionary=construction.snapshot()
	var data:=Kappa.population(bindings,packet)
	if data.is_empty() or catalogues.content_id!=bindings.base_content_id or not actor_id is int or actor_id<0 or actor_id>=data.actor_count:return reject("Unsupported Kappa body identity or context")
	var row: Dictionary=packet.actors[actor_id]
	var model: String=bindings.resolve_ship_model(row.hull_catalogue_id)
	if model.is_empty():return reject(bindings.error)
	var base: int=int(data.rank_base)+int(data.rank_multiplier)*int(data.rank)+int(data.cursor_multiplier)*int(data.campaign_cursor)
	var hull:=scaled_hull(float(base),float(data.difficulty),float(data.difficulty_offset))
	var rules:=KappaFighters.systems(bindings,int(data.rank))
	var systems:=ShipSystems.new()
	if rules.is_empty() or not systems.configure(bindings,rules.capacity,rules.recovery_ms):return reject("Kappa systems initialization is unavailable")
	var initial:={"actor_id":actor_id,"actor_kind":row.actor_kind,"hull_catalogue_id":row.hull_catalogue_id,"hull_resource":model,"position":row.statistics_pose.origin,"current_hull":hull}
	var policy:={"initial_hostile":row.script_hostile,"updated_hostile":row.script_hostile}
	if not _initialize_body(bindings,bindings.opening_actors.npc_initialization,initial,float(data.difficulty),hull,float(data.percentage_scale),policy):return false
	_systems=systems
	_state.merge({"campaign_cursor":int(data.campaign_cursor),"station_id":int(data.station_id),"rank":int(data.rank),"kappa_rescue":true,
		"population_group":"fighter","subtype":row.subtype,"friendly":false,"permanent_friendly":row.permanent_friendly,"scenery":false,
		"script_hostile":row.script_hostile,"systems_disabled":false,"systems_hit_serial":0,"actor_mode":row.mode,"active":row.active,
		"targeting_blocked":bool(data.initial_actor_targeting_blocked),"statistics_targeting_blocked":bool(data.npc_statistics_targeting_blocked),
		"spatial_half_extent":int(data.engagement_half_extent),"model_draw_enabled":bool(data.initial_model_draw_enabled),
		"node_draw_requested":bool(data.initial_node_draw_requested),"engine_draw_enabled":bool(data.initial_engine_draw_enabled)},true)
	if row.has("name_text_id"):_state.name_text_id=row.name_text_id
	return set_pose(row.statistics_pose,row.body_pose)

func enable_kappa_combat() -> bool:
	if not _state.get("kappa_rescue",false):return reject("Kappa combat requires its generated body")
	_state.local_combat=true;_state.forced_hostile=_state.script_hostile
	return true

func retain_kappa_force(forced: bool,persistent: bool) -> bool:
	if not _state.get("kappa_rescue",false) or not _state.get("local_combat",false) or (_state.script_hostile and not persistent):return reject("Kappa reactions lost persistent mission hostility")
	_state.forced_hostile=forced;_state.script_hostile=persistent
	if persistent:_state.hostile=true;_state.friendly=false
	return true

func refresh_kappa_hostility(reputation: Dictionary,forced: bool,persistent: bool,rules: Dictionary) -> bool:
	if not retain_kappa_force(forced,persistent):return false
	var standing: int=reputation.axes[int(rules.axis)]
	_state.hostile=persistent or forced or standing<int(rules.hostile_below)
	_state.friendly=not persistent and not forced and standing>int(rules.friendly_above)
	return true

func apply_kappa_guidance(decision: Dictionary) -> bool:
	if not _state.get("kappa_rescue",false):return reject("Kappa guidance requires its generated fighter")
	return _apply_guidance_activity(decision,true)

func apply_kappa_hostile_cue(owner: RefCounted) -> bool:
	if not _state.get("kappa_rescue",false) or not owner is KappaRescue:return reject("Kappa hostility requires its rescue sequence")
	var sequence: Dictionary=owner.snapshot()
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if sequence.get(key)!=_state[key]:return reject("Kappa hostility belongs to another encounter")
	if sequence.force_hostile_actor_ids.has(_state.actor_id):
		_state.script_hostile=true;_state.hostile=true;_state.friendly=false
		_hostility.updated_hostile=true
	return true

func systems_hit(amount: Variant) -> Dictionary:
	# This is the damage-pool transaction. The encounter stages faction reactions
	# separately before committing a frame, just as for ordinary hull hits.
	error=""
	if _systems==null:return fail_hit("This actor has no supported systems pool")
	if _state.systems_hit_serial>=Vitals.MAX_INTEGER:return fail_hit("Systems hit serial limit reached")
	var result: Dictionary=_systems.hit(amount,_vitals.snapshot().hull,_state.active,_state.damage_allowed)
	if result.is_empty():return fail_hit(_systems.error)
	if result.accepted:_state.systems_hit_serial+=1
	if result.accepted and result.after.integrity==0 and _state.has("systems_motion_ms"):
		_state.systems_motion_ms=float(result.after.recovery_ms)
	return result

func advance_systems(delta_ms: Variant) -> bool:
	error=""
	if _systems==null or not Vitals.integer(delta_ms):return reject("This actor has no supported systems recovery frame")
	var freighter: bool=_state.get("population_group")=="freighter"
	if not freighter and _state.actor_mode in [3,4]:return true
	if not _systems.advance(delta_ms):return reject(_systems.error)
	if freighter and _state.systems_motion_ms>0.0:
		_state.systems_motion_ms=maxf(0.0,Vitals.single(_state.systems_motion_ms-float(delta_ms)))
	# Radio reads the NPC projection, updated during the actor pass. A pulse
	# changes statistics first; it must not fabricate an earlier radio event.
	if freighter:_state.systems_disabled=_state.systems_motion_ms>0.0
	elif _state.actor_mode!=6:_state.systems_disabled=bool(_systems.snapshot().disabled)
	return true

func systems_for_frame() -> RefCounted:
	return null if _systems==null else _systems.fork()

func _configure_ordinary_systems(bindings: RefCounted,rank: int,subtype: int) -> bool:
	if not NPCSystems.available(bindings):return true
	var rules:=NPCSystems.systems(bindings,rank,subtype)
	var systems:=ShipSystems.new()
	if rules.is_empty() or not systems.configure(bindings,rules.capacity,rules.recovery_ms):return reject("Ordinary systems initialization is unavailable")
	_systems=systems
	_state.merge({"systems_disabled":false,"systems_hit_serial":0,"script_hostile":false,"scenery":false,"permanent_friendly":false},true)
	if subtype==1:_state.systems_motion_ms=0.0
	return true

func retain_ordinary_force(forced: bool,persistent: bool) -> bool:
	if _systems==null or not (_state.get("ambient_traffic",false) or _state.get("authored_story",false)) or (_state.script_hostile and not persistent):return reject("Ordinary reactions lost persistent faction hostility")
	if not retain_local_force(forced):return false
	_state.script_hostile=persistent
	if persistent:_state.hostile=true;_state.friendly=false
	return true

func _configure_story(bindings: RefCounted,data: Dictionary,row: Dictionary) -> bool:
	clear()
	var freight: bool=row.population_group=="freighter"
	var model: String=bindings.resolve(int(row.assembly.body_resource_ids[0]),"mesh") if freight else bindings.resolve_ship_model(int(row.hull_catalogue_id))
	if model.is_empty():return reject(bindings.error)
	var base:=int(data.rank_base)+int(data.rank_multiplier)*int(data.rank)+int(data.cursor_multiplier)*int(data.campaign_cursor)
	if freight:base*=int(data.freighter.hull_multiplier)
	var factory_hull:=scaled_hull(float(base),float(data.difficulty),float(data.difficulty_offset))
	var current_hull:=factory_hull
	for divisor in row.get("hull_divisors",[]):
		@warning_ignore("integer_division")
		current_hull=current_hull/int(divisor)
	var initial:={"actor_id":row.actor_id,"actor_kind":row.actor_kind,"hull_catalogue_id":row.hull_catalogue_id,
		"hull_resource":model,"position":row.statistics_pose.origin,"current_hull":current_hull}
	var policy:={"initial_hostile":bool(data.initial_hostile),"updated_hostile":row.actor_kind==9}
	if not _initialize_body(bindings,bindings.opening_actors.npc_initialization,initial,float(data.difficulty),factory_hull,float(data.percentage_scale),policy):return false
	_state.max_hull=current_hull
	_state.merge({"campaign_cursor":int(data.campaign_cursor),"station_id":int(data.station_id),"rank":int(data.rank),"authored_story":true,
		"population_group":row.population_group,"subtype":row.subtype,"friendly":bool(data.friendly),
		"actor_mode":int(data.initial_actor_mode),"active":bool(data.initial_active),
		"targeting_blocked":bool(data.initial_actor_targeting_blocked),"statistics_targeting_blocked":bool(data.initial_statistics_targeting_blocked),
		"spatial_half_extent":int(data.engagement_half_extent),"model_draw_enabled":bool(data.initial_model_draw_enabled),
		"node_draw_requested":bool(data.initial_node_draw_requested),"engine_draw_enabled":bool(data.initial_engine_draw_enabled),
		"local_combat":true,"forced_hostile":false},true)
	_initial_training_death=true
	if freight:
		_state.point_boxes=data.freighter.boxes.map(func(box):return {"offset":Vector3(box.offset[0],box.offset[1],box.offset[2]),"half_extents":Vector3(box.half_extents[0],box.half_extents[1],box.half_extents[2])})
		_state.point_box_index=0
	if not _configure_ordinary_systems(bindings,int(data.rank),int(row.subtype)):return false
	return set_pose(row.statistics_pose,row.body_pose)

func apply_story_guidance(decision: Dictionary) -> bool:
	if not _state.get("authored_story",false) or _state.population_group!="fighter":return reject("Story guidance requires its retained fighter")
	return _apply_guidance_activity(decision,true)

func configure_alioth_attack(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,actor_id: Variant) -> bool:
	clear()
	if not construction is NPCConstruction or catalogues==null:return reject("Alioth bodies require their generated original population")
	var packet: Dictionary=construction.snapshot()
	var data:=Alioth.population(bindings,packet)
	if data.is_empty() or catalogues.content_id!=bindings.base_content_id or not actor_id is int or actor_id<0 or actor_id>=data.actor_count:return reject("Unsupported Alioth body identity or context")
	var row: Dictionary=packet.actors[actor_id]
	var source: Dictionary=bindings.mido_travel.alioth_attack
	var freight: bool=row.population_group=="freighter"
	var model: String=bindings.resolve(int(row.assembly.body_resource_ids[0]),"mesh") if freight else bindings.resolve_ship_model(row.hull_catalogue_id)
	if model.is_empty():return reject(bindings.error)
	var base: int=int(data.rank_base)+int(data.rank_multiplier)*int(data.rank)+int(data.cursor_multiplier)*int(data.campaign_cursor)
	if freight:base*=int(source.population.freighter_combat.hull_multiplier)
	var factory_hull:=scaled_hull(float(base),float(data.difficulty),float(data.difficulty_offset))
	var current_hull:=factory_hull
	if freight:
		for divisor in row.hull_divisors:
			@warning_ignore("integer_division")
			current_hull=current_hull/int(divisor)
	elif row.actor_kind==9:current_hull*=int(source.population.void_hull_multiplier)
	else:current_hull=int(row.current_hull_override)
	var initial:={"actor_id":actor_id,"actor_kind":row.actor_kind,"hull_catalogue_id":row.hull_catalogue_id,"hull_resource":model,"position":row.statistics_pose.origin,"current_hull":current_hull}
	# Kind8/9 share unconditional hostility. Alioth's Terran actors retain
	# the mission's forced friendship through later standing/provocation updates.
	var policy:={"initial_hostile":bool(data.initial_hostile),"updated_hostile":row.actor_kind==9}
	if not _initialize_body(bindings,bindings.opening_actors.npc_initialization,initial,float(data.difficulty),factory_hull,float(data.percentage_scale),policy):return false
	# The freighter/ Void setters replace both hull values. The escort setter
	# replaces current hull and raises capacity only when necessary.
	if freight or row.actor_kind==9:_state.max_hull=current_hull
	_state.merge({"campaign_cursor":int(data.campaign_cursor),"station_id":int(data.station_id),"rank":int(data.rank),"alioth_attack":true,
		"alioth_phase":AliothAttack.Stage.ATTACK,"alioth_elapsed_ms":0,"alioth_script_retired":false,
		"population_group":row.population_group,"subtype":row.subtype,"friendly":bool(row.get("friendly",data.friendly)),
		"actor_mode":int(data.initial_actor_mode),"active":bool(data.initial_active),
		"targeting_blocked":bool(data.initial_actor_targeting_blocked),"statistics_targeting_blocked":bool(data.initial_statistics_targeting_blocked),
		"spatial_half_extent":int(data.engagement_half_extent),"model_draw_enabled":bool(data.initial_model_draw_enabled),
		"node_draw_requested":bool(data.initial_node_draw_requested),"engine_draw_enabled":bool(data.initial_engine_draw_enabled)},true)
	if freight:
		_state.point_boxes=source.population.freighter_combat.boxes.map(func(box):return {"offset":AliothAttack.vec(box.offset),"half_extents":AliothAttack.vec(box.half_extents)})
		_state.point_box_index=0
	_state.alioth_retirement={"actor_kind":int(source.choreography.escaping_actor_kind),"mode":int(source.choreography.retire_mode),
		"active":bool(source.choreography.retire_active),"visible":bool(source.choreography.retire_visible)}
	return set_pose(row.statistics_pose,row.body_pose)

func enable_alioth_combat() -> bool:
	if not _state.get("alioth_attack",false):return reject("Alioth combat requires its generated body")
	_state.local_combat=true;_state.forced_hostile=false;_initial_training_death=true
	return true

func refresh_alioth_hostility(forced: bool) -> bool:
	if not _state.get("alioth_attack",false) or not _state.get("local_combat",false):return reject("Alioth hostility requires connected combat")
	# The mission's persistent friendship overrides standing AND retaliation.
	# The requested-damage/force history still belongs to the normal hit owner.
	_state.forced_hostile=forced;_state.hostile=bool(_hostility.updated_hostile)
	_state.friendly=not _state.hostile
	return true

func apply_alioth_guidance(decision: Dictionary) -> bool:
	if not _state.get("alioth_attack",false) or _state.population_group!="fighter":return reject("Alioth guidance requires a small ship")
	return _apply_guidance_activity(decision,true)

func apply_alioth_retirement(owner: RefCounted) -> bool:
	error=""
	if not _state.get("alioth_attack",false) or not owner is AliothAttack:return reject("Alioth retirement requires its native body and sequence")
	var sequence: Dictionary=owner.snapshot()
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if sequence.get(key)!=_state[key]:return reject("Alioth retirement belongs to another encounter")
	if sequence.phase<_state.alioth_phase or sequence.elapsed_ms<_state.alioth_elapsed_ms:return reject("Alioth retirement cannot regress")
	var rules: Dictionary=_state.alioth_retirement
	if sequence.phase>=AliothAttack.Stage.FAREWELL and _state.actor_kind==rules.actor_kind:
		# Scripted escape changes visibility and activity, not vitals or hit
		# attribution. A living escaped ship must not count as a combat kill.
		_state.actor_mode=rules.mode;_state.active=rules.active
		_state.model_draw_enabled=rules.visible;_state.node_draw_requested=rules.visible
		_state.alioth_script_retired=true
	_state.alioth_phase=sequence.phase;_state.alioth_elapsed_ms=sequence.elapsed_ms
	return true

func refresh_convoy_hostility(reputation: Dictionary,forced: bool,rules: Dictionary) -> bool:
	if not _state.get("convoy",false) or not _state.get("local_combat",false):return reject("Convoy hostility requires connected combat")
	if _state.actor_kind==8:
		_state.hostile=bool(_hostility.updated_hostile);_state.friendly=false
	else:
		# Terran standing is the opposite end of axis zero. The shared source
		# predicates use strict thresholds, including a neutral boundary at 70.
		var standing: int=reputation.axes[int(rules.axis)]
		_state.hostile=forced or standing<int(rules.hostile_below)
		_state.friendly=not forced and standing>int(rules.friendly_above)
	_state.forced_hostile=forced
	return true

func apply_convoy_guidance(decision: Dictionary) -> bool:
	if not _state.get("convoy",false) or _state.population_group!="fighter":return reject("Convoy guidance requires a small ship")
	return _apply_guidance_activity(decision,true)

func apply_convoy_capture(owner: RefCounted) -> bool:
	error=""
	if not _state.get("convoy",false) or not owner is ConvoyCapture:return reject("Capture retirement requires its native convoy actors and choreography")
	var state: Dictionary=owner.snapshot()
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if state.get(key)!=_state[key]:return reject("Capture retirement belongs to another encounter")
	if state.phase<int(_state.convoy_phase):return reject("Capture retirement cannot regress")
	# The original story retires pirates directly. It does not inflict a
	# projectile hit, assign kill credit or trigger a new destruction reward.
	var rules: Dictionary=_state.convoy_retirement
	var retired: bool=state.phase>=ConvoyCapture.Stage.PULSE and _state.actor_id==rules.first_actor
	retired=retired or (state.phase>=ConvoyCapture.Stage.DISABLED and _state.actor_kind==rules.actor_kind)
	if retired:
		var pools: Dictionary=_vitals.snapshot()
		_vitals.configure(rules.hull,pools.armor,pools.shield)
		_state.actor_mode=rules.mode;_state.active=rules.active;_state.convoy_script_retired=true
	_state.convoy_phase=state.phase
	return true

func configure_contract(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,actor_id: Variant) -> bool:
	clear()
	if not construction is NPCConstruction or catalogues==null:return reject("Contract ship bodies require their generated accepted population")
	var packet: Dictionary=construction.snapshot()
	if packet.get("contract_encounter",{}).get("kind")==7:return _configure_debris(bindings,catalogues,packet,actor_id)
	var data:=ContractCombat.population(bindings,packet)
	if data.is_empty() or catalogues.content_id!=bindings.base_content_id or not actor_id is int or actor_id<0 or actor_id>=data.actor_count:return reject("Unsupported contract ship population or identity")
	var row: Dictionary=packet.actors[actor_id]
	if not Flight.rigid_pose(row.get("body_pose")) or row.body_pose!=row.get("statistics_pose"):return reject("Contract ship factory poses disagree")
	var model: String=bindings.resolve_ship_model(int(row.hull_catalogue_id))
	if model.is_empty():return reject(bindings.error)
	var rival: bool=row.population_group=="rival"
	var base: int=int(data.rank_base)+int(data.rank_multiplier)*int(data.rank)+int(data.cursor_multiplier)*int(data.campaign_cursor)
	var factory_hull:=scaled_hull(float(base),float(data.difficulty),float(data.difficulty_offset))
	var initial:={"actor_id":actor_id,"actor_kind":int(row.actor_kind),"hull_catalogue_id":int(row.hull_catalogue_id),
		"hull_resource":model,"position":row.statistics_pose.origin,"current_hull":int(row.current_hull_override) if rival else factory_hull}
	var policy: Dictionary=data.rival if rival else data.pirate
	if not _initialize_body(bindings,bindings.opening_actors.npc_initialization,initial,float(data.difficulty),factory_hull,float(data.percentage_scale),policy):return false
	_state.merge({"campaign_cursor":int(data.campaign_cursor),"station_id":int(data.station_id),"rank":int(data.rank),"contract_ship":true,
		"population_group":row.population_group,"subtype":int(row.subtype),"friendly":bool(policy.friendly),"actor_mode":int(data.rival.initial_mode) if rival else int(row.mode),
		"active":bool(data.rival.initial_active) if rival else bool(row.active),"targeting_blocked":bool(data.rival.initial_targeting_blocked) if rival else bool(row.targeting_blocked),
		"statistics_targeting_blocked":bool(data.npc_statistics_targeting_blocked),"spatial_half_extent":int(data.engagement_half_extent),
		"model_draw_enabled":bool(data.initial_model_draw_enabled),"node_draw_requested":bool(data.initial_node_draw_requested),"engine_draw_enabled":bool(data.initial_engine_draw_enabled)},true)
	if rival:_state.name=row.name
	return set_pose(row.statistics_pose,row.body_pose)

func _configure_debris(bindings: RefCounted,catalogues: RefCounted,packet: Dictionary,actor_id: Variant) -> bool:
	var data:=Junk.population(bindings,packet)
	if data.is_empty() or catalogues.content_id!=bindings.base_content_id or not actor_id is int or actor_id<0 or actor_id>=data.actor_count:return reject("Unsupported contract debris population or identity")
	var row: Dictionary=packet.actors[actor_id]
	if row.body_pose.basis!=Basis.IDENTITY:return reject("Contract debris requires its stationary source pose")
	var model: String=bindings.resolve(int(row.resource_id),"mesh")
	if model.is_empty():return reject(bindings.error)
	var initial:={"actor_id":actor_id,"actor_kind":int(row.actor_kind),"hull_catalogue_id":-1,
		"hull_resource":model,"position":row.statistics_pose.origin,"current_hull":int(row.hull)}
	if not _initialize_body(bindings,bindings.opening_actors.npc_initialization,initial,float(data.difficulty),int(row.hull),float(bindings.combat_training_control.percentage_scale),{"initial_hostile":true,"updated_hostile":true}):return false
	var rules: Dictionary=data.lifecycle
	_state.merge({"campaign_cursor":int(data.campaign_cursor),"station_id":int(data.station_id),"rank":int(data.rank),"contract_debris":true,
		"resource_id":int(row.resource_id),"population_group":"debris","friendly":bool(row.friendly),
		"actor_mode":int(row.mode),"active":bool(rules.initial_active),"targeting_blocked":bool(rules.initial_targeting_blocked),
		"half_extent":int(row.half_extent),"spatial_half_extent":int(row.half_extent),
		"model_draw_enabled":bool(rules.initial_model_draw_enabled)},true)
	return set_pose(row.statistics_pose,row.body_pose)

func apply_contract_guidance(decision: Dictionary) -> bool:
	error=""
	if not _state.get("contract_ship",false):return reject("Contract guidance requires its prepared ship body")
	return _apply_guidance_activity(decision,true)

func enable_contract_combat(bindings: RefCounted) -> bool:
	var supported: bool=Junk.available(bindings) if _state.get("contract_debris",false) else _state.get("contract_ship",false) and ContractLife.available(bindings)
	if not supported:return reject("Contract damage requires verified lifecycle declarations")
	if bindings.base_content_id!=_state.base_content_id or bindings.binding_id!=_state.binding_id:return reject("Contract lifecycle belongs to another content pack")
	_state.contract_combat=true;_state.forced_hostile=false
	return true

func refresh_contract_hostility(forced: bool) -> bool:
	if not _state.get("contract_combat",false):return reject("Contract hostility requires connected combat reactions")
	_state.forced_hostile=forced
	# The rival's authored friendship takes precedence over faction provocation.
	return refresh_hostility()

func relaunch_ambient(bindings: RefCounted,death_owner: RefCounted=null) -> bool:
	error=""
	if bindings==null or not AmbientLife.parameters(bindings.ambient_lifecycle):return reject("Traffic launch requires supported lifecycle declarations")
	var recycling:=AmbientLife.recycling_parameters(bindings.ambient_lifecycle)
	if _state.get("population_group") not in (["patrol","travel"] if recycling else ["travel"]):return reject("Traffic launch requires a supported small ship")
	for key in ["base_content_id","binding_id"]:
		if _state.get(key)!=bindings.get(key):return reject("Traffic launch belongs to another content identity")
	if _state.actor_mode!=int(bindings.ambient_lifecycle.initial_mode) or _state.active:return reject("Only inactive traffic can relaunch")
	if _vitals.snapshot().hull==0:
		if not recycling or not death_owner is SmallShipDeath:return reject("Destroyed traffic requires its retired native death owner")
		var death: Dictionary=death_owner.snapshot()
		for key in ["base_content_id","binding_id","campaign_cursor","actor_id","spawn_generation"]:
			if death.get(key)!=_state.get(key):return reject("Retired traffic belongs to another instance")
		if death.get("phase")!="retired" or death.get("mode")!=4 or death.get("pose")!=_state.body_pose or death.get("statistics_pose")!=_state.pose:return reject("Traffic destruction has not finished retiring")
	elif death_owner!=null:return reject("A surviving ship cannot borrow a destruction owner")
	if recycling and (not _state.get("spawn_generation") is int or _state.spawn_generation>=2147483647):return reject("Traffic instance counter is exhausted")
	var pools:=Vitals.new()
	if not pools.configure(_state.max_hull,0,0.0):return reject(pools.error)
	var root: Transform3D=_state.body_pose
	root.origin=Vector3.ZERO
	var banked: Transform3D=root if recycling else _state.pose
	banked.origin=Vector3.ZERO
	if not set_pose(banked,root):return false
	_vitals=pools;_state.actor_mode=int(bindings.ambient_lifecycle.launch_mode);_state.active=true
	_state.statistics_targeting_blocked=false;_state.nonplayer_kill=false
	_state.contact=false;_state.impact_vector=Vector3.ZERO
	_state.engine_draw_enabled=true;_state.node_draw_requested=true;_state.model_draw_enabled=true
	if _state.has("travel_cycle"):_state.travel_cycle+=1
	if recycling:_state.spawn_generation+=1
	if _systems!=null:
		var systems: Dictionary=_systems.snapshot()
		if not _systems.configure(bindings,systems.capacity,systems.recovery_ms):return reject(_systems.error)
		_state.systems_disabled=false
	return true

func apply_ambient_guidance(decision: Dictionary) -> bool:
	error=""
	if not _state.get("ambient_traffic",false) or _state.get("population_group")=="freighter":return reject("Ambient guidance requires its small-ship body")
	for key in ["base_content_id","binding_id","campaign_cursor","actor_id"]:
		if decision.get(key)!=_state.get(key):return reject("Ambient guidance belongs to another actor")
	if decision.get("traffic_departure",false):
		if not _state.has("travel_cycle") or not _state.active or _state.actor_mode not in [1,6] or _vitals.snapshot().hull==0 or not decision.get("traffic_parked") is bool:return reject("Invalid outbound traffic transition")
		_state.actor_mode=4 if decision.traffic_parked else 6
		if decision.traffic_parked:_state.active=false
		return true
	if decision.get("traffic_waiting",false):return _state.get("travel_cycle",-1)>=0 and not _state.active and _state.actor_mode==4 and _vitals.snapshot().hull>0
	return _apply_guidance_activity(decision,true)

func apply_ambient_departure_pose(root: Variant) -> bool:
	error=""
	if not _state.has("travel_cycle") or _state.actor_mode not in [4,6] or _vitals.snapshot().hull==0 or not Flight.rigid_pose(root):return reject("Departure motion requires a living outbound traffic ship")
	_state.body_pose=root
	return true

static func full_hold_initial(bindings: RefCounted, catalogues: RefCounted, construction: RefCounted) -> Dictionary:
	if bindings==null or catalogues==null or not construction is Construction:return {}
	if not Library.valid_hash(bindings.base_content_id) or not Library.valid_hash(bindings.binding_id) or bindings.base_content_id!=catalogues.content_id:return {}
	if not FullHold.parameters(bindings.full_hold_pirate):return {}
	var data: Dictionary=bindings.full_hold_pirate
	var world: Dictionary=construction.snapshot()
	for key in ["base_content_id","binding_id"]:
		if world.get(key)!=bindings.get(key):return {}
	if world.get("campaign_cursor")!=data.campaign_cursor or world.get("activated")!=false:return {}
	var progress: Dictionary=world.get("departure",{}).get("progress",{})
	if progress.get("campaign_cursor")!=data.campaign_cursor or not Vitals.integer(progress.get("rank")) or progress.rank>1:return {}
	var rows: Variant=world.get("scenery",{}).get("world_initialization",{}).get("npc_construction",{}).get("actors")
	if not rows is Array or rows.size()!=1 or not rows[0] is Dictionary:return {}
	var row: Dictionary=rows[0]
	for key in ["actor_id","actor_kind","hull_catalogue_id","subtype"]:
		if row.get(key)!=data[key]:return {}
	if row.get("active")!=false or row.get("mode")!=5 or row.get("targeting_blocked")!=true:return {}
	var pose: Variant=row.get("statistics_pose")
	if not pose is Transform3D or not pose.is_finite() or pose!=row.get("body_pose"):return {}
	return {"actor":row.duplicate(true),"rank":int(progress.rank)}

static func scaled_hull(base_hull: float, difficulty: float, offset: float) -> int:
	var base:=Vitals.single(base_hull)
	var adjustment:=Vitals.single(difficulty+offset)
	return int(Vitals.single(Vitals.single(adjustment*base)+base))

func _initialize_body(bindings: RefCounted, data: Dictionary, actor: Dictionary, source_difficulty: float, factory_hull: int, percentage_scale: float, encounter_hostility: Dictionary={}) -> bool:
	if not Definitions.parameters(data) or data.is_player or data.initial_point_geometry or data.initial_special_impact_state:
		return reject("Unsupported ordinary NPC initialization")
	var vitals:=Vitals.new()
	if not vitals.configure(actor.current_hull,int(data.initial_armor),float(data.initial_shield)):return reject(vitals.error)
	# Encounter construction supplies source-space position. Live flight owns pose.
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"actor_id":actor.actor_id,"hull_catalogue_id":actor.hull_catalogue_id,"hull_resource":actor.hull_resource,
		"actor_kind":actor.actor_kind,"difficulty":source_difficulty,
		# The base NPC constructor clears actor+0x5E. Its only recovered set is
		# the separate faction-zero random-world group, absent from these
		# supported construction records. The radar music mark requires this bit
		# AND statistics/root+0xF8, so later root hostility cannot mark this body.
		"radar_marked_actor":false,
		"half_extent":int(data.special_half_extent if source_difficulty==Vitals.single(float(data.special_difficulty)) else data.ordinary_half_extent),
		"position":actor.position,"pose":Transform3D(Basis.IDENTITY,actor.position),"active":data.initial_active,
		"damage_allowed":data.initial_damage_allowed,"firing_allowed":data.initial_firing_allowed,
		"collision_enabled":data.initial_collision_enabled,"contact":false,"impact_vector":Vector3.ZERO}
	_vitals=vitals
	if factory_hull>=0:
		_state.factory_hull=factory_hull
		_state.max_hull=maxi(factory_hull,actor.current_hull)
		_hull_percentage_scale=percentage_scale
	var holding: Variant = data.get("holding",{})
	if not holding is Dictionary or (not holding.is_empty() and not Holding.parameters(holding)):
		clear()
		return reject("Unsupported opening NPC holding state")
	if not holding.is_empty():
		_state.actor_mode=int(holding.actor_mode)
		_state.spatial_half_extent=int(holding.spatial_half_extent)
	var hostility: Variant=data.get("hostility",{})
	if not hostility is Dictionary or (not hostility.is_empty() and (not Hostility.parameters(hostility) or (encounter_hostility.is_empty() and actor.actor_kind!=hostility.actor_kind))):
		clear()
		return reject("Unsupported opening NPC hostility")
	if not hostility.is_empty():
		_hostility=hostility.duplicate(true)
		_state.hostile=hostility.initial_hostile
	if not encounter_hostility.is_empty():
		_hostility=encounter_hostility.duplicate(true)
		_state.hostile=bool(_hostility.initial_hostile)
	var accounting: Variant=data.get("death_accounting",{})
	if not accounting is Dictionary or (not accounting.is_empty() and not DeathAccounting.parameters(accounting)):
		clear()
		return reject("Unsupported NPC hit attribution")
	if not accounting.is_empty(): _state.nonplayer_kill=accounting.initial_nonplayer_kill
	return true

func refresh_hostility() -> bool:
	error=""
	if _state.is_empty() or _hostility.is_empty(): return reject("Fresh NPC hostility is unavailable")
	# The source updates this flag before the holding/activity decision.
	_state.hostile=_hostility.updated_hostile
	return true

func enable_local_combat() -> bool:
	if not _state.get("local_patrol",false) and not _state.get("ambient_traffic",false):return reject("Local combat requires its generated body")
	_state.local_combat=true;_state.forced_hostile=false
	return true

func apply_local_hostility(reputation: Dictionary, forced: bool, rules: Dictionary) -> bool:
	if not _state.get("local_combat",false):return reject("Local hostility requires connected combat reactions")
	var value: int=reputation.axes[int(rules.axis)]
	var hostile: bool=forced or _state.get("script_hostile",false)
	_state.hostile=hostile or value>int(rules.hostile_above)
	_state.friendly=not hostile and value<int(rules.friendly_below)
	_state.forced_hostile=forced
	return true

func apply_free_hostility(reputation: Dictionary,forced: bool,rules: Dictionary) -> bool:
	if not (_state.get("free_traffic",false) or _state.get("authored_story",false)) or not _state.get("local_combat",false):return reject("Ordinary hostility requires connected faction reactions")
	if _state.get("authored_story",false) and _state.actor_kind==9:
		_state.hostile=true;_state.friendly=false;_state.forced_hostile=forced
		return true
	var standing:=FreeLife.standing(rules,int(_state.actor_kind),reputation,forced or _state.get("script_hostile",false))
	if standing.is_empty():return reject("Unsupported ordinary faction standing")
	_state.merge(standing,true);_state.forced_hostile=forced
	return true

func retain_local_force(forced: bool) -> bool:
	if not _state.get("local_combat",false) and not _state.get("contract_combat",false):return reject("Local force requires connected combat reactions")
	# The hit changes the force flag now; ordinary actor update refreshes the
	# displayed/targeting hostility later in the same frame.
	_state.forced_hostile=forced
	return true

func snapshot() -> Dictionary:
	if _state.is_empty(): return {}
	var result := _state.duplicate(true)
	result.vitals = _vitals.snapshot()
	if _systems!=null:result.systems=_systems.snapshot()
	if _state.has("max_hull"):
		var fraction := Vitals.single(Vitals.single(float(result.vitals.hull))/Vitals.single(float(result.max_hull)))
		result.hull_percent=int(Vitals.single(fraction*_hull_percentage_scale))
	return result

## Mission/radio predicates need current NPC flags, not projectile, pose or
## systems-pool snapshots. In particular the projected stun flag can lag a hit.
func kappa_observation() -> Dictionary:
	if not _state.get("kappa_rescue",false):return {}
	var result:={}
	for key in ["actor_id","actor_kind","hull_catalogue_id","actor_mode","hostile","scenery","active","friendly","systems_disabled"]:
		result[key]=_state[key]
	result.current_hull=int(_vitals.snapshot().hull)
	return result

func apply_scene(scene: Variant) -> bool:
	error = ""
	if _state.is_empty() or not scene is Dictionary or scene.get("base_content_id") != _state.base_content_id or scene.get("binding_id") != _state.binding_id:
		return reject("Actor scene must belong to its configured content and bindings")
	var actors: Variant = scene.get("actors")
	if not actors is Array: return reject("Actor scene has no authored population")
	var selected := {}
	for actor in actors:
		if not actor is Dictionary or not actor.get("actor_id") is int: return reject("Invalid actor scene row")
		if actor.get("actor_id") != _state.actor_id: continue
		if not selected.is_empty(): return reject("Duplicate actor scene identity")
		selected = actor
	if selected.is_empty(): return reject("Actor is missing from its source scene")
	var position: Variant = selected.get("position")
	if not position is Vector3 or not position.is_finite(): return reject("Invalid actor scene position")
	if selected.has("pose"):
		var pose: Variant = selected.pose
		if not pose is Transform3D or pose.origin != position: return reject("Actor scene pose and position disagree")
		return set_pose(pose)
	var source_position := Vector3(Vitals.single(position.x),Vitals.single(position.y),Vitals.single(position.z))
	if not source_position.is_finite(): return reject("Actor scene position exceeds source precision")
	_state.position = source_position
	if _state.has("pose"): _state.pose.origin = source_position
	# Scene staging owns placement, not live hull or combat permissions.
	return true

func set_pose(pose: Variant, physical_pose: Variant=null) -> bool:
	error = ""
	if _state.is_empty() or not pose is Transform3D or not pose.is_finite(): return reject("Actor pose requires a configured body and finite transform")
	if physical_pose!=null and ((_state.get("campaign_cursor") not in [4,7,10] and not _state.get("ambient_traffic",false) and not _state.get("contract_ship",false) and not _state.get("contract_debris",false) and not _state.get("convoy",false) and not _state.get("alioth_attack",false) and not _state.get("kappa_rescue",false) and not _state.get("authored_story",false)) or not Flight.rigid_pose(physical_pose)):return reject("Separate physical motion requires a supported finite flight root")
	# The actor's source-space transform is also the collision-center authority.
	var source_pose: Transform3D = pose
	for axis in 3:
		for component in 3: source_pose.basis[axis][component] = Vitals.single(source_pose.basis[axis][component])
	for component in 3: source_pose.origin[component] = Vitals.single(source_pose.origin[component])
	if not source_pose.is_finite(): return reject("Actor pose exceeds source precision")
	_state.pose = source_pose
	_state.position = source_pose.origin
	if physical_pose!=null:_state.body_pose=physical_pose
	return true

func set_permissions(active: Variant, damage_allowed: Variant, firing_allowed: Variant) -> bool:
	error = ""
	if _state.is_empty() or not active is bool or not damage_allowed is bool or not firing_allowed is bool:
		return reject("Actor lifecycle requires explicit activity, damage and firing permissions")
	_state.active = active
	_state.damage_allowed = damage_allowed
	_state.firing_allowed = firing_allowed
	return true

func apply_destruction(death: Dictionary) -> bool:
	error=""
	if _state.get("population_group") in ["freighter","debris"]:return reject("This actor requires its separate destruction lifecycle")
	if _state.is_empty() or _vitals.snapshot().hull!=0: return reject("NPC destruction requires an exhausted hull")
	for key in ["base_content_id","binding_id","actor_id"]:
		if death.get(key)!=_state[key]: return reject("NPC destruction belongs to another actor")
	if _state.has("campaign_cursor") and death.get("campaign_cursor")!=_state.campaign_cursor:return reject("NPC destruction belongs to another campaign context")
	var phase: Variant=death.get("phase")
	if phase not in ["tumble","explosion","retired"] or death.get("mode")!=(3 if phase=="tumble" else 4): return reject("Unsupported NPC destruction phase")
	var previous: Variant=_state.get("actor_mode")
	var initial_death: bool=previous==0 and (_initial_training_death or _state.get("local_combat",false) or _state.get("contract_combat",false))
	if previous==6 and _state.has("travel_cycle"):initial_death=true
	if _state.has("spawn_generation") and death.get("spawn_generation")!=_state.spawn_generation:return reject("Destruction belongs to an earlier traffic instance")
	if (previous not in [1,3,4] and not initial_death) or (previous==4 and phase=="tumble") or (not _state.active and phase!="retired"): return reject("NPC destruction phase regressed")
	if ((previous==1 or initial_death) and phase!="tumble") or (previous==3 and phase=="retired"): return reject("NPC destruction skipped a lifecycle phase")
	var body_pose: Variant=death.get("pose")
	if not body_pose is Transform3D or not body_pose.is_finite():return reject("NPC destruction lacks its finite hull transform")
	if _state.has("campaign_cursor") and (not death.get("statistics_pose") is Transform3D or not death.statistics_pose.is_finite()):return reject("Cargo destruction lacks its finite statistics transform")
	if not set_pose(death.get("statistics_pose",body_pose),body_pose if _state.has("campaign_cursor") else null): return false
	if _state.has("engine_draw_enabled") and (previous==1 or initial_death):_state.engine_draw_enabled=false
	_state.actor_mode=int(death.mode)
	if phase=="retired": _state.active=false
	return true

func apply_freighter_destruction(owner: RefCounted) -> bool:
	error=""
	if not owner is FreighterDeath or _state.get("population_group") not in ["freighter","capital"] or _vitals.snapshot().get("hull")!=0:return reject("Freighter lifecycle requires its exhausted combat body")
	var death: Dictionary=owner.snapshot()
	for key in ["base_content_id","binding_id","campaign_cursor","actor_id","actor_kind","hull_catalogue_id","subtype"]:
		if death.get(key)!=_state.get(key):return reject("Freighter lifecycle belongs to another actor")
	var mode: Variant=death.get("mode");var previous: int=_state.actor_mode
	if mode not in [3,4] or (previous==0 and mode!=3) or (previous==4 and mode!=4) or previous not in [0,3,4]:return reject("Freighter lifecycle skipped or regressed a phase")
	if not death.get("active") is bool or (not _state.active and death.active) or not death.get("pose") is Transform3D or not death.get("statistics_pose") is Transform3D:return reject("Invalid freighter lifecycle state")
	if not set_pose(death.statistics_pose,death.pose):return false
	_state.actor_mode=mode;_state.active=death.active;_state.engine_draw_enabled=false
	_state.world_movement_enabled=false;_state.interaction_blocked=death.interaction_blocked
	return true

## Internal half of the encounter's native wreck transaction. Pulling moves the
## physical root without refreshing statistics; model recreation updates both.
func _retain_recovery_frame(frame: Dictionary) -> void:
	var changes: Dictionary=frame.actor_changes
	if changes.has("body_pose"):_state.body_pose=changes.body_pose
	if changes.has("statistics_pose"):
		_state.pose=changes.statistics_pose;_state.position=changes.statistics_pose.origin
	if changes.has("active"):_state.active=changes.active
	for event in frame.events:
		if event.kind=="special_cargo_accepted":_state.special_cargo_accepted=true
		elif event.kind=="special_cargo_rejected":_state.special_cargo_rejected=true

func apply_debris_destruction(owner: RefCounted) -> bool:
	error=""
	if not owner is DebrisDeath or not _state.get("contract_combat",false) or not _state.get("contract_debris",false) or _vitals.snapshot().hull!=0:return reject("Debris destruction requires its exhausted prepared body")
	var death: Dictionary=owner.snapshot()
	for key in ["base_content_id","binding_id","campaign_cursor","actor_id","actor_kind","resource_id"]:
		if death.get(key)!=_state.get(key):return reject("Debris lifecycle belongs to another actor")
	if death.get("phase")!="destroyed" or death.get("mode")!=4 or _state.actor_mode not in [0,4] or death.pose!=_state.body_pose or death.statistics_pose!=_state.pose:return reject("Debris lifecycle changed its stationary pose or phase")
	if not death.get("active") is bool or (not _state.active and death.active):return reject("Debris cannot reactivate after destruction")
	_state.actor_mode=death.mode;_state.active=death.active;_state.model_draw_enabled=false
	return true

func collision_context() -> Dictionary:
	error = ""
	if _state.is_empty():
		reject("Configure an actor before checking collision eligibility")
		return {}
	# Capture once per target before visiting projectile slots. A later death in
	# that inner pass does not retroactively change its already-selected geometry.
	var result:={"base_content_id":_state.base_content_id,"actor_id":_state.actor_id,
		"eligible":_state.active and _state.collision_enabled and _vitals.snapshot().hull > 0,
		"path":"bounds","center":_state.position,"half_extent":_state.half_extent}
	if _state.has("point_boxes"):
		result.path="point_geometry";result.boxes=_state.point_boxes.duplicate(true)
	return result

func normal_hit(amount: Variant, nonplayer_source: Variant=false) -> Dictionary:
	error = ""
	# A body prepared for patrol cannot take damage until the group also owns
	# reputation, warning requests and faction retaliation.
	if (_state.get("local_patrol",false) or _state.get("ambient_traffic",false) or _state.get("kappa_rescue",false)) and not _state.get("local_combat",false):return fail_hit("Local traffic damage and retaliation are not connected")
	if (_state.get("contract_ship",false) or _state.get("contract_debris",false)) and not _state.get("contract_combat",false):return fail_hit("Contract damage and lifecycle are not connected")
	if _state.is_empty():
		reject("Configure an actor before applying a normal hit")
		return {}
	if not nonplayer_source is bool or (nonplayer_source and not _state.has("nonplayer_kill")):
		reject("NPC hit attribution requires a supported explicit source flag")
		return {}
	var result: Dictionary = _vitals.normal_hit(amount,_state.active and _state.damage_allowed)
	if result.is_empty(): reject(_vitals.error)
	elif result.destroyed_now and nonplayer_source: _state.nonplayer_kill=true
	return result

func fail_hit(message: String) -> Dictionary:
	reject(message)
	return {}

func record_contact(incoming_velocity: Variant,point_box_index: Variant=null) -> bool:
	error = ""
	if _state.is_empty() or not incoming_velocity is Vector3 or not incoming_velocity.is_finite():
		return reject("NPC contact requires a configured body and finite incoming velocity")
	var impact := Vector3.ZERO
	for axis in 3: impact[axis]=Vitals.single(-incoming_velocity[axis])
	if not impact.is_finite(): return reject("NPC contact exceeds source precision")
	if point_box_index!=null:
		if not _state.has("point_boxes") or not point_box_index is int or point_box_index<0 or point_box_index>=_state.point_boxes.size():return reject("Contact names an unavailable collision box")
		_state.point_box_index=point_box_index
	# Contact metadata follows the hit attempt even if damage was denied or a
	# preceding slot exhausted hull. Eligibility belongs to the contact owner.
	_state.contact=true
	_state.impact_vector=impact
	return true

func reject(message: String) -> bool:
	error = message
	return false

func apply_activation(data: Dictionary) -> bool:
	error = ""
	if _state.is_empty() or _state.has("campaign_cursor") or not Activation.parameters(data):
		return reject("Opening activation must name this configured actor")
	var names_actor := false
	for id in data.actor_ids: names_actor = names_actor or int(id)==_state.actor_id
	if not names_actor: return reject("Opening activation names another actor")
	_state.active = data.active
	_state.actor_mode = int(data.actor_mode)
	_state.spatial_half_extent = int(data.spatial_half_extent)
	return true

func apply_full_hold_guidance(data: Dictionary, decision: Dictionary) -> bool:
	error=""
	if not ControlDefinitions.parameters(data) or _state.get("campaign_cursor")!=data.campaign_cursor or not _state.has("node_draw_requested"):return reject("Second-trip activity requires its configured source context")
	return _apply_guidance_activity(decision)

func apply_combat_training_guidance(data: Dictionary, decision: Dictionary) -> bool:
	error=""
	if not TrainingControl.parameters(data) or _state.get("campaign_cursor")!=data.campaign_cursor or not _state.has("statistics_targeting_blocked"):return reject("Combat-training activity requires its configured context")
	return _apply_guidance_activity(decision,true)

func apply_local_patrol_guidance(decision: Dictionary) -> bool:
	error=""
	if not _state.get("local_patrol",false):return reject("Local patrol activity requires its configured source body")
	return _apply_guidance_activity(decision,true)

func _apply_guidance_activity(decision: Dictionary, training: bool=false) -> bool:
	for key in ["base_content_id","binding_id","campaign_cursor","actor_id"]:
		if decision.get(key)!=_state[key]:return reject("Second-trip activity belongs to another actor")
	var activation: Variant=decision.get("activation")
	if activation not in ["","proximity","target"] or not decision.get("holding") is bool:return reject("Invalid second-trip activation decision")
	var initializing: bool=training and _state.active and _state.get("actor_mode")==0
	if training and decision.get("initializing")!=initializing:return reject("NPC initialization disagrees with its source mode")
	var dormant: bool=not _state.active and _state.get("actor_mode")==5
	if not activation.is_empty():
		if not dormant or decision.holding!=(activation=="target"):return reject("Second-trip activation has the wrong dispatch timing")
	elif decision.holding!=dormant or (not dormant and not initializing and _state.get("actor_mode")!=1):return reject("Second-trip activity disagrees with its living mode")
	var request: bool=not decision.holding or not activation.is_empty()
	if _state.get("kappa_rescue",false) and dormant and not _state.hostile and activation.is_empty():request=bool(_state.node_draw_requested)
	if not decision.get("node_draw_requested") is bool or decision.node_draw_requested!=request:return reject("Second-trip model request disagrees with its source activity")
	if not activation.is_empty() or initializing:_state.active=true;_state.actor_mode=1
	_state.node_draw_requested=request
	return true

func apply_full_hold_appearance(data: Dictionary, root: Variant, statistics: Variant) -> bool:
	error=""
	if not Appearance.parameters(data) or _state.get("campaign_cursor")!=data.campaign_cursor or _state.get("appearance_applied",false):return reject("Appearance requires the unplaced second-trip actor")
	for key in ["actor_id","actor_kind","hull_catalogue_id"]:
		if _state.get(key)!=int(data[key]):return reject("Appearance names another pirate")
	if not Flight.rigid_pose(root) or not Flight.rigid_pose(statistics) or root.origin!=statistics.origin:return reject("Appearance requires consistent source poses")
	if not set_pose(statistics,root):return false
	_state.appearance_applied=true
	_state.actor_mode=int(data.actor_mode);_state.active=bool(data.active)
	_state.model_draw_enabled=bool(data.model_draw_enabled)
	_state.node_draw_requested=bool(data.node_draw_requested)
	_state.engine_draw_enabled=true
	return true

func fork_for_frame() -> RefCounted:
	var copy: RefCounted = get_script().new()
	copy._state = _state.duplicate(true)
	copy._initial_training_death=_initial_training_death
	copy._hostility = _hostility.duplicate(true)
	copy._hull_percentage_scale = _hull_percentage_scale
	if _systems!=null:copy._systems=_systems.fork()
	if _vitals != null:
		var pools: Dictionary = _vitals.snapshot()
		copy._vitals = Vitals.new()
		copy._vitals.configure(pools.hull,pools.armor,pools.shield)
	return copy
