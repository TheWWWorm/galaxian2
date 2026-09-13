extends RefCounted
## Declarative initial actor state, before cinematic visibility/pose changes.
## No AI, damage, maximum hull, rewards or mission completion are inferred here.
const Definitions = preload("res://src/content/opening_actor_definitions.gd")
const Library = preload("res://src/content/library.gd")
var error := ""
var _state := {}

func clear() -> void:
	error = ""
	_state = {}

func configure(bindings: RefCounted, catalogues: RefCounted, content_id: String) -> bool:
	clear()
	if bindings == null or catalogues == null or not Library.valid_hash(content_id) or bindings.base_content_id != content_id or catalogues.content_id != content_id or not Library.valid_hash(bindings.binding_id): return fail("Opening actors require matching content and bindings")
	var data: Dictionary = bindings.opening_actors
	if not Definitions.parameters(data): return fail("Opening actors have no supported declarations")
	var ships: Variant = catalogues.tables.get("ships")
	if not ships is Array: return fail("Opening actors require the source hull catalogue")
	var actors := []
	for row in data.actors:
		var hull_id := int(row.hull_catalogue_id)
		if hull_id >= ships.size(): return fail("Opening actor hull is outside this edition's catalogue")
		var model: String = bindings.resolve_ship_model(hull_id)
		if model.is_empty(): return fail(bindings.error)
		actors.append({"actor_id": int(row.actor_id), "hull_catalogue_id": hull_id, "hull_resource": model,
			"actor_kind": int(row.actor_kind), "current_hull": int(row.current_hull_override),
			"position": Vector3(row.position[0], row.position[1], row.position[2])})
	_state = {"base_content_id": content_id, "binding_id": bindings.binding_id, "actors": actors,
		"player_current_hull_override": int(data.player_current_hull_override)}
	return true

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func fail(message: String) -> bool:
	error = message
	_state = {}
	return false
