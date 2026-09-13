extends HBoxContainer
const AEM = preload("res://src/content/aem.gd")
const Model = preload("res://src/presentation/imported_model.gd")
const Tracks = preload("res://src/content/animation_tracks.gd")
const MaterialLibrary = preload("res://src/presentation/material_library.gd")
const Hangar = preload("res://src/presentation/hangar_geometry.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
var catalogues := Catalogues.new()
var current_station := -1
var hangar_ship_id := 0
var frame_ship_button: Button
var ship_stats_view: RichTextLabel
var displayed_ship_id := -1
var library: RefCounted
var visuals: RefCounted
var bindings: RefCounted
var paths: Array = []
var filtered: Array = []
var list: ItemList
var filter: LineEdit
var info: Label
var viewport: SubViewport
var canvas: SubViewportContainer
var image_view: TextureRect
var camera: Camera3D
var model: Node3D
var timeline: HSlider
var time_label: Label
var current_path := ""
var center := Vector3.ZERO
var distance := 1000.0
var yaw := 0.65
var pitch := 0.35
var texture_quality := "high"
var quality_picker: OptionButton

func _ready() -> void:
	add_theme_constant_override("separation", 16)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 310
	add_child(sidebar)
	filter = LineEdit.new()
	filter.placeholder_text = "Filter mesh or texture filenames…"
	filter.text_changed.connect(func(_text): refresh_list())
	sidebar.add_child(filter)
	var resource_id := LineEdit.new()
	resource_id.placeholder_text = "Resource ID (press Enter)"
	resource_id.text_submitted.connect(show_id)
	sidebar.add_child(resource_id)
	var ship_id := LineEdit.new()
	ship_id.placeholder_text = "Ship catalogue ID (press Enter)"
	ship_id.text_submitted.connect(show_ship)
	sidebar.add_child(ship_id)
	var station_id := LineEdit.new()
	station_id.placeholder_text = "Station ID — hangar (press Enter)"
	station_id.text_submitted.connect(show_hangar)
	sidebar.add_child(station_id)
	quality_picker = OptionButton.new()
	quality_picker.add_item("High-resolution textures")
	quality_picker.add_item("Low-resolution textures")
	quality_picker.tooltip_text = "Choose verified resolution variants from this Mac content profile."
	quality_picker.hide()
	quality_picker.item_selected.connect(func(index):
		texture_quality = "high" if index == 0 else "low"
		if not current_path.is_empty() or current_station >= 0:
			var source_time := timeline.value
			var view_distance := distance
			refresh_current()
			timeline.value = source_time
			distance = view_distance
			update_camera())
	sidebar.add_child(quality_picker)
	ship_stats_view = RichTextLabel.new()
	ship_stats_view.custom_minimum_size.y = 220
	ship_stats_view.selection_enabled = true
	ship_stats_view.tooltip_text = "Original base properties before equipment, upgrades or market pricing."
	ship_stats_view.hide()
	sidebar.add_child(ship_stats_view)
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_selected.connect(func(index): show_resource(filtered[index]))
	sidebar.add_child(list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "Select an original mesh or texture. Drag to orbit; scroll to zoom."
	right.add_child(info)
	var space := Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(space)
	canvas = SubViewportContainer.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.stretch = true
	canvas.gui_input.connect(orbit_input)
	space.add_child(canvas)
	viewport = SubViewport.new()
	viewport.size = Vector2i(640, 420)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	canvas.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.035, 0.05, 0.075)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.68, 0.76, 0.9)
	environment.environment.ambient_light_energy = 0.6
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 1.4
	viewport.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(20, 140, 0)
	fill.light_color = Color(0.5, 0.68, 1)
	fill.light_energy = 0.65
	viewport.add_child(fill)
	camera = Camera3D.new()
	camera.current = true
	viewport.add_child(camera)
	image_view = TextureRect.new()
	image_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	space.add_child(image_view)
	image_view.hide()
	var row := HBoxContainer.new()
	right.add_child(row)
	var frame_button := Button.new()
	frame_button.text = "Frame pose"
	frame_button.pressed.connect(frame_pose)
	row.add_child(frame_button)
	frame_ship_button = Button.new()
	frame_ship_button.text = "Frame hull"
	frame_ship_button.pressed.connect(frame_hangar_ship)
	frame_ship_button.hide()
	row.add_child(frame_ship_button)
	time_label = Label.new()
	time_label.text = "Source time: 0"
	time_label.custom_minimum_size.x = 165
	row.add_child(time_label)
	timeline = HSlider.new()
	timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline.step = 0.01
	timeline.editable = false
	timeline.value_changed.connect(func(value):
		time_label.text = "Source time: %.2f" % value
		if is_instance_valid(model): model.set_source_time(value))
	row.add_child(timeline)
	var note := Label.new()
	note.text = "Asset inspection · Prepared bindings supply source materials · Animation clock, lighting and scene composition remain unverified"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.55, 0.68, 0.8)
	right.add_child(note)

