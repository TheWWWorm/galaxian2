extends RefCounted
## Fresh opening NPC acquisition. This owns no damage, rewards or mission state.
## Special devices, other target groups and acquisition audio/messages remain separate.
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
var _selected := -1
var _candidate := -1
var _elapsed := 0
var _sample := {}
var _kinds:=[8,8,8]
var _campaign_cursor:=0
var _departure_modes:={}

func configure(bindings: RefCounted, catalogues: RefCounted, frame_radii: Vector2, animation_frames: int, equipment_owner: RefCounted=null, local_combat: Dictionary={}) -> bool:
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
	var ordinary: bool=local_combat.get("campaign_cursor")==18 and preload("res://src/content/ordinary_fitting_definitions.gd").available(bindings)
	if local_flight and (not training or not Travel.parameters(bindings.mido_travel) or local_combat.get("campaign_cursor") not in [10,11,12,13,14,16,18]):return reject("Local scanner requires its equipped traffic encounter")
	if training:
		if not equipment_owner is Equipment or not Training.parameters(bindings.combat_training_control) or (not ordinary and not equipment_owner.requirements().satisfied):return reject("Training scanner requires the retained equipped ship and complete cast")
		loadout=equipment_owner.snapshot().loadout
		if loadout.base_content_id!=bindings.base_content_id or loadout.binding_id!=bindings.binding_id or catalogues.content_id!=bindings.base_content_id:return reject("Training scanner equipment belongs to another content identity")
		var station: Variant=local_combat.get("contract_encounter",{}).get("context",{}).get("station_id",local_combat.get("provocation",{}).get("station_id"))
		if local_flight and (loadout.station_id!=station or not equipment_owner.snapshot().get("prototype_drill_replaced",false) or not equipment_owner.snapshot().get("training_inventory_released",false)):return reject("Local scanner requires its retained Mido inventory")
	else:
		var initial:=Loadout.new()
		if not initial.configure(bindings,catalogues,bindings.base_content_id):return reject(initial.error)
		loadout=initial.snapshot()
	var data: Dictionary=bindings.opening_staging.npc_scanner
	var equipment := -1
	for id in loadout.equipment_ids:
		var item: Dictionary=catalogues.tables.items[id]
		if item.arrays[2].size()<=5:return reject("Scanner equipment lacks its source type")
		if int(item.arrays[2][5]) in [13,19] and not (ordinary and int(item.arrays[2][5])==19) and (not training or id!=(86 if local_flight else 90)):return reject("Special scanner devices are outside this flight's scope")
		if int(item.arrays[2][5])==int(data.equipment_type):equipment=id
	var duration := int(data.default_duration_ms)
	var cargo := false
	if equipment>=0:
		var properties: Dictionary=catalogues.tables.items[equipment].properties
		if not Numbers.integer(properties.get(int(data.duration_property)),1,2147483647):return reject("Unsupported scanner acquisition duration")
		duration=int(properties[int(data.duration_property)])
		cargo=properties.get(int(data.cargo_property))==1
	if ordinary and cargo:return reject("Cargo inspection of ordinary traffic is not yet supported")
	if training and not ordinary and (equipment!=81 or duration!=4000 or cargo):return reject("Training NPC scanning requires the source starter scanner without cargo inspection")
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_definition=data.duplicate(true);_perspective=bindings.flight_projection.duplicate(true);_hulls=npc.hull.hull_catalogue_ids.duplicate()
	if training:
		_hulls=bindings.combat_training_control.hull_catalogue_ids.duplicate();_kinds=bindings.combat_training_control.actor_kinds.duplicate();_campaign_cursor=7
	if local_flight:
		for key in _identity:
			if local_combat.get(key)!=_identity[key]:return reject("Local scanner belongs to another encounter")
		var actors: Variant=local_combat.get("actors")
		if not OrdinaryFlight.combat_population(bindings,local_combat):return reject("Local scanner requires the generated population")
		_hulls=[];_kinds=[];_campaign_cursor=int(local_combat.campaign_cursor)
		for id in actors.size():
			var actor: Variant=actors[id]
			if not actor is Dictionary or actor.get("actor_id")!=id or (local_combat.campaign_cursor not in [13,14,16,18] and actor.get("actor_kind")!=3):return reject("Local scanner has an unsupported ship")
			_hulls.append(int(actor.hull_catalogue_id));_kinds.append(int(actor.actor_kind))
			if actor.get("population_group")=="travel" and actor.has("travel_cycle"):
				if not TrafficLife.parameters(bindings.ambient_lifecycle):return reject("Travelling scanner targets lack their source lifecycle")
				_departure_modes[id]=int(bindings.ambient_lifecycle.departure_mode)
	_radii=frame_radii;_frame_count=animation_frames;_equipment=equipment;_duration=duration;_cargo=cargo
	return true

