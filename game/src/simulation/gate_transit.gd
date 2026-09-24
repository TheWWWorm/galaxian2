extends RefCounted
const Frames=preload("res://src/simulation/frame_clock.gd")
var _max_ms:=0
## Contact, acknowledgement and departure cinematic. A completed animation only
## requests arrival; the flight transaction still validates and constructs it.
const Definitions=preload("res://src/content/gate_transit_definitions.gd")
const GateAnimation=preload("res://src/simulation/gate_animation.gd")
const Navigation=preload("res://src/simulation/system_navigation.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const Arrival=preload("res://src/content/gate_arrival_definitions.gd")
var error:=""
var _state:={}
var _rules:={}
var _departure:={}
var _gate:={}
var _animation: RefCounted
var _navigation: RefCounted

func configure(bindings: RefCounted,animation: RefCounted,navigation: RefCounted) -> bool:
	error=""
	if not Definitions.available(bindings) or not animation is GateAnimation or not navigation is Navigation:return reject("Gate transit requires native animation and system navigation")
	var visual: Dictionary=animation.snapshot();var routing: Dictionary=navigation.snapshot()
	if visual.is_empty() or routing.is_empty():return reject("Prepare the gate and route before transit")
	var layout: Dictionary=visual.layout
	for key in ["base_content_id","binding_id"]:
		if layout.get(key)!=bindings.get(key) or routing.get(key)!=bindings.get(key):return reject("Gate transit owners belong to different content")
	var gate:={}
	for row in layout.objects:
		if row.index==int(bindings.mido_travel.gate_transit.contact.environment_object_index):gate=row
	if gate.is_empty() or not gate.interactive or layout.station_id!=layout.gate_station_id or animation.object_state(1).active:return reject("This location has no unused outgoing gate")
	_rules=bindings.mido_travel.gate_transit.duplicate(true);_gate=gate.duplicate(true)
	_max_ms=Frames.simulation_limit(bindings,150)
	_departure=bindings.mido_travel.gate_arrival.departure.duplicate(true) if Arrival.available(bindings) else {}
	_animation=animation.fork_for_frame();_navigation=navigation.fork()
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"station_id":layout.station_id,"system_id":layout.system_id,"phase":"flight",
		"course":{},"coasting":false,"player_pose":Transform3D.IDENTITY,"speed":0.0,
		"camera_position":Vector3.ZERO,"elapsed_ms":0,"events":[]}
	return true

func set_course(destination: int) -> bool:
	error=""
	if _state.is_empty() or _state.phase not in ["flight","map"]:return reject("Choose a gate destination before departure")
	var course: Dictionary=_navigation.course(_state.station_id,destination)
	if course.is_empty() or course.guidance.get("kind")!="gate":return reject("The selected destination does not use this outgoing gate")
	if course.jump_count!=1:return reject("Select a destination in a directly connected system")
	_state=_state.duplicate(true);_state.course=course
	return true

func contains(position: Vector3) -> bool:
	if _state.is_empty() or not position.is_finite():return false
	# Original contact compares against truncated integer object coordinates.
	var origin: Vector3=_gate.pose.origin
	var center:=Vector3(int(origin.x),int(origin.y),int(origin.z))
	var offset:=Vectors.added(position,-center)
	var bound: float=_gate.collision_radius
	return offset.x>-bound and offset.x<bound and offset.y>-bound and offset.y<bound and offset.z>-bound and offset.z<bound

func observe_contact(pose: Transform3D,speed: float,guidance_active: bool,target_is_gate: bool,mission: Dictionary) -> bool:
	error=""
	if _state.is_empty() or _state.phase!="flight" or not Flight.rigid_pose(pose) or not is_finite(speed) or speed<0 or speed>2147483647:return reject("Gate contact requires the current finite flight state")
	if not mission.get("kind") is int or not mission.get("completed") is bool:return reject("Gate contact requires the active mission state")
	if not contains(pose.origin) or (not mission.completed and not _rules.contact.mission_allowlist.has(mission.kind)):return true
	var next:=_state.duplicate(true);next.player_pose=pose;next.speed=speed;next.events=[]
	if target_is_gate and not next.coasting:
		next.coasting=true;next.events=[{"kind":"coast"}]
	elif not next.course.is_empty() and (guidance_active or target_is_gate):
		next.phase="confirmation";next.events=[{"kind":"clear_guidance"}]
	elif target_is_gate:
		next.phase="map";next.events=[{"kind":"clear_guidance"}]
	_state=next
	return true

func choose_confirmation(result: int) -> bool:
	error=""
	if _state.is_empty() or _state.phase!="confirmation" or result not in [int(_rules.confirmation.accept_result),int(_rules.confirmation.map_result)]:return reject("No gate confirmation accepts this choice")
	if result==int(_rules.confirmation.map_result):
		_state=_state.duplicate(true);_state.phase="map";_state.events=[];return true
	return _begin_departure()

