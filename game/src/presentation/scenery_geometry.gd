extends Node3D
## Initial source scenery geometry. Shared meshes/textures keep field population
## inexpensive. LOD selection and motion arrive from native scene owners.
const Resources = preload("res://src/presentation/model_resources.gd")
const Definitions = preload("res://src/content/scenery_resource_definitions.gd")
const DestructionGeometry = preload("res://src/presentation/scenery_destruction_geometry.gd")
const Response = preload("res://src/presentation/surface_response.gd")
var error := ""
var objects: Array[Node3D] = []
var _identity := {}
var _levels: Array = []
var destruction: Node3D

func prepare_destruction(field: Dictionary, library: RefCounted, visuals: RefCounted, bindings: RefCounted, resources: RefCounted, lighting: Dictionary, reflection: RefCounted, response: Dictionary, quality := "high") -> bool:
	if _identity.is_empty():return reject("Build intact scenery before preparing destruction")
	if bindings==null or bindings.base_content_id!=_identity.base_content_id or bindings.binding_id!=_identity.binding_id or field.get("objects",[]).size()!=objects.size():
		return reject("Destruction preparation belongs to another intact field")
	for index in objects.size():
		if field.objects[index].get("model_id")!=objects[index].get_meta("source_resource_id"):return reject("Destruction preparation model differs from the intact field")
	var candidate := DestructionGeometry.new()
	if not candidate.build(field,library,visuals,bindings,resources,lighting,reflection,response,quality):
		var message := candidate.error;candidate.free();return reject(message)
	var models := []
	for levels in _levels:models.append_array(levels)
	var adapter := Response.new()
	var materials := adapter.prepare_models(models,bindings.surface_material,lighting,reflection.texture,response.diffuse_bias,response.normal_bias,"two_light_cube")
	if materials.is_empty():
		var message := adapter.error;candidate.free();return reject(message)
	Response.commit_models(materials)
	if destruction!=null:destruction.free()
	destruction=candidate;add_child(destruction)
	return true

func apply_destruction(world: RefCounted, camera: Transform3D, parent_rgba: PackedByteArray, global_tint: Vector4, darken: Variant) -> bool:
	if destruction==null:return reject("Prepare scenery destruction before presenting it")
	if not destruction.apply_world(world,camera,parent_rgba,global_tint,darken):return reject(destruction.error)
	for index in objects.size():objects[index].visible=destruction.intact[index]
	return true

func build(field: Dictionary, library: RefCounted, visuals: RefCounted, bindings: RefCounted, quality := "high", with_detail := false) -> bool:
	clear()
	if library==null or visuals==null or bindings==null or not Definitions.parameters(bindings.scenery_resources):return reject("Scenery geometry requires source resource declarations")
	if field.get("base_content_id")!=bindings.base_content_id or field.get("binding_id")!=bindings.binding_id:return reject("Scenery geometry belongs to another content identity")
	var rows: Variant = field.get("objects")
	if not rows is Array or rows.size()>8192:return reject("Invalid scenery object list")
	var paths := [];var poses := [];var model_paths := []
	for index in rows.size():
		var row: Variant = rows[index]
		if not row is Dictionary or row.get("index")!=index or not row.get("model_variant") is int or row.model_variant<0 or row.model_variant>=4:return reject("Invalid scenery model alternative")
		if not row.get("model_id") is int or row.model_id!=int(bindings.scenery_resources.model_ids[row.model_variant]):return reject("Scenery model is not bound to its source alternative")
		if not row.get("position") is Vector3 or not row.position.is_finite() or not row.get("basis") is Basis or not row.basis.is_finite() or not row.basis.is_equal_approx(row.basis.orthonormalized()) or row.basis.determinant()<=0.0:return reject("Invalid scenery source pose")
		if not row.get("scale") is float or not is_finite(row.scale) or row.scale<=0.0 or row.scale>10.0:return reject("Invalid scenery source scale")
		var levels := []
		for level in (4 if with_detail else 1):
			var path: String = bindings.resolve(row.model_id+level,"mesh")
			if path.is_empty():return reject(bindings.error)
			paths.append(path);levels.append(path)
		model_paths.append(levels);poses.append(Transform3D(row.basis.scaled(Vector3.ONE*row.scale),row.position))
	var resources := Resources.new()
	if not resources.prepare(paths,library,visuals,bindings,quality,true):return reject(resources.error)
	var staged: Array[Node3D] = []
	for index in rows.size():
		var body: Node3D = resources.instantiate(model_paths[index][0])
		if body==null:
			for node in staged:node.free()
			_levels.clear();var message: String = resources.error;resources.clear();return reject(message)
		body.name="Scenery%d" % index;body.transform=poses[index]
		body.set_meta("source_resource_id",rows[index].model_id)
		body.set_meta("source_item_id",rows[index].get("item_id",-1))
		staged.append(body)
		var levels := [body]
		for level in range(1,model_paths[index].size()):
			var alternate: Node3D = resources.instantiate(model_paths[index][level])
			if alternate==null:
				for node in staged:node.free()
				_levels.clear();var message: String = resources.error;resources.clear();return reject(message)
			alternate.name="Level%d" % level;alternate.visible=false
			alternate.set_meta("source_resource_id",rows[index].model_id+level)
			body.add_child(alternate);levels.append(alternate)
		_levels.append(levels)
	resources.clear()
	for body in staged:add_child(body)
	objects=staged
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	return true

