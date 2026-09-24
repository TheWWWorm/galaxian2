extends SceneTree
## Exercise station departure through the player frontend and actual mouse input,
## using a private copy of an earned save with its original imported content.
const Frontend=preload("res://src/presentation/player_frontend.gd")
const Flight=preload("res://src/presentation/first_flight_session.gd")
const Guard=preload("res://tests/fixtures/convoy_station_scenario.gd")
var checks:=0
var failures:=0

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	var directory:=OS.get_environment("GOF2_MENU_TEST_DIRECTORY")
	if args.size()!=2 or directory.is_empty() or not Guard.private_path(directory.path_join("player.json")):
		check(false,"Expected an import receipt, earned save and private test directory");finish();return
	var receipt:=Frontend.DmgImport.read_receipt(args[0])
	check(not receipt.is_empty(),"The original import receipt is unavailable")
	if failures:finish();return
	var original:=FileAccess.get_file_as_bytes(args[1])
	var path:=directory.path_join("saves").path_join(receipt.base_content_id).path_join(receipt.binding_id).path_join("station.gof2save")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	check(DirAccess.copy_absolute(args[1],path)==OK,"Could not isolate the earned save")
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,720)
	var app:=Frontend.new();root.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.boot(PackedStringArray(),directory)
	check(app.open_import(args[0]),app.error)
	# Dismiss the real title before resuming, as a player does. A direct resume
	# request otherwise leaves an unseen title waiting to consume the next key.
	var title_key:=InputEventKey.new();title_key.physical_keycode=KEY_ENTER;title_key.pressed=true
	Input.parse_input_event(title_key);Input.flush_buffered_events();await process_frame
	title_key=InputEventKey.new();title_key.physical_keycode=KEY_ENTER
	Input.parse_input_event(title_key);Input.flush_buffered_events()
	app.request_action("resume")
	check(app.phase=="game" and app.has_session(),app.error)
	if not failures:await verify_departure(app)
	check(FileAccess.get_file_as_bytes(args[1])==original,"Departure changed the original supplied save")
	app.free();await process_frame;finish()

func verify_departure(app: Control) -> void:
	var host: Control=app.game
	host._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	host.present_session();await process_frame;await process_frame
	var state: Dictionary=host.session.snapshot()
	print("Loaded departure: cursor=",state.campaign_cursor," phase=",state.phase," station=",state.loadout.station_id)
	for line in 40:
		if not host.station_panel.visible:break
		click(host.station_panel._next);await process_frame
	check(not host.station_panel.visible,"Station conversation did not finish")
	if failures:return
	check(host.station_shell.visible and host.station_shell._actions.depart.visible and not host.station_shell._actions.depart.disabled,"Station did not expose its permitted departure")
	if failures:return
	click(host.station_shell._actions.depart);await process_frame;await process_frame
	check(host._launch_dialog.visible and not host._launch_dialog._yes.disabled,"Depart did not open an active question: "+host.status.text+" / "+host.session.error+" / focused="+str(host._focused))
	if failures:return
	await capture("saved-station-departure-question")
	# A missing prepared texture can reject the next scene after Yes. Keep the
	# earned station/save and expose the reason instead of a silent hangar.
	var station: Node=host.session
	var accepted: Dictionary=station.snapshot()
	var textures: Dictionary=host.visuals.textures
	host.visuals.textures={}
	click(host._launch_dialog._yes);await process_frame
	host.visuals.textures=textures
	check(host.session==station and station.snapshot()==accepted and host._transition_failed,"Rejected departure changed the earned station")
	check(host.status.is_visible_in_tree() and not host.status.text.is_empty() and host._retry_button.is_visible_in_tree(),"The player cannot see why station departure failed or retry it")
	await capture("saved-station-departure-error")
	if failures:return
	click(host._retry_button);await process_frame;await process_frame
	check(host._launch_dialog.visible,"Retry did not offer station departure again")
	if failures:return
	click(host._launch_dialog._yes);await process_frame
	check(host.session is Flight and not host._launch_dialog.visible,"Mouse Yes did not depart: "+host.status.text+" / "+host._save_notice.text)
	if failures:return
	host.set_process(false)
	host.session.rebase_time(0)
	for tick in 80:
		host.session.set_pause("focus",false,tick*100000)
		check(host.session.step((tick+1)*100000),host.session.error)
		if failures:return
		host.present_session()
		if host.session.can_control():break
	check(host.session.can_control(),"Accepted departure did not release flight controls")
	await capture("saved-station-departure-flight")

func click(button: Button) -> void:
	# Input.parse_input_event expects window coordinates, including the viewport
	# transform used by native-resolution and high-DPI player display settings.
	var point:=root.get_final_transform()*button.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point
	Input.parse_input_event(motion);Input.flush_buffered_events()
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT
		event.position=point;event.global_position=point;event.pressed=down
		Input.parse_input_event(event);Input.flush_buffered_events()

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
	print("Saved player station departure: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)
