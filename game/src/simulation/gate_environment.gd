extends RefCounted
## Station-seeded ordinary gate layout. This creates scenery, never travel
## permission or career progress. The flight transaction owns arrival.
const Definitions=preload("res://src/content/gate_environment_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
var error:=""
var _state:={}

func configure(bindings: RefCounted,catalogues: RefCounted,station_id: int) -> bool:
	error=""
	if not Definitions.available(bindings) or catalogues==null or catalogues.content_id!=bindings.base_content_id:return reject("Ordinary gates require matching source declarations and catalogues")
	if not Numbers.integer(station_id,0,catalogues.tables.stations.size()-1):return reject("Gate station is absent from the catalogue")
	var station: Dictionary=catalogues.tables.stations[station_id]
	var system: Dictionary=catalogues.tables.systems[station.system_id]
	var rules: Dictionary=bindings.mido_travel.gate_environment
	var type:=int(system.fields[int(rules.system_type_field)])
	var gate_station:=int(system.fields[int(rules.system_gate_station_field)])
	if not system.station_ids.has(station_id) or not Numbers.integer(type,0,rules.resources.size()-1):return reject("This location has no supported ordinary gate type")
	var random:=Random.new()
	random.seed_from(station_id*int(rules.seed_station_multiplier))
	var initial_random:=random.snapshot()
	var units:=int(rules.initial_angle_units)
	var objects:=[]
	for slot in rules.objects:
		if slot.gate_station_only and station_id!=gate_station:continue
		var sign_draw:=random.next_int(int(rules.sign_bound))
		var increment_draw:=random.next_int(int(rules.increment_bound))
		var increment: int=(increment_draw+int(rules.increment_offset))*int(rules.increment_multiplier)
		units+=-increment if sign_draw==int(rules.negative_sign_draw) else increment
		var angle:=single(single(units*float(rules.angle_fraction))*float(rules.angle_tau))
		var distance:=single(single(units*float(rules.radial_slope))+float(slot.radial_base))
		# A radial point rotated about Y. Round trigonometric values before the
		# products, as required by the source's single-precision world matrix.
		var origin:=Vector3(single(single(sin(angle))*distance),float(rules.height),single(single(cos(angle))*distance))
		var row: Array=rules.resources[type]
		var models:={}
		var ids: Array=row.duplicate();ids.append_array(rules.lod_mesh_ids[type])
		if type==int(rules.child_lod_type):ids.append_array(rules.child_lod_mesh_ids)
		for id in ids:
			var path: String=bindings.resolve(int(id),"mesh")
			if path.is_empty():return reject(bindings.error)
			models[int(id)]=path
		objects.append({"index":int(slot.index),"source_kind":int(rules.source_kind),"interactive":slot.interactive,
			"pose":Transform3D(Basis(Vector3.UP,float(rules.model_yaw)),origin),"angle_units":units,
			"angle":angle,"radial_distance":distance,"sign_draw":sign_draw,"increment_draw":increment_draw,
			"random_state":random.snapshot(),"mesh_id":int(row[0]),"child_mesh_ids":[int(row[1]),int(row[2])],
			"jump_mesh_id":int(row[3]),"lod_mesh_ids":rules.lod_mesh_ids[type].duplicate(),
			"lod_distances":rules.lod_distances.duplicate(),
			"child_lod_mesh_ids":rules.child_lod_mesh_ids.duplicate() if type==int(rules.child_lod_type) else [],
			"collision_radius":float(rules.collision_radii[type]) if slot.interactive else 0.0,"models":models})
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"station_id":station_id,
		"system_id":int(station.system_id),"gate_station_id":gate_station,"gate_type":type,
		"objects":objects,"initial_random":initial_random,"random_state":random.snapshot(),
		"arrival_object_index":int(rules.arrival_object_index)}
	return true

func arrival_position() -> Variant:
	if _state.is_empty():reject("Prepare ordinary gate scenery before local arrival");return null
	var entry:=object_state(_state.arrival_object_index)
	if entry.is_empty():reject("The incoming gate object is unavailable");return null
	return entry.pose.origin

func configure_void(bindings: RefCounted,environment: RefCounted) -> bool:
	error=""
	if not is_instance_of(environment,load("res://src/simulation/void_environment.gd")):return reject("Void gates require their native world environment")
	var world: Dictionary=environment.snapshot()
	for key in ["base_content_id","binding_id"]:
		if world.get(key)!=bindings.get(key):return reject("Void gate belongs to another source")
	var source: Dictionary=environment.object_state(2)
	if source.is_empty():return reject("Void entry has no incoming gate")
	var rules: Dictionary=bindings.mido_travel.gate_environment
	var ids: Array=source.model_ids
	var models: Dictionary=source.models
	for id in rules.lod_mesh_ids[0]:
		var path: String=bindings.resolve(int(id),"mesh")
		if path.is_empty():return reject(bindings.error)
		models[int(id)]=path
	var gate:={"index":2,"source_kind":int(rules.source_kind),"interactive":false,"pose":source.pose,
		"mesh_id":ids[0],"child_mesh_ids":[ids[1],ids[2]],"jump_mesh_id":ids[3],"models":models,
		"lod_mesh_ids":rules.lod_mesh_ids[0].duplicate(),"lod_distances":rules.lod_distances.duplicate(),
		"child_lod_mesh_ids":[],"collision_radius":0.0}
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"station_id":-1,"system_id":-1,
		"world_mode":"void","gate_type":0,"gate_station_id":-1,"objects":[gate],"arrival_object_index":2,
		"initial_random":world.initial_random,"random_state":world.random_state}
	return true

func object_state(index: int) -> Dictionary:
	for row in _state.get("objects",[]):
		if row.index==index:return row.duplicate(true)
	return {}

func snapshot() -> Dictionary:return _state.duplicate(true)

func fork() -> RefCounted:
	var result: RefCounted=get_script().new();result._state=_state.duplicate(true);return result

static func single(value: float) -> float:return PackedFloat32Array([value])[0]
func reject(message: String) -> bool:error=message;return false
