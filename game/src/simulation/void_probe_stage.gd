extends RefCounted
## Cursor29's detached probe phase and source-relative clock. Flight applies
## the one-time cues; RadioSequence owns playback and display time.
const Probe=preload("res://src/content/void_probe_definitions.gd")
const Portal=preload("res://src/content/void_portal_definitions.gd")
const Library=preload("res://src/content/library.gd")
const Frames=preload("res://src/simulation/frame_clock.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const Radio=preload("res://src/simulation/radio_sequence.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")

var error:=""
var _rules:={}
var _state:={}
var _probe:={}
var _frame:={}
var _last_radio:={}
var _max_frame_ms:=0
var _awaiting_radio:=false

func configure(bindings: RefCounted,entry: Dictionary) -> bool:
	error=""
	if bindings==null or not bindings.get("mido_travel") is Dictionary \
		or not Probe.parameters(bindings.mido_travel.get("void_probe",{})) \
		or entry.get("campaign_cursor")!=int(bindings.mido_travel.void_probe.mission29.campaign_cursor) \
		or not Portal.selected(bindings.mido_travel,entry):
		return reject("Probe stage requires its selected unfinished Void29 world")
	for key in ["base_content_id","binding_id"]:
		if not Library.valid_hash(bindings.get(key)) or entry.get(key)!=bindings.get(key):
			return reject("Probe stage belongs to another content identity")
	if not Frames.valid_parameters(bindings.frame_clock):return reject("Probe stage requires the native frame clock")
	var max_frame:=Frames.simulation_limit(bindings)
	if max_frame<=0:return reject("Probe stage has no supported simulation frame")
	_rules=bindings.mido_travel.void_probe.world29.duplicate(true)
	_max_frame_ms=max_frame
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"campaign_cursor":int(bindings.mido_travel.void_probe.mission29.campaign_cursor),
		"phase":0,"stage_elapsed_ms":0,"revision":0,
		"input_blocked":false,"scripted_coast":false,"damage_enabled":true,
		"hud_visible":true,"target_overlay_visible":true,
		"environment_targeting_enabled":true,"scripted_camera":false}
	_probe={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"model_id":int(_rules.probe.model_id),"pose":Transform3D.IDENTITY,
		"visible":false,"model_time_ms":0}
	_frame={"cues":[]};_last_radio={"started":[false,false,false,false,false,false],
		"finished":[false,false,false,false,false,false]}
	_awaiting_radio=false
	return true

## Call before RadioSequence.step_probe, passing its observation this clock.
func advance_clock(delta_ms: Variant) -> bool:
	error=""
	if _state.is_empty() or _awaiting_radio or not delta_ms is int or delta_ms<0 or delta_ms>_max_frame_ms:
		return reject("Probe clock requires one bounded native frame before radio")
	if _state.stage_elapsed_ms>2147483647-delta_ms or (_probe.visible and _probe.model_time_ms>2147483647-delta_ms):
		return reject("Probe clock exceeds its source range")
	_state.stage_elapsed_ms+=delta_ms
	if _probe.visible:_probe.model_time_ms+=delta_ms
	_frame={"cues":[]};_awaiting_radio=true
	return true

