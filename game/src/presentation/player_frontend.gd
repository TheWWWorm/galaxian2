extends Control
## Player entry and paused-session ownership. Prepare replacements before commit.
signal exit_requested
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Preferences=preload("res://src/content/player_preferences.gd")
const DisplaySettings=preload("res://src/presentation/display_settings.gd")
const DmgImport=preload("res://src/content/dmg_import.gd")
const SaveFile=preload("res://src/simulation/station_save_file.gd")
const Menu=preload("res://src/presentation/main_menu_panel.gd")
const MenuAudio=preload("res://src/presentation/main_menu_audio.gd")
const Host=preload("res://src/presentation/opening_preview.gd")
const Streams=preload("res://src/presentation/audio_stream_control.gd")
const LANGUAGE_NAMES={"de":1,"gb":2,"es":3,"fr":4,"it":5,"ptl":14,"pl":7,"ru":8,"zt":10,"zs":11,"ko":12,"ja":13}
var error:=""
var phase:="setup"
var library: RefCounted
var bindings: RefCounted
var visuals: RefCounted
var game: Control
var menu: Control
var music: Node
var preferences:=Preferences.new()
var _display:=DisplaySettings.new()
var _preferences_path:=""
var _save_directory:=""
var _data_directory:=""
var _importer: Node
var _import_status: Label
var _mobile:=OS.has_feature("mobile")
var _details: PanelContainer
var _detail_title: Label
var _body: VBoxContainer
var _back: Button
var _notice: Label
var _picker: FileDialog
var _selection:={}
var _pending_action:=""
var _quit_after_import:=false
var _settings_controls:={}

func _ready() -> void:
	menu=Menu.new();add_child(menu);menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.action_requested.connect(request_action)
	_details=PanelContainer.new();add_child(_details)
	_details.minimum_size_changed.connect(func():_layout.call_deferred())
	var margins:=MarginContainer.new();_details.add_child(margins)
	for side in ["left","right","top","bottom"]:margins.add_theme_constant_override("margin_"+side,20)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",12);margins.add_child(column)
	_detail_title=Label.new();_detail_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(_detail_title)
	var scroll:=ScrollContainer.new();scroll.follow_focus=true;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;column.add_child(scroll)
	_body=VBoxContainer.new();_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_body.add_theme_constant_override("separation",10);scroll.add_child(_body)
	_notice=Label.new();_notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(_notice)
	_back=Button.new();_back.pressed.connect(show_menu);column.add_child(_back)
	_picker=FileDialog.new();_picker.access=FileDialog.ACCESS_FILESYSTEM;_picker.file_mode=FileDialog.FILE_MODE_OPEN_FILE
	_picker.file_selected.connect(_picked);add_child(_picker)
	_picker.filters=PackedStringArray(["*.dmg ; Galaxy on Fire 2 Full HD Mac disk image"])
	_importer=DmgImport.new();add_child(_importer)
	_importer.progress.connect(func(message):
		if phase=="import" and is_instance_valid(_import_status):_import_status.text=message)
	_importer.finished.connect(_import_finished)
	resized.connect(_layout);_layout()

func boot(args: PackedStringArray=PackedStringArray(),directory: String="user://") -> bool:
	_data_directory=ProjectSettings.globalize_path(directory)
	_preferences_path=directory.path_join("player.json");_save_directory=directory.path_join("saves")
	preferences.read_file(_preferences_path);var message:=preferences.error
	_selection=preferences.values.duplicate(true)
	apply_preferences()
	_display.apply(get_window(),preferences.values,_mobile)
	var image_index:=args.find("--dmg")
	if image_index>=0 and image_index+1<args.size():return begin_import(args[image_index+1])
	if not preferences.values.import_record.is_empty():
		if open_import(preferences.values.import_record):return true
		message=error
	show_setup();_notice.text=message;return false

func select_content(selection: Dictionary) -> bool:
	if has_session():return reject("Close the current game before changing its content")
	if not Preferences.valid(selection):return reject("Choose valid game folders and a supported language")
	var candidate_library:=Library.new();var candidate_bindings:=Bindings.new();var candidate_visuals:=Visuals.new()
	if not candidate_library.open(selection.content) or not candidate_bindings.open(selection.bindings,candidate_library.manifest) or not candidate_visuals.open(selection.visuals,candidate_library.manifest) or not candidate_library.select_language(selection.language):return reject(candidate_library.error+candidate_bindings.error+candidate_visuals.error)
	var candidate_music:=MenuAudio.new()
	if not candidate_music.configure(candidate_library,candidate_bindings):
		var message:=candidate_music.error;candidate_music.free();return reject(message)
	if not menu.configure(candidate_library,candidate_bindings,candidate_visuals):candidate_music.free();return reject(menu.error)
	if music!=null:music.free()
	music=candidate_music;add_child(music)
	if game!=null:game.free();game=null
	library=candidate_library;bindings=candidate_bindings;visuals=candidate_visuals
	preferences.values=selection.duplicate(true);_selection=selection.duplicate(true)
	apply_preferences();show_menu();_persist();return true

