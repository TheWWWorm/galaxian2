extends "res://tests/player_station_departure.gd"
## Drive an earned station save through the player UI with native mouse events.
var _result_available:=false
var _accepted_contact:=-1

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	var directory:=OS.get_environment("GOF2_MENU_TEST_DIRECTORY")
	if args.size()!=2 or directory.is_empty() or not Guard.private_path(directory.path_join("player.json")):
		check(false,"Expected an import receipt, copied earned save and private player directory");finish();return
	var receipt:=Frontend.DmgImport.read_receipt(args[0])
	check(not receipt.is_empty(),"The selected import receipt is unavailable")
	if failures:finish();return
	var original:=FileAccess.get_file_as_bytes(args[1])
	check(not original.is_empty(),"The copied player save is unavailable")
	var path:=directory.path_join("saves").path_join(receipt.base_content_id).path_join(receipt.binding_id).path_join("station.gof2save")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	check(DirAccess.copy_absolute(args[1],path)==OK,"Could not isolate the copied player save")
	if failures:finish();return
	root.size=Vector2i(1280,720);root.content_scale_size=Vector2i(960,540)
	var app:=Frontend.new();root.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.boot(PackedStringArray(),directory)
	check(app.open_import(args[0]),app.error)
	if failures:app.free();finish();return
	await process_frame
	for frame in 26:app.menu.advance_title(150.0)
	check(app.menu.snapshot().title_active and app.menu._title_prompt.visible,"The actual player menu did not present Tap to continue")
	if failures:app.free();finish();return
	await click_control(app.menu._title_prompt)
	check(not app.menu.snapshot().title_active and app.phase=="menu","A native mouse click did not dismiss the player title")
	check(app.menu._buttons.resume.visible and not app.menu._buttons.resume.disabled,"The copied earned save did not offer Resume")
	if failures:app.free();finish();return
	await capture("saved-title-dismissed")
	await click_control(app.menu._buttons.resume)
	check(app.phase=="game" and app.has_session(),"A native mouse click did not load the copied save: "+app.error)
	if not failures:await verify_player_mouse(app)
	check(FileAccess.get_file_as_bytes(args[1])==original,"The original copied save was changed by the player test")
	app.free();await process_frame;finish()

func verify_player_mouse(app: Control) -> void:
	var host: Control=app.game
	host._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	host.present_session();await process_frame;await process_frame
	var state: Dictionary=host.session.snapshot()
	print("Saved station: cursor=",state.campaign_cursor," phase=",state.phase," station=",state.loadout.station_id," offers=",state.get("contracts",{}).get("offers",{}).size()," pending=",not state.get("contracts",{}).get("pending_result",{}).is_empty())
	_result_available=not state.get("contracts",{}).get("pending_result",{}).is_empty()
	if _result_available:
		check(host.lounge_panel.visible and host.lounge_panel._yes.visible,"Saved contract result did not present Close")
		if failures:return
		var serial: int=int(state.contracts.pending_result.serial)
		await click_control(host.lounge_panel._yes,host)
		state=host.session.snapshot()
		check(state.contracts.pending_result.is_empty() and not host.lounge_panel.snapshot().pending_result.has("serial"),"Mouse Close did not acknowledge saved result "+str(serial))
		if failures:return
	await advance_station_dialogue(host)
	if failures:return
	check(host.station_shell.visible and host.station_shell._actions.depart.visible and not host.station_shell._actions.depart.disabled,"Saved station has no mouse departure action")
	if failures:return
	await click_control(host.station_shell._actions.depart,host)
	check(host._launch_dialog.visible and not host._launch_dialog._no.disabled,"Mouse Depart did not open the actual confirmation")
	if failures:return
	await capture("saved-departure-question")
	await click_control(host._launch_dialog._no,host)
	check(not host._launch_dialog.visible and host.station_shell.visible,"Mouse No did not cancel departure")
	if failures:return
	var lounge_button: Button=host.station_shell._actions.lounge
	if lounge_button.visible and not lounge_button.disabled:
		await click_control(lounge_button,host)
		state=host.session.snapshot()
		check(state.get("lounge_open",false) and host.lounge_panel.visible,"Mouse Lounge did not open the saved station's lounge")
		if failures:return
		await capture("saved-lounge")
		await exercise_saved_offer(host)
		if failures:return
		await advance_station_dialogue(host)
		if failures:return
		if host.lounge_panel.visible:
			check(host.lounge_panel._back.visible and not host.lounge_panel._back.disabled,"The saved lounge has no active Back button")
			if failures:return
			await click_control(host.lounge_panel._back,host)
			check(not host.session.snapshot().get("lounge_open",false),"Mouse Back did not close the saved lounge")
			if failures:return
	else:print("Saved cursor has no enabled station Lounge action; contract-offer click is unavailable")
	host.present_session();await process_frame
	check(host.station_shell.visible and host.station_shell._actions.depart.visible and not host.station_shell._actions.depart.disabled,"Station did not restore Depart after the lounge")
	if failures:return
	await click_control(host.station_shell._actions.depart,host)
	check(host._launch_dialog.visible and not host._launch_dialog._yes.disabled,"Mouse Depart did not reopen the actual confirmation")
	if failures:return
	await click_control(host._launch_dialog._yes,host)
	check(host.session is Flight and not host._launch_dialog.visible,"Mouse Yes did not launch the saved career: "+host.status.text+" / "+host.session.error)
	if failures:return
	await capture("saved-mouse-departed-flight")
	print("Real-host pointer coverage: result_close=",_result_available," accepted_contact=",_accepted_contact," departure_yes=true")

