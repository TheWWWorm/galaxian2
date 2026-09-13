extends RefCounted
## Opening placement, drift and camera ownership before complete flight/AI.
## The caller owns elapsed simulation time, radio advancement and pause policy.
const EscapeFrame=preload("res://src/simulation/opening_escape_frame.gd")
const Staging = preload("res://src/simulation/opening_staging.gd")
const View = preload("res://src/simulation/opening_view.gd")
const Drift = preload("res://src/simulation/opening_drift.gd")
const Definitions = preload("res://src/content/opening_drift_definitions.gd")
var error := ""
var _staging: RefCounted
var _view: RefCounted
var _data := {}
var _elapsed_ms := -1
var _escape: RefCounted

func clear() -> void:
	error = ""
	_staging = null
	_view = null
	_data = {}
	_elapsed_ms = -1
	_escape=null

func configure(bindings: RefCounted, catalogues: RefCounted, content_id: String) -> bool:
	clear()
	if not Definitions.parameters(bindings.opening_drift): return reject("Opening scene motion requires source drift declarations")
	var staging := Staging.new()
	var view := View.new()
	if not staging.configure(bindings, catalogues, content_id): return reject(staging.error)
	if not view.configure(bindings): return reject(view.error)
	var ids := []
	for actor in staging.snapshot().actors: ids.append(actor.actor_id)
	for id in bindings.opening_drift.actor_ids:
		if int(id) not in ids: return reject("Opening drift actor is unavailable")
	_staging = staging
	_view = view
	_data = bindings.opening_drift.duplicate(true)
	return true

func configure_escape(bindings: RefCounted, library: RefCounted) -> bool:
	error=""
	if _staging==null or _elapsed_ms!=-1 or _escape!=null:return reject("Escape must join a fresh opening once")
	var escape:=EscapeFrame.new()
	if not escape.configure(bindings,library):return reject(escape.error)
	if escape.snapshot().binding_id!=_staging.snapshot().binding_id:return reject("Escape belongs to another opening")
	_escape=escape
	return true

func update(delta_ms: Variant, elapsed_ms: Variant, radio: Dictionary, player_motion: Dictionary = {}, escape_context: Dictionary = {}) -> bool:
	error = ""
	if _staging == null: return reject("Configure opening scene motion before updating")
	var stage: RefCounted = _staging.fork_for_frame()
	if not player_motion.is_empty() and not stage.adopt_player_motion(player_motion): return reject(stage.error)
	if not stage.update(radio): return reject(stage.error)
	var revealed: bool = stage.snapshot().formation_revealed and not _staging.snapshot().formation_revealed
	var drift := Drift.displacement(_data, elapsed_ms, _view.snapshot().shot.phase, revealed)
	if drift.has("error"): return reject(drift.error)
	if elapsed_ms < _elapsed_ms: return reject("Opening elapsed time regressed; configure a new scene for a new clock")
	if drift.apply and not stage.displace_actors(_data.actor_ids, drift.value): return reject(stage.error)
	var view: RefCounted=_view.fork_for_frame()
	var escape: RefCounted=_escape.fork_for_frame() if _escape!=null else null
	var active:=false
	if escape!=null and int(_view.snapshot().shot.phase)==4:
		var prior_view: Dictionary=_view.snapshot().view
		if not _escape.snapshot().camera.is_empty():prior_view=_escape.snapshot().camera.view
		if not escape.advance(delta_ms,radio,stage.snapshot().player_pose,prior_view,escape_context):return reject(escape.error)
		var escaped: Dictionary=escape.snapshot()
		active=escaped.phase>4
		if active and escaped.frame.player_pose_override!=null:
			var replacement: Dictionary=stage.snapshot()
			replacement.prior_pose=replacement.player_pose;replacement.pose=escaped.frame.player_pose_override
			if not stage.adopt_player_motion(replacement):return reject(stage.error)
	if not active and not view.update(delta_ms, radio, stage.snapshot()):return reject(view.error)
	_view=view;_escape=escape
	_staging = stage
	_elapsed_ms = int(elapsed_ms)
	return true

func escape_owner() -> RefCounted:
	return null if _escape==null else _escape.fork_for_frame()

func snapshot() -> Dictionary:
	if _staging == null: return {}
	var state:={"scene":_staging.snapshot(),"camera":_view.snapshot(),"elapsed_ms":_elapsed_ms}
	if _escape!=null:
		state.escape=_escape.snapshot()
		if not state.escape.camera.is_empty():state.camera=state.escape.camera
	return state

func adopt_actor_poses(combat: Dictionary) -> bool:
	error=""
	if _staging==null: return reject("Configure opening motion before adopting actor poses")
	var staged: RefCounted=_staging.fork_for_frame()
	if not staged.adopt_actor_poses(combat): return reject(staged.error)
	# The camera already consumed this frame's preceding actor poses. Store the
	# new motion for rendering and the next frame without recomputing that view.
	_staging=staged
	return true

func fork_for_frame() -> RefCounted:
	var copy: RefCounted = get_script().new()
	if _staging != null:
		copy._staging = _staging.fork_for_frame()
		copy._view = _view.fork_for_frame()
	if _escape!=null:copy._escape=_escape.fork_for_frame()
	copy._data = _data.duplicate(true)
	copy._elapsed_ms = _elapsed_ms
	return copy

func reject(message: String) -> bool:
	error = message
	return false
