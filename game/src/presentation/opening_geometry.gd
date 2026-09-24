extends Node3D
const FlightStages=preload("res://src/content/flight_stages.gd")
## Source opening body/light presentation, driven by detached simulation state.
## Mac Betty departure includes its original nozzle-glow mesh. Exhaust particles,
## mounted equipment and the location environment have separate owners.
## Detail mode accepts source-scheduled selections. Hidden actors need no invented initial orientation.
const Vectors=preload("res://src/simulation/source_vectors.gd")
const ShipGeometry = preload("res://src/presentation/ship_geometry.gd")
const Resources = preload("res://src/presentation/model_resources.gd")
const Loadout = preload("res://src/simulation/opening_loadout.gd")
const Staging = preload("res://src/simulation/opening_staging.gd")
const ArrivalStaging = preload("res://src/simulation/arrival_choreography.gd")
const ArrivalLocation = preload("res://src/simulation/arrival_location.gd")
const ArrivalConstruction = preload("res://src/content/arrival_actor_construction_definitions.gd")
const ImportedModel = preload("res://src/presentation/imported_model.gd")
const SurfaceResponse = preload("res://src/presentation/surface_response.gd")
const OrdinaryFlight=preload("res://src/content/ordinary_flight_definitions.gd")
const Campaign=preload("res://src/content/free_campaign_definitions.gd")
const EngineParticles=preload("res://src/simulation/player_engine_particles.gd")
const ParticleGeometry=preload("res://src/presentation/opening_damage_geometry.gd")
var error := ""
var player: Node3D
var engine_particles: Node3D
var actors := {}
var surface_materials: Array[ShaderMaterial] = []
var _definitions := {}
var _content_id := ""
var _binding_id := ""
var _with_detail := false
var _escape_available:=false
var _campaign_cursor:=0
var _departure_return_available:=false
var _departure_return_cursor:=3
var _departure_return_mission:={}
var _visit_transition:={}
var _visit_system_id:=-1
var _arrival_player_origin:=Vector3.ZERO

func apply_surface_response(bindings: RefCounted, lighting: Dictionary, reflection: RefCounted, diffuse_bias: Variant, normal_bias: Variant, variant: String) -> bool:
	error=""
	if player==null or not surface_materials.is_empty():return reject("Build a fresh opening assembly before applying surface response")
	if bindings==null or bindings.base_content_id!=_content_id or bindings.binding_id!=_binding_id or lighting.get("base_content_id")!=_content_id or lighting.get("binding_id")!=_binding_id:
		return reject("Surface lighting belongs to another opening content identity")
	if reflection==null or reflection.selection.get("base_content_id")!=_content_id or reflection.selection.get("binding_id")!=_binding_id or reflection.selection.get("system_id")!=lighting.get("system_id"):
		return reject("Surface reflection belongs to another opening location")
	var models := []
	for child in find_children("*","",true,false):
		if child.get_script()==ImportedModel:models.append(child)
	var adapter := SurfaceResponse.new()
	var staged := adapter.prepare_models(models,bindings.surface_material,lighting,reflection.texture,diffuse_bias,normal_bias,variant)
	if staged.is_empty():return reject(adapter.error)
	# Stage every replacement before changing an instance or its animation owner.
	SurfaceResponse.commit_models(staged)
	for row in staged:
		surface_materials.append(row.material)
	return true

func build_player_exhaust(owner: RefCounted,library: RefCounted,visuals: RefCounted,bindings: RefCounted) -> bool:
	error=""
	if player==null or engine_particles!=null or not owner is EngineParticles:return reject("Build fresh opening geometry and its player engine owner first")
	var state: Dictionary=owner.snapshot()
	if state.get("base_content_id")!=_content_id or state.get("binding_id")!=_binding_id or state.get("ship_id")!=player.get_meta("source_ship_id"):
		return reject("Opening exhaust belongs to another player hull or content identity")
	var sprites:=ParticleGeometry.new()
	if not sprites.build(owner,library,visuals,bindings):
		var message: String=sprites.error
		sprites.free()
		return reject(message)
	add_child(sprites);engine_particles=sprites
	return true

