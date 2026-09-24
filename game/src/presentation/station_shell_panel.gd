extends Control
## Station chrome around the live hangar. The application owns action availability.
signal action_requested(action: String)
const Catalogues=preload("res://src/content/catalogues.gd")
const Atlas=preload("res://src/content/atlas_region.gd")
const OriginalUI=preload("res://src/presentation/original_ui.gd")
const INTERFACE_ATLAS="resources/data/textures/gof2_interface_ipad_1440.aei"
const ACTION_LABELS={"map":176,"hangar":166,"lounge":387,"depart":406,"save":495,"load":494,"menu":170}
const ACTION_ORDER=["map","hangar","lounge","depart","save","load","menu"]
var error:=""
var _identity:={}
var _catalogues: RefCounted
var _ui: RefCounted
var _map_rules:={}
var _labels:={}
var _faction_names:=[]
var _faction_icons:={}
var _active:=true
var _mobile:=false
var _state:={}
var _top: TextureRect
var _bottom: TextureRect
var _sidebar: ColorRect
var _sidebar_art: TextureRect
var _station: Label
var _system: Label
var _faction: Label
var _tech: Label
var _faction_icon: TextureRect
var _cargo: Label
var _credits: Label
var _actions:={}
var _navigation: VBoxContainer
var _navigation_scroll: ScrollContainer

func _init() -> void:
	visible=false;mouse_filter=Control.MOUSE_FILTER_IGNORE
	_top=TextureRect.new();_top.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(_top)
	_top.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_top.stretch_mode=TextureRect.STRETCH_SCALE
	_bottom=TextureRect.new();_bottom.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(_bottom)
	_bottom.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_bottom.stretch_mode=TextureRect.STRETCH_SCALE
	_sidebar=ColorRect.new();_sidebar.mouse_filter=Control.MOUSE_FILTER_IGNORE;_sidebar.color=Color.BLACK;add_child(_sidebar)
	_sidebar_art=TextureRect.new();_sidebar_art.mouse_filter=Control.MOUSE_FILTER_IGNORE;_sidebar.add_child(_sidebar_art)
	_sidebar_art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_sidebar_art.stretch_mode=TextureRect.STRETCH_TILE
	_sidebar_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_station=Label.new();_station.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(_station)
	_faction_icon=TextureRect.new();_faction_icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(_faction_icon)
	_faction_icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_faction_icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_system=Label.new();_system.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(_system)
	_faction=Label.new();_faction.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(_faction)
	_tech=Label.new();_tech.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(_tech)
	_cargo=Label.new();_cargo.mouse_filter=Control.MOUSE_FILTER_IGNORE;_cargo.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;add_child(_cargo)
	_credits=Label.new();_credits.mouse_filter=Control.MOUSE_FILTER_IGNORE;_credits.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;add_child(_credits)
	_navigation_scroll=ScrollContainer.new();add_child(_navigation_scroll)
	_navigation_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;_navigation_scroll.follow_focus=true
	_navigation=VBoxContainer.new();_navigation_scroll.add_child(_navigation)
	_navigation.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_navigation.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_navigation.alignment=BoxContainer.ALIGNMENT_END;_navigation.add_theme_constant_override("separation",4)
	for action in ACTION_ORDER:
		var button:=Button.new();button.visible=false;button.text=action;button.clip_text=true
		button.pressed.connect(func():_request_action(action))
		if action in ["menu","depart"]:add_child(button)
		else:_navigation.add_child(button)
		_actions[action]=button
	resized.connect(_relayout)
	set_mobile_layout(false)

