extends TextureRect
## Keep 3D at physical resolution while the surrounding interface uses UI scale.
var viewport: SubViewport

func _ready() -> void:
	expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode=TextureRect.STRETCH_SCALE
	# The 3D scene also owns native GUI panels (flight conversations). Forward
	# pointer events into its viewport while allowing outer controls to receive
	# events when no embedded GUI consumes them.
	mouse_filter=Control.MOUSE_FILTER_PASS
	viewport=SubViewport.new();viewport.own_world_3d=true;viewport.handle_input_locally=false
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(viewport);texture=viewport.get_texture()
	resized.connect(refresh_size);get_window().size_changed.connect(refresh_size)
	refresh_size()

func refresh_size() -> void:
	if viewport==null:return
	var pixels: Vector2=get_global_transform_with_canvas().get_scale().abs()*get_viewport().get_stretch_transform().get_scale().abs()
	viewport.size=Vector2i(maxi(2,roundi(size.x*pixels.x)),maxi(2,roundi(size.y*pixels.y)))
	# Projection and HUD coordinates stay in the same logical coordinate space.
	viewport.size_2d_override=Vector2i(maxi(2,roundi(size.x)),maxi(2,roundi(size.y)))
	viewport.size_2d_override_stretch=true

func _gui_input(event: InputEvent) -> void:
	if viewport==null or size.x<=0 or size.y<=0 or not event is InputEventMouse:return
	var forwarded: InputEventMouse=event.duplicate()
	# Control input is already in the authored 2D coordinate space. The child
	# viewport maps that space to its physical render target itself.
	forwarded.position=event.position
	forwarded.global_position=forwarded.position
	viewport.push_input(forwarded,true)
	if viewport.is_input_handled():accept_event()
