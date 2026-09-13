extends Control
## Screen effect beneath the flight HUD and above the finite 3D world.
var textures: Array[AtlasTexture]=[]
var composition:={}
var source_color:=Color.WHITE
func _init() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE;clip_contents=true
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
func apply_frame(value: Dictionary,color: Array) -> void:
	composition=value.duplicate(true)
	source_color=Color(float(color[0])/255.0,float(color[1])/255.0,float(color[2])/255.0)
	queue_redraw()
func _draw() -> void:
	for row in composition.get("sprites",[]):
		var tint:=source_color;tint.a=float(row.alpha_byte)/255.0
		draw_texture_rect(textures[row.image_index],Rect2(row.rect),false,tint)
	if composition.get("wash_alpha",0)>0:
		var tint:=source_color;tint.a=float(composition.wash_alpha)/255.0
		draw_rect(Rect2(Vector2.ZERO,size),tint)
