extends Control
## Passive native view of a radio snapshot. The mission owns simulation time,
## pauses and completion; native wrapping never feeds back into source timing.
## Speaker names/portraits must be resolved by the content owner before use.
const Library = preload("res://src/content/library.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
var error := ""
var _identity := {}
var _speakers := {}
var _snapshot := {}
var _mobile := false
var _top_inset := 0.0
var _panel: Panel
var _name: Label
var _body: RichTextLabel
var _portrait: TextureRect

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_name = Label.new()
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_panel.add_child(_name)
	_portrait = TextureRect.new()
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_panel.add_child(_portrait)
	_body = RichTextLabel.new()
	_body.mouse_filter = Control.MOUSE_FILTER_PASS
	_body.bbcode_enabled = false
	_body.fit_content = false
	_body.scroll_active = true
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.focus_mode = Control.FOCUS_NONE
	_panel.add_child(_body)
	resized.connect(_relayout)
	set_mobile_layout(false)

func configure(base_content_id: String, binding_id: String, language: String, speakers := {}, campaign_cursor: int = 0) -> bool:
	clear()
	_identity = {}
	_speakers = {}
	if not Library.valid_hash(base_content_id) or not Library.valid_hash(binding_id) or language.is_empty() or campaign_cursor not in [0, 1, 7, 10, 11, 12, 13, 14, 16, 18,19]:
		return _fail("Radio view needs a verified content, binding and language identity")
	# Copy names and retain supplied texture resources. Never guess a portrait or
	# derive a localization ID by adding a fixed cross-edition offset.
	for id in speakers:
		var row: Variant = speakers[id]
		if not Numbers.integer(id, 0, 65535) or not row is Dictionary or not row.get("name") is String or row.name.length() > 65534:
			return _fail("Invalid resolved radio speaker")
		if row.get("portrait") != null and not row.portrait is Texture2D:
			return _fail("Invalid resolved radio portrait")
	for id in speakers:
		_speakers[int(id)] = {"name": speakers[id].name, "portrait": speakers[id].get("portrait")}
	_identity = {"base_content_id": base_content_id, "binding_id": binding_id, "language": language}
	if campaign_cursor != 0: _identity.campaign_cursor = campaign_cursor
	return true

func clear() -> void:
	error = ""
	_snapshot = {}
	visible = false
	_name.text = ""
	_body.text = ""
	_portrait.texture = null

func present(snapshot: Dictionary, resolved_speaker: Dictionary = {}) -> bool:
	error = ""
	if snapshot.is_empty():
		clear()
		return true
	if _identity.is_empty(): return _fail("Radio view is unconfigured")
	for key in _identity:
		if snapshot.get(key) != _identity[key]: return _fail("Radio snapshot belongs to another content, binding or language")
	if not Numbers.integer(snapshot.get("active_event"), -1, 65534) or not snapshot.get("visible") is bool:
		return _fail("Invalid radio display state")
	if snapshot.active_event == -1:
		if snapshot.visible: return _fail("A visible radio snapshot has no active event")
		clear()
		return true
	if not Numbers.integer(snapshot.get("speaker_id"), 0, 65535) or not Numbers.integer(snapshot.get("text_id"), 0, 65535) or not snapshot.get("text") is String or snapshot.text.length() > 65534:
		return _fail("Invalid radio transmission")
	if not snapshot.visible:
		clear()
		return true
	var speaker: Dictionary = _speakers.get(int(snapshot.speaker_id), {})
	if _identity.get("campaign_cursor") in [10,11,12]:
		if not resolved_speaker.get("name") is String or not resolved_speaker.get("portrait") is Texture2D:return _fail("Local radio requires its selected portrait and resolved name")
		speaker=resolved_speaker
	# Avoid rewriting text/resetting scroll on every simulation frame.
	if snapshot == _snapshot and _portrait.texture==speaker.get("portrait") and _name.text==speaker.get("name", ""): return true
	_snapshot = snapshot.duplicate(true)
	_name.text = speaker.get("name", "")
	_portrait.texture = speaker.get("portrait")
	_body.text = snapshot.text
	_body.get_v_scroll_bar().value = 0
	visible = true
	_relayout()
	return true

func set_mobile_layout(enabled: bool) -> void:
	_mobile = enabled
	var scale := 1.0 if _mobile else 0.5
	_body.add_theme_font_size_override("normal_font_size", int(28 * scale))
	_name.add_theme_font_size_override("font_size", int(30 * scale))
	# Native remake styling; original panel atlas bindings remain a separate
	# content scope. Geometry/text are drawn at native resolution, never scaled.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.055, 0.085, 0.96)
	style.border_color = Color(0.24, 0.53, 0.65, 0.95)
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(12 * scale))
	_panel.add_theme_stylebox_override("panel", style)
	_name.add_theme_color_override("font_color", Color(0.68, 0.86, 0.93))
	_body.add_theme_color_override("default_color", Color(0.94, 0.97, 0.99))
	_relayout()

func set_top_inset(value: float) -> void:
	if not is_finite(value) or value<0 or value==_top_inset:return
	_top_inset=value;_relayout()

func _relayout() -> void:
	if not visible or size.x < 1 or size.y < 1: return
	var scale := 1.0 if _mobile else 0.5
	var inset := minf(24 * scale, size.x * 0.05)
	var width := minf(760 * scale, size.x - inset * 2)
	var padding := minf(24 * scale, width * 0.05)
	var top := maxf(minf(48 * scale, size.y * 0.05),_top_inset)
	var header := 38 * scale if not _name.text.is_empty() else 0.0
	var available := maxf(1, size.y - top - inset - padding * 2 - header)
	var portrait_height := minf(150 * scale, available)
	var portrait_width := portrait_height * 0.8 if _portrait.texture != null else 0.0
	var gap := padding if portrait_width > 0 else 0.0
	_panel.position = Vector2((size.x - width) * 0.5, top)
	_name.visible = header > 0
	_name.position = Vector2(padding, padding)
	_name.size = Vector2(maxf(1, width - padding * 2), header)
	_portrait.visible = portrait_width > 0
	_portrait.position = Vector2(padding, padding + header)
	_portrait.size = Vector2(portrait_width, portrait_height)
	_body.position = Vector2(padding + portrait_width + gap, padding + header)
	_body.size = Vector2(maxf(1, width - padding * 2 - portrait_width - gap), available)
	var body_height := clampf(maxf(_body.get_content_height(), portrait_height if portrait_width > 0 else 0), 1, available)
	_body.size.y = body_height
	_panel.size = Vector2(width, padding * 2 + header + body_height)

func _fail(message: String) -> bool:
	clear()
	error = message
	return false
