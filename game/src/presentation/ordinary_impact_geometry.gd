extends Node3D
## Slot-local, one-shot source impacts. Geometry follows retained sampling time,
## not the reset playback clock, and copies the current camera basis verbatim.
const State=preload("res://src/simulation/ordinary_impact_state.gd")
const Models=preload("res://src/presentation/model_resources.gd")
const Sampler=preload("res://src/presentation/scenery_animation.gd")
const Surface=preload("res://src/presentation/animated_additive_model.gd")
const Colors=preload("res://src/presentation/effect_color.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
var error:=""
var guns:=[]
var _samplers:=[]
var _descriptor:={}
var _identity: RefCounted
var _edition:=""
var _surface: RefCounted

func build(owner: RefCounted, library: RefCounted, visuals: RefCounted, bindings: RefCounted) -> bool:
	clear()
	if not owner is State or owner.presentation_identity()==null:return reject("Impact geometry requires its configured clock owner")
	var state: Dictionary=owner.snapshot()
	if library==null or visuals==null or bindings==null or library.manifest.get("content_id")!=state.base_content_id or visuals.base_content_id!=state.base_content_id or bindings.base_content_id!=state.base_content_id or bindings.binding_id!=state.binding_id:return reject("Impact resources belong to another identity")
	var paths:=[]
	for weapon in state.weapons:
		if bindings.resolve(weapon.model_id,"mesh")!=weapon.resource or bindings.material_for_mesh(weapon.resource,"high").get("render_type")!=state.rules.render_type:return reject("Unsupported impact material mapping")
		paths.append(weapon.resource)
	var resources:=Models.new()
	if not resources.prepare(paths,library,visuals,bindings,"high",false,true):return reject(resources.error)
	_surface=Surface.new()
	for weapon in state.weapons:
		var slots:=[];var samplers:=[]
		for row in weapon.slots:
			var model: Node3D=resources.instantiate(weapon.resource)
			if model==null:resources.clear();return reject(resources.error)
			add_child(model);slots.append(model);model.visible=false
			if not _surface.prepare_model(model):resources.clear();return reject(_surface.error)
			var sampler:=Sampler.new()
			if not sampler.configure(model.surfaces):resources.clear();return reject(sampler.error)
			if sampler.snapshot().range!={"start_ms":row.start_ms,"end_ms":row.end_ms}:resources.clear();return reject("Impact animation metadata changed")
			samplers.append(sampler)
		guns.append({"key":weapon.key,"slots":slots});_samplers.append(samplers)
	resources.clear();_identity=owner.presentation_identity();_descriptor=state;_edition=library.manifest.profile.edition
	return true

func prepare_world(owner: RefCounted, world: Dictionary, camera: Transform3D, parent_rgba:=PackedByteArray([255,255,255,255]), global_tint:=Vector4.ONE, darken:=1.0) -> Dictionary:
	error=""
	if not owner is State or _descriptor.is_empty() or owner.presentation_identity()!=_identity:return failed("Impact geometry follows one configured owner")
	var state: Dictionary=owner.snapshot()
	for key in ["base_content_id","binding_id"]:
		if state.get(key)!=_descriptor[key] or world.get(key)!=_descriptor[key]:return failed("Impact frame belongs to another identity")
	if world.get("elapsed_ms")!=state.elapsed_ms or world.get("impact_visuals")!=state:return failed("Impact presentation requires its current world clock")
	if not camera.is_finite() or Colors.tint(parent_rgba,global_tint).is_empty() or not is_finite(darken) or not is_finite(Colors.single(darken)):return failed("Invalid impact camera or color")
	if state.weapons.size()!=guns.size():return failed("Impact weapon population changed")
	var prepared:=[];var samplers:=[]
	for i in guns.size():
		var weapon: Dictionary=state.weapons[i]
		for key in ["key","item_id","kind","capacity","model_id","resource"]:
			if weapon.get(key)!=_descriptor.weapons[i][key]:return failed("Impact model identity changed")
		if weapon.slots.size()!=guns[i].slots.size():return failed("Impact slot population changed")
		var slots:=[];var slot_samplers:=[]
		for j in weapon.slots.size():
			var slot: Dictionary=weapon.slots[j];var initial: Dictionary=_descriptor.weapons[i].slots[j]
			if slot.get("start_ms")!=initial.start_ms or slot.get("end_ms")!=initial.end_ms or not Numbers.integer(slot.get("sample_time_ms"),initial.start_ms,initial.end_ms) or not slot.get("playing") is bool or not slot.get("position") is Vector3 or not slot.position.is_finite():return failed("Invalid impact animation slot")
			var sampler: RefCounted=_samplers[i][j].fork_for_frame()
			# Sampling at the retained time also preserves the final key of a
			# stopped effect, needed when this projectile slot is reused later.
			var animation: Dictionary=sampler.sample(int(slot.sample_time_ms),Transform3D.IDENTITY)
			if animation.is_empty():return failed(sampler.error)
			var surfaces:=[]
			if slot.playing:
				surfaces=_surface.prepare_surfaces(animation,Transform3D(camera.basis,slot.position),parent_rgba,global_tint)
				if surfaces.is_empty():return failed(_surface.error)
			slots.append({"visible":slot.playing,"surfaces":surfaces});slot_samplers.append(sampler)
		prepared.append(slots);samplers.append(slot_samplers)
	return {"guns":prepared,"samplers":samplers,"darken":Colors.single(darken) if _edition=="mac-full-hd" else 1.0}

func commit_world(prepared: Dictionary) -> void:
	for i in guns.size():
		for j in guns[i].slots.size():
			var model: Node3D=guns[i].slots[j];var row: Dictionary=prepared.guns[i][j]
			model.visible=row.visible
			if row.visible:_surface.apply_surfaces(model,row.surfaces,prepared.darken)
	_samplers=prepared.samplers

func clear() -> void:
	for child in get_children():child.free()
	guns=[];_samplers=[];_descriptor={};_identity=null;_edition="";_surface=null;error=""
func reject(message: String) -> bool:clear();error=message;return false
func failed(message: String) -> Dictionary:error=message;return {}
