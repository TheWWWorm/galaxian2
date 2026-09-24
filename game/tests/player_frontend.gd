extends SceneTree
## Real entry, paused opening and saved-station restart. Saves are earned inputs.
const Frontend=preload("res://src/presentation/player_frontend.gd")
const Preferences=preload("res://src/content/player_preferences.gd")
const SaveFile=preload("res://src/simulation/station_save_file.gd")
const Archive=preload("res://src/simulation/station_archive.gd")
const Catalogue=preload("res://src/content/catalogues.gd")
const Streams=preload("res://src/presentation/audio_stream_control.gd")
const PathGuard=preload("res://tests/fixtures/free_play_station_scenario.gd")
var checks:=0
var failures:=0
var app: Control
var captures:=""
var directory:=""
var args: PackedStringArray

func _initialize() -> void:call_deferred("run")

func run() -> void:
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,720)
	args=OS.get_cmdline_user_args();directory=OS.get_environment("GOF2_MENU_TEST_DIRECTORY")
	if args.size() not in [3,4] or directory.is_empty() or not PathGuard.private_path(directory+"/player.json"):
		check(false,"Expected content paths and a private menu test directory");quit(1);return
	captures=args[3] if args.size()==4 else OS.get_environment("GOF2_CAPTURE_DIR")
	if not captures.is_empty():
		if not PathGuard.private_path(captures+"/image.png"):check(false,"Keep captures outside source");quit(1);return
		DirAccess.make_dir_recursive_absolute(captures)
	app=Frontend.new();root.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if OS.get_environment("GOF2_MENU_TEST_PHASE")=="setup":await verify_setup()
	elif OS.get_environment("GOF2_MENU_TEST_PHASE")=="resume":await verify_restart()
	elif OS.get_environment("GOF2_MENU_TEST_PHASE")=="cancel":await verify_cancel()
	elif OS.get_environment("GOF2_MENU_TEST_PHASE")=="close_import":await verify_close_import()
	else:await verify_prepare()
	app.free();Streams.set_levels(1,1,1);await process_frame
	print("Player entry: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify_setup() -> void:
	check(not app.boot(PackedStringArray(),directory) and app.phase=="setup","Fresh entry must request original Mac content")
	check(app._picker.file_mode==FileDialog.FILE_MODE_OPEN_ANY,"One picker must accept files and app directories")
	check(app._picker.file_selected.is_connected(app._picked) and app._picker.dir_selected.is_connected(app._picked),"Both container choices must share the import entry")
	await capture("entry-mac-game-setup")
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(Rect2(app._details.position,app._details.size)),"Import setup escaped the desktop viewport")
	app._picker.dir_selected.emit(directory)
	check(app.phase=="setup" and not app._importer.busy() and not app.error.is_empty(),"Invalid folder must retain setup and report a useful error")
	check(app.preferences.values.import_record.is_empty(),"Rejected folder activated an installation")

