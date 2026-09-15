extends Node3D
## Original animated wreck and salvage. Build after native death entry, when
## source debris has been sampled. Mesh resources can be shared across actors.
const Death=preload("res://src/simulation/freighter_destruction.gd")
const Resources=preload("res://src/content/freighter_destruction_resources.gd")
const Models=preload("res://src/presentation/model_resources.gd")
const Sampler=preload("res://src/presentation/scenery_animation.gd")
const Effects=preload("res://src/presentation/npc_death_effect_geometry.gd")
const Materials=preload("res://src/presentation/material_library.gd")
var error:=""
var body: Node3D
var cargo: Node3D
var effect: Node3D
var _identity: RefCounted
var _sampler: RefCounted
var _materials:={}
var _descriptor:={}

func build(library: RefCounted,visuals: RefCounted,bindings: RefCounted,resources: RefCounted,death: RefCounted,shared_models: RefCounted=null) -> bool:
	clear()
	if library==null or visuals==null or bindings==null:return reject("Freighter presentation requires its content libraries")
	if not resources is Resources or not death is Death or death.presentation_identity()==null:return reject("Freighter presentation requires its configured native lifecycle")
	var state: Dictionary=death.snapshot();var pack: Dictionary=resources.snapshot()
	if state.get("phase") not in ["animation","wreck"]:return reject("Construct freighter destruction geometry after its lethal entry")
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if state.get(key)!=pack.get(key):return reject("Freighter geometry resources belong to another lifecycle")
	var paths: Array=[pack.model.resource,pack.cargo_model.resource]
	for model in pack.models:paths.append(model.resource)
	var models: RefCounted=shared_models;var owns:=models==null
	if owns:
		models=Models.new()
		if not models.prepare(paths,library,visuals,bindings):return reject(models.error)
	elif not models is Models or not models.covers(paths,bindings,"high",false):return reject("Freighter geometry requires matching shared resources")
	body=models.instantiate(pack.model.resource);cargo=models.instantiate(pack.cargo_model.resource)
	if body==null or cargo==null:
		if owns:models.clear()
		return reject("Freighter model preparation failed")
	add_child(body);add_child(cargo)
	_sampler=Sampler.new()
	if not _sampler.configure(body.surfaces):
		if owns:models.clear()
		return reject(_sampler.error)
	var range: Dictionary=_sampler.snapshot().range
	if range.start_ms!=state.animation.start_ms or range.end_ms!=state.animation.end_ms:
		if owns:models.clear()
		return reject("Freighter animation changed after staging")
	var descriptor: Dictionary=pack.wreck_material
	var diffuse: Image=visuals.load_image(descriptor.texture_paths[0])
	var normal: Image=visuals.load_image(descriptor.texture_paths[1])
	if diffuse==null or normal==null:
		if owns:models.clear()
		return reject("Freighter original wreck textures are unavailable")
	var textures:=[ImageTexture.create_from_image(diffuse),ImageTexture.create_from_image(normal)]
	var wreck_materials: Array[ShaderMaterial]=[]
	for i in body.surfaces.size():
		body.instances[i].top_level=true
		wreck_materials.append(Materials.create(28,textures[0],textures[1],not body.surfaces[i].colors.is_empty()))
	_materials[int(pack.initial_material.id)]=body.materials.duplicate()
	_materials[int(pack.wreck_material.id)]=wreck_materials
	effect=Effects.new();add_child(effect)
	if not effect.build(library,visuals,bindings,death,"high",models):
		var message: String=effect.error
		if owns:models.clear()
		return reject(message)
	if owns:models.clear()
	_identity=death.presentation_identity();_descriptor=state.duplicate(true)
	visible=false
	return true

func apply_state(death: RefCounted,camera: Transform3D) -> bool:
	var frame:=prepare_state(death,camera)
	if frame.is_empty():return false
	commit_state(frame)
	return true

func is_built() -> bool:return _identity!=null

func prepare_state(death: RefCounted,camera: Transform3D) -> Dictionary:
	error=""
	if _identity==null or not death is Death or death.presentation_identity()!=_identity:return failed_state("Freighter geometry follows one native lifecycle")
	var state: Dictionary=death.snapshot()
	if not _materials.has(state.get("material_id")) or state.get("phase") not in ["animation","wreck"]:return failed_state("Unsupported freighter presentation state")
	for key in ["base_content_id","binding_id","campaign_cursor","actor_id","fragments"]:
		if state.get(key)!=_descriptor[key]:return failed_state("Freighter presentation identity changed")
	var sampler: RefCounted=_sampler.fork_for_frame()
	var pose: Transform3D=state.pose
	pose.basis=pose.basis.scaled(Vector3.ONE*float(state.get("model_scale",1.0)))
	var animated: Dictionary=sampler.sample(state.animation.time_ms,pose)
	if animated.is_empty():return failed_state(sampler.error)
	var candidate: Dictionary=effect.prepare_effect(death,camera,PackedByteArray([255,255,255,255]),Vector4.ONE,1.0)
	if candidate.is_empty():return failed_state(effect.error)
	return {"animated":animated,"sampler":sampler,"effect":candidate,"material_id":state.material_id,"cargo":state.cargo.duplicate(true)}

func commit_state(frame: Dictionary) -> void:
	var selected: Array=_materials[frame.material_id]
	for i in body.instances.size():
		body.instances[i].transform=frame.animated.surfaces[i].pose
		body.instances[i].material_override=selected[i]
	body.materials.assign(selected)
	cargo.visible=frame.cargo.model_exists;cargo.transform=frame.cargo.pose
	effect.commit_effect(frame.effect);_sampler=frame.sampler
	visible=true

func failed_state(message: String) -> Dictionary:error=message;return {}

func clear() -> void:
	for node in [body,cargo,effect]:
		if is_instance_valid(node):node.free()
	body=null;cargo=null;effect=null;_identity=null;_sampler=null;_materials={};_descriptor={};visible=false;error=""
func reject(message: String) -> bool:clear();error=message;return false
func failed_frame(message: String) -> bool:error=message;return false
