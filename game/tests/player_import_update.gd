extends SceneTree
## Re-select updated game data while retaining the earlier import and its save.
const Frontend=preload("res://src/presentation/player_frontend.gd")
const SaveFile=preload("res://src/simulation/station_save_file.gd")
const Guard=preload("res://tests/fixtures/convoy_station_scenario.gd")
var checks:=0
var failures:=0

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	var directory:=OS.get_environment("GOF2_MENU_TEST_DIRECTORY")
	if args.size()!=3 or directory.is_empty() or not Guard.private_path(directory.path_join("player.json")):
		check(false,"Expected earlier receipt, updated receipt, earned save and private test directory");finish();return
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,720)
	var earlier:=Frontend.DmgImport.read_receipt(args[0])
	var updated:=Frontend.DmgImport.read_receipt(args[1])
	check(not earlier.is_empty() and not updated.is_empty() and earlier.base_content_id==updated.base_content_id and earlier.binding_id!=updated.binding_id,"Use two actual imports of the same supplied Mac game")
	if failures:finish();return
	var saved:=FileAccess.get_file_as_bytes(args[2])
	var copy:=directory.path_join("saves").path_join(earlier.base_content_id).path_join(earlier.binding_id).path_join("station.gof2save")
	DirAccess.make_dir_recursive_absolute(copy.get_base_dir())
	check(DirAccess.copy_absolute(args[2],copy)==OK,"Could not copy the earned save into isolated storage")
	var app:=Frontend.new();root.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	check(not app.boot(PackedStringArray(),directory) and app.phase=="setup","Start the chooser in an isolated profile")
	check(app._prepared_imports().size()==2,"Game files chooser lost one of the prepared imports")
	choose(app,"earlier files")
	check(app.phase=="menu" and app.bindings.binding_id==earlier.binding_id and app.has_save(),"Earlier files must retain their earned save")
	app.request_action("new_game")
	check(app.phase=="update" and not app.has_session(),"New game silently reused files without exhaust")
	await capture("import-update-notice")
	choose(app,"Choose or update")
	check(app.phase=="setup","Update action did not return to the common file chooser")
	await capture("import-update-choices")
	choose(app,"updated files")
	check(app.phase=="menu" and app.bindings.binding_id==updated.binding_id and not app.has_save() and not app._needs_import_update(),"Updated files must start independently of the earlier save")
	app.request_action("new_game")
	check(app.phase=="game" and app.has_session() and app.game.session.geometry.engine_particles!=null,"Updated New Game omitted connected opening exhaust")
	if app.game!=null:app.game.free();app.game=null
	app.show_setup();choose(app,"earlier files")
	check(app.has_save() and app.bindings.binding_id==earlier.binding_id,"Returning to earlier files lost Resume")
	app.request_action("resume")
	check(app.phase=="game" and app.has_session(),app.error)
	if app.has_session():
		app.game.set_process(false);app.game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN);app.game.present_session()
		check(app.game.station_shell.visible,"The existing first-station save still has no interface")
		await capture("import-earlier-save-resumed")
	check(FileAccess.get_file_as_bytes(copy)==saved and FileAccess.get_file_as_bytes(args[2])==saved,"Import selection changed or migrated the earlier save")
	app.free();await process_frame
	finish()

func choose(app: Control,text: String) -> void:
	for control in app._body.get_children():
		if control is Button and text in control.text:control.pressed.emit();return
	check(false,"Missing import action: "+text)

func capture(name: String) -> void:
	var directory:=OS.get_environment("GOF2_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name()=="headless":return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(directory)
	check(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Could not capture "+name)

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish() -> void:
	print("Player import update: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)