func advance_station_dialogue(host: Control) -> void:
	for line in 40:
		if not host.station_panel.visible:break
		check(host.station_panel._next.visible and not host.station_panel._next.disabled,"Station dialogue lost its clickable Next control")
		if failures:return
		await click_control(host.station_panel._next,host)
	check(not host.station_panel.visible,"Saved station conversation did not finish through mouse Next")

func exercise_saved_offer(host: Control) -> void:
	var lounge: Control=host.lounge_panel
	# StationSession.step advances the authored entry camera. Let the real host
	# reach its settled pose before choosing a visitor on screen.
	var entry_ms: int=int(lounge._scene._rules.camera.entry_duration_ms)
	for frame in 240:
		if int(lounge._scene.snapshot().elapsed_ms)>=entry_ms:break
		await process_frame
	var state: Dictionary=host.session.snapshot()
	if not state.contracts.pending_result.is_empty():
		print("Saved lounge contains a pending result; offer selection is unavailable")
		return
	var previews: Dictionary=state.get("contract_previews",{})
	var candidates:=[]
	for id in previews:
		if previews[id].get("can_accept",false):candidates.append(int(id))
	print("Saved lounge: offers=",state.contracts.offers.size()," acceptable=",candidates.size()," camera_ms=",lounge._scene.snapshot().elapsed_ms," contacts=",lounge._scene.screen_contacts().size())
	if candidates.is_empty():return
	var chosen:=-1
	for attempt in 90:
		for row in lounge._scene.screen_contacts():
			var id:=int(row.id)
			if id not in candidates:continue
			for point in [row.anchor,row.rect.get_center(),row.rect.position+row.rect.size*Vector2(0.25,0.5),row.rect.position+row.rect.size*Vector2(0.75,0.5)]:
				if not Rect2(Vector2.ZERO,lounge.size).has_point(point) or lounge._panel.get_rect().has_point(point):continue
				await click_point(lounge.get_global_transform()*point,host)
				if lounge.snapshot().selected==id:chosen=id;break
			if chosen>=0:break
		if chosen>=0:break
		await process_frame
	check(chosen>=0,"An acceptable saved contact could not be selected by mouse")
	if failures:return
	check(lounge._yes.visible and not lounge._yes.disabled,"The selected saved contract lacks an enabled Okay button")
	if failures:return
	await capture("saved-contract-offer")
	await click_control(lounge._yes,host)
	check(lounge.snapshot().confirming,"Mouse Okay did not present contract confirmation")
	if failures:return
	await click_control(lounge._yes,host)
	state=host.session.snapshot()
	check(int(state.contracts.active_offer_id)==chosen and state.contracts.offers[chosen].consumed and not state.contracts.mission.is_empty(),"Mouse Okay did not accept the original saved contact's offer")
	if not failures:_accepted_contact=chosen

func click_control(control: Control,host: Control=null) -> void:
	await click_point(control.get_global_rect().get_center(),host)

func click_point(point: Vector2,host: Control=null) -> void:
	var window_point:=root.get_final_transform()*point
	var motion:=InputEventMouseMotion.new();motion.position=window_point;motion.global_position=window_point
	Input.parse_input_event(motion);Input.flush_buffered_events();await process_frame
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=window_point;event.global_position=window_point;event.pressed=true
	Input.parse_input_event(event);Input.flush_buffered_events();await process_frame
	if host!=null and host.session!=null:host.present_session()
	await process_frame
	event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=window_point;event.global_position=window_point;event.pressed=false
	Input.parse_input_event(event);Input.flush_buffered_events();await process_frame

func finish() -> void:
	print("Saved player mouse flow: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)
