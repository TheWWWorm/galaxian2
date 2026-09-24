extends Control
## Native remake touch steering and primary fire. Multiple fingers retain their
## own controls; pausing or hiding clears every held input.
const OriginalUI=preload("res://src/presentation/original_ui.gd")
const ART_IDS=[1200,1201,1204,1205,1206,1207,1208,1209,1210,1211,1212,1213,1214,1215,1217,1257,1258,1344,1345]
signal steering(command: Vector2, held: bool)
signal firing(held: bool)
var active := false
var mobile := OS.has_feature("mobile")
var _stick_id := -2
var _fire_ids := {}
var _command := Vector2.ZERO
var _fire_label:="Fire"
var sprites:={}
var art_error:=""

func configure(library: RefCounted,bindings: RefCounted,visuals: RefCounted) -> bool:
	var atlas_resources: Dictionary=bindings.mido_travel.get("map",{}).get("ui",{}).get("atlas_resources",{})
	if atlas_resources.is_empty():art_error="Source touch atlas is unavailable";return false
	var art:=OriginalUI.new()
	var loaded: Dictionary=art.load_regions(library,bindings,visuals,ART_IDS,atlas_resources)
	if loaded.is_empty():art_error=art.error;return false
	sprites=loaded;art_error="";queue_redraw();return true

func set_fire_label(value: String) -> void:
	if _fire_label==value:return
	_fire_label=value;queue_redraw()

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func set_active(value: bool) -> void:
	if active==value:return
	active=value
	if not active:clear()
	queue_redraw()

func clear() -> void:
	_stick_id=-2;_fire_ids.clear();_command=Vector2.ZERO
	steering.emit(Vector2.ZERO,false);firing.emit(false);queue_redraw()

func radius() -> float:return 62.0 if mobile else 52.0
func fire_radius() -> float:return 48.0 if mobile else 43.0
func stick_center() -> Vector2:return Vector2(radius()+20,size.y-radius()-20)
func fire_center() -> Vector2:return Vector2(size.x-fire_radius()-16,size.y-fire_radius()-16)

func _input(event: InputEvent) -> void:
	if not active or not is_visible_in_tree():return
	var handled:=false
	if event is InputEventScreenTouch:
		handled=press(event.index,event.position) if event.pressed else release(event.index)
	elif event is InputEventScreenDrag:
		handled=drag(event.index,event.position)
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.device!=-1:
		handled=press(-1,event.position) if event.pressed else release(-1)
	elif event is InputEventMouseMotion and event.device!=-1:
		handled=drag(-1,event.position)
	if handled:get_viewport().set_input_as_handled()

func press(id: int, point: Vector2) -> bool:
	if not active or not is_visible_in_tree():return false
	point=get_global_transform_with_canvas().affine_inverse()*point
	if _stick_id==-2 and point.distance_to(stick_center())<=radius():
		_stick_id=id;move_stick(point);return true
	if point.distance_to(fire_center())<=fire_radius():
		_fire_ids[id]=true;firing.emit(true);queue_redraw();return true
	return false

func drag(id: int, point: Vector2) -> bool:
	if id==_stick_id and _stick_id!=-2:
		move_stick(get_global_transform_with_canvas().affine_inverse()*point);return true
	return _fire_ids.has(id)

func release(id: int) -> bool:
	if id==_stick_id and _stick_id!=-2:
		_stick_id=-2;_command=Vector2.ZERO;steering.emit(Vector2.ZERO,false);queue_redraw();return true
	if _fire_ids.erase(id):firing.emit(not _fire_ids.is_empty());queue_redraw();return true
	return false

func move_stick(point: Vector2) -> void:
	var direction:=(point-stick_center())/radius()
	direction=direction.limit_length(1.0)
	_command=Vector2(direction.y,direction.x)
	steering.emit(_command,true);queue_redraw()

func _draw() -> void:
	if not sprites.is_empty():
		var base:=radius()*2.15
		_draw_sprite(1217,stick_center(),Vector2.ONE*base)
		var knob:=stick_center()+Vector2(_command.y,_command.x)*radius()*0.42
		_draw_sprite(1206 if _stick_id!=-2 else 1207,knob,Vector2.ONE*radius()*1.45)
		_draw_sprite(1204 if not _fire_ids.is_empty() else 1205,fire_center(),Vector2.ONE*fire_radius()*2.0)
		if _fire_label=="Stop":
			var font:=ThemeDB.fallback_font
			var label_size:=18 if mobile else 14
			var extent:=font.get_string_size(_fire_label,HORIZONTAL_ALIGNMENT_LEFT,-1,label_size)
			draw_string(font,fire_center()+Vector2(-extent.x/2,extent.y/4),_fire_label,HORIZONTAL_ALIGNMENT_LEFT,-1,label_size,Color(0.04,0.12,0.18))
		return
	var color:=Color(0.46,0.78,0.92,0.8 if active else 0.25)
	var fill:=Color(0.015,0.035,0.06,0.7 if active else 0.3)
	for center in [stick_center(),fire_center()]:
		draw_circle(center,radius(),fill)
		draw_arc(center,radius(),0,TAU,64,color,1.5,true)
	var point:=stick_center()+Vector2(_command.y,_command.x)*radius()*0.7
	draw_circle(point,radius()*0.28,color)
	var font:=ThemeDB.fallback_font;var font_size:=20 if mobile else 14
	var label:=_fire_label;var extent:=font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	if not _fire_ids.is_empty():draw_circle(fire_center(),radius()-2,Color(0.3,0.65,0.8,0.4))
	draw_string(font,fire_center()+Vector2(-extent.x/2,extent.y/4),label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _draw_sprite(id: int,center: Vector2,extent: Vector2) -> void:
	draw_texture_rect(sprites[id],Rect2(center-extent*0.5,extent),false,Color.WHITE if active else Color(1,1,1,0.5))