func prepare_player_exhaust(owner: RefCounted,state: Dictionary,camera_pose: Variant) -> Dictionary:
	error=""
	if engine_particles==null:
		if state.has("engine_particles"):error="Opening exhaust has no configured renderer"
		return {}
	if not owner is EngineParticles or not state.has("engine_particles"):
		error="Opening exhaust requires its current engine-particle frame";return {}
	var prepared: Dictionary=engine_particles.prepare_world(owner,state,camera_pose)
	if prepared.is_empty():error=engine_particles.error
	return prepared

func commit_player_exhaust(prepared: Dictionary) -> void:
	if engine_particles!=null and not prepared.is_empty():engine_particles.commit_world(prepared)

func build(library: RefCounted, visuals: RefCounted, bindings: RefCounted, catalogues: RefCounted, quality := "high", with_detail := false) -> bool:
	clear()
	error = ""
	var loadout := Loadout.new()
	var staging := Staging.new()
	var content_id: String = library.manifest.get("content_id", "")
	if not loadout.configure(bindings, catalogues, content_id): return reject(loadout.error)
	if not staging.configure(bindings, catalogues, content_id): return reject(staging.error)
	var state := staging.snapshot()
	var selected := {"player": bindings.resolve_ship_layers(loadout.snapshot().ship_id)}
	if selected.player.is_empty(): return reject(bindings.error)
	for actor in state.actors:
		selected[actor.actor_id] = bindings.resolve_ship_layers(actor.hull_catalogue_id)
		if selected[actor.actor_id].is_empty(): return reject(bindings.error)
	return _assemble(library,visuals,bindings,selected,state,quality,with_detail,0)

func build_arrival(library: RefCounted, visuals: RefCounted, bindings: RefCounted, catalogues: RefCounted, cache: Variant, quality := "high", with_detail := false) -> bool:
	clear();error=""
	var location:=ArrivalLocation.new()
	var context:=location.resolve(bindings,catalogues,cache)
	if context.is_empty():return reject(location.error)
	if not ArrivalConstruction.parameters(bindings.arrival_actor_construction):return reject("Rescue model construction is unavailable")
	var staging:=ArrivalStaging.new()
	if not staging.configure(bindings,library):return reject(staging.error)
	var initial:=staging.snapshot()
	var actor: Dictionary=initial.frame.actor
	if actor.engine_draw_enabled:return reject("Rescue engine-effect rendering is unavailable")
	if bindings.resolve(actor.engine_resource_id,"mesh").is_empty():return reject(bindings.error)
	var selected:={"player":bindings.resolve_ship_layers(context.ship_id),0:bindings.resolve_ship_layers(actor.hull_catalogue_id)}
	if selected.player.is_empty() or selected[0].is_empty():return reject(bindings.error)
	var state:={"base_content_id":context.base_content_id,"binding_id":context.binding_id,"campaign_cursor":1,
		"player_pose":Transform3D(Vectors.local_xyz(initial.player_model_rotation).transposed(),initial.frame.player_position),
		"actors":[{"actor_id":0,"hull_catalogue_id":actor.hull_catalogue_id,"hull_resource":selected[0].path,
			"position":actor.position,"pose":Transform3D(Basis.IDENTITY,actor.position),"visible":actor.model_draw_enabled}]}
	if not _assemble(library,visuals,bindings,selected,state,quality,with_detail,1):return false
	_arrival_player_origin=initial.frame.player_position
	return true