## Call after that radio tick. The two source row latches are deliberately
## distinct; no display-time rewind or speculative phase progression occurs.
func observe_radio(radio: RefCounted,player_pose: Transform3D,camera_pose: Transform3D) -> bool:
	error=""
	if _state.is_empty() or not _awaiting_radio or not Flight.rigid_pose(player_pose) or not Flight.rigid_pose(camera_pose):
		return reject("Probe stage requires its accepted radio tick and physical poses")
	if not radio is Radio or not radio.error.is_empty():return reject("Probe stage requires the accepted radio owner")
	var observed: Dictionary=radio.snapshot()
	if not _valid_radio(radio,observed):return false
	var first: Dictionary=radio.event_state(int(_rules.stage_presentation.phase1_trigger.event_index))
	var second: Dictionary=radio.event_state(int(_rules.stage_presentation.phase2_trigger.event_index))
	var phase: int=int(_state.phase)
	var cues:=[]
	if phase==0 and first.condition_satisfied:
		if second.playback_finished:return reject("Probe stage cannot skip its source phase1")
		var pose: Transform3D=_probe_pose(player_pose)
		if not Flight.rigid_pose(pose):return reject("Probe pose exceeds source coordinates")
		var eye: Vector3=_camera_eye(player_pose)
		if not eye.is_finite():return reject("Probe camera eye exceeds source coordinates")
		var view: Dictionary=_rules.stage_presentation
		var spec: Dictionary=_rules.probe
		cues=[{"kind":"primary_trigger","enabled":bool(view.primary_trigger_enabled_in_phase1)},
			{"kind":"player_coast","enabled":true},{"kind":"input_blocked","enabled":bool(view.input_blocked_in_phase1)},
			{"kind":"player_damage","enabled":bool(view.damage_enabled_in_phase1)},
			{"kind":"hud_visibility","visible":bool(view.hud_visible_in_phase1)},
			{"kind":"target_overlay_visibility","visible":bool(view.target_overlay_visible_in_phase1)},
			{"kind":"environment_targeting","enabled":false},
			{"kind":"camera_scripted","enabled":bool(view.scripted_camera_in_phase1)},
			{"kind":"camera_target","target":String(spec.camera_initial_target_ref)},
			{"kind":"camera_initial_offsets","first":vec(spec.camera_initial_offsets_xyz[0]),"second":vec(spec.camera_initial_offsets_xyz[1])},
			{"kind":"camera_reset_offset","offset":vec(spec.camera_reset_offset_xyz)},
			{"kind":"camera_eye","position":eye},
			{"kind":"probe_spawn","model_id":int(spec.model_id),"pose":pose},
			{"kind":"camera_target","target":String(spec.camera_probe_target_ref)},
			{"kind":"sound_start","event_id":int(spec.sound_event_id),"position":eye}]
		_probe.pose=pose;_probe.visible=true;_probe.model_time_ms=0
		_state.phase=1;_state.input_blocked=bool(view.input_blocked_in_phase1)
		_state.scripted_coast=true;_state.damage_enabled=bool(view.damage_enabled_in_phase1)
		_state.hud_visible=bool(view.hud_visible_in_phase1)
		_state.target_overlay_visible=bool(view.target_overlay_visible_in_phase1)
		_state.environment_targeting_enabled=false
		_state.scripted_camera=bool(view.scripted_camera_in_phase1)
	elif phase==1 and second.playback_finished:
		# The radio owner has already cleared its active row. Only stage time resets.
		if int(observed.active_event)!=-1:return reject("Probe playback still owns an active radio row")
		var view: Dictionary=_rules.stage_presentation
		var spec: Dictionary=_rules.probe
		cues=[{"kind":"probe_despawn","model_id":int(spec.model_id)},
			{"kind":"camera_target","target":String(spec.camera_restored_target_ref)},
			{"kind":"camera_scripted","enabled":bool(view.scripted_camera_in_phase2)},
			{"kind":"hud_visibility","visible":bool(view.hud_visible_in_phase2)},
			{"kind":"target_overlay_visibility","visible":bool(view.target_overlay_visible_in_phase2)},
			{"kind":"environment_targeting","enabled":true},
			{"kind":"player_damage","enabled":bool(view.damage_enabled_in_phase2)},
			{"kind":"player_coast","enabled":false},
			{"kind":"input_blocked","enabled":bool(view.input_blocked_in_phase2)}]
		_probe.visible=false
		_state.phase=2;_state.stage_elapsed_ms=int(_rules.completion.phase2_resets_stage_elapsed_ms)
		_state.input_blocked=bool(view.input_blocked_in_phase2)
		_state.scripted_coast=false;_state.damage_enabled=bool(view.damage_enabled_in_phase2)
		_state.hud_visible=bool(view.hud_visible_in_phase2)
		_state.target_overlay_visible=bool(view.target_overlay_visible_in_phase2)
		_state.environment_targeting_enabled=true
		_state.scripted_camera=bool(view.scripted_camera_in_phase2)
	_state.revision+=1;_frame={"cues":cues}
	_last_radio={"started":observed.started.duplicate(),"finished":observed.finished.duplicate()}
	_awaiting_radio=false
	return true

