extends Control
## Original artwork and localized prompt over the retained flight scene.
## The destruction owner supplies fade/readiness; the caller owns exit routing.
signal continue_requested
const Definitions=preload("res://src/content/game_over_definitions.gd")
const Desktop=preload("res://src/content/desktop_text_definitions.gd")
const Death=preload("res://src/simulation/player_destruction.gd")
const Atlas=preload("res://src/content/atlas_region.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
const Controls=preload("res://src/input/flight_controls.gd")
var error:=""
var _identity:={}
var _owner_identity: RefCounted
var _rules:={}
var _texts:={}
var _sample:={}
var _mobile:=false
var _active:=true
var _controls:=Controls.new()
var _art: TextureRect
var _prompt: Label

func _init() -> void:
	visible=false;clip_contents=true;mouse_filter=Control.MOUSE_FILTER_STOP
	focus_mode=Control.FOCUS_ALL
	_art=TextureRect.new();_art.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR;add_child(_art)
	_prompt=Label.new();_prompt.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_prompt.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_prompt.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_prompt.add_theme_color_override("font_color",Color.WHITE);add_child(_prompt)
	resized.connect(_reflow)

func configure(library: RefCounted, bindings: RefCounted, visuals: RefCounted, death: RefCounted) -> bool:
	error=""
	if library==null or bindings==null or visuals==null or not death is Death or not Definitions.parameters(bindings.game_over_presentation) or not Desktop.parameters(bindings.desktop_text):return reject("Game-over resources require supported Mac content")
	var state: Dictionary=death.snapshot()
	if library.manifest.get("content_id")!=bindings.base_content_id or visuals.base_content_id!=bindings.base_content_id or library.active_language.is_empty():return reject("Game-over resources belong to another content base")
	for key in ["base_content_id","binding_id"]:
		if state.get(key)!=bindings.get(key):return reject("Game-over resources belong to another flight")
	var rules: Dictionary=bindings.game_over_presentation
	var registered:=false
	for row in bindings.records.get(int(rules.texture_id),[]):
		if row.resource==rules.resource and row.kind=="texture" and int(row.registration_type)==2:registered=true
	if not registered:return reject("The original game-over atlas is not registered")
	var reader:=Atlas.new()
	var texture:=reader.load(library,visuals,rules.resource,int(rules.region))
	if texture==null:return reject(reader.error)
	var texts:={}
	for id in [int(rules.continue_text_id),bindings.desktop_text_id(int(rules.continue_text_id))]:
		if id<0 or id>=library.strings.size() or not library.strings[id] is String or library.strings[id].is_empty():return reject("The localized game-over prompt is unavailable")
		texts[id]=library.strings[id]
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":library.active_language,
		"desktop_text_id":bindings.desktop_text_id(int(rules.continue_text_id))}
	_owner_identity=death.presentation_identity();_rules=rules.duplicate(true);_texts=texts
	_art.texture=texture;clear()
	return true

func present(death: RefCounted, absolute_milliseconds: Variant) -> bool:
	error=""
	if _identity.is_empty() or not death is Death or death.presentation_identity()!=_owner_identity:return reject("Game-over display belongs to another flight")
	if not absolute_milliseconds is int or absolute_milliseconds<0:return reject("Game-over blinking requires a nonnegative absolute clock")
	var state: Dictionary=death.snapshot()
	for key in ["base_content_id","binding_id"]:
		if state.get(key)!=_identity[key]:return reject("Game-over display belongs to another content identity")
	var next:={"base_content_id":_identity.base_content_id,"binding_id":_identity.binding_id,"language":_identity.language,
		"phase":state.phase,"visible":state.game_over_visible,"alpha_byte":state.game_over_alpha_byte,
		"continue_enabled":state.continue_enabled,"prompt_visible":state.game_over_visible and state.phase=="game_over",
		"prompt_alpha_byte":blink_alpha(absolute_milliseconds,float(_rules.blink_radians_per_millisecond)),
		"absolute_ms":absolute_milliseconds,"image_id":int(_rules.image_id),"resource":_rules.resource,
		"source_rect":_art.texture.region}
	_sample=next;visible=next.visible;_art.modulate.a=float(next.alpha_byte)/255.0
	_prompt.visible=next.prompt_visible;_prompt.modulate.a=float(next.prompt_alpha_byte)/255.0
	_reflow()
	return true

static func blink_alpha(absolute_milliseconds: int, radians_per_millisecond: float) -> int:
	var angle:=Vitals.single(Vitals.single(float(absolute_milliseconds))*radians_per_millisecond)
	return clampi(int(Vitals.single(absf(Vitals.single(sin(angle)))*255.0)),0,255)

func handle_event(event: InputEvent) -> bool:
	# Track fire edges even before the fade ends. A held trigger must be released
	# before it can acknowledge; reuse the flight controller's device/deadzone rules.
	_controls.accept(event)
	var fired: bool="fire" in _controls.take_pressed()
	if not _active or not is_visible_in_tree() or not _sample.get("continue_enabled",false):return false
	var accepted:=fired
	if event is InputEventKey:accepted=fired or (event.pressed and not event.echo and (event.physical_keycode if event.physical_keycode else event.keycode) in [KEY_ENTER,KEY_KP_ENTER])
	elif event is InputEventJoypadButton:accepted=event.pressed and event.button_index==JOY_BUTTON_A
	elif event is InputEventScreenTouch:accepted=event.pressed
	elif event is InputEventMouseButton:accepted=event.pressed and event.button_index==MOUSE_BUTTON_LEFT
	if not accepted:return false
	continue_requested.emit()
	return true

func _gui_input(event: InputEvent) -> void:
	if handle_event(event):accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if handle_event(event):get_viewport().set_input_as_handled()

func set_active(value: bool) -> void:_active=value
func set_mobile_layout(value: bool) -> void:_mobile=value;_reflow()

func _reflow() -> void:
	if _sample.is_empty() or size.x<=0 or size.y<=0:return
	var scale:=1.0 if _mobile else 0.5
	var available:=Vector2(maxf(1,size.x-24),maxf(1,size.y-80))
	var art_size:=_art.texture.get_size()*scale
	art_size*=minf(1.0,minf(available.x/art_size.x,available.y/art_size.y))
	_art.size=art_size;_art.position=(size-art_size)*0.5
	var text_id:=int(_rules.continue_text_id) if _mobile else int(_identity.desktop_text_id)
	_prompt.text=_texts[text_id]
	var font_size:=24 if _mobile else 14
	_prompt.add_theme_font_size_override("font_size",font_size)
	_prompt.size=Vector2(maxf(1,size.x-24),0)
	_prompt.position=Vector2(12,_art.position.y+art_size.y+float(_rules.prompt_gap)*scale)
	_sample.text_id=text_id;_sample.text=_prompt.text;_sample.composition_scale=scale
	_sample.image_rect=Rect2(_art.position,_art.size)
	_sample.prompt_rect=Rect2(_prompt.position,_prompt.size)

func snapshot() -> Dictionary:
	var state:=_sample.duplicate(true)
	if not state.is_empty():
		state.input_enabled=_active and is_visible_in_tree() and state.continue_enabled
		state.image_rect=Rect2(_art.position,_art.size)
		state.prompt_rect=Rect2(_prompt.position,_prompt.size)
	return state

func clear() -> void:
	error="";_sample={};visible=false;_prompt.text="";_controls.clear()

func reject(message: String) -> bool:error=message;return false
