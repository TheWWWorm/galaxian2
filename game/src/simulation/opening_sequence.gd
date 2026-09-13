extends RefCounted
## Ordinary opening update followed by radio presentation. The native scene sees
## the preceding presentation's radio flags; newly finished cues affect the next
## scene update. Clock origin, pause and radio suppression belong to the caller.
const CombatGroup = preload("res://src/simulation/opening_combat_group.gd")
const Motion = preload("res://src/simulation/opening_scene_motion.gd")
const Radio = preload("res://src/simulation/radio_sequence.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
var error := ""
var _motion: RefCounted
var _radio: RefCounted
var _changes := []
var _combat: RefCounted
var _pending_elapsed := -1

func clear() -> void:
	error = ""
	_motion = null
	_radio = null
	_combat = null
	_changes = []
	_pending_elapsed = -1

func configure(bindings: RefCounted, catalogues: RefCounted, library: RefCounted, source_line_counts: Array, difficulty: Variant = null) -> bool:
	clear()
	var motion := Motion.new()
	var radio := Radio.new()
	if not motion.configure(bindings,catalogues,library.manifest.get("content_id", "")): return reject(motion.error)
	if not radio.configure(bindings,library,source_line_counts): return reject(radio.error)
	var combat: RefCounted
	if difficulty != null:
		var initial: Variant = bindings.opening_actors.get("npc_initialization",{})
		if not initial is Dictionary: return reject("Invalid opening NPC initialization scope")
		var activation: Variant = initial.get("activation",{})
		if not activation is Dictionary: return reject("Invalid opening NPC activation scope")
		if not activation.is_empty():
			combat = CombatGroup.new()
			if not combat.configure(bindings,catalogues,difficulty): return reject(combat.error)
			var state: Dictionary = motion.snapshot()
			if not combat.update(state.scene,state.camera.shot.phase,radio.snapshot()): return reject(combat.error)
	_motion = motion
	_radio = radio
	_combat = combat
	return true

func configure_escape(bindings: RefCounted, library: RefCounted) -> bool:
	error=""
	if _motion==null or _pending_elapsed!=-1:return reject("Escape requires a fresh opening timeline")
	var next: RefCounted=_motion.fork_for_frame()
	if not next.configure_escape(bindings,library):return reject(next.error)
	if _combat==null:return reject("Escape requires the source encounter owners")
	var combat: RefCounted=_combat.fork_for_frame()
	if not combat.configure_escape(bindings):return reject(combat.error)
	_combat=combat
	_motion=next
	return true

func update(delta_ms: Variant, elapsed_ms: Variant, present_radio: Variant) -> bool:
	error=""
	var staged: RefCounted=fork_for_frame()
	if not staged.begin_frame(delta_ms,elapsed_ms) or not staged.finish_frame(present_radio): return reject(staged.error)
	_motion=staged._motion;_radio=staged._radio;_combat=staged._combat
	_changes=staged._changes;_pending_elapsed=staged._pending_elapsed
	return true

func begin_frame(delta_ms: Variant, elapsed_ms: Variant, player_motion: Dictionary = {}, escape_context: Dictionary = {}) -> bool:
	error = ""
	if _motion == null: return reject("Configure the opening sequence before updating")
	if _pending_elapsed>=0: return reject("Finish the pending opening frame before starting another")
	if not Numbers.integer(elapsed_ms,0,2147483647): return reject("Opening sequence requires valid elapsed time")
	var motion: RefCounted = _motion.fork_for_frame()
	if not motion.update(delta_ms,elapsed_ms,_radio.snapshot(),player_motion,escape_context): return reject(motion.error)
	var combat: RefCounted = _combat.fork_for_frame() if _combat != null else null
	var state: Dictionary = motion.snapshot()
	if combat != null and not combat.update(state.scene,state.camera.shot.phase,_radio.snapshot()): return reject(combat.error)
	_motion=motion;_combat=combat;_changes=[];_pending_elapsed=int(elapsed_ms)
	return true

func finish_frame(present_radio: Variant) -> bool:
	error=""
	if _pending_elapsed<0 or not present_radio is bool: return reject("Begin a frame and select explicit radio presentation before finishing")
	var radio: RefCounted=_radio.fork_for_frame()
	var state: Dictionary=_motion.snapshot()
	var changes := []
	if present_radio:
		var hulls := {}
		for actor in state.scene.actors: hulls[actor.actor_id] = actor.current_hull
		if _combat != null:
			for actor in _combat.snapshot().actors: hulls[actor.actor_id]=actor.vitals.hull
		changes = radio.step(_pending_elapsed,hulls,int(state.camera.shot.phase))
		if not radio.error.is_empty(): return reject(radio.error)
	_radio = radio
	_changes = changes
	_pending_elapsed=-1
	return true

func combat_owner() -> RefCounted:
	return null if _combat==null else _combat.fork_for_frame()

func adopt_combat_pass(combat: RefCounted) -> bool:
	error=""
	if _pending_elapsed<0 or not combat is CombatGroup: return reject("Actor motion must belong to the pending opening frame")
	return _adopt_combat(combat)

func adopt_contact_pass(combat: RefCounted) -> bool:
	error=""
	if _pending_elapsed>=0 or not combat is CombatGroup or _combat==null: return reject("Weapon contacts must precede the opening controller")
	var before: Array=_combat.snapshot().actors
	var after: Array=combat.snapshot().actors
	if before.size()!=after.size(): return reject("Contacts changed the opening population")
	for i in before.size():
		if before[i].pose!=after[i].pose: return reject("Contacts moved an opening actor")
	return _adopt_combat(combat)

func _adopt_combat(combat: RefCounted) -> bool:
	var state: Dictionary=combat.snapshot()
	var prior: Dictionary=_combat.snapshot() if _combat!=null else {}
	if prior.is_empty() or state.get("phase")!=prior.phase or state.get("activated")!=prior.activated:
		return reject("Actor pass changed cinematic activation")
	var motion: RefCounted=_motion.fork_for_frame()
	if not motion.adopt_actor_poses(state): return reject(motion.error)
	_motion=motion;_combat=combat.fork_for_frame()
	return true

func escape_owner() -> RefCounted:
	return null if _motion==null else _motion.escape_owner()

func snapshot() -> Dictionary:
	if _motion == null: return {}
	var state: Dictionary = _motion.snapshot()
	if _combat != null:
		state.combat = _combat.snapshot()
		for actor in state.combat.actors: state.scene.actors[actor.actor_id].current_hull=actor.vitals.hull
	state.radio = _radio.snapshot()
	state.radio_changes = _changes.duplicate(true)
	return state

func fork_for_frame() -> RefCounted:
	var copy: RefCounted = get_script().new()
	if _motion != null:
		copy._motion = _motion.fork_for_frame()
		copy._radio = _radio.fork_for_frame()
	if _combat != null: copy._combat = _combat.fork_for_frame()
	copy._changes = _changes.duplicate(true)
	copy._pending_elapsed=_pending_elapsed
	return copy

func reject(message: String) -> bool:
	error = message
	return false