func set_context(base: RefCounted, pack: RefCounted) -> void:
	library = base
	visuals = pack
	quality_picker.visible = library.manifest.get("profile", {}).get("edition") == "mac-full-hd"
	paths = []
	current_path = ""
	current_station = -1
	hangar_ship_id = 0
	clear_view()
	for path in library.manifest.get("files", {}):
		if path.ends_with(".aem") or path.ends_with(".aei"):
			paths.append(path)
	paths.sort()
	refresh_list()

func refresh_list() -> void:
	filtered = []
	list.clear()
	for path in paths:
		if filter.text.is_empty() or str(path).to_lower().contains(filter.text.to_lower()):
			filtered.append(path)
			list.add_item(str(path).get_file())
			list.set_item_tooltip(list.item_count - 1, path)

func clear_view() -> void:
	displayed_ship_id = -1
	ship_stats_view.hide()
	if is_instance_valid(model):
		model.free()
	model = null
	image_view.texture = null
	image_view.hide()
	canvas.show()
	timeline.editable = false
	timeline.set_value_no_signal(0.0)
	time_label.text = "Source time: 0"
	frame_ship_button.hide()

func show_resource(path: String) -> void:
	clear_view()
	current_station = -1
	current_path = path
	info.text = path.trim_prefix("resources/")
	var selected_index := filtered.find(path)
	if selected_index >= 0:
		list.select(selected_index)
		list.call_deferred("ensure_current_is_visible")
	if library == null or library.manifest.is_empty():
		info.text = "Open imported content before selecting an asset."
		return
	if path.ends_with(".aei"):
		var image: Image = visuals.load_image(path)
		if image == null:
			info.text += "\n" + visuals.error + ". Open its prepared visuals.json to inspect pixels."
			return
		image_view.texture = ImageTexture.create_from_image(image)
		image_view.show()
		canvas.hide()
		info.text += "\n%d × %d · %d stored mip levels" % [image.get_width(), image.get_height(), image.get_mipmap_count() + 1]
		return
	var bytes: PackedByteArray = library.read_resource(path, AEM.MAX_BYTES)
	if bytes.is_empty():
		info.text += "\n" + library.error
		return
	var reader := AEM.new()
	var decoded := reader.decode(bytes)
	if decoded.is_empty():
		info.text += "\nUnsupported asset: " + reader.error
		return
	var diffuse_path := companion(path, "_diffuse.aei")
	var normal_path := companion(path, "_normal_specular.aei")
	var render_type := 28
	var material_note := "Provisional filename-matched material"
	if bindings != null and not bindings.records.is_empty():
		diffuse_path = ""
		normal_path = ""
		var descriptor: Dictionary = bindings.material_for_mesh(path, texture_quality)
		if descriptor.is_empty():
			material_note = bindings.error
		else:
			material_note = "Source material %d · render type %d" % [descriptor.id, descriptor.render_type]
			if quality_picker.visible:
				material_note += " · " + texture_quality + " texture preference"
			if MaterialLibrary.supports(descriptor):
				render_type = int(descriptor.render_type)
				diffuse_path = descriptor.texture_paths[0]
				normal_path = descriptor.texture_paths[1] if render_type == 28 else ""
			else:
				material_note += " · rendering not implemented"
	var diffuse: Image = visuals.load_image(diffuse_path) if not diffuse_path.is_empty() else null
	if not diffuse_path.is_empty() and diffuse == null:
		material_note += " · diffuse unavailable: " + visuals.error
	var normal: Image = visuals.load_image(normal_path) if not normal_path.is_empty() else null
	if not normal_path.is_empty() and normal == null:
		material_note += " · normal/specular unavailable: " + visuals.error
	info.text += "\n" + material_note
	model = Model.new()
	viewport.add_child(model)
	model.build(decoded, diffuse, normal, render_type)
	var bounds: AABB = model.transform * model.source_bounds
	center = bounds.get_center()
	distance = maxf(1.0, bounds.size.length() * 0.85)
	camera.near = maxf(0.01, distance / 1000.0)
	camera.far = maxf(100.0, distance * 100.0)
	update_camera()
	info.text += "\nV%d · %d submeshes · %d vertices · %d keys · %s" % [decoded.version,
		decoded.surfaces.size(), decoded.vertices, decoded.keyframes,
		"diffuse + normal/specular" if diffuse and normal else ("diffuse" if diffuse else "untextured")]
	var extent := Tracks.range_of(decoded.surfaces)
	timeline.min_value = extent.x
	timeline.max_value = maxf(extent.x, extent.y)
	timeline.editable = extent.x < extent.y
	timeline.value = clampf(0.0, extent.x, extent.y)
	model.set_source_time(timeline.value)

