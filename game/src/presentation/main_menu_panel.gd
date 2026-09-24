extends Control
## Original menu artwork over a separately owned native background scene.
signal action_requested(action: String)
const Resources=preload("res://src/content/main_menu_resources.gd")
const OriginalUI=preload("res://src/presentation/original_ui.gd")
const Background=preload("res://src/presentation/main_menu_background.gd")
var error:=""
var _resources: RefCounted
var _ui: RefCounted
var _mobile:=false
var _buttons:={}
var _ordered: Array[Button]=[]
var _logo: TextureRect
var _background_rect: TextureRect
var _background: SubViewport
var _title_prompt: Label
var _scroll: ScrollContainer
var _column: VBoxContainer
var _exit: Button
var _notice: Label
var _ready_for_input:=false
var _title_seen:=false
var _title_active:=false
var _background_only:=false
var _title_elapsed_ms:=0.0
var _focused:=true
const TITLE_FADE_MS:=3900.0
const FRAME_LIMIT_MS:=150.0

func _init() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP
	_background_rect=TextureRect.new();_background_rect.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_background_rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_background_rect.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(_background_rect);_background_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_logo=TextureRect.new();_logo.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_logo.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_logo.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;add_child(_logo)
	_title_prompt=Label.new();_title_prompt.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_title_prompt.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;add_child(_title_prompt)
	_scroll=ScrollContainer.new();_scroll.follow_focus=true;_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(_scroll)
	_column=VBoxContainer.new();_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_scroll.add_child(_column)
	_notice=Label.new();_notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_notice.clip_text=true;_notice.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;_notice.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(_notice)
	_exit=Button.new();_exit.pressed.connect(func():_request("exit"));add_child(_exit)
	resized.connect(_layout)
	visibility_changed.connect(_sync_background)
	visible=false

func _ready() -> void:
	_focused=get_window().has_focus()
	get_window().size_changed.connect(_layout)

func _process(delta: float) -> void:
	if _title_active and _focused and is_visible_in_tree():advance_title(delta*1000.0)

func _notification(what: int) -> void:
	if what in [MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN,MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT]:_focused=what==MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN

func configure(library: RefCounted,bindings: RefCounted,visuals: RefCounted) -> bool:
	error=""
	var resources:=Resources.new();var ui:=OriginalUI.new()
	if not resources.configure(library,bindings,visuals):return reject(resources.error)
	if not ui.configure(library,bindings,visuals):return reject(ui.error)
	# Complete fallible asset preparation before replacing visible controls.
	var candidate_background: SubViewport
	if _background==null or _resources.identity.base_content_id!=resources.identity.base_content_id or _resources.identity.binding_id!=resources.identity.binding_id:
		candidate_background=Background.new();add_child(candidate_background)
		if not candidate_background.build(library,bindings,visuals):
			var message: String=candidate_background.error;candidate_background.free();return reject(message)
	if candidate_background!=null:
		_background_rect.texture=candidate_background.get_texture()
		if _background!=null:_background.free()
		_background=candidate_background
	if _resources==null or _resources.identity.base_content_id!=resources.identity.base_content_id:_title_seen=false
	for button in _buttons.values():button.free()
	_buttons={};_ordered.clear();_resources=resources;_ui=ui
	theme=Theme.new();theme.default_font=ui.font
	_logo.texture=resources.logo;_title_prompt.text=resources.title_prompt;_exit.text=library.strings[Resources.EXIT_TEXT_ID]
	for row in resources.actions:
		var button:=Button.new();button.set_meta("action",row.action)
		button.set_meta("source_text",row.text);button.tooltip_text=row.text
		button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		button.pressed.connect(func():_request(row.action))
		_column.add_child(button);_buttons[row.action]=button
	_buttons.supernova.disabled=true
	_buttons.supernova.tooltip_text="Supernova Challenge is not implemented yet"
	_ready_for_input=true;present(false,false);return true

func present(has_resume: bool,has_save: bool) -> void:
	if _resources==null:return
	_buttons.resume.visible=has_resume;_buttons.load.disabled=not has_save
	_ordered.clear()
	for row in _resources.actions:
		var button: Button=_buttons[row.action]
		if not button.visible:continue
		_ordered.append(button)
		button.text="%d.  %s"%[_ordered.size(),button.get_meta("source_text")]
	error="";_notice.text="";visible=true
	_background_only=false
	_title_active=not _title_seen
	if _title_active:_title_elapsed_ms=0.0
	_apply_title_state();_layout();_sync_background()

func show_background_only() -> void:
	if _resources==null:return
	_background_only=true;visible=true;_apply_title_state();_sync_background()

func _sync_background() -> void:
	if _background!=null:_background.set_active(is_visible_in_tree())

func advance_title(milliseconds: float) -> void:
	if not _title_active or not is_finite(milliseconds) or milliseconds<0.0:return
	_title_elapsed_ms=minf(1000000000.0,_title_elapsed_ms+minf(milliseconds,FRAME_LIMIT_MS))
	_apply_title_state()

