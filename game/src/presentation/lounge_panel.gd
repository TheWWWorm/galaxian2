extends Control
## Native lounge selection and acknowledged results using the original atlas,
## font, generated portraits and localized contract text. No UI artwork is shipped.
signal action_requested(action: String,id: int)
const Art=preload("res://src/presentation/original_ui.gd")
const Portraits=preload("res://src/presentation/portrait_compositor.gd")
const Recipe=preload("res://src/content/mission_recipe.gd")
const Dialogue=preload("res://src/simulation/lounge_dialogue.gd")
const ContractOffer=preload("res://src/simulation/contract_offer.gd")
const MAC_LABEL_IDS={614:616,753:755,754:756,837:839,838:840,839:841,841:843,843:845,844:846,845:847,846:848,847:849,848:850,850:852,855:857,856:858,857:859}
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
## The contact whose offer was taken while selected; selecting it again is a revisit.
var _taken:=-1
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
	_no=Button.new();_no.pressed.connect(decline);actions.add_child(_no)
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
	var refresh:=not visible
	if client!=_client_definition:
		var image: Texture2D
		if not client.is_empty():
			var composer:=Portraits.new()
			var composite: Dictionary=composer.compose_definition(_library,_bindings,_visuals,0,"large",client)
			if composite.is_empty():return reject(composer.error)
			image=ImageTexture.create_from_image(composite.image)
		_client_definition=client.duplicate(true);_client_portrait=image;refresh=true
	if _population!=population:
		var portraits:={};var composer:=Portraits.new()
		for contact in population.get("contacts",[]):
			var composite: Dictionary=composer.compose_definition(_library,_bindings,_visuals,contact.contact_id,"large",contact.portrait)
			if composite.is_empty():return reject(composer.error)
			portraits[contact.contact_id]=ImageTexture.create_from_image(composite.image)
		_population=population.duplicate(true);_portraits=portraits;_selected=-1;_confirming=false;_taken=-1
		_contact_ids=[]
		for contact in population.get("contacts",[]):_contact_ids.append(int(contact.contact_id))
		refresh=true
	var previews: Dictionary=state.get("contract_previews",{})
	if _state!=next or _previews!=previews:
		_state=next;_previews=previews.duplicate(true);_confirming=false;refresh=true
	visible=true
	# Station frames continue while the player reads or confirms an offer.
	# Rebuild text and controls only when their displayed state changes.
	if refresh:_refresh();_layout()
	return true

func select_contact(id: int) -> void:
	if not _active or not visible or not _state.pending_result.is_empty():return
	if not _portraits.has(id):return
	action_requested.emit("select",id)
	_selected=id;_confirming=false;_taken=-1;_body.scroll_to_line(0)
	if is_instance_valid(_scene):_scene.select_contact(id)
	_refresh();_layout()

func text(id: int) -> String:return _library.strings[id] if id>=0 and id<_library.strings.size() else ""

func label_text(id: int) -> String:
	# Fixed interface labels use source-specific IDs. Imported job descriptions
	# and replacement notices already carry their own original text IDs.
	if _bindings.early_contracts.get("briefing_text_base")==775:id=int(MAC_LABEL_IDS.get(id,id))
	return text(id)

## A taken offer (SpaceLounge::onKeyPress, startChat). Right after the deal a
## seller says one of 837-839 (the source picks at random) and a job client
## 841, or 843 for a Challenge. Selected again, a purchase client says 844, a
## Challenge client 846, everyone else 845.
func taken_text(kind: int=-1,job: bool=false) -> String:
	if _taken==_selected:return label_text((843 if kind==12 else 841) if job else 837+_selected%3)
	return label_text(844 if kind==8 else 846 if kind==12 else 845)
func money(value: int) -> String:return str(value)+"$"

## The result the player is looking at (empty when none is open).
func pending_result() -> Dictionary:return {} if _state.is_empty() else _state.get("pending_result",{}).duplicate(true)

func format_job(template: String,mission: Dictionary) -> String:return format_job_text(_library,_catalogues,_bindings,template,mission)

## Shared with the Missions log: fills a job text's station, target, goods and pay tokens.
static func format_job_text(library: RefCounted,catalogues: RefCounted,bindings: RefCounted,template: String,mission: Dictionary) -> String:
	var station:=int(mission.get("station_id",-1))
	var name: String=catalogues.tables.stations[station].name if station>=0 and station<catalogues.tables.stations.size() else ""
	var cargo_text:=int(mission.get("cargo_text_id",-1))
	var delivery:=Recipe.station_delivery(bindings.early_contracts,mission)
	if delivery.get("briefing_location")=="system":name=catalogues.tables.systems[int(mission.system_id)].name
	var required: Dictionary=delivery.get("required_cargo",{})
	if not required.is_empty():cargo_text=int(bindings.station_equipment.item_text_offset)+int(required.item_id)
	var goods: String=library.strings[cargo_text] if cargo_text>=0 and cargo_text<library.strings.size() else ""
	return template.replace("#S",name).replace("#N",str(mission.get("target_name",""))).replace("#Q",str(int(mission.get("quantity",0)))).replace("#P",goods).replace("#C",str(int(mission.get("reward",0))+int(mission.get("bonus",0)))+"$")

