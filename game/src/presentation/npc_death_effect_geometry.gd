extends Node3D
## Native type-zero explosion presentation. Clocks, activity and fragments are
## retained by the death owner; presentation never advances simulation time.
const Player = preload("res://src/simulation/player_destruction.gd")
const Death = preload("res://src/simulation/npc_destruction.gd")
const Freighter = preload("res://src/simulation/freighter_destruction.gd")
const Resources = preload("res://src/content/npc_destruction_resources.gd")
const Models = preload("res://src/presentation/model_resources.gd")
const Sampler = preload("res://src/presentation/scenery_animation.gd")
const Poses = preload("res://src/presentation/npc_destruction_pose.gd")
const Colors = preload("res://src/presentation/effect_color.gd")
const Alpha = preload("res://src/presentation/scenery_effect_alpha.gdshader")
const Additive = preload("res://src/presentation/effect_additive.gdshader")
var error := ""
var models: Array[Node3D]=[]
var body_visible := true
var _samplers := []
var _descriptor := {}
var _identity: RefCounted
var _edition := ""

func build(library: RefCounted, visuals: RefCounted, bindings: RefCounted, death: RefCounted, quality := "high", shared_models: RefCounted = null) -> bool:
	clear()
	if not (death is Death or death is Player or death is Freighter) or death.presentation_identity()==null: return reject("Build Explosion effects from a configured native death owner")
	var state: Dictionary=death.snapshot()
	if library==null or visuals==null or bindings==null or library.manifest.get("content_id")!=state.base_content_id or visuals.base_content_id!=state.base_content_id or bindings.base_content_id!=state.base_content_id or bindings.binding_id!=state.binding_id:
		return reject("Explosion effect resources belong to another content identity")
	var edition: Variant=library.manifest.get("profile",{}).get("edition")
	if edition not in ["ios-hd","mac-full-hd"]: return reject("Unsupported Explosion effect edition")
	var paths := []
	for index in state.effect.models.size():
		var model: Dictionary=state.effect.models[index]
		var expected: String=Resources.PATHS[mini(index,2)]
		if model.resource!=expected or bindings.resolve(model.model_id,"mesh")!=expected: return reject("Unsupported Explosion effect model mapping")
		var material: Dictionary=bindings.material_for_mesh(expected,quality)
		if material.get("render_type")!=(18 if index==0 else 2): return reject("Unsupported Explosion effect material family")
		paths.append(expected)
	var resources: RefCounted=shared_models
	var owns := resources==null
	if owns:
		resources=Models.new()
		if not resources.prepare(paths,library,visuals,bindings,quality,false,true): return reject(resources.error)
	elif not resources is Models or not resources.covers(paths,bindings,quality,false,true): return reject("Explosion effects require matching shared models")
	for index in paths.size():
		var model: Node3D=resources.instantiate(paths[index])
		if model==null: return abort_build(resources,owns,resources.error)
		models.append(model);add_child(model)
		var sampler := Sampler.new()
		if not sampler.configure(model.surfaces): return abort_build(resources,owns,sampler.error)
		var timing: Dictionary=sampler.snapshot().range
		if timing.start_ms!=state.effect.models[index].start_ms or timing.end_ms!=state.effect.models[index].end_ms: return abort_build(resources,owns,"Explosion animation metadata changed")
		for surface_index in model.surfaces.size():
			var surface: Dictionary=model.surfaces[surface_index]
			if surface.uvs.is_empty() or surface.normals.is_empty() or not surface.colors.is_empty(): return abort_build(resources,owns,"Unsupported Explosion effect vertex attributes")
			var material := ShaderMaterial.new();material.shader=Alpha if index==0 else Additive
			material.render_priority=1 if index==0 else 0
			material.set_shader_parameter("diffuse_texture",model.materials[surface_index].get_shader_parameter("diffuse_texture"))
			model.materials[surface_index]=material;model.instances[surface_index].material_override=material
			# Samplers produce complete source-space world poses, including the
			# billboard/fragment root. Do not apply scene-container transforms again.
			model.instances[surface_index].top_level=true
		_samplers.append(sampler)
	if owns: resources.clear()
	_descriptor=state.duplicate(true);_identity=death.presentation_identity();_edition=edition
	visible=false
	return true

