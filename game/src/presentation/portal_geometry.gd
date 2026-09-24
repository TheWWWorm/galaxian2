extends Node3D
## Original two-surface wormhole, sampled at an accepted native model clock.
## Admission, pose, visibility, extent and elapsed time belong to its caller.
const Models=preload("res://src/presentation/model_resources.gd")
const Sampler=preload("res://src/presentation/scenery_animation.gd")
const Additive=preload("res://src/presentation/animated_additive_model.gd")
var error:=""
var model: Node3D
var _identity:={}
var _sampler: RefCounted
var _additive: RefCounted

func _build_portal(library: RefCounted,visuals: RefCounted,bindings: RefCounted,identity: Dictionary) -> bool:
	var models:=Models.new();var path: String=bindings.resolve(int(identity.model_id),"mesh")
	if path.is_empty() or not models.prepare([path],library,visuals,bindings):return reject(models.error)
	model=models.instantiate(path);models.clear()
	if model==null:return reject("Original portal model is unavailable")
	add_child(model);_sampler=Sampler.new();_additive=Additive.new()
	if not _sampler.configure(model.surfaces) or not _additive.prepare_model(model):return reject(_sampler.error+_additive.error)
	_identity=identity.duplicate(true)
	return true

func prepare_state(state: Dictionary) -> Dictionary:
	error=""
	for key in _identity:
		if state.get(key)!=_identity[key]:return failed("Portal presentation belongs to another environment")
	if _identity.is_empty() or not state.get("pose") is Transform3D or not state.pose.is_finite() or not state.get("visible") is bool:return failed("Portal presentation lost its accepted native state")
	var animation: Variant=state.get("animation")
	var scale: Variant=state.get("scale")
	if not animation is Dictionary or not animation.get("time_ms") is int or animation.time_ms<0:return failed("Portal presentation lost its native animation clock")
	if not (scale is float or scale is int) or not is_finite(float(scale)):return failed("Portal presentation requires a finite native scale")
	var sampler: RefCounted=_sampler.fork_for_frame()
	var animated: Dictionary=sampler.sample(animation.time_ms,Transform3D.IDENTITY)
	if animated.is_empty():return failed(sampler.error)
	var pose: Transform3D=state.pose;pose.basis=pose.basis.scaled(Vector3.ONE*float(scale))
	var surfaces: Array=_additive.prepare_surfaces(animated,pose,PackedByteArray([255,255,255,255]),Vector4.ONE)
	if surfaces.is_empty():return failed(_additive.error)
	return {"surfaces":surfaces,"sampler":sampler,"visible":state.visible}

func commit_state(frame: Dictionary) -> void:
	_additive.apply_surfaces(model,frame.surfaces,1.0);_sampler=frame.sampler;visible=frame.visible
func failed(message: String) -> Dictionary:error=message;return {}
func reject(message: String) -> bool:error=message;return false
