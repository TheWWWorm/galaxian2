extends Node3D
## Native assembly of source-selected geometry; cameras/lights/game state separate.
const Resources = preload("res://src/presentation/model_resources.gd")
var error := ""
var instances: Array[MeshInstance3D] = []
var surfaces: Array = []
var models: Array[Node3D] = []
var source_bounds := AABB()
var definition := {}
var ship_model: Node3D
var ship_instances: Array[MeshInstance3D] = []
var ship_light_models: Array[Node3D] = []

func build(selected: Dictionary, library: RefCounted, visuals: RefCounted, bindings: RefCounted, quality := "high") -> bool:
	clear()
	error = ""
	var paths := {}
	for layer in selected.get("layers", []):
		paths[layer.path] = true
		for child in layer.children:
			paths[child.path] = true
	if selected.has("ship"):
		paths[selected.ship.path] = true
		for light in selected.ship.get("lights", []):
			paths[light.path] = true
	if paths.is_empty():
		return fail("No supported hangar geometry was selected")
	var resources := Resources.new()
	if not resources.prepare(paths.keys(), library, visuals, bindings, quality):
		return fail(resources.error)
	for layer in selected.layers:
		var parent := add_model(resources, layer.path, self)
		parent.set_meta("source_resource_id", layer.resource_id)
		parent.rotation.y = selected.rotation_y
		# The supported source factory appends these transforms to each
		# root layer. Preserve that hierarchy; render-pass parity is unverified.
		for child in layer.children:
			add_model(resources, child.path, parent).set_meta("source_resource_id", child.resource_id)
	definition = selected.duplicate(true)
	if selected.has("ship"):
		ship_model = add_model(resources, selected.ship.path, self)
		ship_model.set_meta("source_resource_id", selected.ship.resource_id)
		ship_model.set_meta("source_ship_id", selected.ship.ship_id)
		ship_model.position = selected.ship.position
		ship_instances.append_array(ship_model.instances)
		for light in selected.ship.get("lights", []):
			var light_model := add_model(resources, light.path, ship_model)
			light_model.set_meta("source_resource_id", light.resource_id)
			light_model.set_meta("source_light_slot", light.slot)
			ship_instances.append_array(light_model.instances)
			ship_light_models.append(light_model)
	var first := true
	for instance in instances:
		var transform_value := Transform3D.IDENTITY
		var node: Node3D = instance
		while node != self:
			transform_value = node.transform * transform_value
			node = node.get_parent()
		var bounds: AABB = transform_value * instance.mesh.get_aabb()
		source_bounds = bounds if first else source_bounds.merge(bounds)
		first = false
	resources.clear()
	return error.is_empty()

func add_model(resources: RefCounted, path: String, parent: Node3D) -> Node3D:
	var model: Node3D = resources.instantiate(path)
	parent.add_child(model)
	models.append(model)
	instances.append_array(model.instances)
	surfaces.append_array(model.surfaces)
	return model

func set_source_time(value: float) -> void:
	for model in models:
		model.set_source_time(value)

func clear() -> void:
	for child in get_children():
		child.free()
	instances.clear()
	models.clear()
	surfaces.clear()
	definition.clear()
	ship_model = null
	ship_instances.clear()
	ship_light_models.clear()
	source_bounds = AABB()

func fail(message: String) -> bool:
	error = message
	return false
