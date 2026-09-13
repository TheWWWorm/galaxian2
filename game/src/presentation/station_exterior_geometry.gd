extends Node3D
## Original station assembly using the mesh's existing engine axes. Additive lights
## retain their source initial sample until their playback clock is implemented.
const Resources=preload("res://src/content/station_exterior_resources.gd")
const Models=preload("res://src/presentation/model_resources.gd")
var error:=""
var station: Node3D
var layers: Array[Node3D]=[]
var _state:={}

func build(library: RefCounted, visuals: RefCounted, bindings: RefCounted, resources: RefCounted) -> bool:
	clear()
	if resources==null or resources.get_script()!=Resources or resources.snapshot().is_empty():return fail("Prepare the current station exterior before rendering it")
	var state: Dictionary=resources.snapshot()
	if state.base_content_id!=bindings.base_content_id or state.binding_id!=bindings.binding_id:return fail("Station geometry belongs to another content identity")
	var paths:=[]
	for layer in state.layers:paths.append(layer.path)
	var models:=Models.new()
	if not models.prepare(paths,library,visuals,bindings,"high",false,true):return fail(models.error)
	station=Node3D.new();station.name="StationExterior";station.transform=state.pose;add_child(station)
	station.set_meta("source_station_id",state.station_id)
	var axes:=Node3D.new();axes.name="SourceMeshAxes";axes.basis=state.mesh_axes;station.add_child(axes)
	for layer in state.layers:
		var model: Node3D=models.instantiate(layer.path)
		if model==null:
			var reason: String=models.error;models.clear();return fail(reason)
		model.set_meta("source_resource_id",layer.resource_id);axes.add_child(model);layers.append(model)
	models.clear();_state=state
	return true

func apply_state(state: Dictionary) -> bool:
	error=""
	if station==null or state!=_state:return reject("Station geometry changed its prepared identity, pose or resources")
	return true

func clear() -> void:
	for child in get_children():child.free()
	station=null;layers=[];_state={};error=""
func fail(message: String) -> bool:clear();error=message;return false
func reject(message: String) -> bool:error=message;return false
