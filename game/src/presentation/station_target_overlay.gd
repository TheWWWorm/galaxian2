extends Control
## The source neutral target rings and catalogue identity for an ordinary
## station. Acquisition and projection are committed by StationTargeting.
const Atlas=preload("res://src/content/atlas_region.gd")
const Frame=preload("res://src/presentation/flight_target_frame.gd")
const TargetProjection=preload("res://src/presentation/target_projection.gd")
const Story=preload("res://src/content/combat_training_story_definitions.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const Library=preload("res://src/content/library.gd")
const RESOURCE:="resources/data/textures/gof2_interface2_ipad.aei"
const MARKER_IMAGE_ID:=1225
const SELECTED_IMAGE_ID:=1244
var error:=""
var _identity:={}
var _station_id:=-1
var _station_name:=""
var _tech_text:=""
var _distance_rules:={}
var _textures:={}
var _sample:={}
var _mobile:=false

func _init() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE;clip_contents=true;visible=false

func prepare(library: RefCounted,bindings: RefCounted,visuals: RefCounted,catalogues: RefCounted,station: Dictionary) -> bool:
	error=""
	if library==null or bindings==null or visuals==null or catalogues==null or not Library.valid_hash(bindings.get("binding_id")) or library.manifest.get("content_id")!=bindings.base_content_id or visuals.base_content_id!=bindings.base_content_id or catalogues.content_id!=bindings.base_content_id:
		return reject("Station marker requires matching original content and pixels")
	if station.get("base_content_id")!=bindings.base_content_id or station.get("binding_id")!=bindings.binding_id or not station.get("station_id") is int or station.station_id<0 or station.station_id>=catalogues.tables.stations.size() or not station.get("name") is String or station.name.is_empty():
		return reject("Station marker requires its constructed source location")
	var row: Dictionary=catalogues.tables.stations[station.station_id]
	if row.name!=station.name or row.fields.size()<3 or not row.fields[2] is int:return reject("Station marker catalogue differs from its exterior")
	if library.strings.size()<=135 or library.strings[132].is_empty() or library.strings[135].is_empty():return reject("Localized station identity is unavailable")
	var rules: Dictionary=Story.navigation(bindings)
	if rules.is_empty() or rules.get("distance_coordinate_scale")!=0.5 or rules.get("distance_squared_scale")!=0.000244140625 or rules.get("distance_result_scale")!=8:
		return reject("Station distance requires the shared source HUD units")
	if Frame.BASELINE_ATLASES.get(10063)!=RESOURCE:return reject("Station marker atlas differs from the flight HUD")
	var textures:={};var reader:=Atlas.new()
	for image_id in [MARKER_IMAGE_ID,SELECTED_IMAGE_ID]:
		var alias: Dictionary=bindings.resolve_image_region(image_id,10063)
		if alias.is_empty():return reject(bindings.error)
		var texture:=reader.load(library,visuals,RESOURCE,int(alias.region))
		if texture==null:return reject(reader.error)
		textures[image_id]=texture
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_station_id=int(station.station_id);_station_name="%s %s"%[station.name,library.strings[135]]
	_tech_text="%s: %d"%[library.strings[132],int(row.fields[2])]
	_distance_rules=rules;_textures=textures;_sample={};visible=false
	return true

func present(lock: Dictionary,camera: Transform3D,hud_enabled: bool) -> bool:
	error=""
	if _identity.is_empty():return reject("Prepare station marker before presenting")
	if lock.is_empty():_sample={};visible=false;queue_redraw();return true
	for key in _identity:
		if lock.get(key)!=_identity[key]:return reject("Station marker belongs to another imported flight")
	if lock.get("station_id")==_station_id and not lock.has("station_pixels") and lock.get("found_index")==-1 and lock.get("aimed_index")==-1 and lock.get("locked_index")==-1 and lock.get("elapsed_ms")==0:
		_sample={};visible=false;queue_redraw();return true
	if lock.get("station_id")!=_station_id or not lock.get("station_in_view") is bool or not lock.get("station_pixels") is Vector2i or not lock.get("station_position") is Vector3 or not lock.station_position.is_finite() or not Flight.rigid_pose(camera):
		return reject("Station marker requires a projected live station")
	for key in ["found_index","aimed_index","locked_index"]:
		if not lock.get(key) is int or lock[key] not in [-1,0]:return reject("Station marker has an invalid acquisition index")
	if not lock.get("elapsed_ms") is int or lock.elapsed_ms<0 or not lock.get("duration_ms") is int or lock.duration_ms<1:return reject("Station marker has an invalid acquisition clock")
	var meters:=distance_meters(lock.station_position,camera.origin)
	if meters<0:return reject("Station distance exceeds source range")
	var draw: bool=hud_enabled and lock.station_in_view
	_sample={"visible":draw,"pixels":lock.station_pixels,"selected":lock.aimed_index==0 or lock.locked_index==0,
		"label_visible":lock.locked_index==0,"name":_station_name,"tech":_tech_text,"distance":distance_text(meters),"distance_meters":meters}
	visible=draw;queue_redraw()
	return true

func distance_meters(point: Vector3,eye: Vector3) -> int:
	if _distance_rules.is_empty() or not point.is_finite() or not eye.is_finite():return -1
	var squared: int=0
	for axis in 3:
		var delta:=TargetProjection.single(TargetProjection.single(point[axis]*_distance_rules.distance_coordinate_scale)-TargetProjection.single(eye[axis]*_distance_rules.distance_coordinate_scale))
		if not is_finite(delta) or absf(delta)>1000000000:return -1
		var component:=int(delta);squared+=component*component
	var root:=TargetProjection.single(sqrt(TargetProjection.single(TargetProjection.single(float(squared))*_distance_rules.distance_squared_scale)))
	var result:=int(root)*int(_distance_rules.distance_result_scale)
	return result if result<2147483648 else -1

func distance_text(meters: int) -> String:
	if meters<int(_distance_rules.kilometer_threshold):return "%dm"%meters
	@warning_ignore("integer_division")
	return "%d.%dkm"%[meters/1000,(meters%1000)/100]

func set_mobile_layout(value: bool) -> void:_mobile=value;queue_redraw()
func snapshot() -> Dictionary:return _sample.duplicate(true)

func _draw() -> void:
	if _sample.is_empty() or not _sample.visible:return
	var texture: Texture2D=_textures[SELECTED_IMAGE_ID if _sample.selected else MARKER_IMAGE_ID]
	var art_scale:=1.0 if _mobile else 0.5
	var extent:=texture.get_size()*art_scale
	var point:=Vector2(_sample.pixels)
	draw_texture_rect(texture,Rect2(point-extent*0.5,extent),false)
	if not _sample.label_visible:return
	var font:=get_theme_font("font");var font_size:=22 if _mobile else 14
	var x:=point.x+extent.x*0.5+6.0*art_scale
	var y:=point.y-extent.y*0.5+font.get_ascent(font_size)
	for line in [_sample.name,_sample.tech,_sample.distance]:
		var baseline:=Vector2(x,y)
		draw_string_outline(font,baseline,line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,2,Color(0,0,0,0.8))
		draw_string(font,baseline,line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color.WHITE)
		y+=font.get_height(font_size)+2.0*art_scale

func reject(message: String) -> bool:error=message;return false
