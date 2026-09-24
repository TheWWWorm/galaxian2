extends RefCounted
## Shared source environment-slot0 lock. Ordinary flight supplies an already
## validated scanner sample; Void29 configures the same controller separately.
const TargetProjection=preload("res://src/presentation/target_projection.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const Frames=preload("res://src/simulation/frame_clock.gd")
const Library=preload("res://src/content/library.gd")
const Mining=preload("res://src/content/mining_targeting_definitions.gd")

const ORDINARY_RULES:={"station_slot":0,"outer_window_width_divisor":8,"inner_aim_width_divisor":18}
var error:=""
var _identity:={}
var _rules:={}
var _perspective:={}
var _frame_radii:=Vector2.ZERO
var _max_frame_ms:=0
var _scanner_id:=-1
var _duration_ms:=0
var _station_id:=-1
var _found_index:=-1
var _aimed_index:=-1
var _locked_index:=-1
var _elapsed_ms:=0
var _sample:={}

func configure_ordinary(bindings: RefCounted,station: Dictionary,mining: Dictionary,frame_radii: Vector2,campaign_cursor: int) -> bool:
	error=""
	if bindings==null or not Library.valid_hash(bindings.get("base_content_id")) or not Library.valid_hash(bindings.get("binding_id")) or not Mining.parameters(bindings.get("mining_targeting")):
		return reject("Ordinary station targeting requires source scanner declarations")
	if campaign_cursor<0 or campaign_cursor==29 or station.get("base_content_id")!=bindings.base_content_id or station.get("binding_id")!=bindings.binding_id or not station.get("station_id") is int or station.station_id<0 or not station.get("pose") is Transform3D or not Flight.rigid_pose(station.pose):
		return reject("Ordinary station targeting requires its constructed exterior")
	if mining.get("base_content_id")!=bindings.base_content_id or mining.get("binding_id")!=bindings.binding_id or not mining.get("scanner_id") is int or mining.scanner_id< -1 or not mining.get("duration_ms") is int or mining.duration_ms<1:
		return reject("Ordinary station targeting requires the flight scanner")
	var projection:=TargetProjection.new()
	if not projection.configure(bindings.flight_projection,Vector2i.ONE,frame_radii):return reject(projection.error)
	var frame_limit: int=Frames.simulation_limit(bindings)
	if frame_limit<=0:return reject("Ordinary station lock has no supported frame")
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":campaign_cursor}
	_rules=ORDINARY_RULES;_perspective=bindings.flight_projection.duplicate(true)
	_frame_radii=frame_radii;_max_frame_ms=frame_limit;_scanner_id=int(mining.scanner_id);_duration_ms=int(mining.duration_ms);_station_id=int(station.station_id)
	_found_index=-1;_aimed_index=-1;_locked_index=-1;_elapsed_ms=0;_sample={}
	return true

## A disabled controller preserves its previous state. All other frames sample
## the live station pose and explicit owner gates supplied by the flight.
func advance(observation: Dictionary) -> bool:
	error=""
	if _rules.is_empty():return reject("Configure station targeting before advancing")
	for key in _identity:
		if observation.get(key)!=_identity[key]:return reject("Station observation belongs to another flight")
	var delta: Variant=observation.get("delta_ms")
	var viewport: Variant=observation.get("viewport_size")
	var camera: Variant=observation.get("camera_pose")
	var aim: Variant=observation.get("aim_point")
	var station: Variant=observation.get("station")
	if not delta is int or delta<0 or delta>_max_frame_ms or not viewport is Vector2i or viewport.x<1 or viewport.y<1 or not camera is Transform3D or not Flight.rigid_pose(camera) or not aim is Vector3 or not aim.is_finite() or not TargetProjection.safe_pixel(aim.x) or not TargetProjection.safe_pixel(aim.y) or not station is Dictionary:
		return reject("Station targeting requires a bounded aim and camera frame")
	if station.get("environment_slot")!=int(_rules.station_slot) or not station.get("pose") is Transform3D or not Flight.rigid_pose(station.pose) or not station.get("active") is bool:
		return reject("Station targeting requires the live slot0 body")
	for key in ["controller_enabled","held_primary","other_selected_target","mining_approach_active","alternate_operation_active","selected_target_active"]:
		if not observation.get(key) is bool:return reject("Station targeting requires explicit owner gates: "+key)
	if not observation.controller_enabled:return true
	var projection:=TargetProjection.new()
	if not projection.configure(_perspective,viewport,_frame_radii):return reject(projection.error)
	var projected: Dictionary=projection.project(camera,station.pose.origin)
	if projected.has("error"):return reject(projection.error)
	var center:=Vector3(float(viewport.x>>1),float(viewport.y>>1),0.0)
	var outer: bool=station.active and projected.in_view and _inside(projected.pixels,center,viewport,int(_rules.outer_window_width_divisor))
	var found: int=int(_rules.station_slot) if outer else -1
	var inner: bool=outer and _inside(projected.pixels,aim,viewport,int(_rules.inner_aim_width_divisor))
	var candidate: int=int(_rules.station_slot) if inner and not observation.other_selected_target and not observation.held_primary else -1
	var suppressed: bool=observation.mining_approach_active or observation.alternate_operation_active or observation.selected_target_active
	var aimed: int=candidate if not suppressed else -1
	var elapsed: int=_elapsed_ms if aimed==_aimed_index and aimed>=0 else 0
	if aimed>=0:
		if elapsed>2147483647-delta:return reject("Station lock time exceeds source integer range")
		elapsed+=delta
	var locked: int=int(_rules.station_slot) if aimed>=0 and elapsed>_duration_ms else -1
	_found_index=found;_aimed_index=aimed;_locked_index=locked;_elapsed_ms=elapsed
	_sample={"station_pixels":projected.pixels,"station_in_view":projected.in_view,"outer_window":outer,"inner_window":inner,"station_position":station.pose.origin}
	return true

func _inside(pixels: Vector2i,aim: Vector3,viewport: Vector2i,divisor: int) -> bool:
	@warning_ignore("integer_division")
	var radius: int=viewport.x/divisor
	var low_x: int=int(TargetProjection.single(aim.x-float(radius)))
	var low_y: int=int(TargetProjection.single(aim.y-float(radius)))
	return pixels.x>low_x and pixels.x<low_x+radius*2 and pixels.y>low_y and pixels.y<low_y+radius*2

func snapshot() -> Dictionary:
	if _rules.is_empty():return {}
	var result: Dictionary=_identity.duplicate()
	result.merge({"found_index":_found_index,"aimed_index":_aimed_index,
		"locked_index":_locked_index,"elapsed_ms":_elapsed_ms,"duration_ms":_duration_ms,
		"scanner_id":_scanner_id,"mother_ship_locked":_locked_index==int(_rules.station_slot)})
	if _station_id>=0:result.station_id=_station_id
	result.merge(_sample.duplicate(true))
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._identity=_identity;copy._rules=_rules;copy._perspective=_perspective
	copy._frame_radii=_frame_radii;copy._max_frame_ms=_max_frame_ms
	copy._scanner_id=_scanner_id;copy._duration_ms=_duration_ms;copy._station_id=_station_id
	copy._found_index=_found_index;copy._aimed_index=_aimed_index;copy._locked_index=_locked_index
	copy._elapsed_ms=_elapsed_ms;copy._sample=_sample.duplicate(true)
	return copy

func reject(message: String) -> bool:error=message;return false
