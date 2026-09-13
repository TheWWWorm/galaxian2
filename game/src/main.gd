extends Control
const Library = preload("res://src/content/library.gd")
const VisualLibrary = preload("res://src/content/visual_library.gd")
const Inspector = preload("res://src/presentation/asset_inspector.gd")
const WorldBrowser = preload("res://src/presentation/world_browser.gd")
const ResourceBindings = preload("res://src/content/resource_bindings.gd")
const OpeningPreview = preload("res://src/presentation/opening_preview.gd")
const RadioPreview = preload("res://src/presentation/radio_preview.gd")
var library := Library.new()
var visuals := VisualLibrary.new()
var status: Label
var languages: OptionButton
var search: LineEdit
var records: RichTextLabel
var picker: FileDialog
var visual_picker: FileDialog
var inspector: Control
var tabs: TabContainer
var world_browser: Control
var bindings := ResourceBindings.new()
var bindings_picker: FileDialog
var radio_preview: Control
var opening_preview: Control

func _ready() -> void:
	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + edge, 20)
	add_child(outer)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	outer.add_child(column)
	var title := Label.new()
	title.text = "GALAXY ON FIRE 2  /  REMAKE"
	title.add_theme_font_size_override("font_size", 26)
	column.add_child(title)
	var row := HBoxContainer.new()
	column.add_child(row)
	var button := Button.new()
	button.text = "Open imported content…"
	button.pressed.connect(func(): picker.popup_centered_ratio(0.8))
	row.add_child(button)
	var visual_button := Button.new()
	visual_button.text = "Open prepared textures…"
	visual_button.pressed.connect(func(): visual_picker.popup_centered_ratio(0.8))
	row.add_child(visual_button)
	var bindings_button := Button.new()
	bindings_button.text = "Open resource bindings…"
	bindings_button.pressed.connect(func(): bindings_picker.popup_centered_ratio(0.8))
	row.add_child(bindings_button)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "Import an iOS IPA or Mac app with tools/import_content.py, then open its manifest.json."
	column.add_child(status)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	inspector = Inspector.new()
	inspector.name = "Assets"
	tabs.add_child(inspector)
	world_browser = WorldBrowser.new()
	world_browser.name = "World"
	tabs.add_child(world_browser)
	world_browser.hangar_requested.connect(func(id):
		tabs.current_tab = 0
		inspector.show_hangar(str(id)))
	var text_tab := VBoxContainer.new()
	text_tab.name = "Localization"
	tabs.add_child(text_tab)
	languages = OptionButton.new()
	languages.disabled = true
	languages.item_selected.connect(_language_selected)
	text_tab.add_child(languages)
	search = LineEdit.new()
	search.placeholder_text = "Search source localization…"
	search.text_changed.connect(func(_text): _show_records())
	text_tab.add_child(search)
	records = RichTextLabel.new()
	records.size_flags_vertical = Control.SIZE_EXPAND_FILL
	records.selection_enabled = true
	records.bbcode_enabled = false
	text_tab.add_child(records)
	radio_preview = RadioPreview.new()
	radio_preview.name = "Radio"
	tabs.add_child(radio_preview)
	opening_preview=OpeningPreview.new()
	opening_preview.name="Opening"
	tabs.add_child(opening_preview)
	var note := Label.new()
	note.text = "Native engine in development · Opening flight and primary combat available with current bindings · Full campaigns remain unfinished"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.6, 0.67, 0.75)
	column.add_child(note)
	picker = FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.filters = PackedStringArray(["manifest.json ; Imported content manifest"])
	picker.file_selected.connect(func(path): _open_content(path.get_base_dir()))
	add_child(picker)
	visual_picker = FileDialog.new()
	visual_picker.access = FileDialog.ACCESS_FILESYSTEM
	visual_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	visual_picker.filters = PackedStringArray(["visuals.json ; Prepared texture manifest"])
	visual_picker.file_selected.connect(func(path): _open_visuals(path.get_base_dir()))
	add_child(visual_picker)
	bindings_picker = FileDialog.new()
	bindings_picker.access = FileDialog.ACCESS_FILESYSTEM
	bindings_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	bindings_picker.filters = PackedStringArray(["bindings.json ; Prepared resource bindings"])
	bindings_picker.file_selected.connect(func(path): _open_bindings(path.get_base_dir()))
	add_child(bindings_picker)
	var args := OS.get_cmdline_user_args()
	for option in ["--content", "--bindings", "--visuals", "--asset", "--resource-id", "--station-id", "--ship-id"]:
		var i := args.find(option)
		if i >= 0 and i + 1 < args.size():
			match option:
				"--content": _open_content(args[i + 1])
				"--visuals": _open_visuals(args[i + 1])
				"--asset": inspector.show_resource(args[i + 1])
				"--bindings": _open_bindings(args[i + 1])
				"--resource-id": inspector.show_id(args[i + 1])
				"--ship-id": inspector.show_ship(args[i + 1])
				"--station-id": inspector.show_hangar(args[i + 1])
	if "--radio-preview" in args:
		tabs.current_tab = radio_preview.get_index()
		radio_preview.start()

	if "--opening-preview" in args:
		tabs.current_tab=opening_preview.get_index()
		opening_preview.start()