func follows(death: RefCounted) -> bool:
	return death!=null and death.presentation_identity()==_identity and not _descriptor.is_empty()

func prepare_effect(death: RefCounted, camera: Transform3D, parent_rgba: PackedByteArray, global_tint: Vector4, darken: Variant) -> Dictionary:
	error=""
	if _descriptor.is_empty() or not (death is Death or death is Player or death is Freighter) or death.presentation_identity()!=_identity: return failed_frame("Explosion geometry follows one configured death owner")
	var state: Dictionary=death.snapshot()
	for key in ["base_content_id","binding_id","actor_id","fragments"]:
		if state.get(key)!=_descriptor[key]: return failed_frame("Explosion effect identity or retained fragments changed")
	if not state.get("effect") is Dictionary or not state.effect.get("models") is Array or state.effect.models.size()!=models.size(): return failed_frame("Explosion effect model population changed")
	if state.effect.get("duration_ms")!=_descriptor.effect.duration_ms: return failed_frame("Explosion effect duration changed")
	for index in models.size():
		if not state.effect.models[index] is Dictionary: return failed_frame("Invalid Explosion model clock")
		for key in ["model_id","resource","start_ms","end_ms"]:
			if state.effect.models[index].get(key)!=_descriptor.effect.models[index][key]: return failed_frame("Explosion model clock differs from prepared geometry")
	if Colors.tint(parent_rgba,global_tint).is_empty() or not (darken is int or darken is float) or not is_finite(darken) or not is_finite(Colors.single(darken)): return failed_frame("Invalid Explosion effect color")
	var roots := Poses.for_death(death,camera)
	if roots.has("error"): return failed_frame(roots.error)
	if not roots.effect_visible: return {"visible":false,"body_visible":roots.body_visible}
	var samplers := [];var surfaces := []
	for index in models.size():
		var sampler: RefCounted=_samplers[index].fork_for_frame()
		var sampled: Dictionary=sampler.sample(state.effect.models[index].get("time_ms"),roots.roots[index])
		if sampled.is_empty(): return failed_frame(sampler.error)
		for surface in sampled.surfaces:
			var color := Colors.tint(parent_rgba,global_tint,surface.get("color_byte",-1))
			if color.is_empty(): return failed_frame("Explosion effect color exceeded source precision")
			surface.tint=color.value
		samplers.append(sampler);surfaces.append(sampled.surfaces)
	return {"visible":true,"body_visible":roots.body_visible,"samplers":samplers,"surfaces":surfaces,"darken":Colors.single(darken) if _edition=="mac-full-hd" else 1.0}

func commit_effect(prepared: Dictionary) -> void:
	visible=prepared.visible;body_visible=prepared.body_visible
	if not visible: return
	for index in models.size():
		for surface_index in models[index].instances.size():
			var row: Dictionary=prepared.surfaces[index][surface_index]
			models[index].instances[surface_index].transform=row.pose
			models[index].materials[surface_index].set_shader_parameter("effect_tint",row.tint)
			models[index].materials[surface_index].set_shader_parameter("darken_value",prepared.darken)
	_samplers=prepared.samplers

func apply_effect(death: RefCounted, camera: Transform3D, parent_rgba: PackedByteArray, global_tint: Vector4, darken: Variant) -> bool:
	var result := prepare_effect(death,camera,parent_rgba,global_tint,darken)
	if result.is_empty(): return false
	commit_effect(result)
	return true

func clear() -> void:
	for model in models:
		if is_instance_valid(model): model.free()
	models.clear();_samplers=[];_descriptor={};_identity=null;_edition=""
	visible=false;body_visible=true;error=""

func abort_build(resources: RefCounted, owns: bool, message: String) -> bool:
	if owns: resources.clear()
	return reject(message)

func reject(message: String) -> bool:
	clear();error=message;return false

func failed_frame(message: String) -> Dictionary:
	error=message;return {}
