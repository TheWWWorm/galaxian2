extends Control
## Shared source acquisition filmstrip for NPCs and mineable asteroids.
## Gameplay supplies a frame index; drawing never advances acquisition time.
const Atlas=preload("res://src/content/atlas_region.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const RESOURCE:="resources/data/textures/gof2_interface.aei"
var error:=""
var prepared:=false
var mobile_layout:=false
var _source:={}
var _frames: Array[AtlasTexture]=[]
var _sample:={}

func _init() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE;clip_contents=true;visible=false

static func source_geometry(library: RefCounted, bindings: RefCounted, data: Dictionary) -> Dictionary:
	if library==null or bindings==null or bindings.base_content_id!=library.manifest.get("content_id") or data.get("animation_image_id")!=1110 or data.get("animation_texture_id")!=10062 or data.get("animation_region")!=10:return {"error":"Scanner animation requires its imported source declarations"}
	var registered:=false
	for record in bindings.records.get(int(data.animation_texture_id),[]):
		if record.resource==RESOURCE and record.kind=="texture" and int(record.registration_type)==2:registered=true
	if not registered:return {"error":"Scanner atlas is not registered by this profile"}
	var reader:=Atlas.new()
	var metadata:=reader.region(library.read_resource(RESOURCE,Atlas.MAX_BYTES),int(data.animation_region))
	if metadata.is_empty():return {"error":reader.error}
	var rect: Rect2i=metadata.rect
	if rect.size.x%rect.size.y!=0:return {"error":"Unsupported scanner filmstrip dimensions"}
	return {"rect":rect,"frames":rect.size.x/rect.size.y,"frame_size":rect.size.y,"resource":RESOURCE,"region":int(data.animation_region)}

static func source_frames(strip: AtlasTexture, geometry: Dictionary) -> Array[AtlasTexture]:
	var frames: Array[AtlasTexture]=[]
	for index in geometry.frames:
		var frame:=AtlasTexture.new();frame.atlas=strip.atlas;frame.filter_clip=true
		frame.region=Rect2(Vector2(geometry.rect.position)+Vector2(index*geometry.frame_size,0),Vector2.ONE*geometry.frame_size)
		frames.append(frame)
	return frames

func prepare(library: RefCounted, bindings: RefCounted, visuals: RefCounted, data: Dictionary) -> bool:
	clear()
	var geometry:=source_geometry(library,bindings,data)
	if geometry.has("error"):return reject(geometry.error)
	if visuals==null or visuals.base_content_id!=bindings.base_content_id:return reject("Scanner pixels belong to another content profile")
	var reader:=Atlas.new();var strip:=reader.load(library,visuals,RESOURCE,geometry.region)
	if strip==null:return reject(reader.error)
	_frames=source_frames(strip,geometry)
	_source=geometry;_source.merge({"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id})
	prepared=true
	return true

func present(sample: Dictionary) -> bool:
	error=""
	if sample.is_empty():_sample={};visible=false;queue_redraw();return true
	if not prepared or sample.get("base_content_id")!=_source.base_content_id or sample.get("binding_id")!=_source.binding_id or not sample.get("visible") is bool or not sample.get("aim_pixels") is Vector2i or not Numbers.integer(sample.get("animation_frame"),-1,_frames.size()-1):return reject("Invalid scanner animation sample")
	_sample={"visible":sample.visible,"aim_pixels":sample.aim_pixels,"animation_frame":int(sample.animation_frame)}
	visible=sample.visible;queue_redraw()
	return true

func set_mobile_layout(value: bool) -> void:mobile_layout=value;queue_redraw()
func frame_rect() -> Rect2:
	if _sample.is_empty() or not _sample.visible or _sample.animation_frame<0:return Rect2()
	var extent:=_frames[_sample.animation_frame].get_size()
	var scale_factor:=1.0 if mobile_layout else 0.5
	var anchor:=Vector2(floorf(extent.x/2.0),floorf(extent.y/2.0))
	return Rect2(Vector2(_sample.aim_pixels)-anchor*scale_factor,extent*scale_factor)
func _draw() -> void:
	var rect:=frame_rect()
	if rect.has_area():draw_texture_rect(_frames[_sample.animation_frame],rect,false)
func source() -> Dictionary:return _source.duplicate(true)
func clear() -> void:
	error="";prepared=false;visible=false;_source={};_frames.clear();_sample={};queue_redraw()
func reject(message: String) -> bool:error=message;return false
