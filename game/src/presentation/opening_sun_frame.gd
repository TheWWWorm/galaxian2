extends RefCounted
## Prepares the two ordinary sun poses and the following lens-flare intensity.
## The caller supplies the preceding draw's intensity explicitly. Preparing or
## replaying a frame does not advance a retained screen state.
const Layout=preload("res://src/simulation/opening_planet_layout.gd")
const Definitions=preload("res://src/content/sun_flare_definitions.gd")
const TargetProjection=preload("res://src/presentation/target_projection.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
const Geometry=preload("res://src/presentation/opening_geometry.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
var error:=""
var selection:={}
var _layout:={}
var _perspective:={}

func configure(bindings: RefCounted,catalogues: RefCounted,base_content_id: String,quality:="high") -> bool:
	clear()
	var data: Dictionary=bindings.opening_sky.get("sun_flares",{})
	if not Definitions.parameters(data):return reject("Sun flare declarations are unavailable; prepare current bindings")
	var layout:=Layout.new()
	_layout=layout.for_opening(bindings,catalogues,base_content_id,quality)
	if _layout.is_empty():return reject(layout.error)
	return _configure_layout(bindings,data,base_content_id)

func configure_arrival(bindings: RefCounted,catalogues: RefCounted,cache: Variant,quality:="high") -> bool:
	clear()
	var data: Dictionary=bindings.opening_sky.get("sun_flares",{})
	if not Definitions.parameters(data):return reject("Sun flare declarations are unavailable; prepare current bindings")
	var layout:=Layout.new()
	_layout=layout.for_arrival(bindings,catalogues,cache,quality)
	if _layout.is_empty():return reject(layout.error)
	return _configure_layout(bindings,data,bindings.base_content_id)

func configure_departure(bindings: RefCounted,catalogues: RefCounted,cache: Variant,quality:="high", equipment: RefCounted=null, mission_context: RefCounted=null) -> bool:
	clear()
	var data: Dictionary=bindings.opening_sky.get("sun_flares",{})
	if not Definitions.parameters(data):return reject("Sun flare declarations are unavailable; prepare current bindings")
	var layout:=Layout.new()
	_layout=layout.for_departure(bindings,catalogues,cache,quality,equipment,mission_context)
	if _layout.is_empty():return reject(layout.error)
	return _configure_layout(bindings,data,bindings.base_content_id)

func _configure_layout(bindings: RefCounted,data: Dictionary,base_content_id: String) -> bool:
	var type:=int(data.system_types[_layout.system_id])
	var sun: Dictionary=_layout.entries[0]
	selection={"base_content_id":base_content_id,"binding_id":bindings.binding_id,
		"station_id":_layout.station_id,"system_id":_layout.system_id,"color_type":type,
		"color":data.colors[type].duplicate(),"mesh_id":_layout.mesh_id,"mesh_path":_layout.mesh_path,
		"texture_id":sun.texture_id,"texture_path":sun.texture_path,"images":data.images.duplicate(true)}
	if _layout.has("sun_swell"):
		# Supernova system: the glare and the streak use sn_sun_011, not the sun texture.
		var glare_id:=int(load("res://src/content/valkyrie_world_definitions.gd").SUPERNOVA.glare_texture)
		var glare_path: String=bindings.resolve_texture(glare_id,"high")
		if glare_path.is_empty():return reject(bindings.error)
		selection.glare_texture_id=glare_id;selection.glare_texture_path=glare_path
	_perspective=bindings.flight_projection.duplicate(true)
	return true

func configure_station(bindings: RefCounted,catalogues: RefCounted,station_id: int,cursor: int,quality:="high") -> bool:
	clear()
	var data: Dictionary=bindings.opening_sky.get("sun_flares",{})
	if not Definitions.parameters(data):return reject("Station sun requires its original flare declarations")
	var layout:=Layout.new()
	_layout=layout.for_station(bindings,catalogues,station_id,cursor,quality)
	if _layout.is_empty():return reject(layout.error)
	return _configure_layout(bindings,data,bindings.base_content_id)

func evaluate(view: Dictionary,viewport_size: Vector2i,previous_intensity: Variant) -> Dictionary:
	error=""
	if selection.is_empty() or not Geometry.valid_pose(view.get("pose")):
		return failure("Sun frame requires a configured opening and valid camera")
	if viewport_size.x<2 or viewport_size.y<2 or viewport_size.x>32767 or viewport_size.y>32767:
		return failure("Sun frame requires a supported viewport")
	var sun: Dictionary=_layout.entries[0]
	var poses:=poses_for_view(sun.origin,sun.scale,view.pose,previous_intensity,_layout.has("sun_swell"))
	if poses.has("error"):return failure(poses.error)
	var projection:=TargetProjection.new()
	if not projection.configure(_perspective,viewport_size):return failure(projection.error)
	var position:=Vectors.added(Vectors.scaled(_layout.sun.direction_to_sun,65536.0),view.pose.origin)
	var projected:=projection.project_point(view.pose,position)
	if projected.has("error"):return failure(projected.error)
	# The renderer's boolean includes the screen bounds. The broader rejection
	# inside the lens composer does not make offscreen suns emit flares.
	var next:=0.0
	if projected.in_view:
		var result:=intensity_at(projected.screen_position,projected.camera_position.z,viewport_size,selection.color_type)
		if result.has("error"):return failure(result.error)
		next=result.intensity
	var frame:={"base_content_id":selection.base_content_id,"binding_id":selection.binding_id,
		"previous_intensity":float(previous_intensity),"next_intensity":next,
		"primary_pose":poses.primary,"secondary_pose":poses.secondary,"delta":poses.delta,
		"screen_position":projected.screen_position,"camera_position":projected.camera_position,
		"in_view":projected.in_view,"color":selection.color.duplicate(),"color_type":selection.color_type}
	if poses.has("glare"):frame.glare_pose=poses.glare
	return frame

## `supernova`: the original's StarSystem::render in the supernova system
## (Ginoya before 158) faces the sun with world X as up and does not swell it.
## The swollen camera-up pass becomes a glare sprite (sn_sun_011) built from
## 0.3x the sun's scale, and the streak builds on that glare pose.
static func poses_for_view(origin: Vector3,base_scale: float,camera: Transform3D,previous_intensity: Variant,supernova:=false) -> Dictionary:
	if not origin.is_finite() or not Geometry.valid_pose(camera) or not is_finite(base_scale) or base_scale<=0:
		return {"error":"Invalid source sun pose"}
	if (not previous_intensity is float and not previous_intensity is int) or not is_finite(previous_intensity) or previous_intensity>80:
		return {"error":"Invalid retained sun flare intensity"}
	var prior:=single(float(previous_intensity))
	if not is_finite(prior):return {"error":"Retained sun intensity exceeds source precision"}
	var position:=Vectors.added(origin,camera.origin)
	var backward:=Vectors.normalized(position-camera.origin)
	var right:=Vectors.normalized(Vectors.cross(camera.basis.y,backward))
	var up:=Vectors.cross(backward,right)
	var delta:=maxf(0.0,single(single(prior-10.0)*0.015625))
	var base:=single(base_scale)
	var swell_base:=single(base*single(0.3)) if supernova else base
	var width:=single(swell_base+delta)
	var swollen:=Basis(Vectors.scaled(right,width),Vectors.scaled(up,width),Vectors.scaled(backward,swell_base))
	# The source matrix-scale helper mutates its input. The secondary pass scales
	# the already scaled primary basis again; constructor flare scale is replaced.
	var extra:=Vector3(single(single(single(swell_base+delta)+1.0)*delta),
		single(swell_base/single(single(single(1.0-delta)*6.0)+6.0)),swell_base)
	var secondary:=Basis(Vectors.scaled(swollen.x,extra.x),Vectors.scaled(swollen.y,extra.y),Vectors.scaled(swollen.z,extra.z))
	var primary:=swollen
	if supernova:
		var fixed_right:=Vectors.normalized(Vectors.cross(Vector3.RIGHT,backward))
		primary=Basis(Vectors.scaled(fixed_right,base),Vectors.scaled(Vectors.cross(backward,fixed_right),base),Vectors.scaled(backward,base))
	if not position.is_finite() or not primary.is_finite() or not secondary.is_finite():return {"error":"Sun poses exceed source precision"}
	var poses:={"primary":Transform3D(primary,position),"secondary":Transform3D(secondary,position),"delta":delta}
	if supernova:poses.glare=Transform3D(swollen,position)
	return poses

static func intensity_at(screen: Vector2,depth: float,viewport_size: Vector2i,color_type: Variant) -> Dictionary:
	if not screen.is_finite() or not is_finite(depth) or viewport_size.x<2 or viewport_size.y<2 or viewport_size.x>32767 or viewport_size.y>32767 or not Numbers.integer(color_type,0,5):
		return {"error":"Invalid lens flare projection"}
	if depth>=0 or screen.x<=-viewport_size.x or screen.x>=2*viewport_size.x or screen.y<=-viewport_size.y or screen.y>=2*viewport_size.y:
		return {"intensity":0.0}
	var half:=Vector2(viewport_size.x>>1,viewport_size.y>>1)
	var offset:=half-screen
	var distance:=single(sqrt(single(single(offset.x*offset.x)+single(offset.y*offset.y))))
	var value:=single(single(1.0-single(distance/half.y))*(80.0 if int(color_type)==5 else 64.0))
	if not is_finite(value):return {"error":"Lens intensity exceeds source precision"}
	return {"intensity":value}

static func single(value: float) -> float:return Vector2(value,0.0).x

func clear() -> void:
	error="";selection.clear();_layout.clear();_perspective.clear()

func reject(message: String) -> bool:
	clear();error=message;return false

func failure(message: String) -> Dictionary:
	error=message;return {"error":message}
