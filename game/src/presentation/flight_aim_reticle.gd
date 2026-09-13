extends Control
## Original idle/contact reticles, placed at the committed player aim sample.
const Atlas = preload("res://src/content/atlas_region.gd")
const Library = preload("res://src/content/library.gd")
const Definitions = preload("res://src/content/player_aim_definitions.gd")
const TargetProjection = preload("res://src/presentation/target_projection.gd")
const RESOURCE := "resources/data/textures/gof2_interface.aei"
var error := ""
var prepared := false
var mobile_layout := false
var sprite: TextureRect
var _textures := {}
var _source := {}
var _sample := {}

func _init() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE;clip_contents=true;visible=false

func prepare(library: RefCounted, bindings: RefCounted, visuals: RefCounted) -> bool:
	clear()
	if library==null or bindings==null or visuals==null or not Library.valid_hash(bindings.binding_id) or bindings.base_content_id!=library.manifest.get("content_id") or visuals.base_content_id!=bindings.base_content_id:
		return fail("Aim reticle requires matching content, bindings and pixels")
	var data: Dictionary=bindings.opening_staging.get("player_aim",{})
	if not Definitions.parameters(data):return fail("Aim reticle requires its imported alias declarations")
	var registered := false
	for record in bindings.records.get(int(data.texture_id),[]):
		if record.resource==RESOURCE and record.kind=="texture" and int(record.registration_type)==2:registered=true
	if not registered:return fail("Aim reticle baseline atlas is not registered by this profile")
	var textures := {};var regions := []
	var reader := Atlas.new()
	for index in 2:
		var texture := reader.load(library,visuals,RESOURCE,int(data.image_regions[index]))
		if texture==null:return fail(reader.error)
		textures[int(data.image_ids[index])]=texture
		regions.append({"image_id":int(data.image_ids[index]),"region":int(data.image_regions[index]),"source_rect":texture.region})
	_source={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"texture_id":int(data.texture_id),"resource":RESOURCE,"regions":regions}
	_textures=textures
	sprite=TextureRect.new();sprite.mouse_filter=Control.MOUSE_FILTER_IGNORE
	sprite.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR;sprite.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode=TextureRect.STRETCH_SCALE;add_child(sprite)
	prepared=true
	return true

func present(sample: Dictionary) -> bool:
	error=""
	if sample.is_empty():_sample={};visible=false;return true
	if not prepared or sample.get("base_content_id")!=_source.base_content_id or sample.get("binding_id")!=_source.binding_id:
		return fail("Aim sample belongs to another content profile")
	var point: Variant=sample.get("point")
	if not point is Vector3 or not point.is_finite() or not TargetProjection.safe_pixel(point.x) or not TargetProjection.safe_pixel(point.y) or not _textures.has(sample.get("image_id")) or not sample.get("visible") is bool:
		return fail("Invalid committed aim sample")
	_sample=sample.duplicate(true)
	reflow()
	return true

func set_mobile_layout(value: bool) -> void:
	mobile_layout=value;reflow()

func reflow() -> void:
	if not prepared or _sample.is_empty():return
	sprite.texture=_textures[_sample.image_id]
	sprite.size=sprite.texture.get_size()*(1.0 if mobile_layout else 0.5)
	sprite.position=Vector2(int(_sample.point.x),int(_sample.point.y))-sprite.size*0.5
	visible=_sample.visible

func source() -> Dictionary:return _source.duplicate(true)

func clear() -> void:
	if sprite!=null:sprite.free();sprite=null
	error="";prepared=false;visible=false;_source={};_sample={};_textures={}

func fail(message: String) -> bool:
	error=message
	return false
