extends Control
## Native compact inventory using original localized names and action labels.
## The actual station hangar remains visible behind this independently built UI.
signal action_requested(action: String, item_id: int)
const Definitions=preload("res://src/content/station_equipment_definitions.gd")
var error:=""
var _identity:={}
var _names:={}
var _labels:={}
var _state:={}
var _mobile:=false
var _active:=true
var _tab:="shop"
var _panel: PanelContainer
var _title: Label
var _requirement: Label
var _cargo: Label
var _message: Label
var _close: Button
var _rows:={}
var _tabs:={}
var _buttons:=[]
var _column: VBoxContainer

func _init() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE;visible=false
	_panel=PanelContainer.new();add_child(_panel)
	var margin:=MarginContainer.new();_panel.add_child(margin)
	for edge in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+edge,14)
	_column=VBoxContainer.new();margin.add_child(_column);_column.add_theme_constant_override("separation",10)
	_title=Label.new();_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_column.add_child(_title)
	_requirement=Label.new();_requirement.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_column.add_child(_requirement)
	var tabs:=HBoxContainer.new();_column.add_child(tabs)
	for tab in ["shop","cargo","ship"]:
		var button:=Button.new();button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.toggle_mode=true
		button.pressed.connect(func():select_tab(tab));tabs.add_child(button);_tabs[tab]=button
	_cargo=Label.new();_cargo.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_column.add_child(_cargo)
	var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.follow_focus=true;_column.add_child(scroll)
	var list:=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",10);scroll.add_child(list)
	for id in [0,22,55,90,81]:
		var row:=VBoxContainer.new();list.add_child(row)
		var name:=Label.new();name.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;row.add_child(name)
		var detail:=Label.new();detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;row.add_child(detail)
		var actions:=HFlowContainer.new();row.add_child(actions)
		var controls:={}
		for action in ["buy","sell","mount","unmount"]:
			var button:=Button.new();actions.add_child(button);controls[action]=button;_buttons.append(button)
			button.pressed.connect(func():action_requested.emit(action,id))
		_rows[id]={"node":row,"name":name,"detail":detail,"actions":controls}
	_message=Label.new();_message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_column.add_child(_message)
	_close=Button.new();_close.pressed.connect(func():action_requested.emit("close",-1));_column.add_child(_close)
	resized.connect(_relayout)
	_panel.minimum_size_changed.connect(_relayout)
	_panel.resized.connect(_place_panel)
	set_mobile_layout(false)

func configure(library: RefCounted, bindings: RefCounted) -> bool:
	error=""
	if library==null or bindings==null or not Definitions.parameters(bindings.station_equipment) or library.manifest.get("content_id")!=bindings.base_content_id:return reject("Equipment presentation requires its matching content pack")
	var names:={};var labels:={}
	for id in _rows:
		var text_id: int=int(id)+int(bindings.station_equipment.item_text_offset)
		if text_id>=library.strings.size() or library.strings[text_id].is_empty():return reject("Equipment name is unavailable")
		names[id]=library.strings[text_id]
	for key in {"shop":184,"cargo":183,"ship":182,"close":180,"mount":270,"unmount":271,"sell":319,"instruction":1724,"protected":312}:
		var text_id: int={"shop":184,"cargo":183,"ship":182,"close":180,"mount":270,"unmount":271,"sell":319,"instruction":1724,"protected":312}[key]
		if text_id>=library.strings.size() or library.strings[text_id].is_empty():return reject("Equipment action text is unavailable")
		labels[key]=library.strings[text_id]
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":library.active_language}
	_names=names;_labels=labels;_tab="shop";_state={};_message.text=""
	_title.text=labels.instruction;_close.text=labels.close
	for key in _tabs:_tabs[key].text=labels[key]
	return true

func present(state: Dictionary) -> bool:
	error=""
	if not state.get("hangar_open",false):clear();return true
	if _identity.is_empty() or not state.get("equipment") is Dictionary:return reject("Equipment presentation is unavailable")
	for key in _identity:
		if state.get(key)!=_identity[key]:return reject("Equipment presentation belongs to another session")
	if _state!=state.equipment:_state=state.equipment.duplicate(true);_message.text=""
	visible=true;_refresh();_relayout()
	return true

func select_tab(tab: String) -> void:
	if not _active or not visible or not _tabs.has(tab):return
	_tab=tab;_message.text="";_refresh()

func _refresh() -> void:
	if _state.is_empty():return
	var requirements: Dictionary=_state.requirements
	_requirement.text="Weapon: %s   ·   Armor: %s"%["mounted" if requirements.weapon_installed else "needed","mounted" if requirements.armor_installed else "needed"]
	_cargo.text="%s: %d / %d t"%[_labels.cargo,int(_state.cargo.used),int(_state.cargo.capacity)]
	for tab in _tabs:_tabs[tab].set_pressed_no_signal(tab==_tab);_tabs[tab].disabled=not _active
	for id in _rows:
		var row: Dictionary=_rows[id];var stock:=0;var owned:=0;var mounted:=false
		for offer in _state.stock:
			if offer.item_id==id:stock=int(offer.quantity)
		for entry in _state.cargo.entries:
			if entry.item_id==id:owned=int(entry.quantity)
		for slot in _state.loadout.slots:
			if slot!=null and slot.item_id==id:mounted=true
		var protected: bool=id in [90,81]
		row.node.visible=(not protected if _tab=="shop" else owned>0 if _tab=="cargo" else mounted)
		row.name.text=_names[id]
		row.detail.text=("0 cr · %d available"%stock) if _tab=="shop" else (_labels.protected if protected else "Mounted" if _tab=="ship" else "%d in cargo"%owned)
		for action in row.actions:
			var button: Button=row.actions[action]
			button.text="Buy" if action=="buy" else _labels[action]
			button.visible=(action=="buy" and _tab=="shop") or (action in ["mount","sell"] and _tab=="cargo") or (action=="unmount" and _tab=="ship")
			button.disabled=not _active or protected or (action=="buy" and stock==0)
	_close.disabled=not _active

func set_active(value: bool) -> void:_active=value;_refresh()
func show_error(message: String) -> void:_message.text=message

func set_mobile_layout(value: bool) -> void:
	_mobile=value
	var font_size:=20 if value else 15
	for label in [_title,_requirement,_cargo,_message]:label.add_theme_font_size_override("font_size",font_size)
	for row in _rows.values():
		row.name.add_theme_font_size_override("font_size",font_size)
		row.detail.add_theme_font_size_override("font_size",font_size)
	var style:=StyleBoxFlat.new();style.bg_color=Color(0.025,0.055,0.085,0.97)
	style.border_color=Color(0.24,0.53,0.65,0.95);style.set_border_width_all(1);style.set_corner_radius_all(12 if value else 6)
	_panel.add_theme_stylebox_override("panel",style)
	for button in _buttons+_tabs.values()+[_close]:
		button.custom_minimum_size.y=44 if value else 28
		button.add_theme_font_size_override("font_size",font_size)
	_relayout()

func _relayout() -> void:
	if not visible or size.x<=0 or size.y<=0:return
	_panel.size=Vector2(minf(800 if _mobile else 580,maxf(1,size.x-24)),minf(780 if _mobile else 450,maxf(1,size.y-24)))
	_place_panel()

func _place_panel() -> void:
	if not visible:return
	_panel.position=Vector2(maxf(0,(size.x-_panel.size.x)/2),maxf(0,(size.y-_panel.size.y)/2))

func clear() -> void:visible=false;_state={};_message.text=""
func reject(message: String) -> bool:error=message;return false