func _refresh() -> void:
	if _state.is_empty() or _art==null:return
	var pending: Dictionary=_state.pending_result
	var show_yes:=false;var show_no:=false
	_title.text=text(387);_balance.text=money(int(_state.credits))
	_back.text=text(169);_no.text=label_text(848);_yes.text=label_text(847)
	_back.visible=pending.is_empty()
	_panel.visible=not pending.is_empty() or _selected>=0
	_room_title.text=text(387);_room_title.visible=pending.is_empty()
	_portrait.texture=null;_name.text="";_body.text=""
	if not pending.is_empty():
		_portrait.texture=_client_portrait
		_title.text=text(343+int(pending.kind)) if pending.get("completed",false) else text(381)
		_name.text=_state.accepted_contact.get("name","")
		_body.text=label_text(753).replace("#C",money(int(pending.get("reward_credits",pending.get("credit_delta",0))))) if pending.get("completed",false) else text(381)
		if pending.has("result_text_id"):_body.text=format_job(text(int(pending.result_text_id)),pending)
		show_yes=true;_yes.text=text(180)
	else:
		var row: Dictionary=_state.offers.get(_selected,{})
		_portrait.texture=_portraits.get(_selected)
		for contact in _population.get("contacts",[]):
			if contact.contact_id==_selected:_name.text=contact.name;break
		var service: Dictionary=_previews.get(_selected,{})
		if service.get("kind")=="merchant":
			var item_name:=text(int(_bindings.station_equipment.item_text_offset)+int(service.item_id))
			var offer_text:=label_text(855).replace("#Q",str(service.quantity)).replace("#P",item_name).replace("#C",money(int(service.total_price)))
			_body.text=offer_text
			if service.consumed:_body.text+="\n\n"+taken_text()
			elif service.can_accept:
				show_yes=true
				if _confirming:_yes.text=text(133);show_no=true;_no.text=text(134)
			else:_body.text+="\n\n"+text(192).replace("#C",money(int(service.missing_credits)))
		elif service.get("kind")=="kaamo":
			# Kaamo Club agents (Mac text ids): mods 896-899, item 900, ship 901.
			var ship_name:=text(902+int(service.ship_id))
			match service.kaamo_kind:
				"mod":
					_body.text=text(896+int(service.mod)).replace("#SHIP_NAME",ship_name).replace("#N",str([40,30,1,20][int(service.mod)]))+" "+text(868).replace("#C",money(int(service.total_price)))
				"item":
					_body.text=text(900)+"\n"+text(int(_bindings.station_equipment.item_text_offset)+int(service.item_id))+"   "+money(int(service.total_price))
				"ship":
					_body.text=text(739+_selected%6) if service.get("greeting",false) else text(901)+"\n"+text(902+int(service.offer_ship_id))+"   "+money(int(service.total_price))
			if service.consumed and not service.get("greeting",false):_body.text=text(847)
			elif service.can_accept:
				show_yes=true
				if _confirming:
					_body.text=text({"mod":860,"item":861,"ship":862}[service.kaamo_kind]).replace("#C",money(int(service.total_price)))
					_yes.text=text(133);show_no=true;_no.text=text(134)
			elif not service.consumed:_body.text+="\n\n"+text(192).replace("#C",money(int(service.missing_credits)))
		elif service.get("kind")=="coordinates":
			var system_name: String=_catalogues.tables.systems[int(service.system_id)].name
			_body.text=label_text(857).replace("#S",system_name).replace("#C",money(int(service.total_price)))
			if service.consumed:_body.text=taken_text()
			elif service.can_accept:
				show_yes=true
				if _confirming:_yes.text=text(133);show_no=true;_no.text=text(134)
			else:_body.text+="\n\n"+text(192).replace("#C",money(int(service.missing_credits)))
		elif service.get("kind")=="blueprint":
			var item_name:=text(int(_bindings.station_equipment.item_text_offset)+int(service.item_id))
			_body.text=label_text(856).replace("#P",item_name).replace("#C",money(int(service.total_price)))
			if service.consumed:_body.text=taken_text()
			elif service.can_accept:
				show_yes=true
				if _confirming:_yes.text=text(133);show_no=true;_no.text=text(134)
			else:_body.text+="\n\n"+text(192).replace("#C",money(int(service.missing_credits)))
		elif service.get("kind")=="wingmen":
			_body.text=text(int(service.intro_text_id)).replace("#C",money(int(service.total_price)))
			# Hired wingmen share the Challenge client's line (startChat, offer 6).
			if service.get("consumed",false):_body.text=taken_text(12)
			elif service.busy:_body.text=text(774)
			elif service.can_accept:
				show_yes=true
				if _confirming:
					_body.text=text(855).replace("#Q",str(service.crew_size)).replace("#C",money(int(service.total_price)))
					_yes.text=text(133);show_no=true;_no.text=text(134)
			else:_body.text+="\n\n"+text(192).replace("#C",money(int(service.missing_credits)))
		elif service.get("kind")=="diplomat":
			_body.text=text(int(service.intro_text_id)).replace("#C",money(int(service.total_price)))
			if service.consumed:_body.text=text(int(service.response_text_id))
			elif service.can_accept:
				show_yes=true
				if _confirming:
					_body.text=text(874).replace("#C",money(int(service.total_price)))
					_yes.text=text(133);show_no=true;_no.text=text(134)
			elif service.eligible:_body.text+="\n\n"+text(192).replace("#C",money(int(service.missing_credits)))
		elif service.get("kind")=="social":
			_body.text=Dialogue.text(_library,_catalogues,service.dialogue,_name.text)
		elif row.is_empty():
			_body.text=label_text(614) if _selected<0 else "This contact's service is not yet available."
		else:
			var mission: Dictionary=row.offer.mission
			var client: Dictionary=_state.accepted_contact
			if not _state.mission.is_empty() and client.get("station_id")==_state.station_id and client.get("offer_id")==_selected and client.get("offer")==row.offer:mission=_state.mission
			_title.text=text(int(mission.title_text_id))
			var brief: int=_previews.get(_selected,{}).get("briefing_text_id",mission.briefing_text_id)
			var credits:=money(int(mission.reward)+int(mission.bonus))
			# A standing bonus is named after the amount (App Store text 756).
			if int(mission.bonus)>0 and row.offer.get("context") is Dictionary:
				credits+=" "+label_text(754).replace("#P",str(int(ContractOffer.standing_ratio(_bindings.early_contracts,row.offer.context)*100.0)))
			_body.text=format_job(text(brief),mission)+"\n\n"+label_text(753).replace("#C",credits)
			if row.consumed:_body.text+="\n\n"+taken_text(int(mission.kind),true)
			else:
				var preview: Dictionary=_previews.get(_selected,{})
				if preview.get("can_accept",false):
					show_yes=true
					if _confirming:
						_body.text=label_text(850)+( "\n\n"+text(int(preview.replacement_text_id)) if preview.replacement_required else "")
						_yes.text=text(133);show_no=true;_no.text=text(134)
				else:
					_body.text+="\n\n"+text(int(preview.get("reason_text_id",-1))).replace("#Q",str(maxi(int(preview.get("cargo_tons",0)),int(preview.get("passenger_places",0))))).replace("#C",money(int(preview.get("missing_credits",0))))
					if not preview.get("unsupported_reason","").is_empty():_body.text+=preview.unsupported_reason
	_portrait.visible=_portrait.texture!=null
	_yes.visible=show_yes;_no.visible=show_no
	for button in [_yes,_no,_back]:button.disabled=not _active

