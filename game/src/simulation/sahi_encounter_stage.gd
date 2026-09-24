extends RefCounted
## Forkable Sahi choreography and portal observation. The flight applies cues;
## only Session/Career may consume living entry and construct the next world.
const Stage=preload("res://src/content/sahi_stage_definitions.gd")
const PortalRules=preload("res://src/content/alioth_flight_definitions.gd")
const Portal=preload("res://src/simulation/alioth_portal.gd")
const AEM=preload("res://src/content/aem.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const Library=preload("res://src/content/library.gd")
const Frames=preload("res://src/simulation/frame_clock.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
var error:=""
var _selection:={}
var _context:={}
var _rules:={}
var _portal_rules:={}
var _state:={}
var _portal:={}
var _frame:={}
var _contact:={}
var _radio:={}
var _max_ms:=0

func configure(bindings: RefCounted,entry: Dictionary,library: RefCounted) -> bool:
	error=""
	if bindings==null or not Stage.selected(bindings.mido_travel,entry):return reject("Sahi stage requires its selected unfinished story world")
	for key in ["base_content_id","binding_id"]:
		if not Library.valid_hash(bindings.get(key)) or entry.get(key)!=bindings.get(key):return reject("Sahi stage belongs to another content identity")
	if not _ordinary_entry(entry) or not Frames.valid_parameters(bindings.frame_clock):return reject("Sahi stage requires an ordinary distinct-station entry and native clock")
	if not PortalRules.parameters(bindings.mido_travel.get("alioth_flight")):return reject("Sahi stage lacks the verified shared portal clock")
	var rules: Dictionary=Stage.declarations(bindings.mido_travel,entry)
	var clock: Dictionary=bindings.mido_travel.alioth_flight.portal
	for key in ["model_id","environment_slot","open_duration_ms","close_start_ms","hide_at_ms"]:
		if rules.portal[key]!=clock[key]:return reject("Sahi stage disagrees with the shared original portal")
	if rules.portal.maximum_extent!=clock.extent_scale:return reject("Sahi portal extent differs from its source clock")
	var environment: Variant=entry.get("environment_object")
	if not environment is Dictionary or environment.get("resource_id")!=int(rules.portal.model_id) or not environment.get("position") is Vector3 or not environment.position.is_finite():return reject("Sahi stage lacks its original portal environment slot")
	if library==null or library.manifest.get("content_id")!=bindings.base_content_id:return reject("Sahi portal requires its original animation resource")
	var path: String=bindings.resolve(int(rules.portal.model_id),"mesh")
	var reader:=AEM.new();var model: Dictionary=reader.decode(library.read_resource(path,AEM.MAX_BYTES))
	var timing:=Effects.playback_range(model.get("surfaces",[]))
	if timing.is_empty():return reject("Unsupported original Sahi portal animation")
	timing.time_ms=timing.start_ms;timing.playing=true
	var identity:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"campaign_cursor":int(rules.campaign_cursor),"system_id":int(rules.system_id),
		"station_id":int(rules.station_id),"mission_kind":int(rules.mission_kind)}
	_selection={}
	for key in ["sahi_visit","sahi_encounter","sahi_stage"]:_selection[key]=bindings.mido_travel[key].duplicate(true)
	_context=entry.duplicate(true);_rules=rules;_portal_rules=clock.duplicate(true)
	_state=identity.duplicate()
	_state.merge({"phase":int(rules.sequence.initial_phase),"elapsed_ms":0,"revision":0,
		"input_blocked":false,"hud_visible":true,"target_overlay_visible":true,
		"damage_enabled":true,"scripted_coast":false,"player_update_suspended":false,"portal_entered":false})
	_portal=identity.duplicate()
	_portal.merge({"phase":int(rules.sequence.initial_phase),"slot":int(rules.portal.environment_slot),
		"model_id":int(rules.portal.model_id),"position":environment.position,
		"pose":Transform3D(Basis.IDENTITY,environment.position),"animation":timing,
		"elapsed_ms":int(clock.initial_elapsed_ms),"animation_elapsed_ms":0,
		"extent":int(clock.initial_extent),"visible":false,"scale":1.0})
	_max_ms=Frames.simulation_limit(bindings);_frame={};_contact={};_radio={}
	return true

func advance_stage(delta_ms: Variant,radio: Dictionary,player_pose: Transform3D,camera_pose: Transform3D) -> bool:
	error=""
	if _state.is_empty() or not _duration(delta_ms) or not Flight.rigid_pose(player_pose) or not Flight.rigid_pose(camera_pose):return reject("Sahi stage requires a finite native frame and physical poses")
	if not _valid_radio(radio):return false
	var phase:=Stage.phase_for_started_events(_selection,_context,_state.phase,radio.started)
	if phase<0:return reject("Sahi stage lost its accepted radio observations")
	var next:=_state.duplicate(true);var portal:=_portal.duplicate(true)
	var cues:=[]
	if phase==int(_rules.sequence.view_phase) and phase!=int(next.phase):
		var view: Dictionary=_rules.view
		var physical:=Transform3D(Vectors.local_xyz(vec(view.physical_rotation)),player_pose.origin)
		var eye:=Vectors.added(player_pose.origin,vec(view.camera_eye_offset))
		var position:=Vectors.added(player_pose.origin,Vectors.scaled(physical.basis.z,float(_rules.portal.forward_offset)))
		if not Flight.rigid_pose(physical) or not eye.is_finite() or not position.is_finite():return reject("Sahi view exceeds source coordinates")
		cues=[{"kind":"primary_trigger","enabled":bool(view.primary_trigger)},
			{"kind":"hud_visibility","visible":bool(view.hud_visible)},
			{"kind":"target_overlay_visibility","visible":bool(view.target_overlay_visible)},
			{"kind":"player_damage","enabled":bool(view.damage_enabled)},
			{"kind":"player_coast","enabled":bool(view.scripted_coast)},
			{"kind":"discard_flight_weapons"},{"kind":"clear_npc_weapon_targets"},
			{"kind":"player_physical_pose","pose":physical},
			{"kind":"camera_target","target":view.camera_target},
			{"kind":"camera_eye","position":eye,"previous_position":eye,"reset_interpolation":true},
			{"kind":"portal_position","slot":int(portal.slot),"position":position},
			{"kind":"rebase_starfield"},{"kind":"input_blocked","enabled":bool(view.input_blocked)}]
		portal.position=position;portal.pose.origin=position
		next.input_blocked=bool(view.input_blocked);next.hud_visible=bool(view.hud_visible)
		next.target_overlay_visible=bool(view.target_overlay_visible);next.damage_enabled=bool(view.damage_enabled)
		next.scripted_coast=bool(view.scripted_coast);next.player_update_suspended=not bool(view.player_updates_continue)
	elif phase==int(_rules.sequence.open_phase) and phase!=int(next.phase):
		portal.visible=true;portal.elapsed_ms=int(_rules.portal.open_elapsed_ms);portal.extent=int(_rules.portal.open_extent)
		cues=[{"kind":"portal_visible","slot":int(portal.slot),"visible":true},
			{"kind":"portal_reset","slot":int(portal.slot),"closing":false},
			{"kind":"portal_open","slot":int(portal.slot),"elapsed_ms":int(portal.elapsed_ms),"extent":int(portal.extent)},
			{"kind":"sound_start","event_id":int(_rules.spin.sound_event_id)}]
		next.elapsed_ms=0
	if phase==int(_rules.sequence.open_phase):
		if next.elapsed_ms>2147483647-int(delta_ms):return reject("Sahi stage clock exceeds its source range")
		var increment:=Vitals.single(float(delta_ms)/float(_rules.spin.rotation_divisor_ms))
		var rotation:=Vectors.scaled(vec(_rules.spin.rotation_axes),increment)
		cues.append({"kind":"sound_position","event_id":int(_rules.spin.sound_event_id),
			"position":camera_pose.origin,"velocity":vec(_rules.spin.sound_velocity)})
		cues.append({"kind":"camera_shake","shake_kind":int(_rules.spin.shake_kind),"amount":float(_rules.spin.shake_amount)})
		cues.append({"kind":"player_visual_rotation","delta":rotation})
		next.elapsed_ms+=int(delta_ms)
	next.phase=phase;next.revision+=1;portal.phase=phase
	_state=next;_portal=portal;_frame={"cues":cues};_contact={}
	_radio={"started":radio.started.duplicate(),"finished":radio.finished.duplicate()}
	return true

## Call in the existing world pass after applying stage/camera cues. Hidden
## portals retain their appearance clock while original model playback advances.
func advance_portal(delta_ms: Variant,camera_pose: Transform3D) -> bool:
	error=""
	if _state.is_empty() or not _duration(delta_ms) or not Flight.rigid_pose(camera_pose):return reject("Sahi portal requires its accepted world frame")
	if _portal.animation_elapsed_ms>2147483647-int(delta_ms):return reject("Sahi portal clock exceeds its source range")
	var next:=Portal.evaluate_clock(_portal,_portal_rules,int(delta_ms),camera_pose)
	if next.has("error"):return reject(next.error)
	_portal=next
	return true

## The environment owner supplies its real contact admission and mining state.
## Pull is a distance per contact update; the caller owns physical displacement.
func observe_contact(observation: Dictionary) -> bool:
	error=""
	if _state.is_empty() or not Flight.rigid_pose(observation.get("player_pose")):return reject("Sahi portal contact requires the actual physical player pose")
	for key in ["environment_contact_enabled","mining_active"]:
		if not observation.get(key) is bool:return reject("Sahi portal contact lacks its environment/mining admission")
	var offset:=Vectors.added(observation.player_pose.origin,-_portal.position)
	var contact:=Stage.portal_contact(_selection,_context,{"environment_contact_enabled":observation.environment_contact_enabled,
		"mining_active":observation.mining_active,"portal_visible":_portal.visible,
		"portal_elapsed_ms":int(_portal.elapsed_ms),"player_offset":offset})
	if not offset.is_finite():return reject("Sahi portal contact exceeds source coordinates")
	if not contact.is_empty():
		contact.portal_position=_portal.position;contact.player_offset=offset
		if contact.entry_contact:_state.portal_entered=true
	_contact=contact
	return true

func transition_ready(current_hull: Variant) -> bool:
	return not _state.is_empty() and Stage.transition_ready(_selection,_context,{"portal_entered":_state.portal_entered,"player_hull":current_hull})

func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	var result:=_state.duplicate(true);result.frame=_frame.duplicate(true);result.contact=_contact.duplicate(true)
	return result

func portal_snapshot() -> Dictionary:return _portal.duplicate(true)
func clear_frame_cues() -> void:_frame={};_contact={}

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	# Private declarations/context are immutable after configuration.
	copy._selection=_selection;copy._context=_context;copy._rules=_rules;copy._portal_rules=_portal_rules
	copy._state=_state.duplicate(true);copy._portal=_portal.duplicate(true);copy._frame=_frame.duplicate(true)
	copy._contact=_contact.duplicate(true);copy._radio=_radio.duplicate(true);copy._max_ms=_max_ms
	return copy

func _valid_radio(radio: Dictionary) -> bool:
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if radio.get(key)!=_state[key]:return reject("Sahi radio belongs to another encounter")
	for key in ["started","finished"]:
		var flags: Variant=radio.get(key)
		if not flags is Array or flags.size()!=_selection.sahi_encounter.radio_events.size():return reject("Sahi radio lacks its complete event observations")
		for i in flags.size():
			if not flags[i] is bool or (_radio.has(key) and _radio[key][i] and not flags[i]):return reject("Sahi radio regressed or changed type")
	for i in radio.started.size():
		if radio.finished[i] and not radio.started[i]:return reject("Sahi radio finished before it started")
	if radio.started[int(_rules.sequence.open_event_started)] and not radio.started[int(_rules.sequence.view_event_started)]:return reject("Sahi open radio lost its source dependency")
	return true

func _duration(value: Variant) -> bool:return value is int and value>=0 and value<=_max_ms
static func vec(values: Array) -> Vector3:return Vector3(values[0],values[1],values[2])
static func _ordinary_entry(entry: Dictionary) -> bool:
	var current: Variant=entry.get("current_station_id");var destination: Variant=entry.get("void_station_id")
	return current is int and current==48 and destination is int and destination==-1 \
		and entry.get("current_station_special") is bool and not entry.current_station_special
func reject(message: String) -> bool:error=message;return false
