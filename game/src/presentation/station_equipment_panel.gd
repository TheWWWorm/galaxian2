extends Control
## Source-art hangar screen over the existing station equipment transaction owner.
signal action_requested(action: String, item_id: int)
signal slot_action_requested(action: String,item_id: int,slot_index: int)
const Definitions=preload("res://src/content/station_equipment_definitions.gd")
const Shopping=preload("res://src/content/ordinary_shopping_definitions.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Atlas=preload("res://src/content/atlas_region.gd")
const OriginalUI=preload("res://src/presentation/original_ui.gd")
const ITEM_ATLAS="resources/data/textures/gof2_items_ipad_1440.aei"
const CATEGORY_LABELS=[254,255,256,258,259]
# Verified source interface regions: normal row/cap, category band/cap,
# selected row/cap. These are artwork choices, not transaction declarations.
const ROW_ART_IDS=[1144,1145,1153,1154,1160,1161]
var error:=""
var _identity:={}
var _names:={}
var _labels:={}
var _ship_names:={}
var _item_categories:={}
var _state:={}
var _mobile:=false
var _active:=true
var _tab:="shop"
var _panel: PanelContainer
var _art: RefCounted
var _catalogues: RefCounted
var _item_pixels: Texture2D
var _item_metadata:=PackedByteArray()
var _icon_cache:={}
var _categories:={}
var _slot_categories:=[]
var _selected_id:=-1
var _selected_slot:=-1
var _ship_band: PanelContainer
var _ship_label: Label
var _ship_row: PanelContainer
var _ship_name: Label
var _ship_stats: Label
var _scroll: ScrollContainer
var _row_styles:={}
var _row_art:={}
var _background_art: Texture2D
var _header_bar: TextureRect
var _footer_bar: TextureRect
var _body_margin: MarginContainer
var _title: Label
var _requirement: Label
var _cargo: Label
var _message: Label
var _close: Button
var _wallet: Label
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
	mouse_filter=Control.MOUSE_FILTER_STOP;visible=false
	var backdrop:=ColorRect.new();backdrop.color=Color.BLACK;backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel=PanelContainer.new();add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_column=VBoxContainer.new();_panel.add_child(_column);_column.add_theme_constant_override("separation",0)
	var header:=Control.new();header.custom_minimum_size.y=32;_column.add_child(header)
	_header_bar=TextureRect.new();_header_bar.mouse_filter=Control.MOUSE_FILTER_IGNORE;header.add_child(_header_bar)
	_header_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_header_bar.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	_header_bar.stretch_mode=TextureRect.STRETCH_SCALE
	var header_row:=HBoxContainer.new();header.add_child(header_row);header_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var header_margin:=MarginContainer.new();header_margin.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header_row.add_child(header_margin)
	header_margin.add_theme_constant_override("margin_left",12)
	_title=Label.new();header_margin.add_child(_title)
	var tabs:=HBoxContainer.new();header_row.add_child(tabs)
	for tab in ["ship","shop","cargo"]:
		var button:=Button.new();button.toggle_mode=true;button.custom_minimum_size.x=92
		button.pressed.connect(func():select_tab(tab));tabs.add_child(button);_tabs[tab]=button
	_body_margin=MarginContainer.new();_body_margin.size_flags_vertical=Control.SIZE_EXPAND_FILL;_column.add_child(_body_margin)
	var body:=VBoxContainer.new();body.add_theme_constant_override("separation",3);_body_margin.add_child(body)
	_requirement=Label.new();_requirement.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(_requirement)
	_scroll=ScrollContainer.new();_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;_scroll.follow_focus=true;body.add_child(_scroll)
	_list=VBoxContainer.new();_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_list.add_theme_constant_override("separation",2);_scroll.add_child(_list)
	_ship_band=PanelContainer.new();_list.add_child(_ship_band)
	_ship_label=Label.new();_ship_band.add_child(_ship_label)
	_ship_row=PanelContainer.new();_list.add_child(_ship_row)
	var ship_copy:=VBoxContainer.new();ship_copy.add_theme_constant_override("separation",2);_ship_row.add_child(ship_copy)
	_ship_name=Label.new();ship_copy.add_child(_ship_name)
	_ship_stats=Label.new();_ship_stats.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;ship_copy.add_child(_ship_stats)
	for category in CATEGORY_LABELS.size():
		var spacer:=Control.new();_list.add_child(spacer)
		var band:=PanelContainer.new();_list.add_child(band);band.hide()
		var label:=Label.new();band.add_child(label);_categories[category]={"node":band,"label":label,"spacer":spacer}
	for id in [0,22,55,90,81]:_add_row(id)
	_message=Label.new();_message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(_message)
	var footer:=Control.new();footer.custom_minimum_size.y=38;_column.add_child(footer)
	_footer_bar=TextureRect.new();_footer_bar.mouse_filter=Control.MOUSE_FILTER_IGNORE;footer.add_child(_footer_bar)
	_footer_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_footer_bar.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	_footer_bar.stretch_mode=TextureRect.STRETCH_SCALE
	var footer_row:=HBoxContainer.new();footer.add_child(footer_row);footer_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_close=Button.new();_close.pressed.connect(func():action_requested.emit("close",-1));footer_row.add_child(_close)
	var space:=Control.new();space.size_flags_horizontal=Control.SIZE_EXPAND_FILL;footer_row.add_child(space)
	_cargo=Label.new();_cargo.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;footer_row.add_child(_cargo)
	space=Control.new();space.size_flags_horizontal=Control.SIZE_EXPAND_FILL;footer_row.add_child(space)
	_wallet=Label.new();_wallet.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;footer_row.add_child(_wallet)
	resized.connect(_relayout)
	_replacement=ConfirmationDialog.new();_replacement.title="Replace equipment";add_child(_replacement)
	_replacement.confirmed.connect(_confirm_replacement)
	_replacement.canceled.connect(func():_pending_replace={};_refresh())
	set_mobile_layout(false)

func _add_row(id: int) -> void:
	if _rows.has(id):return
	var row:=PanelContainer.new();_list.add_child(row)
	row.focus_mode=Control.FOCUS_ALL
	row.focus_entered.connect(func():_select_row(id))
	row.gui_input.connect(func(event):
		if (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
			row.grab_focus();_select_row(id))
	var line:=HBoxContainer.new();row.add_child(line);line.add_theme_constant_override("separation",8)
	var amount:=Label.new();amount.custom_minimum_size.x=38;amount.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;line.add_child(amount)
	var icon:=TextureRect.new();icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;line.add_child(icon)
	icon.custom_minimum_size=Vector2(88,48) if _mobile else Vector2(68,38)
	var copy:=VBoxContainer.new();copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL;copy.add_theme_constant_override("separation",0);line.add_child(copy)
	var name:=Label.new();name.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;copy.add_child(name)
	var detail:=Label.new();detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;copy.add_child(detail)
	var actions:=HBoxContainer.new();line.add_child(actions);actions.add_theme_constant_override("separation",4)
	var controls:={}
	for action in ["buy","sell","mount","unmount"]:
		var button:=Button.new();actions.add_child(button);controls[action]=button;_buttons.append(button)
		button.pressed.connect(func():_request_action(action,id))
		button.focus_entered.connect(func():_select_row(id))
		_style_button(button)
	_rows[id]={"node":row,"quantity":amount,"icon":icon,"name":name,"detail":detail,"actions":controls,"action_box":actions}
	icon.texture=_icon_texture(id)
	for label in [name,detail,amount]:label.add_theme_font_size_override("font_size",20 if _mobile else 15)
	detail.add_theme_color_override("font_color",Color(0.52,0.62,0.66))

func _request_action(action: String,id: int) -> void:
	if not _active or not visible or not _pending_replace.is_empty():return
	if not _rows.has(id) or not _rows[id].actions.has(action) or _rows[id].actions[action].disabled:return
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
	var row:=PanelContainer.new();_list.add_child(row)
	row.focus_mode=Control.FOCUS_ALL
	row.focus_entered.connect(func():_select_slot(index))
	row.gui_input.connect(func(event):
		if (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
			row.grab_focus();_select_slot(index))
	var line:=HBoxContainer.new();row.add_child(line);line.add_theme_constant_override("separation",8)
	var number:=Label.new();number.custom_minimum_size.x=38;number.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;line.add_child(number)
	var icon:=TextureRect.new();icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;line.add_child(icon)
	icon.custom_minimum_size=Vector2(88,48) if _mobile else Vector2(68,38)
	var copy:=VBoxContainer.new();copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL;copy.add_theme_constant_override("separation",0);line.add_child(copy)
	var label:=Label.new();label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;copy.add_child(label)
	var detail:=Label.new();copy.add_child(detail);detail.add_theme_color_override("font_color",Color(0.52,0.62,0.66))
	var button:=Button.new();line.add_child(button);_buttons.append(button)
	button.focus_entered.connect(func():_select_slot(index));_style_button(button)
	button.pressed.connect(func():
		if not _active or not visible or not _pending_replace.is_empty() or button.disabled:return
		var slot: Variant=_state.loadout.slots[index]
		if slot!=null:slot_action_requested.emit("unmount",int(slot.item_id),index))
	_installed_rows[index]={"node":row,"number":number,"icon":icon,"name":label,"detail":detail,"button":button}
	for text in [label,detail,number]:text.add_theme_font_size_override("font_size",20 if _mobile else 15)

func configure(library: RefCounted, bindings: RefCounted, visuals: RefCounted=null) -> bool:
	error=""
	if library==null or bindings==null or not Definitions.parameters(bindings.station_equipment) or library.manifest.get("content_id")!=bindings.base_content_id:return reject("Equipment presentation requires its matching content pack")
	var cat:=Catalogues.new()
	if not cat.open(library):return reject(cat.error)
	var names:={};var labels:={};var categories:={};var ship_names:={}
	var ids: Array=range(cat.tables.items.size()) if Shopping.available(bindings) else [0,22,55,90,81]
	for id in ids:
		var text_id: int=int(id)+int(bindings.station_equipment.item_text_offset)
		if text_id>=library.strings.size() or library.strings[text_id].is_empty():return reject("Equipment name is unavailable")
		names[id]=library.strings[text_id]
		categories[id]=int(cat.tables.items[id].properties.get(1,-1))
	var ship_base: int=902 if int(bindings.station_equipment.item_text_offset)==1263 else 900 if int(bindings.station_equipment.item_text_offset)==1255 else -1
	if ship_base>=0:
		for id in cat.tables.ships.size():
			if ship_base+id<library.strings.size():ship_names[id]=library.strings[ship_base+id]
	var label_ids:={"hangar":166,"shop":184,"cargo":183,"ship":182,"close":169,"buy":351,"mount":270,"unmount":271,"sell":319,"instruction":1724,"protected":312,"overfilled":193,"blank":173,"primary":254,"secondary":255,"turret":256,"equipment":258,"commodities":259}
	for key in label_ids:
		var text_id: int=label_ids[key]
		if text_id>=library.strings.size() or library.strings[text_id].is_empty():return reject("Equipment action text is unavailable")
		labels[key]=library.strings[text_id]
	var art: RefCounted
	var pixels: Texture2D
	var metadata:=PackedByteArray()
	var row_art:={}
	if visuals!=null:
		if visuals.base_content_id!=bindings.base_content_id:return reject("Hangar artwork belongs to another content pack")
		art=OriginalUI.new()
		if not art.configure(library,bindings,visuals):return reject(art.error)
		var item_image: Image=visuals.load_image(ITEM_ATLAS)
		if item_image==null:return reject(visuals.error)
		metadata=library.read_resource(ITEM_ATLAS,Atlas.MAX_BYTES)
		if metadata.is_empty():return reject(library.error)
		var region: Dictionary=Atlas.new().region(metadata,0)
		if region.is_empty() or region.size!=item_image.get_size():return reject("Hangar item atlas metadata disagrees with imported pixels")
		pixels=ImageTexture.create_from_image(item_image)
		# This additional Hangar mapping is verified on the two Mac layouts.
		# Other profiles retain the existing native row fallback.
		if library.manifest.profile.edition=="mac-full-hd":
			var rules: Dictionary=bindings.mido_travel.map.ui
			var interface_resource: String=rules.atlas_resources[str(int(rules.texture_id))]
			var interface_metadata: PackedByteArray=library.read_resource(interface_resource,Atlas.MAX_BYTES)
			var interface_image: Image=visuals.load_image(interface_resource)
			if interface_metadata.is_empty() or interface_image==null:return reject(library.error+visuals.error)
			var interface_pixels:=ImageTexture.create_from_image(interface_image)
			for id in ROW_ART_IDS:
				var alias: Dictionary=bindings.resolve_image_region(id)
				if alias.is_empty() or int(alias.texture_id)!=int(rules.texture_id):return reject("Hangar row artwork lost its source interface alias")
				var area: Dictionary=Atlas.new().region(interface_metadata,int(alias.region))
				if area.is_empty() or area.size!=interface_image.get_size():return reject("Hangar row artwork disagrees with source pixels")
				var texture:=AtlasTexture.new();texture.atlas=interface_pixels;texture.region=Rect2(area.rect);texture.filter_clip=true
				texture.set_meta("source_image_id",id);row_art[id]=texture
			for id in [1145,1154,1161]:
				var mirrored: Image=row_art[id].get_image();mirrored.flip_x();row_art[-id]=ImageTexture.create_from_image(mirrored)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":library.active_language}
	_names=names;_labels=labels;_item_categories=categories;_ship_names=ship_names;_catalogues=cat
	_art=art;_item_pixels=pixels;_item_metadata=metadata;_icon_cache={};_row_art=row_art
	_background_art=null if art==null else art.sprites[int(bindings.mido_travel.map.ui.panel_background_image_id)]
	_tab="shop";_state={};_message.text="";_selected_id=-1;_selected_slot=-1
	_title.text=labels.hangar;_close.text=labels.close;_ship_label.text=labels.ship
	for key in _tabs:_tabs[key].text=labels[key]
	for category in _categories:_categories[category].label.text=labels[["primary","secondary","turret","equipment","commodities"][category]]
	_header_bar.texture=null if _art==null else _art.sprites[int(bindings.mido_travel.map.ui.footer_image_id)]
	_footer_bar.texture=_header_bar.texture
	var theme: Theme
	if _art!=null:
		theme=Theme.new();theme.default_font=_art.font
	# Keep the previous bitmap font alive while Godot invalidates the labels'
	# shaped text during this theme swap. Dropping its last reference inside the
	# assignment leaves TextServer querying a freed font descriptor.
	var previous_theme: Theme=_panel.theme
	_panel.theme=theme
	for id in _rows:_rows[id].icon.texture=_icon_texture(int(id))
	set_mobile_layout(_mobile)
	return true

func _icon_texture(id: int) -> Texture2D:
	if _item_pixels==null or id<0 or not _item_categories.has(id):return null
	if _icon_cache.has(id):return _icon_cache[id]
	var region: Dictionary=Atlas.new().region(_item_metadata,id)
	if region.is_empty() or Vector2(region.size)!=_item_pixels.get_size():return null
	var texture:=AtlasTexture.new();texture.atlas=_item_pixels;texture.region=Rect2(region.rect);texture.filter_clip=true
	texture.set_meta("source_resource",ITEM_ATLAS);texture.set_meta("source_region",id)
	_icon_cache[id]=texture
	return texture

func _select_row(id: int) -> void:
	if not _active or not visible or not _rows.has(id):return
	_selected_id=id;_selected_slot=-1;_style_rows()

func _select_slot(index: int) -> void:
	if not _active or not visible or not _installed_rows.has(index):return
	_selected_slot=index;_selected_id=-1;_style_rows()

func present(state: Dictionary) -> bool:
	error=""
	if not state.get("hangar_open",false):clear();return true
	if _identity.is_empty() or not state.get("equipment") is Dictionary:return reject("Equipment presentation is unavailable")
	for key in _identity:
		if state.get(key)!=_identity[key]:return reject("Equipment presentation belongs to another session")
	var ids:=[]
	for entry in state.equipment.cargo.entries:ids.append(entry.item_id)
	for row in state.equipment.get("market_rows",[]):ids.append(row.item_id)
	for slot in state.equipment.loadout.slots:
		if slot!=null and slot.item_id not in ids:ids.append(slot.item_id)
	for id in ids:
		if not _names.has(id):return reject("The current inventory item has no localized name")
	for id in ids:_add_row(int(id))
	var ship_id: int=int(state.equipment.loadout.ship_id)
	if ship_id<0 or ship_id>=_catalogues.tables.ships.size():return reject("The displayed ship is absent from this content pack")
	_slot_categories=[]
	var stats: Dictionary=_catalogues.tables.ships[ship_id].stats
	var slot_properties:=["primary_slots","secondary_slots","turret_slots","equipment_slots"]
	for category in slot_properties.size():
		for slot in int(stats[slot_properties[category]]):_slot_categories.append(category)
	if _slot_categories.size()!=state.equipment.loadout.slots.size():return reject("The ship slot display disagrees with its loadout")
	for i in _slot_categories.size():_add_installed_row(i)
	_credits=int(state.get("contracts",{}).get("credits",0))
	if _state!=state.equipment:_state=state.equipment.duplicate(true);_message.text=""
	visible=true;_refresh();_relayout()
	return true

func select_tab(tab: String) -> void:
	if not _active or not visible or not _tabs.has(tab):return
	_tab=tab;_message.text="";_scroll.scroll_vertical=0;_refresh()

func _refresh() -> void:
	if _state.is_empty():return
	var ordinary: bool=_state.get("ordinary_shopping_open",false)
	var fitting: bool=_state.has("fitting_support")
	var controls: bool=_active and _pending_replace.is_empty()
	var requirements: Dictionary=_state.requirements
	_title.text=_labels.hangar
	_requirement.text="Equipment fitting is not yet available here." if ordinary and not fitting else "Weapon: %s   ·   Armor: %s"%["mounted" if requirements.weapon_installed else "needed","mounted" if requirements.armor_installed else "needed"]
	if fitting:
		var stats: Dictionary=_state.fitting_stats
		_ship_stats.text="Hull %d   Armor %d   Shield %d   Handling %d%%   Passengers %d"%[stats.hull,stats.armor,stats.shield,stats.handling_bonus_percent,stats.passenger_capacity]
	_ship_stats.visible=fitting
	_ship_name.text=_ship_names.get(int(_state.loadout.ship_id),_labels.ship)
	_ship_band.visible=_tab=="ship";_ship_row.visible=_tab=="ship"
	_requirement.visible=not ordinary or (_tab=="ship" and not fitting)
	_cargo.text="%d / %dt"%[int(_state.cargo.used),int(_state.cargo.capacity)]
	_cargo.tooltip_text=_labels.cargo
	var overfilled: bool=_state.cargo.used>_state.cargo.capacity
	if overfilled:_cargo.text+="\n"+_labels.overfilled
	_footer_bar.get_parent().custom_minimum_size.y=(72 if _mobile else 58) if overfilled else (52 if _mobile else 38)
	_wallet.text="%d$"%_credits if ordinary else ""
	for tab in _tabs:_tabs[tab].set_pressed_no_signal(tab==_tab);_tabs[tab].disabled=not controls
	for id in _rows:
		var row: Dictionary=_rows[id];var stock:=0;var owned:=0;var price:=0;var price_known:=false;var offered:=false;var mission:=false
		for item in _state.get("market_rows",[]):
			if item.item_id==id:offered=true;price=int(item.unit_price);price_known=true;mission=item.mission
		for offer in _state.stock:
			if offer.item_id==id:stock=int(offer.quantity);price=int(offer.unit_price);price_known=true
		for entry in _state.cargo.entries:
			if entry.item_id==id:owned=int(entry.quantity)
		var protected: bool=mission or id in _state.get("protected_item_ids",[90,81])
		row.node.visible=(offered if ordinary else id in [0,22,55]) if _tab=="shop" else owned>0 and (_tab=="cargo" or int(_item_categories.get(id,-1)) in [0,1,2,3])
		row.name.text=_names.get(id,"")
		row.quantity.text=str(stock) if _tab=="shop" else str(owned)
		row.icon.texture=_icon_texture(int(id))
		row.caption=_labels.protected if protected else "%d$"%price if price_known else ""
		row.detail.text=row.caption
		row.detail.visible=not row.detail.text.is_empty()
		row.detail.add_theme_color_override("font_color",Color(0.48,0.68,0.24) if _tab=="shop" and stock>0 and price<=_credits else Color(0.52,0.62,0.66))
		var reason: String=_state.get("fitting_support",{}).get(id,"")
		row.node.tooltip_text=reason
		row.actions.mount.tooltip_text=reason
		for action in row.actions:
			var button: Button=row.actions[action]
			button.text=_labels[action]
			button.visible=(action=="buy" and _tab=="shop") or (action=="sell" and _tab=="cargo") or (action=="mount" and _tab in ["cargo","ship"])
			if ordinary and not fitting and action in ["mount","unmount"]:button.visible=false
			button.disabled=not controls or protected or (action=="buy" and (stock==0 or (ordinary and price>_credits))) or (action=="mount" and (not _mount_has_position(int(id)) or (fitting and not reason.is_empty())))
	for index in _installed_rows:
		var row: Dictionary=_installed_rows[index]
		var slot: Variant=_state.loadout.slots[index] if index<_state.loadout.slots.size() else null
		row.node.visible=_tab=="ship" and index<_slot_categories.size()
		row.number.text="" if slot==null or int(slot.quantity)==1 else str(slot.quantity)
		row.icon.texture=null if slot==null else _icon_texture(int(slot.item_id))
		row.name.text=_labels.blank if slot==null else _names[int(slot.item_id)]
		row.detail.text=""
		if slot!=null:
			for offer in _state.get("market_rows",[]):
				if int(offer.item_id)==int(slot.item_id):row.detail.text="%d$"%int(offer.unit_price);break
		row.detail.visible=not row.detail.text.is_empty()
		row.button.text=_labels.unmount
		row.button.visible=slot!=null and index==_selected_slot
		row.button.disabled=not controls or (slot!=null and slot.item_id in _state.get("protected_item_ids",[]))
	_close.disabled=not controls
	_order_rows();_style_rows()

func _mount_has_position(item_id: int) -> bool:
	if _state.get("fitting_conflicts",{}).has(item_id):return true
	var category: int=int(_item_categories.get(item_id,-1))
	for index in _slot_categories.size():
		if _slot_categories[index]==category and _state.loadout.slots[index]==null:return true
	return false

func _order_rows() -> void:
	var position:=2
	var preceding_group:=_tab=="ship"
	for category in CATEGORY_LABELS.size():
		var members:=[]
		if _tab=="ship":
			for slot in _installed_rows:
				if _installed_rows[slot].node.visible and slot<_slot_categories.size() and _slot_categories[slot]==category:members.append(_installed_rows[slot].node)
		var ids: Array=_rows.keys();ids.sort()
		for id in ids:
			if _rows[id].node.visible and int(_item_categories.get(id,-1))==category:members.append(_rows[id].node)
		var band: Control=_categories[category].node
		var spacer: Control=_categories[category].spacer
		spacer.visible=not members.is_empty() and preceding_group
		if not members.is_empty():preceding_group=true
		spacer.custom_minimum_size.y=14 if _mobile else 24
		_list.move_child(spacer,position);position+=1
		band.visible=not members.is_empty()
		_list.move_child(band,position);position+=1
		for member in members:_list.move_child(member,position);position+=1

func _style_rows() -> void:
	if _row_styles.is_empty():return
	for id in _rows:
		var row: Dictionary=_rows[id]
		row.node.add_theme_stylebox_override("panel",_row_styles[id==_selected_id])
		row.action_box.visible=id==_selected_id
		row.detail.text=row.get("caption","")
		if id==_selected_id and not row.node.tooltip_text.is_empty():
			row.detail.text+=("\n" if not row.detail.text.is_empty() else "")+row.node.tooltip_text
		row.detail.visible=not row.detail.text.is_empty()
	for index in _installed_rows:
		var row: Dictionary=_installed_rows[index]
		row.node.add_theme_stylebox_override("panel",_row_styles[index==_selected_slot])
		row.button.visible=index==_selected_slot and not _state.is_empty() and index<_state.loadout.slots.size() and _state.loadout.slots[index]!=null

func _style_button(button: Button) -> void:
	if _art!=null:_art.apply_button(button,_mobile,button==_close)
	button.custom_minimum_size.y=44 if _mobile else 28
	button.add_theme_font_size_override("font_size",20 if _mobile else 15)

func _row_style(selected: bool) -> StyleBox:
	if not _row_art.is_empty():
		var center:=1160 if selected else 1144
		var cap:=1161 if selected else 1145
		return OriginalUI.button_style(_row_art,[cap,center,-cap],54 if _mobile else 42)
	var style:=StyleBoxFlat.new();style.bg_color=Color(0.085,0.063,0.032,0.96) if selected else Color(0.025,0.055,0.075,0.92)
	style.border_color=Color(0.78,0.57,0.28,0.96) if selected else Color(0.10,0.19,0.23,0.8)
	style.set_border_width_all(1)
	if selected:style.border_width_left=6;style.border_width_right=6
	style.content_margin_left=8;style.content_margin_right=8;style.content_margin_top=2;style.content_margin_bottom=2
	return style

func set_active(value: bool) -> void:_active=value;_refresh()
func show_error(message: String) -> void:_message.text=message

func set_mobile_layout(value: bool) -> void:
	_mobile=value
	var font_size:=20 if value else 15
	for label in [_title,_requirement,_cargo,_message,_wallet,_ship_label,_ship_name,_ship_stats]:label.add_theme_font_size_override("font_size",font_size)
	for row in _rows.values():
		row.name.add_theme_font_size_override("font_size",font_size)
		row.detail.add_theme_font_size_override("font_size",font_size)
		row.quantity.add_theme_font_size_override("font_size",font_size)
		row.icon.custom_minimum_size=Vector2(88,48) if value else Vector2(68,38)
	for row in _installed_rows.values():
		for label in [row.name,row.detail,row.number]:label.add_theme_font_size_override("font_size",font_size)
		row.icon.custom_minimum_size=Vector2(88,48) if value else Vector2(68,38)
	var style:=StyleBoxFlat.new();style.bg_color=Color(0.007,0.014,0.020,1.0)
	style.content_margin_left=0;style.content_margin_right=0;style.content_margin_top=0;style.content_margin_bottom=0
	if _background_art!=null:
		var source_background:=StyleBoxTexture.new();source_background.texture=_background_art
		source_background.axis_stretch_horizontal=StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		source_background.axis_stretch_vertical=StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:source_background.set_content_margin(side,0)
		_panel.add_theme_stylebox_override("panel",source_background)
	else:_panel.add_theme_stylebox_override("panel",style)
	_header_bar.get_parent().custom_minimum_size.y=48 if value else 32
	_footer_bar.get_parent().custom_minimum_size.y=52 if value else 38
	_row_styles={false:_row_style(false),true:_row_style(true)}
	_ship_row.add_theme_stylebox_override("panel",_row_styles[false])
	var bands: Array=_categories.values()+[{"node":_ship_band,"label":_ship_label}]
	for band in bands:
		band.label.add_theme_font_size_override("font_size",font_size)
		var band_style:=StyleBoxFlat.new();band_style.bg_color=Color(0.08,0.17,0.22,0.98)
		band_style.border_color=Color(0.35,0.55,0.65,0.9);band_style.border_width_top=1
		band_style.content_margin_left=7;band_style.content_margin_right=7;band_style.content_margin_top=2;band_style.content_margin_bottom=2
		if not _row_art.is_empty():
			var source_style:=OriginalUI.button_style(_row_art,[1154,1153,-1154],28 if value else 20)
			source_style.content_margin_left=7;source_style.content_margin_right=7;source_style.content_margin_top=2;source_style.content_margin_bottom=2
			band.node.add_theme_stylebox_override("panel",source_style)
		else:band.node.add_theme_stylebox_override("panel",band_style)
	for button in _buttons+_tabs.values()+[_close]:_style_button(button)
	for tab in _tabs.values():tab.custom_minimum_size.x=116 if value else 92
	_style_rows();_relayout()

func _relayout() -> void:
	if size.x<=0 or size.y<=0:return
	var content_width:=minf(1320 if _mobile else 1140,maxf(1,size.x-24))
	var inset:=maxi(12,roundi((size.x-content_width)/2))
	_body_margin.add_theme_constant_override("margin_left",inset)
	_body_margin.add_theme_constant_override("margin_right",inset)
	_body_margin.add_theme_constant_override("margin_top",8 if _mobile else 24)
	_body_margin.add_theme_constant_override("margin_bottom",8)

func _place_panel() -> void:
	_relayout()

func clear() -> void:
	visible=false;_state={};_message.text="";_pending_replace={};_selected_id=-1;_selected_slot=-1
	if _replacement!=null:_replacement.hide()
func reject(message: String) -> bool:error=message;return false
