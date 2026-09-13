extends Node3D
## Travelling projectile models, sampled once per weapon and reused by its slots.
## Preparing a whole group is atomic; presentation never advances a weapon clock.
const State=preload("res://src/simulation/projectile_visual_state.gd")
const Models=preload("res://src/presentation/model_resources.gd")
const Sampler=preload("res://src/presentation/scenery_animation.gd")
const Pose=preload("res://src/presentation/projectile_pose.gd")
const Colors=preload("res://src/presentation/effect_color.gd")
const Surface=preload("res://src/presentation/animated_additive_model.gd")
const Additive=Surface.ShaderSource
var error:=""
var guns:=[]
var _samplers:=[]
var _descriptor:={}
var _identity: RefCounted
var _edition:=""
var _reduced:=false
var _reflected_additive: Shader
var _surface: RefCounted

func build(owner: RefCounted, library: RefCounted, visuals: RefCounted, bindings: RefCounted, reduced_scale:=false) -> bool:
	clear()
	if not owner is State or owner.presentation_identity()==null:return reject("Projectile geometry requires its configured animation owner")
	var state: Dictionary=owner.snapshot()
	if library==null or visuals==null or bindings==null or library.manifest.get("content_id")!=state.base_content_id or visuals.base_content_id!=state.base_content_id or bindings.base_content_id!=state.base_content_id or bindings.binding_id!=state.binding_id:return reject("Projectile resources belong to another content identity")
	var paths:=[]
	for model in state.models:
		if bindings.resolve(model.model_id,"mesh")!=model.resource or bindings.material_for_mesh(model.resource,"high").get("render_type")!=state.rules.render_type:return reject("Unsupported projectile material mapping")
		paths.append(model.resource)
	var resources:=Models.new()
	if not resources.prepare(paths,library,visuals,bindings,"high",false,true):return reject(resources.error)
	_surface=Surface.new();_reflected_additive=_surface.reflected
	for row in state.models:
		var slots:=[]
		for slot in row.capacity:
			var model: Node3D=resources.instantiate(row.resource)
			if model==null:resources.clear();return reject(resources.error)
			add_child(model);slots.append(model);model.visible=false
			if not _surface.prepare_model(model):resources.clear();return reject(_surface.error)
		guns.append({"key":row.key,"slots":slots})
		var sampler:=Sampler.new()
		if not sampler.configure(slots[0].surfaces,row.end_ms==0):resources.clear();return reject(sampler.error)
		if sampler.snapshot().range!={"start_ms":row.start_ms,"end_ms":row.end_ms}:resources.clear();return reject("Projectile animation metadata changed")
		_samplers.append(sampler)
	resources.clear();_identity=owner.presentation_identity();_descriptor=state;_edition=library.manifest.profile.edition;_reduced=reduced_scale
	return true

func prepare_world(owner: RefCounted, world: Dictionary, camera: Transform3D, parent_rgba:=PackedByteArray([255,255,255,255]), global_tint:=Vector4(1,1,1,1), darken:=1.0) -> Dictionary:
	error=""
	if not owner is State or owner.presentation_identity()!=_identity or _descriptor.is_empty():return failed("Projectile geometry follows one configured weapon population")
	var state: Dictionary=owner.snapshot()
	for key in ["base_content_id","binding_id"]:
		if world.get(key)!=_descriptor[key] or state.get(key)!=_descriptor[key]:return failed("Projectile frame belongs to another identity")
	if world.get("elapsed_ms")!=state.elapsed_ms or world.get("projectile_visuals")!=state:return failed("Projectile presentation requires its current world clock")
	if Colors.tint(parent_rgba,global_tint).is_empty() or not is_finite(darken) or not is_finite(Colors.single(darken)):return failed("Invalid projectile color")
	var weapons:=State.weapons(world)
	if weapons.size()!=guns.size() or state.models.size()!=guns.size():return failed("Projectile weapon population changed")
	var prepared:=[];var samplers:=[]
	for i in guns.size():
		var row: Dictionary=state.models[i];var weapon: Dictionary=weapons[i].projectiles
		for key in ["key","item_id","kind","capacity","model_id","resource","captured_up","start_ms","end_ms"]:
			if row.get(key)!=_descriptor.models[i][key]:return failed("Projectile model identity changed")
		if weapons[i].key!=row.key or weapon.weapon.item_id!=row.item_id or weapon.weapon.kind!=row.kind or weapon.slots.size()!=row.capacity:return failed("Projectile slots differ from prepared weapons")
		var sampler: RefCounted=_samplers[i].fork_for_frame()
		var animation: Dictionary=sampler.sample(row.time_ms,Transform3D.IDENTITY)
		if animation.is_empty():return failed(sampler.error)
		var slots:=[]
		for slot in weapon.slots:
			var root:=Pose.sample(slot,row.kind,camera,_reduced,state.rules,row.captured_up)
			if root.has("error"):return failed(root.error)
			var surfaces:=[]
			if root.visible:
				surfaces=_surface.prepare_surfaces(animation,root.pose,parent_rgba,global_tint)
				if surfaces.is_empty():return failed(_surface.error)
			slots.append({"visible":root.visible,"surfaces":surfaces})
		prepared.append(slots);samplers.append(sampler)
	return {"guns":prepared,"samplers":samplers,"darken":Colors.single(darken) if _edition=="mac-full-hd" else 1.0}

func commit_world(prepared: Dictionary) -> void:
	for i in guns.size():
		for slot in guns[i].slots.size():
			var model: Node3D=guns[i].slots[slot];var row: Dictionary=prepared.guns[i][slot]
			model.visible=row.visible
			if not row.visible:continue
			_surface.apply_surfaces(model,row.surfaces,prepared.darken)
	_samplers=prepared.samplers

func clear() -> void:
	for child in get_children():child.free()
	guns=[];_samplers=[];_descriptor={};_identity=null;_edition="";_reduced=false;_reflected_additive=null;_surface=null;error=""
func reject(message: String) -> bool:clear();error=message;return false
func failed(message: String) -> Dictionary:error=message;return {}
