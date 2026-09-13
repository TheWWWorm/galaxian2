extends Node3D
## Explicit unfogged alpha + two-light cube breakup presentation. This owns
## geometry/material sampling, never effect clocks, damage or actor retirement.
const Clock = preload("res://src/simulation/scenery_effect_clock.gd")
const Resources = preload("res://src/content/scenery_effect_resources.gd")
const Models = preload("res://src/presentation/model_resources.gd")
const Sampler = preload("res://src/presentation/scenery_animation.gd")
const Poses = preload("res://src/presentation/scenery_effect_pose.gd")
const Response = preload("res://src/presentation/surface_response.gd")
const Alpha = preload("res://src/presentation/scenery_effect_alpha.gdshader")
const Colors = preload("res://src/presentation/effect_color.gd")
var error := ""
var models: Array[Node3D] = []
var _samplers: Array = []
var _descriptor := {}
var _edition := ""
var _clock_identity: RefCounted

func build(library: RefCounted, visuals: RefCounted, bindings: RefCounted, descriptor: Dictionary, lighting: Dictionary, reflection: RefCounted, response: Dictionary, quality := "high", shared_models: RefCounted = null) -> bool:
	clear()
	if not Resources.effect_parameters(descriptor,bindings):return reject("Unsupported scenery effect descriptor")
	if library==null or visuals==null or library.manifest.get("content_id")!=descriptor.base_content_id or visuals.base_content_id!=descriptor.base_content_id:
		return reject("Scenery effect resources belong to another content base")
	if response.size()!=3 or response.get("variant")!="unfogged_two_light_cube" or not response.has_all(["diffuse_bias","normal_bias"]):
		return reject("Select the explicit unfogged two-light cube effect variant")
	if lighting.get("base_content_id")!=descriptor.base_content_id or lighting.get("binding_id")!=descriptor.binding_id:
		return reject("Scenery effect lighting belongs to another content identity")
	if reflection==null or reflection.selection.get("base_content_id")!=descriptor.base_content_id or reflection.selection.get("binding_id")!=descriptor.binding_id or reflection.selection.get("system_id")!=lighting.get("system_id"):
		return reject("Scenery effect reflection belongs to another location")
	_edition=library.manifest.get("profile",{}).get("edition","")
	if _edition not in ["ios-hd","mac-full-hd"]:return reject("Unsupported scenery effect edition")
	var paths := []
	for index in 2:
		var source: Dictionary=descriptor.models[index]
		if bindings.resolve(source.model_id,"mesh")!=source.resource:return reject("Scenery effect model binding changed")
		var material: Dictionary=bindings.material_for_mesh(source.resource,quality)
		if material.get("render_type")!=(1 if index==0 else 28):return reject("Unsupported scenery effect material family")
		paths.append(source.resource)
	var resources: RefCounted=shared_models
	var owns_resources := resources==null
	if owns_resources:
		resources=Models.new()
		if not resources.prepare(paths,library,visuals,bindings,quality,false,true):return reject(resources.error)
	elif resources.get_script()!=Models or not resources.covers(paths,bindings,quality,false,true):
		return reject("Shared scenery effects require matching prepared models")
	for index in 2:
		var model: Node3D=resources.instantiate(paths[index])
		if model==null:release_owned(resources,owns_resources);return reject(resources.error)
		models.append(model);add_child(model)
		var sampler := Sampler.new()
		if not sampler.configure(model.surfaces):release_owned(resources,owns_resources);return reject(sampler.error)
		var timing: Dictionary=sampler.snapshot().range
		if timing.start_ms!=descriptor.models[index].start_ms or timing.end_ms!=descriptor.models[index].end_ms:
			release_owned(resources,owns_resources);return reject("Scenery effect descriptor differs from its animation data")
		for surface_index in model.surfaces.size():
			var surface: Dictionary=model.surfaces[surface_index]
			if surface.uvs.is_empty() or surface.normals.is_empty() or not surface.colors.is_empty():
				release_owned(resources,owns_resources);return reject("Unsupported scenery effect vertex attributes")
			var original: ShaderMaterial=model.materials[surface_index]
			var material: ShaderMaterial
			if index==0:
				material=ShaderMaterial.new();material.shader=Alpha
				material.set_shader_parameter("diffuse_texture",original.get_shader_parameter("diffuse_texture"))
			else:
				var adapter := Response.new()
				if not adapter.from_imported(original,bindings.surface_material,lighting,reflection.texture,response.diffuse_bias,response.normal_bias,"two_light_cube"):
					release_owned(resources,owns_resources);return reject(adapter.error)
				material=adapter.material
				# The solid shader reads loader-prepared UVs and ignores tint.
				material.set_shader_parameter("uv_offset",Vector2.ZERO)
				material.set_shader_parameter("uv_scale",Vector2.ONE)
				material.set_shader_parameter("uv_angle",0.0)
			model.materials[surface_index]=material
			model.instances[surface_index].material_override=material
			# Sampler poses already contain the complete world transform. Scene
			# container transforms must not apply it or the effect scale again.
			model.instances[surface_index].top_level=true
		_samplers.append(sampler)
	release_owned(resources,owns_resources)
	_descriptor=descriptor.duplicate(true)
	visible=false
	return true