func _apply_title_state() -> void:
	_logo.visible=not _background_only
	_scroll.visible=not _background_only and not _title_active;_exit.visible=not _background_only and not _title_active
	_notice.visible=not _background_only
	_title_prompt.visible=not _background_only and _title_active and _title_elapsed_ms>=TITLE_FADE_MS
	_title_prompt.modulate.a=floorf(255.0*absf(sin(_title_elapsed_ms*0.003)))/255.0 if _title_prompt.visible else 0.0
	_logo.modulate.a=floorf(255.0*clampf(_title_elapsed_ms/TITLE_FADE_MS,0.0,1.0))/255.0 if _title_active else 1.0

func _dismiss_title() -> void:
	if not _title_active:return
	_title_seen=true;_title_active=false;_apply_title_state();_layout();focus_first()

func set_mobile_layout(value: bool) -> void:
	_mobile=value;_layout()

func show_error(message: String) -> void:
	_dismiss_title();error=message;_notice.text=message;_layout()

func focus_first() -> void:
	if _title_active or _background_only:return
	for button in _ordered:
		if not button.disabled:button.grab_focus();return

func _request(action: String) -> void:
	if not _ready_for_input or _title_active or _background_only or not is_visible_in_tree():return
	if action!="exit" and (not _buttons.has(action) or not _buttons[action].visible or _buttons[action].disabled):return
	action_requested.emit(action)

func _unhandled_key_input(event: InputEvent) -> void:
	if not _ready_for_input or _title_active or _background_only or not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:return
	var key: int=event.physical_keycode if event.physical_keycode else event.keycode
	if key>=KEY_1 and key<=KEY_9:
		var index:=key-KEY_1
		if index<_ordered.size():
			_request(_ordered[index].get_meta("action"));get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if not _title_active or _background_only or not is_visible_in_tree():return
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		_dismiss_title();accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if not _title_active or _background_only or not is_visible_in_tree():return
	var accepted: bool=(event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed) or (event is InputEventJoypadButton and event.pressed)
	if accepted:_dismiss_title();get_viewport().set_input_as_handled()

func _layout() -> void:
	if _ui==null or size.x<=0 or size.y<=0:return
	if _background!=null:
		# The menu's 3D viewport must follow physical pixels when the interface
		# uses a larger desktop UI scale. Keep its authored 2D coordinates logical.
		var pixels: Vector2=get_global_transform_with_canvas().get_scale().abs()*get_viewport().get_stretch_transform().get_scale().abs()
		_background.size=Vector2i(maxi(64,roundi(size.x*pixels.x)),maxi(64,roundi(size.y*pixels.y)))
		_background.size_2d_override=Vector2i(maxi(64,roundi(size.x)),maxi(64,roundi(size.y)))
		_background.size_2d_override_stretch=true
	var width:=minf(300 if _mobile else 200,size.x-32)
	var logo_width:=minf(520 if _title_active else 380,size.x*(0.68 if _title_active else 0.55))
	var logo_height: float=logo_width*_logo.texture.get_height()/_logo.texture.get_width()
	var logo_y:=maxf(16.0,(size.y-logo_height)*0.38) if _title_active else (16.0 if _mobile else size.y*0.08)
	_logo.position=Vector2((size.x-logo_width)*0.5,logo_y);_logo.size=Vector2(logo_width,logo_height)
	_title_prompt.add_theme_font_size_override("font_size",24 if _mobile else 18)
	_title_prompt.position=Vector2(16,logo_y+logo_height+10);_title_prompt.size=Vector2(size.x-32,42)
	var y:=logo_y+logo_height+20 if _mobile else maxf(logo_y+logo_height+32,size.y*0.45)
	if not _notice.text.is_empty():y=maxf(y,logo_y+logo_height+96)
	_column.add_theme_constant_override("separation",6 if _mobile else 10)
	_scroll.position=Vector2((size.x-width)*0.5,y);_scroll.size=Vector2(width,maxf(44,size.y-y-14))
	for button in _buttons.values():_ui.apply_button(button,_mobile)
	_ui.apply_button(_exit,_mobile)
	_exit.size=Vector2(100 if _mobile else 80,44 if _mobile else 30)
	_exit.position=size-_exit.size-Vector2(12,12)
	_notice.add_theme_font_size_override("font_size",18 if _mobile else 14)
	_notice.position=Vector2(16,logo_y+logo_height+4);_notice.size=Vector2(size.x-32,80)

func snapshot() -> Dictionary:
	return {"identity":_resources.identity.duplicate() if _resources!=null else {},"mobile":_mobile,
		"background":_background.selection.duplicate(true) if _background!=null else {},
		"logo_rect":Rect2(_logo.position,_logo.size),"menu_rect":Rect2(_scroll.position,_scroll.size),
		"actions":_ordered.map(func(button):return {"action":button.get_meta("action"),"text":button.text,"disabled":button.disabled,"height":button.size.y}),
		"title_active":_title_active,"background_only":_background_only,"title_elapsed_ms":_title_elapsed_ms,"title_alpha":_logo.modulate.a,"title_prompt":_title_prompt.text,"error":error}

func reject(message: String) -> bool:error=message;return false
