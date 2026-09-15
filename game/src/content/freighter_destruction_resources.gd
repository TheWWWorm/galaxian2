extends RefCounted
const FreeLife=preload("res://src/content/free_lifecycle_definitions.gd")
const Construction=preload("res://src/simulation/opening_npc_construction.gd")
## Transactional staging of original animation, cargo, wreck volumes and effects.
const Definitions=preload("res://src/content/freighter_destruction_definitions.gd")
const Effects=preload("res://src/content/npc_destruction_resources.gd")
const AEM=preload("res://src/content/aem.gd")
const Timing=preload("res://src/content/scenery_effect_resources.gd")
const Volumes=preload("res://src/content/station_collision_volumes.gd")
var error:=""
var _state:={}

func configure(library: RefCounted,bindings: RefCounted,cursor: int=11) -> bool:
	error="";_state={}
	if bindings==null or not Definitions.parameters(bindings.freighter_destruction):return reject("Freighter destruction is unavailable in this content pack")
	var rules:=Definitions.for_context(bindings,cursor)
	if rules.is_empty():return reject("Unsupported freighter destruction context")
	return _configure_resources(library,bindings,rules)

func configure_convoy(library: RefCounted,bindings: RefCounted) -> bool:
	error="";_state={}
	var rules:=Definitions.for_convoy(bindings)
	if rules.is_empty():return reject("Convoy destruction is unavailable in this content pack")
	return _configure_resources(library,bindings,rules)

func configure_alioth_attack(library: RefCounted,bindings: RefCounted) -> bool:
	error="";_state={}
	var rules:=Definitions.for_alioth(bindings)
	if rules.is_empty():return reject("Alioth freighter destruction is unavailable in this content pack")
	return _configure_resources(library,bindings,rules)

func configure_free(library: RefCounted,bindings: RefCounted,construction: RefCounted) -> bool:
	error="";_state={}
	if not construction is Construction:return reject("Ordinary freighter resources require their population")
	var packet: Dictionary=construction.snapshot()
	var data:=FreeLife.population(bindings,packet)
	if data.is_empty():return reject("Unsupported ordinary freighter resources")
	var variants:={}
	for row in packet.actors:
		if row.population_group!="freighter" or variants.has(row.actor_kind):continue
		var prepared: RefCounted=get_script().new()
		if not prepared._configure_resources(library,bindings,Definitions.for_free(bindings,row.actor_kind,packet.free_context)):return reject(prepared.error)
		variants[row.actor_kind]=prepared.snapshot()
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(data.campaign_cursor),"variants":variants,"free_context":packet.free_context.duplicate(true)}
	return true

func for_faction(faction: int) -> Dictionary:
	return _state.get("variants",{}).get(faction,{}).duplicate(true) if _state.has("variants") else snapshot()

func faction_owner(faction: int) -> RefCounted:
	var selected:=for_faction(faction)
	if selected.is_empty():return null
	var owner: RefCounted=get_script().new();owner._state=selected
	return owner

func _configure_resources(library: RefCounted,bindings: RefCounted,rules: Dictionary) -> bool:
	var effects:=Effects.new()
	if not effects.configure(library,bindings):return reject(effects.error)
	var path: String=bindings.resolve(int(rules.model_id),"mesh")
	if path!=rules.model_resource:return reject("Unsupported freighter destruction model")
	var bytes: PackedByteArray=library.read_resource(path,AEM.MAX_BYTES)
	var decoder:=AEM.new();var mesh:=decoder.decode(bytes)
	if mesh.is_empty() or mesh.get("version")!=4:return reject("Invalid freighter animation: "+decoder.error)
	var timing:=Timing.playback_range(mesh.surfaces)
	if timing.is_empty() or timing.end_ms<=timing.start_ms:return reject("Invalid freighter animation range")
	var cargo:=effects.read_cargo_model(library,bindings,rules)
	if cargo.is_empty():return reject(effects.error)
	var initial: Dictionary=bindings.material_for_mesh(path)
	var wreck: Dictionary=bindings.resolve_material(int(rules.wreck_material_id))
	if initial.get("id")!=int(rules.initial_material_id) or initial.get("render_type")!=28 or wreck.get("render_type")!=28:return reject("Unsupported freighter wreck materials")
	var volumes:=Volumes.new()
	var shapes:=volumes.decode(library.read_resource(rules.wreck_resource,Volumes.MAX_BYTES),int(rules.wreck_layout_id),int(rules.wreck_record_limit),float(rules.wreck_sphere_scale),float(rules.wreck_box_scale))
	if shapes.is_empty():return reject("Invalid freighter wreck volumes: "+volumes.error)
	_state=effects.snapshot()
	_state.merge({"campaign_cursor":int(rules.campaign_cursor),"model_scale":float(rules.get("model_scale",1.0)),"model":{"model_id":int(rules.model_id),"resource":path,"start_ms":timing.start_ms,"end_ms":timing.end_ms},
		"cargo_model":cargo,"wreck_shapes":shapes.get("shapes",[]),"wreck_source_offset":shapes.source_offset,"wreck_source_bytes":shapes.source_bytes,
		"initial_material":initial,"wreck_material":wreck})
	if _state.wreck_shapes.is_empty():_state={};return reject("Freighter wreck has no supported collision shapes")
	return true

func snapshot() -> Dictionary:return _state.duplicate(true)
func reject(message: String) -> bool:error=message;return false