func apply_effect(effect: RefCounted, camera: Transform3D, parent_rgba: PackedByteArray, global_tint: Vector4, darken_value: Variant) -> bool:
	var prepared := prepare_effect(effect,camera,parent_rgba,global_tint,darken_value)
	if prepared.is_empty():return false
	commit_effect(prepared)
	return true

# Stage sampling independently so a field can validate every actor before any
# scene node changes. Candidates are private to the native presentation owner.
func prepare_effect(effect: RefCounted, camera: Transform3D, parent_rgba: PackedByteArray, global_tint: Vector4, darken_value: Variant) -> Dictionary:
	error=""
	if _descriptor.is_empty():return failed_frame("Build scenery effect geometry before presenting it")
	if effect==null or effect.get_script()!=Clock or effect.presentation_identity()==null:
		return failed_frame("Scenery effect geometry requires a configured native clock")
	if _clock_identity!=null and effect.presentation_identity()!=_clock_identity:
		return failed_frame("Scenery effect geometry follows one logical effect")
	var state: Dictionary=effect.snapshot()
	for key in ["base_content_id","binding_id","base_model_id","effect_type"]:
		if state.get(key)!=_descriptor[key]:return failed_frame("Scenery effect clock belongs to another prepared effect")
	if state.get("source_duration_ms")!=_descriptor.duration_ms or state.get("models",[]).size()!=2:return failed_frame("Scenery effect clock timing differs from prepared geometry")
	for index in 2:
		for key in ["model_id","resource","start_ms","end_ms"]:
			if state.models[index].get(key)!=_descriptor.models[index][key]:return failed_frame("Scenery effect clock model differs from prepared geometry")
	if not (darken_value is float or darken_value is int) or not is_finite(darken_value) or not is_finite(single(darken_value)):
		return failed_frame("Scenery effect darkening must be finite")
	if tint(parent_rgba,global_tint).is_empty():return failed_frame("Scenery effect color exceeds source precision")
	var roots := Poses.for_effect(effect,camera)
	if roots.has("error"):return failed_frame(roots.error)
	if not roots.visible:return {"visible":false,"identity":effect.presentation_identity()}
	var staged := [];var samplers := []
	for index in 2:
		var sampler: RefCounted=_samplers[index].fork_for_frame()
		var sampled: Dictionary=sampler.sample(state.models[index].time_ms,roots.alpha if index==0 else roots.breakup)
		if sampled.is_empty():return failed_frame(sampler.error)
		for surface in sampled.surfaces:
			var color := tint(parent_rgba,global_tint,surface.get("color_byte",-1))
			if color.is_empty():return failed_frame("Scenery effect color exceeds source precision")
			surface.tint=color.value
		staged.append(sampled.surfaces);samplers.append(sampler)
	return {"visible":true,"identity":effect.presentation_identity(),"surfaces":staged,
		"samplers":samplers,"darken":single(darken_value) if _edition=="mac-full-hd" else 1.0}

func commit_effect(prepared: Dictionary) -> void:
	visible=prepared.visible;_clock_identity=prepared.identity
	if not visible:return
	for index in 2:
		for surface_index in prepared.surfaces[index].size():
			var row: Dictionary=prepared.surfaces[index][surface_index]
			models[index].instances[surface_index].transform=row.pose
			if index==0:
				models[index].materials[surface_index].set_shader_parameter("effect_tint",row.tint)
				models[index].materials[surface_index].set_shader_parameter("darken_value",prepared.darken)
	_samplers=prepared.samplers

func failed_frame(message: String) -> Dictionary:
	error=message;return {}

func release_owned(resources: RefCounted, owned: bool) -> void:
	if owned:resources.clear()

static func tint(parent_rgba: PackedByteArray, global_tint: Vector4, animation_byte := -1) -> Dictionary:
	return Colors.tint(parent_rgba,global_tint,animation_byte)

static func single(value: float) -> float:
	return Colors.single(value)

func clear() -> void:
	for model in models:
		if is_instance_valid(model):model.free()
	models.clear();_samplers=[];_descriptor={};_edition="";_clock_identity=null
	visible=false;error=""

func fail(message: String) -> bool:
	error=message;return false

func reject(message: String) -> bool:
	clear();return fail(message)
