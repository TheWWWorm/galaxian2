extends RefCounted
const Frames=preload("res://src/simulation/frame_clock.gd")
var _max_ms:=0
## Native portal clock and sequence operations. Animation keeps advancing while
## hidden; only visible portals advance their opening/closing and facing state.
const AEM=preload("res://src/content/aem.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const Playback=preload("res://src/simulation/model_playback.gd")
const Definitions=preload("res://src/content/alioth_flight_definitions.gd")
const Attack=preload("res://src/simulation/alioth_attack.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
var error:=""
var _state:={}
var _rules:={}
var _revision:=0

func configure(bindings: RefCounted,entry: Dictionary,library: RefCounted) -> bool:
	error=""
	if not Definitions.available(bindings) or entry.get("campaign_cursor")!=16:return reject("Alioth portal requires its supported flight")
	for key in ["base_content_id","binding_id"]:
		if entry.get(key)!=bindings.get(key):return reject("Portal belongs to another flight")
	var rules: Dictionary=bindings.mido_travel.alioth_flight.portal
	var position:=Attack.vec(bindings.mido_travel.alioth_attack.portal.position)
	if entry.get("environment_object")!={"resource_id":int(rules.model_id),"position":position}:return reject("Portal differs from the authored environment slot")
	var path: String=bindings.resolve(int(rules.model_id),"mesh")
	if library==null or library.manifest.get("content_id")!=bindings.base_content_id:return reject("Portal requires its original animation resource")
	var reader:=AEM.new();var model: Dictionary=reader.decode(library.read_resource(path,AEM.MAX_BYTES))
	var timing:=Effects.playback_range(model.get("surfaces",[]))
	if timing.is_empty():return reject("Unsupported original portal animation")
	timing.time_ms=timing.start_ms;timing.playing=true
	_rules=rules.duplicate(true);_revision=0
	_max_ms=Frames.simulation_limit(bindings,150)
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":16,
		"slot":int(rules.environment_slot),"model_id":int(rules.model_id),"position":position,"pose":Transform3D(Basis.IDENTITY,position),
		"animation":timing,"elapsed_ms":int(rules.initial_elapsed_ms),"animation_elapsed_ms":0,"extent":int(rules.initial_extent),"visible":true,"scale":1.0}
	return true

func apply_sequence(attack: RefCounted) -> bool:
	error=""
	if _state.is_empty() or not attack is Attack:return reject("Portal operations require the native Alioth sequence")
	var sequence: Dictionary=attack.snapshot()
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if sequence.get(key)!=_state[key]:return reject("Portal sequence identity changed")
	if sequence.get("revision")!=_revision+1:return reject("Portal sequence was replayed or skipped")
	var next:=_state.duplicate(true)
	for op in sequence.frame.portal_operations:
		if op.get("slot")!=_state.slot or op.get("elapsed_ms") not in [-3000,59000] or op.get("extent") not in [0,4096]:return reject("Unsupported portal operation")
		next.elapsed_ms=op.elapsed_ms;next.extent=op.extent
		if op.has("visible"):next.visible=op.visible
	_state=next;_revision=sequence.revision
	return true

func advance(milliseconds: int,camera: Transform3D) -> bool:
	error=""
	if _state.is_empty() or not Numbers.integer(milliseconds,0,_max_ms) or not camera.is_finite():return reject("Portal requires a finite ordinary frame")
	var next:=evaluate_clock(_state,_rules,milliseconds,camera)
	if next.has("error"):return reject(next.error)
	_state=next
	return true

## Callers own source admission, frame limits and any relocation policy. A
## relocation preserves this frame's closing extent before facing its new site.
static func evaluate_clock(state: Dictionary,rules: Dictionary,milliseconds: int,camera: Transform3D,relocation: Dictionary={}) -> Dictionary:
	var next:=state.duplicate(true)
	next.animation_elapsed_ms+=milliseconds
	Playback.advance([next.animation],milliseconds,true)
	if next.visible:
		next.elapsed_ms+=milliseconds
		if next.elapsed_ms<0:
			next.extent=int(rules.extent_scale)-int(Vitals.single(Vitals.single(float(-next.elapsed_ms)/float(rules.open_duration_ms))*float(rules.extent_scale)))
		elif next.elapsed_ms>int(rules.close_start_ms):
			next.extent=int(rules.extent_scale)-int(Vitals.single(Vitals.single(float(next.elapsed_ms-int(rules.close_start_ms))/float(rules.open_duration_ms))*float(rules.extent_scale)))
			if next.elapsed_ms>=int(rules.hide_at_ms):
				if relocation.is_empty():next.visible=false
				else:
					next.elapsed_ms=relocation.elapsed_ms;next.position=relocation.position
		next.scale=Vitals.single(float(int(next.extent)<<int(rules.model_scale_shift))*float(rules.model_scale_fraction))
		var forward:=Vectors.normalized(camera.origin-next.position)
		forward.x=Vitals.single(forward.x+float(rules.facing_x_offset))
		var right:=Vectors.normalized(Vectors.cross(Vector3.UP,forward))
		forward=Vectors.normalized(forward)
		var up:=Vectors.normalized(Vectors.cross(forward,right))
		var pose:=Transform3D(Basis(right,up,forward),next.position)
		if not Flight.rigid_pose(pose):return {"error":"Portal facing exceeds source coordinates"}
		next.pose=pose
	return next

func snapshot() -> Dictionary:return _state.duplicate(true)
func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._rules=_rules.duplicate(true);copy._state=_state.duplicate(true);copy._revision=_revision
	copy._max_ms=_max_ms;return copy
func reject(message: String) -> bool:error=message;return false
