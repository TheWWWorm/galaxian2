extends RefCounted
## Held flight acceleration. Input owns delivery, the flight supplies already
## published navigation/combat flags, and each accepted frame advances once.
const Definitions=preload("res://src/content/fast_forward_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Library=preload("res://src/content/library.gd")
var error:=""
var _rules:={}
var _identity:={}
var _held:=false
var _active:=false
var _radar_ready:=false
var _scanner_present:=false
var _battle_count:=0
var _radar_marked_actor: Variant=false

## This capability covers the already supported ordinary constructors. Special
## cloaking and scripted radar overrides need their own native state owners.
static func supported_population(actors: Array) -> bool:
	for actor in actors:
		if not actor is Dictionary or actor.get("actor_kind") not in [0,1,2,3,8] or actor.get("void_encounter",false) or actor.get("radar_hidden",false) or actor.get("asteroid",false):return false
	return true

func configure(bindings: RefCounted) -> bool:
	clear()
	if bindings==null or not Definitions.parameters(bindings.get("fast_forward")):
		return reject("Fast Forward requires this content's verified declarations")
	if not Library.valid_hash(bindings.base_content_id) or not Library.valid_hash(bindings.binding_id):
		return reject("Fast Forward requires a complete content identity")
	if bindings.frame_clock.get("max_frame_milliseconds")!=bindings.fast_forward.timing.real_frame_max_ms:
		return reject("Fast Forward and the raw frame clock disagree")
	_rules=bindings.fast_forward.duplicate(true)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	return true

func configure_radar(catalogues: RefCounted,equipment_ids: Array) -> bool:
	error=""
	if not Definitions.radar_available(_rules) or catalogues==null or catalogues.content_id!=_identity.get("base_content_id"):return reject("Fast Forward radar requires matching verified equipment")
	var installed:=false
	var items: Array=catalogues.tables.get("items",[])
	for id in equipment_ids:
		if not Numbers.integer(id,0,items.size()-1):return reject("Fast Forward scanner is absent from the catalogue")
		var arrays: Variant=items[int(id)].get("arrays")
		if not arrays is Array or arrays.size()<3 or not arrays[2] is PackedInt32Array or arrays[2].size()<6:return reject("Fast Forward scanner lacks its declared equipment type")
		if arrays[2][5]==_rules.radar.scanner_equipment_type:installed=true
	_scanner_present=installed;_radar_ready=true;_battle_count=0;_radar_marked_actor=false
	return true

func publish_radar(actors: Array,visible: bool,music_id: int=-1) -> bool:
	error=""
	if not _radar_ready:return reject("Prepare the radar before publishing combat state")
	if not visible:return true
	# This source music mode bypasses publication and preserves the last sample.
	if music_id==_rules.radar.guarded_music_id:return true
	if not supported_population(actors):return reject("Fast Forward radar requires explicit state for this special actor")
	var count:=0
	var marked:=false;var unknown_marking:=false
	for actor in actors:
		if not actor.get("active") is bool or not actor.get("hostile") is bool or not Numbers.integer(actor.get("actor_mode"),0,2147483647):return reject("Fast Forward radar received an incomplete actor lifecycle")
		# The world list omits asteroids. Its Junk entries remain debris even
		# when active; cargo presence and hull are not combat membership tests.
		if _scanner_present and actor.active and actor.actor_mode not in _rules.radar.inactive_modes and actor.get("population_group","")!="debris" and actor.hostile:
			count+=1
			if actor.get("radar_marked_actor") is bool:marked=marked or actor.radar_marked_actor
			else:unknown_marking=true
	_battle_count=count
	_radar_marked_actor=true if marked else null if unknown_marking else false
	return true

func battle() -> bool:return _battle_count>0
func battle_count() -> int:return _battle_count

func radar_music_context() -> Dictionary:
	# supported_population excludes kind10; legacy actor observations may lack
	# the additional source marker and must not silently imply that it is clear.
	var context:={"radar_kind10":false}
	if _radar_marked_actor!=null:context.radar_marked_actor=_radar_marked_actor
	return context

func press(navigation: bool,battle: bool,near_target: bool) -> bool:
	error=""
	if _rules.is_empty():return reject("Configure Fast Forward before delivering input")
	if _held:return true
	_held=true
	_active=navigation and not battle and not near_target
	return true

func release(time_released:=true) -> bool:
	error=""
	if _rules.is_empty():return reject("Configure Fast Forward before releasing input")
	if time_released:_held=false
	_active=false
	return true

func frame(milliseconds: Variant,battle: bool,near_target: bool,radio: bool,paused:=false) -> Dictionary:
	error=""
	if _rules.is_empty() or not Numbers.integer(milliseconds,int(_rules.timing.real_frame_min_ms),int(_rules.timing.real_frame_max_ms)):
		reject("Fast Forward requires a bounded raw frame interval")
		return {}
	if paused:return {"real_ms":int(milliseconds),"simulation_ms":0,"camera_ms":0,"camera_passes":0,"reset":false}
	var reset:=_active and (battle or near_target or radio)
	if reset:_active=false
	var multiplier:=float(_rules.timing.fast_multiplier if _active else _rules.timing.normal_multiplier)
	var simulation_ms:=int(single(single(float(milliseconds))*multiplier))
	var camera_ms:=int(single(single(float(simulation_ms))/multiplier)) if _active else simulation_ms
	return {"real_ms":int(milliseconds),"simulation_ms":simulation_ms,"camera_ms":camera_ms,
		"camera_passes":int(_rules.timing.fast_camera_passes if _active else _rules.timing.normal_camera_passes),"reset":reset}

func active() -> bool:return _active
func held() -> bool:return _held

func snapshot() -> Dictionary:
	if _rules.is_empty():return {}
	var result:=_identity.duplicate()
	result.merge({"held":_held,"active":_active,"multiplier":float(_rules.timing.fast_multiplier if _active else _rules.timing.normal_multiplier)})
	if _radar_ready:result.merge({"battle":battle(),"battle_count":_battle_count,"scanner_present":_scanner_present})
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._rules=_rules;copy._identity=_identity;copy._held=_held;copy._active=_active
	copy._radar_ready=_radar_ready;copy._scanner_present=_scanner_present;copy._battle_count=_battle_count
	copy._radar_marked_actor=_radar_marked_actor
	return copy

func clear() -> void:
	error="";_rules={};_identity={};_held=false;_active=false
	_radar_ready=false;_scanner_present=false;_battle_count=0;_radar_marked_actor=false

static func single(value: float) -> float:return PackedFloat32Array([value])[0]
func reject(message: String) -> bool:error=message;return false