func apply_state(field: Dictionary) -> bool:
	error=""
	if _identity.is_empty() or field.get("base_content_id")!=_identity.base_content_id or field.get("binding_id")!=_identity.binding_id:return reject("Scenery pose belongs to another content identity")
	var rows: Variant = field.get("objects")
	if not rows is Array or rows.size()!=objects.size():return reject("Scenery pose count changed")
	var poses: Array[Transform3D] = []
	for index in rows.size():
		var row: Variant = rows[index]
		if not row is Dictionary or row.get("index")!=index or row.get("model_id")!=objects[index].get_meta("source_resource_id"):return reject("Scenery pose model changed")
		if not row.get("position") is Vector3 or not row.position.is_finite() or not row.get("basis") is Basis or not row.basis.is_finite() or not row.basis.is_equal_approx(row.basis.orthonormalized()) or row.basis.determinant()<=0.0:return reject("Invalid scenery source pose")
		if not row.get("scale") is float or not is_finite(row.scale) or row.scale<=0.0 or row.scale>10.0:return reject("Invalid scenery source scale")
		poses.append(Transform3D(row.basis.scaled(Vector3.ONE*row.scale),row.position))
	for index in poses.size():objects[index].transform=poses[index]
	return true

func apply_detail(state: Dictionary) -> bool:
	error=""
	if _identity.is_empty() or state.get("base_content_id")!=_identity.base_content_id or state.get("binding_id")!=_identity.binding_id:return reject("Scenery detail belongs to another content identity")
	var selections: Variant = state.get("selections")
	if not selections is Dictionary or selections.size()!=objects.size():return reject("Scenery detail count changed")
	for index in objects.size():
		var selection: Variant = selections.get(index)
		if not selection is Dictionary or selection.get("visible")!=true or not selection.get("level") is int or selection.level<0 or selection.level>=_levels[index].size():return reject("Invalid scenery detail selection")
	for index in objects.size():
		var selected: int = selections[index].level
		# The base ImportedModel is also the transform owner of its LOD children.
		# Hide its surfaces, not their common ancestor, when an alternate is active.
		for instance in objects[index].instances:instance.visible=selected==0
		for level in range(1,_levels[index].size()):_levels[index][level].visible=selected==level
	return true

func apply_activity(bodies: Dictionary) -> bool:
	error=""
	if _identity.is_empty() or bodies.get("base_content_id")!=_identity.base_content_id or bodies.get("binding_id")!=_identity.binding_id:return reject("Scenery activity belongs to another content identity")
	var rows: Variant=bodies.get("objects")
	if not rows is Array or rows.size()!=objects.size():return reject("Scenery activity count changed")
	for index in rows.size():
		var row: Variant=rows[index]
		if not row is Dictionary or row.get("index")!=index or row.get("model_id")!=objects[index].get_meta("source_resource_id") or not row.get("active") is bool:return reject("Invalid scenery body activity")
	# Hide the common ancestor so a later LOD refresh cannot reveal a mined body.
	for index in objects.size():objects[index].visible=rows[index].active
	return true

func clear() -> void:
	for child in get_children():child.free()
	objects.clear();_levels.clear();_identity={};destruction=null;error=""

func reject(message: String) -> bool:
	error=message;return false