func verify_prepare() -> void:
	check(not FileAccess.file_exists(directory.path_join("player.json")),"Use a new directory for each entry test pair")
	check(not app.boot(PackedStringArray(),directory) and app.phase=="setup","Fresh entry did not ask for imported content")
	await capture("entry-setup")
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(Rect2(app._details.position,app._details.size)),"First setup escaped its viewport")
	var expected_ids:=[args[0].get_file(),args[1].get_file(),args[2].get_file()]
	var selection:=Preferences.defaults();selection.content=args[0];selection.bindings=args[1];selection.visuals=args[2]
	var original:=original_source()
	if not original.is_empty():
		pick_source(original)
		check(app.phase=="import" and app._importer.busy(),"Selecting the Mac game did not start its background import")
		await capture("entry-import-progress")
		var deadline:=Time.get_ticks_msec()+780000
		while app._importer.busy() and Time.get_ticks_msec()<deadline:await process_frame
		if app.phase!="menu":check(false,app.error+app._importer.error);return
		selection=app.preferences.values.duplicate(true)
		args[0]=selection.content;args[1]=selection.bindings;args[2]=selection.visuals
		check(not selection.import_record.is_empty(),"The completed Mac import was not remembered")
		var receipt: Dictionary=Frontend.DmgImport.read_receipt(selection.import_record)
		check(not receipt.is_empty() and selection.import_record.begins_with(directory.path_join("imports")+"/") and [receipt.get("base_content_id"),receipt.get("binding_id"),receipt.get("visual_id")]==expected_ids,"The picked Mac game did not prepare the explicit content, binding and visual identities in its own import store")
	elif not app.select_content(selection):check(false,app.error);return
	dismiss_title()
	check(app.phase=="menu" and not app.menu._buttons.resume.visible and app.menu._buttons.load.disabled,"Fresh content created unearned progress")
	check(app.music.player.playing,"The menu omitted its original music")
	await capture("entry-menu-desktop")
	var failed:=selection.duplicate();failed.visuals=directory.path_join("missing")
	var identity: Dictionary=app.menu.snapshot().identity
	check(not app.select_content(failed) and app.menu.snapshot().identity==identity,"Failed content selection discarded accepted menu resources")
	var prefs:=Preferences.new();check(prefs.read_file(directory.path_join("player.json")) and prefs.values.visuals==args[2],"Failed content selection overwrote saved paths")
	app.show_menu();app.menu._buttons.new_game.pressed.emit()
	if app._needs_import_update():
		check(app.phase=="update" and not app.has_session(),"An older import must disclose missing effects before a new game")
		for control in app._body.get_children():
			if control is Button and control.text=="Use current game files":control.pressed.emit();break
	if not app.has_session():check(false,app.error);return
	check(app.phase=="game" and app.game.session.status=="running" and app.game._preview_controls.all(func(control):return not control.visible),"New game did not enter the native opening with player controls")
	check(not app.game._pause_button.visible and not app.game._menu_button.visible,"Desktop flight exposed hidden touch actions")
	check(not app.music.player.playing,"Menu music overlapped the new game's music")
	app.game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	await capture("entry-new-game")
	var key:=InputEventKey.new();key.physical_keycode=KEY_ESCAPE;key.pressed=true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	await process_frame
	var release:=InputEventKey.new();release.physical_keycode=KEY_ESCAPE
	Input.parse_input_event(release);Input.flush_buffered_events()
	check(app.phase=="menu" and not app.game.visible and app.game.session.is_paused(),"Escape did not freeze the live game and open its menu")
	check(app.music.player.playing,"Returning to the menu did not restart menu music")
	var session: Node=app.game.session;var frozen: Dictionary=session.snapshot()
	for i in 3:await process_frame
	check(session.snapshot()==frozen,"The paused menu consumed simulation time")
	app.menu._buttons.new_game.pressed.emit();check(app.phase=="confirm" and app.game.session==session,"New game discarded a live session without its confirmation")
	app._back.pressed.emit();check(app.phase=="menu" and app.game.session==session,"Cancelling new game lost the live session")
	# Trigger an actual failed opening preparation while the prior game is paused.
	var visuals: RefCounted=app.visuals;app.visuals=Frontend.Visuals.new()
	app.request_action("new_game");app.confirm_pending()
	check(app.phase=="menu" and app.game.session==session and not app.error.is_empty(),"Failed new-game preparation destroyed the existing session")
	app.visuals=visuals
	app.menu._buttons.options.pressed.emit()
	app._settings_controls.fx.value=0.35;app._settings_controls.voice.value=0;app._settings_controls.invert_pitch.button_pressed=true;app._settings_controls.touch_controls.button_pressed=true
	check(app.game._controls.invert_pitch and app.game._controls.touch_controls,"Preferences did not reach the existing flight controls")
	var voice_bus:=AudioServer.get_bus_index(Streams.BUSES.Voice);var fx_bus:=AudioServer.get_bus_index(Streams.BUSES.FX)
	check(AudioServer.is_bus_mute(voice_bus) and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(fx_bus)),.35),"Sound preferences did not control their independent buses")
	var voice:=Streams.player(AudioStreamWAV.new(),false,"Voice");var effect:=Streams.player(AudioStreamWAV.new(),true)
	check(voice.bus==Streams.BUSES.Voice and effect.bus==Streams.BUSES.FX,"Native streams bypassed their sound category");voice.free();effect.free()
	await capture("entry-options-desktop")
	root.size=Vector2i(960,540);app.set_mobile_layout(true);app.show_options();await capture("entry-options-landscape")
	check(app._settings_controls.values().all(func(control):return control.size.y>=44),"Landscape preferences lost their touch target height")
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(Rect2(app._details.position,app._details.size)),"Landscape options escaped the viewport")
	app.show_menu();app.menu._buttons.resume.pressed.emit()
	check(app.phase=="game" and app.game.session==session and not app.game._user_paused,"Resume replaced the current game or retained its user pause")
	var start:=InputEventJoypadButton.new();start.button_index=JOY_BUTTON_START;start.pressed=true
	Input.parse_input_event(start);Input.flush_buffered_events()
	check(app.phase=="menu" and app.game.session.is_paused(),"Controller Start did not open the menu through normal input routing")
	var release_start:=InputEventJoypadButton.new();release_start.button_index=JOY_BUTTON_START
	Input.parse_input_event(release_start);Input.flush_buffered_events()
	app.request_action("resume")
	app.show_menu();app.request_action("language");check(app.change_language("pl") and app.library.active_language=="pl" and app.game.library.active_language=="gb","Menu language damaged the active game's resource context")
	await capture("entry-language-landscape")
	check(app.change_language("gb"),app.error)
	app.show_menu();await capture("entry-menu-landscape")
	var source_save:=OS.get_environment("GOF2_MENU_SOURCE_SAVE")
	if source_save.is_empty() or not PathGuard.private_path(source_save):check(false,"Supply the accepted saved-station file from the real gameplay test");return
	var cat:=Catalogue.new();var file:=SaveFile.new();cat.open(app.library)
	var document:=file.load_document(source_save,app.bindings,cat,app.library)
	if document.is_empty():check(false,file.error);return
	var path:=SaveFile.path_for(directory.path_join("saves"),app.bindings)
	check(DirAccess.make_dir_recursive_absolute(path.get_base_dir())==OK and DirAccess.copy_absolute(source_save,path)==OK,"Could not preserve the earned save for the restart test")
	check(file.read_document(path)==document,"The restart input changed its earned career")
	check(not app.change_preference("fx",2) and preferences_unchanged(),"Invalid preferences overwrote accepted settings")
	# Loading from the menu asks before replacing an existing game.
	app.show_menu();app.menu._buttons.load.pressed.emit();check(app.phase=="confirm","Load discarded the active game without confirmation")
	app._back.pressed.emit();check(app.game.session==session,"Cancelled load replaced the paused opening")
	var old:=FileAccess.get_file_as_bytes(path)
	app.visuals=Frontend.Visuals.new();app.request_action("load");app.confirm_pending();app.visuals=visuals
	check(app.phase=="menu" and app.game.session==session and FileAccess.get_file_as_bytes(path)==old,"Failed menu load lost the live opening or changed its save")
	await verify_map_input(document)

