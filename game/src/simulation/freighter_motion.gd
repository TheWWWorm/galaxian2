extends RefCounted
const FreeTraffic=preload("res://src/content/free_traffic_definitions.gd")
const Alioth=preload("res://src/content/alioth_population_definitions.gd")
## Straight-line freighter motion in original coordinates. The encounter owns
## stun, life-mode and world pause gates, and supplies their resolved permission.
## This owner does not complete routes, destroy ships or award recovered cargo.
const Construction=preload("res://src/simulation/opening_npc_construction.gd")
const Ambient=preload("res://src/content/ambient_population_definitions.gd")
const Frames=preload("res://src/simulation/frame_clock.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
const Geometry=preload("res://src/presentation/opening_geometry.gd")
const Convoy=preload("res://src/content/convoy_ship_definitions.gd")
const ConvoyRules=preload("res://src/content/convoy_capture_definitions.gd")
const Capture=preload("res://src/simulation/convoy_capture.gd")
var error:=""
var _state:={}
var _max_ms:=0

func configure(bindings: RefCounted,construction: RefCounted,actor_id: Variant) -> bool:
	clear()
	if bindings==null or not construction is Construction or not Frames.valid_parameters(bindings.frame_clock) or not Ambient.parameters(bindings.ambient_population):return reject("Freighter motion requires a supported generated population")
	var population: Dictionary=construction.snapshot()
	if population.get("base_content_id")!=bindings.base_content_id or population.get("binding_id")!=bindings.binding_id:return reject("Freighter motion belongs to another content identity")
	var actors: Array=population.get("actors",[])
	if not Numbers.integer(actor_id,0,actors.size()-1):return reject("Freighter actor is outside the generated population")
	var actor: Dictionary=actors[int(actor_id)]
	if population.has("free_context"):
		var context: Dictionary=population.free_context
		if FreeTraffic.population(bindings,population,context.get("rank"),context.get("difficulty")).is_empty() or actor.get("population_group")!="freighter":return reject("Unsupported ordinary freighter motion")
	elif actor.get("population_group")!="freighter" or actor.get("actor_kind")!=int(bindings.ambient_population.actor_kind) or actor.get("hull_catalogue_id")!=int(bindings.ambient_population.freighter.hull_catalogue_id) or actor.get("subtype")!=1 or actor.get("world_flag")!=true or not Ambient.assembly_matches(bindings.ambient_population,actor.get("assembly")):return reject("Unsupported freighter motion construction")
	if not Geometry.valid_pose(actor.get("body_pose")) or actor.get("statistics_pose")!=actor.body_pose or actor.get("model_local_pose")!=Transform3D.IDENTITY:return reject("Freighter construction lost its source pose")
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":population.campaign_cursor,
		"actor_id":int(actor_id),"actor_kind":actor.actor_kind,"hull_catalogue_id":actor.hull_catalogue_id,
		"body_pose":actor.body_pose,"statistics_pose":actor.statistics_pose,
		"source_position":Vector3i(actor.body_pose.origin),"elapsed_motion_ms":0}
	_max_ms=Frames.simulation_limit(bindings)
	return true

func configure_convoy(bindings: RefCounted,actor_id: Variant) -> bool:
	clear()
	if not Convoy.available(bindings) or not ConvoyRules.available(bindings) or not Frames.valid_parameters(bindings.frame_clock):return reject("Convoy motion requires its original ship and capture declarations")
	var data: Dictionary=bindings.mido_travel.convoy_ship
	var ids: Array=data.actor_ids.map(func(id):return int(id))
	if not Numbers.integer(actor_id,0,6) or int(actor_id) not in ids:return reject("Actor is not an authored convoy capital ship")
	var population: Dictionary=bindings.mido_travel.convoy_capture.population
	var index: int=ids.find(int(actor_id))
	var point: Array=population.waypoints[0]
	var offset: Array=population.freighter_offsets[index]
	var position:=Vector3(point[0]+offset[0],point[1]+offset[1],point[2]+offset[2])
	# Native motion stays in source world units. The original model's uniform
	# scale belongs to ShipGeometry and must not double displacement or boxes.
	var pose:=Transform3D(Basis.IDENTITY,position)
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(data.campaign_cursor),
		"actor_id":int(actor_id),"actor_kind":int(data.actor_kind),"hull_catalogue_id":int(data.hull_catalogue_id),
		"body_pose":pose,"statistics_pose":pose,"source_position":Vector3i(position),"elapsed_motion_ms":0,
		"convoy_ship":true,"cruise_enabled":bool(data.motion.initial_cruise_enabled),
		"capture_actor_id":int(data.motion.capture_actor_id),"capture_phase":Capture.Stage.INTERCEPTION}
	_max_ms=Frames.simulation_limit(bindings)
	return true

