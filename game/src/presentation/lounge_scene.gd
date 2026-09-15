extends Node3D
## Original lounge geometry with native camera and visitor selection. The room
## uses its actual location's shared sky/planet renderers; no window backdrop.
const Definitions=preload("res://src/content/lounge_presentation_definitions.gd")
const Models=preload("res://src/presentation/model_resources.gd")
const Model=preload("res://src/presentation/imported_model.gd")
const AEM=preload("res://src/content/aem.gd")
const Materials=preload("res://src/presentation/material_library.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const PoseSampler=preload("res://src/presentation/scenery_animation.gd")
const Background=preload("res://src/presentation/opening_sky.gd")
const Planets=preload("res://src/presentation/opening_planet_geometry.gd")
var error:=""
var camera: Camera3D
var sky: Node3D
var planets: Node3D
var selection:={}
var _rules:={}
var _room:=0
var _visitors:=[]
var _animated:=[]
var _elapsed_ms:=0
var _entry:=Transform3D.IDENTITY
var _settled:=Transform3D.IDENTITY
var environment: Environment

func build(library: RefCounted,bindings: RefCounted,visuals: RefCounted,cat: RefCounted,state: Dictionary,seed_value: int=0) -> bool:
	clear()
	if not Definitions.available(bindings):return reject("Original lounge declarations are unavailable; prepare the current Mac bindings")
	_rules=bindings.early_contracts.lounge_presentation
	var station_id:=int(state.loadout.station_id);var cursor:=int(state.campaign_cursor)
	var station: Dictionary=cat.tables.stations[station_id]
	_room=int(cat.tables.systems[station.system_id].fields[int(_rules.system_faction_field)])
	if _room<0 or _room>=_rules.room_meshes.size():return reject("This faction has no supported lounge interior")
	var contacts: Array=state.get("contracts",{}).get("population",{}).get("contacts",[])
	if contacts.size()>_rules.visitor_slots[_room].size():return reject("Lounge contacts exceed the original placement table")
	var paths:=[];var parts: Array=_rules.room_meshes[_room]+_rules.extra_meshes[_room]
	var visitor_ids:=[]
	for contact in contacts:
		var faction:=int(contact.faction)
		if faction==3 and int(contact.portrait.family)==int(_rules.midorian_portrait_family):faction=int(_rules.midorian_nivelian_row)
		if faction<0 or faction>=_rules.visitor_meshes.size():return reject("Unknown visitor model family")
		visitor_ids.append(int(_rules.female_terran_mesh) if faction==0 and not contact.male else int(_rules.visitor_meshes[faction]))
	for id in parts+visitor_ids+[int(_rules.shadow_mesh)]:
		var path: String=bindings.resolve(int(id),"mesh")
		if path.is_empty():return reject(bindings.error)
		paths.append(path)
	var resources:=Models.new()
	if not resources.prepare(paths,library,visuals,bindings):return reject(resources.error)
	for id in parts:
		var model: Node3D=resources.instantiate(bindings.resolve(int(id),"mesh"));add_child(model)
		model.set_meta("source_resource_id",int(id));_animated.append(model)
		if not _initial_pose(model):resources.clear();return false
	# The source uses unique draws from seven positions. Isolate presentation
	# randomness so opening a room never changes offers, stock or career RNG.
	var rng:=Random.new();rng.seed_from(seed_value);var used:={}
	var glow:=_prepare_selection(library,bindings,visuals)
	if glow==null:resources.clear();return false
	for index in contacts.size():
		var slot:=rng.next_int(_rules.visitor_slots[_room].size());var attempts:=0
		while used.has(slot):
			slot=rng.next_int(_rules.visitor_slots[_room].size());attempts+=1
			if attempts>4096:glow.free();resources.clear();return reject("Visitor placement exceeded its draw bound")
		used[slot]=true
		var body: Node3D=resources.instantiate(bindings.resolve(visitor_ids[index],"mesh"));add_child(body)
		body.position=vector(_rules.visitor_slots[_room][slot]);body.set_source_time(0)
		body.set_meta("source_resource_id",visitor_ids[index]);_animated.append(body)
		var shadow: Node3D=resources.instantiate(bindings.resolve(int(_rules.shadow_mesh),"mesh"));add_child(shadow)
		shadow.position=body.position+Vector3.UP*float(_rules.shadow_height);shadow.set_source_time(0)
		var highlight:=Model.new();highlight.copy_from(glow);add_child(highlight);highlight.position=body.position;highlight.visible=false
		_visitors.append({"id":int(contacts[index].contact_id),"slot":slot,"body":body,"highlight":highlight,"bounds":body.source_bounds})
	glow.free();resources.clear()
	camera=Camera3D.new();add_child(camera);camera.keep_aspect=Camera3D.KEEP_HEIGHT
	var projection: Array=_rules.camera.projection
	camera.set_perspective(rad_to_deg(float(projection[0])),float(projection[1]),float(projection[2]))
	_entry=Transform3D(Basis(Vector3.UP,float(_rules.camera.entry_yaws[_room])),vector(_rules.camera.entry_positions[_room]))
	_settled=Transform3D(Basis(Vector3.UP,float(_rules.camera.yaws[_room])),vector(_rules.camera.positions[_room]))
	sky=Background.new();add_child(sky)
	if not sky.build_lounge(library,visuals,bindings,cat,station_id,cursor):return reject(sky.error)
	planets=Planets.new();add_child(planets)
	if not planets.build_lounge(library,visuals,bindings,cat,station_id,cursor):return reject(planets.error)
	# Shared native PBR adaptation. Original shader/global-light parity is still
	# incomplete; the authored additive room and glass layers remain intact.
	environment=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color.BLACK
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color.WHITE;environment.ambient_light_energy=0.5
	var light:=DirectionalLight3D.new();add_child(light);light.rotation=Vector3(-0.8,0.4,0)
	var diffuse: Array=_rules.light_diffuse;light.light_color=Color(diffuse[0],diffuse[1],diffuse[2]).linear_to_srgb();light.shadow_enabled=false
	selection={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"station_id":station_id,"system_id":int(station.system_id),"room":_room,"room_meshes":parts.duplicate(),"visitors":[]}
	for row in _visitors:selection.visitors.append({"contact_id":row.id,"slot":row.slot,"mesh_id":row.body.get_meta("source_resource_id"),"position":row.body.position})
	return advance(0)

func _initial_pose(model: Node3D) -> bool:
	# Use the existing verified geometry sampler, including source axis and pivot
	# conversion and packed surface color. UV playback remains at its initial pose.
	var surfaces:=[]
	for surface in model.surfaces:
		var row: Dictionary=surface.duplicate();row.tracks=surface.tracks.duplicate();row.tracks.erase("uv");surfaces.append(row)
	var sampler:=PoseSampler.new()
	if not sampler.configure(surfaces,true):return reject(sampler.error)
	var sample: Dictionary=sampler.sample(int(sampler.snapshot().range.start_ms),Transform3D.IDENTITY)
	if sample.is_empty():return reject(sampler.error)
	for index in sample.surfaces.size():
		var row: Dictionary=sample.surfaces[index]
		model.instances[index].transform=row.pose
		var tint:=float(row.get("color_byte",255))/255.0
		model.instances[index].visible=tint>0
		model.materials[index].set_shader_parameter("surface_tint",Vector4.ONE*tint)
	return true

func _prepare_selection(library: RefCounted,bindings: RefCounted,visuals: RefCounted) -> Node3D:
	# Four IDs intentionally share a mesh path with different materials. Resolve
	# the selected registration directly instead of conflating path aliases.
	var id:=int(_rules.selection_meshes[_room]);var path: String=bindings.resolve(id,"mesh")
	if path.is_empty():error=bindings.error;return null
	var records: Array=bindings.records[id]
	var material_id:=int(records[0].get("material_id",-1))
	for record in records:
		if record.get("material_id",-1)!=material_id or record.get("mesh_flags",-1)!=0:error="Ambiguous lounge selection material";return null
	var descriptor: Dictionary=bindings.resolve_material(material_id)
	if not Materials.supports(descriptor) or int(descriptor.texture_ids[0])!=int(_rules.selection_textures[_room]):error="Unsupported lounge selection material";return null
	var image: Image=visuals.load_image(descriptor.texture_paths[0])
	if image==null:error=visuals.error;return null
	var reader:=AEM.new();var decoded:=reader.decode(library.read_resource(path,AEM.MAX_BYTES))
	if decoded.is_empty():error=reader.error;return null
	var model:=Model.new();model.build(decoded,image,null,int(descriptor.render_type));model.set_source_time(0)
	return model

func advance(milliseconds: int) -> bool:
	if milliseconds<0 or camera==null:return reject("Invalid lounge camera step")
	_elapsed_ms+=milliseconds
	var weight:=clampf(float(_elapsed_ms)/float(_rules.camera.entry_duration_ms),0,1)
	camera.transform=_entry.interpolate_with(_settled,weight)
	# Retain the authored initial animation pose until lounge playback clocks
	# and transform conventions are verified. Camera time is not asset time.
	for row in _visitors:
		# Native upright facing; exact original billboard interpolation remains
		# separate from the source-authored positions and model selection.
		var towards: Vector3=camera.position-row.body.position;towards.y=0
		if towards.length_squared()>0.001:row.body.basis=Basis.looking_at(towards,Vector3.UP,true)
		row.highlight.basis=row.body.basis
	var view:={"pose":camera.global_transform}
	if not sky.apply_view(view):return reject(sky.error)
	if not planets.apply_view(view):return reject(planets.error)
	return true

func select_contact(id: int) -> void:
	for row in _visitors:row.highlight.visible=row.id==id

func screen_contacts() -> Array:
	var result:=[]
	if camera==null or not visible:return result
	for row in _visitors:
		var bounds: AABB=row.bounds
		var feet: Vector3=row.body.global_position
		var head: Vector3=row.body.to_global(Vector3(0,bounds.end.y,0))
		if camera.is_position_behind(head):continue
		var top:=camera.unproject_position(head);var bottom:=camera.unproject_position(feet)
		var height:=maxf(24,absf(bottom.y-top.y));var width:=maxf(32,height*0.65)
		result.append({"id":row.id,"rect":Rect2(Vector2((top.x+bottom.x-width)/2,minf(top.y,bottom.y)),Vector2(width,height)),"anchor":(top+bottom)/2,"depth":-camera.to_local(head).z})
	result.sort_custom(func(a,b):return a.depth<b.depth)
	return result

func snapshot() -> Dictionary:
	var result:=selection.duplicate(true);result.elapsed_ms=_elapsed_ms
	result.camera_pose=Transform3D.IDENTITY if camera==null else camera.transform
	result.sky={} if sky==null else sky.selection.duplicate(true);result.planets={} if planets==null else planets.selection.duplicate(true)
	return result

static func vector(value: Array) -> Vector3:return Vector3(value[0],value[1],value[2])
func clear() -> void:
	for child in get_children():child.free()
	error="";camera=null;sky=null;planets=null;selection={};_rules={};_visitors=[];_animated=[];_elapsed_ms=0;environment=null
func reject(message: String) -> bool:error=message;return false
