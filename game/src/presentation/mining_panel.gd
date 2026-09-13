extends Control
## Original mining atlas art with native text and a compact desktop composition.
## Presentation never advances drilling, changes the reference coordinates, or
## grants cargo. The input owner handles Fire/stop and the touch preference.
const Drill=preload("res://src/simulation/mining_drill.gd")
const Definitions=preload("res://src/content/mining_drill_definitions.gd")
const Atlas=preload("res://src/content/atlas_region.gd")
const RESOURCE:="resources/data/textures/gof2_interface.aei"
var error:=""
var _identity:={}
var _rules:={}
var _textures:={}
var _spinner_frames: Array[AtlasTexture]=[]
var _rings: Array[TextureRect]=[]
var _point: TextureRect
var _spinner: TextureRect
var _core: TextureRect
var _gauge: TextureRect
var _reserve: TextureRect
var _readout: TextureRect
var _quantity: Label
var _instruction: Label
var _state:={}
var _free_space:=0
var _mobile:=false
var _tutorial:=false

func _init() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE;clip_contents=true;visible=false
	for i in 28:_rings.append(_sprite())
	_core=_sprite();_point=_sprite();_spinner=_sprite();_gauge=_sprite();_reserve=_sprite();_readout=_sprite()
	_quantity=Label.new();_quantity.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_quantity.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;add_child(_quantity)
	_instruction=Label.new();_instruction.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_instruction.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_instruction.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	add_child(_instruction);resized.connect(_reflow)

func configure(library: RefCounted, bindings: RefCounted, visuals: RefCounted) -> bool:
	error=""
	if library==null or bindings==null or visuals==null or not Definitions.parameters(bindings.mining_drill):return reject("Mining artwork requires supported content declarations")
	if bindings.base_content_id!=library.manifest.get("content_id") or visuals.base_content_id!=bindings.base_content_id:return reject("Mining artwork belongs to another content base")
	var registered:=false
	for row in bindings.records.get(10062,[]):
		if row.resource==RESOURCE and row.kind=="texture" and int(row.registration_type)==2:registered=true
	if not registered:return reject("Mining's baseline atlas is not registered in this profile")
	var rules: Dictionary=bindings.mining_drill
	var text_id:=int(rules.instruction_text_id)
	if text_id>=library.strings.size() or library.strings[text_id].is_empty():return reject("The mining instruction is unavailable in this language")
	var metadata: PackedByteArray=library.read_resource(RESOURCE,Atlas.MAX_BYTES)
	if metadata.is_empty():return reject(library.error)
	var reader:=Atlas.new()
	var sheet:=reader.load(library,visuals,RESOURCE,int(rules.image_aliases["1254"].region))
	if sheet==null:return reject(reader.error)
	var textures:={}
	for key in rules.image_aliases:
		var alias: Dictionary=rules.image_aliases[key]
		if int(alias.texture_id)!=10062:return reject("Unsupported mining image atlas")
		var region:=reader.region(metadata,int(alias.region))
		if region.is_empty():return reject(reader.error)
		var texture:=AtlasTexture.new();texture.atlas=sheet.atlas;texture.region=Rect2(region.rect);texture.filter_clip=true
		textures[int(key)]=texture
	var cell:=int(sheet.region.size.y)
	if cell<=0 or int(sheet.region.size.x)%cell!=0:return reject("Mining drill animation has an unsupported cell layout")
	var frames: Array[AtlasTexture]=[]
	for index in int(sheet.region.size.x)/cell:
		var frame:=AtlasTexture.new();frame.atlas=sheet.atlas
		frame.region=Rect2(sheet.region.position+Vector2(index*cell,0),Vector2(cell,cell));frame.filter_clip=true;frames.append(frame)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":library.active_language}
	_rules=rules.duplicate(true);_textures=textures;_spinner_frames=frames;_instruction.text=library.strings[text_id]
	clear()
	return true

func present(drill: RefCounted, free_space: int, show_tutorial: bool) -> bool:
	error=""
	if _identity.is_empty() or drill==null or drill.get_script()!=Drill or free_space<0:return reject("Mining presentation requires the current native drill and cargo space")
	var state: Dictionary=drill.snapshot()
	if state.is_empty() or state.base_content_id!=_identity.base_content_id or state.binding_id!=_identity.binding_id:return reject("Mining display belongs to another flight")
	_state=state;_free_space=free_space;_tutorial=show_tutorial
	visible=state.phase=="drilling"
	_reflow()
	return true

func set_mobile_layout(value: bool) -> void:_mobile=value;_reflow()

