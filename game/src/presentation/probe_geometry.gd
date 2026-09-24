extends Node3D
## Source probe model 14290. The mission owns its pose, visibility and clock.
const Models=preload("res://src/presentation/model_resources.gd")
const Sampler=preload("res://src/presentation/scenery_animation.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const MODEL_ID:=14290
const PATH:="resources/data/assets/main/3d/meshes/misc/scanner_probe.aem"
var error:=""
var model: Node3D
var _identity:={}
var _sampler: RefCounted
var _pending:={}

func build(library: RefCounted,visuals: RefCounted,bindings: RefCounted) -> bool:
	clear()
	if library==null or visuals==null or bindings==null:return fail("Probe requires content, visuals and bindings")
	var path: String=bindings.resolve(MODEL_ID,"mesh")
	if path!=PATH:return fail("Probe model 14290 is absent from the source bindings")
	var material: Dictionary=bindings.material_for_mesh(path,"high")
	if material.get("render_type")!=28:return fail("Probe requires its original lit material")
	var models:=Models.new()
	if not models.prepare([path],library,visuals,bindings,"high",true,true):return fail(models.error)
	model=models.instantiate(path);models.clear()
	if model==null:return fail("Original probe model could not be instantiated")
	if model.surfaces.size()!=1 or not _has_no_keys(model.surfaces[0]):return reject("Probe model has unsupported internal launch animation")
	_sampler=Sampler.new()
	if not _sampler.configure(model.surfaces,true):return reject(_sampler.error)
	add_child(model)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"model_id":MODEL_ID}
	visible=false
	return true

func prepare_state(state: Dictionary) -> Dictionary:
	error="";_pending={}
	if _identity.is_empty():return failed("Build the source probe before preparing its frame")
	for key in _identity:
		if state.get(key)!=_identity[key]:return failed("Probe frame belongs to another content identity or model")
	if not Flight.rigid_pose(state.get("pose")) or not state.get("visible") is bool:
		return failed("Probe frame requires a finite rigid pose and explicit visibility")
	var model_time: Variant=state.get("model_time_ms")
	if not model_time is int or model_time<0:return failed("Probe frame requires explicit nonnegative model time")
	var sampler: RefCounted=_sampler.fork_for_frame()
	var sampled: Dictionary=sampler.sample(model_time,Transform3D.IDENTITY)
	if sampled.is_empty() or sampled.surfaces.size()!=model.instances.size():return failed(sampler.error if not sampler.error.is_empty() else "Probe source surface sample changed")
	var frame:={"pose":state.pose,"visible":state.visible,"surfaces":sampled.surfaces}
	_pending={"frame":frame.duplicate(true),"sampler":sampler}
	return frame

func commit_state(frame: Dictionary) -> bool:
	if _pending.is_empty() or frame!=_pending.frame:return fail("Probe frame was not accepted for this presentation")
	var accepted: Dictionary=_pending.frame
	model.transform=accepted.pose
	for index in model.instances.size():model.instances[index].transform=accepted.surfaces[index].pose
	_sampler=_pending.sampler
	visible=accepted.visible
	_pending={}
	return true

func clear() -> void:
	if model!=null and is_instance_valid(model):model.free()
	model=null;_sampler=null;_identity={};_pending={};visible=false;error=""

static func _has_no_keys(surface: Dictionary) -> bool:
	if not surface.get("tracks") is Dictionary:return false
	for group in surface.tracks.values():
		if not group is Array:return false
		for track in group:
			if not track is Dictionary or not track.get("keys") is PackedFloat32Array or not track.keys.is_empty():return false
	return true

func failed(message: String) -> Dictionary:error=message;return {}
func fail(message: String) -> bool:error=message;return false
func reject(message: String) -> bool:clear();return fail(message)
