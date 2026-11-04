extends Control
## Original NPC marker art and scanner filmstrip in the compact native HUD.
## Acquisition, target identity and health remain owned by the flight frame.
const TargetProjection = preload("res://src/presentation/target_projection.gd")
const Atlas = preload("res://src/content/atlas_region.gd")
const Frame = preload("res://src/presentation/flight_target_frame.gd")
const Definitions = preload("res://src/content/npc_scanner_definitions.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const ScanAnimation = preload("res://src/presentation/flight_scan_animation.gd")
const OriginalUI=preload("res://src/presentation/original_ui.gd")
const FontMetrics=preload("res://src/content/image_font.gd")
const Navigation=preload("res://src/content/combat_training_story_definitions.gd")
const Distance=preload("res://src/presentation/flight_distance.gd")
const HudStyle=preload("res://src/presentation/flight_hud_style.gd")
const BADGES={0:1185,1:1180,2:1183,3:1182,8:1184,9:1181}
var error := ""
var prepared := false
var mobile_layout := false
var _textures := {}
var _frames: Array[AtlasTexture] = []
var _source := {}
var _sample := {}
var _information:={}
var _information_art:={}
var _strings:=[]
var _font: FontFile
var _distance_rules:={}

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
	var art:=OriginalUI.new();var atlases:={}
	for id in Frame.BASELINE_ATLASES:atlases[str(id)]=Frame.BASELINE_ATLASES[id]
	var information_art:=art.load_regions(library,bindings,visuals,[1220]+BADGES.values(),atlases)
	if information_art.is_empty():return fail(art.error)
	var metrics:=FontMetrics.new()
	if not metrics.open_selected(library,bindings):return fail(metrics.error)
	var font:=metrics.create_font(visuals)
	if font==null:return fail(metrics.error)
	_information_art=information_art;_font=font;_strings=library.strings.duplicate()
	_distance_rules=Navigation.navigation(bindings)
	_source={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"texture_id":texture_id,"resource":resource,"regions":regions,"animation":geometry}
	prepared=true
	return true

func present(sample: Dictionary,suppress_information:=false) -> bool:
	error=""
	if sample.is_empty():_sample={};_information={};visible=false;queue_redraw();return true
	if not prepared or sample.get("base_content_id")!=_source.base_content_id or sample.get("binding_id")!=_source.binding_id:return fail("NPC marker sample belongs to another profile")
	if not sample.get("visible") is bool or not sample.get("markers") is Array or not sample.get("aim_pixels") is Vector2i or not Numbers.integer(sample.get("animation_frame"),-1,_frames.size()-1):return fail("Invalid NPC marker sample")
	for marker in sample.markers:
		if not marker is Dictionary or not marker.get("pixels") is Vector2i or not marker.get("near") is bool or not marker.get("selected") is bool or not marker.get("hostile") is bool or not Numbers.integer(marker.get("hull_percent"),0,100):return fail("Invalid NPC marker row")
	var information:={}
	var selected: Variant=sample.get("selected_target",{})
	if not selected is Dictionary:return fail("Invalid selected NPC information")
	# Junk (kind -1) has no scanner panel; the tractor and the pickup message handle its crate.
	if sample.visible and not suppress_information and not selected.is_empty() and selected.get("actor_kind")!=-1:
		if not Numbers.integer(selected.get("actor_kind"),0,10) or not Numbers.integer(selected.get("name_text_id"),-1,_strings.size()-1) or not Numbers.integer(selected.get("hull_percent"),0,100):return fail("Selected NPC identity or hull is invalid")
		var named: bool=selected.name_text_id>=0
		var id: int=selected.name_text_id if named else 395+int(selected.actor_kind)
		if id>=_strings.size() or _strings[id].is_empty():return fail("Selected NPC has no localized identity")
		var special: bool=selected.name_text_id in [1600,1652]
		var label: String=String(selected.get("display_name",_strings[id]))
		information={"text":label if special else "%s %d%%"%[label,selected.hull_percent],
			"color":Color("ff2a00") if special else Color.WHITE,"badge_image_id":int(BADGES.get(int(selected.actor_kind),-1))}
	_sample=sample.duplicate(true);_information=information;visible=sample.visible;queue_redraw()
	return true

func set_mobile_layout(value: bool) -> void:
	mobile_layout=value;queue_redraw()

func _draw() -> void:
	if not prepared or _sample.is_empty() or not _sample.visible:return
	texture_filter=HudStyle.filtering()
	# Resolve physical atlas sizes into the same phone composition, then halve
	# desktop art. Scan-window pixels are independent of this presentation scale.
	var scale_factor: float=41.0/_textures[1234].get_width()*HudStyle.art(mobile_layout)
	var half := Vector2(floorf(_textures[1234].get_width()/2.0),floorf(_textures[1234].get_height()/2.0))
	for marker in _sample.markers:
		var point := Vector2(marker.pixels)
		if marker.has("in_view") and not marker.in_view:
			point=(size*0.5+(point-size*0.5)*HudStyle.multiplier).clamp(Vector2.ONE*16,size-Vector2.ONE*16)
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
			if marker.selected and marker.get("in_view",false) and not _distance_rules.is_empty() and marker.get("position") is Vector3 and _sample.get("camera_position") is Vector3:
				var meters:=Distance.meters(marker.position,_sample.camera_position,_distance_rules)
				if meters>=0:
					var font_size:=HudStyle.font_size(20 if mobile_layout else 12)
					var text:=Distance.label(meters,_distance_rules)
					var position:=point+Vector2((_textures[id].get_width()*0.5+3.0)*scale_factor,_font.get_ascent(font_size)*0.5)
					draw_string_outline(_font,position,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,2,Color(0,0,0,0.8))
					draw_string(_font,position,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color.WHITE)
	if _sample.animation_frame>=0:_centered(_frames[_sample.animation_frame],Vector2(_sample.aim_pixels),HudStyle.art(mobile_layout))
	_draw_information(HudStyle.art(mobile_layout))

## The target panel's rect in this control, or an empty rect without a target.
func information_rect() -> Rect2:
	if _information.is_empty() or not _information_art.has(1220):return Rect2()
	var extent: Vector2=_information_art[1220].get_size()*HudStyle.art(mobile_layout)
	return Rect2(Vector2((size.x-extent.x)*0.5,3.0*(1.0 if mobile_layout else 0.5)),extent)

func _draw_information(art_scale: float) -> void:
	if _information.is_empty():return
	var panel: Texture2D=_information_art[1220]
	var extent:=panel.get_size()*art_scale
	var top:=Vector2((size.x-extent.x)*0.5,3.0*(1.0 if mobile_layout else 0.5))
	draw_texture_rect(panel,Rect2(top,extent),false)
	var font_size:=HudStyle.font_size(20 if mobile_layout else 12)
	var badge: Texture2D=_information_art.get(_information.badge_image_id)
	var icon_size:=Vector2.ZERO if badge==null else badge.get_size()*art_scale
	var gap:=3.0*(1.0 if mobile_layout else 0.5)
	var width:=extent.x-24.0*art_scale-icon_size.x-gap
	while font_size>8 and _font.get_string_size(_information.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>width:font_size-=1
	var text_size:=_font.get_string_size(_information.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	var x: float=(size.x-text_size.x)*0.5
	var y: float=top.y+(extent.y-_font.get_height(font_size))*0.5+_font.get_ascent(font_size)
	if badge!=null:draw_texture_rect(badge,Rect2(Vector2(x-gap-icon_size.x,top.y+(extent.y-icon_size.y)*0.5),icon_size),false)
	draw_string(_font,Vector2(x,y),_information.text,HORIZONTAL_ALIGNMENT_LEFT,width,font_size,_information.color)

func information_snapshot() -> Dictionary:return _information.duplicate(true)

func _centered(texture: Texture2D, point: Vector2, scale_factor: float) -> void:
	var extent := texture.get_size()
	var anchor := Vector2(floorf(extent.x/2.0),floorf(extent.y/2.0))
	draw_texture_rect(texture,Rect2(point-anchor*scale_factor,extent*scale_factor),false)

func source() -> Dictionary:return _source.duplicate(true)
func clear() -> void:
	error="";prepared=false;visible=false;_textures={};_frames.clear();_source={};_sample={}
	_information={};_information_art={};_strings=[];_font=null;_distance_rules={};queue_redraw()
func fail(message: String) -> bool:
	error=message
	return false