func _reflow() -> void:
	if _state.is_empty() or _textures.is_empty() or size.x<=0 or size.y<=0:return
	var scale:=1.0 if _mobile else 0.5
	# Keep the phone composition larger, fitting only when the viewport itself
	# is smaller. Native labels retain legible pixel sizes on desktop.
	scale=minf(scale,minf(size.x/340.0,size.y/420.0))
	var center:=Vector2(floorf(size.x*0.5),floorf(size.y*0.5)-32.0*scale)
	for ring in _rings:ring.visible=false
	for index in range(int(_state.layer_index),int(_state.layer_count)):
		var diameter:=float(_state.radii[index])*2.0
		var aliases: Array=_rules.images.rings_even if index%2==0 else _rules.images.rings_odd
		var variant:=0 if diameter<=float(_rules.ring_small_max_diameter) else 1 if diameter<float(_rules.ring_large_min_diameter) else 2
		var radius:=diameter*scale*0.5
		for quarter in 4:
			var ring: TextureRect=_rings[index*4+quarter]
			ring.texture=_textures[int(aliases[variant])];ring.size=Vector2(radius,radius)
			ring.position=center+Vector2(0 if quarter&1 else -radius,0 if quarter&2 else -radius)
			ring.flip_h=(quarter&1)!=0;ring.flip_v=(quarter&2)!=0;ring.visible=true
	_core.visible=_state.layer_count==int(_rules.core_size)
	if _core.visible:
		var id:=int(_rules.images.core_void) if _state.item_id==164 else int(_rules.images.core_ordinary)
		_center_sprite(_core,_textures[id],center,scale)
	var point: Vector2=center+(_state.point-_state.center)*scale
	_center_sprite(_point,_textures[1255],point,scale)
	_center_sprite(_spinner,_spinner_frames[int(_state.spinner_steps)%_spinner_frames.size()],point,scale)
	_point.modulate=Color.WHITE if _state.inside else Color(1.0,0.35,0.15)
	var bottom:=center+Vector2(0,155.0*scale)
	_center_sprite(_gauge,_textures[1251],bottom,scale)
	var reserve: AtlasTexture=_textures[1256]
	var reserve_width:=reserve.region.size.x*clampf(1.0-float(_state.outside_elapsed_ms)/float(_rules.outside_limit_ms),0,1)
	_reserve.visible=reserve_width>0
	if _reserve.visible:
		var cropped:=AtlasTexture.new();cropped.atlas=reserve.atlas;cropped.region=Rect2(reserve.region.position,Vector2(reserve_width,reserve.region.size.y));cropped.filter_clip=true
		_reserve.texture=cropped;_reserve.size=Vector2(reserve_width,reserve.region.size.y)*scale
		_reserve.position=bottom+Vector2(-reserve.region.size.x*0.5,-reserve.region.size.y*0.5)*scale
	var readout_center: Vector2=point+Vector2(65,0)*scale
	readout_center.x=clampf(readout_center.x,36,size.x-36)
	readout_center.y=clampf(readout_center.y,18,size.y-18)
	_center_sprite(_readout,_textures[1253],readout_center,scale)
	_quantity.text="%dt"%int(_state.ore_tons);_quantity.add_theme_font_size_override("font_size",18 if _mobile else 14)
	_quantity.add_theme_color_override("font_color",Color(1,0.25,0.12) if _state.ore_tons>_free_space else Color.WHITE)
	_quantity.size=Vector2(maxf(64,70*scale),28);_quantity.position=readout_center-_quantity.size*0.5
	_instruction.visible=_tutorial
	_instruction.add_theme_font_size_override("font_size",18 if _mobile else 14)
	_instruction.add_theme_color_override("font_color",Color(0.72,0.88,0.94))
	_instruction.size=Vector2(minf(size.x-24,440*scale),64)
	_instruction.position=Vector2((size.x-_instruction.size.x)*0.5,bottom.y+22*scale)

func _sprite() -> TextureRect:
	var sprite:=TextureRect.new();sprite.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode=TextureRect.STRETCH_SCALE;sprite.mouse_filter=Control.MOUSE_FILTER_IGNORE
	sprite.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR;add_child(sprite)
	return sprite

func _center_sprite(sprite: TextureRect, texture: Texture2D, point: Vector2, scale: float) -> void:
	sprite.texture=texture;sprite.size=texture.get_size()*scale;sprite.position=point-sprite.size*0.5

func source() -> Dictionary:
	if _identity.is_empty():return {}
	var result:=_identity.duplicate(true);result.resource=RESOURCE;result.image_aliases=_rules.image_aliases.duplicate(true)
	return result

func clear() -> void:error="";_state={};visible=false
func reject(message: String) -> bool:error=message;return false
