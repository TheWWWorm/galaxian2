extends Control
## Native lounge selection and acknowledged results using the original atlas,
## font, generated portraits and localized contract text. No UI artwork is shipped.
signal action_requested(action: String,id: int)
const Art=preload("res://src/presentation/original_ui.gd")
const Portraits=preload("res://src/presentation/portrait_compositor.gd")
var error:=""
var _art: RefCounted
var _library: RefCounted
var _bindings: RefCounted
var _visuals: RefCounted
var _catalogues: RefCounted
var _mobile:=false
var _active:=true
var _state:={}
var _population:={}
var _previews:={}
var _portraits:={}
var _client_definition:={}
var _client_portrait: Texture2D
var _selected:=-1
var _confirming:=false
var _panel: PanelContainer
var _title: Label
var _balance: Label
var _contact_ids: Array[int]=[]
var _scene: Node3D
var _room_title: Label
var _footer: Panel
var _portrait: TextureRect
var _name: Label
var _body: RichTextLabel
var _yes: Button
var _no: Button
var _back: Button

func _init() -> void:
	visible=false;mouse_filter=Control.MOUSE_FILTER_STOP
	_room_title=Label.new();_room_title.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(_room_title)
	_footer=Panel.new();add_child(_footer)
	_balance=Label.new();_balance.mouse_filter=Control.MOUSE_FILTER_IGNORE;_footer.add_child(_balance)
	_back=Button.new();_back.pressed.connect(back);_footer.add_child(_back)
	_panel=PanelContainer.new();add_child(_panel)
	var margin:=MarginContainer.new();_panel.add_child(margin)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,7)
	var column:=VBoxContainer.new();margin.add_child(column)
	_title=Label.new();_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(_title)
	var row:=HBoxContainer.new();row.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(row)
	_portrait=TextureRect.new();_portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT;row.add_child(_portrait)
	var text_column:=VBoxContainer.new();text_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(text_column)
	_name=Label.new();_name.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;text_column.add_child(_name)
	_body=RichTextLabel.new();_body.bbcode_enabled=false;_body.scroll_active=true
	_body.size_flags_vertical=Control.SIZE_EXPAND_FILL;text_column.add_child(_body)
	var actions:=VBoxContainer.new();column.add_child(actions)
	_yes=Button.new();_yes.pressed.connect(confirm);actions.add_child(_yes)
	_no=Button.new();_no.pressed.connect(back);actions.add_child(_no)
	resized.connect(_layout)
	_panel.minimum_size_changed.connect(_layout)
	gui_input.connect(_room_input)

func set_scene(scene: Node3D) -> void:
	_scene=scene
	if is_instance_valid(_scene):_scene.select_contact(_selected)
	_layout()

func _process(_delta: float) -> void:
	if visible and is_instance_valid(_scene):_layout()

func _room_input(event: InputEvent) -> void:
	if not _active or _state.is_empty() or not _state.pending_result.is_empty() or not is_instance_valid(_scene):return
	var point:=Vector2.ZERO;var pressed:=false
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:point=event.position;pressed=true
	if event is InputEventScreenTouch and event.pressed:point=event.position;pressed=true
	if not pressed:return
	var rows: Array=_scene.screen_contacts()
	# The scene orders overlapping bodies from nearest to farthest.
	for row in rows:
		if row.rect.grow(12 if _mobile else 3).has_point(point):select_contact(row.id);accept_event();return
	_selected=-1;_confirming=false;_scene.select_contact(-1);_refresh();_layout();accept_event()

func configure(library: RefCounted,bindings: RefCounted,visuals: RefCounted,catalogues: RefCounted) -> bool:
	var art:=Art.new()
	if not art.configure(library,bindings,visuals):return reject(art.error)
	_art=art;_library=library;_bindings=bindings;_visuals=visuals;_catalogues=catalogues
	var original:=Theme.new();original.default_font=art.font;theme=original
	clear();_population={};_portraits={};_client_definition={};_client_portrait=null
	set_mobile_layout(_mobile)
	return true

