extends Control
## Original NPC marker art and scanner filmstrip in the compact native HUD.
## Distance labels, auxiliary bars and selected-target information are pending.
const TargetProjection = preload("res://src/presentation/target_projection.gd")
const Atlas = preload("res://src/content/atlas_region.gd")
const Frame = preload("res://src/presentation/flight_target_frame.gd")
const Definitions = preload("res://src/content/npc_scanner_definitions.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const ScanAnimation = preload("res://src/presentation/flight_scan_animation.gd")
var error := ""
var prepared := false
var mobile_layout := false
var _textures := {}
var _frames: Array[AtlasTexture] = []
var _source := {}
var _sample := {}

func _init() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE;clip_contents=true;visible=false

static func source_geometry(library: RefCounted, bindings: RefCounted) -> Dictionary:
	if library==null or bindings==null or bindings.base_content_id!=library.manifest.get("content_id") or not Definitions.parameters(bindings.opening_staging.get("npc_scanner",{})):
		return {"error":"Scanner animation requires its imported source declarations"}
	return ScanAnimation.source_geometry(library,bindings,bindings.opening_staging.npc_scanner)

func prepare(library: RefCounted, bindings: RefCounted, visuals: RefCounted) -> bool:
	clear()
	var geometry := source_geometry(library,bindings)
	if geometry.has("error"):return fail(geometry.error)
	if visuals==null or visuals.base_content_id!=bindings.base_content_id:return fail("NPC marker pixels belong to another content profile")
	var data: Dictionary=bindings.opening_staging.npc_scanner
	var texture_id := int(data.marker_texture_id)
	if not Frame.BASELINE_ATLASES.has(texture_id):return fail("Unsupported marker atlas")
	var resource: String=Frame.BASELINE_ATLASES[texture_id]
	var bytes: PackedByteArray=library.read_resource(resource,Atlas.MAX_BYTES)
	if bytes.is_empty():return fail(library.error)
	var reader := Atlas.new()
	var sheet: Texture2D
	var regions := []
	for id in data.image_ids:
		var alias: Dictionary=bindings.resolve_image_region(int(id),texture_id)
		if alias.is_empty():return fail(bindings.error)
		var metadata := reader.region(bytes,int(alias.region))
		if metadata.is_empty():return fail(reader.error)
		if sheet==null:
			var first := reader.load(library,visuals,resource,int(alias.region))
			if first==null:return fail(reader.error)
			sheet=first.atlas
		var texture := AtlasTexture.new();texture.atlas=sheet;texture.region=Rect2(metadata.rect);texture.filter_clip=true
		_textures[int(id)]=texture
		regions.append({"image_id":int(id),"region":int(alias.region),"rect":metadata.rect})
	var strip := reader.load(library,visuals,geometry.resource,geometry.region)
	if strip==null:return fail(reader.error)
	_frames=ScanAnimation.source_frames(strip,geometry)
	_source={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"texture_id":texture_id,"resource":resource,"regions":regions,"animation":geometry}
	prepared=true
	return true

func present(sample: Dictionary) -> bool:
	error=""
	if sample.is_empty():_sample={};visible=false;queue_redraw();return true
	if not prepared or sample.get("base_content_id")!=_source.base_content_id or sample.get("binding_id")!=_source.binding_id:return fail("NPC marker sample belongs to another profile")
	if not sample.get("visible") is bool or not sample.get("markers") is Array or not sample.get("aim_pixels") is Vector2i or not Numbers.integer(sample.get("animation_frame"),-1,_frames.size()-1):return fail("Invalid NPC marker sample")
	for marker in sample.markers:
		if not marker is Dictionary or not marker.get("pixels") is Vector2i or not marker.get("near") is bool or not marker.get("selected") is bool or not marker.get("hostile") is bool or not Numbers.integer(marker.get("hull_percent"),0,100):return fail("Invalid NPC marker row")
	_sample=sample.duplicate(true);visible=sample.visible;queue_redraw()
	return true

func set_mobile_layout(value: bool) -> void:
	mobile_layout=value;queue_redraw()

func _draw() -> void:
	if not prepared or _sample.is_empty() or not _sample.visible:return
	# Resolve physical atlas sizes into the same phone composition, then halve
	# desktop art. Scan-window pixels are independent of this presentation scale.
	var scale_factor: float=41.0/_textures[1234].get_width()*(1.0 if mobile_layout else 0.5)
	var half := Vector2(floorf(_textures[1234].get_width()/2.0),floorf(_textures[1234].get_height()/2.0))
	for marker in _sample.markers:
		var point := Vector2(marker.pixels)
		if marker.near:
			var bg := 1242 if marker.hostile else 1237
			var fill := 1241 if marker.hostile else 1238
			draw_texture_rect(_textures[bg],Rect2(point+(Vector2(2,half.y+2)-Vector2(half.x,0))*scale_factor,_textures[bg].get_size()*scale_factor),false)
			var width := int(TargetProjection.single(TargetProjection.single(float(marker.hull_percent)/100.0)*_textures[1236].get_width()))
			if width>0:
				var extent := Vector2(width,_textures[1236].get_height())
				draw_texture_rect_region(_textures[fill],Rect2(point+(Vector2(3,half.y+3)-Vector2(half.x,0))*scale_factor,extent*scale_factor),Rect2(Vector2.ZERO,extent))
			if marker.selected:_centered(_textures[1243 if marker.hostile else 1244],point,scale_factor)
		else:
			var id := (1224 if marker.hostile else 1225) if marker.selected else (1228 if marker.hostile else 1227)
			_centered(_textures[id],point,scale_factor)
	if _sample.animation_frame>=0:_centered(_frames[_sample.animation_frame],Vector2(_sample.aim_pixels),1.0 if mobile_layout else 0.5)

func _centered(texture: Texture2D, point: Vector2, scale_factor: float) -> void:
	var extent := texture.get_size()
	var anchor := Vector2(floorf(extent.x/2.0),floorf(extent.y/2.0))
	draw_texture_rect(texture,Rect2(point-anchor*scale_factor,extent*scale_factor),false)

func source() -> Dictionary:return _source.duplicate(true)
func clear() -> void:
	error="";prepared=false;visible=false;_textures={};_frames.clear();_source={};_sample={};queue_redraw()
func fail(message: String) -> bool:
	error=message
	return false