func refresh_current() -> void:
	if current_station >= 0:
		show_hangar(str(current_station))
	elif not current_path.is_empty():
		show_resource(current_path)

func show_hangar(text: String) -> void:
	clear_view()
	current_path = ""
	current_station = -1
	if not text.is_valid_int() or int(text) < 0:
		info.text = "Enter a non-negative station catalogue ID."
		return
	current_station = int(text)
	if library == null or library.manifest.is_empty() or bindings == null:
		info.text = "Open imported content and its prepared resource bindings."
		return
	if not catalogues.open(library):
		info.text = catalogues.error
		return
	var selected: Dictionary = bindings.resolve_hangar(current_station, catalogues)
	if selected.is_empty():
		info.text = bindings.error
		return
	if not bindings.ship_placement.is_empty():
		var ship: Dictionary = bindings.resolve_hangar_ship(hangar_ship_id)
		if ship.is_empty():
			info.text = "Hangar hull unavailable: " + bindings.error
			return
		selected.ship = ship
	var hangar := Hangar.new()
	viewport.add_child(hangar)
	if not hangar.build(selected, library, visuals, bindings, texture_quality):
		info.text = "Hangar unavailable: " + hangar.error
		hangar.free()
		return
	model = hangar
	var bounds: AABB = model.source_bounds
	center = bounds.get_center()
	distance = maxf(1.0, bounds.size.length() * 0.85)
	camera.near = maxf(0.01, distance / 1000.0)
	camera.far = maxf(100.0, distance * 100.0)
	update_camera()
	var extent := Tracks.range_of(model.surfaces)
	timeline.min_value = extent.x
	timeline.max_value = maxf(extent.x, extent.y)
	timeline.editable = extent.x < extent.y
	timeline.value = clampf(0.0, extent.x, extent.y)
	model.set_source_time(timeline.value)
	info.text = "%s · %s · Source hangar row %d\n%d root layers · %d model instances · %s texture preference\nGeometry preview · Original camera, lighting and animation unverified" % [
		catalogues.tables.stations[current_station].name, catalogues.tables.systems[selected.system_id].name,
		selected.row, selected.layers.size(), model.models.size(), texture_quality]
	if is_instance_valid(hangar.ship_model):
		info.text += "\nHull %d · Source Y %.0f · Full ship assembly pending" % [hangar_ship_id, hangar.ship_model.position.y]
		if selected.ship.get("light_bindings_available", false):
			info.text += " · Light layers: %d" % hangar.ship_light_models.size()
		frame_ship_button.show()
		show_ship_stats(hangar_ship_id)
		frame_hangar_ship()
	else:
		info.text += "\nHangar hull placement is unavailable in this binding pack."

func frame_hangar_ship() -> void:
	if not is_instance_valid(model) or not model is Hangar or not is_instance_valid(model.ship_model):
		return
	var bounds := AABB()
	var first := true
	for instance in model.ship_instances:
		var posed: AABB = instance.global_transform * instance.mesh.get_aabb()
		bounds = posed if first else bounds.merge(posed)
		first = false
	center = bounds.get_center()
	distance = maxf(1.0, bounds.size.length() * 1.3)
	camera.near = maxf(0.01, distance / 1000.0)
	camera.far = maxf(distance * 100.0, model.source_bounds.size.length() * 2.0)
	update_camera()

