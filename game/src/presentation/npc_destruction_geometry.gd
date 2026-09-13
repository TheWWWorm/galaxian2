extends Node3D
## Three-actor effect presentation with shared resources and atomic sampling.
## Intact-body visibility combines with the existing cinematic visibility gate.
const World = preload("res://src/simulation/opening_world_frame.gd")
const Models = preload("res://src/presentation/model_resources.gd")
const Resources = preload("res://src/content/npc_destruction_resources.gd")
const Effect = preload("res://src/presentation/npc_death_effect_geometry.gd")
const Library = preload("res://src/content/library.gd")
const Visuals = preload("res://src/content/visual_library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
var error := ""
var body_visibility: Array[bool]=[]
var effects: Array[Node3D]=[]

func build(world: RefCounted, library: RefCounted, visuals: RefCounted, bindings: RefCounted, quality := "high") -> bool:
	clear()
	if not world is World or world.snapshot().is_empty(): return reject("NPC destruction geometry requires a configured world")
	if not library is Library or not visuals is Visuals or not bindings is Bindings:
		return reject("NPC destruction geometry requires prepared content resources")
	var state: Dictionary=world.snapshot()
	if state.get("base_content_id")!=bindings.base_content_id or state.get("binding_id")!=bindings.binding_id:
		return reject("NPC destruction geometry belongs to another world identity")
	var models := Models.new()
	if not models.prepare(Resources.PATHS,library,visuals,bindings,quality,false,true): return reject(models.error)
	for id in 3:
		var effect := Effect.new();effects.append(effect);add_child(effect)
		if not effect.build(library,visuals,bindings,world.npc_destruction_owner(id),quality,models):
			models.clear();return reject(effect.error)
		body_visibility.append(true)
	models.clear()
	return true

func apply_world(world: RefCounted, camera: Transform3D, parent_rgba: PackedByteArray, global_tint: Vector4, darken: Variant) -> bool:
	error=""
	if effects.size()!=3 or not world is World: return fail("Build NPC destruction geometry before presenting the world")
	var prepared := []
	for id in 3:
		var candidate: Dictionary=effects[id].prepare_effect(world.npc_destruction_owner(id),camera,parent_rgba,global_tint,darken)
		if candidate.is_empty(): return fail(effects[id].error)
		prepared.append(candidate)
	for id in 3:
		effects[id].commit_effect(prepared[id]);body_visibility[id]=prepared[id].body_visible
	return true

func clear() -> void:
	for effect in effects:
		if is_instance_valid(effect): effect.free()
	effects.clear();body_visibility.clear();error=""

func reject(message: String) -> bool:
	clear();return fail(message)

func fail(message: String) -> bool:
	error=message;return false
