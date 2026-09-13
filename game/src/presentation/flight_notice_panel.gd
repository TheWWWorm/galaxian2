extends Control
## Original notice-bar artwork with native text. The queue owns fade time;
## this responsive layout adds no acknowledgement or flight action button.
const Definitions=preload("res://src/content/flight_notice_definitions.gd")
const Atlas=preload("res://src/content/atlas_region.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const RESOURCE:="resources/data/textures/gof2_interface.aei"
var error:=""
var _identity:={}
var _sample:={}
var _mobile:=false
var _bar: NinePatchRect
var _label: RichTextLabel

func _init() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE;clip_contents=true;visible=false
	_bar=NinePatchRect.new();_bar.mouse_filter=Control.MOUSE_FILTER_IGNORE;_bar.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	for edge in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:_bar.set_patch_margin(edge,4)
	add_child(_bar)
	_label=RichTextLabel.new();_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_label.fit_content=false;_label.scroll_active=false
	_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(_label)
	resized.connect(_reflow)

func configure(library: RefCounted, bindings: RefCounted, visuals: RefCounted) -> bool:
	error=""
	if library==null or bindings==null or visuals==null or not Definitions.parameters(bindings.flight_notices):return reject("Flight notice artwork requires supported content")
	if bindings.base_content_id!=library.manifest.get("content_id") or visuals.base_content_id!=bindings.base_content_id or library.active_language.is_empty():return reject("Flight notice artwork belongs to another content base")
	var registered:=false
	for row in bindings.records.get(int(bindings.flight_notices.background_texture_id),[]):
		if row.resource==RESOURCE and row.kind=="texture" and int(row.registration_type)==2:registered=true
	if not registered:return reject("The original notice atlas is not registered")
	var reader:=Atlas.new();var texture:=reader.load(library,visuals,RESOURCE,int(bindings.flight_notices.background_region))
	if texture==null:return reject(reader.error)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":library.active_language}
	_bar.texture=texture;clear()
	return true

func present(state: Dictionary) -> bool:
	error=""
	if _identity.is_empty():return reject("Configure the notice panel first")
	for key in _identity:
		if state.get(key)!=_identity[key]:return reject("Notice text belongs to another flight or language")
	if not state.get("visible") is bool or not Numbers.integer(state.get("alpha"),0,255) or not state.get("current") is Dictionary:return reject("Invalid flight notice display")
	var message: Dictionary=state.current
	if state.visible or not message.is_empty():
		if not message.get("text") is String or message.text.is_empty() or not message.get("rgb") is Array or message.rgb.size()!=3:return reject("Invalid flight notice text or color")
		for value in message.rgb:
			if not Numbers.integer(value,0,255):return reject("Invalid flight notice color")
	_sample=state.duplicate(true);visible=state.visible;modulate.a=float(state.alpha)/255.0
	_label.text=message.get("text","")
	if not message.is_empty():_label.add_theme_color_override("default_color",Color8(int(message.rgb[0]),int(message.rgb[1]),int(message.rgb[2])))
	_reflow()
	return true

func set_mobile_layout(value: bool) -> void:_mobile=value;_reflow()
func _reflow() -> void:
	if _sample.is_empty() or size.x<=24:return
	var scale:=1.0 if _mobile else 0.5
	var font_size:=22 if _mobile else 14
	_label.add_theme_font_size_override("normal_font_size",font_size)
	var font: Font=_label.get_theme_font("normal_font")
	var text: String=_sample.current.get("text","")
	var width:=minf(size.x-24,maxf(196*scale,ceilf(font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x)+24*scale))
	var available:=maxf(1,width-24*scale)
	var text_size:=font.get_multiline_string_size(text,HORIZONTAL_ALIGNMENT_CENTER,available,font_size)
	var height:=maxf(22*scale,ceilf(text_size.y)+12*scale)
	# The complete original HUD's top geometry is not yet connected. Keep the
	# original centered bar below a native margin, with room for localized text.
	_bar.size=Vector2(width,height);_bar.position=Vector2(floorf((size.x-width)*0.5),24*scale)
	_label.size=Vector2(available,height-8*scale);_label.position=_bar.position+Vector2(12,4)*scale
func snapshot() -> Dictionary:return _sample.duplicate(true)
func clear() -> void:error="";_sample={};_label.clear();visible=false
func reject(message: String) -> bool:error=message;return false