func companion(mesh_path: String, suffix: String) -> String:
	# Exact basename/expansion matching is an inspection aid, not game registration.
	var basename := mesh_path.get_file().get_basename()
	var candidates: Array[String] = []
	var parts := mesh_path.split("/")
	var expansion := parts[3] if parts.size() > 4 and parts[2] == "assets" else ""
	for path in visuals.textures:
		if str(path).get_file() != basename + suffix:
			continue
		if not expansion.is_empty() and not str(path).contains("/assets/" + expansion + "/"):
			continue
		candidates.append(path)
	candidates.sort()
	for path in candidates:
		if path.contains("/" + texture_quality + "/"):
			return path
	return candidates[0] if not candidates.is_empty() else ""

func orbit_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		yaw -= event.relative.x * 0.01
		pitch = clampf(pitch + event.relative.y * 0.01, -1.45, 1.45)
		update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(camera.near * 5, distance * 0.88)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(camera.far * 0.5, distance / 0.88)
		update_camera()

func update_camera() -> void:
	camera.position = center + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(center)

func frame_pose() -> void:
	if not is_instance_valid(model):
		return
	var first := true
	var bounds := AABB()
	for instance in model.instances:
		var posed: AABB = instance.global_transform * instance.mesh.get_aabb()
		bounds = posed if first else bounds.merge(posed)
		first = false
	center = bounds.get_center()
	distance = maxf(1.0, bounds.size.length() * 0.85)
	update_camera()

func show_id(text: String) -> void:
	if bindings == null or bindings.records.is_empty():
		info.text = "Open prepared resource bindings before using numeric IDs."
		return
	if not text.is_valid_int() or int(text) < 0 or int(text) > 65535:
		info.text = "Enter a resource ID between 0 and 65535."
		return
	var path: String = bindings.resolve(int(text))
	if path.is_empty():
		info.text = bindings.error
		return
	filter.text = ""
	refresh_list()
	show_resource(path)
	info.text += "\nRecorded resource ID %d · Scene usage and active selection unverified" % int(text)


func show_ship(text: String) -> void:
	if not text.is_valid_int():
		info.text = "Enter a ship catalogue ID."
		return
	if not show_ship_stats(int(text)):
		info.text = catalogues.error
		return
	if bindings == null or bindings.ship_model_resources.is_empty():
		info.text = "Ship properties loaded. Open prepared bindings to inspect its geometry."
		return
	if current_station >= 0:
		hangar_ship_id = int(text)
		show_hangar(str(current_station))
		return
	var path: String = bindings.resolve_ship_model(int(text))
	if path.is_empty():
		info.text = bindings.error
		return
	filter.text = ""
	refresh_list()
	show_resource(path)
	show_ship_stats(int(text))
	info.text += "\nShip catalogue ID %d → resource %d · Active scene registration unverified" % [int(text), bindings.ship_model_resources[int(text)]]


func show_ship_stats(ship_id: int) -> bool:
	displayed_ship_id = -1
	ship_stats_view.hide()
	if library == null:
		catalogues.error = "Open imported content before its ship properties."
		return false
	if not catalogues.open(library):
		return false
	var stats := catalogues.ship_stats(ship_id)
	if stats.is_empty():
		return false
	var labels := catalogues.ship_stat_labels(library)
	# Source properties remain usable without a language pack selected.
	if labels.is_empty():
		labels.assign(["Armor", "Cargo hold", "Price", "Primary weapons",
			"Secondary weapons", "Turrets", "Equipment", "Handling"])
	var lines := PackedStringArray(["Ship %d · Base properties" % ship_id])
	for i in Catalogues.SHIP_PROPERTIES.size():
		var key: String = Catalogues.SHIP_PROPERTIES[i]
		var value := str(catalogues.tables.ships[ship_id].fields[8]) if key == "handling_factor" else str(stats[key])
		lines.append("%s: %s" % [labels[i], value])
	ship_stats_view.text = "\n".join(lines)
	displayed_ship_id = ship_id
	ship_stats_view.show()
	return true


func refresh_ship_labels() -> void:
	if displayed_ship_id >= 0:
		show_ship_stats(displayed_ship_id)