func verify_map_input(document: Dictionary) -> void:
	if failures:return
	app.request_action("load");app.confirm_pending()
	if app.phase!="game":check(false,app.error);return
	check(Archive.new().capture(app.game.session.station_owner(),app.bindings)==document,"Map input must retain the exact earned station and career")
	app.game.set_process(false);app.game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	var now:=Time.get_ticks_usec()
	if not app.game.request_departure() or not app.game.enter_first_flight(now,4096,1789100000):check(false,app.game.status.text);return
	app.game.session.rebase_time(now)
	for tick in 71:
		now+=100000
		if not app.game.session.step(now):check(false,app.game.session.error);return
	app.game.present_session()
	app.game.set_mobile_layout(false);app.game.refresh_render_mode()
	check(app.game._mouse_captured,"Controllable desktop flight did not capture mouse steering")
	for code in [KEY_A,KEY_D]:
		var steer:=InputEventKey.new();steer.physical_keycode=code;steer.pressed=true
		Input.parse_input_event(steer);Input.flush_buffered_events()
		check(app.game._controls.snapshot().command==Vector2.ZERO and app.game._controls.snapshot().strafe==(-1.0 if code==KEY_A else 1.0),"A/D must strafe without steering the ship")
		var released:=InputEventKey.new();released.physical_keycode=code
		Input.parse_input_event(released);Input.flush_buffered_events()
	var motion:=InputEventMouseMotion.new();motion.screen_relative=Vector2(10,0)
	Input.parse_input_event(motion);Input.flush_buffered_events();app.game._controls.advance_mouse(1.0/60.0)
	check(app.game._controls.snapshot().command.y<0,"Mouse look was swallowed by the flight viewport")
	app.game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not app.game._mouse_captured and app.game._controls.snapshot().command==Vector2.ZERO,"Focus loss kept the cursor or steering")
	app.game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	if not app.game.open_map(now):check(false,app.game.status.text);return
	check(not app.game._mouse_captured,"Navigation retained mouse capture")
	var escape:=InputEventKey.new();escape.physical_keycode=KEY_ESCAPE;escape.pressed=true
	Input.parse_input_event(escape);Input.flush_buffered_events()
	check(app.phase=="game" and not app.game.session.map_open(),"Map Escape opened the main menu or failed to close navigation")
	check(app.game._mouse_captured,"Closing navigation did not restore mouse steering")
	var release:=InputEventKey.new();release.physical_keycode=KEY_ESCAPE
	Input.parse_input_event(release);Input.flush_buffered_events()
	check(app.game.open_map(),"Navigation did not reopen after keyboard closure")
	var start:=InputEventJoypadButton.new();start.button_index=JOY_BUTTON_START;start.pressed=true
	Input.parse_input_event(start);Input.flush_buffered_events()
	check(app.phase=="menu" and app.game.session.map_open() and app.game.session.is_paused(),"Controller Start did not preserve and pause the open map")
	check(not app.game._mouse_captured,"Returning to the menu retained the cursor")