func completion_ready(current_hull: Variant) -> bool:
	return not _state.is_empty() and _state.phase==2 and current_hull is int and current_hull>0 \
		and current_hull<=2147483647 and _state.stage_elapsed_ms>int(_rules.completion.survival_duration_ms)

func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	var result: Dictionary=_state.duplicate(true)
	result.frame=_frame.duplicate(true)
	return result

func probe_snapshot() -> Dictionary:return _probe.duplicate(true)
func clear_frame_cues() -> void:_frame={"cues":[]}

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._rules=_rules
	copy._state=_state.duplicate(true);copy._probe=_probe.duplicate(true)
	copy._frame=_frame.duplicate(true);copy._last_radio=_last_radio.duplicate(true)
	copy._max_frame_ms=_max_frame_ms;copy._awaiting_radio=_awaiting_radio
	return copy

func _valid_radio(radio: RefCounted,observed: Dictionary) -> bool:
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if observed.get(key)!=_state[key]:return reject("Probe radio belongs to another mission or content identity")
	for key in ["started","finished"]:
		var flags: Variant=observed.get(key)
		if not flags is Array or flags.size()!=_rules.radio_events.size():return reject("Probe radio lacks six source row latches")
		for i in flags.size():
			if not flags[i] is bool or (_last_radio[key][i] and not flags[i]):return reject("Probe radio row latch regressed or changed type")
	for i in observed.started.size():
		var state: Dictionary=radio.event_state(i)
		if state.get("condition_satisfied")!=observed.started[i] or state.get("playback_finished")!=observed.finished[i]:
			return reject("Probe radio event state disagrees with its snapshot")
		if observed.finished[i] and not observed.started[i]:return reject("Probe radio playback finished before its condition")
	if observed.started[1] and not observed.started[0] or observed.finished[1] and not observed.finished[0]:
		return reject("Probe radio lost its ordered source rows")
	if not observed.get("active_event") is int or observed.active_event<-1 or observed.active_event>=_rules.radio_events.size():
		return reject("Probe radio has an invalid active row")
	return true

func _probe_pose(player_pose: Transform3D) -> Transform3D:
	var forward: Vector3=player_pose.basis.z
	var up:=vec(_rules.probe.orientation_up_xyz)
	# The source's normalize-zero fallback leaves a degenerate pose when its
	# global up and player forward are exactly parallel. Preserve the forward
	# axis and use the already-accepted physical up only at that singularity.
	if Vectors.dot(Vectors.cross(up,forward),Vectors.cross(up,forward))<=0.000000000001:
		up=player_pose.basis.y
	return Transform3D(Basis.looking_at(forward,up,true),player_pose.origin)

func _camera_eye(player_pose: Transform3D) -> Vector3:
	var factors: Array=_rules.probe.camera_eye_forward_right_up_scales
	var eye: Vector3=Vectors.added(player_pose.origin,Vectors.scaled(player_pose.basis.z,float(factors[0])))
	eye=Vectors.added(eye,Vectors.scaled(player_pose.basis.x,float(factors[1])))
	return Vectors.added(eye,Vectors.scaled(player_pose.basis.y,float(factors[2])))

static func vec(values: Array) -> Vector3:return Vector3(values[0],values[1],values[2])
func reject(message: String) -> bool:error=message;return false
