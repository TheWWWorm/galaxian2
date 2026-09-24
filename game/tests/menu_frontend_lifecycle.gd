extends SceneTree
## Fresh title through live opening, detail panels and retained menu state.
const Frontend=preload("res://src/presentation/player_frontend.gd")
const Preferences=preload("res://src/content/player_preferences.gd")
const PrivatePath=preload("res://tests/fixtures/free_play_station_scenario.gd")
var checks:=0
var failures:=0

func _initialize() -> void:call_deferred("run")

func run() -> void:
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,720)
	var args:=OS.get_cmdline_user_args();var directory:=OS.get_environment("GOF2_MENU_TEST_DIRECTORY")
	if args.size()!=3 or directory.is_empty() or not PrivatePath.private_path(directory.path_join("player.json")) or FileAccess.file_exists(directory.path_join("player.json")):
		check(false,"Use three source paths and a fresh private menu lifecycle directory");quit(1);return
	var app:=Frontend.new();root.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	check(not app.boot(PackedStringArray(),directory) and app.phase=="setup","Fresh entry did not request content")
	var selection:=Preferences.defaults();selection.content=args[0];selection.bindings=args[1];selection.visuals=args[2]
	if not app.select_content(selection):check(false,app.error);app.free();quit(1);return
	check(app.phase=="menu" and app.menu.snapshot().title_active and app.music.player.playing,"Content entry skipped the original title or menu music")
	check(not app._pause_controls.visible,"The first title exposed the paused flight reference")
	var background: SubViewport=app.menu._background
	var accepted: Dictionary=app.menu.snapshot()
	for frame in 26:app.menu.advance_title(150.0)
	check(app.menu._title_prompt.visible,"The complete title did not show its localized prompt")
	var enter:=InputEventKey.new();enter.physical_keycode=KEY_ENTER;enter.pressed=true
	Input.parse_input_event(enter);Input.flush_buffered_events();await process_frame
	check(not app.menu.snapshot().title_active and app.menu._scroll.visible,"Title input did not reveal menu actions")
	var release:=InputEventKey.new();release.physical_keycode=KEY_ENTER
	Input.parse_input_event(release);Input.flush_buffered_events()
	var failed:=selection.duplicate();failed.visuals=directory.path_join("missing-visuals")
	check(not app.select_content(failed) and app.menu._background==background and app.menu.snapshot().background==accepted.background and app.preferences.values.visuals==selection.visuals,"A failed content replacement discarded the title scene or accepted paths")
	app.music._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	app.menu._background._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(app.music.player.stream_paused and background.render_target_update_mode==SubViewport.UPDATE_DISABLED,"Focus loss left menu audio or rendering active")
	app.music._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	app.menu._background._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	app.menu._buttons.options.pressed.emit();await process_frame
	check(app.phase=="options" and app.menu.snapshot().background_only and background._active and app._details.visible,"Options did not retain the animated scene behind its panel")
	app.show_menu();app.menu._buttons.new_game.pressed.emit()
	if app.phase=="update":
		for control in app._body.get_children():
			if control is Button and control.text=="Use current game files":control.pressed.emit();break
	if not app.has_session():check(false,app.error);app.free();quit(1);return
	var session: Node=app.game.session
	check(app.phase=="game" and not app.menu.visible and not background._active and not app.music.player.playing,"New game retained the menu scene or music")
	var pause:=InputEventKey.new();pause.physical_keycode=KEY_P;pause.pressed=true
	Input.parse_input_event(pause);Input.flush_buffered_events();await process_frame
	var release_pause:=InputEventKey.new();release_pause.physical_keycode=KEY_P
	Input.parse_input_event(release_pause);Input.flush_buffered_events()
	check(app.phase=="menu" and app.game.session==session and app.game.session.is_paused() and background._active and app.music.player.playing,"Returning to the menu lost or advanced the live session")
	var reference: Dictionary=app._pause_controls.snapshot()
	check(reference.visible and reference.rows.any(func(row):return row.label=="Primary fire") and reference.rows.any(func(row):return row.label=="Pause menu"),"The paused session omitted usable flight controls")
	check(reference.rows.any(func(row):return row.label=="Action menu" and row.key=="E") and reference.rows.any(func(row):return row.label=="Autopilot" and row.key=="Q") and reference.rows.any(func(row):return row.label=="Mouse Ship/Menu" and row.key=="M"),"The paused reference missed restored action, destination or mouse controls")
	check(reference.rows.any(func(row):return row.label=="Strafe left" and row.key=="A") and reference.rows.any(func(row):return row.label=="Strafe right" and row.key=="D") and reference.rows.any(func(row):return row.label=="Brake" and row.key=="S"),"The paused reference omitted native strafe or brake controls")
	check(reference.rows.all(func(row):return row.key not in ["W","K","C","V","1","3"]),"The paused reference advertised an unsupported original action")
	check(reference.rect.end.x<app.menu.snapshot().menu_rect.position.x,"The flight reference obscured paused menu actions")
	app.menu._buttons.options.pressed.emit();await process_frame
	check(app.phase=="options" and not app._pause_controls.visible and app._details.visible,"Paused Options kept the controls column over the settings")
	Input.parse_input_event(pause);Input.flush_buffered_events();await process_frame
	check(app.phase=="options","P closed Options instead of remaining a menu-only resume shortcut")
	Input.parse_input_event(release_pause);Input.flush_buffered_events()
	app.show_menu();await process_frame
	root.size=Vector2i(960,540);app.set_mobile_layout(true);await process_frame
	reference=app._pause_controls.snapshot()
	check(reference.visible and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(reference.rect) and reference.rect.end.x<app.menu.snapshot().menu_rect.position.x,"Landscape controls escaped the viewport or covered the paused menu")
	Input.parse_input_event(pause);Input.flush_buffered_events();await process_frame
	check(app.phase=="game" and app.game.session==session and not app.game._user_paused and not background._active and not app._pause_controls.visible,"Resume replaced the session or left the controls visible")
	app.free();await process_frame
	print("Menu frontend lifecycle: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
