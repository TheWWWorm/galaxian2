extends RefCounted
## Fresh opening NPC acquisition. This owns no damage, rewards or mission state.
## Special devices, other target groups and acquisition audio/messages remain separate.
const Beams=preload("res://src/content/beam_primary_definitions.gd")
const Definitions = preload("res://src/content/npc_scanner_definitions.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const TargetProjection = preload("res://src/presentation/target_projection.gd")
const Loadout = preload("res://src/simulation/opening_loadout.gd")
const Vectors = preload("res://src/simulation/source_vectors.gd")
const Equipment=preload("res://src/simulation/station_equipment.gd")
const Training=preload("res://src/content/combat_training_control_definitions.gd")
const OrdinaryFlight=preload("res://src/content/ordinary_flight_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const TrafficLife=preload("res://src/content/ambient_lifecycle_definitions.gd")
const Recovery=preload("res://src/simulation/tractor_recovery.gd")
const Selected40=preload("res://src/content/selected40_population_definitions.gd")
const Combat=preload("res://src/simulation/opening_combat_group.gd")
var error := ""
var _identity := {}
var _definition := {}
var _perspective := {}
var _hulls := []
var _radii := Vector2.ZERO
var _frame_count := 0
var _equipment := -1
var _duration := 0
var _cargo := false
var _retained_cargo := false
var _selected := -1
var _candidate := -1
var _elapsed := 0
var _sample := {}
var _kinds:=[8,8,8]
var _campaign_cursor:=0
var _departure_modes:={}
var _selected40_world: RefCounted
var _mission_combat:=false

func configure(bindings: RefCounted, catalogues: RefCounted, frame_radii: Vector2, animation_frames: int, equipment_owner: RefCounted=null, local_combat: Dictionary={}, recovery: RefCounted=null,mission_context: RefCounted=null) -> bool:
	if mission_context!=null and (not is_instance_of(mission_context,load("res://src/simulation/mission_context.gd")) or not equipment_owner is Equipment or not mission_context.matches_loadout(equipment_owner.snapshot().loadout)):return reject("Mission scanner lost its admitted equipment")
	return _configure(bindings,catalogues,frame_radii,animation_frames,equipment_owner,local_combat,recovery,null,mission_context)

## The retained inventory stays at Néhma. Only the actual selected native cast
## supplies scanner targets; this does not admit cursor40 as an ordinary flight.
func configure_selected40(bindings: RefCounted,catalogues: RefCounted,frame_radii: Vector2,animation_frames: int,equipment: RefCounted,combat: RefCounted) -> bool:
	error=""
	if not _definition.is_empty() or not combat is Combat or not equipment is Equipment:return reject("Selected40 scanner requires fresh native owners")
	var world: RefCounted=combat.selected40_world_owner()
	if world==null or world.npc_construction_owner()==null or not Selected40.context_valid(bindings,world.snapshot().get("selected40_context",{})):return reject("Selected40 scanner lacks its actual source generation")
	return _configure(bindings,catalogues,frame_radii,animation_frames,equipment,combat.snapshot(),null,world)

## A cast admitted at mission entry scans its native actors with the retained ship.
func configure_mission(bindings: RefCounted,catalogues: RefCounted,frame_radii: Vector2,animation_frames: int,equipment: RefCounted,combat: RefCounted,context: RefCounted) -> bool:
	error=""
	if not _definition.is_empty() or not combat is Combat or not equipment is Equipment or not is_instance_of(context,load("res://src/simulation/mission_context.gd")):return reject("Mission scanner requires fresh admitted native owners")
	if not context.matches_loadout(equipment.snapshot().loadout):return reject("Mission scanner lost its admitted loadout")
	if not _configure(bindings,catalogues,frame_radii,animation_frames,equipment,combat.snapshot(),null,null,context):return false
	_mission_combat=true
	return true

func advance_mission(combat: RefCounted,player: Transform3D,camera: Transform3D,aim: Dictionary,delta_ms: Variant,enabled: bool) -> bool:
	if not _mission_combat or not combat is Combat:return reject("Mission scanning requires its configured native combat owner")
	return _advance(combat.snapshot(),player,camera,aim,delta_ms,enabled)

func _configure(bindings: RefCounted, catalogues: RefCounted, frame_radii: Vector2, animation_frames: int, equipment_owner: RefCounted=null, local_combat: Dictionary={}, recovery: RefCounted=null,selected_world: RefCounted=null,mission: RefCounted=null) -> bool:
	clear()
	if bindings==null or catalogues==null or not Definitions.parameters(bindings.opening_staging.get("npc_scanner",{})):
		return reject("NPC scanner requires its verified opening declarations")
	var npc: Dictionary=bindings.opening_actors.get("npc_initialization",{})
	if npc.get("hull",{}).is_empty() or npc.get("hostility",{}).is_empty() or npc.get("construction",{}).is_empty():
		return reject("NPC scanner requires the fresh actor hull, flags and cargo scope")
	var projection := TargetProjection.new()
	if not projection.configure(bindings.flight_projection,Vector2i.ONE,frame_radii):return reject(projection.error)
	if animation_frames<1 or animation_frames>1024:return reject("Invalid original scanner filmstrip")
	var loadout: Dictionary
	var training:=equipment_owner!=null
	var local_flight:=not local_combat.is_empty()
	var selected40:=selected_world!=null
	var ordinary: bool=local_flight and preload("res://src/content/ordinary_fitting_definitions.gd").available(bindings)
	if local_flight and (not training or not Travel.parameters(bindings.mido_travel)):return reject("Local scanner requires its equipped traffic encounter")
	if training:
		if not equipment_owner is Equipment or not Training.parameters(bindings.combat_training_control) or (not ordinary and not equipment_owner.requirements().satisfied):return reject("Training scanner requires the retained equipped ship and complete cast")
		var owned: Dictionary=equipment_owner.snapshot()
		loadout=owned.loadout
		if loadout.base_content_id!=bindings.base_content_id or loadout.binding_id!=bindings.binding_id or catalogues.content_id!=bindings.base_content_id:return reject("Training scanner equipment belongs to another content identity")
		var station: Variant=local_combat.get("bakka_encounter",{}).get("context",{}).get("station_id",local_combat.get("contract_encounter",{}).get("context",{}).get("station_id",local_combat.get("provocation",{}).get("station_id")))
		if selected40:
			var context: Dictionary=selected_world.snapshot().selected40_context
			var built: Dictionary=selected_world.npc_construction_owner().snapshot()
			station=context.origin_station_id
			if loadout.system_id!=context.origin_system_id or loadout.ship_id!=built.player_ship_id or loadout.equipment_ids!=built.player_equipment_ids:return reject("Selected40 scanner changed its retained origin loadout")
		if mission!=null:station=loadout.station_id
		if local_flight and (loadout.station_id!=station or not owned.get("prototype_drill_replaced",false) or not owned.get("training_inventory_released",false)):return reject("Local scanner requires its retained Mido inventory")
	else:
		var initial:=Loadout.new()
		if not initial.configure(bindings,catalogues,bindings.base_content_id):return reject(initial.error)
		loadout=initial.snapshot()
	var data: Dictionary=bindings.opening_staging.npc_scanner
	var equipment := -1
	var supported_recovery: bool=ordinary and recovery is Recovery and recovery.same_identity(loadout) and recovery.equipment_loadout()=={"ship_id":int(loadout.ship_id),"equipment_ids":loadout.equipment_ids}
	for id in loadout.equipment_ids:
		var item: Dictionary=catalogues.tables.items[id]
		if item.arrays[2].size()<=5:return reject("Scanner equipment lacks its source type")
		if int(item.arrays[2][5]) in [13,19] and not (ordinary and int(item.arrays[2][5])==19) and not (supported_recovery and int(item.arrays[2][5])==13) and (not training or id!=(86 if local_flight else 90)):return reject("Special scanner devices are outside this flight's scope")
		if int(item.arrays[2][5])==int(data.equipment_type):equipment=id
	var duration := int(data.default_duration_ms)
	var cargo := false
	if equipment>=0:
		var properties: Dictionary=catalogues.tables.items[equipment].properties
		if not Numbers.integer(properties.get(int(data.duration_property)),1,2147483647):return reject("Unsupported scanner acquisition duration")
		duration=int(properties[int(data.duration_property)])
		cargo=properties.get(int(data.cargo_property))==1
	if training and not ordinary and (equipment!=81 or duration!=4000 or cargo):return reject("Training NPC scanning requires the source starter scanner without cargo inspection")
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_definition=data.duplicate(true);_perspective=bindings.flight_projection.duplicate(true);_hulls=npc.hull.hull_catalogue_ids.duplicate()
	if training:
		_hulls=bindings.combat_training_control.hull_catalogue_ids.duplicate();_kinds=bindings.combat_training_control.actor_kinds.duplicate();_campaign_cursor=7
	if local_flight:
		for key in _identity:
			if local_combat.get(key)!=_identity[key]:return reject("Local scanner belongs to another encounter")
		var actors: Variant=local_combat.get("actors")
		if not selected40 and mission==null and not OrdinaryFlight.combat_population(bindings,local_combat):return reject("Local scanner requires the generated population")
		_hulls=[];_kinds=[];_campaign_cursor=int(local_combat.campaign_cursor)
		for id in actors.size():
			var actor: Variant=actors[id]
			if not actor is Dictionary or actor.get("actor_id")!=id:return reject("Local scanner has an unsupported ship")
			_hulls.append(int(actor.hull_catalogue_id));_kinds.append(int(actor.actor_kind))
			if actor.get("population_group")=="travel" and actor.has("travel_cycle"):
				if not TrafficLife.parameters(bindings.ambient_lifecycle):return reject("Travelling scanner targets lack their source lifecycle")
				_departure_modes[id]=int(bindings.ambient_lifecycle.departure_mode)
	_radii=frame_radii;_frame_count=animation_frames;_equipment=equipment;_duration=duration;_cargo=cargo;_retained_cargo=local_flight
	_selected40_world=selected_world
	return true

## One projection can serve both cargo acquisition and ordinary markers during
## the same HUD operation. It carries no selection or acquisition clock.
func prepare_projection(viewport: Vector2i) -> RefCounted:
	var projection:=TargetProjection.new()
	if not projection.configure(_perspective,viewport,_radii):reject(projection.error);return null
	return projection

func advance(combat: Dictionary, player: Transform3D, camera: Transform3D, aim: Dictionary, delta_ms: Variant, enabled: bool, ordinary_candidate: int=-2, prepared_projection: RefCounted=null) -> bool:
	if _selected40_world!=null or _mission_combat:return reject("Selected40 scanning requires its native combat owner, not a dictionary")
	return _advance(combat,player,camera,aim,delta_ms,enabled,ordinary_candidate,prepared_projection)

func advance_selected40(combat: RefCounted,player: Transform3D,camera: Transform3D,aim: Dictionary,delta_ms: Variant,enabled: bool) -> bool:
	error=""
	if _selected40_world==null or not combat is Combat:return reject("Selected40 scanning requires its configured native combat owner")
	var world: RefCounted=combat.selected40_world_owner()
	if world==null or world.npc_construction_owner()!=_selected40_world.npc_construction_owner() or world.snapshot()!=_selected40_world.snapshot():return reject("Selected40 scanning changed its constructor generation")
	return _advance(combat.snapshot(),player,camera,aim,delta_ms,enabled)

func _advance(combat: Dictionary, player: Transform3D, camera: Transform3D, aim: Dictionary, delta_ms: Variant, enabled: bool, ordinary_candidate: int=-2, prepared_projection: RefCounted=null) -> bool:
	error=""
	if _definition.is_empty() or not Numbers.integer(delta_ms,0,2147483647):return reject("NPC scanner requires an ordinary integer frame duration")
	for key in _identity:
		if combat.get(key)!=_identity[key] or aim.get(key)!=_identity[key]:return reject("NPC scanner samples belong to another content profile")
	var population: Variant=combat.get("actors")
	var point: Variant=aim.get("point");var viewport: Variant=aim.get("viewport_size")
	if not population is Array or population.size()!=_hulls.size() or not point is Vector3 or not point.is_finite() or not TargetProjection.safe_pixel(point.x) or not TargetProjection.safe_pixel(point.y) or not viewport is Vector2i or not player.is_finite():return reject("Invalid ordinary scanner sample")
	if _campaign_cursor!=0 and combat.get("campaign_cursor")!=_campaign_cursor:return reject("Equipped scanner lost its encounter context")
	if not Numbers.integer(ordinary_candidate,-2,population.size()-1):return reject("The shared HUD candidate is outside this encounter")
	var projection: RefCounted=prepare_projection(viewport) if prepared_projection==null else prepared_projection
	if not projection is TargetProjection:return reject("NPC scanning requires its prepared flight projection")
	# Check all inputs before committing selection, including invisible bodies.
	for id in population.size():
		var actor: Variant=population[id]
		var kind_matches: bool=actor is Dictionary and (Selected40.constructed_kind_matches(actor,_kinds[id]) if _selected40_world!=null else actor.get("actor_kind")==_kinds[id])
		if not actor is Dictionary or actor.get("actor_id")!=id or actor.get("base_content_id")!=_identity.base_content_id or actor.get("binding_id")!=_identity.binding_id or not kind_matches or actor.get("hull_catalogue_id")!=_hulls[id] or not actor.get("pose") is Transform3D or not actor.pose.is_finite() or not actor.get("active") is bool or not actor.get("hostile") is bool or not valid_mode(id,actor.get("actor_mode")) or not Numbers.integer(actor.get("hull_percent"),0,100):
			var detail: Variant=actor
			if actor is Dictionary:detail={"actor_id":actor.get("actor_id"),"kind":actor.get("actor_kind"),"hull":actor.get("hull_catalogue_id"),"mode":actor.get("actor_mode"),"hull_percent":actor.get("hull_percent"),"active":actor.get("active"),"hostile":actor.get("hostile"),"pose":actor.get("pose")}
			return reject("Invalid fresh NPC scanner population at %d: %s"%[id,str(detail)])
	var selected := _selected;var candidate := _candidate;var elapsed := _elapsed
	var markers := [];var events := [];var animation := -1;var found := -1
	var weapon_targets: Array=[] if enabled else weapon_target_ids()
	# Native scope currently displays the ordinary phase-four HUD. Hidden draws
	# retain selection and time; pause owners do not call advance at all.
	if enabled:
		if selected>=0 and selection_retired(population[selected]):selected=-1;candidate=-1
		var radius := int(viewport.x)/int(_definition.window_divisor)
		var lower := Vector2(TargetProjection.single(point.x-float(radius)),TargetProjection.single(point.y-float(radius)))
		if not TargetProjection.safe_pixel(lower.x) or not TargetProjection.safe_pixel(lower.y) or not TargetProjection.safe_pixel(lower.x+radius*2) or not TargetProjection.safe_pixel(lower.y+radius*2):return reject("Scanner window exceeds source pixel coordinates")
		var lower_pixels := Vector2i(int(lower.x),int(lower.y))
		var upper_pixels := lower_pixels+Vector2i(radius*2,radius*2)
		for actor in population:
			if not selectable(actor):continue
			var projected: Dictionary=projection.project(camera,actor.pose.origin)
			if projected.has("error"):return reject(projection.error)
			var offset := Vectors.added(player.origin,-actor.pose.origin)
			var near: bool=projected.in_view and absf(offset.x)<=_definition.near_half_extent and absf(offset.y)<=_definition.near_half_extent and absf(offset.z)<=_definition.near_half_extent
			var pixel: Vector2i=projected.pixels
			var inside: bool=projected.in_view and pixel.x>lower_pixels.x and pixel.x<upper_pixels.x and pixel.y>lower_pixels.y and pixel.y<upper_pixels.y
			if inside and offset.length()<Beams.AIM_DISTANCE:weapon_targets.append(int(actor.actor_id))
			if _equipment<0 or not scannable(actor):continue
			markers.append({"actor_id":actor.actor_id,"pixels":pixel,"near":near,"selected":actor.actor_id==selected,
				"hostile":actor.hostile,"hull_percent":int(actor.hull_percent),"in_scan_window":inside,"in_view":projected.in_view,"position":actor.pose.origin})
			if found<0 and inside:found=int(actor.actor_id)
	if enabled and _equipment>=0:
		# A fitted tractor and ordinary scanner share the original ordered NPC
		# candidate. Cargo cannot advance a second, unrelated ship scan as well.
		if ordinary_candidate!=-2:found=ordinary_candidate
		if found>=0:
			if candidate!=found:elapsed=0
			candidate=found
			if elapsed>2147483647-int(delta_ms):return reject("NPC acquisition timer exceeds source integer range")
			elapsed+=int(delta_ms)
			if elapsed>_duration:
				if selected!=candidate:
					selected=candidate
					events.append({"kind":"sound","source_id":int(_definition.acquisition_sound_id),"actor_id":selected})
					if _cargo:
						# Inspection observes the retained cargo owner only on a new
						# acquisition. Fresh opening construction discarded its cargo.
						if _retained_cargo:events.append({"kind":"cargo_scan","actor_id":selected})
						else:events.append({"kind":"notification","source_id":int(_definition.empty_cargo_message_id),"actor_id":selected})
				elapsed=0
			elif elapsed>0 and candidate!=selected:
				animation=int(TargetProjection.single(float(_frame_count-1)*TargetProjection.single(TargetProjection.single(float(elapsed))/TargetProjection.single(float(_duration)))))
		else:
			elapsed=0
			if selected<0:candidate=-1
	_selected=selected;_candidate=candidate;_elapsed=elapsed
	_sample={"visible":enabled and _equipment>=0,"weapon_target_ids":weapon_targets,"markers":markers,"events":events,"animation_frame":animation,"found_actor_id":found,"aim_pixels":Vector2i(int(point.x),int(point.y)),"viewport_size":viewport}
	_sample.camera_position=camera.origin
	_sample.selected_target={}
	if enabled and _equipment>=0 and selected>=0:
		var actor: Dictionary=population[selected]
		_sample.selected_target={"actor_id":selected,"actor_kind":int(actor.actor_kind),"name_text_id":int(actor.get("name_text_id",-1)),"hull_percent":int(actor.hull_percent)}
		if actor.has("display_name"):_sample.selected_target.display_name=String(actor.display_name)
	return true

func valid_mode(actor_id: int,mode: Variant) -> bool:
	var minimum:=0 if _campaign_cursor not in [0,7] or (_campaign_cursor==7 and actor_id==3) else 1
	return Numbers.integer(mode,minimum,5) or (mode is int and _departure_modes.has(actor_id) and _departure_modes[actor_id]==mode)

static func selectable(actor: Dictionary) -> bool:
	return actor.active and not selection_retired(actor)

## Junk is a weapon target only; its dropped crate is locked by the tractor, never the scanner.
static func scannable(actor: Dictionary) -> bool:
	return selectable(actor) and actor.get("population_group")!="debris"

static func selection_retired(actor: Dictionary) -> bool:
	# Junk removes its body immediately. A dropped container keeps the same
	# target active; an empty drop clears it. Ship breakup has another rule.
	return not actor.active if actor.get("population_group")=="debris" else int(actor.actor_mode) in [3,4]

func weapon_target_ids() -> Array:return _sample.get("weapon_target_ids",[]).duplicate()

## Guidance keeps the acquired ship outside the aim square, until it leaves
## the view. The camera owner disables this observation during free look.
func guidance_target_id(camera_allowed:=true) -> int:
	if not camera_allowed or _equipment<0 or _selected<0:return -1
	for marker in _sample.get("markers",[]):
		if marker.actor_id==_selected and marker.in_view:return _selected
	return -1

func sound_events() -> Array:
	return _sample.get("events",[]).filter(func(event):return event.kind=="sound").duplicate(true)

func snapshot() -> Dictionary:
	if _definition.is_empty():return {}
	var result := _identity.duplicate()
	result.merge({"selected_actor_id":_selected,"candidate_actor_id":_candidate,"elapsed_ms":_elapsed,"equipment_id":_equipment,"duration_ms":_duration,"animation_frames":_frame_count})
	result.merge(_sample.duplicate(true))
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._identity=_identity;copy._definition=_definition;copy._perspective=_perspective;copy._radii=_radii;copy._hulls=_hulls
	copy._frame_count=_frame_count;copy._equipment=_equipment;copy._duration=_duration;copy._cargo=_cargo;copy._retained_cargo=_retained_cargo
	copy._selected=_selected;copy._candidate=_candidate;copy._elapsed=_elapsed;copy._sample=_sample.duplicate(true)
	copy._kinds=_kinds.duplicate();copy._campaign_cursor=_campaign_cursor
	copy._departure_modes=_departure_modes.duplicate()
	copy._selected40_world=_selected40_world;copy._mission_combat=_mission_combat
	return copy

func clear() -> void:
	error="";_identity={};_definition={};_perspective={};_hulls=[];_radii=Vector2.ZERO;_frame_count=0;_equipment=-1;_duration=0;_cargo=false
	_selected=-1;_candidate=-1;_elapsed=0;_sample={};_retained_cargo=false
	_kinds=[8,8,8];_campaign_cursor=0
	_departure_modes={};_mission_combat=false
	_selected40_world=null

func reject(message: String) -> bool:
	error=message
	return false
