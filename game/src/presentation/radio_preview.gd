extends VBoxContainer
## Inspection tool for the source-bound opening transmissions, not a mission.
## The explicit baseline layout is a research fixture until panel declarations
## and source display classification are imported together.
const Resources = preload("res://src/presentation/opening_radio_resources.gd")
const Radio = preload("res://src/simulation/radio_sequence.gd")
const RadioPanel = preload("res://src/presentation/radio_panel.gd")
var library: RefCounted
var bindings: RefCounted
var visuals: RefCounted
var portrait_diagnostics := {}
var radio := Radio.new()
var view: Control
var status: Label
var _play: Button
var _pause: Button
var _running := false
var _elapsed := 0.0

func _ready() -> void:
	var controls := HBoxContainer.new()
	add_child(controls)
	_play = Button.new()
	_play.text = "Play opening radio"
	_play.pressed.connect(start)
	controls.add_child(_play)
	_pause = Button.new()
	_pause.text = "Pause preview"
	_pause.toggle_mode = true
	controls.add_child(_pause)
	var stop := Button.new()
	stop.text = "Stop"
	stop.pressed.connect(reset)
	controls.add_child(stop)
	var phone := CheckButton.new()
	phone.text = "Phone layout"
	phone.toggled.connect(func(enabled): view.set_mobile_layout(enabled))
	controls.add_child(phone)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	view = RadioPanel.new()
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The passive view hides when no transmission is visible. A permanent host
	# retains its viewport, so hiding a line does not collapse the inspector.
	var host := Control.new()
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(host)
	host.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reset()

func set_context(content: RefCounted, definitions: RefCounted, prepared_visuals: RefCounted = null) -> void:
	library = content
	bindings = definitions
	visuals = prepared_visuals
	if is_node_ready(): reset()

func reset() -> void:
	_running = false
	_elapsed = 0
	radio.clear()
	portrait_diagnostics = {}
	if view != null: view.clear()
	if _pause != null: _pause.button_pressed = false
	if status != null:
		status.text = "Radio timing preview · No mission progress · Voice is not yet connected"
		status.tooltip_text = ""

func start() -> void:
	reset()
	if library == null or bindings == null:
		status.text = "Open imported content and resource bindings first."
		return
	var resources := Resources.new()
	if not resources.prepare(library,bindings,visuals):
		status.text=resources.error
		return
	if not radio.configure(bindings,library,resources.line_counts):
		status.text=radio.error
		return
	var speakers: Dictionary = resources.speakers
	portrait_diagnostics=resources.portrait_diagnostics
	var portrait_count := 0
	for row in speakers.values():
		if row.has("portrait"):portrait_count+=1
	if not view.configure(bindings.base_content_id, bindings.binding_id, library.active_language, speakers):
		status.text = view.error
		radio.clear()
		return
	_running = true
	status.text = "Playing opening radio · Baseline timing preview · No mission progress"
	if portrait_count > 0: status.text += " · %d speaker portraits" % portrait_count
	if not portrait_diagnostics.is_empty():
		status.text += " · %d unavailable" % portrait_diagnostics.size()
		var details := PackedStringArray()
		for id in portrait_diagnostics: details.append("Speaker %d: %s" % [id, portrait_diagnostics[id]])
		status.tooltip_text = "\n".join(details)

func _process(delta: float) -> void:
	if not _running or _pause.button_pressed or not is_visible_in_tree(): return
	_elapsed += delta * 1000.0
	# No destroyed actors or cinematic phases are fabricated to advance the list.
	# At the first combat gate this preview waits for the future mission owner.
	radio.step(mini(int(_elapsed), 2147483647), {}, 0)
	if not radio.error.is_empty():
		_running = false
		view.clear()
		status.text = radio.error
		return
	var snapshot := radio.snapshot()
	if not view.present(snapshot):
		_running = false
		status.text = view.error
		return
	if snapshot.active_event == -1 and snapshot.finished.slice(0, 9).all(func(done): return done):
		_running = false
		status.text = "The opening radio now needs the combat encounter. This preview has not completed a mission."
