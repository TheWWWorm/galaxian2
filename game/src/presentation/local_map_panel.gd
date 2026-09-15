extends Control
## Original map models, atlas sprites and glyphs, with native input and layout.
signal destination_requested(station_id: int)
signal close_requested
signal system_requested(system_id: int)
const OriginalUI=preload("res://src/presentation/original_ui.gd")
const Navigation=preload("res://src/simulation/local_map.gd")
const Models=preload("res://src/presentation/model_resources.gd")
const Model=preload("res://src/presentation/imported_model.gd")
const AEM=preload("res://src/content/aem.gd")
const Atlas=preload("res://src/content/atlas_region.gd")
const Metrics=preload("res://src/content/image_font.gd")
var error:=""
var _navigation: RefCounted
var _mobile:=false
var _active:=false
var _panel: Control
var _title: Label
var _faction: Label
var _security: Label
var _faction_icon: TextureRect
var _field: Control
var _view: SubViewport
var _camera: Camera3D
var _world: Node3D
var _system: Node3D
var _canvas: MapCanvas
var _status: Label
var _notice: Panel
var _footer: TextureRect
var _legend: PanelContainer
var _legend_rows: VBoxContainer
var _target: Button
var _yes: Button
var _no: Button
var _back: Button
var _key: Button
var _systems: HBoxContainer
var _bounds_points: Array[Vector3]=[]
var _sprites:={}
var _styles:={}
var _font: FontFile

