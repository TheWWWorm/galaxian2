extends "res://tests/player_repeat_targeting.gd"
## Player-level regression from an untouched earned station save. Input reaches
## the same receiver as play; all acquired targets and movement are simulated.

func verify_departure(app: Control) -> void:
	var host: Control=app.game
	host.set_process(false)
	host._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	host.present_session();await process_frame;await process_frame
	for line in 40:
		if not host.station_panel.visible:break
		click(host.station_panel._next);await process_frame
	check(not host.station_panel.visible,"Post-Gunant station conversation did not finish")
	check(host.station_shell._actions.map.is_visible_in_tree(),"The earned post-Gunant station has no Map button")
	if failures:return
	await process_frame;await process_frame
	var station: Dictionary=host.session.snapshot()
	click(host.station_shell._actions.map);await process_frame;await process_frame
	check(host._station_map_open and host.map_panel.visible,"Station Map click did not display the system map: "+host.status.text)
	check(host.session.is_paused(),"Station map did not own modal input")
	check(not host._menu_button.visible and not host._launch_button.visible and not host._save_button.visible and not host._load_button.visible and not host._save_notice.visible,"Station map leaked fallback actions or a stale notification")
	if failures:return
	await capture("post-gunant-station-map")
	_press(KEY_RIGHT)
	check(host.map_panel.snapshot().selected_station_id>=0,"Station map did not accept selection")
	_press(KEY_ESCAPE)
	check(app.phase=="game" and not host._station_map_open and not host.session.is_paused(),"Map Escape opened Pause or failed to return to station")
	check(host.session.snapshot()==station,"Browsing the station map changed earned progress")
	if failures:return
	await super.verify_departure(app)
	if failures:return
	# Hold S through real input, then move laterally without changing the heading.
	_key(KEY_S,true)
	if not _step(host):return
	var stopped: Dictionary=host.session.snapshot()
	check(stopped.control_throttle==0.0 and stopped.input_throttle==0.0,"S did not brake at the retained zero throttle")
	check(not stopped.engine_particles.engine_enabled and not stopped.engine_particles.draw_enabled,"Braking did not hide exhaust")
	check(host.flight_vitals._throttle_percent==0,"Throttle indicator did not show zero")
	for tick in 8:
		if not _step(host):return
	var before: Dictionary=host.session.snapshot()
	_key(KEY_A,true)
	for tick in 8:
		if not _step(host):return
	_key(KEY_A,false)
	var after: Dictionary=host.session.snapshot()
	var displacement: Vector3=before.player_pose.basis.inverse()*(after.player_pose.origin-before.player_pose.origin)
	check(displacement.x>0.0 and absf(displacement.z)<0.05,"A did not produce source local-X strafe while braking")
	check(before.player_pose.basis.is_equal_approx(after.player_pose.basis),"A rotated the ship instead of strafing")
	for tick in 30:
		if not _step(host):return
	before=host.session.snapshot()
	_key(KEY_D,true)
	for tick in 8:
		if not _step(host):return
	_key(KEY_D,false)
	after=host.session.snapshot();displacement=before.player_pose.basis.inverse()*(after.player_pose.origin-before.player_pose.origin)
	check(displacement.x<0.0 and absf(displacement.z)<0.05,"D did not produce opposite strafe while braking")
	_key(KEY_S,false)
	for press in 10:_press(KEY_BRACKETRIGHT)
	if not _step(host):return
	before=host.session.snapshot()
	check(before.control_throttle==1.0 and before.engine_particles.engine_enabled,"Released brake/throttle did not restore flight and exhaust")
	_key(KEY_S,true)
	if not _step(host):return
	check(host.session.snapshot().control_throttle==0.0 and host.session.snapshot().input_throttle==1.0,"Brake lost the original throttle setting")
	_key(KEY_S,false)
	if not _step(host):return
	check(host.session.snapshot().control_throttle==1.0,"Brake release failed to restore prior throttle")
	if failures:return
	await capture("flight-throttle-exhaust-restored")
	_press(KEY_Q)
	check(host.flight_menu.visible,"Q destination menu is missing")
	check(not host.status.visible,"Q destination menu leaked developer status text")
	await capture("q-autopilot-destinations")
	_press(KEY_ESCAPE)
	check(app.phase=="game" and not host.flight_menu.visible,"Q-menu Escape opened Pause")
	_choose_autopilot(host,"field_autopilot")
	check(host.session.snapshot().station_autopilot.target_kind=="field" and host.session.snapshot().station_autopilot.target_position==host.session.snapshot().scenery.center,"Asteroid field choice targets something other than the generated field center")
	_choose_autopilot(host,"station_autopilot")
	check(host.session.snapshot().station_autopilot.target_kind=="station","Station choice could not replace field guidance")
	_choose_autopilot(host,"cancel_autopilot")
	for press in 10:_press(KEY_SLASH)
	if failures:return
	# Physical P should expose the control reference; Q must remain destination UI.
	_press(KEY_P);await process_frame
	check(app.phase=="menu" and app._pause_controls.is_visible_in_tree(),"P did not show Pause with the controls reference")
	await capture("pause-control-reference")
	_press(KEY_P);await process_frame
	check(app.phase=="game" and not app._pause_controls.visible,"P did not resume the retained flight")
	if failures:return
	host.session.rebase_time(_time)
	_press(KEY_M)
	check(not host._mouse_captured,"M did not release the mouse for menus")
	_press(KEY_M)
	check(host._mouse_captured,"M did not restore mouse steering")
	if not await _station_lock(host):return
	await capture("var-hastra-station-lock")
	_press(KEY_F)
	check(host.session.snapshot().station_autopilot.active and host.session.snapshot().station_autopilot.target_kind=="station","F did not start docking guidance for the aimed station")
	_choose_autopilot(host,"cancel_autopilot")
	for press in 10:_press(KEY_SLASH)
	if failures:return
	var asteroid:=await _acquire(host,-1)
	check(asteroid>=0,"Station guidance prevented asteroid acquisition")
	if failures:return
	if not await _station_lock(host):return
	await capture("station-reacquired-after-asteroid")

func _station_lock(host: Control) -> bool:
	for tick in 1000:
		var state: Dictionary=host.session.snapshot()
		if not _step(host,Pilot.steering_toward(state.player_pose,state.station_exterior.pose.origin)):return false
		if host.session.snapshot().station_targeting.locked_index==0:
			check(host.session.scene.station_target_overlay!=null and host.session.scene.station_target_overlay.visible,"Station locked without its visible overlay")
			return failures==0
	var last: Dictionary=host.session.snapshot()
	print("Station acquisition failed: ",last.station_targeting," mining=",last.mining_targeting.selected_object_index," scanner=",last.get("npc_scanner",{}).get("found_actor_id",-1)," retained_npc=",last.get("npc_scanner",{}).get("selected_actor_id",-1)," approach=",last.mining_approach.phase," guidance=",last.station_autopilot.active," input=",host._controls.snapshot())
	check(false,"Aiming at the station failed to acquire or reacquire it")
	return false

func _key(code: int,down: bool) -> void:
	var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=down
	Input.parse_input_event(event);Input.flush_buffered_events()