func advance(combat: Dictionary, player: Transform3D, camera: Transform3D, aim: Dictionary, delta_ms: Variant, enabled: bool) -> bool:
	error=""
	if _definition.is_empty() or not Numbers.integer(delta_ms,0,2147483647):return reject("NPC scanner requires an ordinary integer frame duration")
	for key in _identity:
		if combat.get(key)!=_identity[key] or aim.get(key)!=_identity[key]:return reject("NPC scanner samples belong to another content profile")
	var population: Variant=combat.get("actors")
	var point: Variant=aim.get("point");var viewport: Variant=aim.get("viewport_size")
	if not population is Array or population.size()!=_hulls.size() or not point is Vector3 or not point.is_finite() or not TargetProjection.safe_pixel(point.x) or not TargetProjection.safe_pixel(point.y) or not viewport is Vector2i or not player.is_finite():return reject("Invalid ordinary scanner sample")
	if _campaign_cursor in [7,10,11,12,13,14,16,18] and combat.get("campaign_cursor")!=_campaign_cursor:return reject("Equipped scanner lost its encounter context")
	var projection := TargetProjection.new()
	if not projection.configure(_perspective,viewport,_radii):return reject(projection.error)
	# Check all inputs before committing selection, including invisible bodies.
	for id in population.size():
		var actor: Variant=population[id]
		if not actor is Dictionary or actor.get("actor_id")!=id or actor.get("base_content_id")!=_identity.base_content_id or actor.get("binding_id")!=_identity.binding_id or actor.get("actor_kind")!=_kinds[id] or actor.get("hull_catalogue_id")!=_hulls[id] or not actor.get("pose") is Transform3D or not actor.pose.is_finite() or not actor.get("active") is bool or not actor.get("hostile") is bool or not valid_mode(id,actor.get("actor_mode")) or not Numbers.integer(actor.get("hull_percent"),0,100):
			var detail: Variant=actor
			if actor is Dictionary:detail={"actor_id":actor.get("actor_id"),"kind":actor.get("actor_kind"),"hull":actor.get("hull_catalogue_id"),"mode":actor.get("actor_mode"),"hull_percent":actor.get("hull_percent"),"active":actor.get("active"),"hostile":actor.get("hostile"),"pose":actor.get("pose")}
			return reject("Invalid fresh NPC scanner population at %d: %s"%[id,str(detail)])
	var selected := _selected;var candidate := _candidate;var elapsed := _elapsed
	var markers := [];var events := [];var animation := -1
	# Native scope currently displays the ordinary phase-four HUD. Hidden draws
	# retain selection and time; pause owners do not call advance at all.
	if enabled and _equipment>=0:
		if selected>=0 and selection_retired(population[selected]):selected=-1;candidate=-1
		var radius := int(viewport.x)/int(_definition.window_divisor)
		var lower := Vector2(TargetProjection.single(point.x-float(radius)),TargetProjection.single(point.y-float(radius)))
		if not TargetProjection.safe_pixel(lower.x) or not TargetProjection.safe_pixel(lower.y) or not TargetProjection.safe_pixel(lower.x+radius*2) or not TargetProjection.safe_pixel(lower.y+radius*2):return reject("Scanner window exceeds source pixel coordinates")
		var lower_pixels := Vector2i(int(lower.x),int(lower.y))
		var upper_pixels := lower_pixels+Vector2i(radius*2,radius*2)
		var found := -1
		for actor in population:
			if not selectable(actor):continue
			var projected: Dictionary=projection.project(camera,actor.pose.origin)
			if projected.has("error"):return reject(projection.error)
			var offset := Vectors.added(player.origin,-actor.pose.origin)
			var near: bool=projected.in_view and absf(offset.x)<=_definition.near_half_extent and absf(offset.y)<=_definition.near_half_extent and absf(offset.z)<=_definition.near_half_extent
			var pixel: Vector2i=projected.pixels
			var inside: bool=projected.in_view and pixel.x>lower_pixels.x and pixel.x<upper_pixels.x and pixel.y>lower_pixels.y and pixel.y<upper_pixels.y
			markers.append({"actor_id":actor.actor_id,"pixels":pixel,"near":near,"selected":actor.actor_id==selected,
				"hostile":actor.hostile,"hull_percent":int(actor.hull_percent),"in_scan_window":inside,"in_view":projected.in_view})
			if found<0 and inside:found=int(actor.actor_id)
		if found>=0:
			if candidate!=found:elapsed=0
			candidate=found
			if elapsed>2147483647-int(delta_ms):return reject("NPC acquisition timer exceeds source integer range")
			elapsed+=int(delta_ms)
			if elapsed>_duration:
				if selected!=candidate:
					selected=candidate
					events.append({"kind":"sound","source_id":int(_definition.acquisition_sound_id),"actor_id":selected})
					# The original finite-coordinate cargo predicate always reaches
					# inspection; fresh opening construction already discarded cargo.
					if _cargo:events.append({"kind":"notification","source_id":int(_definition.empty_cargo_message_id),"actor_id":selected})
				elapsed=0
			elif elapsed>0 and candidate!=selected:
				animation=int(TargetProjection.single(float(_frame_count-1)*TargetProjection.single(TargetProjection.single(float(elapsed))/TargetProjection.single(float(_duration)))))
		else:
			elapsed=0
			if selected<0:candidate=-1
	_selected=selected;_candidate=candidate;_elapsed=elapsed
	_sample={"visible":enabled and _equipment>=0,"markers":markers,"events":events,"animation_frame":animation,"aim_pixels":Vector2i(int(point.x),int(point.y)),"viewport_size":viewport}
	return true