func open_import(receipt: String) -> bool:
	var record:=DmgImport.read_receipt(receipt)
	if record.is_empty():return reject("Select the Mac .dmg to prepare this game")
	var selection:=preferences.values.duplicate(true);selection.import_record=receipt
	for key in ["content","bindings","visuals"]:selection[key]=receipt.get_base_dir().path_join(record[key])
	return select_content(selection)

func apply_preferences() -> void:
	var values:=preferences.values
	Streams.set_levels(values.music,values.fx,values.voice)
	if game!=null:game.apply_preferences(values)

func set_mobile_layout(value: bool) -> void:
	_mobile=value;menu.set_mobile_layout(value)
	if game!=null:game.set_mobile_layout(value)
	_layout()

func has_save() -> bool:
	var path:=SaveFile.path_for(_save_directory,bindings)
	return not path.is_empty() and (FileAccess.file_exists(path) or FileAccess.file_exists(path+".bak"))

func has_session() -> bool:return game!=null and game.session!=null

func show_menu() -> void:
	_pending_action=""
	if library==null:show_setup();return
	if game!=null:game.hide()
	phase="menu";error="";_details.hide()
	music.set_active(true)
	menu.present(has_session() or has_save(),has_save());menu.set_mobile_layout(_mobile);menu.focus_first()

func request_action(action: String) -> void:
	if phase!="menu":return
	match action:
		"new_game":
			if has_session() or has_save():_confirm(action,library.strings[51])
			else:_enter_game(action)
		"load":
			if not has_save():return
			if has_session():_confirm(action,library.strings[50])
			else:_enter_game(action)
		"resume":
			if has_session():_resume()
			elif has_save():_enter_game("load")
		"options":show_options()
		"language":show_languages()
		"info":show_info()
		"exit":
			request_close()

func request_close() -> void:
	if _importer.busy():
		_quit_after_import=true;_importer.cancel()
		if is_instance_valid(_import_status):_import_status.text="Cancelling import before closing…"
		return
	if has_session():
		show_menu();_confirm("exit","Exit the game? Progress since the last station save will be lost.")
	else:exit_requested.emit()

func _confirm(action: String,message: String) -> void:
	_pending_action=action;_show_details("confirm",library.strings[28 if action=="new_game" else 29 if action=="load" else 33])
	_label(message)
	if action=="new_game":_label("Difficulty: "+library.strings[508]+". Other difficulty levels are not available yet.")
	_button("Continue",confirm_pending)

func confirm_pending() -> void:
	if phase!="confirm" or _pending_action.is_empty():return
	var action:=_pending_action;_pending_action=""
	if action=="exit":exit_requested.emit()
	else:_enter_game(action)

func _enter_game(action: String) -> bool:
	if library==null or action not in ["new_game","load"]:return false
	music.set_active(false)
	var candidate:=Host.new();add_child(candidate);candidate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	candidate.set_context(library,bindings,visuals);candidate.set_player_mode(true)
	candidate.set_mobile_layout(_mobile);candidate.apply_preferences(preferences.values);candidate.enable_saves(_save_directory)
	var accepted:=false
	if action=="new_game":
		candidate.start();accepted=candidate.session!=null and candidate.session.status=="running"
	else:accepted=candidate.load_station()
	if not accepted:
		var message: String=candidate._save_notice.text if action=="load" else candidate.status.text
		candidate.free();show_menu();return reject(message)
	# The existing paused game and every save survive preparation failure.
	if game!=null:game.free()
	game=candidate;game.menu_requested.connect(show_menu);game.game_over_requested.connect(show_menu)
	_resume();return true

func _resume() -> void:
	if not has_session():return
	phase="game";error="";menu.hide();_details.hide();game.show()
	music.set_active(false)
	game.apply_preferences(preferences.values);game.set_user_paused(false);game.clear_input()
	var focused:=get_viewport().gui_get_focus_owner()
	if focused!=null:focused.release_focus()

func show_setup() -> void:
	_show_details("setup","Galaxy on Fire 2 Full HD")
	_label("Select your Mac disk image (.dmg) to play. The game prepares the original content locally the first time, then remembers it for future launches.")
	_label("Original game content is not included with the remake.")
	_button("Choose Mac .dmg…",func():_picker.popup_centered_ratio(0.8))
	_back.visible=library!=null

func _picked(path: String) -> void:
	if phase=="setup":begin_import(path)