class MapCanvas extends Control:
	signal selected(station_id: int)
	var rows:=[]
	var selected_id:=-1
	var mobile:=false
	var active:=false
	var sprites:={}
	var rules:={}
	var font: FontFile
	func _gui_input(event: InputEvent) -> void:
		if not active:return
		var point:=Vector2.ZERO
		if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:point=event.position
		elif event is InputEventScreenTouch and event.pressed:point=event.position
		else:return
		var nearest:=-1;var distance:=36.0 if mobile else 25.0
		for row in rows:
			var away: float=point.distance_to(row.pixels)
			if away<=distance:distance=away;nearest=int(row.station_id)
		if nearest>=0:selected.emit(nearest);accept_event()
	func label_rectangles() -> Array[Rect2]:
		var result: Array[Rect2]=[]
		if font==null:return result
		var extent:=68.0 if mobile else 44.0
		var font_size:=20 if mobile else 14
		for row in rows:
			var width:=font.get_string_size(row.name,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
			var left:=clampf(row.pixels.x-width/2,3,maxf(3,size.x-width-3))
			var label:=Rect2(Vector2(left,row.pixels.y+extent/2+3),Vector2(width,font_size+2))
			# Nearby planets keep their source positions. Stack intersecting names
			# beneath their frames so larger touch-layout glyphs remain readable.
			for attempt in result.size()+1:
				var moved:=false
				for previous in result:
					if label.intersects(previous):label.position.y=previous.end.y+3;moved=true
				if not moved:break
			result.append(label)
		return result
	func _draw() -> void:
		if font==null or sprites.is_empty():return
		var extent:=68.0 if mobile else 44.0
		var font_size:=20 if mobile else 14
		var icon_size:=22.0 if mobile else 15.0
		var labels:=label_rectangles()
		for index in rows.size():
			var row: Dictionary=rows[index]
			var id:=int(rules.selected_image_id if row.station_id==selected_id else rules.frame_image_id)
			draw_texture_rect(sprites[id],Rect2(row.pixels-Vector2.ONE*extent/2,Vector2.ONE*extent),false)
			var anchor:=labels[index].position+Vector2(0,font_size)
			draw_string(font,anchor+Vector2.ONE,row.name,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color.BLACK)
			draw_string(font,anchor,row.name,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color.WHITE)
			if row.mission_target or row.current:
				var marker:=int(rules.story_image_id if row.mission_target else rules.current_image_id)
				draw_texture_rect(sprites[marker],Rect2(row.pixels+Vector2(extent/2-2,-extent/2-3),Vector2.ONE*icon_size),false)

func _init() -> void:
	visible=false;mouse_filter=Control.MOUSE_FILTER_STOP
	_panel=Control.new();add_child(_panel);_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_field=Control.new();_panel.add_child(_field);_field.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_field.clip_contents=true
	var container:=SubViewportContainer.new();container.stretch=true;container.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_field.add_child(container);container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view=SubViewport.new();_view.own_world_3d=true;_view.handle_input_locally=false;_view.gui_disable_input=true
	_view.msaa_3d=Viewport.MSAA_4X;_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	container.add_child(_view)
	_world=Node3D.new();_view.add_child(_world)
	_camera=Camera3D.new();_camera.keep_aspect=Camera3D.KEEP_HEIGHT;_camera.near=1;_camera.far=64000
	_world.add_child(_camera)
	_canvas=MapCanvas.new();_field.add_child(_canvas);_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.selected.connect(select_station)
	_faction_icon=texture_rect(_panel)
	_title=label(_panel);_faction=label(_panel);_security=label(_panel)
	_footer=texture_rect(_panel)
	_notice=Panel.new();_notice.mouse_filter=Control.MOUSE_FILTER_IGNORE;_panel.add_child(_notice);_notice.visible=false
	_status=label(_notice);_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;_status.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_legend=PanelContainer.new();_panel.add_child(_legend);_legend.visible=false
	_legend_rows=VBoxContainer.new();_legend.add_child(_legend_rows)
	_back=button(back);_target=button(request_confirmation);_no=button(back);_yes=button(confirm_destination)
	_key=button(func():_legend.visible=not _legend.visible;_relayout())
	_systems=HBoxContainer.new();_panel.add_child(_systems)
	resized.connect(_relayout);_view.size_changed.connect(_project)

func texture_rect(parent: Node) -> TextureRect:
	var result:=TextureRect.new();result.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode=TextureRect.STRETCH_SCALE;result.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(result);return result

func label(parent: Node) -> Label:
	var result:=Label.new();result.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(result);return result

func button(action: Callable) -> Button:
	var result:=Button.new();result.focus_mode=Control.FOCUS_NONE
	_panel.add_child(result);result.pressed.connect(action);return result

func configure(library: RefCounted, bindings: RefCounted, visuals: RefCounted, catalogues: RefCounted, flight: Dictionary, display_system_id: int=-1) -> bool:
	error=""
	var navigation:=Navigation.new()
	if not navigation.configure(library,bindings,catalogues,flight,display_system_id):return reject(navigation.error)
	var state:=navigation.snapshot();var paths:=[];var art: Dictionary=state.visuals
	for row in state.rows:paths.append(row.model_path)
	var orbit_path: String=bindings.resolve(int(art.orbit_model_id),"mesh")
	if orbit_path.is_empty():return reject(bindings.error)
	paths.append(orbit_path)
	var background_paths:=[]
	for id in art.background_model_ids:
		var path: String=bindings.resolve(int(id),"mesh")
		if path.is_empty():return reject(bindings.error)
		background_paths.append(path);paths.append(path)
	var sprites:=load_sprites(library,bindings,visuals,state)
	if sprites.is_empty():return false
	var metrics:=Metrics.new()
	if not metrics.open_selected(library,bindings):return reject(metrics.error)
	var font:=metrics.create_font(visuals)
	if font==null:return reject(metrics.error)
	var sun:=build_sun(library,bindings,visuals,state)
	if sun==null:return false
	var resources:=Models.new()
	if not resources.prepare(paths,library,visuals,bindings,"high",true):sun.free();return reject(resources.error)
	var stage:=Node3D.new();var system:=Node3D.new();stage.add_child(system)
	system.rotation_order=EULER_ORDER_XYZ
	system.scale=Vector3.ONE*float(art.parent_scale)
	system.rotation=Vector3(art.parent_rotation[0],art.parent_rotation[1],art.parent_rotation[2])
	for row in state.rows:
		var orbit: Node3D=resources.instantiate(orbit_path)
		orbit.scale=Vector3.ONE*float(row.radius)*float(art.orbit_scale_multiplier);orbit.rotation.y=row.orbit_angle
		orbit.set_meta("source_resource_id",int(art.orbit_model_id));system.add_child(orbit)
		var model: Node3D=resources.instantiate(row.model_path)
		model.position=row.position;model.scale=Vector3.ONE*row.scale
		model.set_meta("source_resource_id",row.model_id);model.set_meta("source_station_id",row.station_id)
		for material in model.materials:
			material.set_shader_parameter("ambient_color",Vector3.ONE*state.ambient)
			material.set_shader_parameter("diffuse_color",Vector3.ONE*state.diffuse)
		for instance in model.instances:instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		system.add_child(model)
	for index in background_paths.size():
		var model: Node3D=resources.instantiate(background_paths[index]);stage.add_child(model)
		model.position=Vector3(-3000,-2500,0)
		model.set_meta("source_resource_id",int(art.background_model_ids[index]))
	stage.add_child(sun);resources.clear()
	clear();_navigation=navigation;_sprites=sprites;_font=font;_system=system;_world.add_child(stage)
	for model in system.get_children():
		if not model.has_meta("source_station_id"):continue
		for surface in model.surfaces:
			for point in surface.positions:_bounds_points.append(model.transform*point)
	var map_theme:=Theme.new();map_theme.default_font=font;theme=map_theme
	_canvas.font=font;_canvas.sprites=sprites;_canvas.rules=state.ui
	_camera.fov=rad_to_deg(float(art.field_of_view_radians))
	_camera.near=float(art.camera_near);_camera.far=float(art.camera_far)
	_title.text=state.system_name;_faction.text=state.labels.faction;_security.text=state.labels.security
	_security.modulate=state.security_color
	_faction_icon.texture=sprites[state.faction_image_id];_footer.texture=sprites[int(state.ui.footer_image_id)]
	for entry in state.labels.legend:
		var row:=HBoxContainer.new();_legend_rows.add_child(row)
		var icon:=texture_rect(row);icon.texture=sprites[entry.image_id];icon.custom_minimum_size=Vector2(22,22)
		icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var text:=label(row);text.text=entry.text
	_back.text=state.labels.back;_target.text=state.labels.target;_yes.text=state.labels.confirm;_no.text=state.labels.cancel;_key.text=state.labels.key
	for choice in state.system_choices:
		var item:=Button.new();item.text=choice.name;item.focus_mode=Control.FOCUS_NONE
		item.set_meta("system_id",int(choice.system_id));_systems.add_child(item)
		item.pressed.connect(func():request_system(int(item.get_meta("system_id"))))
	_systems.visible=state.system_choices.size()>1
	for mobile in [false,true]:
		var height:=44 if mobile else 30;var variants:={}
		variants.panel=panel_style(sprites,state.ui,1.0 if mobile else 0.5)
		for pressed in [false,true]:
			var ids: Array=state.ui.pressed_button_images if pressed else state.ui.button_images
			variants["pressed" if pressed else "normal"]=button_style(sprites,ids,height)
			ids=ids.duplicate();ids[0]=state.ui.pressed_back_image_id if pressed else state.ui.back_image_id
			variants["back_pressed" if pressed else "back_normal"]=button_style(sprites,ids,height)
		_styles[mobile]=variants
	visible=true;_camera.make_current();_present();_relayout()
	return true

func load_sprites(library: RefCounted, bindings: RefCounted, visuals: RefCounted, state: Dictionary) -> Dictionary:
	var art:=OriginalUI.new()
	var sprites:=art.load_sprites(library,bindings,visuals,state)
	if sprites.is_empty():reject(art.error)
	return sprites

func button_style(sprites: Dictionary,ids: Array,height: int) -> StyleBoxTexture:
	return OriginalUI.button_style(sprites,ids,height)

func panel_style(sprites: Dictionary,rules: Dictionary,scale: float) -> StyleBoxTexture:
	return OriginalUI.panel_style(sprites,rules,scale)

func build_sun(library: RefCounted, bindings: RefCounted, visuals: RefCounted, state: Dictionary) -> Node3D:
	var path: String=bindings.resolve(int(state.visuals.sun_mesh_id),"mesh")
	var texture_path: String=bindings.resolve_texture(int(state.sun_texture_id),"high")
	if path.is_empty() or texture_path.is_empty():reject(bindings.error);return null
	var reader:=AEM.new();var decoded:=reader.decode(library.read_resource(path,AEM.MAX_BYTES))
	if decoded.is_empty():reject(reader.error);return null
	var image: Image=visuals.load_image(texture_path)
	if image==null:reject(visuals.error);return null
	var model:=Model.new();model.build(decoded,image,null,int(state.visuals.sun_render_type))
	model.scale=Vector3.ONE*float(state.visuals.sun_scale)
	model.set_meta("source_resource_id",int(state.visuals.sun_mesh_id));model.set_meta("source_texture_id",int(state.sun_texture_id))
	return model

func select_station(station_id: int) -> void:
	if not _active or _navigation==null:return
	var state: Dictionary=_navigation.snapshot()
	if state.confirmation_visible:return
	if int(state.selected_station_id)==station_id:request_confirmation();return
	if not _navigation.select_station(station_id):set_error(_navigation.error);return
	error=""
	_present()

func request_confirmation() -> void:
	if not _active or _navigation==null:return
	if not _navigation.request_confirmation():set_error(_navigation.error);return
	error=""
	_present()

func confirm_destination() -> void:
	if not _active or _navigation==null or _navigation.destination()<0:return
	destination_requested.emit(_navigation.destination())

func back() -> void:
	if not _active or _navigation==null:return
	if _navigation.snapshot().confirmation_visible:
		_navigation.cancel_confirmation();error="";_present()
	else:close_requested.emit()

func request_system(system_id: int) -> void:
	if not _active or _navigation==null:return
	var state: Dictionary=_navigation.snapshot()
	if state.confirmation_visible or state.system_id==system_id:return
	if state.system_choices.any(func(row):return row.system_id==system_id):system_requested.emit(system_id)

func move_system(direction: int) -> void:
	if _navigation==null:return
	var state: Dictionary=_navigation.snapshot();var ids: Array=state.system_choices.map(func(row):return row.system_id)
	if ids.size()>1:request_system(ids[posmod(ids.find(state.system_id)+direction,ids.size())])

func handle_event(event: InputEvent) -> bool:
	if not visible:return false
	if not _active:return true
	var action:=""
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int=event.physical_keycode if event.physical_keycode else event.keycode
		if key in [KEY_ESCAPE,KEY_M]:action="back"
		elif key in [KEY_ENTER,KEY_KP_ENTER]:action="confirm"
		elif key in [KEY_Q,KEY_E]:action="system_previous" if key==KEY_Q else "system_next"
		elif key in [KEY_LEFT,KEY_UP,KEY_A,KEY_W]:action="previous"
		elif key in [KEY_RIGHT,KEY_DOWN,KEY_D,KEY_S,KEY_TAB]:action="next"
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index in [JOY_BUTTON_B,JOY_BUTTON_LEFT_SHOULDER]:action="back"
		elif event.button_index==JOY_BUTTON_A:action="confirm"
		elif event.button_index==JOY_BUTTON_RIGHT_SHOULDER:action="system_next"
		elif event.button_index in [JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_UP]:action="previous"
		elif event.button_index in [JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_DPAD_DOWN]:action="next"
	if action=="back":back()
	elif action in ["system_previous","system_next"]:move_system(-1 if action=="system_previous" else 1)
	elif action=="confirm":
		if _navigation.snapshot().confirmation_visible:confirm_destination()
		else:request_confirmation()
	elif not action.is_empty() and not _navigation.snapshot().confirmation_visible:
		_navigation.move_selection(-1 if action=="previous" else 1);_present()
	return true

func set_active(value: bool) -> void:
	var active:=value and visible
	if _active==active:return
	_active=active
	if _navigation!=null:_present()
	_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS if _active else SubViewport.UPDATE_ONCE if visible else SubViewport.UPDATE_DISABLED

func set_mobile_layout(value: bool) -> void:
	_mobile=value;_canvas.mobile=value;_relayout()
func snapshot() -> Dictionary:return {} if _navigation==null else _navigation.snapshot()
func set_error(message: String) -> void:error=message;_status.text=message;_notice.visible=true;_relayout()

func _present() -> void:
	var state: Dictionary=_navigation.snapshot();var confirming: bool=state.confirmation_visible
	_yes.visible=confirming;_no.visible=confirming;_target.visible=not confirming;_key.visible=not confirming
	_target.disabled=not _active or state.selected_station_id<0
	for item in [_back,_yes,_no,_key]:item.disabled=not _active
	for item in _systems.get_children():item.disabled=not _active or confirming or int(item.get_meta("system_id"))==int(state.system_id)
	_canvas.active=_active and not confirming;_canvas.selected_id=int(state.selected_station_id)
	_status.text=state.diagnostic if error.is_empty() else error
	if confirming and error.is_empty():
		_legend.visible=false
		for row in state.rows:
			if row.station_id==state.selected_station_id:_status.text=row.name+" · "+state.labels.question
	_notice.visible=not _status.text.is_empty()
	_canvas.queue_redraw();_relayout()

func _relayout() -> void:
	if not visible or _navigation==null:return
	var font_size:=20 if _mobile else 15
	var icon:=68.0 if _mobile else 44.0
	_faction_icon.position=Vector2(8,8);_faction_icon.size=Vector2.ONE*icon
	var top:=8.0
	for item in [_title,_faction,_security]:
		item.add_theme_font_size_override("font_size",font_size)
		item.position=Vector2(icon+16,top);top+=font_size+4
	var footer_height:=62.0 if _mobile else 44.0
	_footer.position=Vector2(0,size.y-footer_height);_footer.size=Vector2(size.x,footer_height)
	var button_height:=44.0 if _mobile else 30.0
	var button_width:=96.0 if _mobile else 112.0
	var button_y:=size.y-footer_height+(footer_height-button_height)/2
	var style: Dictionary=_styles[_mobile]
	_notice.add_theme_stylebox_override("panel",style.panel);_legend.add_theme_stylebox_override("panel",style.panel)
	for item in [_back,_target,_key,_no,_yes]:
		item.add_theme_font_size_override("font_size",18 if _mobile else 14)
		item.add_theme_stylebox_override("normal",style.back_normal if item==_back else style.normal)
		item.add_theme_stylebox_override("hover",style.back_pressed if item==_back else style.pressed)
		item.add_theme_stylebox_override("pressed",style.back_pressed if item==_back else style.pressed)
		item.add_theme_stylebox_override("disabled",style.back_normal if item==_back else style.normal)
		item.size=Vector2(button_width,button_height)
	for item in _systems.get_children():
		item.add_theme_font_size_override("font_size",18 if _mobile else 14)
		for mode in ["normal","disabled","focus"]:item.add_theme_stylebox_override(mode,style.normal)
		for mode in ["hover","pressed"]:item.add_theme_stylebox_override(mode,style.pressed)
		item.custom_minimum_size=Vector2(112,button_height)
	_systems.size=_systems.get_combined_minimum_size()
	_systems.position=Vector2(size.x-_systems.size.x-8,8)
	_back.position=Vector2(8,button_y)
	_key.position=Vector2(size.x-button_width-8,button_y);_yes.position=_key.position
	_target.position=Vector2(size.x-button_width*2-16,button_y);_no.position=_target.position
	var notice_width:=minf(600,size.x-24)
	_notice.size=Vector2(notice_width,90 if _mobile else 66)
	_notice.position=Vector2((size.x-notice_width)/2,size.y-footer_height-_notice.size.y-8)
	_status.position=Vector2(12,8);_status.size=_notice.size-Vector2(24,16)
	_status.add_theme_font_size_override("font_size",font_size)
	for row in _legend_rows.get_children():
		row.get_child(0).custom_minimum_size=Vector2.ONE*(24 if _mobile else 18)
		row.get_child(1).add_theme_font_size_override("font_size",font_size)
	_legend.size=_legend.get_combined_minimum_size()
	_legend.position=Vector2(size.x-_legend.size.x-8,size.y-footer_height-_legend.size.y-8)
	_project()

func _project() -> void:
	if _navigation==null or not is_instance_valid(_system) or _field.size.x<1 or _field.size.y<1:return
	var state: Dictionary=_navigation.snapshot()
	var angles: Array=state.visuals.parent_rotation
	# The source camera faces +Z after its Y-pi turn; Godot faces -Z.
	var rotation:=Basis(Vector3.UP,PI)*Basis.from_euler(Vector3(angles[0],angles[1],angles[2]),EULER_ORDER_XYZ)
	_system.basis=rotation.scaled(Vector3.ONE*float(state.visuals.parent_scale))
	var focal:=_field.size.y*0.5/tan(deg_to_rad(_camera.fov)*0.5)
	var half:=_field.size*0.5;var padding:=48.0 if _mobile else 62.0
	# Landscape phones retain the orbital plane and fit between the target-frame
	# margin and touch footer. Shift the camera to use that available height;
	# fixed desktop margins otherwise shrink the planets into the lower controls.
	var top_margin:=42.0 if _mobile else 100.0
	var bottom_margin:=_footer.size.y+62.0 if _mobile else 130.0
	var center_offset:=(top_margin-bottom_margin)*0.5 if _mobile else 0.0
	# The orbit quads include transparent corners far outside their visible art.
	# Desktop retains the source distance; phone framing scales with its height.
	var distance:=float(state.visuals.camera_distance)
	if _mobile:distance*=minf(1.0,_field.size.y/660.0)
	for local_point in _bounds_points:
		var point: Vector3=_system.transform*local_point
		distance=maxf(distance,point.z+1)
		distance=maxf(distance,point.z+absf(point.x)*focal/maxf(1,half.x-padding))
		var above:=half.y-top_margin;var below:=half.y-bottom_margin
		distance=maxf(distance,(point.y*focal+above*point.z)/maxf(1,above+center_offset))
		distance=maxf(distance,(-point.y*focal+below*point.z)/maxf(1,below-center_offset))
	_camera.position=Vector3(0,center_offset*distance/focal,distance)
	var projected:=[]
	for row in state.rows:
		var point: Vector3=_system.transform*row.position
		row.pixels=half+Vector2(point.x,_camera.position.y-point.y)*focal/(distance-point.z);projected.append(row)
	_canvas.rows=projected;_canvas.queue_redraw()

func clear() -> void:
	visible=false;_active=false;error="";_navigation=null;_system=null;_canvas.rows=[];_canvas.sprites={};_canvas.font=null
	_bounds_points.clear()
	for child in _world.get_children():
		if child!=_camera:child.free()
	for child in _legend_rows.get_children():child.free()
	# System selection can rebuild this row from one of its own press signals.
	# Detach immediately, then retire the emitting button after dispatch ends.
	for child in _systems.get_children():_systems.remove_child(child);child.queue_free()
	_systems.visible=false
	_legend.visible=false;_notice.visible=false;_sprites={};_styles={};_font=null
	_faction_icon.texture=null;_footer.texture=null
	_view.render_target_update_mode=SubViewport.UPDATE_DISABLED

func reject(message: String) -> bool:error=message;return false