func close_map(accepted: bool) -> bool:
	error=""
	if _state.is_empty() or _state.phase!="map":return reject("The gate destination map is not open")
	if accepted:return _begin_departure()
	var next:=_state.duplicate(true)
	next.phase="flight";next.coasting=false;next.speed=float(_rules.confirmation.cancel_speed)
	var pose: Transform3D=_gate.pose
	pose.origin=Vectors.added(pose.origin,vec(_rules.confirmation.cancel_gate_offset))
	next.player_pose=pose;next.events=[{"kind":"clear_guidance"},{"kind":"resume_flight"}]
	_state=next
	return true

func _begin_departure() -> bool:
	if _state.is_empty() or _state.phase not in ["confirmation","map"] or _state.course.is_empty():return reject("A retained destination and gate acknowledgement must precede departure")
	var next:=_state.duplicate(true)
	if not _departure.is_empty():
		next.speed=float(_departure.speed_units_per_ms)
		next.departure_permissions={"damage_allowed":bool(_departure.damage_allowed),"collision_enabled":bool(_departure.collision_enabled),"boost_enabled":bool(_departure.boost_enabled)}
		next.reset_primary_fire_intervals=bool(_departure.confirmation_resets_primary if next.phase=="confirmation" else _departure.map_resets_primary)
	next.phase="departing";next.elapsed_ms=0;next.events=[{"kind":"clear_guidance"}]
	next.player_pose=Transform3D(Basis.IDENTITY,Vectors.added(_gate.pose.origin,vec(_rules.cinematic.player_gate_offset)))
	next.camera_position=Vectors.added(next.player_pose.origin,vec(_rules.cinematic.camera_player_offset))
	_state=next
	return true

func advance(milliseconds: int,paused:=false) -> bool:
	error=""
	if _state.is_empty() or not Numbers.integer(milliseconds,0,_max_ms):return reject("Gate transit requires a bounded ordinary frame")
	if paused or _state.phase in ["confirmation","map","ready"]:return true
	var animation: RefCounted=_animation.fork_for_frame()
	if not animation.advance(milliseconds):return reject(animation.error)
	if _state.phase!="departing":_animation=animation;return true
	var next:=_state.duplicate(true);next.events=[];next.elapsed_ms+=milliseconds
	# Player movement and model clocks precede the HUD's cinematic update.
	next.player_pose.origin=Vectors.added(next.player_pose.origin,Vectors.scaled(Vector3.BACK,float(milliseconds)*float(next.speed)))
	var fast: bool=animation.accelerating()
	if not fast:
		next.camera_position=Vectors.added(next.camera_position,Vectors.scaled(vec(_rules.cinematic.camera_velocity),float(milliseconds)))
	if _gate.pose.origin.z+float(_rules.cinematic.activation_camera_gate_z)>next.camera_position.z:
		if not animation.object_state(1).active:next.events.append({"kind":"gate_activation"})
		if not animation.activate(1):return reject(animation.error)
	if fast:next.speed=float(_rules.cinematic.fast_speed)
	if animation.completed():next.phase="ready";next.events.append({"kind":"arrival_requested"})
	if not Flight.rigid_pose(next.player_pose) or not next.camera_position.is_finite():return reject("Gate cinematic exceeds source coordinates")
	_state=next;_animation=animation
	return true

func confirmation() -> Dictionary:
	if _state.is_empty() or _state.phase!="confirmation":return {}
	return {"text_ids":_rules.confirmation.text_ids.duplicate(),"separators":_rules.confirmation.separators.duplicate(),"destination_station_id":_state.course.destination_station_id}

func arrival_request() -> Dictionary:
	if _state.is_empty() or _state.phase!="ready":return {}
	return {"base_content_id":_state.base_content_id,"binding_id":_state.binding_id,
		"from_station_id":_state.station_id,"destination_station_id":_state.course.destination_station_id}

func animation() -> RefCounted:return _animation.fork_for_frame() if _animation!=null else null
func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	var result:=_state.duplicate(true);result.animation=_animation.snapshot();return result
func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._state=_state.duplicate(true);copy._rules=_rules.duplicate(true);copy._gate=_gate.duplicate(true)
	copy._departure=_departure.duplicate(true)
	copy._animation=_animation.fork_for_frame() if _animation!=null else null;copy._navigation=_navigation.fork() if _navigation!=null else null
	copy._max_ms=_max_ms;return copy
static func vec(value: Array) -> Vector3:return Vector3(value[0],value[1],value[2])
func reject(message: String) -> bool:error=message;return false
