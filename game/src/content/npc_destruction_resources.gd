extends RefCounted
## Authored explosion models and ranges; no death or mission state is inferred.
const Definitions = preload("res://src/content/npc_destruction_definitions.gd")
const FullHold = preload("res://src/content/full_hold_destruction_definitions.gd")
const Training = preload("res://src/content/combat_training_destruction_definitions.gd")
const AEM = preload("res://src/content/aem.gd")
const Timing = preload("res://src/content/scenery_effect_resources.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Library = preload("res://src/content/library.gd")
const PATHS := ["resources/data/assets/main/3d/meshes/fx/explosion_anim_lookat_alpha.aem",
	"resources/data/assets/main/3d/meshes/fx/explosion_anim_lookat_add.aem",
	"resources/data/assets/main/3d/meshes/fx/explosion_debris_anim_add.aem"]
var error := ""
var _state := {}

func configure(library: RefCounted, bindings: RefCounted) -> bool:
	clear()
	if not library is Library or not bindings is Bindings: return reject("Explosion resources require a content library and resource bindings")
	if not Library.valid_hash(bindings.base_content_id) or not Library.valid_hash(bindings.binding_id) or library.manifest.get("content_id")!=bindings.base_content_id: return reject("Explosion resources require one base content identity")
	var parameters: Variant=bindings.opening_actors.get("npc_initialization",{}).get("destruction")
	if not Definitions.parameters(parameters): return reject("NPC destruction declarations are unavailable")
	var ids: Array=parameters.model_ids.duplicate();ids.append(parameters.fragment_model_id)
	var models := []
	for i in ids.size():
		var path: String=bindings.resolve(int(ids[i]),"mesh")
		if path!=PATHS[i]: return reject("Unsupported NPC explosion resource mapping")
		var reader := AEM.new()
		var bytes: PackedByteArray=library.read_resource(path,AEM.MAX_BYTES)
		if bytes.is_empty(): return reject(path.get_file()+": "+library.error)
		var mesh: Dictionary=reader.decode(bytes)
		if mesh.is_empty(): return reject(path.get_file()+": "+reader.error)
		if mesh.version!=4: return reject("Unsupported NPC explosion mesh version")
		var timing := Timing.playback_range(mesh.surfaces)
		if timing.is_empty(): return reject("Unsupported NPC explosion animation timing")
		models.append({"model_id":int(ids[i]),"resource":path,"start_ms":timing.start_ms,"end_ms":timing.end_ms})
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"models":models,"duration_ms":models[0].end_ms}
	return true

func configure_full_hold(library: RefCounted, bindings: RefCounted) -> bool:
	clear()
	if not bindings is Bindings or not FullHold.parameters(bindings.full_hold_destruction):return reject("Cargo destruction resources require their second-trip declarations")
	# Prepare all resources as a candidate; a missing container must not leave a
	# seemingly complete explosion pack that silently discards generated cargo.
	var prepared: RefCounted=get_script().new()
	if not prepared.configure(library,bindings):return reject(prepared.error)
	var data: Dictionary=bindings.full_hold_destruction
	var model: Dictionary=prepared.read_cargo_model(library,bindings,data)
	if model.is_empty():return reject(prepared.error)
	_state=prepared.snapshot()
	_state.cargo_model=model
	return true

func configure_combat_training(library: RefCounted, bindings: RefCounted) -> bool:
	clear()
	if not bindings is Bindings or not Training.parameters(bindings.combat_training_destruction):return reject("Training destruction resources require their verified declarations")
	var prepared: RefCounted=get_script().new()
	if not prepared.configure(library,bindings):return reject(prepared.error)
	var models:=[]
	for row in bindings.combat_training_destruction.actors:
		var model: Dictionary=prepared.read_cargo_model(library,bindings,row)
		if model.is_empty():return reject(prepared.error)
		models.append(model)
	_state=prepared.snapshot();_state.cargo_models=models;_state.campaign_cursor=7
	return true

func read_cargo_model(library: RefCounted, bindings: RefCounted, data: Dictionary) -> Dictionary:
	var path: String=bindings.resolve(int(data.cargo_model_id),"mesh")
	if path!=data.cargo_model_resource:reject("Unsupported cargo model mapping");return {}
	var bytes: PackedByteArray=library.read_resource(path,AEM.MAX_BYTES)
	if bytes.is_empty():reject(library.error);return {}
	var reader:=AEM.new();var mesh: Dictionary=reader.decode(bytes)
	if mesh.is_empty():reject(reader.error);return {}
	if mesh.version!=4:reject("Unsupported cargo mesh version");return {}
	return {"model_id":int(data.cargo_model_id),"resource":path}

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._state=_state.duplicate(true)
	return copy

func clear() -> void:
	error="";_state={}

func reject(message: String) -> bool:
	error=message
	return false
