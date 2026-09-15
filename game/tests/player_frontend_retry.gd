extends "res://tests/player_frontend.gd"
## The actual DMG-backed menu loads an earned mining checkpoint. A positioned
## source projectile isolates lethal contact; the native death/input/menu path
## must return to the same viable saved station without changing progress.
const DeathFixture=preload("res://tests/player_death_flight.gd")

func run() -> void:
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,720);root.grab_focus()
	args=OS.get_cmdline_user_args();directory=OS.get_environment("GOF2_MENU_TEST_DIRECTORY")
	if args.size() not in [3,4] or directory.is_empty() or not PathGuard.private_path(directory+"/player.json"):
		check(false,"Expected content paths and a private menu test directory");quit(1);return
	if args.size()==4:
		captures=args[3]
		if not PathGuard.private_path(captures+"/image.png"):check(false,"Keep captures outside source");quit(1);return
		DirAccess.make_dir_recursive_absolute(captures)
	app=Frontend.new();root.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await verify_retry()
	app.free();await process_frame
	print("Menu death retry: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify_retry() -> void:
	if FileAccess.file_exists(directory.path_join("player.json")):check(false,"Use a new menu retry directory");return
	check(not app.boot(PackedStringArray(),directory) and app.phase=="setup","Fresh retry test bypassed the DMG requirement")
	var receipt:=OS.get_environment("GOF2_MENU_IMPORT_RECORD")
	if receipt.is_empty() or not app.open_import(receipt):check(false,"Supply the completed Mac DMG import: "+app.error);return
	var source_save:=OS.get_environment("GOF2_MENU_SOURCE_SAVE")
	if source_save.is_empty() or not PathGuard.private_path(source_save):check(false,"Supply the earned second-mining checkpoint");return
	var path:=SaveFile.path_for(directory.path_join("saves"),app.bindings)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if DirAccess.copy_absolute(source_save,path)!=OK:check(false,"Cannot stage the earned opening save");return
	var file:=SaveFile.new();var document:=file.read_document(path)
	if document.get("station",{}).get("campaign_cursor")!=4:check(false,"The retry input must be the earned first mining return");return
	app.show_menu();app.menu._buttons.resume.pressed.emit()
	if not app.has_session():check(false,app.error);return
	app.game.set_process(false);app.game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(app.phase=="game" and app.game.session.snapshot().campaign_cursor==4,"Menu Resume did not load the opening checkpoint")
	check(app.game._preview_controls.all(func(control):return not control.visible) and app.game._menu_button.visible,"The player entry exposed developer controls or omitted its menu")
	await capture("menu-retry-loaded-mining")
	root.size=Vector2i(960,540);app.set_mobile_layout(true);app.game.set_touch_controls(true)
	await capture("menu-retry-loaded-landscape")
	check(app.game._save_button.size.y>=44 and app.game._load_button.size.y>=44,"Opening save actions lost their landscape touch targets")
	root.size=Vector2i(1280,720);app.set_mobile_layout(false);app.game.set_touch_controls(false)
	if not app.game.request_departure() or not app.game.enter_first_flight(0,4096,1789100000):check(false,app.game.status.text);return
	var flight: Node=app.game.session;flight.rebase_time(0)
	var now:=0
	for tick in 160:
		if flight.snapshot().dialogue.visible:break
		now+=100000
		if not flight.step(now):check(false,flight.error);return
	if not flight.snapshot().dialogue.visible or not flight.navigate("next"):check(false,flight.error);return
	var fixture:=DeathFixture.new();var dead: RefCounted=fixture.lethal(flight.flight_owner())
	check(dead!=null and fixture.failures==0,"The source projectile did not start the native death path");fixture.free()
	if dead==null:return
	if not flight._commit(dead,false):check(false,flight.error);return
	var rules: Dictionary=app.bindings.player_destruction
	for tick in ceili(float(rules.failure_after_ms+rules.failure_delay_ms+rules.fade_ms)/150.0)+8:
		if flight.snapshot().player_destruction.phase=="game_over":break
		now+=150000
		if not flight.step(now):check(false,flight.error);return
	check(flight.snapshot().player_destruction.phase=="game_over","Death did not finish its original fade")
	app.game.present_session();await capture("menu-retry-game-over")
	var event:=InputEventKey.new();event.physical_keycode=KEY_ENTER;event.pressed=true
	app.game._unhandled_input(event)
	check(flight.status=="game_over_transition_required","Game-over confirmation did not select the original menu transition")
	if not app.game.enter_game_over():check(false,app.game.status.text);return
	check(app.phase=="menu" and not app.has_session() and app.menu._buttons.resume.visible and app.music.player.playing,"The actual game-over signal did not return to the main menu")
	check(file.read_document(path)==document,"Death replaced the viable opening save")
	await capture("menu-retry-menu")
	app.menu._buttons.resume.pressed.emit()
	if not app.has_session():check(false,app.error);return
	var archive:=Archive.new();var restored:=archive.capture(app.game.session.station_owner(),app.bindings,app.game.session.location_owner())
	check(app.phase=="game" and restored==document,"Menu retry changed the earned mining station or its contacts")
	check(not app.music.player.playing,"Menu music continued after retry")
	await capture("menu-retry-restored")
