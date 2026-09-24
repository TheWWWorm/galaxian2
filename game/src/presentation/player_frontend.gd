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
const PauseControls=preload("res://src/presentation/pause_controls_panel.gd")
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
var _pause_controls: PanelContainer
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
var _settings_art:={}

func _ready() -> void:
	menu=Menu.new();add_child(menu);menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.action_requested.connect(request_action)
	_pause_controls=PauseControls.new();add_child(_pause_controls)
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
	_picker=FileDialog.new();_picker.access=FileDialog.ACCESS_FILESYSTEM;_picker.file_mode=FileDialog.FILE_MODE_OPEN_ANY
	_picker.file_selected.connect(_picked);_picker.dir_selected.connect(_picked);add_child(_picker)
	_picker.filters=PackedStringArray(["*.dmg,*.app ; Galaxy on Fire 2 Full HD Mac game"])
	if OS.get_name()=="Android":
		_picker.use_native_dialog=true;_picker.file_mode=FileDialog.FILE_MODE_OPEN_FILE
		_picker.filters=PackedStringArray(["*.dmg,*.zip ; Galaxy on Fire 2 Full HD Mac disk image or application ZIP"])
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
	if image_index<0:image_index=args.find("--app")
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
	if record.is_empty():return reject("Select the Mac .dmg or .app to prepare this game")
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
	if _pause_controls.visible:_show_pause_controls()
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
	if has_session():_show_pause_controls()
	else:_pause_controls.hide()

func _show_pause_controls() -> void:
	if not has_session() or game.session.status not in ["running","gate_confirmation_required","gate_map_required"] or menu._ui==null:
		_pause_controls.hide();return
	_pause_controls.present(PauseControls.reference_rows(library.strings,preferences.values.mouse_steering),menu._ui,_mobile,library.strings[487])
	_pause_controls.layout_in_viewport(size,menu.snapshot().menu_rect.position.x)

func request_action(action: String) -> void:
	if phase!="menu":return
	match action:
		"new_game":
			if not has_session() and _needs_import_update():
				_show_details("update","Update game files")
				_label("These game files were prepared before engine exhaust and newer fixes were added. Select your Mac game again to prepare updated files for a new game.")
				_label("Existing saves remain available with their earlier import. You can select either import from the game files screen.")
				_button("Choose or update game files…",show_setup)
				_button("Use current game files",_start_new_game)
			else:_start_new_game()
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

func _needs_import_update() -> bool:
	return bindings!=null and library.manifest.get("profile",{}).get("edition")=="mac-full-hd" and (bindings.engine_particle_owners.is_empty() or not bindings.engine_particles.has("opening_ship"))

func _start_new_game() -> void:
	if has_session() or has_save():_confirm("new_game",library.strings[51])
	else:_enter_game("new_game")

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
	phase="game";error="";menu.hide();_pause_controls.hide();_details.hide();game.show()
	music.set_active(false)
	game.apply_preferences(preferences.values);game.set_user_paused(false);game.clear_input()
	var focused:=get_viewport().gui_get_focus_owner()
	if focused!=null:focused.release_focus()

func show_setup() -> void:
	_show_details("setup","Galaxy on Fire 2 Full HD")
	if OS.get_name()=="Android":
		_label("Select your Galaxy on Fire 2 Full HD Mac disk image (.dmg) or a ZIP containing its application (.app). The game prepares the original content on this device, then remembers it for future launches.")
	else:
		_label("Select your Mac disk image (.dmg) or application folder (.app). The game prepares the original content locally the first time, then remembers it for future launches.")
	_label("Original game content is not included with the remake.")
	_button("Choose Mac game…",func():_picker.popup_centered_ratio(0.8))
	for installation in _prepared_imports():
		var receipt: String=installation.path
		var record: Dictionary=installation.record
		var label: String=str(record.get("source_name","Mac game"))
		label+=" · updated files" if Bindings.reader_version(record.get("reader"))==Bindings.MAX_READER_VERSION else " · earlier files"
		var saved:=_save_directory.path_join(record.base_content_id).path_join(record.binding_id).path_join("station.gof2save")
		if FileAccess.file_exists(saved) or FileAccess.file_exists(saved+".bak"):label+=" · saved game"
		var button:=_button(label,func():open_import(receipt))
		button.tooltip_text=label;button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	_back.visible=library!=null

func _prepared_imports() -> Array:
	var result:=[]
	var directory:=_data_directory.path_join("imports")
	if not DirAccess.dir_exists_absolute(directory):return result
	for child in DirAccess.get_directories_at(directory):
		var path:=directory.path_join(child).path_join("installation.json")
		var record:=DmgImport.read_receipt(path)
		if not record.is_empty():result.append({"path":path,"record":record})
	result.sort_custom(func(a,b):return Bindings.reader_version(a.record.get("reader"))>Bindings.reader_version(b.record.get("reader")))
	return result

