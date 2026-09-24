extends Control
## Compact native secondary controls. Original item names come from the active
## content; this is not a reconstruction of the original mission instruction UI.
## The display reads accepted launcher state and never changes ammunition/time.
signal action_requested(action: String)
signal selection_requested(item_id: int)
signal selection_cancelled
signal layout_changed
const Ownership=preload("res://src/simulation/secondary_weapons.gd")
const Library=preload("res://src/content/library.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const OriginalUI=preload("res://src/presentation/original_ui.gd")
const MENU_TEXT_IDS={"title":255,"selected":266,"none":275,"confirm":130,"cancel":414}
var error:=""
var _identity:={}
var _names:={}
var _art: RefCounted
var _menu_labels:={}
var _state:={}
var _mobile:=false
var _active:=false
var _touch:=false
var _hud_visible:=true
var _panel: PanelContainer
var _title: Label
var _name: Label
var _ammunition: Label
var _status: Label
var _hint: Label
var _actions: HBoxContainer
var _select: Button
var _fire: Button
var _can_cycle:=false
var _can_activate:=false
var _menu_open:=false
var _menu_active:=false
var _highlighted:=-1
var _choices:=[]
var _menu_edges:={}
var _shade: ColorRect
var _menu: PanelContainer
var _menu_title: Label
var _menu_hint: Label
var _menu_column: VBoxContainer
var _menu_actions: HBoxContainer
var _menu_scroll: ScrollContainer
var _menu_rows: VBoxContainer
var _menu_confirm: Button
var _menu_cancel: Button

func _init() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE;visible=false
	_panel=PanelContainer.new();_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(_panel)
	var column:=VBoxContainer.new();column.mouse_filter=Control.MOUSE_FILTER_IGNORE;_panel.add_child(column)
	column.add_theme_constant_override("separation",5)
	_title=Label.new();_name=Label.new();_ammunition=Label.new();_status=Label.new();_hint=Label.new()
	for label in [_title,_name,_ammunition,_status,_hint]:
		label.mouse_filter=Control.MOUSE_FILTER_IGNORE
		label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		column.add_child(label)
	_title.text="SECONDARY"
	_title.add_theme_color_override("font_color",Color(0.56,0.76,0.84))
	_hint.add_theme_color_override("font_color",Color(0.7,0.79,0.83))
	_actions=HBoxContainer.new();_actions.mouse_filter=Control.MOUSE_FILTER_IGNORE;column.add_child(_actions)
	_select=Button.new();_fire=Button.new()
	for button in [_select,_fire]:
		button.focus_mode=Control.FOCUS_NONE;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_actions.add_child(button)
	_select.text="Select";_select.pressed.connect(func():_request("secondary_menu"))
	_fire.pressed.connect(func():_request("missiles"))
	_build_selection_menu()
	resized.connect(_relayout)
	_panel.minimum_size_changed.connect(_relayout)
	_panel.resized.connect(func():layout_changed.emit())
	set_mobile_layout(false)

func matches_context(library: RefCounted,bindings: RefCounted,visuals: RefCounted=null) -> bool:
	return library!=null and bindings!=null and not _identity.is_empty() and _identity.base_content_id==library.manifest.get("content_id") and _identity.base_content_id==bindings.base_content_id and _identity.binding_id==bindings.binding_id and _identity.language==library.active_language and (visuals==null or (_art!=null and visuals.base_content_id==_identity.base_content_id and _art.identity==_identity))

func configure(library: RefCounted,bindings: RefCounted,visuals: RefCounted=null) -> bool:
	error=""
	if library==null or bindings==null or not Ownership.Definitions.available(bindings) or not Library.valid_hash(bindings.binding_id) or library.manifest.get("content_id")!=bindings.base_content_id or library.active_language.is_empty():return reject("Secondary controls require matching imported content and an active language")
	var names:={}
	for id in Ownership.Definitions.VALUES.item_ids:
		var text_id: int=int(id)+int(bindings.station_equipment.item_text_offset)
		if text_id<0 or text_id>=library.strings.size() or not library.strings[text_id] is String or library.strings[text_id].is_empty():return reject("The equipped secondary name is unavailable")
		names[int(id)]=library.strings[text_id]
	var art: RefCounted
	var labels:={}
	if visuals!=null:
		art=OriginalUI.new()
		if not art.configure(library,bindings,visuals):return reject(art.error)
		for key in MENU_TEXT_IDS:
			var id: int=MENU_TEXT_IDS[key]
			if id>=library.strings.size() or not library.strings[id] is String or library.strings[id].is_empty():return reject("The localized secondary menu text is unavailable")
			labels[key]=library.strings[id]
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":library.active_language}
	_names=names;_art=art;_menu_labels=labels
	_menu.theme=null
	if _art!=null:
		var original_theme:=Theme.new();original_theme.default_font=_art.font;_menu.theme=original_theme
	clear_sample();_refresh_menu_text();set_mobile_layout(_mobile)
	return true

func present(sample: Dictionary) -> bool:
	error=""
	if sample.is_empty():clear_sample();return true
	if _identity.is_empty():return reject("Prepare secondary controls before presenting a launcher")
	for key in ["base_content_id","binding_id"]:
		if sample.get(key)!=_identity[key]:return reject("Secondary controls belong to another content identity")
	if not sample.get("selected_item_id") is int or not sample.get("weapons") is Array or sample.weapons.size()>_names.size() or not sample.get("actions") is Array:return reject("Invalid secondary control sample")
	var ids:={};var slots:={};var expected_actions:=[];var ended:=false
	for weapon in sample.weapons:
		if not weapon is Dictionary or not weapon.get("item_id") is int or not _names.has(weapon.item_id) or ids.has(weapon.item_id):return reject("Secondary controls lost a unique equipped item")
		if not Numbers.integer(weapon.get("quantity"),0,2147483647) or not weapon.get("live") is bool or not Numbers.integer(weapon.get("slot_index"),0,2147483647) or slots.has(weapon.slot_index) or not Numbers.integer(weapon.get("wait_ms"),0,2147483647):return reject("Secondary controls lost ammunition, timing or slot identity")
		ids[weapon.item_id]=true;slots[weapon.slot_index]=true
		if ended:continue
		if weapon.live:expected_actions.append({"item_id":weapon.item_id,"action":"detonated"})
		elif weapon.item_id==sample.selected_item_id and weapon.quantity>0 and weapon.wait_ms==0:
			expected_actions.append({"item_id":weapon.item_id,"action":"launched"});ended=true
	if sample.selected_item_id!=-1 and not ids.has(sample.selected_item_id):return reject("Secondary controls selected an unavailable launcher")
	if sample.actions!=expected_actions:return reject("Secondary control feedback disagrees with launcher order or readiness")
	if _state!=sample:_state=sample.duplicate(true);_refresh()
	return true

func set_interaction(active: bool,show_touch: bool) -> void:
	if _active==active and _touch==show_touch:return
	_active=active;_touch=show_touch;_refresh()

func set_hud_visible(value: bool) -> void:
	_hud_visible=value;_refresh_visibility()

func _refresh_visibility() -> void:
	visible=_hud_visible and not _state.is_empty() and not _state.weapons.is_empty()
	_panel.visible=not _menu_open
	_shade.visible=_menu_open
	z_index=20 if _menu_open else 0
	_select.disabled=not _active or not visible or not _can_cycle or _menu_open
	_fire.disabled=not _active or not visible or not _can_activate or _menu_open
	var enabled: bool=_menu_open and _menu_active and visible
	_menu_confirm.disabled=not enabled
	_menu_cancel.disabled=not enabled
	for row in _menu_rows.get_children():row.disabled=not enabled

func _refresh() -> void:
	if _state.is_empty():_refresh_visibility();return
	var selected:={};var live:=0;var remaining:=0
	for weapon in _state.weapons:
		live+=int(weapon.live);remaining+=weapon.quantity
		if weapon.item_id==_state.selected_item_id:selected=weapon
	var launches: int=_state.actions.filter(func(action):return action.action=="launched").size()
	var detonations: int=_state.actions.size()-launches
	_can_activate=not _state.actions.is_empty()
	_can_cycle=remaining>0 or not selected.is_empty()
	_name.text="None selected" if selected.is_empty() else _names[selected.item_id]
	_ammunition.text="Ammunition: %d"%selected.quantity if not selected.is_empty() else "Available ammunition: %d"%remaining
	if live>0:_ammunition.text+=" · In flight: %d"%live
	var activation:="Launch / detonate"
	_fire.text="Activate"
	if launches>0 and detonations>0:_status.text="Detonate, then launch";activation="Detonate + launch"
	elif detonations>0:_status.text="Ready to detonate";_fire.text="Detonate";activation="Detonate"
	elif launches>0:_status.text="Ready to launch";_fire.text="Launch";activation="Launch"
	elif remaining==0:_status.text="No ammunition remaining"
	elif selected.is_empty():_status.text="Select a secondary weapon"
	elif selected.quantity==0:_status.text="Selected ammunition exhausted"
	else:_status.text="Reloading · %.1f s"%(ceilf(float(selected.wait_ms)/100.0)/10.0)
	# Both input families remain usable. A previously used controller is not
	# evidence that the player stopped using the keyboard.
	_hint.text="Q / D-pad right: Weapons menu\nR / B / LT: "+activation
	_actions.visible=_touch;_hint.visible=not _touch
	if _menu_open:_rebuild_choices()
	_refresh_visibility();_relayout()

func _request(action: String) -> void:
	if not _active or not _touch or not is_visible_in_tree() or _menu_open:return
	if (action=="secondary_menu" and _can_cycle) or (action=="missiles" and _can_activate):action_requested.emit(action)

func set_mobile_layout(value: bool) -> void:
	_mobile=value
	var box:=StyleBoxFlat.new();box.bg_color=Color(0.025,0.055,0.09,0.94);box.border_color=Color(0.19,0.39,0.48,0.9)
	box.set_border_width_all(1);box.set_corner_radius_all(8)
	box.content_margin_left=12;box.content_margin_right=12;box.content_margin_top=10;box.content_margin_bottom=10
	_panel.add_theme_stylebox_override("panel",box)
	_menu.add_theme_stylebox_override("panel",box.duplicate())
	if _art!=null:_menu.add_theme_stylebox_override("panel",_art.styles[value].panel)
	_menu_title.add_theme_font_size_override("font_size",24 if value else 20)
	_menu_hint.add_theme_font_size_override("font_size",18 if value else 14)
	for button in [_menu_confirm,_menu_cancel]+_menu_rows.get_children():
		_style_menu_button(button,button.get_parent()==_menu_rows)
	for label in [_title,_ammunition,_status,_hint]:label.add_theme_font_size_override("font_size",18 if value else 14)
	_name.add_theme_font_size_override("font_size",22 if value else 17)
	for button in [_select,_fire]:
		button.custom_minimum_size.y=48 if value else 32
		button.add_theme_font_size_override("font_size",20 if value else 15)
	_relayout()

var _top_inset:=0.0

func set_top_inset(value: float) -> void:
	if _top_inset==value:return
	_top_inset=value;_relayout()

func _relayout() -> void:
	var width:=minf(380.0 if _mobile else 300.0,maxf(0.0,size.x-24.0))
	_panel.position=Vector2(12,maxf(12,_top_inset))
	_panel.custom_minimum_size=Vector2(width,0)
	_panel.size=Vector2(width,0)
	var menu_width:=minf(560.0,maxf(0.0,size.x-32.0))
	_menu.custom_minimum_size=Vector2(menu_width,0)
	# Keep the title and both actions reachable in short landscape viewports.
	# Only equipped choices scroll; browsing still owns no gameplay state.
	var fixed_height: float=_menu.get_theme_stylebox("panel").get_minimum_size().y
	for control in [_menu_title,_menu_hint,_menu_actions]:fixed_height+=control.get_combined_minimum_size().y
	fixed_height+=3*_menu_column.get_theme_constant("separation")
	_menu_scroll.custom_minimum_size.y=minf(_menu_rows.get_combined_minimum_size().y,maxf(1.0,size.y-24.0-fixed_height))
	_menu.size=Vector2(menu_width,0)
	_menu.position=((size-_menu.size)*0.5).round()

func top_inset() -> float:
	return _panel.position.y+_panel.size.y+8.0 if visible and not _menu_open else 0.0

func snapshot() -> Dictionary:
	return {"state":_state.duplicate(true),"visible":visible,"name":_name.text,"ammunition":_ammunition.text,"status":_status.text,"hint":_hint.text,"touch_controls":_actions.visible,"select_enabled":not _select.disabled,"activate_enabled":not _fire.disabled,"panel_rect":_panel.get_rect(),"selection":selection_snapshot()}

func clear_sample() -> void:
	close_selection()
	_state={};_can_cycle=false;_can_activate=false
	_name.text="";_ammunition.text="";_status.text="";_hint.text=""
	_refresh_visibility()

func clear() -> void:
	error="";_identity={};_names={};_art=null;_menu_labels={};_menu.theme=null;_active=false;clear_sample()

func _build_selection_menu() -> void:
	_shade=ColorRect.new();_shade.color=Color(0.005,0.015,0.03,0.82)
	_shade.mouse_filter=Control.MOUSE_FILTER_STOP;add_child(_shade)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu=PanelContainer.new();_shade.add_child(_menu)
	_menu_column=VBoxContainer.new();_menu_column.add_theme_constant_override("separation",10);_menu.add_child(_menu_column)
	_menu_title=Label.new();_menu_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_menu_title.text="SECONDARY WEAPONS";_menu_column.add_child(_menu_title)
	_menu_hint=Label.new();_menu_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_menu_hint.text="Choose equipped ammunition. Selection does not fire."
	_menu_column.add_child(_menu_hint)
	_menu_scroll=ScrollContainer.new();_menu_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_menu_scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_menu_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_menu_column.add_child(_menu_scroll)
	_menu_rows=VBoxContainer.new();_menu_rows.add_theme_constant_override("separation",6)
	_menu_rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_menu_scroll.add_child(_menu_rows)
	_menu_rows.minimum_size_changed.connect(_relayout)
	_menu_rows.sort_children.connect(func():_reveal_highlight.call_deferred())
	_menu_actions=HBoxContainer.new();_menu_column.add_child(_menu_actions)
	_menu_cancel=Button.new();_menu_confirm=Button.new()
	for button in [_menu_cancel,_menu_confirm]:
		button.focus_mode=Control.FOCUS_NONE;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_menu_actions.add_child(button)
	_menu_cancel.text="Cancel";_menu_confirm.text="Select"
	_menu_cancel.pressed.connect(_cancel_selection);_menu_confirm.pressed.connect(_confirm_selection)
	_menu.minimum_size_changed.connect(_relayout)
	_shade.hide()

func open_selection() -> bool:
	error=""
	if _menu_open or not _active or not is_visible_in_tree() or _state.is_empty() or _state.weapons.is_empty():return reject("No active equipped secondary selection is available")
	_menu_open=true;_menu_active=true;_highlighted=int(_state.selected_item_id);_menu_edges={}
	_rebuild_choices();_refresh_visibility();_relayout()
	return true

func close_selection() -> void:
	_menu_open=false;_menu_active=false;_highlighted=-1;_choices=[];_menu_edges={}
	for row in _menu_rows.get_children():row.free()
	_refresh_visibility()

func set_selection_active(value: bool) -> void:
	_menu_active=value
	_refresh_visibility()

func _rebuild_choices() -> void:
	_choices=_state.weapons.filter(func(weapon):return weapon.quantity>0).map(func(weapon):return {"item_id":weapon.item_id,"quantity":weapon.quantity})
	_choices.append({"item_id":-1,"quantity":0})
	if not _choices.any(func(choice):return choice.item_id==_highlighted):_highlighted=-1
	for row in _menu_rows.get_children():row.free()
	for choice in _choices:
		var row:=Button.new();row.focus_mode=Control.FOCUS_NONE;row.toggle_mode=true
		row.alignment=HORIZONTAL_ALIGNMENT_LEFT
		_style_menu_button(row,true)
		row.text=_menu_labels.get("none","None") if choice.item_id==-1 else "%s · %d"%[_names[choice.item_id],choice.quantity]
		row.pressed.connect(_highlight_choice.bind(int(choice.item_id)))
		_menu_rows.add_child(row)
	_refresh_menu_text();_sync_highlight()

func _refresh_menu_text() -> void:
	_menu_title.text=_menu_labels.get("title","SECONDARY WEAPONS")
	_menu_cancel.text=_menu_labels.get("cancel","Cancel");_menu_confirm.text=_menu_labels.get("confirm","Select")
	_menu_hint.text="Choose equipped ammunition. Selection does not fire."
	if not _menu_labels.is_empty():
		var accepted: int=_state.get("selected_item_id",-1)
		_menu_hint.text=_menu_labels.selected+": "+_names.get(accepted,_menu_labels.none)

func _style_menu_button(button: Button,choice: bool) -> void:
	for state in ["normal","hover","disabled","focus","pressed","hover_pressed"]:button.remove_theme_stylebox_override(state)
	if _art!=null:_art.apply_button(button,_mobile,button==_menu_cancel)
	elif choice:
		var highlight:=StyleBoxFlat.new()
		highlight.bg_color=Color(0.045,0.15,0.20);highlight.border_color=Color(0.40,0.80,0.94)
		highlight.set_border_width_all(2);highlight.set_corner_radius_all(4)
		highlight.content_margin_left=8;highlight.content_margin_right=8
		highlight.content_margin_top=4;highlight.content_margin_bottom=4
		button.add_theme_stylebox_override("pressed",highlight);button.add_theme_stylebox_override("hover_pressed",highlight)
	button.custom_minimum_size.y=56 if _mobile else 42
	button.add_theme_font_size_override("font_size",20 if _mobile else 17)

func _highlight_choice(item_id: int) -> void:
	if not _selection_accepts_input() or not _choices.any(func(choice):return choice.item_id==item_id):return
	_highlighted=item_id;_sync_highlight()

func _sync_highlight() -> void:
	for index in _choices.size():_menu_rows.get_child(index).set_pressed_no_signal(_choices[index].item_id==_highlighted)
	_reveal_highlight.call_deferred()

func _reveal_highlight() -> void:
	if not _menu_open:return
	for index in _choices.size():
		if _choices[index].item_id==_highlighted:
			_menu_scroll.ensure_control_visible(_menu_rows.get_child(index));return

func _selection_accepts_input() -> bool:return _menu_open and _menu_active and is_visible_in_tree()

func _confirm_selection() -> void:
	if _selection_accepts_input() and _choices.any(func(choice):return choice.item_id==_highlighted):selection_requested.emit(_highlighted)

func _cancel_selection() -> void:
	if _selection_accepts_input():selection_cancelled.emit()

func handle_selection_event(event: InputEvent) -> bool:
	if not _menu_open:return false
	# Own releases as well as presses, without converting them to flight input.
	var code: int=-1;var down:=false;var handle:=""
	if event is InputEventKey:
		code=event.physical_keycode if event.physical_keycode else event.keycode
		down=event.pressed;handle="key:%d"%code
		if event.echo:return true
	elif event is InputEventJoypadButton:
		code=event.button_index;down=event.pressed;handle="pad:%d:%d"%[event.device,code]
	else:return true
	var held: bool=_menu_edges.get(handle,false)
	_menu_edges[handle]=down
	if not down or held or not _selection_accepts_input():return true
	var movement:=0;var confirm:=false;var cancel:=false
	if event is InputEventKey:
		if code in [KEY_UP,KEY_LEFT]:movement=-1
		elif code in [KEY_DOWN,KEY_RIGHT]:movement=1
		confirm=code in [KEY_ENTER,KEY_KP_ENTER]
		cancel=code in [KEY_ESCAPE,KEY_Q]
	else:
		if code in [JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_LEFT]:movement=-1
		elif code in [JOY_BUTTON_DPAD_DOWN,JOY_BUTTON_DPAD_RIGHT]:movement=1
		confirm=code==JOY_BUTTON_A;cancel=code==JOY_BUTTON_B
	if movement!=0:
		var ids: Array=_choices.map(func(choice):return choice.item_id)
		_highlight_choice(int(ids[posmod(ids.find(_highlighted)+movement,ids.size())]))
	elif confirm:_confirm_selection()
	elif cancel:_cancel_selection()
	return true

func selection_snapshot() -> Dictionary:
	return {"open":_menu_open,"active":_menu_active,"highlighted_item_id":_highlighted,"choices":_choices.duplicate(true),"rect":_menu.get_rect()}

func reject(message: String) -> bool:error=message;return false