func _open_content(directory: String) -> void:
	languages.clear()
	languages.disabled = true
	records.text = ""
	visuals = VisualLibrary.new()
	bindings = ResourceBindings.new()
	radio_preview.set_context(library, bindings, visuals)
	opening_preview.set_context(library,bindings,visuals)
	inspector.bindings = bindings
	if not library.open(directory):
		status.text = library.error
		inspector.set_context(library, visuals)
		world_browser.set_context(library)
		return
	status.text = "%s · source version %s · base %s" % [library.manifest.profile.edition,
		library.manifest.profile.get("bundle_version", "unknown"), str(library.manifest.content_id).left(16)]
	inspector.set_context(library, visuals)
	world_browser.set_context(library)
	var codes: Array = library.manifest.languages.keys()
	codes.sort()
	for code in codes:
		languages.add_item(code)
	languages.disabled = false
	var index: int = maxi(0, codes.find("gb"))
	languages.select(index)
	_language_selected(index)

func _open_bindings(directory: String) -> void:
	radio_preview.reset()
	opening_preview.reset()
	if not bindings.open(directory, library.manifest):
		status.text = bindings.error
		inspector.refresh_current()
		return
	status.text = "%s · %d recovered resource IDs · bindings %s" % [library.manifest.profile.edition,
		bindings.records.size(), bindings.binding_id.left(16)]
	inspector.refresh_current()

func _open_visuals(directory: String) -> void:
	radio_preview.reset()
	opening_preview.reset()
	if library.manifest.is_empty():
		status.text = "Open a base content manifest before its prepared textures."
		return
	if not visuals.open(directory, library.manifest):
		status.text = visuals.error
		inspector.refresh_current()
		return
	status.text = "%s · %d prepared textures · base %s" % [library.manifest.profile.edition,
		visuals.textures.size(), str(library.manifest.content_id).left(16)]
	inspector.refresh_current()

func _language_selected(index: int) -> void:
	radio_preview.reset()
	opening_preview.reset()
	if not library.select_language(languages.get_item_text(index)):
		records.text = library.error
		return
	inspector.refresh_ship_labels()
	_show_records()

func _show_records() -> void:
	var query := search.text.to_lower()
	var shown := 0
	var output := PackedStringArray()
	for i in library.strings.size():
		var text: String = library.strings[i]
		if query.is_empty() or text.to_lower().contains(query):
			output.append("%04d  %s" % [i, text])
			shown += 1
			if shown >= 150:
				output.append("\nShowing the first 150 matches. Refine the search to see more.")
				break
	records.text = "\n\n".join(output)
