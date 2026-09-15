extends Control
## Original menu artwork over a separately owned native background scene.
signal action_requested(action: String)
const Resources=preload("res://src/content/main_menu_resources.gd")
const OriginalUI=preload("res://src/presentation/original_ui.gd")
var error:=""
var _resources: RefCounted
var _ui: RefCounted
var _mobile:=false
var _buttons:={}
var _ordered: Array[Button]=[]
var _logo: TextureRect
var _scroll: ScrollContainer
var _column: VBoxContainer
var _exit: Button
var _notice: Label
var _ready_for_input:=false

func _init() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	_logo=TextureRect.new();_logo.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_logo.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_logo.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;add_child(_logo)
	_scroll=ScrollContainer.new();_scroll.follow_focus=true;_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(_scroll)
	_column=VBoxContainer.new();_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_scroll.add_child(_column)
	_notice=Label.new();_notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_notice.clip_text=true;_notice.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;_notice.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(_notice)
	_exit=Button.new();_exit.pressed.connect(func():_request("exit"));add_child(_exit)
	resized.connect(_layout)
	visible=false

func configure(library: RefCounted,bindings: RefCounted,visuals: RefCounted) -> bool:
	error=""
	var resources:=Resources.new();var ui:=OriginalUI.new()
	if not resources.configure(library,bindings,visuals):return reject(resources.error)
	if not ui.configure(library,bindings,visuals):return reject(ui.error)
	# Complete fallible asset preparation before replacing visible controls.
	for button in _buttons.values():button.free()
	_buttons={};_ordered.clear();_resources=resources;_ui=ui
	theme=Theme.new();theme.default_font=ui.font
	_logo.texture=resources.logo;_exit.text=library.strings[Resources.EXIT_TEXT_ID]
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
	error="";_notice.text="";visible=true;_layout()

func set_mobile_layout(value: bool) -> void:
	_mobile=value;_layout()

func show_error(message: String) -> void:
	error=message;_notice.text=message;_layout()

func focus_first() -> void:
	for button in _ordered:
		if not button.disabled:button.grab_focus();return

func _request(action: String) -> void:
	if not _ready_for_input or not is_visible_in_tree():return
	if action!="exit" and (not _buttons.has(action) or not _buttons[action].visible or _buttons[action].disabled):return
	action_requested.emit(action)

func _unhandled_key_input(event: InputEvent) -> void:
	if not _ready_for_input or not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:return
	var key: int=event.physical_keycode if event.physical_keycode else event.keycode
	if key>=KEY_1 and key<=KEY_9:
		var index:=key-KEY_1
		if index<_ordered.size():
			_request(_ordered[index].get_meta("action"));get_viewport().set_input_as_handled()

func _layout() -> void:
	if _ui==null or size.x<=0 or size.y<=0:return
	var width:=minf(300 if _mobile else 200,size.x-32)
	var logo_width:=minf(380,size.x*0.55)
	var logo_height: float=logo_width*_logo.texture.get_height()/_logo.texture.get_width()
	var logo_y:=16.0 if _mobile else size.y*0.08
	_logo.position=Vector2((size.x-logo_width)*0.5,logo_y);_logo.size=Vector2(logo_width,logo_height)
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
		"logo_rect":Rect2(_logo.position,_logo.size),"menu_rect":Rect2(_scroll.position,_scroll.size),
		"actions":_ordered.map(func(button):return {"action":button.get_meta("action"),"text":button.text,"disabled":button.disabled,"height":button.size.y}),"error":error}

func reject(message: String) -> bool:error=message;return false
