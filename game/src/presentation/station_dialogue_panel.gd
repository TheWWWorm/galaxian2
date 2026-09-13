extends Control
## Native acknowledged conversation with original localized text and portraits.
## Layout remains crisp at compact desktop and larger phone composition sizes.
signal next_requested
signal previous_requested
const Portraits=preload("res://src/presentation/portrait_compositor.gd")
const Definitions=preload("res://src/content/station_presentation_definitions.gd")
const MiningStory=preload("res://src/content/full_hold_story_definitions.gd")
const StationReturn=preload("res://src/content/full_hold_return_definitions.gd")
var error:=""
var portrait_diagnostics:={}
var _identity:={}
var _portraits:={}
var _labels:={}
var _mobile:=false
var _snapshot:={}
var _active:=true
var _panel: PanelContainer
var _body: RichTextLabel
var _portrait: TextureRect
var _name: Label
var _next: Button
var _previous: Button
var _counter: Label

func _init() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE;visible=false
	_panel=PanelContainer.new();add_child(_panel)
	var margin:=MarginContainer.new();_panel.add_child(margin)
	for edge in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+edge,12)
	var column:=VBoxContainer.new();margin.add_child(column)
	var row:=HBoxContainer.new();row.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(row)
	_portrait=TextureRect.new();_portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;row.add_child(_portrait)
	var text_column:=VBoxContainer.new();text_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(text_column)
	_name=Label.new();_name.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;text_column.add_child(_name)
	_body=RichTextLabel.new();_body.bbcode_enabled=false;_body.scroll_active=true
	_body.size_flags_vertical=Control.SIZE_EXPAND_FILL;_body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;text_column.add_child(_body)
	var buttons:=HBoxContainer.new();column.add_child(buttons)
	_previous=Button.new();_previous.text="‹";_previous.tooltip_text="Previous line · Left / controller B"
	_previous.pressed.connect(func():previous_requested.emit());buttons.add_child(_previous)
	_counter=Label.new();_counter.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_counter.size_flags_horizontal=Control.SIZE_EXPAND_FILL;buttons.add_child(_counter)
	_next=Button.new();_next.pressed.connect(func():next_requested.emit());buttons.add_child(_next)
	resized.connect(_relayout)
	_panel.minimum_size_changed.connect(_relayout)
	_panel.resized.connect(_place_panel)
	set_mobile_layout(false)

func configure(library: RefCounted, bindings: RefCounted, visuals: RefCounted) -> bool:
	if library==null or bindings==null or visuals==null or not Definitions.parameters(bindings.station_presentation):return reject("Station conversation resources are unavailable")
	return _configure_resources(library,bindings,visuals,bindings.station_presentation.dialogue)

func configure_mining_briefing(library: RefCounted, bindings: RefCounted, visuals: RefCounted, campaign_cursor:=2) -> bool:
	if library==null or bindings==null or visuals==null or not Definitions.parameters(bindings.station_presentation):return reject("Mining briefing resources are unavailable")
	var rules:=MiningStory.briefing(bindings,campaign_cursor)
	if rules.is_empty():return reject("Mining briefing resources are unavailable for this departure")
	return _configure_resources(library,bindings,visuals,rules)

func configure_mining_objective(library: RefCounted, bindings: RefCounted, visuals: RefCounted, campaign_cursor:=2) -> bool:
	if library==null or bindings==null or visuals==null or not Definitions.parameters(bindings.station_presentation):return reject("Mining return resources are unavailable")
	var rules:=MiningStory.objective(bindings,campaign_cursor)
	if rules.is_empty():return reject("Mining return resources are unavailable for this departure")
	return _configure_resources(library,bindings,visuals,rules)

func configure_station_return(library: RefCounted, bindings: RefCounted, visuals: RefCounted, campaign_cursor:=3) -> bool:
	if library==null or bindings==null or visuals==null or not Definitions.parameters(bindings.station_presentation):return reject("Station return resources are unavailable")
	var rules:=StationReturn.select(bindings,campaign_cursor)
	if rules.is_empty():return reject("Station return resources are unavailable for this visit")
	return _configure_resources(library,bindings,visuals,rules)

