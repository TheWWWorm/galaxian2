extends Node3D
## Two original plane draws plus the following screen composition. Preparation
## is pure; committing a successful frame is the only presentation mutation.
const Frame=preload("res://src/presentation/opening_sun_frame.gd")
const FlareLayout=preload("res://src/presentation/sun_flare_layout.gd")
const FlareCanvas=preload("res://src/presentation/sun_flare_canvas.gd")
const Atlas=preload("res://src/content/atlas_region.gd")
const Target=preload("res://src/presentation/flight_target_frame.gd")
const AEM=preload("res://src/content/aem.gd")
const Model=preload("res://src/presentation/imported_model.gd")
const SHADER=preload("res://src/presentation/sky_sun.gdshader")
var error:=""
var selection:={}
var frame:={}
var primary: Node3D
var secondary: Node3D
var flares: Control
var _owner: RefCounted
var _image_sizes: Array=[]

func build(library: RefCounted,visuals: RefCounted,bindings: RefCounted,catalogues: RefCounted,quality:="high") -> bool:
	clear()
	if visuals.base_content_id!=bindings.base_content_id:return reject("Sun textures belong to another content identity")
	_owner=Frame.new()
	if not _owner.configure(bindings,catalogues,library.manifest.get("content_id",""),quality):return reject(_owner.error)
	return _build_models(library,visuals,bindings)

func build_arrival(library: RefCounted,visuals: RefCounted,bindings: RefCounted,catalogues: RefCounted,cache: Variant,quality:="high") -> bool:
	clear()
	if library.manifest.get("content_id","")!=bindings.base_content_id or visuals.base_content_id!=bindings.base_content_id:return reject("Rescue sun resources belong to another content identity")
	_owner=Frame.new()
	if not _owner.configure_arrival(bindings,catalogues,cache,quality):return reject(_owner.error)
	return _build_models(library,visuals,bindings)

func build_departure(library: RefCounted,visuals: RefCounted,bindings: RefCounted,catalogues: RefCounted,cache: Variant,quality:="high") -> bool:
	clear()
	if library.manifest.get("content_id","")!=bindings.base_content_id or visuals.base_content_id!=bindings.base_content_id:return reject("Departure sun resources belong to another content identity")
	_owner=Frame.new()
	if not _owner.configure_departure(bindings,catalogues,cache,quality):return reject(_owner.error)
	return _build_models(library,visuals,bindings)

func _build_models(library: RefCounted,visuals: RefCounted,bindings: RefCounted) -> bool:
	if _owner._layout.sky_index in [11,12]:return reject("Fogged sun drawing is not yet supported")
	var chosen: Dictionary=_owner.selection
	var reader:=AEM.new();var bytes: PackedByteArray=library.read_resource(chosen.mesh_path,AEM.MAX_BYTES)
	if bytes.is_empty():return reject(library.error)
	var decoded:=reader.decode(bytes)
	if decoded.is_empty():return reject(reader.error)
	if int(decoded.keyframes)!=0:return reject("Animated sun geometry is unsupported")
	var image: Image=visuals.load_image(chosen.texture_path)
	if image==null:return reject(visuals.error)
	primary=Model.new();primary.name="SunBackground";add_child(primary)
	primary.build(decoded,image,null,2)
	secondary=Model.new();secondary.name="SunWorldFlare";add_child(secondary)
	secondary.copy_from(primary)
	for material in primary.materials:material.shader=SHADER;material.render_priority=-126
	# This tail draw retains world depth testing. It must not shine through hulls.
	for material in secondary.materials:material.render_priority=2
	for model in [primary,secondary]:
		model.set_meta("source_resource_id",chosen.mesh_id);model.set_meta("source_texture_id",chosen.texture_id)
		for instance in model.instances:
			instance.custom_aabb=AABB(Vector3.ONE*-1e9,Vector3.ONE*2e9)
			instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var atlas:=Atlas.new();flares=FlareCanvas.new();flares.name="SunScreenFlares";add_child(flares)
	for alias in chosen.images:
		var id:=int(alias.texture_id)
		if not Target.BASELINE_ATLASES.has(id):return reject("Sun flare atlas has no verified baseline selection")
		var path: String=Target.BASELINE_ATLASES[id]
		var registered:=false
		for record in bindings.records.get(id,[]):
			if record.resource==path and record.kind=="texture" and int(record.registration_type)==2:registered=true
		if not registered:return reject("Sun flare atlas is not registered by this profile")
		var texture:=atlas.load(library,visuals,path,int(alias.region))
		if texture==null:return reject(atlas.error)
		flares.textures.append(texture);_image_sizes.append(Vector2i(texture.region.size))
	selection=chosen.duplicate(true)
	return true

func prepare_frame(view: Dictionary,viewport_size: Vector2i,previous_intensity: Variant) -> Dictionary:
	error=""
	if _owner==null:return failure("Sun geometry has not been prepared")
	var prepared: Dictionary=_owner.evaluate(view,viewport_size,previous_intensity)
	if prepared.has("error"):return failure(prepared.error)
	var composition:={"sprites":[],"intensity":0.0,"wash_alpha":0}
	if prepared.in_view:
		composition=FlareLayout.compose(prepared.screen_position,prepared.camera_position.z,viewport_size,prepared.color_type,_image_sizes)
		if composition.has("error"):return failure(composition.error)
	prepared.composition=composition;prepared.viewport_size=viewport_size
	return prepared

func commit_frame(prepared: Dictionary) -> void:
	primary.global_transform=prepared.primary_pose
	secondary.global_transform=prepared.secondary_pose
	# The zero-width source strip draws no pixels. Hide it to avoid submitting a
	# singular transform to Godot's normal-matrix calculation.
	secondary.visible=prepared.delta>0
	flares.size=Vector2(prepared.viewport_size);flares.apply_frame(prepared.composition,prepared.color)
	frame=prepared.duplicate(true)

func clear() -> void:
	for child in get_children():child.free()
	selection.clear();frame.clear();_image_sizes.clear();_owner=null;primary=null;secondary=null;flares=null;error=""
func reject(message: String) -> bool:
	clear();error=message;return false
func failure(message: String) -> Dictionary:
	error=message;return {"error":message}
