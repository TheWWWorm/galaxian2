extends RefCounted
## Prospective rescue-scene cues. The world owns actor statistics, body motion,
## camera sampling, radio and fade advancement; station entry remains a boundary.
const Definitions=preload("res://src/content/arrival_staging_definitions.gd")
const Dialogue=preload("res://src/content/dialogue_definitions.gd")
const Library=preload("res://src/content/library.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
const Poses=preload("res://src/simulation/opening_staging.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
enum Stage { RESCUE, FADE }
var error:=""
var _rules:={}
var _state:={}
var _frame:={}
var _radio:={}
var _identity: RefCounted

func configure(bindings: RefCounted, library: RefCounted) -> bool:
	error="";_rules={};_state={};_frame={};_radio={};_identity=null
	if bindings==null or library==null or library.manifest.get("content_id")!=bindings.base_content_id:return reject("Rescue staging requires matching content")
	if not Library.valid_hash(bindings.base_content_id) or not Library.valid_hash(bindings.binding_id):return reject("Rescue content identity is unavailable")
	var rules: Dictionary=bindings.arrival_staging
	if not Definitions.parameters(rules):return reject("Rescue staging declarations are unavailable")
	if not Dialogue.valid_parameters(bindings.arrival_dialogue,1) or bindings.opening_staging.get("player_motion",{}).is_empty() or bindings.opening_actors.get("npc_initialization",{}).is_empty():return reject("Rescue staging requires its source radio and shared actors")
	_rules=rules.duplicate(true)
	# The rescue sets both source flags: scripted flight remains selected while
	# the freeze byte prevents the ordinary player update from running.
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":1,
		"phase":Stage.RESCUE,"elapsed_ms":0,"generation":0,"boundary":"","hud_visible":bool(rules.hud_visible),
		"eye":Poses.vec(rules.camera_position),"camera_fixed_eye":bool(rules.camera_fixed_eye),"camera_target":rules.camera_target,
		"player_model_rotation":Poses.vec(rules.player_model_rotation),"scripted_player":bool(rules.scripted_player),
		"player_update_enabled":bool(rules.player_update_enabled),"player_cruise":float(rules.player_cruise)}
	_frame={"initial":true,"player_position":Poses.vec(rules.player_initial_position),
		"actor":{"kind":int(rules.actor_kind),"hull_catalogue_id":int(rules.actor_hull_id),"factory_subtype":int(rules.actor_factory_subtype),
			"position":Poses.vec(rules.actor_initial_position),"route_points":rules.actor_route_points.duplicate(true),
			"model_draw_enabled":bool(rules.actor_model_draw_enabled),"engine_draw_enabled":bool(rules.actor_engine_draw_enabled),
			"engine_resource_id":int(rules.actor_engine_resource_id),"cruise":float(rules.actor_initial_cruise)},
		"audio":[{"action":"stop_player_engine"},{"action":"stop_actor_engine","actor_id":0}],
		"fade_request":fade_request(int(rules.initial_fade_direction))}
	_identity=RefCounted.new()
	return true

func advance(delta_ms: Variant, radio: Dictionary, actor_statistics_position: Vector3, actor_body: Transform3D, fade_active: bool) -> bool:
	error=""
	if _state.is_empty() or not Numbers.integer(delta_ms,0,150):return reject("Rescue staging requires ordinary frame milliseconds")
	if not valid_radio(radio):return reject("Rescue radio is missing, foreign or regressed")
	if not actor_statistics_position.is_finite() or not actor_body.is_finite() or not actor_body.basis.is_equal_approx(actor_body.basis.orthonormalized()) or actor_body.basis.determinant()<=0:return reject("Rescue staging requires finite actor statistics and an orthonormal body")
	if not _state.boundary.is_empty():return reject("The rescue requires its following station scene")
	var next:=_state.duplicate(true)
	var step:=int(delta_ms)
	# Quantized source angle uses ordinary milliseconds, not accumulated time.
	var angle:=Vitals.single(Vitals.single(float((step*int(_rules.rotation_time_multiplier))&int(_rules.rotation_time_mask))*float(_rules.rotation_fraction))*float(_rules.rotation_radians))
	var rotation:=Vector3(0,angle,angle)
	next.player_model_rotation=Vectors.added(next.player_model_rotation,rotation)
	# The scalar comes from the actor's statistics; the direction comes from its
	# body. These can differ during the ordered world/controller update.
	var factor:=minf(Vitals.single(actor_statistics_position.z/float(_rules.actor_distance_divisor)),float(_rules.actor_distance_upper))
	var distance:=Vitals.single(Vitals.single(float(step)*float(_rules.actor_speed_per_ms))*factor)
	var body:=actor_body
	body.origin=Vectors.added(body.origin,Vectors.scaled(Vectors.normalized(body.basis.z),distance))
	var frame:={"initial":false,"model_rotation_delta":rotation,"actor_script_mode":int(_rules.actor_script_mode),
		"actor_forward_distance":distance,"actor_pose_override":body,"camera_pan":Vector3.ZERO,"audio":[],"fade_request":{}}
	if next.phase==Stage.RESCUE and radio.finished[int(_rules.exit_after_event_finished)]:
		next.phase=Stage.FADE
		frame.fade_request=fade_request(int(_rules.exit_fade_direction))
	if next.phase==Stage.FADE and frame.fade_request.is_empty() and not fade_active:
		next.boundary="station_transition_required"
	else:
		frame.camera_pan=Vector3(Vitals.single(float(step)*float(_rules.camera_x_per_ms)),0,0)
		next.eye=Vectors.added(next.eye,frame.camera_pan)
	if not body.is_finite() or not next.player_model_rotation.is_finite() or not next.eye.is_finite():return reject("Rescue movement exceeds source precision")
	next.elapsed_ms+=step;next.generation+=1
	_state=next;_frame=frame
	_radio={"started":radio.started.duplicate(),"finished":radio.finished.duplicate()}
	return true

func valid_radio(radio: Dictionary) -> bool:
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if radio.get(key)!=_state.get(key):return false
	for key in ["started","finished"]:
		var flags: Variant=radio.get(key)
		if not flags is Array or flags.size()!=3:return false
		for i in 3:
			if not flags[i] is bool or (_radio.has(key) and _radio[key][i] and not flags[i]):return false
	for i in 3:
		if radio.finished[i] and not radio.started[i]:return false
		if i>0 and radio.started[i] and not radio.started[i-1]:return false
	return true

func fade_request(direction: int) -> Dictionary:
	return {"duration_ms":int(_rules.fade_duration_ms),"source_direction":direction,"source_color_argument":int(_rules.fade_color_argument)}

func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	var state:=_state.duplicate(true);state.frame=_frame.duplicate(true)
	state.player_model_basis=Vectors.local_xyz(state.player_model_rotation).transposed()
	return state

func presentation_identity() -> RefCounted:return _identity
func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._rules=_rules;copy._state=_state.duplicate(true);copy._radio=_radio.duplicate(true);copy._frame=_frame.duplicate(true);copy._identity=_identity
	return copy
func reject(message: String) -> bool:error=message;return false
