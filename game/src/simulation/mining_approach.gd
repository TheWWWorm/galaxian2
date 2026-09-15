extends RefCounted
## Source first-mining approach, with independent motion and visual tilt.
## A ready result requests the drill owner; it never extracts ore or progresses
## a mission. The flight must apply camera, engine and spin changes together.
const Definitions=preload("res://src/content/mining_approach_definitions.gd")
const OrdinaryFlight=preload("res://src/content/ordinary_flight_definitions.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Targeting=preload("res://src/simulation/mining_targeting.gd")
const Scenery=preload("res://src/simulation/opening_scenery.gd")
const Vehicle=preload("res://src/simulation/vehicle_response.gd")
const Cruise=preload("res://src/simulation/cruise_motion.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
const Guidance=preload("res://src/simulation/player_guidance.gd")
var error:=""
var _rules:={}
var _identity:={}
var _field_identity: RefCounted
var _gain:=0.0
var _speed:=0.0
var _state:={}
var _aligned:=false
var _alignment_open:=false
var _reference_up:=Vector3.ZERO
var _guidance_sample:={}

func configure(bindings: RefCounted, catalogues: RefCounted, construction: RefCounted) -> bool:
	error=""
	if bindings==null or catalogues==null or construction==null or construction.get_script()!=Construction or not Definitions.parameters(bindings.mining_approach):return reject("Mining approach requires a supported mining departure")
	var entry: Dictionary=construction.snapshot()
	if entry.is_empty() or entry.get("base_content_id")!=bindings.base_content_id or entry.get("binding_id")!=bindings.binding_id or OrdinaryFlight.for_departure(bindings,entry).is_empty() or entry.scenery.get("bodies",{}).is_empty():return reject("Mining approach belongs to another or incomplete flight")
	var vehicle:=Vehicle.new();var cruise:=Cruise.new()
	if not vehicle.configure(bindings,catalogues,bindings.base_content_id) or not cruise.configure(bindings,bindings.base_content_id):return reject(vehicle.error+cruise.error)
	var loadout: Dictionary=entry.departure.loadout
	var response:=vehicle.resolve(int(loadout.ship_id),[],loadout.equipment_ids)
	if response.is_empty():return reject(vehicle.error)
	_rules=bindings.mining_approach.duplicate(true)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_field_identity=construction.scenery_owner().presentation_identity()
	# Guidance reads the ship handling getter before pilot scaling or equipment.
	_gain=minf(float(_rules.maximum_gain),f32(float(response.effective_handling)+float(_rules.response_add)))
	_speed=float(bindings.cruise.speed_units_per_millisecond)
	_aligned=false;_alignment_open=false;_reference_up=Vector3.ZERO
	_guidance_sample={}
	_state={"phase":"idle","object_index":-1,"elapsed_ms":0,"tilt_units":0.0,"stand_off":0,
		"player_pose":entry.player_pose,"model_basis":Basis.IDENTITY,"throttle":1.0,
		"camera_update_enabled":true,"engine_visible":true,"spin_enabled":true,
		"near_asteroid":false,"events":[]}
	return true

func start(scenery: RefCounted, selection: RefCounted, pose: Transform3D, model_basis:=Basis.IDENTITY, throttle:=1.0) -> bool:
	error=""
	if _state.is_empty() or _state.phase!="idle" or selection==null or selection.get_script()!=Targeting or selection.field_identity()!=_field_identity:return reject("Mining approach requires its active field's asteroid selection")
	var selected: Dictionary=selection.snapshot()
	for key in _identity:
		if selected.get(key)!=_identity[key]:return reject("Mining selection belongs to another content profile")
	if not proper_pose(pose) or not proper_pose(Transform3D(model_basis,Vector3.ZERO)) or not is_finite(throttle) or throttle<0 or throttle>1:return reject("Invalid initial mining pose or throttle")
	var body:=target_body(scenery,selected.get("selected_object_index"))
	if body.is_empty():return false
	if not intact(body):return reject("Selected asteroid is no longer mineable")
	var distance:=f32(float(body.scale)*float(_rules.stand_off_scale))
	if not is_finite(distance) or distance<1 or distance>2147481647.0:return reject("Mining stand-off exceeds source coordinates")
	var next:=_state.duplicate(true)
	next.merge({"phase":"approach","object_index":int(body.index),"elapsed_ms":0,"tilt_units":0.0,
		"stand_off":int(distance),"player_pose":pose,"model_basis":model_basis,"throttle":throttle,
		"camera_update_enabled":true,"engine_visible":true,"spin_enabled":true,"near_asteroid":false,"events":[]},true)
	# Cancel resets the target/reference vector, but the original does not reset
	# its alignment flags. Keep them across attempts within this player lifetime.
	_state=next;_guidance_sample={}
	return true

func advance(scenery: RefCounted, delta_ms: Variant, paused:=false) -> bool:
	error=""
	if _state.is_empty() or _state.phase not in ["approach","docking"] or not Numbers.integer(delta_ms,0,int(_rules.max_frame_ms)):return reject("Mining approach requires an active, bounded frame")
	var body:=target_body(scenery,_state.object_index)
	if body.is_empty():return false
	if paused:return true
	if not intact(body):
		cancel();_state.events=[{"kind":"approach_cancelled","reason":"target_unavailable","object_index":int(body.index)}]
		return true
	if _state.elapsed_ms>2147483647-int(delta_ms):return reject("Mining approach time exceeds the source range")
	var next:=_state.duplicate(true);next.elapsed_ms+=int(delta_ms);next.events=[]
	var sample:={}
	var aligned:=_aligned;var alignment_open:=_alignment_open;var reference_up:=_reference_up
	if next.phase=="docking":
		if next.tilt_units>float(_rules.tilt_limit):
			next.tilt_units=f32(float(next.tilt_units)+float((-int(delta_ms))>>int(_rules.drill_wait_shift)))
		else:
			next.phase="drill_required";alignment_open=false
			next.events=[{"kind":"drill_required","object_index":next.object_index},{"kind":"audio_event","source_id":int(_rules.drill_start_event)}]
	else:
		var pose: Transform3D=next.player_pose
		var offset:=Vectors.added(body.position,-pose.origin)
		var length:=f32(sqrt(Vectors.dot(offset,offset)))
		if not is_finite(length) or length>2147483647.0:return reject("Mining target distance exceeds source coordinates")
		var distance:=int(length)
		if distance>=next.stand_off:
			sample.before=pose
			pose=guided_pose(pose,body.position,int(delta_ms),next.throttle)
			if not proper_pose(pose):return reject("Mining guidance produced an unsupported pose")
			sample.after=pose
			next.player_pose=pose
			var remaining:=Vectors.added(body.position,-pose.origin)
			if int(f32(sqrt(Vectors.dot(remaining,remaining))))<int(_rules.near_distance_limit):next.near_asteroid=true
		elif aligned:
			next.phase="docking";next.spin_enabled=false
		# The close test uses distance BEFORE movement. Reaching the threshold on
		# this frame cannot retroactively trigger the earlier close condition.
		if distance<next.stand_off+int(_rules.close_margin):
			next.throttle=1.0
			if not alignment_open:
				next.engine_visible=false;next.camera_update_enabled=false
				next.events.append({"kind":"audio_event","source_id":int(_rules.engine_stop_event)})
				reference_up=Vectors.normalized(next.model_basis.y);alignment_open=true
			var cosine:=Vectors.dot(Vectors.normalized(next.model_basis.z),reference_up)
			# The source acos returns NaN outside its domain, which takes its
			# completion branch. Do not turn a rounding overflow into more tilt.
			var angle:=f32(acos(cosine)) if cosine>=-1.0 and cosine<=1.0 else -1.0
			if angle>float(_rules.alignment_angle) and next.tilt_units>float(_rules.tilt_limit):
				next.tilt_units=f32(float(next.tilt_units)+f32(float(delta_ms)*float(_rules.tilt_rate)))
				var radians:=f32(f32(float(next.tilt_units)*float(_rules.angle_fraction))*float(_rules.angle_tau))
				# Source row-major pitch and matrix product: local model × Rx.
				next.model_basis=next.model_basis*Basis(Vector3.RIGHT,radians)
			else:alignment_open=false;aligned=true
	if not proper_pose(Transform3D(next.model_basis,Vector3.ZERO)):return reject("Mining visual alignment produced an unsupported orientation")
	_state=next;_aligned=aligned;_alignment_open=alignment_open;_reference_up=reference_up;_guidance_sample=sample
	return true

func guided_pose(pose: Transform3D, target: Vector3, milliseconds: int, throttle: float) -> Transform3D:
	return Guidance.advance(pose,target,milliseconds,_gain,_speed,float(_rules.turn_fraction),throttle)

func accept_model_basis(value: Variant) -> bool:
	# The later player tail can replace the visible model during death. The
	# next alignment pass reads that matrix, keeping its own target and clocks.
	error=""
	if _state.is_empty() or _state.phase=="idle" or not value is Basis or not proper_pose(Transform3D(value,Vector3.ZERO)):return reject("Active mining requires a proper retained model basis")
	_state.model_basis=value
	return true

func cancel() -> bool:
	error=""
	if _state.is_empty() or _state.phase=="idle":return reject("No active mining approach to cancel")
	_state=_state.duplicate(true)
	_state.merge({"phase":"idle","object_index":-1,"camera_update_enabled":true,"engine_visible":true,"spin_enabled":true,"events":[]},true)
	_reference_up=Vector3.ZERO;_guidance_sample={}
	return true

func target_body(scenery: RefCounted, index: Variant) -> Dictionary:
	if scenery==null or scenery.get_script()!=Scenery or scenery.presentation_identity()!=_field_identity:reject("Mining approach field was replaced");return {}
	var field: Dictionary=scenery.snapshot();var rows: Variant=field.get("bodies",{}).get("objects")
	for key in _identity:
		if field.get(key)!=_identity[key] or field.get("bodies",{}).get(key)!=_identity[key]:reject("Mining approach field belongs to another content identity");return {}
	if not rows is Array or not Numbers.integer(index,0,rows.size()-1) or rows.size()!=field.objects.size():reject("Mining approach asteroid is unavailable");return {}
	var row: Dictionary=rows[index]
	if row.get("index")!=index or not row.get("position") is Vector3 or not row.position.is_finite() or row.position!=field.objects[index].position or row.model_id!=field.objects[index].model_id or not row.get("active") is bool:reject("Mining asteroid geometry differs from its body");return {}
	row.lifecycle_state=0 if field.get("destruction",[]).is_empty() else int(field.destruction[index].lifecycle.actor_state)
	return row
static func intact(body: Dictionary) -> bool:return body.active and not body.get("mined",false) and body.vitals.hull>0 and body.lifecycle_state==0
static func proper_pose(pose: Transform3D) -> bool:return pose.is_finite() and pose.basis.determinant()>0 and pose.basis.is_equal_approx(pose.basis.orthonormalized())
static func f32(value: float) -> float:return PackedFloat32Array([value])[0]
func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	var result:=_identity.duplicate();result.merge(_state.duplicate(true))
	result.merge({"guidance_gain":_gain,"aligned":_aligned,"alignment_open":_alignment_open,"reference_up":_reference_up})
	result.presentation_pose=result.player_pose*Transform3D(result.model_basis,Vector3.ZERO)
	return result
func field_identity() -> RefCounted:return _field_identity
func last_guidance_sample() -> Dictionary:return _guidance_sample.duplicate(true)
func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._rules=_rules;copy._identity=_identity;copy._field_identity=_field_identity;copy._gain=_gain;copy._speed=_speed
	copy._state=_state.duplicate(true);copy._aligned=_aligned;copy._alignment_open=_alignment_open;copy._reference_up=_reference_up
	copy._guidance_sample=_guidance_sample.duplicate(true)
	return copy
func clear() -> void:
	error="";_rules={};_identity={};_field_identity=null;_gain=0;_speed=0;_state={};_aligned=false;_alignment_open=false;_reference_up=Vector3.ZERO
	_guidance_sample={}
func reject(message: String) -> bool:error=message;return false
