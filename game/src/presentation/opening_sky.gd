extends Node3D
## Source background layers for the verified opening and rescue. No suns,
## planets, stations, flares, asteroid belts or location lighting are implied.
const Definitions = preload("res://src/content/opening_sky_definitions.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const Loadout = preload("res://src/simulation/opening_loadout.gd")
const Arrival = preload("res://src/simulation/arrival_location.gd")
const Orientation = preload("res://src/simulation/scenery_orientation.gd")
const AEM = preload("res://src/content/aem.gd")
const Model = preload("res://src/presentation/imported_model.gd")
const Geometry = preload("res://src/presentation/opening_geometry.gd")
const STAR_SHADER = preload("res://src/presentation/sky_stars.gdshader")
const NEBULA_SHADER = preload("res://src/presentation/sky_nebula.gdshader")
var error := ""
var selection := {}
var layers: Array[Node3D] = []
var _orientation := Basis.IDENTITY
var _initial_descriptors:=[]
var _escape_descriptor:={}

func build(library: RefCounted, visuals: RefCounted, bindings: RefCounted, catalogues: RefCounted, campaign_cursor: Variant, world_type: Variant, location_match: Variant, quality := "high", with_escape := false) -> bool:
	clear()
	var data: Dictionary = bindings.opening_sky
	if not Definitions.parameters(data): return reject("Opening sky declarations are unavailable")
	if not Numbers.integer(campaign_cursor,0,2147483647) or not Numbers.integer(world_type,0,2147483647) or not location_match is bool:
		return reject("Opening sky requires explicit campaign, world and location state")
	if campaign_cursor!=int(data.campaign_cursor) or world_type!=int(data.world_type) or location_match!=data.location_match:
		return reject("This background selector only supports the fresh opening context")
	var loadout := Loadout.new()
	if not loadout.configure(bindings,catalogues,library.manifest.get("content_id","")): return reject(loadout.error)
	return _build_location(library,visuals,bindings,catalogues,data,loadout.snapshot(),quality,with_escape)

func build_arrival(library: RefCounted, visuals: RefCounted, bindings: RefCounted, catalogues: RefCounted, arrival_cache: Variant, quality := "high") -> bool:
	clear()
	var location:=Arrival.new()
	var context:=location.resolve(bindings,catalogues,arrival_cache)
	if context.is_empty():return reject(location.error)
	if library.manifest.get("content_id","")!=bindings.base_content_id:return reject("Rescue sky belongs to another content identity")
	if not _build_location(library,visuals,bindings,catalogues,context.sky_parameters,context,quality,false):return false
	selection.campaign_cursor=context.campaign_cursor
	return true

func build_lounge(library: RefCounted,visuals: RefCounted,bindings: RefCounted,catalogues: RefCounted,station_id: int,cursor: int,quality:="high") -> bool:
	clear()
	var location:=Arrival.new()
	var context:=location.resolve_lounge(bindings,catalogues,station_id,cursor)
	if context.is_empty():return reject(location.error)
	if library.manifest.get("content_id","")!=bindings.base_content_id:return reject("Lounge sky belongs to another content identity")
	if not _build_location(library,visuals,bindings,catalogues,context.sky_parameters,context,quality,false):return false
	selection.campaign_cursor=cursor;selection.world_type=context.world_type
	return true

func build_departure(library: RefCounted, visuals: RefCounted, bindings: RefCounted, catalogues: RefCounted, cache: Variant, quality := "high", equipment: RefCounted=null) -> bool:
	clear()
	var location:=Arrival.new()
	var context:=location.resolve_departure(bindings,catalogues,cache,equipment)
	if context.is_empty():return reject(location.error)
	if library.manifest.get("content_id","")!=bindings.base_content_id:return reject("Departure sky belongs to another content identity")
	if not _build_location(library,visuals,bindings,catalogues,context.sky_parameters,context,quality,false):return false
	selection.campaign_cursor=context.campaign_cursor
	return true

func _build_location(library: RefCounted, visuals: RefCounted, bindings: RefCounted, catalogues: RefCounted, data: Dictionary, opening: Dictionary, quality: String, with_escape: bool) -> bool:
	if visuals.base_content_id!=bindings.base_content_id: return reject("Sky textures belong to another content identity")
	var system: Dictionary = catalogues.tables.systems[opening.system_id]
	if not Numbers.integer(system.get("sky_index"),0,65535): return reject("Opening system has no valid sky index")
	# System 27 uses a light-direction basis in the source, not the seeded Euler
	# basis. That additional background path is outside this opening renderer.
	if opening.system_id==27: return reject("Light-oriented background is not implemented")
	var orientation := Orientation.new()
	var rotation_value := orientation.for_station(opening.station_id,int(system.sky_index) in [17,18])
	if rotation_value.is_empty(): return reject(orientation.error)
	var variant := int(opening.system_id)%int(data.star_variants)
	var descriptors := [
		{"mesh_id":int(data.star_mesh_base)+variant,"texture_id":int(data.star_texture_base)+variant,"mode":0},
		{"mesh_id":int(data.sky_mesh_id),"texture_id":int(data.sky_texture_id),"mode":2}]
	_initial_descriptors=descriptors.duplicate(true)
	if with_escape:
		var escape: Dictionary=bindings.opening_staging.get("escape",{})
		if bindings.opening_staging.get("escape_camera",{}).is_empty() or escape.is_empty():return reject("Escape sky requires supported escape declarations")
		_escape_descriptor={"mesh_id":int(escape.jump_sky_mesh_id),"texture_id":int(escape.jump_sky_texture_id),"mode":2}
		descriptors.append(_escape_descriptor)
	var cache := {}
	for descriptor in descriptors:
		# The source explicitly overrides the texture for these mesh IDs. Path-only
		# material lookup would conflate the three registered star alternatives.
		var path: String = bindings.resolve(descriptor.mesh_id,"mesh")
		if path.is_empty(): return reject(bindings.error)
		var texture_path: String = bindings.resolve_texture(descriptor.texture_id,quality)
		if texture_path.is_empty(): return reject(bindings.error)
		var reader := AEM.new()
		var bytes: PackedByteArray = library.read_resource(path,AEM.MAX_BYTES)
		if bytes.is_empty(): return reject(library.error)
		var decoded := reader.decode(bytes)
		if decoded.is_empty(): return reject(reader.error)
		if int(decoded.keyframes)!=0: return reject("Animated opening sky is not supported")
		var image: Image = visuals.load_image(texture_path)
		if image==null: return reject(visuals.error)
		var model := Model.new()
		model.build(decoded,image,null,descriptor.mode,cache)
		model.name="Stars" if descriptor.mode==0 else ("Nebula" if layers.size()==1 else "ArrivalNebula")
		model.visible=layers.size()<2
		model.set_meta("source_resource_id",descriptor.mesh_id)
		model.set_meta("source_texture_id",descriptor.texture_id)
		model.set_meta("source_texture_path",texture_path)
		for material in model.materials:
			material.shader=STAR_SHADER if descriptor.mode==0 else NEBULA_SHADER
			material.render_priority=-128 if descriptor.mode==0 else -127 # Stars, then nebula, before alpha world geometry.
		# The shader projects infinite background directions; source-sized CPU
		# bounds must not cull the layer against an ordinary world far plane.
		for instance in model.instances:
			instance.custom_aabb=AABB(Vector3.ONE*-1e9,Vector3.ONE*2e9)
			instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(model);layers.append(model)
	_orientation=rotation_value.basis
	basis=_orientation
	selection={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"station_id":opening.station_id,"system_id":opening.system_id,"angles":rotation_value.angles,
		"star_variant":variant,"layers":_initial_descriptors.duplicate(true)}
	return true

func apply_view(view: Dictionary, escape: Dictionary = {}) -> bool:
	error=""
	if selection.is_empty() or not Geometry.valid_pose(view.get("pose")):
		error="Opening sky requires a valid current camera view"
		return false
	var relocated:=false
	if not _escape_descriptor.is_empty():
		if escape.get("base_content_id")!=selection.base_content_id or escape.get("binding_id")!=selection.binding_id or not Numbers.integer(escape.get("phase"),4,16):
			error="Escape sky frame belongs to another or invalid opening";return false
		relocated=int(escape.phase)>=10
	elif not escape.is_empty():
		error="This sky has no prepared escape resources";return false
	# Keep bounds near the viewer. Shader projection excludes this translation.
	global_transform=Transform3D(_orientation,view.pose.origin)
	if not _escape_descriptor.is_empty():
		layers[1].visible=not relocated;layers[2].visible=relocated
		selection.layers=[_initial_descriptors[0].duplicate(),(_escape_descriptor if relocated else _initial_descriptors[1]).duplicate()]
	return true

func clear() -> void:
	for child in get_children(): child.free()
	layers.clear();selection.clear();_initial_descriptors=[];_escape_descriptor={};_orientation=Basis.IDENTITY;transform=Transform3D.IDENTITY;error=""

func reject(message: String) -> bool:
	clear();error=message
	return false
