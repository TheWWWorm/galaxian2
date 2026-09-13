extends Node3D
## Original planet planes for the verified opening and rescue. Sun and lens-flare
## drawing are separate; their retained screen intensity is not guessed here.
const Layout = preload("res://src/simulation/opening_planet_layout.gd")
const Geometry = preload("res://src/presentation/opening_geometry.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const AEM = preload("res://src/content/aem.gd")
const Model = preload("res://src/presentation/imported_model.gd")
const SHADER = preload("res://src/presentation/sky_planet.gdshader")
var error := ""
var selection := {}
var models: Array[Node3D]=[]
var _layout := {}
var _textures: Array[Texture2D]=[]
var _arrival: Texture2D
var _arrival_id := -1

func build(library: RefCounted, visuals: RefCounted, bindings: RefCounted, catalogues: RefCounted, quality := "high", with_escape := false) -> bool:
	return _build(library,visuals,bindings,catalogues,quality,with_escape,0,{})

func build_arrival(library: RefCounted, visuals: RefCounted, bindings: RefCounted, catalogues: RefCounted, arrival_cache: Variant, quality := "high") -> bool:
	return _build(library,visuals,bindings,catalogues,quality,false,1,arrival_cache)

func build_departure(library: RefCounted, visuals: RefCounted, bindings: RefCounted, catalogues: RefCounted, cache: Variant, quality := "high", equipment: RefCounted=null) -> bool:
	return _build(library,visuals,bindings,catalogues,quality,false,2,cache,equipment)

func _build(library: RefCounted, visuals: RefCounted, bindings: RefCounted, catalogues: RefCounted, quality: String, with_escape: bool, cursor: int, location_cache: Variant, equipment: RefCounted=null) -> bool:
	clear()
	if visuals.base_content_id!=bindings.base_content_id:return reject("Planet textures belong to another content identity")
	var layout:=Layout.new()
	if library.manifest.get("content_id","")!=bindings.base_content_id:return reject("Planet resources belong to another content identity")
	match cursor:
		0:_layout=layout.for_opening(bindings,catalogues,library.manifest.get("content_id",""),quality)
		1:_layout=layout.for_arrival(bindings,catalogues,location_cache,quality)
		2:_layout=layout.for_departure(bindings,catalogues,location_cache,quality,equipment)
		_:return reject("Unsupported planet scene")
	if _layout.is_empty():return reject(layout.error)
	if _layout.sky_index in [11,12]:return reject("Fogged planet drawing is not yet supported")
	var reader:=AEM.new()
	var bytes: PackedByteArray=library.read_resource(_layout.mesh_path,AEM.MAX_BYTES)
	if bytes.is_empty():return reject(library.error)
	var decoded:=reader.decode(bytes)
	if decoded.is_empty():return reject(reader.error)
	if int(decoded.keyframes)!=0:return reject("Animated planet geometry is unsupported")
	if with_escape:
		var escape: Dictionary=bindings.opening_staging.get("escape",{})
		if bindings.opening_staging.get("escape_camera",{}).is_empty() or not Numbers.integer(escape.get("jump_planet_texture_id"),0,65533):return reject("Escape planet declarations are unavailable")
		_arrival_id=int(escape.jump_planet_texture_id)
		var path: String=bindings.resolve_texture(_arrival_id,quality)
		if path.is_empty():return reject(bindings.error)
		var image: Image=visuals.load_image(path)
		if image==null:return reject(visuals.error)
		_arrival=ImageTexture.create_from_image(image)
	var cache:={}
	for index in range(1,_layout.entries.size()):
		var entry: Dictionary=_layout.entries[index]
		var image: Image=visuals.load_image(entry.texture_path)
		if image==null:return reject(visuals.error)
		var model:=Model.new();model.build(decoded,image,null,1,cache)
		model.name="Planet_"+str(entry.station_id)
		model.set_meta("source_resource_id",_layout.mesh_id)
		model.set_meta("source_station_id",entry.station_id)
		model.set_meta("source_texture_id",entry.texture_id)
		for material in model.materials:
			material.shader=SHADER
			# Stars, nebula and sun precede planets; preserve station draw order.
			material.render_priority=-126+index
		for instance in model.instances:
			instance.custom_aabb=AABB(Vector3.ONE*-1e9,Vector3.ONE*2e9)
			instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(model);models.append(model);_textures.append(cache[image])
	selection={"base_content_id":_layout.base_content_id,"binding_id":_layout.binding_id,
		"station_id":_layout.station_id,"system_id":_layout.system_id,"selected_index":_layout.selected_index,
		"mesh_id":_layout.mesh_id,"planets":[]}
	if cursor!=0:selection.campaign_cursor=int(_layout.campaign_cursor)
	return true

func apply_view(view: Dictionary, escape: Dictionary = {}) -> bool:
	error=""
	if selection.is_empty() or not Geometry.valid_pose(view.get("pose")):
		error="Planet drawing requires a valid current camera view";return false
	var relocated:=false
	if _arrival!=null:
		if escape.get("base_content_id")!=selection.base_content_id or escape.get("binding_id")!=selection.binding_id or not Numbers.integer(escape.get("phase"),4,16):
			error="Escape planet frame belongs to another or invalid opening";return false
		relocated=int(escape.phase)>=10
	elif not escape.is_empty():
		error="This planet scene has no prepared escape resources";return false
	var staged:=[]
	for index in models.size():
		var entry: Dictionary=_layout.entries[index+1]
		var scale_value: float=entry.scale
		if entry.current:
			# Source draw overwrites the current wrapper's scale from retained
			# constructor scale plus clamped camera Z. The escape controller's
			# earlier one-time doubling does not alter that constructor baseline.
			var adjustment:=clampf(f32(view.pose.origin.z/-800000.0),f32(-0.2),f32(0.2))
			scale_value=f32(scale_value+adjustment)
		var pose:=Transform3D(entry.basis.scaled(Vector3.ONE*scale_value),entry.origin+view.pose.origin)
		if not pose.origin.is_finite() or not pose.basis.is_finite():
			error="Planet drawing is outside supported coordinates";return false
		staged.append({"station_id":entry.station_id,"pose":pose,"scale":scale_value,
			"texture_id":_arrival_id if entry.current and relocated else entry.texture_id,
			"texture":_arrival if entry.current and relocated else _textures[index]})
	for index in models.size():
		var row: Dictionary=staged[index]
		models[index].global_transform=row.pose
		models[index].set_meta("source_texture_id",row.texture_id)
		for material in models[index].materials:material.set_shader_parameter("diffuse_texture",row.texture)
		row.erase("texture")
	selection.planets=staged
	return true

func f32(value: float) -> float:
	return PackedFloat32Array([value])[0]

func clear() -> void:
	for child in get_children():child.free()
	models.clear();selection.clear();_layout.clear();_textures.clear();_arrival=null;_arrival_id=-1;error=""

func reject(message: String) -> bool:
	clear();error=message;return false