func begin_import(path: String) -> bool:
	if has_session() or _importer.busy():return false
	_show_details("import","Preparing Galaxy on Fire 2 Full HD")
	_import_status=_label("Reading your Mac disk image…")
	var progress:=ProgressBar.new();progress.indeterminate=true;progress.show_percentage=false;_body.add_child(progress)
	_button("Cancel import",func():_importer.cancel());_back.hide()
	if not _importer.start(path,_data_directory):show_setup();return reject(_importer.error)
	return true

func _import_finished(success: bool,receipt: String,message: String) -> void:
	if _quit_after_import:exit_requested.emit();return
	if success and open_import(receipt):return
	if success:message=error
	show_setup();reject(message)

func show_options() -> void:
	_show_details("options",library.strings[31]);_settings_controls={}
	var scale_labels: Array=[]
	for value in Preferences.UI_SCALES:scale_labels.append("Automatic (match resolution)" if value==0 else "%d%%"%value)
	_choice("ui_scale","UI scale",Preferences.UI_SCALES,scale_labels)
	if not _mobile:
		_choice("window_mode","Display mode",["windowed","fullscreen"],["Windowed","Fullscreen (native resolution)"])
		var native:=DisplaySettings.native_size(get_window())
		var resolution_labels: Array=[]
		for value in Preferences.RESOLUTIONS:resolution_labels.append("Native (%d × %d)"%[native.x,native.y] if value=="native" else value.replace("x"," × "))
		_choice("resolution","Window resolution",Preferences.RESOLUTIONS,resolution_labels)
		_settings_controls.resolution.disabled=preferences.values.window_mode=="fullscreen"
		_choice("aspect_ratio","Aspect ratio",Preferences.ASPECTS,["Automatic (match window)","Native display","4:3","16:9","16:10","21:9","32:9"])
	_choice("frame_rate","Frame rate",Preferences.FRAME_RATES,["Display refresh (V-Sync)","Unlimited (V-Sync off)","30 FPS","60 FPS","90 FPS","120 FPS","144 FPS","165 FPS","240 FPS","360 FPS"])
	for pair in [["music",34],["fx",35],["voice",36]]:
		_label(library.strings[pair[1]])
		var slider:=HSlider.new();slider.min_value=0;slider.max_value=1;slider.step=0.05;slider.value=preferences.values[pair[0]];slider.custom_minimum_size.y=44 if _mobile else 30
		slider.value_changed.connect(func(value):change_preference(pair[0],value));_body.add_child(slider);_settings_controls[pair[0]]=slider
	for pair in [["invert_pitch",library.strings[489]],["touch_controls","Touch controls"],["mouse_steering","Mouse steering"]]:
		if pair[0]=="mouse_steering" and _mobile:continue
		var toggle:=CheckButton.new();toggle.text=pair[1];toggle.button_pressed=preferences.values[pair[0]];toggle.custom_minimum_size.y=44 if _mobile else 30
		toggle.toggled.connect(func(value):change_preference(pair[0],value));_body.add_child(toggle);_settings_controls[pair[0]]=toggle
	if not _mobile:
		_label("Mouse sensitivity")
		var slider:=HSlider.new();slider.min_value=0.1;slider.max_value=3.0;slider.step=0.1;slider.value=preferences.values.mouse_sensitivity;slider.custom_minimum_size.y=30
		slider.value_changed.connect(func(value):change_preference("mouse_sensitivity",value));_body.add_child(slider);_settings_controls.mouse_sensitivity=slider
	_label("Mouse / WASD / arrows: steer · Left click / Space: fire\nEsc / controller Start: menu · M: navigation\nF5: save station · F9: load station\nMouse steering releases the cursor in menus and maps.")

func _choice(key: String,title: String,values: Array,labels: Array) -> void:
	_label(title)
	var choice:=OptionButton.new();choice.custom_minimum_size.y=44 if _mobile else 30
	for i in values.size():choice.add_item(labels[i])
	choice.select(values.find(int(preferences.values[key]) if key in ["frame_rate","ui_scale"] else preferences.values[key]))
	choice.item_selected.connect(func(index):change_preference(key,values[index]))
	_body.add_child(choice);_settings_controls[key]=choice

func change_preference(key: String,value: Variant) -> bool:
	if key not in ["music","fx","voice","invert_pitch","touch_controls","mouse_steering","mouse_sensitivity"]+Preferences.DISPLAY_KEYS:return false
	var candidate:=preferences.values.duplicate(true);candidate[key]=value
	if not Preferences.valid(candidate):return reject("Invalid game preference")
	if not preferences.save_file(_preferences_path,candidate):return reject(preferences.error)
	if key in Preferences.DISPLAY_KEYS:
		_display.apply(get_window(),candidate,_mobile)
		if is_instance_valid(_settings_controls.get("resolution")):_settings_controls.resolution.disabled=candidate.window_mode=="fullscreen"
		if is_instance_valid(_settings_controls.get("window_mode")):_settings_controls.window_mode.select(1 if candidate.window_mode=="fullscreen" else 0)
	else:apply_preferences()
	return true