func configure(library: RefCounted,bindings: RefCounted,visuals: RefCounted) -> bool:
	error=""
	if library==null or bindings==null or visuals==null or library.manifest.get("content_id")!=bindings.base_content_id or visuals.base_content_id!=bindings.base_content_id:return reject("Station shell requires matching imported content and artwork")
	var map_rules: Dictionary=bindings.mido_travel.get("map",{}).get("ui",{})
	if map_rules.is_empty():return reject("Station shell has no verified interface mapping")
	var cat:=Catalogues.new()
	if not cat.open(library):return reject(cat.error)
	var art:=OriginalUI.new()
	if not art.configure(library,bindings,visuals):return reject(art.error)
	var labels:={}
	for action in ACTION_LABELS:
		var id: int=ACTION_LABELS[action]
		if id>=library.strings.size() or library.strings[id].is_empty():return reject("Station action text is unavailable")
		labels[action]=library.strings[id]
	for key in {"tech":132,"cargo":183}:
		var id: int={"tech":132,"cargo":183}[key]
		if id>=library.strings.size() or library.strings[id].is_empty():return reject("Station identity text is unavailable")
		labels[key]=library.strings[id]
	var faction_names:=[]
	for faction in map_rules.faction_image_ids.size():
		var id: int=int(map_rules.faction_text_base)+faction
		if id>=library.strings.size() or library.strings[id].is_empty():return reject("Station faction text is unavailable")
		faction_names.append(library.strings[id])
	var bytes: PackedByteArray=library.read_resource(INTERFACE_ATLAS,Atlas.MAX_BYTES)
	var image: Image=visuals.load_image(INTERFACE_ATLAS)
	if bytes.is_empty() or image==null:return reject(library.error+visuals.error)
	var pixels:=ImageTexture.create_from_image(image)
	var icons:={}
	for id in map_rules.faction_image_ids:
		var alias: Dictionary=bindings.resolve_image_region(int(id))
		if alias.is_empty() or int(alias.texture_id)!=int(map_rules.texture_id):return reject("Station faction icon lost its source atlas alias")
		var region: Dictionary=Atlas.new().region(bytes,int(alias.region))
		if region.is_empty() or region.size!=image.get_size():return reject("Station faction icon disagrees with source pixels")
		var texture:=AtlasTexture.new();texture.atlas=pixels;texture.region=Rect2(region.rect);texture.filter_clip=true
		texture.set_meta("source_image_id",int(id));icons[int(id)]=texture
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":library.active_language}
	_catalogues=cat;_ui=art;_map_rules=map_rules;_labels=labels;_faction_names=faction_names;_faction_icons=icons
	_top.texture=art.sprites[int(map_rules.footer_image_id)];_bottom.texture=_top.texture
	_sidebar_art.texture=art.sprites[int(map_rules.panel_background_image_id)]
	var prepared_theme:=Theme.new();prepared_theme.default_font=art.font
	var previous_theme: Theme=theme
	theme=prepared_theme
	for action in ACTION_ORDER:
		_actions[action].text=labels[action];_actions[action].tooltip_text=labels[action]
	set_mobile_layout(_mobile)
	return true

func present(state: Dictionary) -> bool:
	error=""
	if _identity.is_empty() or _catalogues==null:return reject("Configure the station shell before presenting it")
	for key in _identity:
		if state.get(key)!=_identity[key]:return reject("Station shell belongs to another content session")
	var loadout: Variant=state.get("loadout")
	var cargo: Variant=state.get("cargo")
	var actions: Variant=state.get("ui_actions")
	if not loadout is Dictionary or not actions is Dictionary:return reject("Station shell needs the current station and action states")
	# The first rescue visit has not constructed its cargo owner. Station actions
	# remain available, while cargo totals appear only when that owner exists.
	if state.has("cargo") and not cargo is Dictionary:return reject("Station shell received invalid cargo totals")
	var station_id: int=int(loadout.get("station_id",-1))
	if station_id<0 or station_id>=_catalogues.tables.stations.size():return reject("Station shell selected an unknown station")
	var station: Dictionary=_catalogues.tables.stations[station_id]
	var system_id: int=int(station.system_id)
	if system_id<0 or system_id>=_catalogues.tables.systems.size():return reject("Station shell selected an unknown system")
	var system: Dictionary=_catalogues.tables.systems[system_id]
	var faction_id: int=int(system.fields[2])
	if faction_id<0 or faction_id>=_map_rules.faction_image_ids.size():return reject("Station shell selected an unknown faction")
	if cargo is Dictionary and (not cargo.get("used") is int or not cargo.get("capacity") is int or cargo.used<0 or cargo.capacity<0):return reject("Station shell received invalid cargo totals")
	for action in actions:
		if not _actions.has(action) or not actions[action] is Dictionary or not actions[action].get("visible") is bool or not actions[action].get("enabled") is bool:return reject("Station shell received an unknown action state")
	var credits: int=int(state.get("contracts",{}).get("credits",0))
	if credits<0:return reject("Station shell received an invalid wallet")
	_station.text=station.name;_system.text=system.name
	_faction.text=_faction_names[faction_id]
	_tech.text="%s: %d"%[_labels.tech,int(station.fields[2])]
	_faction_icon.texture=_faction_icons[int(_map_rules.faction_image_ids[faction_id])]
	_cargo.visible=cargo is Dictionary
	_cargo.text="%d / %dt"%[cargo.used,cargo.capacity] if _cargo.visible else "";_cargo.tooltip_text=_labels.cargo
	_credits.text="%d$"%credits
	for label in [_station,_system,_faction,_tech]:label.tooltip_text=label.text
	_state=state
	for action in ACTION_ORDER:
		var policy: Dictionary=actions.get(action,{"visible":false,"enabled":false})
		_actions[action].visible=policy.visible
		_actions[action].disabled=not _active or not policy.enabled
	visible=true;_relayout()
	return true