func preferences_unchanged() -> bool:
	var prefs:=Preferences.new();return prefs.read_file(directory.path_join("player.json")) and is_equal_approx(prefs.values.fx,0.35)

func dismiss_title() -> void:
	var event:=InputEventKey.new();event.physical_keycode=KEY_ENTER;event.pressed=true
	app.menu._unhandled_input(event)
	check(not app.menu._title_active,"The title did not accept its opening input")

func verify_restart() -> void:
	if not app.boot(PackedStringArray(),directory):check(false,app.error);return
	dismiss_title()
	check(app.phase=="menu" and app.library.root==app.preferences.values.content and app.menu._buttons.resume.visible and not app.menu._buttons.load.disabled,"Restart did not restore content selection and saved-game actions")
	check(app.preferences.values.invert_pitch and app.preferences.values.touch_controls and is_equal_approx(app.preferences.values.fx,.35),"Restart forgot control or sound preferences")
	var file:=SaveFile.new();var path:=SaveFile.path_for(directory.path_join("saves"),app.bindings);var document:=file.read_document(path)
	app.menu._buttons.resume.pressed.emit()
	if not app.has_session():check(false,app.error);return
	app.game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(app.phase=="game" and Archive.new().capture(app.game.session.station_owner(),app.bindings)==document,"Fresh-process Resume changed the earned saved career")
	check(app.game._controls.invert_pitch and app.game._controls.touch_controls,"Loaded game omitted saved controls")
	await capture("entry-resumed-station")
	app.game._menu_button.pressed.emit();check(app.phase=="menu" and app.game.session.is_paused(),"Station Menu did not pause the loaded career")
	var session: Node=app.game.session
	app.menu._buttons.resume.pressed.emit();check(app.game.session==session,"In-process Resume loaded a replacement instead of resuming")
	var exit_count:=[0];app.exit_requested.connect(func():exit_count[0]+=1)
	app.request_close()
	check(app.phase=="confirm" and app.game.session==session and session.is_paused() and exit_count[0]==0,"Window close bypassed the saved-progress confirmation")
	app._back.pressed.emit();app.request_action("resume")
	check(app.phase=="game" and app.game.session==session and not app.game._mouse_captured,"Cancelling station close lost the game or captured the pointer")
	var fullscreen:=InputEventKey.new();fullscreen.physical_keycode=KEY_F11;fullscreen.pressed=true
	Input.parse_input_event(fullscreen);Input.flush_buffered_events()
	check(app.preferences.values.window_mode=="fullscreen" and app.phase=="game","Fullscreen shortcut did not preserve the active game")
	var release_fullscreen:=InputEventKey.new();release_fullscreen.physical_keycode=KEY_F11
	Input.parse_input_event(release_fullscreen);Input.flush_buffered_events()
	app.change_preference("window_mode","windowed")
	app.show_menu();app.request_action("exit");check(app.phase=="confirm" and exit_count[0]==0,"Exit discarded the game before confirmation")
	app.confirm_pending();check(exit_count[0]==1 and FileAccess.get_file_as_bytes(path)==file.encode(document),"Exit changed the career or failed to reach the application")

