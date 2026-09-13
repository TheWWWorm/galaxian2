extends RefCounted
## Fresh-opening simulation time. Save restoration, accelerated time and world
## transitions require their own verified policies; they cannot reset this clock.
const Sequence = preload("res://src/simulation/opening_sequence.gd")
const Definitions = preload("res://src/content/opening_clock_definitions.gd")
const FrameClock = preload("res://src/simulation/frame_clock.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
var error := ""
var _sequence: RefCounted
var _elapsed_ms := 0
var _max_ms := 0
var _changes := []

func clear() -> void:
	error = ""
	_sequence = null
	_elapsed_ms = 0
	_max_ms = 0
	_changes = []

func configure(bindings: RefCounted, catalogues: RefCounted, library: RefCounted, source_line_counts: Array, difficulty: Variant = null) -> bool:
	clear()
	if not Definitions.parameters(bindings.opening_clock) or not FrameClock.valid_parameters(bindings.frame_clock):
		return reject("Fresh opening requires verified clock declarations")
	var sequence := Sequence.new()
	if not sequence.configure(bindings,catalogues,library,source_line_counts,difficulty): return reject(sequence.error)
	_elapsed_ms = int(bindings.opening_clock.initial_elapsed_ms)
	_max_ms = int(bindings.frame_clock.max_frame_milliseconds)
	_sequence = sequence
	return true

func configure_escape(bindings: RefCounted, library: RefCounted) -> bool:
	error=""
	if _sequence==null or _elapsed_ms!=0:return reject("Escape requires a fresh opening timeline")
	var next: RefCounted=_sequence.fork_for_frame()
	if not next.configure_escape(bindings,library):return reject(next.error)
	_sequence=next
	return true

func update(delta_ms: Variant, present_radio: Variant, blocked: Variant) -> bool:
	error = ""
	if _sequence == null: return reject("Configure a fresh opening timeline before updating")
	if not Numbers.integer(delta_ms,0,_max_ms) or not present_radio is bool or not blocked is bool:
		return reject("Invalid ordinary opening frame or pause state")
	if blocked:
		_changes = []
		return true
	var staged: RefCounted=fork_for_frame()
	if not staged.begin_frame(delta_ms) or not staged.finish_frame(present_radio): return reject(staged.error)
	_sequence=staged._sequence;_elapsed_ms=staged._elapsed_ms;_changes=staged._changes
	return true

func begin_frame(delta_ms: Variant, player_motion: Dictionary = {}, escape_context: Dictionary = {}) -> bool:
	error=""
	if _sequence==null or not Numbers.integer(delta_ms,0,_max_ms): return reject("Invalid opening frame duration")
	var next := _elapsed_ms+int(delta_ms)
	if next > 2147483647: return reject("Opening time exceeds the supported radio interval")
	# Increment precedes actor drift and controller work in both source editions.
	# Sequence failure leaves its state unchanged, so the clock commits afterwards.
	if not _sequence.begin_frame(delta_ms,next,player_motion,escape_context): return reject(_sequence.error)
	_elapsed_ms = next
	_changes=[]
	return true

func finish_frame(present_radio: Variant) -> bool:
	error=""
	if _sequence==null: return reject("Configure opening time before finishing a frame")
	if not _sequence.finish_frame(present_radio): return reject(_sequence.error)
	_changes=_sequence.snapshot().radio_changes
	return true

func combat_owner() -> RefCounted:
	return null if _sequence==null else _sequence.combat_owner()

func adopt_contact_pass(combat: RefCounted) -> bool:
	error=""
	if _sequence==null: return reject("Configure opening time before weapon contacts")
	if not _sequence.adopt_contact_pass(combat): return reject(_sequence.error)
	return true

func adopt_combat_pass(combat: RefCounted) -> bool:
	error=""
	if _sequence==null: return reject("Configure opening time before adopting actor motion")
	if not _sequence.adopt_combat_pass(combat): return reject(_sequence.error)
	return true

func escape_owner() -> RefCounted:
	return null if _sequence==null else _sequence.escape_owner()

func snapshot() -> Dictionary:
	if _sequence == null: return {}
	var state: Dictionary = _sequence.snapshot()
	state.elapsed_ms = _elapsed_ms
	state.radio_changes = _changes.duplicate(true)
	return state

func fork_for_frame() -> RefCounted:
	var copy: RefCounted = get_script().new()
	if _sequence != null: copy._sequence = _sequence.fork_for_frame()
	copy._elapsed_ms = _elapsed_ms
	copy._max_ms = _max_ms
	copy._changes = _changes.duplicate(true)
	return copy

func reject(message: String) -> bool:
	error = message
	return false
