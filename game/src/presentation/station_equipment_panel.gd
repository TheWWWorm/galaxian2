extends Control
## Native compact inventory using original localized names and action labels.
## The actual station hangar remains visible behind this independently built UI.
signal action_requested(action: String, item_id: int)
signal slot_action_requested(action: String,item_id: int,slot_index: int)
const Definitions=preload("res://src/content/station_equipment_definitions.gd")
const Shopping=preload("res://src/content/ordinary_shopping_definitions.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
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
var _list: VBoxContainer
var _credits:=0
var _installed_rows:={}
var _replacement: ConfirmationDialog
var _pending_replace:={}

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
	_list=VBoxContainer.new();_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_list.add_theme_constant_override("separation",10);scroll.add_child(_list)
	for id in [0,22,55,90,81]:_add_row(id)
	_message=Label.new();_message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_column.add_child(_message)
	_close=Button.new();_close.pressed.connect(func():action_requested.emit("close",-1));_column.add_child(_close)
	resized.connect(_relayout)
	_panel.minimum_size_changed.connect(_relayout)
	_panel.resized.connect(_place_panel)
	_replacement=ConfirmationDialog.new();_replacement.title="Replace equipment";add_child(_replacement)
	_replacement.confirmed.connect(_confirm_replacement)
	_replacement.canceled.connect(func():_pending_replace={};_refresh())
	set_mobile_layout(false)

func _add_row(id: int) -> void:
	if _rows.has(id):return
	var row:=VBoxContainer.new();_list.add_child(row)
	var name:=Label.new();name.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;row.add_child(name)
	var detail:=Label.new();detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;row.add_child(detail)
	var actions:=HFlowContainer.new();row.add_child(actions)
	var controls:={}
	for action in ["buy","sell","mount","unmount"]:
		var button:=Button.new();actions.add_child(button);controls[action]=button;_buttons.append(button)
		button.pressed.connect(func():_request_action(action,id))
	_rows[id]={"node":row,"name":name,"detail":detail,"actions":controls}
	for label in [name,detail]:label.add_theme_font_size_override("font_size",20 if _mobile else 15)
	for button in controls.values():
		button.custom_minimum_size.y=44 if _mobile else 28
		button.add_theme_font_size_override("font_size",20 if _mobile else 15)

func _request_action(action: String,id: int) -> void:
	if not _active or not visible or not _pending_replace.is_empty():return
	var conflict: Dictionary=_state.get("fitting_conflicts",{}).get(id,{})
	if action=="mount" and not conflict.is_empty():
		_pending_replace={"item_id":id,"index":conflict.index,"previous_item_id":conflict.item_id,"loadout":_state.loadout.duplicate(true)}
		_replacement.dialog_text="Replace %s with %s?"%[_names[conflict.item_id],_names[id]]
		_replacement.popup_centered(Vector2i(600 if _mobile else 420,160))
		_refresh()
	else:action_requested.emit(action,id)

func _confirm_replacement() -> void:
	var pending:=_pending_replace;_pending_replace={}
	if not _active or not visible or pending.is_empty() or _state.get("loadout")!=pending.loadout:return
	slot_action_requested.emit("replace",pending.item_id,pending.index)
	_refresh()

func _add_installed_row(index: int) -> void:
	if _installed_rows.has(index):return
	var row:=VBoxContainer.new();_list.add_child(row)
	var label:=Label.new();label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;row.add_child(label)
	var button:=Button.new();row.add_child(button);_buttons.append(button)
	button.pressed.connect(func():
		if not _active or not visible or not _pending_replace.is_empty():return
		var slot: Variant=_state.loadout.slots[index]
		if slot!=null:slot_action_requested.emit("unmount",int(slot.item_id),index))
	_installed_rows[index]={"node":row,"name":label,"button":button}
	label.add_theme_font_size_override("font_size",20 if _mobile else 15)
	button.custom_minimum_size.y=44 if _mobile else 28
	button.add_theme_font_size_override("font_size",20 if _mobile else 15)

func configure(library: RefCounted, bindings: RefCounted) -> bool:
	error=""
	if library==null or bindings==null or not Definitions.parameters(bindings.station_equipment) or library.manifest.get("content_id")!=bindings.base_content_id:return reject("Equipment presentation requires its matching content pack")
	var names:={};var labels:={}
	var ids: Array=[0,22,55,90,81]
	if Shopping.available(bindings):
		var cat:=Catalogues.new()
		if not cat.open(library):return reject(cat.error)
		ids=range(cat.tables.items.size())
	for id in ids:
		var text_id: int=int(id)+int(bindings.station_equipment.item_text_offset)
		if text_id>=library.strings.size() or library.strings[text_id].is_empty():return reject("Equipment name is unavailable")
		names[id]=library.strings[text_id]
	var label_ids:={"shop":184,"cargo":183,"ship":182,"close":180,"mount":270,"unmount":271,"sell":319,"instruction":1724,"protected":312,"overfilled":193}
	for key in label_ids:
		var text_id: int=label_ids[key]
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
	var ids:=[]
	for row in state.equipment.get("market_rows",[]):ids.append(row.item_id)
	for slot in state.equipment.loadout.slots:
		if slot!=null and slot.item_id not in ids:ids.append(slot.item_id)
	for id in ids:
		if not _names.has(id):return reject("The current inventory item has no localized name")
	for i in ids.size():
		_add_row(ids[i]);_list.move_child(_rows[ids[i]].node,i)
	if state.equipment.has("fitting_support"):
		for i in state.equipment.loadout.slots.size():_add_installed_row(i)
	_credits=int(state.get("contracts",{}).get("credits",0))
	if _state!=state.equipment:_state=state.equipment.duplicate(true);_message.text=""
	visible=true;_refresh();_relayout()
	return true

func select_tab(tab: String) -> void:
	if not _active or not visible or not _tabs.has(tab):return
	_tab=tab;_message.text="";_refresh()

func _refresh() -> void:
	if _state.is_empty():return
	var ordinary: bool=_state.get("ordinary_shopping_open",false)
	var fitting: bool=_state.has("fitting_support")
	var controls: bool=_active and _pending_replace.is_empty()
	var requirements: Dictionary=_state.requirements
	_title.text=_labels.shop if ordinary else _labels.instruction
	_requirement.text="Equipment fitting is not yet available here." if ordinary else "Weapon: %s   ·   Armor: %s"%["mounted" if requirements.weapon_installed else "needed","mounted" if requirements.armor_installed else "needed"]
	if fitting:
		var stats: Dictionary=_state.fitting_stats
		_requirement.text="Hull %d · Armor %d · Shield %d\nHandling bonus %d%% · Passenger capacity %d"%[stats.hull,stats.armor,stats.shield,stats.handling_bonus_percent,stats.passenger_capacity]
	_cargo.text="%s: %d / %d t"%[_labels.cargo,int(_state.cargo.used),int(_state.cargo.capacity)]
	if ordinary:_cargo.text+="   ·   %d cr"%_credits
	if _state.cargo.used>_state.cargo.capacity:_cargo.text+="\n"+_labels.overfilled
	for tab in _tabs:_tabs[tab].set_pressed_no_signal(tab==_tab);_tabs[tab].disabled=not controls
	for id in _rows:
		var row: Dictionary=_rows[id];var stock:=0;var owned:=0;var mounted:=false;var price:=0;var offered:=false;var mission:=false
		for item in _state.get("market_rows",[]):
			if item.item_id==id:offered=true;price=int(item.unit_price);mission=item.mission
		for offer in _state.stock:
			if offer.item_id==id:stock=int(offer.quantity);price=int(offer.unit_price)
		for entry in _state.cargo.entries:
			if entry.item_id==id:owned=int(entry.quantity)
		for slot in _state.loadout.slots:
			if slot!=null and slot.item_id==id:mounted=true
		var protected: bool=mission or id in _state.get("protected_item_ids",[90,81])
		row.node.visible=((offered if ordinary else id in [0,22,55]) if _tab=="shop" else owned>0 if _tab=="cargo" else mounted)
		if fitting and _tab=="ship":row.node.visible=false
		row.name.text=_names.get(id,"")
		row.detail.text=("%d cr · %d available"%[price,stock]) if _tab=="shop" else (_labels.protected if protected else "Mounted" if _tab=="ship" else "%d in cargo · %d cr each"%[owned,price])
		var reason: String=_state.get("fitting_support",{}).get(id,"")
		if fitting and not reason.is_empty() and _tab in ["cargo","shop"]:row.detail.text+="\n"+reason
		for action in row.actions:
			var button: Button=row.actions[action]
			button.text="Buy" if action=="buy" else _labels[action]
			button.visible=(action=="buy" and _tab=="shop") or (action in ["mount","sell"] and _tab=="cargo") or (action=="unmount" and _tab=="ship")
			if ordinary and not fitting and action in ["mount","unmount"]:button.visible=false
			button.disabled=not controls or protected or (action=="buy" and (stock==0 or (ordinary and price>_credits))) or (fitting and action=="mount" and not reason.is_empty())
	for index in _installed_rows:
		var row: Dictionary=_installed_rows[index]
		var slot: Variant=_state.loadout.slots[index] if index<_state.loadout.slots.size() else null
		row.node.visible=fitting and _tab=="ship" and slot!=null
		if slot==null:continue
		row.name.text="%s · Slot %d · Quantity %d"%[_names[int(slot.item_id)],index+1,slot.quantity]
		row.button.text=_labels.unmount
		row.button.disabled=not controls or slot.item_id in _state.get("protected_item_ids",[])
	_close.disabled=not controls

func set_active(value: bool) -> void:_active=value;_refresh()
func show_error(message: String) -> void:_message.text=message

func set_mobile_layout(value: bool) -> void:
	_mobile=value
	var font_size:=20 if value else 15
	for label in [_title,_requirement,_cargo,_message]:label.add_theme_font_size_override("font_size",font_size)
	for row in _rows.values():
		row.name.add_theme_font_size_override("font_size",font_size)
		row.detail.add_theme_font_size_override("font_size",font_size)
	for row in _installed_rows.values():row.name.add_theme_font_size_override("font_size",font_size)
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

func clear() -> void:
	visible=false;_state={};_message.text="";_pending_replace={}
	if _replacement!=null:_replacement.hide()
func reject(message: String) -> bool:error=message;return false
