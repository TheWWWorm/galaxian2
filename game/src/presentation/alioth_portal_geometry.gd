extends Node3D
## Original two-surface wormhole, sampled at the accepted native model clock.
const Models=preload("res://src/presentation/model_resources.gd")
const Sampler=preload("res://src/presentation/scenery_animation.gd")
const Additive=preload("res://src/presentation/animated_additive_model.gd")
const Definitions=preload("res://src/content/alioth_flight_definitions.gd")
var error:=""
var model: Node3D
var _identity:={}
var _sampler: RefCounted
var _additive: RefCounted

func build(library: RefCounted,visuals: RefCounted,bindings: RefCounted) -> bool:
	if not Definitions.available(bindings):return reject("This pack has no supported Alioth portal")
	var models:=Models.new();var path: String=bindings.resolve(16994,"mesh")
	if path.is_empty() or not models.prepare([path],library,visuals,bindings):return reject(models.error)
	model=models.instantiate(path);models.clear()
	if model==null:return reject("Original portal model is unavailable")
	add_child(model);_sampler=Sampler.new();_additive=Additive.new()
	if not _sampler.configure(model.surfaces) or not _additive.prepare_model(model):return reject(_sampler.error+_additive.error)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":16,"model_id":16994,"slot":3}
	return true

func prepare_state(state: Dictionary) -> Dictionary:
	error=""
	for key in _identity:
		if state.get(key)!=_identity[key]:return failed("Portal presentation belongs to another environment")
	if _identity.is_empty() or not state.get("pose") is Transform3D or not state.pose.is_finite() or not state.get("visible") is bool:return failed("Portal presentation lost its accepted native state")
	var sampler: RefCounted=_sampler.fork_for_frame()
	var animated: Dictionary=sampler.sample(int(state.animation.time_ms),Transform3D.IDENTITY)
	if animated.is_empty():return failed(sampler.error)
	var pose: Transform3D=state.pose;pose.basis=pose.basis.scaled(Vector3.ONE*float(state.scale))
	var surfaces: Array=_additive.prepare_surfaces(animated,pose,PackedByteArray([255,255,255,255]),Vector4.ONE)
	if surfaces.is_empty():return failed(_additive.error)
	return {"surfaces":surfaces,"sampler":sampler,"visible":state.visible}

func commit_state(frame: Dictionary) -> void:
	_additive.apply_surfaces(model,frame.surfaces,1.0);_sampler=frame.sampler;visible=frame.visible
func failed(message: String) -> Dictionary:error=message;return {}
func reject(message: String) -> bool:error=message;return false