func build_departure(library: RefCounted, visuals: RefCounted, bindings: RefCounted, catalogues: RefCounted, cache: Variant, state: Dictionary, quality := "high", with_detail := false, equipment: RefCounted=null) -> bool:
	clear()
	var location:=ArrivalLocation.new()
	var context:=location.resolve_departure(bindings,catalogues,cache,equipment)
	if context.is_empty():return reject(location.error)
	var objective:=OrdinaryFlight.objective(bindings,int(context.campaign_cursor))
	_departure_return_available=int(context.campaign_cursor) in [2,4,7,16,25,26,29] and not objective.is_empty()
	_departure_return_cursor=int(context.campaign_cursor)+1
	if _departure_return_available:
		_departure_return_mission={"kind":int(objective.next_kind),"station_id":int(objective.station_id),"reward":0,"bonus":0}
		if objective.get("alioth_attack",false):_departure_return_mission.source_parameter=0
		if objective.has("next_mission"):_departure_return_mission=objective.next_mission.duplicate(true)
	var rescue:=Campaign.rescue_at(bindings.mido_travel,context.campaign_cursor,context.station_id)
	if Campaign.visit_at(bindings.mido_travel,context.campaign_cursor,context.station_id) or rescue:
		var mission:=Campaign.mission(bindings.mido_travel,context.campaign_cursor)
		var visit:=Campaign.result_rules(bindings,context.campaign_cursor,mission) if rescue else Campaign.dialogue_rules(bindings,context.campaign_cursor,mission)
		_visit_transition={"base_content_id":context.base_content_id,"binding_id":context.binding_id,
			"from_cursor":int(context.campaign_cursor),"campaign_cursor":int(visit.next_cursor),
			"previous_mission":Campaign.mission(bindings.mido_travel,int(context.campaign_cursor)),
			"mission":Campaign.mission(bindings.mido_travel,int(visit.next_cursor)),
			"station_id":int(context.station_id),"reward_credits":int(visit.reward_credits)}
		if rescue:_visit_transition.outcome="completed"
		_visit_system_id=int(context.system_id)
	if (state.get("campaign_cursor")!=context.campaign_cursor and not _is_departure_return(state) and not _is_acknowledged_visit(state)) or state.get("base_content_id")!=context.base_content_id or state.get("binding_id")!=context.binding_id or state.get("actors")!=[]:
		return reject("Departure player geometry requires its supported mining world")
	var selected:={"player":bindings.resolve_ship_layers(context.ship_id)}
	if selected.player.is_empty():return reject(bindings.error)
	return _assemble(library,visuals,bindings,selected,state,quality,with_detail,int(context.campaign_cursor))

func _assemble(library: RefCounted, visuals: RefCounted, bindings: RefCounted, selected: Dictionary, state: Dictionary, quality: String, with_detail: bool, cursor: int) -> bool:
	var paths := []
	var player_glow: bool=with_detail and cursor in [2,4,7,10,11,12,13,14,16] and bindings.source_architecture=="x86_64"
	if player_glow:
		var glow: Dictionary=bindings.resolve_player_engine_glow(selected.player.ship_id,quality)
		if glow.is_empty():return reject(bindings.error)
		paths.append(glow.path)
	for ship in selected.values():
		if ship.ship_id in [13, 14, 15]: return reject("Special ship construction is not implemented in the opening renderer")
		if not ship.light_bindings_available: return reject("Opening ship light bindings are unavailable")
		if with_detail:
			var detail: Dictionary = bindings.resolve_ship_detail(ship.ship_id)
			if detail.is_empty(): return reject(bindings.error)
			for level in detail.levels:
				paths.append(level.path)
				for light in level.lights: paths.append(light.path)
		else:
			paths.append(ship.path)
			for light in ship.lights: paths.append(light.path)
	var resources := Resources.new()
	if not resources.prepare(paths, library, visuals, bindings, quality, true): return reject(resources.error)
	for id in selected:
		var ship: Dictionary = selected[id]
		var body: Node3D
		if with_detail:
			body=ShipGeometry.new()
			if not body.build(ship.ship_id,library,visuals,bindings,quality,resources,player_glow and id is String):
				var message: String = body.error
				body.free();resources.clear();clear()
				return reject(message)
		else:
			body=resources.instantiate(ship.path)
			for light in ship.lights:
				var layer: Node3D = resources.instantiate(light.path)
				layer.set_meta("source_resource_id", light.resource_id)
				layer.set_meta("source_light_slot", light.slot)
				body.add_child(layer)
		body.name = "Player" if id is String else "Actor%d" % id
		body.set_meta("source_ship_id", ship.ship_id)
		body.set_meta("source_resource_id", ship.resource_id)
		add_child(body)
		if id is String: player = body
		else:
			body.set_meta("source_actor_id", id)
			actors[id] = body
	resources.clear()
	_definitions = selected
	_content_id = library.manifest.get("content_id", "")
	_binding_id = bindings.binding_id
	_campaign_cursor=cursor
	_escape_available=cursor==0 and not bindings.opening_staging.get("escape_camera",{}).is_empty()
	# Detail levels remain hidden until the timeline supplies its initial batch.
	if not apply_state(state):
		var message := error
		clear()
		return reject(message)
	_with_detail=with_detail
	return true

