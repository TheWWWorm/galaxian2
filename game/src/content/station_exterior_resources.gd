extends RefCounted
## Source-bound first mining station: model assembly bounds and authored volumes.
## This owner has no clock, random draws, damage, autopilot or arrival transition.
const Definitions=preload("res://src/content/station_exterior_definitions.gd")
const MiningFlight=preload("res://src/content/full_hold_flight_definitions.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Library=preload("res://src/content/library.gd")
const AEM=preload("res://src/content/aem.gd")
const Tracks=preload("res://src/content/animation_tracks.gd")
const Volumes=preload("res://src/content/station_collision_volumes.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
# V4 vertex/normal buffers already use engine axes. Only stored sphere centers
# need the authoring-to-engine conversion performed by the source sphere reader.
const MESH_AXES:=Basis.IDENTITY
const SPHERE_AXES:=Basis(Vector3.RIGHT,Vector3(0,0,-1),Vector3.UP)
var error:=""
var _state:={}

func configure(library: RefCounted, bindings: RefCounted, catalogues: RefCounted, construction: RefCounted) -> bool:
	error=""
	if library==null or bindings==null or catalogues==null or construction==null or construction.get_script()!=Construction or not Definitions.parameters(bindings.station_exterior):return reject("This pack has no supported mining station exterior")
	if not Library.valid_hash(bindings.base_content_id) or not Library.valid_hash(bindings.binding_id) or library.manifest.get("content_id")!=bindings.base_content_id or catalogues.content_id!=bindings.base_content_id:return reject("Station exterior resources belong to different content identities")
	var entry: Dictionary=construction.snapshot();var data: Dictionary=bindings.station_exterior
	if entry.get("base_content_id")!=bindings.base_content_id or entry.get("binding_id")!=bindings.binding_id or MiningFlight.flight(bindings,entry.get("campaign_cursor")).is_empty() or entry.get("location",{}).get("station_id")!=int(data.station_id) or entry.get("location",{}).get("system_id")!=int(data.system_id):return reject("Station exterior requires the supported mining location")
	var stations: Array=catalogues.tables.get("stations",[]);var systems: Array=catalogues.tables.get("systems",[])
	if stations.size()<=int(data.station_id) or systems.size()<=int(data.system_id):return reject("Station exterior is absent from the source catalogues")
	var station: Dictionary=stations[int(data.station_id)];var system: Dictionary=systems[int(data.system_id)]
	if station.system_id!=int(data.system_id) or system.fields.size()<=int(data.system_faction_field) or system.fields[int(data.system_faction_field)]!=int(data.faction):return reject("Station exterior faction differs from its source catalogue")
	var volume_reader:=Volumes.new()
	var bytes: PackedByteArray=library.read_resource(data.collision_resource,Volumes.MAX_BYTES)
	if bytes.is_empty():return reject(library.error)
	var collision:=volume_reader.decode(bytes,int(data.station_id),int(data.collision_record_limit))
	if collision.is_empty():return reject(volume_reader.error)
	var layers:=[];var sphere:=Vector4.ZERO
	for index in data.model_ids.size():
		var id:=int(data.model_ids[index]);var path: String=bindings.resolve(id,"mesh")
		if path.is_empty():return reject(bindings.error)
		var material: Dictionary=bindings.material_for_mesh(path,"high")
		if material.is_empty():return reject(bindings.error)
		if material.render_type!=int(data.render_types[index]):return reject("Unsupported station exterior material: "+path)
		var model_bytes: PackedByteArray=library.read_resource(path,AEM.MAX_BYTES)
		if model_bytes.is_empty():return reject(library.error)
		var reader:=AEM.new();var model:=reader.decode(model_bytes)
		if model.is_empty():return reject(reader.error)
		if model.version!=4 or model.surfaces.size()!=([1,1,2][index]):return reject("Unsupported station exterior mesh layout: "+path)
		var layer_sphere:=Vector4.ZERO
		for surface in model.surfaces:
			if not initial_transform_supported(surface,index==2):return reject("Unsupported station exterior transform or initial light sample: "+path)
			var raw: Vector4=surface.sphere
			if not raw.is_finite() or raw.w<=0:return reject("Invalid station exterior sphere: "+path)
			var center:=SPHERE_AXES*Vector3(raw.x,raw.y,raw.z)
			layer_sphere=merge_spheres(layer_sphere,Vector4(center.x,center.y,center.z,raw.w))
		sphere=merge_spheres(sphere,layer_sphere)
		layers.append({"resource_id":id,"path":path,"render_type":int(material.render_type),"sphere":layer_sphere})
	var extent:=f32(sphere.w+float(data.bounds_margin))
	if not sphere.is_finite() or not is_finite(extent) or extent<=0 or extent>=2147483647:return reject("Station exterior bounds exceed the supported range")
	var angles:=Vector3(data.rotation[0],data.rotation[1],data.rotation[2])
	var pose:=Transform3D(Vectors.local_xyz(angles).transposed(),Vector3(data.position[0],data.position[1],data.position[2]))
	# Commit only after all original records, models and material bindings agree.
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"station_id":int(data.station_id),"system_id":int(data.system_id),"name":station.name,"faction":int(data.faction),
		"pose":pose,"mesh_axes":MESH_AXES,"layers":layers,"sphere":sphere,"bounds_half_extent":int(extent),"collision":collision,
		"collision_resource":data.collision_resource,"collision_sha256":library.manifest.files[data.collision_resource].sha256,
		"light_animation_supported":false,"docking_transition_supported":false}
	return true

static func initial_transform_supported(surface: Dictionary, allow_light_scalar: bool) -> bool:
	var copy:=surface.duplicate(true)
	var scalar: Array=copy.tracks.get("scalar",[])
	if allow_light_scalar:
		if scalar.size()!=1 or scalar[0].dimensions!=1 or scalar[0].keys.size()<2 or scalar[0].keys[0]!=0 or scalar[0].keys[1]!=100:return false
		copy.tracks.scalar=[]
	return Tracks.has_identity_tracks([copy])

static func merge_spheres(current: Vector4, incoming: Vector4) -> Vector4:
	if incoming.w==0:return current
	if current.w==0:return incoming
	var center:=Vector3(current.x,current.y,current.z)
	var delta:=Vector3(incoming.x,incoming.y,incoming.z)-center
	var distance:=f32(sqrt(Vectors.dot(delta,delta)))
	if distance==0:return Vector4(center.x,center.y,center.z,maxf(current.w,incoming.w))
	if f32(distance+incoming.w)<current.w:return current
	if -current.w>f32(distance-incoming.w):return incoming
	var shift:=f32(f32(0.5*f32(f32(incoming.w+distance)-current.w))/distance)
	center=Vectors.added(center,Vectors.scaled(delta,shift))
	return Vector4(center.x,center.y,center.z,f32(f32(f32(current.w+distance)+incoming.w)*0.5))

func point_volume(point: Vector3) -> int:
	if _state.is_empty() or not Volumes.contains_point(point,_state.pose.origin,Vector3.ONE*float(_state.bounds_half_extent)):return -1
	for i in _state.collision.boxes.size():
		var box: Dictionary=_state.collision.boxes[i]
		if Volumes.contains_point(point,box.center+_state.pose.origin,box.half_extents):return i
	return -1

func snapshot() -> Dictionary:return _state.duplicate(true)
func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new();copy._state=_state.duplicate(true);return copy
func clear() -> void:_state={};error=""
static func f32(value: float) -> float:return PackedFloat32Array([value])[0]
func reject(message: String) -> bool:error=message;return false