func configure_alioth_attack(bindings: RefCounted,construction: RefCounted,actor_id: Variant) -> bool:
	clear()
	if not construction is Construction or not Frames.valid_parameters(bindings.frame_clock):return reject("Alioth motion requires its generated encounter")
	var packet: Dictionary=construction.snapshot()
	var data:=Alioth.lifecycle(bindings,packet)
	if data.is_empty() or not Numbers.integer(actor_id,0,data.actor_count-1):return reject("Unsupported Alioth motion actor")
	var row: Dictionary=packet.actors[actor_id]
	if row.population_group!="freighter":return reject("Alioth motion requires an original freighter")
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(data.campaign_cursor),
		"actor_id":actor_id,"actor_kind":row.actor_kind,"hull_catalogue_id":row.hull_catalogue_id,
		"body_pose":row.body_pose,"statistics_pose":row.statistics_pose,"source_position":Vector3i(row.body_pose.origin),
		"elapsed_motion_ms":0,"cruise_enabled":row.cruise_enabled}
	_max_ms=Frames.simulation_limit(bindings)
	return true

func _configure_story(bindings: RefCounted,data: Dictionary,row: Dictionary) -> bool:
	clear()
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(data.campaign_cursor),
		"actor_id":row.actor_id,"actor_kind":row.actor_kind,"hull_catalogue_id":row.hull_catalogue_id,
		"body_pose":row.body_pose,"statistics_pose":row.statistics_pose,"source_position":Vector3i(row.body_pose.origin),
		"elapsed_motion_ms":0,"cruise_enabled":row.cruise_enabled}
	_max_ms=Frames.simulation_limit(bindings)
	return true

func apply_capture(capture: RefCounted) -> bool:
	error=""
	if not _state.get("convoy_ship",false) or not capture is Capture:return reject("Cruise permission requires the convoy capture owner")
	var packet: Dictionary=capture.snapshot()
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if packet.get(key)!=_state[key]:return reject("Capture and convoy motion belong to different encounters")
	if packet.phase<_state.capture_phase:return reject("Convoy capture cannot move backwards")
	_state.capture_phase=packet.phase
	_state.cruise_enabled=_state.actor_id==_state.capture_actor_id and packet.phase>=Capture.Stage.CAPTURE_VIEW
	return true

func update(delta_ms: Variant,movement_enabled: Variant) -> bool:
	error=""
	if _state.is_empty():return reject("Configure freighter motion before advancing")
	if not Numbers.integer(delta_ms,0,_max_ms) or not movement_enabled is bool:return reject("Invalid freighter frame duration or movement permission")
	if not movement_enabled or not _state.get("cruise_enabled",true) or delta_ms==0:return true
	var pose: Transform3D=_state.body_pose
	# The original model movement advances a normalized local +Z by elapsed
	# milliseconds. Scale on imported geometry cannot multiply cruise speed.
	pose.origin=Vectors.added(pose.origin,Vectors.scaled(Vectors.normalized(pose.basis.z),float(delta_ms)))
	if not Geometry.valid_pose(pose):return reject("Freighter displacement exceeds supported coordinates")
	_state.body_pose=pose;_state.statistics_pose=pose
	# The source also retains integer XYZ; ordinary cruise increments only Z.
	_state.source_position.z+=int(delta_ms)
	_state.elapsed_motion_ms+=int(delta_ms)
	return true

func source_position() -> Vector3i:return _state.source_position

## The tractor uses the freighter's retained integer origin, not the model's
## fractional cruise position. Commit it alongside the same recovery frame.
func _retain_recovery_frame(frame: Dictionary) -> void:
	var changes: Dictionary=frame.actor_changes
	if changes.has("freighter_position"):
		_state.source_position=changes.freighter_position
		_state.body_pose=changes.body_pose;_state.statistics_pose=changes.statistics_pose

func snapshot() -> Dictionary:return _state.duplicate(true)

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._state=_state.duplicate(true);copy._max_ms=_max_ms
	return copy

func clear() -> void:error="";_state={};_max_ms=0
func reject(message: String) -> bool:error=message;return false
