extends Node3D
## Original beam geometry follows the accepted native recovery state. Rendering
## never moves cargo, advances its clock or emits a recovery transaction.
const Recovery=preload("res://src/simulation/tractor_recovery.gd")
const Models=preload("res://src/presentation/model_resources.gd")
const Sampler=preload("res://src/presentation/scenery_animation.gd")
const Surface=preload("res://src/presentation/animated_additive_model.gd")
const Colors=preload("res://src/presentation/effect_color.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
var error:=""
var beam: Node3D
var _identity: RefCounted
var _sampler: RefCounted
var _surface: RefCounted

func build(owner: RefCounted,library: RefCounted,visuals: RefCounted,bindings: RefCounted) -> bool:
	clear()
	if not owner is Recovery or owner.transaction_identity()==null or not owner.same_identity({"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}):return fail("Tractor geometry requires its configured native device")
	var state: Dictionary=owner.snapshot()
	if state.equipment_id<0 or not state.beam.has("playback"):return fail("Prepare the installed tractor's original model before drawing it")
	var resource: String=state.beam.playback.resource
	var models:=Models.new()
	if not models.prepare([resource],library,visuals,bindings,"high",false,true):return fail(models.error)
	beam=models.instantiate(resource);models.clear()
	add_child(beam);beam.hide();beam.set_meta("source_resource_id",state.beam.model_id)
	_surface=Surface.new();_sampler=Sampler.new()
	if not _surface.prepare_model(beam) or not _sampler.configure(beam.surfaces,true):return fail(_surface.error+_sampler.error)
	_identity=owner.transaction_identity()
	return true

func prepare_world(owner: RefCounted,parent_rgba:=PackedByteArray([255,255,255,255]),global_tint:=Vector4.ONE,darken:=1.0) -> Dictionary:
	error=""
	if _identity==null or not owner is Recovery or owner.transaction_identity()!=_identity:return failed("Tractor geometry follows one equipped device")
	if Colors.tint(parent_rgba,global_tint).is_empty() or not is_finite(darken) or not is_finite(Colors.single(darken)):return failed("Invalid tractor beam color")
	var state: Dictionary=owner.snapshot();var row: Dictionary=state.beam
	var pose: Transform3D=row.pose
	# Scale local columns. A world-axis scale changes diagonal beam orientation.
	for axis in 3:pose.basis[axis]=Vectors.scaled(pose.basis[axis],row.scale[axis])
	if not pose.is_finite():return failed("Tractor beam exceeded finite world coordinates")
	var sampler: RefCounted=_sampler.fork_for_frame()
	var animation: Dictionary=sampler.sample(int(row.playback.time_ms),Transform3D.IDENTITY)
	if animation.is_empty():return failed(sampler.error)
	var surfaces: Array=_surface.prepare_surfaces(animation,pose,parent_rgba,global_tint)
	if surfaces.is_empty():return failed(_surface.error)
	return {"visible":state.active,"surfaces":surfaces,"sampler":sampler,"darken":Colors.single(darken)}

func commit_world(frame: Dictionary) -> void:
	beam.visible=frame.visible
	if frame.visible:_surface.apply_surfaces(beam,frame.surfaces,frame.darken)
	_sampler=frame.sampler

func clear() -> void:
	for child in get_children():child.free()
	beam=null;_identity=null;_sampler=null;_surface=null;error=""
func fail(message: String) -> bool:clear();error=message;return false
func failed(message: String) -> Dictionary:error=message;return {}