func apply_arrival(staging: Dictionary, actor: Dictionary, detail: Dictionary = {}) -> bool:
	error=""
	if _campaign_cursor!=1 or player==null:return reject("Build rescue geometry before applying its frame")
	for row in [staging,actor]:
		if row.get("base_content_id")!=_content_id or row.get("binding_id")!=_binding_id or row.get("campaign_cursor")!=1:return reject("Rescue geometry received another flight identity")
		for key in ["generation","elapsed_ms"]:
			if not row.get(key) is int or row[key]<0 or row[key]!=staging.get(key):return reject("Rescue model and choreography frames disagree")
	if actor.get("actor_id")!=0 or actor.get("hull_catalogue_id")!=30 or not actor.get("model_draw_enabled") is bool or not actor.get("engine_draw_enabled") is bool or actor.engine_draw_enabled or actor.get("engine_resource_id")!=18030:return reject("Rescue model visibility or engine-effect state is unsupported")
	for key in ["body_pose","model_local_pose","statistics_pose"]:
		if not valid_pose(actor.get(key)):return reject("Rescue model pose is invalid")
	var rotation: Variant=staging.get("player_model_rotation")
	if not rotation is Vector3 or not rotation.is_finite():return reject("Rescue player rotation is invalid")
	var frame: Variant=staging.get("frame")
	if not frame is Dictionary or not frame.get("initial") is bool:return reject("Rescue model frame is missing")
	if frame.initial!=(staging.generation==0):return reject("Rescue model frame has an inconsistent entry state")
	if frame.initial:
		if not frame.get("actor") is Dictionary or not frame.actor.get("position") is Vector3 or not frame.get("player_position") is Vector3:return reject("Rescue model entry placement is missing")
		if frame.player_position!=_arrival_player_origin or not actor.body_pose.is_equal_approx(Transform3D(Basis.IDENTITY,frame.actor.position)):return reject("Rescue model entry placement disagrees with construction")
	if not frame.initial and (not valid_pose(frame.get("actor_pose_override")) or not frame.actor_pose_override.is_equal_approx(actor.body_pose)):return reject("Rescue actor has not received its scripted pose")
	var pose: Transform3D=actor.body_pose*actor.model_local_pose
	if not pose.is_equal_approx(actor.statistics_pose):return reject("Rescue model and statistics transforms disagree")
	var state:={"base_content_id":_content_id,"binding_id":_binding_id,"campaign_cursor":1,
		"player_pose":Transform3D(Vectors.local_xyz(rotation).transposed(),_arrival_player_origin),
		"actors":[{"actor_id":0,"hull_catalogue_id":30,"hull_resource":_definitions[0].path,
			"position":pose.origin,"pose":pose,"visible":actor.model_draw_enabled}]}
	if _with_detail:state.ship_detail=detail
	return apply_state(state)

func _is_departure_return(state: Dictionary) -> bool:
	var objective: Variant=state.get("mining_objective",{})
	return _departure_return_available and state.get("campaign_cursor")==_departure_return_cursor and objective is Dictionary and objective.get("phase") in ["return_required","portal_search","free_navigation"] and objective.get("combat_objective_acknowledged",objective.get("cargo_objective_acknowledged",false)) and state.get("mission")==_departure_return_mission

func _is_acknowledged_visit(state: Dictionary) -> bool:
	if _visit_transition.is_empty():return false
	var visit: Dictionary=state.get("mining_objective",{}).get("campaign_visit",{})
	var location: Dictionary=state.get("location",{})
	return state.get("campaign_cursor")==_visit_transition.campaign_cursor and state.get("mission")==_visit_transition.mission \
		and state.get("contracts",{}).get("flight",{}).get("story_transition") == _visit_transition \
		and location.get("station_id")==_visit_transition.station_id and location.get("system_id")==_visit_system_id \
		and state.get("player",{}).get("campaign_cursor")==_visit_transition.from_cursor \
		and visit.get("base_content_id")==_visit_transition.base_content_id and visit.get("binding_id")==_visit_transition.binding_id \
		and visit.get("campaign_cursor")==_visit_transition.from_cursor and visit.get("mission")==_visit_transition.previous_mission \
		and visit.get("phase")=="acknowledged" and visit.get("acknowledged")==true