func valid_mode(actor_id: int,mode: Variant) -> bool:
	var minimum:=0 if _campaign_cursor in [10,11,12,13,14,16,18] or (_campaign_cursor==7 and actor_id==3) else 1
	return Numbers.integer(mode,minimum,5) or (mode is int and _departure_modes.has(actor_id) and _departure_modes[actor_id]==mode)

static func selectable(actor: Dictionary) -> bool:
	return actor.active and not selection_retired(actor)

static func selection_retired(actor: Dictionary) -> bool:
	# Junk removes its body immediately. A dropped container keeps the same
	# target active; an empty drop clears it. Ship breakup has another rule.
	return not actor.active if actor.get("population_group")=="debris" else int(actor.actor_mode) in [3,4]

func snapshot() -> Dictionary:
	if _definition.is_empty():return {}
	var result := _identity.duplicate()
	result.merge({"selected_actor_id":_selected,"candidate_actor_id":_candidate,"elapsed_ms":_elapsed,"equipment_id":_equipment,"duration_ms":_duration,"animation_frames":_frame_count})
	result.merge(_sample.duplicate(true))
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._identity=_identity;copy._definition=_definition;copy._perspective=_perspective;copy._radii=_radii;copy._hulls=_hulls
	copy._frame_count=_frame_count;copy._equipment=_equipment;copy._duration=_duration;copy._cargo=_cargo
	copy._selected=_selected;copy._candidate=_candidate;copy._elapsed=_elapsed;copy._sample=_sample.duplicate(true)
	copy._kinds=_kinds.duplicate();copy._campaign_cursor=_campaign_cursor
	copy._departure_modes=_departure_modes.duplicate()
	return copy

func clear() -> void:
	error="";_identity={};_definition={};_perspective={};_hulls=[];_radii=Vector2.ZERO;_frame_count=0;_equipment=-1;_duration=0;_cargo=false
	_selected=-1;_candidate=-1;_elapsed=0;_sample={}
	_kinds=[8,8,8];_campaign_cursor=0
	_departure_modes={}

func reject(message: String) -> bool:
	error=message
	return false
