extends RefCounted
## Camera choreography through the first player-follow handoff. The scene owns
## ships and the radio; this director cannot complete missions or start combat.
const Definitions = preload("res://src/content/opening_camera_definitions.gd")
const Staging = preload("res://src/content/opening_staging_definitions.gd")
const Poses = preload("res://src/simulation/opening_staging.gd")
const CameraView = preload("res://src/simulation/camera_view.gd")
const Dialogue = preload("res://src/content/dialogue_definitions.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
var error := ""
var _state := {}
var _data := {}
var _formation := {}
var _event_count := 0
var _fixed_refresh := {}
var _view_translation: Variant = null

func clear() -> void:
	error = ""
	_state = {}
	_data = {}
	_formation = {}
	_event_count = 0
	_fixed_refresh = {}
	_view_translation = null

func configure(bindings: RefCounted) -> bool:
	clear()
	if not Definitions.parameters(bindings.opening_camera) or not Staging.parameters(bindings.opening_staging): return fail("Opening camera requires source camera and staging declarations")
	if not Dialogue.valid_parameters(bindings.opening_dialogue): return fail("Opening camera requires source radio declarations")
	var data: Dictionary = bindings.opening_camera
	var formation: Dictionary = bindings.opening_staging.formation
	_event_count = bindings.opening_dialogue.events.size()
	if formation.after_event_finished >= data.actor_cut.after_event_finished or data.pan.follow_player_after_event_finished >= _event_count: return fail("Opening camera gates are outside the supported radio order")
	if bindings.base_content_id.is_empty() or bindings.binding_id.is_empty(): return fail("Opening camera content identity is unavailable")
	_data = data.duplicate(true)
	_formation = formation.duplicate(true)
	_state = {"base_content_id": bindings.base_content_id, "binding_id": bindings.binding_id,
		"phase": 0, "mode": "fixed_eye", "target": "player", "actor_id": -1,
		"eye": Poses.vec(bindings.opening_staging.initial.camera_position_parameter),
		"inherit_target_up": data.inherit_target_up}
	return true

func advance(delta_ms: Variant, radio: Dictionary) -> bool:
	error = ""
	if _state.is_empty(): return reject("Configure opening camera before advancing")
	if not Numbers.integer(delta_ms, 0, 2147483647): return reject("Invalid opening camera frame time")
	if not same_content(radio): return reject("Radio belongs to another opening content identity")
	var finished: Variant = radio.get("finished")
	if not finished is Array or finished.size() != _event_count: return reject("Opening camera requires radio completion state")
	for flag in finished:
		if not flag is bool: return reject("Invalid opening radio completion flag")
	var gates := [int(_formation.after_event_finished), int(_data.actor_cut.after_event_finished), int(_data.pan.engagement_after_event_finished), int(_data.pan.follow_player_after_event_finished)]
	for phase in int(_state.phase):
		if not finished[gates[phase]]: return reject("Opening radio regressed behind the camera phase")
	# Source cue checks do not depend on positive elapsed time. Pause ownership
	# belongs to the caller, which must suspend updates while a pause is active.
	if _state.phase == 4:
		_fixed_refresh = {}
		_view_translation = null
		return true
	var next := _state.duplicate(true)
	var refresh := {}
	var translation: Variant = null
	if next.phase == 0:
		if finished[gates[0]]:
			next.eye = Poses.vec(_formation.camera_position_parameter)
			next.phase = 1
			translation = next.eye
		# Formation is a separate update even when later cues are already set.
	elif next.phase >= 1:
		if next.phase == 1 and finished[gates[1]]:
			next.phase = 2
			next.target = "actor"
			next.actor_id = int(_data.actor_cut.actor_id)
			next.eye = Poses.vec(_data.actor_cut.eye)
		if next.phase == 2 or next.phase == 3:
			# The cut enters the pan in the same frame. Pan before consuming the
			# next cue, and never move twice when phase 2 becomes phase 3.
			next.eye += Poses.vec(_data.pan.velocity_per_ms) * float(delta_ms)
			if not next.eye.is_finite(): return reject("Opening camera movement overflowed")
			# The source pan setter immediately resolves a fixed-eye view before
			# processing the next cue. Retain that target even at the follow cut.
			refresh = next.duplicate(true)
			if finished[gates[int(next.phase)]]:
				next.phase += 1
				if next.phase == 4:
					next.mode = "follow"
					next.target = "player"
					next.actor_id = -1
	_state = next
	_fixed_refresh = refresh
	_view_translation = translation
	return true

func fixed_refresh() -> Dictionary:
	return _fixed_refresh.duplicate(true)

func view_translation() -> Variant:
	return _view_translation

func fork_for_frame() -> RefCounted:
	# A prospective frame can fail while resolving scene poses. The owner only
	# adopts this director after the corresponding rig update succeeds.
	var copy = get_script().new()
	copy._state = _state.duplicate(true)
	copy._data = _data.duplicate(true)
	copy._formation = _formation.duplicate(true)
	copy._event_count = _event_count
	copy._fixed_refresh = _fixed_refresh.duplicate(true)
	copy._view_translation = _view_translation
	return copy

func view(scene: Dictionary) -> Dictionary:
	if _state.is_empty(): return {"error": "Configure opening camera before resolving its view"}
	if not same_content(scene): return {"error": "Scene belongs to another opening content identity"}
	if _state.mode != "fixed_eye": return {"error": "Opening camera handoff requires the player follow camera"}
	var resolved := target_pose(_state, scene)
	if resolved.has("error"): return resolved
	return CameraView.fixed_eye(_state.eye, resolved.target, _state.inherit_target_up)

static func target_pose(shot: Dictionary, scene: Dictionary) -> Dictionary:
	if scene.get("base_content_id") != shot.get("base_content_id") or scene.get("binding_id") != shot.get("binding_id"): return {"error": "Scene belongs to another opening content identity"}
	if shot.get("target") not in ["player", "actor"]: return {"error": "Unknown camera target selector"}
	var target: Variant = scene.get("player_pose")
	if shot.target == "actor":
		if not Numbers.integer(shot.get("actor_id"), 0, 2): return {"error": "Invalid opening camera actor selector"}
		target = null
		var actors: Variant = scene.get("actors")
		if not actors is Array: return {"error": "Opening camera actor poses are unavailable"}
		var found := false
		for actor in actors:
			if not actor is Dictionary: return {"error": "Invalid opening camera actor state"}
			if actor.get("actor_id") == shot.actor_id:
				if found: return {"error": "Duplicate opening camera target"}
				found = true
				target = actor.get("pose")
	if not target is Transform3D: return {"error": "Opening camera target pose is unavailable"}
	return {"target": target}

func same_content(value: Dictionary) -> bool:
	return value.get("base_content_id") == _state.base_content_id and value.get("binding_id") == _state.binding_id

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func reject(message: String) -> bool:
	error = message
	return false

func fail(message: String) -> bool:
	clear()
	error = message
	return false
