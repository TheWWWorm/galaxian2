extends RefCounted
## Native choreography for the opening escape. The world remains authoritative
## for player movement, camera views, rendering, audio and the final fade. This
## owner emits prospective cues; adopting a frame is the caller's responsibility.
const Definitions=preload("res://src/content/opening_escape_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Library=preload("res://src/content/library.gd")
const AEM=preload("res://src/content/aem.gd")
const Ranges=preload("res://src/content/scenery_effect_resources.gd")
const Playback=preload("res://src/simulation/model_playback.gd")
const Poses=preload("res://src/simulation/opening_staging.gd")
const EFFECT_PATH="resources/data/assets/main/3d/meshes/fx/hyper_drive.aem"
enum Stage { WAITING=4, DRIVE, DISTURBANCE, DEPARTURE, COAST, RELOCATION, ARRIVAL_BUILDUP, ARRIVAL, DRIFT, SECOND_SHOT, LAST_SHOT, ORBIT, FADE }
var error:=""
var _rules: Dictionary={}
var _state: Dictionary={}
var _radio: Dictionary={}
var _frame: Dictionary={}
var _identity: RefCounted

func configure(bindings: RefCounted, library: RefCounted) -> bool:
	error="";_rules={};_state={};_radio={};_frame={};_identity=null
	if bindings==null or library==null or library.manifest.get("content_id")!=bindings.base_content_id:return reject("Opening escape requires matching content")
	var rules: Variant=bindings.opening_staging.get("escape",{})
	if not Definitions.parameters(rules):return reject("Opening escape declarations are unavailable")
	if not Library.valid_hash(bindings.base_content_id) or not Library.valid_hash(bindings.binding_id):return reject("Opening escape identity is unavailable")
	if bindings.opening_staging.get("player_flight",{}).get("postcombat_after_event_finished")!=rules.entry_after_event_finished or bindings.opening_dialogue.get("events",[]).size()!=23:return reject("Opening escape does not join its source encounter")
	var path: String=bindings.resolve(int(rules.effect_resource_id),"mesh")
	if path!=EFFECT_PATH:return reject("Unsupported opening hyperdrive model mapping")
	var decoder:=AEM.new();var model:=decoder.decode(library.read_resource(path,AEM.MAX_BYTES))
	if model.is_empty():return reject(decoder.error)
	var timing:=Ranges.playback_range(model.surfaces)
	if timing.is_empty() or timing.end_ms<=timing.start_ms:return reject("Opening hyperdrive animation range is unavailable")
	_rules=rules.duplicate(true)
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"phase":Stage.WAITING,
		"phase_elapsed_ms":0,"elapsed_ms":0,"cruise_speed":float(rules.initial_cruise_speed),"input_blocked":false,
		"hud_visible":true,"ship_visible":true,"eye":Vector3.ZERO,"shake_strength":0.0,"shake_radius":0,
		"effect":{"model_id":int(rules.effect_resource_id),"resource":path,"start_ms":int(timing.start_ms),"end_ms":int(timing.end_ms),
			"time_ms":int(timing.start_ms),"sample_time_ms":int(timing.start_ms),"sample_generation":0,"playing":false,"position":Vector3.ZERO},
		"boundary":""}
	_identity=RefCounted.new()
	return true

