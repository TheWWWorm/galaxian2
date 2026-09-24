extends RefCounted
## Source physical player contacts. Static imported policy and geometry are
## configured once; each frame supplies one live player/body observation.
## Applying pose, impact, damage and destruction remains with their owners.
const Definitions=preload("res://src/content/physical_scenery_contact_definitions.gd")
const Library=preload("res://src/content/library.gd")
const Volumes=preload("res://src/content/station_collision_volumes.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
var error:=""
var _identity:={}
var _policy:={}
var _station_center:=Vector3.ZERO
var _station_half:=0
var _station_shapes:=[]
var _body_geometry:=[]

func configure(policy: Variant, identity: Variant, station: Variant, bodies: Variant) -> bool:
	clear()
	if not Definitions.parameters(policy):return reject("Physical contacts require source declarations")
	if not identity is Dictionary or not Library.valid_hash(identity.get("base_content_id")) or not Library.valid_hash(identity.get("binding_id")):return reject("Physical contacts require one content identity")
	if not station is Dictionary or not bodies is Dictionary:return reject("Physical contacts require prepared scenery observations")
	for state in [station,bodies]:
		if not state.is_empty() and (state.get("base_content_id")!=identity.base_content_id or state.get("binding_id")!=identity.binding_id):return reject("Physical scenery contact identities differ")
	if not station.is_empty():
		if not station.get("pose") is Transform3D or not station.pose.is_finite() or not station.get("bounds_half_extent") is int or station.bounds_half_extent<=0 or not station.get("collision") is Dictionary:return reject("Station contact requires prepared authored volumes")
		var shapes: Variant=station.collision.get("shapes",station.collision.get("boxes",[]))
		if not shapes is Array or shapes.is_empty() or shapes.size()>4096:return reject("Station contact volumes are invalid")
		for shape in shapes:
			if not valid_shape(shape):return reject("Station contact shape is invalid")
		_station_center=station.pose.origin;_station_half=int(station.bounds_half_extent)
		_station_shapes=shapes.duplicate(true)
	if not bodies.is_empty():
		if not bodies.get("objects") is Array or bodies.objects.size()>8192:return reject("Physical scenery body observation is invalid")
		for index in bodies.objects.size():
			var body: Variant=bodies.objects[index]
			if not body is Dictionary or body.get("index")!=index or not body.get("position") is Vector3 or not body.position.is_finite() or not body.get("half_extent") is int or body.half_extent<0:return reject("Physical scenery body geometry is invalid")
			_body_geometry.append({"position":body.position,"half_extent":body.half_extent})
	_identity=identity.duplicate(true);_policy=policy.duplicate(true)
	return true

func plan(player: Variant, bodies: Variant, collision_enabled: Variant, selected_mining_index: Variant=-1) -> Dictionary:
	error=""
	if _identity.is_empty():return fail("Physical contacts are not configured")
	if not player is Dictionary or player.get("base_content_id")!=_identity.base_content_id or player.get("binding_id")!=_identity.binding_id or not player.get("center") is Vector3 or not player.center.is_finite() or not player.get("eligible") is bool:return fail("Physical contacts require one finite player observation")
	if not collision_enabled is bool or not selected_mining_index is int or selected_mining_index< -1 or selected_mining_index>=_body_geometry.size():return fail("Physical contacts require explicit collision and mining gates")
	if not bodies is Dictionary:return fail("Physical contacts require one body observation")
	var live: Array=[]
	if not bodies.is_empty():
		if bodies.get("base_content_id")!=_identity.base_content_id or bodies.get("binding_id")!=_identity.binding_id or not bodies.get("objects") is Array or bodies.objects.size()!=_body_geometry.size():return fail("Physical scenery body observation changed identity or extent")
		live=bodies.objects
	elif not _body_geometry.is_empty():return fail("Physical scenery body observation is missing")
	var current: Vector3=player.center
	var result:={"center_before":current,"center_after":current,"operations":[]}
	if not collision_enabled or not player.eligible:return result
	if not _station_shapes.is_empty() and Volumes.contains_point(current,_station_center,Vector3.ONE*float(_station_half)):
		var volume_index:=first_station_volume(current,_station_center,_station_shapes)
		if volume_index>=0:
			var before:=current
			for pass_index in int(_policy.station_projection_passes):
				for shape in _station_shapes:
					current=project_shape(current,_station_center,shape)
					if not current.is_finite():return fail("Station contact projection exceeds source precision")
			result.operations.append({"kind":"station","station_slot":int(_policy.station_slot),"authored_volume_index":volume_index,"center_before":before,"center_after":current,"damage":int(_policy.station_damage)})
			result.center_after=current
	for index in live.size():
		if index==selected_mining_index:continue
		var body: Dictionary=live[index]
		if not body.active or not body.collision_enabled or int(body.vitals.hull)<=0:continue
		var geometry: Dictionary=_body_geometry[index]
		if not Volumes.contains_point(current,geometry.position,Vector3.ONE*float(geometry.half_extent)):continue
		var inward:=Vectors.normalized(Vectors.added(geometry.position,-current))
		if not inward.is_finite():return fail("Asteroid contact vector exceeds source precision")
		result.operations.append({"kind":"asteroid","object_index":index,"impact_vector":inward,"body_damage":int(_policy.asteroid_damage),"player_damage":int(_policy.player_damage)})
	return result

static func first_station_volume(point: Vector3, station_center: Vector3, shapes: Array) -> int:
	for index in shapes.size():
		var shape: Dictionary=shapes[index]
		var center:=Vectors.added(station_center,shape.center)
		if shape.get("kind",1)==0:
			if Volumes.contains_sphere(point,center,float(shape.radius)):return index
		else:
			if Volumes.contains_point(point,center,shape.half_extents):return index
	return -1

static func valid_shape(shape: Variant) -> bool:
	if not shape is Dictionary or not shape.get("center") is Vector3 or not shape.center.is_finite():return false
	if shape.get("kind",1)==0:
		return (shape.get("radius") is float or shape.get("radius") is int) and is_finite(float(shape.radius)) and float(shape.radius)>0
	if shape.get("kind",1)!=1 or not shape.get("half_extents") is Vector3:return false
	var half: Vector3=shape.half_extents
	return half.is_finite() and half.x>0 and half.y>0 and half.z>0

static func project_shape(point: Vector3, station_center: Vector3, shape: Dictionary) -> Vector3:
	var center:=Vectors.added(station_center,shape.center)
	if shape.get("kind",1)==0:
		if not Volumes.contains_sphere(point,center,float(shape.radius)):return point
		return Vectors.added(center,Vectors.scaled(Vectors.normalized(Vectors.added(point,-center)),float(shape.radius)))
	var half: Vector3=shape.half_extents
	if not Volumes.contains_point(point,center,half):return point
	# Source chooses the nearest face; equal distances retain the earlier face.
	var faces:=[
		Vector3(Vitals.single(center.x+half.x),point.y,point.z),
		Vector3(Vitals.single(center.x-half.x),point.y,point.z),
		Vector3(point.x,Vitals.single(center.y+half.y),point.z),
		Vector3(point.x,Vitals.single(center.y-half.y),point.z),
		Vector3(point.x,point.y,Vitals.single(center.z+half.z)),
		Vector3(point.x,point.y,Vitals.single(center.z-half.z)),
	]
	var best: Vector3=faces[0]
	var distance:=absf(Vitals.single(point.x-best.x))
	for index in range(1,faces.size()):
		var candidate: Vector3=faces[index]
		var axis:=int(index/2)
		var next:=absf(Vitals.single(point[axis]-candidate[axis]))
		if next<distance:best=candidate;distance=next
	return best

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._identity=_identity;copy._policy=_policy;copy._station_center=_station_center;copy._station_half=_station_half
	copy._station_shapes=_station_shapes;copy._body_geometry=_body_geometry
	return copy

func clear() -> void:
	error="";_identity={};_policy={};_station_center=Vector3.ZERO;_station_half=0;_station_shapes=[];_body_geometry=[]
func fail(message: String) -> Dictionary:error=message;return {}
func reject(message: String) -> bool:error=message;return false
