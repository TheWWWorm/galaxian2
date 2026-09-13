extends Node3D
## Field presentation: share decoded resources, instantiate effects on demand,
## and retain actor-owned junk after the breakup finishes. No collection/reward.
const World = preload("res://src/simulation/opening_scenery.gd")
const Models = preload("res://src/presentation/model_resources.gd")
const Effect = preload("res://src/presentation/scenery_effect_geometry.gd")
const Lifecycle = preload("res://src/simulation/scenery_destruction.gd")
const Tracks = preload("res://src/content/animation_tracks.gd")
const Response = preload("res://src/presentation/surface_response.gd")
var error := ""
var intact: Array = []
var _models: RefCounted
var _descriptors := {}
var _effects := {}
var _cargo := {}
var _cargo_materials := {}
var _identity := {}
var _model_ids := []
var _library: RefCounted
var _visuals: RefCounted
var _bindings: RefCounted
var _reflection: RefCounted
var _lighting := {}
var _response := {}
var _quality := ""
var _world_identity: RefCounted

func build(field: Dictionary, library: RefCounted, visuals: RefCounted, bindings: RefCounted, resources: RefCounted, lighting: Dictionary, reflection: RefCounted, response: Dictionary, quality := "high") -> bool:
	clear()
	if resources==null or bindings==null or library==null or visuals==null or field.get("base_content_id")!=bindings.base_content_id or field.get("binding_id")!=bindings.binding_id:
		return reject("Destruction geometry requires matching field resources")
	if not field.get("destruction") is Array or field.destruction.size()!=field.get("objects",[]).size():
		return reject("Destruction geometry requires a field lifecycle owner")
	var paths := Lifecycle.CargoPaths.duplicate()
	for row in field.objects:
		var descriptor: Dictionary=resources.effect_for_model(row.model_id)
		if descriptor.is_empty():return reject(resources.error)
		_descriptors[row.model_id]=descriptor
		_model_ids.append(row.model_id)
		for model in descriptor.models:paths.append(model.resource)
	_models=Models.new()
	if not _models.prepare(paths,library,visuals,bindings,quality,false,true):return reject(_models.error)
	# Verify every model/material variant during scene loading, then discard its
	# nodes. Runtime instances reuse these prepared meshes and textures.
	for descriptor in _descriptors.values():
		var probe := Effect.new()
		var ready := probe.build(library,visuals,bindings,descriptor,lighting,reflection,response,quality,_models)
		var message := probe.error;probe.free()
		if not ready:return reject(message)
	for path in Lifecycle.CargoPaths:
		var probe: Node3D=_models.instantiate(path)
		var supported := probe!=null and Tracks.has_identity_tracks(probe.surfaces)
		if not supported:
			if probe!=null:probe.free()
			return reject("Scenery cargo requires a static source model")
		var adapter := Response.new()
		var materials := adapter.prepare_models([probe],bindings.surface_material,lighting,reflection.texture,response.diffuse_bias,response.normal_bias,"two_light_cube")
		if materials.size()!=probe.materials.size():
			probe.free();return reject("Scenery cargo requires complete opaque surface materials: "+adapter.error)
		_cargo_materials[path]=[]
		for row in materials:_cargo_materials[path].append(row.material)
		probe.free()
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_library=library;_visuals=visuals;_bindings=bindings;_reflection=reflection
	_lighting=lighting.duplicate(true);_response=response.duplicate(true);_quality=quality
	intact.resize(_model_ids.size());intact.fill(true)
	return true

func apply_world(world: RefCounted, camera: Transform3D, parent_rgba: PackedByteArray, global_tint: Vector4, darken: Variant) -> bool:
	error=""
	if _identity.is_empty() or world==null or world.get_script()!=World:return fail("Destruction presentation requires its native world owner")
	if world.presentation_identity()==null or (_world_identity!=null and world.presentation_identity()!=_world_identity):return fail("Destruction presentation follows one logical world")
	if not camera.is_finite() or Effect.tint(parent_rgba,global_tint).is_empty() or not (darken is float or darken is int) or not is_finite(darken) or not is_finite(Effect.single(darken)):
		return fail("Invalid world destruction presentation inputs")
	var field: Dictionary=world.snapshot()
	for key in _identity:
		if field.get(key)!=_identity[key]:return fail("Destruction presentation belongs to another field")
	if field.get("objects",[]).size()!=_model_ids.size() or field.get("destruction",[]).size()!=_model_ids.size():return fail("Destruction presentation field size changed")
	var staged := [];var created := [];var next_intact := []
	for index in _model_ids.size():
		var row: Dictionary=field.destruction[index]
		if row.object_index!=index or field.objects[index].model_id!=_model_ids[index]:return abort_frame(created,"Destruction presentation actor changed")
		var state: Dictionary=row.lifecycle
		next_intact.append(state.actor_state==0)
		var effect: Node3D=_effects.get(index)
		var prepared := {}
		if state.actor_state==3:
			if effect==null:
				effect=Effect.new();created.append(effect)
				if not effect.build(_library,_visuals,_bindings,_descriptors[_model_ids[index]],_lighting,_reflection,_response,_quality,_models):return abort_frame(created,effect.error)
			prepared=effect.prepare_effect(world.presentation_clock(index),camera,parent_rgba,global_tint,darken)
			if prepared.is_empty():return abort_frame(created,effect.error)
		var cargo: Node3D=_cargo.get(index)
		if not state.cargo.is_empty():
			if cargo==null:
				cargo=_models.instantiate(state.cargo.resource)
				if cargo==null:return abort_frame(created,_models.error)
				created.append(cargo);cargo.name="Cargo%d" % index
				for surface in cargo.materials.size():
					cargo.materials[surface]=_cargo_materials[state.cargo.resource][surface]
					cargo.instances[surface].material_override=cargo.materials[surface]
				cargo.transform=state.cargo.pose
				cargo.set_meta("source_item_id",state.cargo.item_id)
				cargo.set_meta("source_quantity",state.cargo.quantity)
				cargo.set_meta("source_resource_id",state.cargo.model_id)
		staged.append({"effect":effect,"prepared":prepared,"cargo":cargo})
	# All samplers and resources succeeded. No earlier actor is changed if a
	# later actor fails; discarded candidates never become visible scene nodes.
	for index in staged.size():
		var row: Dictionary=staged[index]
		if row.prepared.is_empty():
			if _effects.has(index):_effects[index].free();_effects.erase(index)
		else:
			if row.effect.get_parent()==null:add_child(row.effect)
			row.effect.commit_effect(row.prepared);_effects[index]=row.effect
		if row.cargo!=null:
			if row.cargo.get_parent()==null:add_child(row.cargo)
			_cargo[index]=row.cargo
	intact=next_intact
	_world_identity=world.presentation_identity()
	return true

func abort_frame(created: Array, message: String) -> bool:
	for node in created:node.free()
	return fail(message)

func clear() -> void:
	for child in get_children():child.free()
	if _models!=null:_models.clear()
	_models=null;_effects={};_cargo={};_cargo_materials={};_descriptors={};_identity={};_model_ids=[];intact=[]
	_library=null;_visuals=null;_bindings=null;_reflection=null;_lighting={};_response={};_quality="";error=""
	_world_identity=null

func _notification(what: int) -> void:
	if what==NOTIFICATION_PREDELETE and _models!=null:_models.clear()

func reject(message: String) -> bool:
	clear();return fail(message)

func fail(message: String) -> bool:
	error=message;return false