func configured_for(bindings: RefCounted,language: String) -> bool:
	return _art!=null and _art.identity=={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":language}

func present(state: Dictionary) -> bool:
	error=""
	var career: Dictionary=state.get("contracts",{})
	var pending: Dictionary=career.get("pending_result",{})
	if career.is_empty() or (not state.get("lounge_open",false) and pending.is_empty()):clear();return true
	if _art==null:return reject("The original lounge interface is not prepared")
	for key in ["base_content_id","binding_id"]:
		if state.get(key)!=_art.identity[key] or career.get(key)!=_art.identity[key]:return reject("The lounge belongs to another session")
	var next:={}
	for key in ["station_id","offers","mission","pending_result","credits","accepted_contact","completed_side_missions"]:next[key]=career.get(key,{}).duplicate(true) if career.get(key) is Dictionary else career.get(key)
	next.cargo=state.get("cargo",{}).duplicate(true)
	var population: Dictionary=career.get("population",{})
	var client: Dictionary=career.get("accepted_contact",{}).get("portrait",{})
	if client!=_client_definition:
		var image: Texture2D
		if not client.is_empty():
			var composer:=Portraits.new()
			var composite: Dictionary=composer.compose_definition(_library,_bindings,_visuals,0,"large",client)
			if composite.is_empty():return reject(composer.error)
			image=ImageTexture.create_from_image(composite.image)
		_client_definition=client.duplicate(true);_client_portrait=image
	if _population!=population:
		var portraits:={};var composer:=Portraits.new()
		for contact in population.get("contacts",[]):
			var composite: Dictionary=composer.compose_definition(_library,_bindings,_visuals,contact.contact_id,"large",contact.portrait)
			if composite.is_empty():return reject(composer.error)
			portraits[contact.contact_id]=ImageTexture.create_from_image(composite.image)
		_population=population.duplicate(true);_portraits=portraits;_selected=-1;_confirming=false
		_contact_ids=[]
		for contact in population.get("contacts",[]):_contact_ids.append(int(contact.contact_id))
	if _state!=next:_state=next;_confirming=false
	_previews=state.get("contract_previews",{}).duplicate(true)
	visible=true;_refresh();_layout()
	return true

func select_contact(id: int) -> void:
	if not _active or not visible or not _state.pending_result.is_empty():return
	if not _portraits.has(id):return
	_selected=id;_confirming=false;_body.scroll_to_line(0)
	if is_instance_valid(_scene):_scene.select_contact(id)
	_refresh();_layout()

func text(id: int) -> String:return _library.strings[id] if id>=0 and id<_library.strings.size() else ""
func money(value: int) -> String:return str(value)+"$"

func format_job(template: String,mission: Dictionary) -> String:
	var station:=int(mission.get("station_id",-1))
	var name: String=_catalogues.tables.stations[station].name if station>=0 and station<_catalogues.tables.stations.size() else ""
	return template.replace("#S",name).replace("#Q",str(int(mission.get("quantity",0)))).replace("#P",text(int(mission.get("cargo_text_id",-1)))).replace("#C",money(int(mission.get("reward",0))+int(mission.get("bonus",0))))

func _refresh() -> void:
	if _state.is_empty() or _art==null:return
	var pending: Dictionary=_state.pending_result
	_title.text=text(387);_balance.text=money(int(_state.credits))
	_back.text=text(169);_no.text=text(848);_yes.text=text(847)
	_back.visible=pending.is_empty();_no.visible=false;_yes.visible=false
	_panel.visible=not pending.is_empty() or _selected>=0
	_room_title.text=text(387);_room_title.visible=pending.is_empty()
	_portrait.texture=null;_name.text="";_body.text=""
	if not pending.is_empty():
		_portrait.texture=_client_portrait
		_title.text=text(343+int(pending.kind)) if pending.get("completed",false) else text(381)
		_name.text=_state.accepted_contact.get("name","")
		_body.text=text(753).replace("#C",money(int(pending.get("reward_credits",pending.get("credit_delta",0))))) if pending.get("completed",false) else text(381)
		_yes.visible=true;_yes.text=text(180)
	else:
		var row: Dictionary=_state.offers.get(_selected,{})
		_portrait.texture=_portraits.get(_selected)
		for contact in _population.get("contacts",[]):
			if contact.contact_id==_selected:_name.text=contact.name;break
		if row.is_empty():
			_body.text=text(614) if _selected<0 else "This contact's service is not yet available."
		else:
			var mission: Dictionary=row.offer.mission
			_title.text=text(int(mission.title_text_id))
			_body.text=format_job(text(int(mission.briefing_text_id)),mission)+"\n\n"+text(753).replace("#C",money(int(mission.reward)+int(mission.bonus)))
			if row.consumed:_body.text+="\n\n"+text(841)
			else:
				var preview: Dictionary=_previews.get(_selected,{})
				if preview.get("can_accept",false):
					_yes.visible=true
					if _confirming:
						_body.text=text(850)+( "\n\n"+text(int(preview.replacement_text_id)) if preview.replacement_required else "")
						_yes.text=text(133);_no.visible=true;_no.text=text(134)
				else:
					_body.text+="\n\n"+text(int(preview.get("reason_text_id",-1))).replace("#Q",str(maxi(int(preview.get("cargo_tons",0)),int(preview.get("passenger_places",0))))).replace("#C",money(int(preview.get("missing_credits",0))))
					if not preview.get("unsupported_reason","").is_empty():_body.text+=preview.unsupported_reason
	_portrait.visible=_portrait.texture!=null
	for button in [_yes,_no,_back]:button.disabled=not _active

func confirm() -> void:
	if not _active or not visible or _state.is_empty():return
	if not _state.pending_result.is_empty():action_requested.emit("result_close",int(_state.pending_result.serial));return
	var preview: Dictionary=_previews.get(_selected,{})
	if not preview.get("can_accept",false):return
	if not _confirming:_confirming=true;_refresh();return
	action_requested.emit("replace" if preview.replacement_required else "accept",_selected)

func back() -> void:
	if not _active or not visible or not _state.pending_result.is_empty():return
	if _confirming:_confirming=false;_refresh()
	else:action_requested.emit("close",-1)

func handle_event(event: InputEvent) -> bool:
	if not visible or not _active:return false
	var code:=-1
	if event is InputEventKey and event.pressed and not event.echo:code=event.physical_keycode if event.physical_keycode else event.keycode
	if code in [KEY_ENTER,KEY_KP_ENTER]:confirm();return true
	if code==KEY_BACKSPACE:back();return true
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index==JOY_BUTTON_A:confirm();return true
		if event.button_index==JOY_BUTTON_B:back();return true
	var move:=0
	if code in [KEY_LEFT,KEY_UP]:move=-1
	if code in [KEY_RIGHT,KEY_DOWN]:move=1
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index in [JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_UP]:move=-1
		if event.button_index in [JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_DPAD_DOWN]:move=1
	if move!=0 and _state.pending_result.is_empty() and not _contact_ids.is_empty():
		select_contact(_contact_ids[posmod(_contact_ids.find(_selected)+move,_contact_ids.size())]);return true
	return false

func set_active(value: bool) -> void:
	if value==_active:return
	_active=value;_refresh()

func set_mobile_layout(value: bool) -> void:
	_mobile=value;_apply_theme();_layout()

func _apply_theme() -> void:
	if _art==null:return
	_panel.add_theme_stylebox_override("panel",_art.styles[_mobile].panel)
	_footer.add_theme_stylebox_override("panel",_art.styles[_mobile].panel)
	for label in [_title,_balance,_name,_room_title]:label.add_theme_font_size_override("font_size",18 if _mobile else 14)
	_body.add_theme_font_size_override("normal_font_size",18 if _mobile else 14)
	for button in [_yes,_no,_back]:_art.apply_button(button,_mobile,button==_back)
	_portrait.custom_minimum_size=Vector2(84,112) if _mobile else Vector2(64,86)

func _layout() -> void:
	if _art==null or not visible or size.x<=0 or size.y<=0:return
	var footer_height:=50.0 if _mobile else 36.0
	_footer.position=Vector2(0,size.y-footer_height);_footer.size=Vector2(size.x,footer_height)
	_back.position=Vector2(6,3);_back.size=Vector2(120 if _mobile else 96,footer_height-6)
	_balance.size=_balance.get_minimum_size();_balance.position=Vector2(size.x-_balance.size.x-12,(footer_height-_balance.size.y)/2)
	_room_title.position=Vector2(10,6)
	_panel.size=Vector2(minf(440 if _mobile else 350,size.x-20),minf(265 if _mobile else 235,size.y-footer_height-44))
	var point: Vector2=(size-_panel.size)/2
	if is_instance_valid(_scene) and _selected>=0:
		for row in _scene.screen_contacts():
			if row.id!=_selected:continue
			point=Vector2(row.rect.position.x-_panel.size.x-16,row.anchor.y-_panel.size.y*0.45)
			if point.x<10:point.x=row.rect.end.x+16
			break
	point.x=clampf(point.x,10,maxf(10,size.x-_panel.size.x-10))
	point.y=clampf(point.y,32,maxf(32,size.y-footer_height-_panel.size.y-8))
	_panel.position=point

func snapshot() -> Dictionary:
	return {"visible":visible,"selected":_selected,"confirming":_confirming,"panel_rect":Rect2(_panel.position,_panel.size),"title":_title.text,"body":_body.text,"accept_visible":_yes.visible,"pending_result":_state.get("pending_result",{}).duplicate(true)}
func show_error(message: String) -> void:_body.text=message
func clear() -> void:
	visible=false;_state={};_confirming=false;_selected=-1
	if is_instance_valid(_scene):_scene.select_contact(-1)
	_scene=null
func reject(message: String) -> bool:error=message;return false