func confirm() -> void:
	if not _active or not visible or _state.is_empty():return
	if not _state.pending_result.is_empty():action_requested.emit("result_close",int(_state.pending_result.serial));return
	var preview: Dictionary=_previews.get(_selected,{})
	if not preview.get("can_accept",false):return
	if not _confirming:_confirming=true;_refresh();return
	_taken=_selected
	if preview.get("kind")=="merchant":action_requested.emit("buy_goods",_selected)
	elif preview.get("kind")=="kaamo":action_requested.emit("buy_kaamo",_selected)
	elif preview.get("kind")=="coordinates":action_requested.emit("buy_coordinates",_selected)
	elif preview.get("kind")=="blueprint":action_requested.emit("buy_blueprint",_selected)
	elif preview.get("kind")=="diplomat":action_requested.emit("buy_diplomat",_selected)
	elif preview.get("kind")=="wingmen":action_requested.emit("hire_wingmen",_selected)
	else:action_requested.emit("replace" if preview.replacement_required else "accept",_selected)

func decline() -> void:
	if not _active or not visible or _state.is_empty() or not _state.pending_result.is_empty():return
	var row: Variant=_state.get("offers",{}).get(_selected)
	var preview: Dictionary=_previews.get(_selected,{})
	if _confirming and row is Dictionary and row.get("consumed")==false and preview.get("can_accept",false):
		_confirming=false;action_requested.emit("decline",_selected);return
	back()

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
		var current:=_contact_ids.find(_selected)
		var next: int=(0 if move>0 else _contact_ids.size()-1) if current<0 else posmod(current+move,_contact_ids.size())
		select_contact(_contact_ids[next]);return true
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
	visible=false;_state={};_confirming=false;_selected=-1;_taken=-1
	if is_instance_valid(_scene):_scene.select_contact(-1)
	_scene=null
func reject(message: String) -> bool:error=message;return false
