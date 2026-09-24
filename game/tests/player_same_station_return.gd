extends "res://tests/player_repeat_targeting.gd"
## An earned local-travel departure must be able to dock back at its origin,
## save/reload, and leave again without completing the destination objective.

func verify_departure(app: Control) -> void:
	var host: Control=app.game
	host.set_process(false);host._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	host.present_session();await process_frame;await process_frame
	for line in 40:
		if not host.station_panel.visible:break
		click(host.station_panel._next);await process_frame
	var origin: Dictionary=host.session.snapshot()
	check(origin.campaign_cursor in [10,11,12],"Use an earned local-travel station")
	if failures:return
	for visit in 2:
		host.present_session();await process_frame;await process_frame
		click(host.station_shell._actions.depart);await process_frame
		check(host._launch_dialog.visible,"Depart did not open its confirmation")
		if failures:return
		click(host._launch_dialog._yes);await process_frame
		check(host.session is Flight,"Departure failed: "+host.status.text)
		if failures:return
		_time=0;host.session.rebase_time(0)
		for frame in 160:
			if host.session.can_control():break
			if not _step(host):return
		check(host.session.can_control(),"Departure did not release controls")
		check(host.session.snapshot().station_return_supported,"Origin station docking is disabled")
		if failures:return
		_choose_autopilot(host,"station_autopilot")
		for frame in 1000:
			if host.session.status!="running":break
			if not _step(host):return
		check(host.session.status=="station_transition_required","Station guidance failed to dock at the origin: "+str(host.session.snapshot().player_pose.origin))
		if failures:return
		check(host.enter_station(_time),host.status.text)
		host.present_session();await process_frame;await process_frame
		check(not host.station_panel.visible,"Returning to origin replayed destination dialogue")
		var state: Dictionary=host.session.snapshot()
		check(state.campaign_cursor==origin.campaign_cursor and state.mission==origin.mission,"Returning to origin advanced the travel objective")
		check(state.loadout.station_id==origin.loadout.station_id,"Returning to origin changed station")
		check(state.equipment.credit_delta==origin.equipment.credit_delta,"Returning to origin duplicated a reward")
		check(host.save_station(false),host._save_notice.text)
		if failures:return
		await capture("same-station-return-"+str(visit))
		check(host.load_station(),host._save_notice.text)
		host.set_process(false);host._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
		check(host.session.snapshot().campaign_cursor==origin.campaign_cursor and host.session.snapshot().mission==origin.mission,"Reload changed the unfinished trip")
		if failures:return
