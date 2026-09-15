extends RefCounted
## Native convoy choreography. Cues are prospective: the flight owner must apply
## them to its real actors, camera and player before adopting this frame. Arrival
## is a request to the session; this owner never changes career state or rewards.
const Definitions=preload("res://src/content/convoy_capture_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Library=preload("res://src/content/library.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
enum Stage { INTERCEPTION, PULSE, DISABLED, CAPTURE_VIEW, TRANSFER_WAIT, ARRIVAL_REQUIRED }
var error:=""
var _state:={}
var _rules:={}
var _radio:={}
var _frame:={}
var _max_ms:=0

func configure(bindings: RefCounted) -> bool:
	error="";_state={};_rules={};_radio={};_frame={};_max_ms=0
	if not Definitions.available(bindings):return reject("Convoy capture declarations are unavailable")
	if not Library.valid_hash(bindings.base_content_id) or not Library.valid_hash(bindings.binding_id):return reject("Convoy capture requires a verified content identity")
	if not Numbers.integer(bindings.frame_clock.get("max_frame_milliseconds"),1,150):return reject("Convoy capture requires the ordinary frame clock")
	_rules=bindings.mido_travel.convoy_capture.duplicate(true)
	_max_ms=int(bindings.frame_clock.max_frame_milliseconds)
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(_rules.campaign_cursor),
		"phase":Stage.INTERCEPTION,"elapsed_ms":0,"transfer_elapsed_ms":0,"input_blocked":false,"ship_visible":true,"arrival":{}}
	return true

func advance(delta_ms: Variant, radio: Dictionary, player_pose: Transform3D, capture_pose: Transform3D) -> bool:
	error=""
	if _state.is_empty() or not Numbers.integer(delta_ms,0,_max_ms):return reject("Convoy capture requires an ordinary frame")
	if not player_pose.is_finite() or not capture_pose.is_finite():return reject("Convoy capture requires finite current poses")
	if not _valid_radio(radio):return reject("Convoy radio is missing, foreign or regressed")
	if _state.phase==Stage.ARRIVAL_REQUIRED:return reject("Convoy capture is waiting for its station transition")
	if int(_state.elapsed_ms)>2147483647-int(delta_ms):return reject("Convoy clock exceeds its source range")
	var next:=_state.duplicate(true)
	next.elapsed_ms+=int(delta_ms)
	var frame:={"retire_actor_ids":[],"retire_actor_kind":-1,"audio":[],"camera_operations":[],
		"disable_player":false,"model_rotation_delta":Vector3.ZERO,"blackout":{},"reset_starfield":false,
		"reset_follow_offsets":false,"emp_target":{},"stop_nozzle_emitters":false,"capture_actor_id":-1,"arrival":{}}
	match int(next.phase):
		Stage.INTERCEPTION:
			if radio.started[int(_rules.first_pulse_event_started)]:
				next.phase=Stage.PULSE
				frame.retire_actor_ids=[int(_rules.first_pulse_actor_id)]
				frame.emp_target={"actor_id":int(_rules.first_pulse_actor_id),"position":player_pose.origin}
				frame.audio.append({"action":"start","source_id":int(_rules.emp_sound_id)})
		Stage.PULSE:
			if radio.finished[int(_rules.disable_event_finished)]:
				next.phase=Stage.DISABLED;next.input_blocked=true
				frame.disable_player=true;frame.reset_follow_offsets=true
				frame.retire_actor_kind=int(_rules.disabled_actor_kind)
				frame.blackout={"kind":int(_rules.blackout.kind),"duration_ms":int(_rules.blackout.duration_ms),
					"rgb":_rules.blackout.rgb.map(func(v):return int(v)),"alpha":int(_rules.blackout.alpha)}
				frame.audio.append({"action":"start_spatial","source_id":int(_rules.emp_sound_id),"position":player_pose.origin})
				frame.camera_operations=[{"action":"follow_player","position":player_pose.origin},
					{"action":"offset","delta":vec(_rules.disabled_eye_offset)}]
				frame.reset_starfield=true
		Stage.DISABLED:
			frame.disable_player=true;frame.reset_follow_offsets=true
			frame.model_rotation_delta=Vector3(0,Vitals.single(float(delta_ms)/float(_rules.drift_yaw_divisor)),0)
			frame.camera_operations=[{"action":"offset","delta":Vector3(0,0,Vitals.single(float(delta_ms)*float(_rules.drift_camera_z_per_ms)))}]
			if radio.finished[int(_rules.capture_view_event_finished)]:
				next.phase=Stage.CAPTURE_VIEW;next.ship_visible=false
				frame.stop_nozzle_emitters=true;frame.capture_actor_id=int(_rules.capture_actor_id)
				frame.camera_operations.append({"action":"follow_actor","actor_id":int(_rules.capture_actor_id),"position":capture_pose.origin})
				frame.camera_operations.append({"action":"offset","delta":vec(_rules.capture_eye_offset)})
				frame.reset_starfield=true
		Stage.CAPTURE_VIEW:
			if radio.finished[int(_rules.transfer_event_finished)]:
				next.phase=Stage.TRANSFER_WAIT;next.transfer_elapsed_ms=0
				frame.reset_starfield=true
		Stage.TRANSFER_WAIT:
			next.transfer_elapsed_ms+=int(delta_ms)
			if next.transfer_elapsed_ms>=int(_rules.transfer_wait_ms):
				next.phase=Stage.ARRIVAL_REQUIRED
				for key in _rules.arrival:next.arrival[key]=int(_rules.arrival[key])
				frame.arrival=next.arrival.duplicate(true)
	_state=next;_frame=frame
	_radio={"started":radio.started.duplicate(),"finished":radio.finished.duplicate()}
	return true

func _valid_radio(radio: Dictionary) -> bool:
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if radio.get(key)!=_state[key]:return false
	var count: int=_rules.radio_events.size()
	for key in ["started","finished"]:
		var flags: Variant=radio.get(key)
		if not flags is Array or flags.size()!=count:return false
		for i in count:
			if not flags[i] is bool or (_radio.has(key) and _radio[key][i] and not flags[i]):return false
	for i in count:
		if radio.finished[i] and not radio.started[i]:return false
	return true

func clear_frame_cues() -> void:
	_frame={}

func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	var result:=_state.duplicate(true)
	result.frame=_frame.duplicate(true)
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._state=_state.duplicate(true);copy._rules=_rules.duplicate(true)
	copy._radio=_radio.duplicate(true);copy._frame=_frame.duplicate(true);copy._max_ms=_max_ms
	return copy

static func vec(values: Array) -> Vector3:return Vector3(values[0],values[1],values[2])

func reject(message: String) -> bool:
	error=message
	return false
