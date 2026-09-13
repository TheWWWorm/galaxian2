extends RefCounted
## Native ordinary NPC bodies for verified encounter populations.
## Encounter logic supplies poses, lifecycle changes and already-resolved hits.
const TrainingControl=preload("res://src/content/combat_training_control_definitions.gd")
const TrainingDeath=preload("res://src/content/combat_training_destruction_definitions.gd")
const TrainingWorld=preload("res://src/simulation/opening_world_initialization.gd")
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
const Hull = preload("res://src/content/npc_hull_definitions.gd")
const InitialActors = preload("res://src/simulation/opening_actor_state.gd")
const Definitions = preload("res://src/content/npc_initialization_definitions.gd")
const Vitals = preload("res://src/simulation/combat_vitals.gd")
var error := ""
var _initial_training_death := false
var _state := {}
var _vitals: RefCounted
var _hostility := {}
var _hull_percentage_scale := 0.0

func clear() -> void:
	_initial_training_death=false
	error = ""
	_state = {}
	_vitals = null
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

func snapshot() -> Dictionary:
	if _state.is_empty(): return {}
	var result := _state.duplicate(true)
	result.vitals = _vitals.snapshot()
	if _state.has("max_hull"):
		var fraction := Vitals.single(Vitals.single(float(result.vitals.hull))/Vitals.single(float(result.max_hull)))
		result.hull_percent=int(Vitals.single(fraction*_hull_percentage_scale))
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
	if physical_pose!=null and (_state.get("campaign_cursor") not in [4,7] or not Flight.rigid_pose(physical_pose)):return reject("Separate physical motion requires a supported finite flight root")
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
	if _state.is_empty() or _vitals.snapshot().hull!=0: return reject("NPC destruction requires an exhausted hull")
	for key in ["base_content_id","binding_id","actor_id"]:
		if death.get(key)!=_state[key]: return reject("NPC destruction belongs to another actor")
	if _state.has("campaign_cursor") and death.get("campaign_cursor")!=_state.campaign_cursor:return reject("NPC destruction belongs to another campaign context")
	var phase: Variant=death.get("phase")
	if phase not in ["tumble","explosion","retired"] or death.get("mode")!=(3 if phase=="tumble" else 4): return reject("Unsupported NPC destruction phase")
	var previous: Variant=_state.get("actor_mode")
	var initial_training: bool=previous==0 and _initial_training_death
	if (previous not in [1,3,4] and not initial_training) or (previous==4 and phase=="tumble") or (not _state.active and phase!="retired"): return reject("NPC destruction phase regressed")
	if ((previous==1 or initial_training) and phase!="tumble") or (previous==3 and phase=="retired"): return reject("NPC destruction skipped a lifecycle phase")
	var body_pose: Variant=death.get("pose")
	if not body_pose is Transform3D or not body_pose.is_finite():return reject("NPC destruction lacks its finite hull transform")
	if _state.has("campaign_cursor") and (not death.get("statistics_pose") is Transform3D or not death.statistics_pose.is_finite()):return reject("Cargo destruction lacks its finite statistics transform")
	if not set_pose(death.get("statistics_pose",body_pose),body_pose if _state.has("campaign_cursor") else null): return false
	if _state.has("engine_draw_enabled") and (previous==1 or initial_training):_state.engine_draw_enabled=false
	_state.actor_mode=int(death.mode)
	if phase=="retired": _state.active=false
	return true

func collision_context() -> Dictionary:
	error = ""
	if _state.is_empty():
		reject("Configure an actor before checking collision eligibility")
		return {}
	# Capture once per target before visiting projectile slots. A later death in
	# that inner pass does not retroactively change its already-selected geometry.
	return {"base_content_id":_state.base_content_id,"actor_id":_state.actor_id,
		"eligible":_state.active and _state.collision_enabled and _vitals.snapshot().hull > 0,
		"path":"bounds","center":_state.position,"half_extent":_state.half_extent}

func normal_hit(amount: Variant, nonplayer_source: Variant=false) -> Dictionary:
	error = ""
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

func record_contact(incoming_velocity: Variant) -> bool:
	error = ""
	if _state.is_empty() or not incoming_velocity is Vector3 or not incoming_velocity.is_finite():
		return reject("NPC contact requires a configured body and finite incoming velocity")
	var impact := Vector3.ZERO
	for axis in 3: impact[axis]=Vitals.single(-incoming_velocity[axis])
	if not impact.is_finite(): return reject("NPC contact exceeds source precision")
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
	if _vitals != null:
		var pools: Dictionary = _vitals.snapshot()
		copy._vitals = Vitals.new()
		copy._vitals.configure(pools.hull,pools.armor,pools.shield)
	return copy
