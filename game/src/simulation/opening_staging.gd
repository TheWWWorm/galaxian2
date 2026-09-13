extends RefCounted
## Authored initial placement and the first formation reveal. Further cinematic
## phases, camera view calculation, AI and flight-control ownership remain with
## the mission controller. This component never advances or completes a mission.
const Actors = preload("res://src/simulation/opening_actor_state.gd")
const Definitions = preload("res://src/content/opening_staging_definitions.gd")
const Dialogue = preload("res://src/content/dialogue_definitions.gd")
var error := ""
var _state := {}
var _formation := {}
var _event_count := 0

func clear() -> void:
	error = ""
	_state = {}
	_formation = {}
	_event_count = 0

func configure(bindings: RefCounted, catalogues: RefCounted, content_id: String) -> bool:
	clear()
	var actors := Actors.new()
	if not actors.configure(bindings, catalogues, content_id): return fail(actors.error)
	var data: Dictionary = bindings.opening_staging
	if not Definitions.parameters(data): return fail("Opening staging is unavailable")
	if not Dialogue.valid_parameters(bindings.opening_dialogue): return fail("Opening staging requires source radio declarations")
	_event_count = bindings.opening_dialogue.events.size()
	if int(data.formation.after_event_finished) >= _event_count: return fail("Formation gate is outside the opening radio sequence")
	var state := actors.snapshot()
	if state.actors.size() < data.initial.hidden_actor_ids.size(): return fail("Opening formation requires its authored actors")
	for id in data.initial.hidden_actor_ids:
		state.actors[int(id)].visible = false
	state["player_pose"] = pose(data.initial.player_position, data.initial.player_forward, data.initial.player_up)
	state["camera_position_parameter"] = vec(data.initial.camera_position_parameter)
	state["formation_revealed"] = false
	_state = state
	_formation = data.formation.duplicate(true)
	return true

func update(radio: Dictionary) -> bool:
	error = ""
	if _state.is_empty(): return reject("Configure opening staging before updating")
	if radio.get("base_content_id") != _state.base_content_id or radio.get("binding_id") != _state.binding_id: return reject("Radio belongs to another opening content identity")
	var finished: Variant = radio.get("finished")
	if not finished is Array or finished.size() != _event_count: return reject("Opening radio completion state is unavailable")
	for value in finished:
		if not value is bool: return reject("Invalid opening radio completion state")
	if _state.formation_revealed or not finished[int(_formation.after_event_finished)]: return true
	# Preserve the current heading: the source relocates the player without
	# assigning a new orientation at this boundary.
	_state.player_pose.origin = vec(_formation.player_position)
	_state.camera_position_parameter = vec(_formation.camera_position_parameter)
	for row in _formation.actors:
		var actor: Dictionary = _state.actors[int(row.actor_id)]
		actor.position = vec(row.position)
		actor["pose"] = pose(row.position, row.forward, row.up)
		actor.visible = row.visible
	_state.formation_revealed = true
	return true

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func adopt_player_motion(motion: Dictionary) -> bool:
	error=""
	if _state.is_empty() or motion.get("base_content_id")!=_state.base_content_id or motion.get("binding_id")!=_state.binding_id:
		return reject("Player motion belongs to another opening")
	if motion.get("prior_pose")!=_state.player_pose: return reject("Player motion requires the current scene pose")
	var next: Variant=motion.get("pose")
	if not next is Transform3D or not next.is_finite() or not next.basis.is_equal_approx(next.basis.orthonormalized()) or next.basis.determinant()<=0.0:
		return reject("Player motion has an invalid pose")
	_state.player_pose=next
	return true

func adopt_actor_poses(combat: Dictionary) -> bool:
	error=""
	if _state.is_empty() or combat.get("base_content_id")!=_state.base_content_id or combat.get("binding_id")!=_state.binding_id:
		return reject("Actor motion belongs to another opening")
	var actors: Variant=combat.get("actors")
	if not actors is Array or actors.size()!=_state.actors.size(): return reject("Actor motion changed the opening population")
	var next := _state.duplicate(true)
	for id in actors.size():
		var actor: Variant=actors[id]
		if not actor is Dictionary or actor.get("actor_id")!=id or actor.get("hull_catalogue_id")!=next.actors[id].hull_catalogue_id:
			return reject("Actor motion changed an opening identity")
		var actor_pose: Variant=actor.get("pose")
		if not actor_pose is Transform3D or not actor_pose.is_finite() or actor.get("position")!=actor_pose.origin:
			return reject("Actor motion has an invalid pose")
		next.actors[id].pose=actor_pose;next.actors[id].position=actor_pose.origin
	_state=next
	return true

func fork_for_frame() -> RefCounted:
	var copy = get_script().new()
	copy._state = _state.duplicate(true)
	copy._formation = _formation.duplicate(true)
	copy._event_count = _event_count
	return copy

func displace_actors(ids: Array, offset: Vector3) -> bool:
	error = ""
	if _state.is_empty() or not offset.is_finite(): return reject("Invalid opening actor displacement")
	var next := _state.duplicate(true)
	for id in ids:
		var found := false
		for actor in next.actors:
			if actor.actor_id != id: continue
			if found: return reject("Duplicate opening actor")
			found = true
			actor.position += offset
			if not actor.position.is_finite(): return reject("Opening actor displacement overflowed")
			if actor.has("pose"): actor.pose.origin = actor.position
		if not found: return reject("Opening actor displacement target is unavailable")
	_state = next
	return true

static func vec(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

static func pose(position: Array, forward: Array, up: Array) -> Transform3D:
	var f := vec(forward)
	var u := vec(up)
	return Transform3D(Basis(u.cross(f), u, f), vec(position))

func reject(message: String) -> bool:
	error = message
	return false

func fail(message: String) -> bool:
	clear()
	error = message
	return false
