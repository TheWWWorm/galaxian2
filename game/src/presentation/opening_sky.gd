extends Node3D
## Source background layers, with opt-in nearby clouds for exterior views.
## Suns, planets, stations, flares and location lighting have separate owners.
const Definitions = preload("res://src/content/opening_sky_definitions.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const Loadout = preload("res://src/simulation/opening_loadout.gd")
const Arrival = preload("res://src/simulation/arrival_location.gd")
const Orientation = preload("res://src/simulation/scenery_orientation.gd")
const AEM = preload("res://src/content/aem.gd")
const Model = preload("res://src/presentation/imported_model.gd")
const Geometry = preload("res://src/presentation/opening_geometry.gd")
const Quality = preload("res://src/presentation/graphics_quality.gd")
const SpaceFog = preload("res://src/presentation/space_fog_geometry.gd")
const StaticFog = preload("res://src/presentation/static_fog_geometry.gd")
const ForegroundParticles = preload("res://src/presentation/foreground_particle_geometry.gd")
const STAR_SHADER = preload("res://src/presentation/sky_stars.gdshader")
const NEBULA_SHADER = preload("res://src/presentation/sky_nebula.gdshader")
const STORED_STAR_SHADER = preload("res://src/presentation/sky_stored_stars.gdshader")
const STORED_NEBULA_SHADER = preload("res://src/presentation/sky_stored_nebula.gdshader")
var error := ""
var selection := {}
var layers: Array[Node3D] = []
var space_fog: MultiMeshInstance3D
var static_fogs:=[]
var foreground_particles: MultiMeshInstance3D
var _orientation := Basis.IDENTITY
var _initial_descriptors:=[]
var _escape_descriptor:={}
var _stored_channels:=false
## Animated supernova flare layers: [{model, speed}] (Ginoya, 90-157).
var _flares:=[]

func enable_foreground_particles(library: RefCounted,visuals: RefCounted,bindings: RefCounted,environment: Dictionary,seed_value: Variant=null) -> bool:
	if selection.is_empty() or foreground_particles!=null or bindings==null:
		error="Prepare one exterior before its nearby particles";return false
	for key in ["base_content_id","binding_id"]:
		if selection.get(key)!=bindings.get(key):error="Nearby particles belong to another background identity";return false
	var seed: int=int(Time.get_unix_time_from_system()) if seed_value==null else int(seed_value)
	var particles:=ForegroundParticles.new()
	if not particles.build(library,visuals,bindings,environment,seed):
		error=particles.error;particles.free();return false
	particles.name="ForegroundParticles";add_child(particles);foreground_particles=particles
	error="";return true

func enable_space_fog(library: RefCounted,visuals: RefCounted,bindings: RefCounted,catalogues: RefCounted) -> bool:
	if selection.is_empty() or space_fog!=null or catalogues==null or bindings==null or catalogues.content_id!=selection.base_content_id:
		error="Prepare one matching exterior before its space clouds";return false
	if bindings.base_content_id!=selection.base_content_id or bindings.binding_id!=selection.binding_id:
		error="Space clouds belong to another background identity";return false
	var sky_index:=int(catalogues.tables.systems[int(selection.system_id)].sky_index)
	var cursor:=int(selection.get("campaign_cursor",-1))
	# Level::initParticleSystems: in the supernova system (Ginoya before 158) the
	# clouds are tinted x0.5 and, except at the blast (89), drift away from the sun.
	if load("res://src/content/valkyrie_world_definitions.gd").supernova_sun_scale(int(selection.system_id),cursor)!=1.0:
		var station: Dictionary=catalogues.tables.stations[int(selection.station_id)]
		var placement=load("res://src/simulation/sun_placement.gd").new()
		var sun: Dictionary=placement.for_station(int(selection.station_id),int(station.get("planet_type",0)))
		if sun.is_empty():error=placement.error;return false
		var wind:=Vector3.ZERO if cursor==89 else -Vector3(sun.direction_to_sun)*2000.0
		return _build_space_fog(library,visuals,bindings,sky_index,int(selection.station_id),wind,0.5)
	return _build_space_fog(library,visuals,bindings,sky_index,int(selection.station_id))

## A fixed fog cloud around one world object, in this exterior's cloud material.
func add_static_fog(library: RefCounted,visuals: RefCounted,bindings: RefCounted,catalogues: RefCounted,center: Vector3,rule: Dictionary,seed_value: int) -> bool:
	if selection.is_empty() or catalogues==null or catalogues.content_id!=selection.base_content_id:
		error="Prepare one matching exterior before its object fog";return false
	var fog:=StaticFog.new()
	if not fog.build(library,visuals,bindings,int(catalogues.tables.systems[int(selection.system_id)].sky_index),center,rule,seed_value):
		error=fog.error;fog.free();return false
	fog.name="ObjectFog%d"%static_fogs.size();add_child(fog);static_fogs.append(fog)
	fog.visible=Quality.effects_enabled()
	error="";return true

func _build_space_fog(library: RefCounted,visuals: RefCounted,bindings: RefCounted,sky_index: int,seed_value: int,velocity:=Vector3.ZERO,color_scale:=0.6) -> bool:
	var clouds:=SpaceFog.new()
	if not clouds.build(library,visuals,bindings,sky_index,seed_value,velocity,color_scale):
		error=clouds.error;clouds.free();return false
	clouds.name="SpaceClouds";add_child(clouds);space_fog=clouds
	error="";return true

func set_stored_channel_composition(enabled: bool) -> bool:
	# This is an explicit presentation choice. Existing flight views keep their
	# accepted mode; source-channel composition never changes another material.
	if layers.size()<2:error="Sky composition requires a complete background pair";return false
	for index in layers.size():
		var expected: Shader=(STORED_STAR_SHADER if index==0 else STORED_NEBULA_SHADER) if _stored_channels else (STAR_SHADER if index==0 else NEBULA_SHADER)
		for material in layers[index].materials:
			if material.shader!=expected:
				error="Sky composition cannot replace a different material owner";return false
	if enabled!=_stored_channels:
		for index in layers.size():
			var selected: Shader=(STORED_STAR_SHADER if index==0 else STORED_NEBULA_SHADER) if enabled else (STAR_SHADER if index==0 else NEBULA_SHADER)
			for material in layers[index].materials:
				material.shader=selected
				if index>0:
					var black: Color=layers[index].get_meta("nebula_black_level",Color.BLACK)
					if not enabled:black=black.srgb_to_linear()
					material.set_shader_parameter("nebula_black_level",Vector3(black.r,black.g,black.b))
		_stored_channels=enabled
	error="";return true

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

func build_station(library: RefCounted,visuals: RefCounted,bindings: RefCounted,catalogues: RefCounted,station_id: int,quality:="high") -> bool:
	clear()
	if library.manifest.get("content_id","")!=bindings.base_content_id or visuals.base_content_id!=bindings.base_content_id or catalogues.content_id!=bindings.base_content_id:
		return reject("Station background belongs to another content identity")
	if station_id<0 or station_id>=catalogues.tables.stations.size():return reject("Unknown station background location")
	var system_id:=int(catalogues.tables.stations[station_id].system_id)
	if system_id<0 or system_id>=catalogues.tables.systems.size():return reject("This station background uses an unsupported source orientation")
	var sky_index:=int(catalogues.tables.systems[system_id].sky_index)
	var sky: Dictionary=bindings.opening_sky
	var arrival: Dictionary=bindings.arrival_environment
	if not Definitions.parameters(sky) or sky_index<0 or sky_index>Orientation.LAST_SKY_INDEX:
		return reject("Station background has no supported source sky")
	var orientation:=Orientation.new()
	var rotation_value: Dictionary=orientation.for_location(station_id,system_id,sky_index,int(catalogues.tables.stations[station_id].get("planet_type",0)))
	if rotation_value.is_empty():return reject(orientation.error)
	var variant:=system_id%int(sky.star_variants)
	var descriptors:=[{"mesh_id":int(sky.star_mesh_base)+variant,"texture_id":int(sky.star_texture_base)+variant,"mode":0},
		{"mesh_id":int(arrival.sky_mesh_base)+sky_index,"texture_id":int(arrival.sky_texture_base)+sky_index,"mode":2}]
	_initial_descriptors=descriptors.duplicate(true)
	return _build_layers(library,visuals,bindings,{"station_id":station_id,"system_id":system_id},quality,descriptors,rotation_value,variant)

func build_departure(library: RefCounted, visuals: RefCounted, bindings: RefCounted, catalogues: RefCounted, cache: Variant, quality := "high", equipment: RefCounted=null, mission_context: RefCounted=null) -> bool:
	clear()
	var location:=Arrival.new()
	var context:=location.resolve_departure(bindings,catalogues,cache,equipment,mission_context)
	if context.is_empty():return reject(location.error)
	if library.manifest.get("content_id","")!=bindings.base_content_id:return reject("Departure sky belongs to another content identity")
	if not _build_location(library,visuals,bindings,catalogues,context.sky_parameters,context,quality,false):return false
	selection.campaign_cursor=context.campaign_cursor
	return true

func _build_location(library: RefCounted, visuals: RefCounted, bindings: RefCounted, catalogues: RefCounted, data: Dictionary, opening: Dictionary, quality: String, with_escape: bool) -> bool:
	if visuals.base_content_id!=bindings.base_content_id: return reject("Sky textures belong to another content identity")
	var system: Dictionary = catalogues.tables.systems[opening.system_id]
	if not Numbers.integer(system.get("sky_index"),0,65535): return reject("Opening system has no valid sky index")
	var orientation := Orientation.new()
	var rotation_value := orientation.for_location(int(opening.station_id),int(opening.system_id),int(system.sky_index),int(catalogues.tables.stations[int(opening.station_id)].get("planet_type",0)))
	if rotation_value.is_empty(): return reject(orientation.error)
	var variant := int(opening.system_id)%int(data.star_variants)
	var descriptors := [
		{"mesh_id":int(data.star_mesh_base)+variant,"texture_id":int(data.star_texture_base)+variant,"mode":0},
		{"mesh_id":int(data.sky_mesh_id),"texture_id":int(data.sky_texture_id),"mode":2}]
	_initial_descriptors=descriptors.duplicate(true)
	var World=load("res://src/content/valkyrie_world_definitions.gd")
	descriptors.append_array(World.supernova_flares(int(opening.system_id),int(opening.get("campaign_cursor",-1))))
	if with_escape:
		var escape: Dictionary=bindings.opening_staging.get("escape",{})
		if bindings.opening_staging.get("escape_camera",{}).is_empty() or escape.is_empty():return reject("Escape sky requires supported escape declarations")
		_escape_descriptor={"mesh_id":int(escape.jump_sky_mesh_id),"texture_id":int(escape.jump_sky_texture_id),"mode":2}
		descriptors.append(_escape_descriptor)
	return _build_layers(library,visuals,bindings,opening,quality,descriptors,rotation_value,variant)

func build_void(library: RefCounted,visuals: RefCounted,bindings: RefCounted,environment: RefCounted,quality:="high") -> bool:
	clear()
	if not is_instance_of(environment,load("res://src/simulation/void_environment.gd")):return reject("Void sky requires its generated source world")
	var state: Dictionary=environment.snapshot()
	for key in ["base_content_id","binding_id"]:
		if state.get(key)!=bindings.get(key):return reject("Void sky belongs to another source")
	if visuals.base_content_id!=bindings.base_content_id or library.manifest.get("content_id")!=bindings.base_content_id:return reject("Void sky textures belong to another source")
	var source: Dictionary=state.sky
	_initial_descriptors=[{"mesh_id":int(source.star_mesh_id),"texture_id":int(source.star_texture_id),"mode":0},
		{"mesh_id":int(source.sky_mesh_id),"texture_id":int(source.sky_texture_id),"mode":2}]
	if not _build_layers(library,visuals,bindings,state,quality,_initial_descriptors,state.sky_orientation,0):return false
	var lighting=load("res://src/simulation/environment_lighting.gd").new()
	var light: Dictionary=lighting.for_void(bindings.environment_colors)
	if light.is_empty():return reject(lighting.error)
	return _build_space_fog(library,visuals,bindings,10,-1,-light.lights[0].direction_to_light*2000.0,1.0)

func _build_layers(library: RefCounted,visuals: RefCounted,bindings: RefCounted,opening: Dictionary,quality: String,descriptors: Array,rotation_value: Dictionary,variant: int) -> bool:
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
		var animated: bool=descriptor.has("speed")
		if int(decoded.keyframes)!=0 and not animated: return reject("Animated opening sky is not supported")
		var image: Image = visuals.load_image(texture_path)
		if image==null: return reject(visuals.error)
		var model := Model.new()
		model.build(decoded,image,null,descriptor.mode,cache)
		model.name="Stars" if descriptor.mode==0 else ("Nebula" if layers.size()==1 else "ArrivalNebula")
		model.visible=layers.size()<2 or animated
		model.set_meta("source_resource_id",descriptor.mesh_id)
		model.set_meta("source_texture_id",descriptor.texture_id)
		model.set_meta("source_texture_path",texture_path)
		var black:=_nebula_background(image) if descriptor.mode!=0 else Color.BLACK
		model.set_meta("nebula_black_level",black)
		for material in model.materials:
			material.shader=STAR_SHADER if descriptor.mode==0 else NEBULA_SHADER
			if descriptor.mode!=0:
				var linear_black:=black.srgb_to_linear()
				material.set_shader_parameter("nebula_black_level",Vector3(linear_black.r,linear_black.g,linear_black.b))
			material.render_priority=-128 if descriptor.mode==0 else -127 # Stars, then nebula, before alpha world geometry.
		# The shader projects infinite background directions; source-sized CPU
		# bounds must not cull the layer against an ordinary world far plane.
		for instance in model.instances:
			instance.custom_aabb=AABB(Vector3.ONE*-1e9,Vector3.ONE*2e9)
			instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if animated:
			# Flares scroll their texture and fade to half strength (scalar
			# track 100 -> 50; assumed to be brightness), drawn additively.
			model.name="SupernovaFlares";_flares.append({"model":model,"speed":float(descriptor.speed),"length":maxf(load("res://src/content/animation_tracks.gd").range_of(model.surfaces).y,1.0)})
			for material in model.materials:material.set_shader_parameter("surface_tint",Color(0.5,0.5,0.5,1.0))
			add_child(model);continue
		add_child(model);layers.append(model)
	_orientation=rotation_value.basis
	basis=_orientation
	selection={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"station_id":opening.station_id,"system_id":opening.system_id,"angles":rotation_value.angles,
		"star_variant":variant,"layers":_initial_descriptors.duplicate(true)}
	return true

func _nebula_background(image: Image) -> Color:
	# A constant dark atlas backdrop must not expose the additive mesh's joins.
	# This adapts the material only; imported pixels and UVs stay untouched.
	var black:=image.get_pixel(0,0)
	if maxf(black.r,maxf(black.g,black.b))>0.125:return Color.BLACK
	for point in [Vector2i(image.get_width()-1,0),Vector2i(0,image.get_height()-1),image.get_size()-Vector2i.ONE]:
		if image.get_pixelv(point)!=black:return Color.BLACK
	return black

func apply_view(view: Dictionary, escape: Dictionary = {},elapsed_ms:=0) -> bool:
	var prepared:=prepare_view(view,escape,elapsed_ms)
	if prepared.is_empty():return false
	commit_view(prepared)
	return true

func prepare_view(view: Dictionary, escape: Dictionary = {},elapsed_ms:=0) -> Dictionary:
	error=""
	if selection.is_empty() or not Geometry.valid_pose(view.get("pose")):
		error="Opening sky requires a valid current camera view"
		return {}
	var relocated:=false
	if not _escape_descriptor.is_empty():
		if escape.get("base_content_id")!=selection.base_content_id or escape.get("binding_id")!=selection.binding_id or not Numbers.integer(escape.get("phase"),4,16):
			error="Escape sky frame belongs to another or invalid opening";return {}
		relocated=int(escape.phase)>=10
	elif not escape.is_empty():
		error="This sky has no prepared escape resources";return {}
	var clouds: RefCounted
	if space_fog!=null:
		clouds=space_fog.prepare_view(view.pose,elapsed_ms)
		if clouds==null:error=space_fog.error;return {}
	var particles: RefCounted
	if foreground_particles!=null:
		particles=foreground_particles.prepare_view(view.pose,elapsed_ms)
		if particles==null:error=foreground_particles.error;return {}
	return {"pose":view.pose,"relocated":relocated,"clouds":clouds,"particles":particles,"elapsed_ms":elapsed_ms}

func commit_view(prepared: Dictionary) -> void:
	# Keep bounds near the viewer. Shader projection excludes this translation.
	global_transform=Transform3D(_orientation,prepared.pose.origin)
	var relocated: bool=prepared.relocated
	if not _escape_descriptor.is_empty():
		layers[1].visible=not relocated;layers[2].visible=relocated
		selection.layers=[_initial_descriptors[0].duplicate(),(_escape_descriptor if relocated else _initial_descriptors[1]).duplicate()]
	if space_fog!=null:
		space_fog.commit_view(prepared.clouds);space_fog.visible=Quality.effects_enabled()
	for fog in static_fogs:fog.visible=Quality.effects_enabled()
	var World=load("res://src/content/valkyrie_world_definitions.gd")
	for flare in _flares:
		# Looping animation (assumed to loop, as the sun's).
		flare.model.set_source_time(fmod(float(World.SUPERNOVA.overlay_start_ms)+float(prepared.get("elapsed_ms",0))*float(flare.speed),float(flare.length)))
	if foreground_particles!=null:
		foreground_particles.commit_view(prepared.particles);foreground_particles.visible=Quality.effects_enabled()

## The supernova reversal (157): the flare layers go at once.
func reverse_supernova() -> void:
	for flare in _flares:flare.model.visible=false
	_flares=[]

func clear() -> void:
	for child in get_children(): child.free()
	layers.clear();_flares=[];selection.clear();_initial_descriptors=[];_escape_descriptor={};_orientation=Basis.IDENTITY;transform=Transform3D.IDENTITY;error=""
	_stored_channels=false
	space_fog=null;static_fogs=[]
	foreground_particles=null

func reject(message: String) -> bool:
	clear();error=message
	return false