func apply_state(state: Dictionary, escape: Dictionary = {}) -> bool:
	error = ""
	if player == null: return reject("Build opening geometry before applying scene state")
	if state.get("base_content_id") != _content_id or state.get("binding_id") != _binding_id:
		return reject("Opening geometry received another content identity")
	# Acknowledged objectives change the mission while retaining this
	# same world and ship. It does not construct a new station or flight scene.
	if state.get("campaign_cursor",0)!=_campaign_cursor and not _is_departure_return(state) and not _is_acknowledged_visit(state):return reject("Flight geometry received another campaign scene")
	if not valid_pose(state.get("player_pose")): return reject("Opening player pose is unavailable or invalid")
	var rows: Variant = state.get("actors")
	if not rows is Array or rows.size() != actors.size(): return reject("Opening actor set changed")
	var next := {}
	for row in rows:
		if not row is Dictionary: return reject("Opening actor state is invalid")
		var id: Variant = row.get("actor_id")
		if not id is int or not actors.has(id) or next.has(id): return reject("Opening actor identity is invalid or duplicated")
		var selected: Dictionary = _definitions[id]
		if row.get("hull_catalogue_id") != selected.ship_id or row.get("hull_resource") != selected.path:
			return reject("Opening actor hull changed without rebuilding geometry")
		var position_value: Variant = row.get("position")
		if not position_value is Vector3 or not position_value.is_finite() or not row.get("visible") is bool:
			return reject("Opening actor placement or visibility is invalid")
		if row.has("pose"):
			if not valid_pose(row.pose) or not row.pose.origin.is_equal_approx(position_value): return reject("Opening actor pose disagrees with its position")
		elif row.visible: return reject("A visible opening actor requires its source pose")
		next[id] = row
	var detail := {}
	if _with_detail:
		var group: Variant = state.get("ship_detail")
		if not group is Dictionary or group.get("base_content_id")!=_content_id or group.get("binding_id")!=_binding_id or not group.get("selections") is Dictionary:
			return reject("Opening detail selections belong to another or missing content identity")
		detail=group.selections
		if detail.size()!=actors.size()+1 or not player.valid_selection(detail.get("player")): return reject("Invalid opening player detail selection")
		for id in actors:
			if not actors[id].valid_selection(detail.get(id)): return reject("Invalid opening actor detail selection")
	var player_pose: Transform3D=state.player_pose
	var player_visible:=true
	if state.has("player_model_basis"):
		if _campaign_cursor not in ([2,4]+FlightStages.EQUIPPED) or not state.player_model_basis is Basis or not valid_pose(Transform3D(state.player_model_basis,Vector3.ZERO)):return reject("Invalid mining-flight visual model orientation")
		player_pose=player_pose*Transform3D(state.player_model_basis,Vector3.ZERO)
		if not valid_pose(player_pose):return reject("First-flight visual model orientation overflowed")
	if not escape.is_empty():
		if not _escape_available or escape.get("base_content_id")!=_content_id or escape.get("binding_id")!=_binding_id or not escape.get("model_rotation") is Vector3 or not escape.model_rotation.is_finite() or not escape.get("ship_visible") is bool:
			return reject("Invalid escape player presentation")
		# The source visual model is a child of the logical player root. Its fixed
		# Euler setter uses the transposed XYZ matrix; logical travel is unchanged.
		player_pose=player_pose*Transform3D(Vectors.local_xyz(escape.model_rotation).transposed(),Vector3.ZERO)
		if not valid_pose(player_pose):return reject("Escape player model rotation overflowed")
		player_visible=escape.ship_visible
	# Validate the whole frame before moving any node.
	player.transform=player_pose
	player.visible=player_visible
	for id in next:
		var row: Dictionary = next[id]
		var body: Node3D = actors[id]
		if row.has("pose"): body.transform = row.pose
		else: body.position = row.position
		body.visible = row.visible
	if _with_detail:
		player.apply_selection(detail.player)
		for id in actors: actors[id].apply_selection(detail[id])
	return true

static func valid_pose(value: Variant) -> bool:
	return value is Transform3D and value.origin.is_finite() and value.basis.is_finite() \
		and value.basis.determinant() > 0.0 and value.basis.is_equal_approx(value.basis.orthonormalized())

func clear() -> void:
	for child in get_children(): child.free()
	surface_materials.clear()
	player = null
	engine_particles=null
	actors.clear()
	_definitions.clear()
	_content_id = ""
	_binding_id = ""
	_with_detail = false
	_escape_available=false
	_campaign_cursor=0;_departure_return_available=false;_departure_return_cursor=3;_departure_return_mission={}
	_visit_transition={};_visit_system_id=-1
	_arrival_player_origin=Vector3.ZERO

func reject(message: String) -> bool:
	error = message
	return false
