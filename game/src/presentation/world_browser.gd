extends VBoxContainer
## Inspection of source world relationships, independent of campaign availability.
const Catalogues = preload("res://src/content/catalogues.gd")
signal hangar_requested(station_id: int)
var catalogues := Catalogues.new()
var status: Label
var search: LineEdit
var systems: ItemList
var heading: Label
var stations: ItemList
var links: HFlowContainer
var current_system := -1


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "Open imported content to inspect its systems and stations."
	add_child(status)
	search = LineEdit.new()
	search.placeholder_text = "Find a system or station…"
	search.text_changed.connect(func(_text): _filter())
	add_child(search)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(row)
	systems = ItemList.new()
	systems.custom_minimum_size.x = 240
	systems.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	systems.size_flags_stretch_ratio = 0.4
	systems.item_selected.connect(func(index): select_system(systems.get_item_metadata(index)))
	row.add_child(systems)
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 10)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(detail)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 24)
	detail.add_child(heading)
	var station_label := Label.new()
	station_label.text = "Stations"
	detail.add_child(station_label)
	stations = ItemList.new()
	stations.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stations.allow_reselect = true
	stations.tooltip_text = "Double-click a station to inspect its source-selected hangar geometry."
	stations.item_activated.connect(func(index): hangar_requested.emit(int(stations.get_item_metadata(index))))
	detail.add_child(stations)
	var link_label := Label.new()
	link_label.text = "Linked systems"
	detail.add_child(link_label)
	links = HFlowContainer.new()
	detail.add_child(links)
	var note := Label.new()
	note.text = "Source catalogue inspection · Campaign locks and travel requirements are not yet implemented."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.6, 0.67, 0.75)
	add_child(note)


func set_context(library: RefCounted) -> void:
	current_system = -1
	search.text = ""
	heading.text = ""
	stations.clear()
	_clear_links()
	if not catalogues.open(library):
		status.text = catalogues.error
		_filter()
		return
	status.text = "%d systems · %d stations · %d ship records · %d item records" % [
		catalogues.tables.systems.size(), catalogues.tables.stations.size(),
		catalogues.tables.ships.size(), catalogues.tables.items.size()]
	_filter()
	select_system(0)


func _filter() -> void:
	systems.clear()
	if catalogues.tables.is_empty():
		return
	var query := search.text.to_lower()
	for system in catalogues.tables.systems:
		var matched: bool = query.is_empty() or system.name.to_lower().contains(query)
		for station_id in system.station_ids:
			if catalogues.tables.stations[station_id].name.to_lower().contains(query):
				matched = true
		if not matched:
			continue
		var index := systems.add_item(system.name)
		systems.set_item_metadata(index, system.id)
		if system.id == current_system:
			systems.select(index)


func select_system(id: int) -> void:
	if catalogues.tables.is_empty() or id < 0 or id >= catalogues.tables.systems.size():
		return
	current_system = id
	var system: Dictionary = catalogues.tables.systems[id]
	heading.text = system.name
	stations.clear()
	for station_id in system.station_ids:
		var station: Dictionary = catalogues.tables.stations[station_id]
		var index := stations.add_item(station.name)
		stations.set_item_metadata(index, station.id)
	_clear_links()
	if system.linked_system_ids.is_empty():
		var empty := Label.new()
		empty.text = "No links listed in the source catalogue."
		links.add_child(empty)
	for target in system.linked_system_ids:
		var button := Button.new()
		button.text = catalogues.tables.systems[target].name
		button.pressed.connect(func():
			search.text = ""
			select_system(target))
		links.add_child(button)
	_filter()
	systems.call_deferred("ensure_current_is_visible")


func _clear_links() -> void:
	for child in links.get_children():
		links.remove_child(child)
		child.queue_free()