func _picked(path: String) -> void:
	if phase=="setup":begin_import(path)

func begin_import(path: String) -> bool:
	if has_session() or _importer.busy():return false
	_show_details("import","Preparing Galaxy on Fire 2 Full HD")
	_import_status=_label("Reading your Mac game…")
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
	_settings_art={}
	if menu._ui!=null:
		var atlas_resources: Dictionary=bindings.mido_travel.get("map",{}).get("ui",{}).get("atlas_resources",{})
		_settings_art=menu._ui.load_regions(library,bindings,visuals,[1303,1304,1305,1306],atlas_resources)
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
	_settings_heading(library.strings[490])
	for pair in [["music",34],["fx",35],["voice",36]]:
		var slider:=HSlider.new();slider.min_value=0;slider.max_value=1;slider.step=0.05;slider.value=preferences.values[pair[0]];slider.custom_minimum_size.y=44 if _mobile else 30
		_style_settings_slider(slider)
		slider.value_changed.connect(func(value):change_preference(pair[0],value));_setting_row(library.strings[pair[1]],slider);_settings_controls[pair[0]]=slider
	_settings_heading(library.strings[487])
	for pair in [["invert_pitch",library.strings[489]],["touch_controls","Touch controls"],["mouse_steering","Mouse steering"]]:
		if pair[0]=="mouse_steering" and _mobile:continue
		var toggle:=CheckButton.new();toggle.text=pair[1];toggle.button_pressed=preferences.values[pair[0]];toggle.custom_minimum_size.y=44 if _mobile else 30
		if menu._ui!=null:menu._ui.apply_button(toggle,_mobile)
		_style_settings_toggle(toggle)
		toggle.toggled.connect(func(value):change_preference(pair[0],value));_body.add_child(toggle);_settings_controls[pair[0]]=toggle
	if not _mobile:
		var slider:=HSlider.new();slider.min_value=0.1;slider.max_value=3.0;slider.step=0.1;slider.value=preferences.values.mouse_sensitivity;slider.custom_minimum_size.y=30
		_style_settings_slider(slider)
		slider.value_changed.connect(func(value):change_preference("mouse_sensitivity",value));_setting_row("Mouse sensitivity",slider);_settings_controls.mouse_sensitivity=slider
	_label("Arrows / mouse: turn · Left click / Space: fire\nP / Esc / controller Start: pause · Q: autopilot · E: actions\nM: mouse ship/menu · F5: save station · F9: load station")
	var files:=_button("Game files…",show_setup);files.disabled=has_session()
	files.tooltip_text="Choose or update imported game files before starting or loading a game"
	_body.get_parent().set_deferred("scroll_vertical",0)

func _settings_heading(text: String) -> void:
	var band:=PanelContainer.new();band.custom_minimum_size.y=40 if _mobile else 28
	if menu._ui!=null:
		var ui: Dictionary=bindings.mido_travel.map.ui
		var style:=StyleBoxTexture.new();style.texture=menu._ui.sprites[int(ui.footer_image_id)]
		style.content_margin_left=8;style.content_margin_right=8
		band.add_theme_stylebox_override("panel",style)
	var caption:=Label.new();caption.text=text;caption.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size",20 if _mobile else 14)
	band.add_child(caption);_body.add_child(band)

func _settings_icon(image_id: int) -> Texture2D:
	var texture: Texture2D=_settings_art.get(image_id)
	if texture==null:return null
	var image: Image=texture.get_image()
	if not _mobile:image.resize(maxi(1,roundi(image.get_width()*0.5)),maxi(1,roundi(image.get_height()*0.5)),Image.INTERPOLATE_LANCZOS)
	var result:=ImageTexture.create_from_image(image)
	result.set_meta("source_image_id",image_id)
	return result

func _style_settings_slider(slider: HSlider) -> void:
	if not _settings_art.has(1305):return
	var track:=StyleBoxTexture.new();track.texture=_settings_icon(1305)
	track.content_margin_top=11 if _mobile else 5.5
	track.content_margin_bottom=11 if _mobile else 5.5
	track.set_meta("source_image_id",1305)
	slider.add_theme_stylebox_override("slider",track)
	var empty:=StyleBoxEmpty.new()
	slider.add_theme_stylebox_override("grabber_area",empty)
	slider.add_theme_stylebox_override("grabber_area_highlight",empty)
	var thumb:=_settings_icon(1306)
	for state in ["grabber","grabber_highlight","grabber_disabled"]:slider.add_theme_icon_override(state,thumb)
	if menu._ui!=null:slider.add_theme_stylebox_override("focus",menu._ui.styles[_mobile].focus)

