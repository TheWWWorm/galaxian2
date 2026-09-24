extends "res://tests/free_application.gd"
## Reproduce player flight actions from an actual, unchanged station save.

func verify_free_application() -> void:
	var original: Dictionary=app.session.station_owner().snapshot()
	app.set_player_mode(true)
	app.show();app.present_session();await process_frame;resume_application_focus()
	for method in ["mouse","keyboard","controller"]:
		report_key(KEY_ENTER);await process_frame
		check(app._launch_dialog.visible and app._launch_dialog.snapshot().text==source.strings[int(definitions.station_departure.confirmation_text_id)],"Departure lost the original localized question")
		check(Rect2(Vector2.ZERO,app._launch_dialog.size).encloses(app._launch_dialog._panel.get_rect()),"Departure panel exceeds the viewport")
		if method=="mouse":
			await capture_free_application("player-reports-departure-desktop")
			report_click(app._launch_dialog._no)
		elif method=="keyboard":report_key(KEY_ESCAPE)
		else:report_pad(JOY_BUTTON_B)
		check(not app._launch_dialog.visible and app._launch_packet.is_empty() and app.session.station_owner().snapshot()==original,"Cancelled departure changed the career or left its modal open: "+method)
		if failures:return
	app.set_mobile_layout(true);root.size=Vector2i(960,540)
	if not app.request_departure():check(false,app.status.text);return
	await process_frame;await process_frame
	check(app._launch_dialog._yes.size.y>=44 and Rect2(Vector2.ZERO,app._launch_dialog.size).encloses(app._launch_dialog._panel.get_rect()),"Landscape departure clips its touch actions")
	await capture_free_application("player-reports-departure-landscape")
	app._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	report_key(KEY_ENTER);report_click(app._launch_dialog._yes)
	check(app._launch_dialog.visible and app.session.station_owner().snapshot()==original,"Unfocused confirmation launched or changed the station")
	app._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	report_pad(JOY_BUTTON_B)
	check(not app._launch_dialog.visible,"Controller could not cancel after focus returned")
	app.set_mobile_layout(false);root.size=Vector2i(1280,720);await process_frame
	report_key(KEY_ENTER);await process_frame
	report_click(app._launch_dialog._yes)
	check(app.session is FlightSession and not app._launch_dialog.visible,"Mouse confirmation did not launch the actual earned station")
	if failures:return
	app.session.rebase_time(now_us)
	if not await release_application_flight():return
	check(app._flight_hint.visible and "Q  Autopilot destinations" in app._flight_hint.text and "F  Dock / Mine" in app._flight_hint.text and "Hold Tab  Fast Forward" in app._flight_hint.text,"Desktop flight omitted its station/Fast Forward shortcuts: "+str(app._flight_hint.visible)+" "+app._flight_hint.text)
	check(not app._flight_actions.visible and not app.touch_overlay.visible,"Shortcut hints enabled desktop touch actions")
	for cycle in 3:
		check(choose_free_keyboard_flight_action(KEY_Q,"station_autopilot"),"Q menu did not select station guidance")
		check(app.session.snapshot().station_autopilot.active,"Station autopilot failed to engage on cycle "+str(cycle)+": "+app.status.text)
		if failures or not report_step():return
		check(choose_free_keyboard_flight_action(KEY_Q,"cancel_autopilot"),"Q menu did not cancel guidance")
		check(not app.session.snapshot().station_autopilot.active,"Station autopilot did not cancel on cycle "+str(cycle))
		if failures or not report_step():return
	# A later station/planet selection must remain usable after cancellation.
	if not app.open_map(now_us):check(false,app.status.text);return
	var choices: Array=app.map_panel.snapshot().rows.filter(func(row):return row.supported)
	check(not choices.is_empty(),"The earned flight has no ordinary local destination")
	if failures:return
	var destination: int=int(choices[0].station_id)
	app.map_panel.select_station(destination);app.map_panel.request_confirmation()
	check(app.confirm_map_planet(destination,now_us),app.map_panel.error+app.session.error)
	check(app.session.snapshot().station_autopilot.active and app.session.snapshot().station_autopilot.target_kind=="planet","A map destination could not re-engage guidance after station cancellation")
	if failures:return
	check(choose_free_keyboard_flight_action(KEY_Q,"cancel_autopilot"),"Q menu did not cancel selected planet guidance")
	check(not app.session.snapshot().station_autopilot.active,"Station action did not cancel the selected planet")
	check(choose_free_keyboard_flight_action(KEY_Q,"station_autopilot"),"Q menu did not reselect station guidance")
	check(app.session.snapshot().station_autopilot.active and app.session.snapshot().station_autopilot.target_kind=="station","A cancelled planet prevented station re-engagement")
	check("Autopilot destinations / Cancel" in app._flight_hint.text,"Active guidance did not explain cancellation")
	var retained: Dictionary=app.session.snapshot()
	check(retained.cargo==original.cargo and retained.mission==original.mission and retained.contracts.credits==original.contracts.credits,"Autopilot input changed retained cargo, story or credits")
	await capture_free_application("player-reports-autopilot-reengaged")

func report_key(code: int) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=pressed
		Input.parse_input_event(event);Input.flush_buffered_events()

func report_pad(button: int) -> void:
	for pressed in [true,false]:
		var event:=InputEventJoypadButton.new();event.button_index=button;event.pressed=pressed
		Input.parse_input_event(event);Input.flush_buffered_events()

func report_click(button: Button) -> void:
	var center:=button.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=center;motion.global_position=center
	Input.parse_input_event(motion);Input.flush_buffered_events()
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=center;event.global_position=center;event.pressed=pressed
		Input.parse_input_event(event);Input.flush_buffered_events()

func report_step() -> bool:
	now_us+=100000
	if not app.session.step(now_us):check(false,app.session.error);return false
	app.present_session()
	return true