func verify_cancel() -> void:
	if not app.boot(PackedStringArray(),directory):check(false,app.error);return
	dismiss_title()
	var original:=original_source()
	if original.is_empty():check(false,"Supply the same Mac game for the cancellation check");return
	var stored:=FileAccess.get_file_as_bytes(directory.path_join("player.json"))
	var identity: Dictionary=app.menu.snapshot().identity
	app.show_setup();pick_source(original)
	check(app._importer.busy() and app.phase=="import","Mac picker did not start a cancellable import")
	app._importer.cancel()
	var deadline:=Time.get_ticks_msec()+30000
	while app._importer.busy() and Time.get_ticks_msec()<deadline:await process_frame
	check(app.phase=="setup" and not app._importer.busy() and app.error.contains("cancelled") and FileAccess.get_file_as_bytes(directory.path_join("player.json"))==stored,"Cancelling the Mac import changed the accepted content selection")
	await capture("entry-import-cancelled")
	app.show_menu();check(app.menu.snapshot().identity==identity and app.has_save(),"Cancellation lost the accepted game or saved career")
	app.show_setup();pick_source(original)
	deadline=Time.get_ticks_msec()+60000
	while app._importer.busy() and Time.get_ticks_msec()<deadline:await process_frame
	check(app.phase=="menu" and app.menu.snapshot().identity==identity and FileAccess.get_file_as_bytes(directory.path_join("player.json"))==stored,"Reusing a completed Mac import changed its content identity or preferences")
	app.show_setup();app._picker.dir_selected.emit(directory)
	check(app.phase=="setup" and not app.error.is_empty() and not app._importer.busy(),"Player setup accepted a folder without the Mac app structure")
	root.size=Vector2i(960,540);app.set_mobile_layout(true);app.show_options()
	await process_frame;app._settings_controls.touch_controls.grab_focus();await process_frame;await process_frame
	var scroll: ScrollContainer=app._body.get_parent()
	check(scroll.get_global_rect().encloses(app._settings_controls.touch_controls.get_global_rect()),"Controller focus did not reveal the last landscape option")
	await capture("entry-options-landscape-focused")

func verify_close_import() -> void:
	if not app.boot(PackedStringArray(),directory):check(false,app.error);return
	var original:=original_source()
	if original.is_empty():check(false,"Supply the Mac game for import close");return
	var stored:=FileAccess.get_file_as_bytes(directory.path_join("player.json"))
	var exited:=[0];app.exit_requested.connect(func():exited[0]+=1)
	app.show_setup();pick_source(original)
	check(app._importer.busy(),"Import close requires a running importer")
	app.request_close()
	check(exited[0]==0 and app._quit_after_import,"Window close did not wait for import cancellation")
	var deadline:=Time.get_ticks_msec()+30000
	while app._importer.busy() and Time.get_ticks_msec()<deadline:await process_frame
	check(not app._importer.busy() and exited[0]==1,"Import close failed to finish cancellation and exit")
	check(FileAccess.get_file_as_bytes(directory.path_join("player.json"))==stored,"Closing import lost the previously accepted game")

func original_source() -> String:
	var original:=OS.get_environment("GOF2_MENU_TEST_SOURCE")
	return original if not original.is_empty() else OS.get_environment("GOF2_MENU_TEST_DMG")

func pick_source(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):app._picker.dir_selected.emit(path)
	else:app._picker.file_selected.emit(path)

func capture(label: String) -> void:
	if captures.is_empty() or DisplayServer.get_name()=="headless":return
	await process_frame;RenderingServer.force_draw(false);await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(captures.path_join(label+".png"))==OK,"Could not save entry capture")
	if app.game!=null:app.game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
