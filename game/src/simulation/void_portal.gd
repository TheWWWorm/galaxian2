extends RefCounted
## Shared selected-story portal. Flight owns movement and transitions.
const Definitions=preload("res://src/content/void_portal_definitions.gd")
const Portal=preload("res://src/simulation/alioth_portal.gd")
const Contact=preload("res://src/simulation/portal_contact.gd")
const Frames=preload("res://src/simulation/frame_clock.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Library=preload("res://src/content/library.gd")
const AEM=preload("res://src/content/aem.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
var error:=""
var _rules:={}
var _probe:={}
var _state:={}
var _contact:={}
var _frame:={}
var _entered:=false
var _max_ms:=0

func configure(bindings: RefCounted,entry: Dictionary,library: RefCounted) -> bool:
	error=""
	if bindings==null or not Definitions.selected(bindings.mido_travel,entry):return reject("The portal requires its selected source world")
	for key in ["base_content_id","binding_id"]:
		if not Library.valid_hash(bindings.get(key)) or entry.get(key)!=bindings.get(key):return reject("Void portal belongs to another content identity")
	if not Frames.valid_parameters(bindings.frame_clock):return reject("Void portal requires the native frame clock")
	var rules: Dictionary=bindings.mido_travel.void_portal
	var environment: Variant=entry.get("environment_object")
	if not environment is Dictionary or environment.get("resource_id")!=int(rules.portal.model_id) or not environment.get("position") is Vector3 or not environment.position.is_finite():return reject("Void portal lacks its original environment slot")
	if library==null or library.manifest.get("content_id")!=bindings.base_content_id:return reject("Void portal requires its original animation resource")
	var path: String=bindings.resolve(int(rules.portal.model_id),"mesh")
	if path.is_empty():return reject(bindings.error)
	var reader:=AEM.new();var model: Dictionary=reader.decode(library.read_resource(path,AEM.MAX_BYTES))
	var timing:=Effects.playback_range(model.get("surfaces",[]))
	if timing.is_empty():return reject("Unsupported original Void portal animation")
	timing.time_ms=timing.start_ms;timing.playing=true
	var state:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"campaign_cursor":int(entry.campaign_cursor),"system_id":int(entry.system_id),"station_id":int(entry.station_id),
		"mission_kind":int(entry.mission_kind),"slot":int(rules.portal.environment_slot),"model_id":int(rules.portal.model_id),
		"position":environment.position,"pose":Transform3D(Basis.IDENTITY,environment.position),"animation":timing,
		"elapsed_ms":int(rules.portal.initial_elapsed_ms),"animation_elapsed_ms":0,
		"extent":int(rules.portal.initial_extent),"visible":true,"scale":1.0}
	_rules=rules.duplicate(true);_probe=bindings.mido_travel.void_probe.duplicate(true) if entry.campaign_cursor==29 else {}
	_state=state;_contact={};_frame={};_entered=false
	_max_ms=Frames.simulation_limit(bindings,150)
	return true

func advance(milliseconds: Variant,camera: Transform3D,random: RefCounted) -> bool:
	error=""
	if _state.is_empty() or not milliseconds is int or milliseconds<0 or milliseconds>_max_ms or not Flight.rigid_pose(camera):return reject("Void portal requires its accepted world frame")
	if not random is Random or random.snapshot().is_empty():return reject("Void portal requires the retained world random stream")
	if _state.animation_elapsed_ms>2147483647-milliseconds:return reject("Void portal animation exceeds its source time range")
	var relocation:={};var next_random: RefCounted=null
	if _state.visible and _state.elapsed_ms+milliseconds>=int(_rules.portal.hide_at_ms):
		next_random=random.fork()
		var policy: Dictionary=_rules.portal.relocation
		var magnitude: int=int(policy.x_magnitude_offset)+next_random.next_int(int(policy.random_bounds[0]))
		var x: int=magnitude if next_random.next_int(int(policy.random_bounds[1]))==int(policy.x_positive_sign_draw) else -magnitude
		var y: int=int(policy.y_offset)+next_random.next_int(int(policy.random_bounds[2]))
		var z: int=int(policy.z_offset)+int(policy.z_draw_multiplier)*next_random.next_int(int(policy.random_bounds[3]))
		relocation={"position":Vector3(x,y,z),"elapsed_ms":int(policy.opening_elapsed_ms)}
	var next:=Portal.evaluate_clock(_state,_rules.portal,milliseconds,camera,relocation)
	if next.has("error"):return reject(next.error)
	if next_random!=null and not random.restore(next_random.snapshot()):return reject(random.error)
	_state=next
	_frame={} if relocation.is_empty() else {"relocated":true,"cancel_autopilot":bool(_rules.portal.relocation.cancel_player_autopilot_on_relocation)}
	return true

func observe_contact(observation: Dictionary) -> bool:
	error=""
	if _state.is_empty() or not Flight.rigid_pose(observation.get("player_pose")):return reject("Void portal contact requires the player's physical pose")
	for key in ["environment_contact_enabled","mining_active"]:
		if not observation.get(key) is bool:return reject("Void portal contact lacks environment/mining admission")
	var admission:=1
	if _state.campaign_cursor==29:
		admission=Definitions.contact_admission(_probe,_state,observation.get("story_selection"))
		if admission<0:return reject("Void29 contact requires its retained story selection")
	var offset:=Vectors.added(observation.player_pose.origin,-_state.position)
	if not offset.is_finite():return reject("Void portal contact exceeds source coordinates")
	var contact:=Contact.evaluate(_rules.contact,int(_rules.portal.close_start_ms),{
		"environment_contact_enabled":observation.environment_contact_enabled,"mining_active":observation.mining_active,
		"portal_visible":_state.visible,"portal_elapsed_ms":int(_state.elapsed_ms),"player_offset":offset})
	if not contact.is_empty():
		contact.portal_position=_state.position;contact.player_offset=offset
		if contact.entry_contact and admission==0:contact.entry_contact=false
		elif contact.entry_contact:_entered=true
	_contact=contact
	return true

func transition_ready(current_hull: Variant) -> bool:return _entered and current_hull is int and current_hull>0
func portal_snapshot() -> Dictionary:return _state.duplicate(true)
func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	return {"base_content_id":_state.base_content_id,"binding_id":_state.binding_id,"campaign_cursor":_state.campaign_cursor,
		"portal_entered":_entered,"frame":_frame.duplicate(true),"contact":_contact.duplicate(true)}
func clear_frame_cues() -> void:_frame={};_contact={}
func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._rules=_rules;copy._probe=_probe;copy._state=_state.duplicate(true);copy._frame=_frame.duplicate(true)
	copy._contact=_contact.duplicate(true);copy._entered=_entered;copy._max_ms=_max_ms
	return copy
func reject(message: String) -> bool:error=message;return false
