extends Node3D
## Original scenery at the first Void visit. Travel and contact remain simulation
## concerns; this renderer cannot select a destination or grant mission progress.
const VoidEnvironment=preload("res://src/simulation/void_environment.gd")
const GateLayout=preload("res://src/simulation/gate_environment.gd")
const GateGeometry=preload("res://src/presentation/gate_geometry.gd")
const GateClock=preload("res://src/simulation/gate_animation.gd")
const Models=preload("res://src/presentation/model_resources.gd")
const SkyLayers=preload("res://src/presentation/opening_sky.gd")
var error:=""
var station: Node3D
var gates: Node3D
var sky: Node3D
var _clock: RefCounted

func build(library: RefCounted,visuals: RefCounted,bindings: RefCounted,environment: RefCounted,animation: RefCounted=null) -> bool:
	clear()
	if not environment is VoidEnvironment:return reject("Void rendering requires its generated native world")
	var state: Dictionary=environment.snapshot()
	for key in ["base_content_id","binding_id"]:
		if state.get(key)!=bindings.get(key):return reject("Void world belongs to another source")
	var layout:=GateLayout.new()
	if not layout.configure_void(bindings,environment):return reject(layout.error)
	var clock: RefCounted=animation
	if clock==null:
		clock=GateClock.new()
		if not clock.configure_layout(bindings,library,layout):return reject(clock.error)
	elif not clock is GateClock or clock.snapshot().layout!=layout.snapshot():return reject("Void gate animation belongs to another environment")
	var gate_node:=GateGeometry.new();add_child(gate_node);gates=gate_node
	if not gate_node.build_layout(library,visuals,bindings,layout):return reject(gate_node.error)
	var sky_node:=SkyLayers.new();add_child(sky_node);sky=sky_node
	if not sky_node.build_void(library,visuals,bindings,environment):return reject(sky_node.error)
	var source: Dictionary=environment.object_state(0)
	var models:=Models.new()
	if not models.prepare(source.models.values(),library,visuals,bindings,"high",false,true):return reject(models.error)
	station=Node3D.new();station.name="VoidStation";station.transform=source.pose;add_child(station)
	for id in source.model_ids:
		var instance: Node3D=models.instantiate(source.models[id])
		if instance==null:models.clear();return reject(models.error)
		instance.set_meta("source_resource_id",id);station.add_child(instance)
	models.clear();_clock=clock
	return gates.apply_animation(_clock)

func advance(milliseconds: int,view: Dictionary) -> bool:
	error=""
	if _clock==null:return reject("Prepare Void scenery before animation")
	if not _clock.advance(milliseconds):return reject(_clock.error)
	if not gates.apply_animation(_clock):return reject(gates.error)
	if not sky.apply_view(view):return reject(sky.error)
	return true

func clear() -> void:
	for child in get_children():child.free()
	station=null;gates=null;sky=null;_clock=null;error=""

func reject(message: String) -> bool:error=message;return false