func show_languages() -> void:
	_show_details("language",library.strings[0])
	if has_session():_label("The current game keeps its dialogue language until the next new game or load.")
	for code in Preferences.LANGUAGES:
		if not library.manifest.languages.has(code):continue
		var button:=_button(library.strings[LANGUAGE_NAMES[code]],func():change_language(code))
		button.disabled=library.active_language==code

func change_language(code: String) -> bool:
	var candidate:=Library.new()
	if not candidate.open(library.root) or not candidate.select_language(code):return reject(candidate.error)
	if not menu.configure(candidate,bindings,visuals):return reject(menu.error)
	library=candidate;preferences.values.language=code;_selection.language=code
	show_languages();return _persist()

func show_info() -> void:
	_show_details("info",library.strings[43])
	_label("Galaxy on Fire 2 Remake\nAn independent native engine using your locally imported game content.")
	_label("The opening through free travel, supported jumpgate routes, shopping and courier/passenger contracts are playable. Station saves retain acknowledged opening and free-play progress. The remaining campaign and expansions are unfinished.")
	_label("The animated menu background and additional difficulty levels remain unfinished. Saving during flight or conversations and original game save files are not supported yet.")
	_label("Engine: Apache-2.0. Original game content remains the property of its respective owners.")
	var button:=_button("Choose another Mac .dmg…",show_setup);button.disabled=has_session()
	button.tooltip_text="The source game can be changed before starting or loading a game"

func _show_details(next: String,title: String) -> void:
	phase=next;menu.hide();_details.show();_detail_title.text=title;_notice.text="";error=""
	for child in _body.get_children():_body.remove_child(child);child.queue_free()
	_back.visible=true;_back.text=library.strings[178] if library!=null else "Back"
	if menu._ui!=null:
		_details.theme=menu.theme;_details.add_theme_stylebox_override("panel",menu._ui.styles[_mobile].panel)
		menu._ui.apply_button(_back,_mobile,true)
	_layout.call_deferred();_back.grab_focus()

func _label(text: String) -> Label:
	var label:=Label.new();label.text=text;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",18 if _mobile else 14);_body.add_child(label);return label

func _button(text: String,callback: Callable) -> Button:
	var button:=Button.new();button.text=text;button.pressed.connect(callback);_body.add_child(button)
	if menu._ui!=null:menu._ui.apply_button(button,_mobile)
	else:button.custom_minimum_size.y=44 if _mobile else 30
	return button

func _layout() -> void:
	if _details==null or size.x<64 or size.y<64:return
	_details.size=Vector2(minf(600,size.x-32),minf(620,size.y-32));_details.position=(size-_details.size)*0.5
	_detail_title.add_theme_font_size_override("font_size",24 if _mobile else 20)
	_notice.add_theme_font_size_override("font_size",18 if _mobile else 14)

func _input(event: InputEvent) -> void:
	if not _mobile and event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode if event.physical_keycode else event.keycode)==KEY_F11:
		change_preference("window_mode","windowed" if preferences.values.window_mode=="fullscreen" else "fullscreen")
		get_viewport().set_input_as_handled();return
	# Own the menu shortcut before SubViewportContainer forwards the same event
	# into the flight viewport. Map Escape still belongs to its navigation panel.
	if phase!="game" or not has_session() or not game._focused or not is_visible_in_tree():return
	var escape: bool=event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode if event.physical_keycode else event.keycode)==KEY_ESCAPE
	var start: bool=event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_START
	if not escape and not start:return
	if escape and (game.session.status in ["gate_confirmation_required","gate_map_required"] or (game.session.has_method("map_open") and game.session.map_open())):return
	get_viewport().set_input_as_handled()
	show_menu()

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or phase=="game":return
	var pressed_key: bool=event is InputEventKey and event.pressed and not event.echo
	var back_key: bool=pressed_key and (event.physical_keycode if event.physical_keycode else event.keycode)==KEY_ESCAPE
	var back_button: bool=event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_B,JOY_BUTTON_START]
	if back_key or back_button:
		if phase=="import":_importer.cancel()
		elif phase=="menu" and has_session():_resume()
		elif phase!="setup":show_menu()
		get_viewport().set_input_as_handled()

func _persist() -> bool:
	if preferences.save_file(_preferences_path,preferences.values):return true
	return reject(preferences.error)

func reject(message: String) -> bool:
	error=message
	if phase=="menu":menu.show_error(message)
	else:_notice.text=message
	return false