func advance(delta_ms: Variant, radio: Dictionary, player_pose: Transform3D, preceding_camera: Transform3D, fade_active := true) -> bool:
	error=""
	if _state.is_empty() or not Numbers.integer(delta_ms,0,150):return reject("Opening escape requires an ordinary source frame")
	if not player_pose.is_finite() or not player_pose.basis.is_equal_approx(player_pose.basis.orthonormalized()) or player_pose.basis.determinant()<=0.0 or not preceding_camera.is_finite():return reject("Opening escape requires finite player and camera poses")
	if not valid_radio(radio):return reject("Opening escape radio is missing, foreign or regressed")
	if not _state.boundary.is_empty():return reject("The following arrival scene is not yet connected")
	var next:=_state.duplicate(true)
	var frame:={"camera_operations":[],"audio":[],"player_pose_override":null,"model_rotation_delta":Vector3.ZERO,
		"effect_sampled":false,"effect_orientation":{},"world_change":{},"fade_request":{},"entry":false,"ship_restore":false}
	var finished: Array=radio.finished;var started: Array=radio.started
	var phase:=int(next.phase)
	if phase!=Stage.WAITING:next.elapsed_ms+=int(delta_ms)
	if phase in [Stage.DISTURBANCE,Stage.DEPARTURE,Stage.COAST,Stage.ARRIVAL_BUILDUP,Stage.ARRIVAL,Stage.SECOND_SHOT,Stage.LAST_SHOT]:next.phase_elapsed_ms+=int(delta_ms)
	match phase:
		Stage.WAITING:
			if finished[int(_rules.entry_after_event_finished)]:
				enter(next,Stage.DRIVE)
				next.input_blocked=true;next.hud_visible=false
				# All source Euler orders agree for this single-axis rotation.
				var yaw:=float(_rules.entry_yaw)
				var s:=single(sin(yaw));var c:=single(cos(yaw))
				# The source forward helper reads the Euler matrix's third column;
				# positive yaw sends the logical ship toward positive X.
				frame.player_pose_override=Transform3D(Basis(Vector3(c,0,-s),Vector3.UP,Vector3(s,0,c)),player_pose.origin)
				next.eye=player_pose.origin+Poses.vec(_rules.entry_eye_offset)
				refresh(next,frame)
				frame.entry=true
				frame.audio.append({"action":"replace_music","source_id":int(_rules.entry_music_id)})
		Stage.DRIVE:
			if finished[int(_rules.slowdown_after_event_finished)]:
				if next.cruise_speed==_rules.initial_cruise_speed:
					for i in 2:frame.audio.append({"action":"start_spatial","source_id":int(_rules.drive_sound_ids[i]),"position":player_pose.origin})
					frame.audio.append({"action":"stop_player_engine"})
					frame.audio.append({"action":"start","source_id":int(_rules.drive_sound_ids[2])})
				frame.audio.append({"action":"position","source_id":int(_rules.drive_sound_ids[2]),"position":player_pose.origin})
				# The source applies decay once per update, including a zero-time cue.
				next.cruise_speed=single(next.cruise_speed*_rules.cruise_decay_per_update)
				if finished[int(_rules.pan_after_event_finished)]:pan(next,frame,drive_pan(int(delta_ms)))
				if started[int(_rules.disturbance_after_event_started)]:enter(next,Stage.DISTURBANCE)
		Stage.DISTURBANCE:
			frame.audio.append({"action":"position","source_id":int(_rules.drive_sound_ids[2]),"position":player_pose.origin})
			# This immediate refresh uses the preceding shake, before its ramp.
			pan(next,frame,drive_pan(int(delta_ms)))
			shake(next,rise(next.phase_elapsed_ms,_rules.shake_rise_ms))
			if finished[int(_rules.effect_after_event_finished)]:
				enter(next,Stage.DEPARTURE)
				next.effect.position=player_pose.origin
				Playback.restart([next.effect])
				frame.audio.append({"action":"start","source_id":int(_rules.exit_sound_id)})
				frame.audio.append({"action":"stop","source_id":int(_rules.drive_sound_ids[2])})
		Stage.DEPARTURE:
			pan(next,frame,drive_pan(int(delta_ms)))
			frame.effect_orientation={"view":"immediate","up":Vector3.UP}
			advance_effect(next,frame,int(delta_ms))
			if next.phase_elapsed_ms>=_rules.hide_ship_at_ms:
				next.ship_visible=false;shake(next,0.0,0)
				frame.audio.append({"action":"stop","source_id":int(_rules.drive_sound_ids[1])})
			if not next.effect.playing:
				enter(next,Stage.COAST)
				frame.audio.append({"action":"replace_music","source_id":int(_rules.jump_music_id)})
		Stage.COAST:
			shake(next,falloff(next.phase_elapsed_ms,_rules.after_exit_falloff_ms))
			if next.phase_elapsed_ms>=_rules.after_exit_wait_ms:
				enter(next,Stage.RELOCATION);shake(next,0.0,0)
				# Stop + reset activates the model but does not sample its first key.
				Playback.restart([next.effect])
		Stage.RELOCATION:
			enter(next,Stage.ARRIVAL_BUILDUP)
			frame.player_pose_override=Poses.pose(_rules.jump_position,_rules.jump_forward,_rules.jump_up)
			frame.model_rotation_delta=Poses.vec(_rules.jump_model_rotation)
			next.eye=Poses.vec(_rules.jump_eye);next.effect.position=Poses.vec(_rules.jump_position)
			frame.world_change={"sky_mesh_id":int(_rules.jump_sky_mesh_id),"sky_texture_id":int(_rules.jump_sky_texture_id),
				"planet_texture_id":int(_rules.jump_planet_texture_id),"planet_scale_multiplier":float(_rules.jump_planet_scale_multiplier)}
		Stage.ARRIVAL_BUILDUP:
			shake(next,rise(next.phase_elapsed_ms,_rules.arrival_shake_rise_ms))
			if next.phase_elapsed_ms>=_rules.arrival_effect_after_ms:
				enter(next,Stage.ARRIVAL)
				next.effect.position=player_pose.origin
				frame.audio.append({"action":"start","source_id":int(_rules.arrival_sound_id)})
		Stage.ARRIVAL:
			shake(next,falloff(next.phase_elapsed_ms,_rules.arrival_shake_falloff_ms))
			# The source reads the renderer matrix's backward axis, not its eye.
			# Retain the preceding view here; departure uses its immediate view.
			frame.effect_orientation={"view":"preceding","backward":preceding_camera.basis.z,"up":Vector3.UP}
			advance_effect(next,frame,int(delta_ms))
			if next.phase_elapsed_ms>=_rules.arrival_ship_restore_after_ms:
				# Source retains this phase counter until the event-17 camera cut.
				next.phase=Stage.DRIFT;next.ship_visible=true
				next.cruise_speed=float(_rules.initial_cruise_speed)
				frame.ship_restore=true
				frame.audio.append({"action":"set_player_engine","source_id":int(_rules.arrival_engine_sound_id)})
		Stage.DRIFT:
			advance_effect(next,frame,int(delta_ms))
			frame.model_rotation_delta=Vector3.ONE*single(float(delta_ms)/_rules.drift_roll_divisor)
			if finished[int(_rules.drift_cut_after_event_finished)]:
				enter(next,Stage.SECOND_SHOT)
				next.eye=player_pose.origin+Poses.vec(_rules.drift_eye_offset)
		Stage.SECOND_SHOT:
			frame.model_rotation_delta=Vector3.ONE*single(float(delta_ms)/_rules.second_roll_divisor)
			if next.phase_elapsed_ms>=_rules.second_cut_after_ms:
				enter(next,Stage.LAST_SHOT)
				next.eye=player_pose.origin+Poses.vec(_rules.second_eye_offset)
		Stage.LAST_SHOT:
			frame.model_rotation_delta=Vector3.ONE*single(float(delta_ms)/_rules.last_roll_divisor)
			pan(next,frame,Vector3(0,0,single(float(delta_ms)*_rules.last_pan_z_per_ms)))
			if next.phase_elapsed_ms>=_rules.last_cut_after_ms:
				enter(next,Stage.ORBIT)
				next.eye=player_pose.origin+Poses.vec(_rules.last_eye_offset)
		Stage.ORBIT:
			if finished[int(_rules.fade_after_event_finished)]:
				next.phase=Stage.FADE
				frame.fade_request={"duration_ms":int(_rules.fade_duration_ms),"source_direction":int(_rules.fade_source_direction),"source_color_argument":int(_rules.fade_source_color_argument)}
		Stage.FADE:
			if not fade_active:next.boundary="arrival_transition_required"
	if not next.eye.is_finite() or not is_finite(next.cruise_speed):return reject("Opening escape movement exceeds source precision")
	_state=next;_frame=frame;_radio={"started":started.duplicate(),"finished":finished.duplicate()}
	return true