func _request_action(action: String) -> void:
	if not _active or not is_visible_in_tree() or _state.is_empty():return
	var policy: Dictionary=_state.ui_actions.get(action,{"visible":false,"enabled":false})
	if policy.visible and policy.enabled:action_requested.emit(action)

func set_active(value: bool) -> void:
	_active=value
	if not _state.is_empty():
		for action in ACTION_ORDER:
			var policy: Dictionary=_state.ui_actions.get(action,{"enabled":false})
			_actions[action].disabled=not value or not policy.enabled

func set_mobile_layout(value: bool) -> void:
	_mobile=value
	var font_size:=20 if value else 15
	for label in [_station,_system,_faction,_tech,_cargo,_credits]:
		label.add_theme_font_size_override("font_size",font_size);label.clip_text=true
	for action in ACTION_ORDER:
		var button: Button=_actions[action]
		if _ui!=null:_ui.apply_button(button,value,action=="menu")
		button.custom_minimum_size.y=48 if value else 30
		button.add_theme_font_size_override("font_size",font_size)
	_relayout()

func _relayout() -> void:
	if size.x<=0 or size.y<=0:return
	var bar_height:=52.0 if _mobile else 32.0
	var side_width:=minf(size.x*0.32,256.0 if _mobile else 180.0)
	_top.position=Vector2.ZERO;_top.size=Vector2(size.x,bar_height)
	_bottom.position=Vector2(0,size.y-bar_height);_bottom.size=Vector2(size.x,bar_height)
	_sidebar.position=Vector2(0,bar_height);_sidebar.size=Vector2(side_width,maxf(0,size.y-bar_height*2))
	_station.position=Vector2(12,2);_station.size=Vector2(maxf(0,size.x-24),bar_height-4)
	var icon:=54.0 if _mobile else 42.0
	_faction_icon.position=Vector2(8,bar_height+10);_faction_icon.size=Vector2(icon,icon)
	var left:=icon+15.0;var line:=27.0 if _mobile else 21.0
	for pair in [[_system,0],[_tech,1],[_faction,2]]:
		pair[0].position=Vector2(left,bar_height+10+line*pair[1]);pair[0].size=Vector2(maxf(0,side_width-left-5),line)
	var navigation_top:=bar_height+10+line*3+12
	_navigation_scroll.position=Vector2(7,navigation_top)
	_navigation_scroll.size=Vector2(maxf(1,side_width-14),maxf(1,size.y-bar_height-navigation_top-8))
	var menu: Button=_actions.menu
	menu.position=Vector2(7,size.y-bar_height+2);menu.size=Vector2(maxf(1,side_width-14),bar_height-4)
	var depart: Button=_actions.depart
	var depart_width:=minf(150 if _mobile else 112,size.x*0.2) if depart.visible else 0.0
	depart.position=Vector2(size.x-depart_width-5,size.y-bar_height+2);depart.size=Vector2(maxf(1,depart_width),bar_height-4)
	var wallet_width:=minf(170 if _mobile else 140,size.x*0.22)
	_credits.position=Vector2(size.x-depart_width-wallet_width-12,size.y-bar_height+3)
	_credits.size=Vector2(wallet_width,bar_height-6)
	_cargo.position=Vector2(side_width,size.y-bar_height+3)
	_cargo.size=Vector2(maxf(0,_credits.position.x-side_width-8),bar_height-6)

func clear() -> void:
	_state={};visible=false
	for action in ACTION_ORDER:_actions[action].visible=false

func reject(message: String) -> bool:error=message;return false