func _configure_resources(library: RefCounted, bindings: RefCounted, visuals: RefCounted, rules: Dictionary) -> bool:
	clear();_identity={};_portraits={};_labels={};portrait_diagnostics={}
	if library.manifest.get("content_id")!=bindings.base_content_id or visuals.base_content_id!=bindings.base_content_id:return reject("Station conversation belongs to another base content")
	for key in ["next_text_id","final_text_id"]:
		var id:=int(rules[key])
		if id>=library.strings.size() or library.strings[id].is_empty():return reject("Station navigation text is unavailable")
		_labels[key]=library.strings[id]
	var composer:=Portraits.new()
	for id in [0,2,16]:
		var portrait: Dictionary=composer.compose_definition(library,bindings,visuals,id,"large",bindings.station_presentation.portraits[str(id)])
		if portrait.is_empty():return reject(composer.error)
		_portraits[id]=ImageTexture.create_from_image(portrait.image)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":library.active_language}
	return true

func present(state: Dictionary) -> bool:
	error=""
	if state.is_empty():clear();return true
	for key in _identity:
		if state.get(key)!=_identity[key]:return reject("Station conversation belongs to another session")
	if _identity.is_empty() or not state.get("dialogue") is Dictionary:return reject("Invalid station conversation")
	var line: Dictionary=state.dialogue
	if not line.get("visible",false):clear();return true
	if line.get("speaker_id") not in [0,2,16] or not line.get("text") is String or not line.get("speaker_name") is String:return reject("Invalid station conversation line")
	if not line.get("desktop_text",line.text) is String:return reject("Invalid desktop station text")
	if _snapshot==line:return true
	_snapshot=line.duplicate(true);_name.text=line.speaker_name;_body.text=line.text
	_body.scroll_to_line(0);_portrait.texture=_portraits.get(int(line.speaker_id))
	_portrait.visible=_portrait.texture!=null
	_next.text=_labels.final_text_id if line.index==line.count-1 else _labels.next_text_id
	_counter.text="%d / %d"%[int(line.index)+1,int(line.count)]
	visible=true;set_active(_active);_relayout()
	return true

func set_active(value: bool) -> void:
	_active=value
	_next.disabled=not value
	_previous.disabled=not value or not _snapshot.get("previous_available",false)

func set_mobile_layout(value: bool) -> void:
	_mobile=value
	var scale:=1.0 if value else 0.5
	_body.add_theme_font_size_override("normal_font_size",int(30*scale))
	_name.add_theme_font_size_override("font_size",int(32*scale))
	for button in [_next,_previous]:button.add_theme_font_size_override("font_size",int(30*scale))
	var style:=StyleBoxFlat.new();style.bg_color=Color(0.025,0.055,0.085,0.96)
	style.border_color=Color(0.24,0.53,0.65,0.95);style.set_border_width_all(1);style.set_corner_radius_all(int(12*scale))
	_panel.add_theme_stylebox_override("panel",style)
	_name.add_theme_color_override("font_color",Color(0.68,0.86,0.93));_relayout()

func _relayout() -> void:
	if not visible:return
	var selected: String=_snapshot.get("text","") if _mobile else _snapshot.get("desktop_text",_snapshot.get("text",""))
	if _body.text!=selected:_body.text=selected;_body.scroll_to_line(0)
	if size.x<1 or size.y<1:return
	var scale:=1.0 if _mobile else 0.5
	var width:=minf(1120*scale,maxf(1,size.x-24))
	var height:=minf(390*scale,maxf(1,size.y-24))
	var narrow:=_mobile and width<600
	_body.add_theme_font_size_override("normal_font_size",24 if narrow else int(30*scale))
	_name.add_theme_font_size_override("font_size",24 if narrow else int(32*scale))
	_portrait.custom_minimum_size=Vector2(104,130) if narrow else Vector2(160*scale,180*scale)
	_body.custom_minimum_size.y=32*scale
	for button in [_next,_previous]:button.custom_minimum_size=Vector2(44,44) if _mobile else Vector2.ZERO
	# Child font/touch-target changes invalidate the container's minimum size.
	# Apply the requested compact size after them and again when that minimum
	# settles. Position from the actual panel size, including translated labels.
	_panel.size=Vector2(width,height)
	_place_panel()

func _place_panel() -> void:
	if not visible:return
	var bottom_margin:=24.0 if _mobile else 12.0
	_panel.position=Vector2(maxf(0,(size.x-_panel.size.x)/2),maxf(0,size.y-_panel.size.y-bottom_margin))

func clear() -> void:
	error="";_snapshot={};visible=false;_name.text="";_body.text="";_portrait.texture=null
func reject(message: String) -> bool:error=message;return false
