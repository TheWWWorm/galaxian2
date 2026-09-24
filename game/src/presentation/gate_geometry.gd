extends Node3D
## Original gate assemblies, including their accepted native animation clocks.
## Flight owns contact, activation and arrival; LOD switching remains separate.
const Layout=preload("res://src/simulation/gate_environment.gd")
const Models=preload("res://src/presentation/model_resources.gd")
const GateAnimation=preload("res://src/simulation/gate_animation.gd")
const Transit=preload("res://src/content/gate_transit_definitions.gd")
const Sampler=preload("res://src/presentation/scenery_animation.gd")
const Additive=preload("res://src/presentation/animated_additive_model.gd")
var error:=""
var objects:={}
var _state:={}
var _animation_identity: RefCounted

func build(library: RefCounted,visuals: RefCounted,bindings: RefCounted,catalogues: RefCounted,state: Dictionary) -> bool:
	clear()
	var layout:=Layout.new()
	if not state.get("station_id") is int:return fail("Gate geometry requires a catalogue station")
	if not layout.configure(bindings,catalogues,state.station_id):return fail(layout.error)
	if state!=layout.snapshot():return fail("Gate rendering differs from its accepted ordinary environment")
	return build_layout(library,visuals,bindings,layout)

func build_layout(library: RefCounted,visuals: RefCounted,bindings: RefCounted,layout: RefCounted) -> bool:
	clear()
	if not layout is Layout:return fail("Gate geometry requires its native layout")
	var state: Dictionary=layout.snapshot()
	for key in ["base_content_id","binding_id"]:
		if state.get(key)!=bindings.get(key):return fail("Gate geometry belongs to another source")
	var paths:=[]
	for row in state.objects:
		paths.append(row.models[row.mesh_id])
		for id in row.child_mesh_ids:paths.append(row.models[id])
		if Transit.available(bindings):paths.append(row.models[row.jump_mesh_id])
	var models:=Models.new()
	if not models.prepare(paths,library,visuals,bindings,"high",false,true):return fail(models.error)
	for row in state.objects:
		var assembly:=Node3D.new();assembly.name="Gate%d"%row.index;assembly.transform=row.pose
		add_child(assembly)
		var ids: Array=[row.mesh_id];ids.append_array(row.child_mesh_ids)
		var layers:=[]
		for id in ids:
			var model: Node3D=models.instantiate(row.models[id])
			if model==null:
				var message: String=models.error;models.clear();return fail(message)
			model.set_meta("source_resource_id",id);assembly.add_child(model);layers.append(model)
		var animated:={}
		if Transit.available(bindings):
			var jump: Node3D=models.instantiate(row.models[row.jump_mesh_id])
			if jump==null:
				var message: String=models.error;models.clear();return fail(message)
			jump.set_meta("source_resource_id",row.jump_mesh_id);assembly.add_child(jump);jump.visible=false
			var all_layers: Array=layers.duplicate();all_layers.append(jump)
			for model in all_layers:
				var id: int=model.get_meta("source_resource_id")
				var sampler:=Sampler.new()
				if not sampler.configure(model.surfaces,true):models.clear();return fail(sampler.error)
				var material: Dictionary=bindings.material_for_mesh(row.models[id],"high")
				var adapter: RefCounted
				if material.get("render_type")==2:
					adapter=Additive.new()
					if not adapter.prepare_model(model):models.clear();return fail(adapter.error)
				else:
					for surface in model.surfaces:
						if surface.tracks.get("scalar",[]).any(func(track):return not track.keys.is_empty()):models.clear();return fail("Gate solid layer has unsupported color animation: "+row.models[id])
				animated[id]={"model":model,"sampler":sampler,"adapter":adapter}
		objects[row.index]={"assembly":assembly,"layers":layers,"animated":animated}
	models.clear();_state=state.duplicate(true)
	return true

func apply_state(state: Dictionary) -> bool:
	error=""
	return true if not _state.is_empty() and state==_state else reject("Gate geometry lost its accepted identity or layout")

func prepare_animation(owner: RefCounted) -> Dictionary:
	error=""
	if not owner is GateAnimation or _state.is_empty():reject("Gate rendering requires a prepared native animation");return {}
	var state: Dictionary=owner.snapshot()
	if state.get("layout")!=_state or owner.presentation_identity()==null or (_animation_identity!=null and owner.presentation_identity()!=_animation_identity):reject("Gate animation belongs to another environment");return {}
	var prepared:=[]
	for gate in state.objects:
		var instance: Dictionary=objects[gate.index]
		for index in gate.models.size():
			var clock: Dictionary=gate.models[index]
			if not instance.animated.has(clock.model_id):reject("Original animated gate layer is absent");return {}
			var row: Dictionary=instance.animated[clock.model_id]
			var sampler: RefCounted=row.sampler.fork_for_frame()
			var range: Dictionary=sampler.snapshot().range
			if range.start_ms!=clock.start_ms or range.end_ms!=clock.end_ms:reject("Gate playback differs from its original keys");return {}
			var sample: Dictionary=sampler.sample(clock.time_ms,Transform3D.IDENTITY)
			if sample.is_empty():reject(sampler.error);return {}
			var surfaces: Array=sample.surfaces
			if row.adapter!=null:
				surfaces=row.adapter.prepare_surfaces(sample,instance.assembly.global_transform,PackedByteArray([255,255,255,255]),Vector4.ONE)
				if surfaces.is_empty():reject(row.adapter.error);return {}
			prepared.append({"row":row,"sampler":sampler,"surfaces":surfaces,"visible":gate.active if index==3 else (not gate.active if index==2 else true)})
	return {"identity":owner.presentation_identity(),"layers":prepared}

func commit_animation(frame: Dictionary) -> void:
	for next in frame.layers:
		var row: Dictionary=next.row
		if row.adapter!=null:row.adapter.apply_surfaces(row.model,next.surfaces,1.0)
		else:
			for index in next.surfaces.size():row.model.instances[index].transform=next.surfaces[index].pose
		row.sampler=next.sampler;row.model.visible=next.visible
	_animation_identity=frame.identity

func apply_animation(owner: RefCounted) -> bool:
	var frame:=prepare_animation(owner)
	if frame.is_empty():return false
	commit_animation(frame);return true

func clear() -> void:
	for child in get_children():child.free()
	objects={};_state={};_animation_identity=null;error=""
func fail(message: String) -> bool:clear();error=message;return false
func reject(message: String) -> bool:error=message;return false