func _style_settings_toggle(toggle: CheckButton) -> void:
	if not _settings_art.has(1303):return
	var dim:=_settings_icon(1303);var amber:=_settings_icon(1304)
	for state in ["unchecked","unchecked_disabled"]:toggle.add_theme_icon_override(state,dim)
	for state in ["checked","checked_disabled"]:toggle.add_theme_icon_override(state,amber)

func _choice(key: String,title: String,values: Array,labels: Array) -> void:
	var choice:=OptionButton.new();choice.custom_minimum_size.y=44 if _mobile else 30
	for i in values.size():choice.add_item(labels[i])
	choice.select(values.find(int(preferences.values[key]) if key in ["frame_rate","ui_scale"] else preferences.values[key]))
	choice.item_selected.connect(func(index):change_preference(key,values[index]))
	if menu._ui!=null:
		menu._ui.apply_button(choice,_mobile)
		var popup:=choice.get_popup();var font_size:=20 if _mobile else 14
		# The source panel is translucent; an opaque popup prevents the settings
		# behind its list from showing through the original texture.
		popup.transparent=false;popup.transparent_bg=false
		popup.add_theme_stylebox_override("panel",menu._ui.styles[_mobile].panel)
		popup.add_theme_stylebox_override("hover",menu._ui.styles[_mobile].pressed)
		popup.add_theme_font_size_override("font_size",font_size)
		popup.add_theme_constant_override("v_separation",maxi((44 if _mobile else 30)-ceili(menu._ui.font.get_height(font_size)),0))
	_setting_row(title,choice);_settings_controls[key]=choice

func _setting_row(title: String,control: Control) -> void:
	var row:=VBoxContainer.new();row.add_theme_constant_override("separation",4);_body.add_child(row)
	var label:=Label.new();label.text=title;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",18 if _mobile else 14);row.add_child(label);row.add_child(control)
	# Follow the complete setting, including its caption, when navigating upward.
	# ScrollContainer's default follow_focus only reveals the slider/button itself.
	control.focus_entered.connect(func():
		var scroll: ScrollContainer=_body.get_parent()
		scroll.ensure_control_visible.call_deferred(row))

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
	_label("Additional difficulty levels remain unfinished. Saving during flight or conversations and original game save files are not supported yet.")
	_label("Engine: Apache-2.0. Original game content remains the property of its respective owners.")
	var button:=_button("Choose another Mac game…",show_setup);button.disabled=has_session()
	button.tooltip_text="The source game can be changed before starting or loading a game"

func _show_details(next: String,title: String) -> void:
	phase=next;menu.show_background_only();_pause_controls.hide();_details.show();_detail_title.text=title;_notice.text="";error=""
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
	if _pause_controls.visible:_pause_controls.layout_in_viewport(size,menu.snapshot().menu_rect.position.x)

func _input(event: InputEvent) -> void:
	if not _mobile and event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode if event.physical_keycode else event.keycode)==KEY_F11:
		change_preference("window_mode","windowed" if preferences.values.window_mode=="fullscreen" else "fullscreen")
		get_viewport().set_input_as_handled();return
	# Own the menu shortcut before SubViewportContainer forwards the same event
	# into the flight viewport. Map Escape still belongs to its navigation panel.
	if phase!="game" or not has_session() or not game._focused or not is_visible_in_tree():return
	var pause_key: bool=event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode if event.physical_keycode else event.keycode) in [KEY_ESCAPE,KEY_P]
	var escape: bool=pause_key and (event.physical_keycode if event.physical_keycode else event.keycode)==KEY_ESCAPE
	var start: bool=event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_START
	if not pause_key and not start:return
	if escape and (game._station_map_open or game.flight_menu.visible or game.session.status in ["gate_confirmation_required","gate_map_required"] or (game.session.has_method("map_open") and game.session.map_open())):return
	get_viewport().set_input_as_handled()
	show_menu()

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or phase=="game":return
	var pressed_key: bool=event is InputEventKey and event.pressed and not event.echo
	var back_key: bool=pressed_key and (event.physical_keycode if event.physical_keycode else event.keycode)==KEY_ESCAPE
	var resume_key: bool=pressed_key and phase=="menu" and has_session() and (event.physical_keycode if event.physical_keycode else event.keycode)==KEY_P
	var back_button: bool=event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_B,JOY_BUTTON_START]
	if back_key or back_button or resume_key:
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
