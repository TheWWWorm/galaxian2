extends Node3D
## Source hyperdrive surfaces and retained root pose. Animation playback and draw
## visibility are independent: the source also draws a stopped model's last pose.
const Frame=preload("res://src/simulation/opening_escape_frame.gd")
const Models=preload("res://src/presentation/model_resources.gd")
const Sampler=preload("res://src/presentation/scenery_animation.gd")
const Surface=preload("res://src/presentation/animated_additive_model.gd")
const Colors=preload("res://src/presentation/effect_color.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
var error:=""
var model: Node3D
var _sampler: RefCounted
var _surface: RefCounted
var _identity: RefCounted
var _descriptor:={}
var _edition:=""

func build(owner: RefCounted, library: RefCounted, visuals: RefCounted, bindings: RefCounted) -> bool:
	clear()
	if not owner is Frame or owner.presentation_identity()==null:return reject("Hyperdrive geometry requires a configured escape owner")
	var state: Dictionary=owner.snapshot()
	if library==null or visuals==null or bindings==null or library.manifest.get("content_id")!=state.base_content_id or visuals.base_content_id!=state.base_content_id or bindings.base_content_id!=state.base_content_id or bindings.binding_id!=state.binding_id:
		return reject("Hyperdrive resources belong to another opening")
	var effect: Dictionary=state.effect
	if bindings.resolve(effect.model_id,"mesh")!=effect.resource:return reject("Hyperdrive model mapping changed")
	var material: Dictionary=bindings.material_for_mesh(effect.resource,"high")
	if material.get("id")!=27262 or material.get("render_type")!=2 or not matches_integers(material.get("texture_ids"),[24203,65535,65535,65535,65535,65535,65535,65535]) or not matches_integers(material.get("parameter_bits"),[0,3240099840,0,0]):
		return reject("Unsupported hyperdrive material mapping")
	var resources:=Models.new()
	if not resources.prepare([effect.resource],library,visuals,bindings,"high",false,true):return reject(resources.error)
	model=resources.instantiate(effect.resource)
	if model==null:resources.clear();return reject(resources.error)
	add_child(model);_surface=Surface.new();_sampler=Sampler.new()
	if not _surface.prepare_model(model):resources.clear();return reject(_surface.error)
	if not _sampler.configure(model.surfaces):resources.clear();return reject(_sampler.error)
	resources.clear()
	if _sampler.snapshot().range!={"start_ms":effect.start_ms,"end_ms":effect.end_ms}:return reject("Hyperdrive animation range changed")
	_identity=owner.presentation_identity();_descriptor=state;_edition=library.manifest.profile.edition
	return true

func prepare_frame(owner: RefCounted, parent_rgba:=PackedByteArray([255,255,255,255]), global_tint:=Vector4.ONE, darken:=1.0) -> Dictionary:
	error=""
	if not owner is Frame or _identity==null or owner.presentation_identity()!=_identity:return failed("Hyperdrive presentation follows one configured escape")
	var state: Dictionary=owner.snapshot()
	for key in ["base_content_id","binding_id"]:
		if state.get(key)!=_descriptor[key]:return failed("Hyperdrive frame belongs to another content identity")
	if Colors.tint(parent_rgba,global_tint).is_empty() or not is_finite(darken) or not is_finite(Colors.single(darken)):return failed("Invalid hyperdrive tint")
	var effect: Dictionary=state.effect
	for key in ["model_id","resource","start_ms","end_ms"]:
		if effect.get(key)!=_descriptor.effect[key]:return failed("Hyperdrive animation identity changed")
	if not Numbers.integer(effect.get("sample_time_ms"),effect.start_ms,effect.end_ms) or not effect.get("playing") is bool or not state.get("effect_pose") is Transform3D or not state.effect_pose.is_finite() or state.effect_pose.origin!=effect.get("position"):
		return failed("Invalid retained hyperdrive pose or sampling time")
	var sampler: RefCounted=_sampler.fork_for_frame()
	var animation: Dictionary=sampler.sample(int(effect.sample_time_ms),Transform3D.IDENTITY)
	if animation.is_empty():return failed(sampler.error)
	var surfaces: Array=_surface.prepare_surfaces(animation,state.effect_pose,parent_rgba,global_tint)
	if surfaces.is_empty():return failed(_surface.error)
	return {"sampler":sampler,"surfaces":surfaces,"darken":Colors.single(darken) if _edition=="mac-full-hd" else 1.0}

func commit_frame(prepared: Dictionary) -> void:
	_surface.apply_surfaces(model,prepared.surfaces,prepared.darken)
	model.visible=true;_sampler=prepared.sampler

static func matches_integers(values: Variant, expected: Array) -> bool:
	if not values is Array or values.size()!=expected.size():return false
	for i in expected.size():
		if not Numbers.integer(values[i],expected[i],expected[i]):return false
	return true

func clear() -> void:
	for child in get_children():child.free()
	model=null;_sampler=null;_surface=null;_identity=null;_descriptor={};_edition="";error=""
func reject(message: String) -> bool:clear();error=message;return false
func failed(message: String) -> Dictionary:error=message;return {}
