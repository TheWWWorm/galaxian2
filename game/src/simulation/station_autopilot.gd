extends RefCounted
## Source-bound guidance to the first mining station. The caller supplies the
## preceding manual response sample and each frame's pitch response, owns
## frame/input ordering and checks arrival.
## The logical camera target stays separate from the visible banked ship.
const Definitions=preload("res://src/content/station_autopilot_definitions.gd")
const OrdinaryFlight=preload("res://src/content/ordinary_flight_definitions.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Station=preload("res://src/content/station_exterior_resources.gd")
const Vehicle=preload("res://src/simulation/vehicle_response.gd")
const Guidance=preload("res://src/simulation/player_guidance.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
var error:=""
var _rules:={}
var _identity:={}
var _state:={}
var _gain:=0.0
var _response:=0.0
var _limit:=0.0
var _speed:=0.0
var _history: Array=[]
var _cursor:=0
var _wrapped:=false
var _manual_sample:=false

func configure(bindings: RefCounted, catalogues: RefCounted, construction: RefCounted, station: RefCounted) -> bool:
	error=""
	if bindings==null or catalogues==null or construction==null or construction.get_script()!=Construction or station==null or station.get_script()!=Station or not Definitions.parameters(bindings.station_autopilot):return reject("This flight has no supported station autopilot")
	var entry: Dictionary=construction.snapshot();var target: Dictionary=station.snapshot()
	for data in [entry,target]:
		if data.get("base_content_id")!=bindings.base_content_id or data.get("binding_id")!=bindings.binding_id:return reject("Station autopilot belongs to another flight identity")
	var rules: Dictionary=bindings.station_autopilot
	if OrdinaryFlight.select(bindings,entry.get("campaign_cursor")).is_empty() or entry.get("location",{}).get("station_id")!=int(rules.station_id) or entry.location.get("system_id")!=int(rules.system_id) or target.get("station_id")!=int(rules.station_id) or target.get("system_id")!=int(rules.system_id):return reject("Station autopilot requires the supported mining location")
	var destination:=Vector3(rules.target_position[0],rules.target_position[1],rules.target_position[2])
	if not target.get("pose") is Transform3D or target.pose.origin!=destination:return reject("Station autopilot target differs from its authored position")
	var vehicle:=Vehicle.new()
	if not vehicle.configure(bindings,catalogues,bindings.base_content_id):return reject(vehicle.error)
	var loadout: Dictionary=entry.departure.loadout
	var response:=vehicle.resolve(int(loadout.ship_id),[],loadout.equipment_ids,true)
	if response.is_empty():return reject(vehicle.error)
	var gain:=minf(float(rules.maximum_gain),single(float(response.effective_handling)+float(rules.response_add)))
	var factor:=float(response.response_factor)
	var limit:=single(single(single(factor*float(rules.bank_limit_numerator))/float(rules.bank_limit_divisor))*float(rules.bank_limit_scale))
	var speed: Variant=bindings.cruise.get("speed_units_per_millisecond")
	if not is_finite(limit) or limit<=0 or limit>2147483647.0 or not (speed is int or speed is float) or not is_finite(speed) or speed<=0:return reject("Station autopilot response exceeds supported coordinates")
	_rules=rules.duplicate(true);_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_gain=gain;_response=factor;_limit=limit;_speed=float(speed)
	_history.resize(int(rules.bank_samples));_history.fill(0.0);_cursor=0;_wrapped=false;_manual_sample=false
	_state={"active":false,"station_id":int(rules.station_id),"target_position":destination,"player_pose":entry.player_pose,
		"model_basis":Basis.IDENTITY,"angular_units":Vector2.ZERO,"bank":0.0,"target_bank":0.0,"signed_turn":0.0,
		"throttle":float(rules.start_throttle),"near_target":false,"elapsed_ms":0,"events":[]}
	return true

func observe_manual(pose: Transform3D, angular_units: Vector2) -> bool:
	error=""
	if _state.is_empty() or _state.active:return reject("A manual sample requires inactive station guidance")
	if not proper_pose(pose) or not angular_units.is_finite() or absf(angular_units.x)>2147483647.0 or absf(angular_units.y)>2147483647.0:return reject("Invalid preceding manual pose or angular response")
	var model:=visual_basis(angular_units)
	if not proper_pose(Transform3D(model,Vector3.ZERO)):return reject("Manual visual response exceeds supported orientation")
	_state=_state.duplicate(true);_state.player_pose=pose;_state.angular_units=angular_units
	_state.bank=float(angular_units.y);_state.model_basis=model;_state.events=[];_manual_sample=true
	return true

func start(pose: Variant=null) -> bool:
	error=""
	if _state.is_empty() or _state.active or not _manual_sample:return reject("Station guidance requires the preceding manual sample")
	if pose!=null and (not pose is Transform3D or not proper_pose(pose)):return reject("Invalid current station guidance pose")
	_state=_state.duplicate(true);_state.active=true;_state.throttle=float(_rules.start_throttle)
	if pose!=null:_state.player_pose=pose
	_state.events=[{"kind":"notification","source_id":int(_rules.start_notice)}]
	return true

func observe_mining_guidance(before: Transform3D, after: Transform3D) -> bool:
	error=""
	if _state.is_empty() or _state.active or not proper_pose(before) or not proper_pose(after):return reject("Mining guidance requires valid poses and inactive station guidance")
	# Both destinations use the same player turn history. Mining ignores the
	# resulting bank target and retains the preceding manual bank response.
	var turn:=_turn_sample(before.basis,after.basis)
	_history=turn.history;_cursor=turn.cursor;_wrapped=turn.wrapped
	return true

func advance(milliseconds: Variant, pitch_units: float, throttle:=1.0, paused:=false) -> bool:
	error=""
	if _state.is_empty() or not _state.active or not Numbers.integer(milliseconds,0,int(_rules.max_frame_ms)) or not is_finite(pitch_units) or absf(pitch_units)>2147483647.0 or not is_finite(throttle) or throttle<0 or throttle>1:return reject("Station guidance requires an active bounded frame and throttle")
	if paused:return true
	if int(_state.elapsed_ms)>2147483647-int(milliseconds):return reject("Station guidance time exceeds the source range")
	var before: Transform3D=_state.player_pose
	var offset:=Vectors.added(_state.target_position,-before.origin)
	var distance:=single(sqrt(Vectors.dot(offset,offset)))
	if not is_finite(distance) or distance>=2147483648.0:return reject("Station target distance exceeds source coordinates")
	var pose:=Guidance.advance(before,_state.target_position,int(milliseconds),_gain,_speed,float(_rules.turn_fraction),throttle)
	if not proper_pose(pose):return reject("Station guidance produced a degenerate orientation")
	var turn:=_turn_sample(before.basis,pose.basis)
	var target: float=turn.target
	var step:=single(single(float(milliseconds)*_response)*float(_rules.bank_slew_scale))
	var bank: float=_state.bank
	if bank<target:bank=minf(single(bank+step),target)
	elif bank>target:bank=maxf(single(bank-step),target)
	var angular:=Vector2(pitch_units,bank)
	var model:=visual_basis(angular)
	if not proper_pose(Transform3D(model,Vector3.ZERO)):return reject("Station bank exceeds supported orientation")
	var next:=_state.duplicate(true)
	next.merge({"player_pose":pose,"model_basis":model,"angular_units":angular,"bank":bank,"target_bank":target,
		"signed_turn":turn.angle,"near_target":int(distance)<int(_rules.near_distance_limit),"throttle":throttle,
		"elapsed_ms":int(_state.elapsed_ms)+int(milliseconds),"events":[]},true)
	_state=next;_history=turn.history;_cursor=turn.cursor;_wrapped=turn.wrapped
	return true

func _turn_sample(before: Basis, after: Basis) -> Dictionary:
	var angle:=Guidance.signed_turn(before,after.z,float(_rules.bank_sign_angle))
	var history:=_history.duplicate();history[_cursor]=angle
	# During warm-up, the source averages preceding samples; after wrapping,
	# all five samples participate, including the new sample.
	var count:=history.size() if _wrapped else _cursor
	var mean:=angle
	if count>0:
		mean=0.0
		for i in count:mean=single(mean+float(history[i]))
		mean=single(mean/float(count))
	var target:=clampf(-single(single(mean*_limit)*float(_rules.bank_gain)),-_limit,_limit)
	return {"angle":angle,"target":target,"history":history,"cursor":(_cursor+1)%history.size(),"wrapped":_wrapped or _cursor+1==history.size()}

func cancel() -> bool:
	error=""
	if _state.is_empty() or not _state.active:return reject("No station autopilot is active")
	_state=_state.duplicate(true);_state.active=false;_cursor=0;_wrapped=false
	_state.events=[{"kind":"notification","source_id":int(_rules.cancel_notice)}]
	# Retain the response and visible bank for the caller's ordinary player
	# update. Cancelling does not teleport, level the ship or clear samples.
	return true

func visual_basis(angular_units: Vector2) -> Basis:
	var pitch:=single(float(angular_units.x)*float(_rules.pitch_angle_scale)*float(_rules.angle_tau))
	var roll:=single(single(float(angular_units.y)*float(_rules.bank_angle_scale))*float(_rules.angle_tau))
	return Vectors.local_xyz(Vector3(pitch,0,roll))

func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	var result:=_identity.duplicate();result.merge(_state.duplicate(true))
	result.merge({"guidance_gain":_gain,"response_factor":_response,"bank_limit":_limit,"history":_history.duplicate(),"history_cursor":_cursor,"history_wrapped":_wrapped,"manual_sample_available":_manual_sample,
		"docking_transition_supported":false,"avoidance_supported":false})
	result.presentation_pose=result.player_pose*Transform3D(result.model_basis,Vector3.ZERO)
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._rules=_rules;copy._identity=_identity;copy._state=_state.duplicate(true)
	copy._gain=_gain;copy._response=_response;copy._limit=_limit;copy._speed=_speed
	copy._history=_history.duplicate();copy._cursor=_cursor;copy._wrapped=_wrapped;copy._manual_sample=_manual_sample
	return copy

func clear() -> void:
	error="";_rules={};_identity={};_state={};_gain=0;_response=0;_limit=0;_speed=0
	_history=[];_cursor=0;_wrapped=false;_manual_sample=false
static func proper_pose(pose: Transform3D) -> bool:return pose.is_finite() and pose.basis.determinant()>0 and pose.basis.is_equal_approx(pose.basis.orthonormalized())
static func single(value: float) -> float:return Guidance.single(value)
func reject(message: String) -> bool:error=message;return false
