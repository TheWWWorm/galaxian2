extends "res://tests/ordinary_contract_application.gd"
## Second process: load without a fixture, deliver, reload, die and retry.
const SaveFile=preload("res://src/simulation/station_save_file.gd")
const Archive=preload("res://src/simulation/station_archive.gd")

func _initialize() -> void:call_deferred("run_saved_application")

func run_saved_application() -> void:
	if not open_application_content(OS.get_cmdline_user_args()):quit(1);return
	var directory:=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	if directory.is_empty() or not FreePlayCheckpoint.private_path(directory+"/save.bin"):check(false,"Set the first process's private save directory");quit(1);return
	app=Host.new();root.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.set_context(source,definitions,visual);app.set_process(false);app._focused=true;app.enable_saves(directory)
	app.show();await process_frame;resume_application_focus()
	await verify_saved_application()
	app.free();print("Saved-game application: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify_saved_application() -> void:
	var file:=SaveFile.new();var archive:=Archive.new()
	var earlier:=file.read_document(app.station_save_path()+".bak")
	var before:=archive.restore(definitions,catalogue,source,earlier)
	if before==null:check(false,file.error+archive.error);return
	check(app.session==null and app._load_button.visible,"A new application omitted its saved-game control")
	var key:=InputEventKey.new();key.physical_keycode=KEY_F9;key.pressed=true;app._unhandled_input(key)
	if app.session==null:check(false,app._save_notice.text);return
	var accepted: Dictionary=app.session.station_owner().snapshot()
	check(accepted.contracts.mission.kind==0 and accepted.contracts.completed_side_missions==4,"The new process did not resume its actual accepted courier")
	check(not app.session.snapshot().dialogue.visible and not app.session.snapshot().lounge_open,"Loading replayed a modal station conversation")
	await capture_free_application("save-loaded-desktop")
	# A failed scene preparation leaves the running station and file untouched.
	check(app._prepare_player_overlays().is_empty(),"Could not prepare the current game's HUD before the failed-load diagnostic")
	var frame_source: Dictionary=app.target_frame.source();var aim_source: Dictionary=app.aim_reticle.source();var markers_source: Dictionary=app.npc_markers.source()
	var previous: Node3D=app.session;var bytes:=FileAccess.get_file_as_bytes(app.station_save_path());var visuals: RefCounted=app.visuals
	app.visuals=Visuals.new()
	check(not app.load_station(now_us) and app.session==previous and app.session.station_owner().snapshot()==accepted and FileAccess.get_file_as_bytes(app.station_save_path())==bytes and not app._save_notice.text.is_empty(),"Failed loaded presentation replaced the running game or save")
	check(app.target_frame.prepared and app.aim_reticle.prepared and app.npc_markers.prepared and app.target_frame.source()==frame_source and app.aim_reticle.source()==aim_source and app.npc_markers.source()==markers_source,"Failed loaded presentation cleared the current HUD")
	app.visuals=visuals
	var offer: Dictionary=accepted.contracts.accepted_contact.offer
	await verify_delivery_route(before.snapshot(),before.snapshot(),offer,accepted,0)
	if failures:return
	var paid: Dictionary=app.session.station_owner().snapshot()
	var paid_record:=file.load_document(app.station_save_path(),definitions,catalogue,source)
	if paid_record.is_empty():check(false,file.error);return
	check(paid_record.career.credits==paid.contracts.credits and paid_record.career.mission.is_empty(),"Acknowledged delivery was not saved")
	check(app.load_station(now_us) and app.session.station_owner().snapshot()==paid,"Reloading paid the completed delivery again or lost its cargo")
	await capture_free_application("save-loaded-mobile-landscape")
	check(app._save_button.size.y>=44 and app._load_button.size.y>=44,"Landscape Save and Load lost their touch target size")
	root.size=Vector2i(1280,720);app.set_mobile_layout(false);app.set_touch_controls(false)
	await process_frame;resume_application_focus()
	await verify_free_game_over()
	if failures:return
	check(file.load_document(app.station_save_path(),definitions,catalogue,source)==paid_record,"Game over overwrote the viable saved station")
	check(app._load_button.visible and app._load_button.text=="Retry saved game","Game over omitted checkpoint retry")
	await capture_free_application("save-retry-desktop")
	app._load_button.pressed.emit()
	if app.session==null:check(false,app._save_notice.text);return
	check(app.session.station_owner().snapshot()==paid,"Retry restored different inventory, money or progress")
	await capture_free_application("save-retried-desktop")
	print("Loaded delivery and death retry retain ",paid.contracts.credits," credits and ",paid.contracts.completed_side_missions," completed jobs")
