extends RefCounted
## Fresh ordinary opening with source-ordered geometry detail selection.
## Preferences and suppression ownership remain explicit caller inputs.
const Timeline = preload("res://src/simulation/opening_timeline.gd")
const Group = preload("res://src/presentation/ship_detail_group.gd")
const Loadout = preload("res://src/simulation/opening_loadout.gd")
var error := ""
var _timeline: RefCounted
var _group: RefCounted
var _reference := Vector3.ZERO

func configure(bindings: RefCounted, catalogues: RefCounted, library: RefCounted, line_counts: Array, detail: Variant, difficulty: Variant = null) -> bool:
	clear()
	var timeline := Timeline.new();var group := Group.new();var loadout := Loadout.new()
	if not timeline.configure(bindings,catalogues,library,line_counts,difficulty): return reject(timeline.error)
	if not loadout.configure(bindings,catalogues,library.manifest.get("content_id","")): return reject(loadout.error)
	var scene: Dictionary = timeline.snapshot().scene
	var ships := {"player":loadout.snapshot().ship_id}
	for actor in scene.actors: ships[actor.actor_id]=actor.hull_catalogue_id
	if not group.configure(bindings,ships): return reject(group.error)
	# Both source startup paths allocate/select a fresh renderer camera with an
	# identity transform before staging and the constructor's immediate refresh.
	# The authored camera-position parameter has not reached that renderer yet.
	if not group.refresh(positions(scene),Vector3.ZERO,detail): return reject(group.error)
	_timeline=timeline;_group=group
	return true

func configure_escape(bindings: RefCounted, library: RefCounted) -> bool:
	error=""
	if _timeline==null or _timeline.snapshot().elapsed_ms!=0:return reject("Escape requires a fresh opening timeline")
	var next: RefCounted=_timeline.fork_for_frame()
	if not next.configure_escape(bindings,library):return reject(next.error)
	_timeline=next
	return true

func update(delta_ms: Variant, present_radio: Variant, blocked: Variant, detail_suppressed: Variant, detail: Variant) -> bool:
	return _advance(delta_ms,present_radio,blocked,detail_suppressed,detail,false)

func begin_frame(delta_ms: Variant, detail_suppressed: Variant, detail: Variant, player_motion: Dictionary = {}, escape_context: Dictionary = {}) -> bool:
	return _advance(delta_ms,false,false,detail_suppressed,detail,true,player_motion,escape_context)

func _advance(delta_ms: Variant, present_radio: Variant, blocked: Variant, detail_suppressed: Variant, detail: Variant, defer_radio: bool, player_motion: Dictionary = {}, escape_context: Dictionary = {}) -> bool:
	error=""
	if _timeline==null: return reject("Configure the opening detail timeline before updating")
	if not detail_suppressed is bool: return reject("Opening detail requires explicit suppression state")
	var timeline: RefCounted = _timeline.fork_for_frame()
	var group: RefCounted = _group.fork_for_frame()
	var before: Dictionary = _timeline.snapshot().scene
	# Validate/advance the detached timeline first; group selection below still
	# consumes the preceding frame's world positions and renderer reference.
	if defer_radio:
		if not timeline.begin_frame(delta_ms,player_motion,escape_context): return reject(timeline.error)
	elif not timeline.update(delta_ms,present_radio,blocked): return reject(timeline.error)
	var next_reference := _reference
	if not blocked:
		if not group.update(delta_ms,positions(before),_reference,detail,detail_suppressed): return reject(group.error)
		var state: Dictionary = timeline.snapshot()
		if state.scene.formation_revealed and not before.formation_revealed:
			# Formation refresh is independent of the ordinary world suppression
			# and occurs after the source's immediate renderer translation.
			if not group.refresh(positions(state.scene),state.scene.camera_position_parameter,detail): return reject(group.error)
		if not state.camera.view.is_empty(): next_reference=state.camera.view.eye
	_timeline=timeline;_group=group;_reference=next_reference
	return true

func finish_frame(present_radio: Variant) -> bool:
	error=""
	if _timeline==null: return reject("Configure opening detail before finishing a frame")
	var timeline: RefCounted=_timeline.fork_for_frame()
	if not timeline.finish_frame(present_radio): return reject(timeline.error)
	_timeline=timeline
	return true

func combat_owner() -> RefCounted:
	return null if _timeline==null else _timeline.combat_owner()

func adopt_contact_pass(combat: RefCounted) -> bool:
	error=""
	if _timeline==null: return reject("Configure opening detail before weapon contacts")
	var timeline: RefCounted=_timeline.fork_for_frame()
	if not timeline.adopt_contact_pass(combat): return reject(timeline.error)
	_timeline=timeline
	return true

func adopt_combat_pass(combat: RefCounted) -> bool:
	error=""
	if _timeline==null: return reject("Configure opening detail before adopting actor motion")
	var timeline: RefCounted=_timeline.fork_for_frame()
	if not timeline.adopt_combat_pass(combat): return reject(timeline.error)
	_timeline=timeline
	return true

func escape_owner() -> RefCounted:
	return null if _timeline==null else _timeline.escape_owner()

func snapshot() -> Dictionary:
	if _timeline==null: return {}
	var state: Dictionary = _timeline.snapshot()
	state.scene.ship_detail=_group.snapshot()
	state.detail_reference=_reference
	return state

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	# update() forks both private owners before mutating them.
	copy._timeline=_timeline;copy._group=_group;copy._reference=_reference
	return copy

static func positions(scene: Dictionary) -> Dictionary:
	var result := {"player":scene.player_pose.origin}
	for actor in scene.actors: result[actor.actor_id]=actor.position
	return result

func clear() -> void:
	error="";_timeline=null;_group=null;_reference=Vector3.ZERO

func reject(message: String) -> bool:
	error=message
	return false
