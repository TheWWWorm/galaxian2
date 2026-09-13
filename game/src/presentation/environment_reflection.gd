extends RefCounted
## Resource preparation only. Reflection-vector and material response are owned
## by the native material renderer; an available cube does not implement them.
const Library = preload("res://src/content/library.gd")
const Definitions = preload("res://src/content/reflection_definitions.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const Cube = preload("res://src/content/cube_texture.gd")
const Loadout = preload("res://src/simulation/opening_loadout.gd")
var error := ""
var selection := {}
var texture: Cubemap

func build(library: RefCounted,bindings: RefCounted,catalogues: RefCounted,system_id: Variant,location_match: Variant,quality := "high") -> bool:
	clear()
	if library==null or bindings==null or catalogues==null:return reject("Reflection requires content, bindings and catalogues")
	var identity: Variant = library.manifest.get("content_id")
	if not Library.valid_hash(identity) or identity!=bindings.base_content_id or identity!=catalogues.content_id:
		return reject("Reflection resources must belong to one content base")
	if not Numbers.integer(system_id,0,2147483647) or int(system_id)>=catalogues.tables.get("systems",[]).size():
		return reject("Reflection requires a known source system")
	var system: Dictionary = catalogues.tables.systems[int(system_id)]
	var identifier := Definitions.texture_id(bindings.reflection_selection,system.get("sky_index"),location_match)
	if identifier<0:return reject("Reflection selection is unavailable or its location state is unsupported")
	var path: String = bindings.resolve_texture(identifier,quality)
	if path.is_empty():return reject(bindings.error)
	var loader := Cube.new()
	var staged := loader.load(library,path)
	if staged==null:return reject(loader.error)
	texture=staged
	selection={"base_content_id":identity,"binding_id":bindings.binding_id,"system_id":int(system_id),
		"sky_index":system.get("sky_index"),"location_match":location_match,"texture_id":identifier,
		"texture_path":path,"quality":quality}
	return true

func build_opening(library: RefCounted,bindings: RefCounted,catalogues: RefCounted,campaign_cursor: Variant,world_type: Variant,location_match: Variant,quality := "high") -> bool:
	clear()
	if library==null or bindings==null or catalogues==null:return reject("Opening reflection requires content, bindings and catalogues")
	if not Numbers.integer(campaign_cursor,0,0) or not Numbers.integer(world_type,3,3) or not location_match is bool or location_match:
		return reject("Opening reflection requires the verified fresh opening context")
	var loadout := Loadout.new()
	if not loadout.configure(bindings,catalogues,library.manifest.get("content_id","")):return reject(loadout.error)
	return build(library,bindings,catalogues,loadout.snapshot().system_id,location_match,quality)

func clear() -> void:
	error="";texture=null;selection.clear()

func reject(message: String) -> bool:
	clear();error=message
	return false
