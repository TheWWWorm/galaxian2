extends "res://tests/player_repeat_targeting.gd"
## Select the supported destination while docked, then use the ordinary Depart
## confirmation and let the host hand that course to released flight controls.

func verify_departure(app: Control) -> void:
	var host: Control=app.game
	host.set_process(false);host._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	host.present_session();await process_frame;await process_frame
	for line in 40:
		if not host.station_panel.visible:break
		click(host.station_panel._next);await process_frame
	await process_frame;await process_frame
	check(host.station_shell._actions.map.visible,"Earned station has no Map entry")
	if failures:return
	var original: Dictionary=host.session.snapshot()
	click(host.station_shell._actions.map);await process_frame
	check(host._station_map_open,"Map did not open")
	if failures:return
	var selected:=-1
	for index in 24:
		_press(KEY_RIGHT)
		var map: Dictionary=host.map_panel.snapshot()
		for row in map.rows:
			if row.station_id==map.selected_station_id and row.supported:selected=int(row.station_id)
		if selected>=0:break
	check(selected>=0,"No supported post-Gunant destination exists")
	if failures:return
	_press(KEY_ENTER)
	check(host.map_panel.snapshot().confirmation_visible,"Map did not ask to confirm the selected destination")
	await capture("station-map-course-confirmation")
	_press(KEY_ENTER)
	check(not host._station_map_open and host._station_course_id==selected and host.session.snapshot()==original,"Selecting a course changed station progress or failed to return")
	if failures:return
	await process_frame;await process_frame
	click(host.station_shell._actions.depart);await process_frame
	check(host._launch_dialog.visible,"Depart did not ask for confirmation after map selection")
	if failures:return
	click(host._launch_dialog._yes);await process_frame
	check(host.session is Flight,"Confirmed departure after Map failed: "+host.status.text)
	if failures:return
	host.session.rebase_time(0)
	for frame in 160:
		if host.session.can_control():break
		if not _step(host):return
	check(host.session.can_control(),"Departure after Map did not release controls")
	if failures:return
	host._process(0)
	var state: Dictionary=host.session.snapshot()
	check(not host._transition_failed and host._station_course_id==-1,"Host did not consume the docked course: "+host.status.text)
	check(state.station_autopilot.active and state.station_autopilot.target_kind=="planet" and state.station_autopilot.station_id==selected,"Docked course did not become planet guidance after departure")
	await capture("departed-with-selected-course")