func valid_radio(radio: Dictionary) -> bool:
	for key in ["base_content_id","binding_id"]:
		if radio.get(key)!=_state[key]:return false
	for key in ["started","finished"]:
		var flags: Variant=radio.get(key)
		if not flags is Array or flags.size()!=23:return false
		for i in flags.size():
			if not flags[i] is bool or (_radio.has(key) and _radio[key][i] and not flags[i]):return false
	for i in 23:
		if radio.finished[i] and not radio.started[i]:return false
	return true

func drive_pan(delta_ms: int) -> Vector3:
	return Vector3(single(float(delta_ms)*_rules.pan_x_per_ms_double),0,single(single(float(delta_ms))*_rules.pan_z_per_ms))

func shake(state: Dictionary, strength: float, radius := -1) -> void:
	state.shake_strength=strength;state.shake_radius=int(_rules.shake_radius) if radius<0 else radius

static func rise(milliseconds: int, duration: float) -> float:return minf(single(single(float(milliseconds))/duration),1.0)
static func falloff(milliseconds: int, duration: float) -> float:return maxf(0.0,single(single(single(float(milliseconds))/-duration)+1.0))
static func enter(state: Dictionary, phase: int) -> void:state.phase=phase;state.phase_elapsed_ms=0
static func pan(state: Dictionary, frame: Dictionary, offset: Vector3) -> void:state.eye+=offset;refresh(state,frame)
static func refresh(state: Dictionary, frame: Dictionary) -> void:
	frame.camera_operations.append({"eye":state.eye,"shake_strength":state.shake_strength,"shake_radius":state.shake_radius,"immediate":true})
static func advance_effect(state: Dictionary, frame: Dictionary, delta_ms: int) -> void:
	if not state.effect.playing:return
	Playback.advance([state.effect],delta_ms)
	state.effect.sample_time_ms=state.effect.time_ms;state.effect.sample_generation+=1;frame.effect_sampled=true
static func single(value: float) -> float:return PackedFloat32Array([value])[0]
func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	var result:=_state.duplicate(true);result.frame=_frame.duplicate(true);return result
func presentation_identity() -> RefCounted:return _identity
func fork_for_frame() -> RefCounted:
	var next: RefCounted=get_script().new();next._rules=_rules;next._state=_state.duplicate(true);next._frame=_frame.duplicate(true);next._radio=_radio.duplicate(true);next._identity=_identity;return next
func reject(message: String) -> bool:error=message;return false
