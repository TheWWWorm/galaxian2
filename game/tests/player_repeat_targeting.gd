extends "res://tests/player_station_departure.gd"
## Resume an untouched copy of an earned station save, then use flight controls
## to acquire different generated asteroids. No target or pose is injected.
const Pilot=preload("res://tests/fixtures/expedition_flight_pilot.gd")
var _time:=0

func verify_departure(app: Control) -> void:
	var host: Control=app.game
	host.set_process(false)
	check(app.change_preference("mouse_steering",true),app.error)
	host._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	host.present_session();await process_frame;await process_frame
	print("Repeat-target save: cursor=",host.session.snapshot().campaign_cursor)
	for line in 40:
		if not host.station_panel.visible:break
		click(host.station_panel._next);await process_frame
	check(not host.station_panel.visible,"Saved station conversation did not finish")
	if failures:return
	click(host.station_shell._actions.depart);await process_frame;await process_frame
	check(host._launch_dialog.visible,"Saved station did not offer departure")
	if failures:return
	click(host._launch_dialog._yes);await process_frame
	check(host.session is Flight,"Saved station could not depart: "+host.status.text)
	if failures:return
	host.session.rebase_time(0)
	for tick in 300:
		if host.session.snapshot().dialogue.visible:
			check(host.session.navigate("next"),host.session.error)
		elif host.session.can_control():break
		if not _step(host):return
	check(host.session.can_control(),"Flight did not release controls after its briefing")
	check(host._mouse_captured,"Released flight did not capture the configured mouse")
	if failures:return
	for tick in 5:
		if not _step(host):return
	await _verify_exhaust(host)
	if failures:return
	for press in 10:_press(KEY_SLASH)
	var flight: Dictionary=host.session.snapshot()
	print("Target entry: cursor=",flight.campaign_cursor," pose=",flight.player_pose)
	check(flight.get("player_route",{}).is_empty(),"Use an earned post-training save: the active training route intentionally blocks mining acquisition")
	if failures:return
	var first:=await _acquire(host,-1)
	if first<0:return
	await capture("first-asteroid-lock")
	if flight.cargo.free_space>0:
		_press(KEY_F)
		check(host.session.snapshot().mining_approach.phase!="idle","Acquired asteroid could not start a mining approach")
		if failures or not _step(host):return
		_press(KEY_F)
		check(host.session.snapshot().mining_approach.phase=="idle","Mining approach did not cancel")
		if failures:return
	var second:=await _acquire(host,first)
	check(second>=0 and second!=first,"Second acquisition did not select a different asteroid")
	if failures:return
	await capture("second-asteroid-lock")
	for attempt in 2:
		_choose_autopilot(host,"station_autopilot")
		check(host.session.snapshot().station_autopilot.active,"Station guidance did not engage after an asteroid lock")
		if not _step(host):return
		_choose_autopilot(host,"cancel_autopilot")
		check(not host.session.snapshot().station_autopilot.active,"Station guidance did not cancel")
		for press in 10:_press(KEY_SLASH)
		if failures:return
	check(await _acquire(host,second)>=0,"Cancelling station guidance prevented another asteroid lock")
	await capture("reacquired-after-station-guidance")

func _verify_exhaust(host: Control) -> void:
	var state: Dictionary=host.session.snapshot()
	var particles: Node3D=host.session.scene.engine_particles
	check(state.get("engine_particles",{}).get("owners",{}).size()==4 and particles!=null,"Saved Betty flight has no four-nozzle exhaust owner")
	if failures:return
	var counts: Array=particles.frame.get("counts",[])
	check(counts.size()==4 and counts.all(func(value):return int(value)>0),"Saved Betty flight has no visible exhaust populations: "+str(counts))
	if failures or DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw
	var visible: Image=host.viewport.get_texture().get_image()
	particles.hide()
	await process_frame;await RenderingServer.frame_post_draw
	var hidden: Image=host.viewport.get_texture().get_image()
	particles.show()
	var changed:=0
	for y in visible.get_height():
		for x in visible.get_width():
			var a:=visible.get_pixel(x,y);var b:=hidden.get_pixel(x,y)
			if a.r-b.r+a.g-b.g+a.b-b.b>0.08:changed+=1
	check(changed>100,"Exhaust is absent from the saved flight's normal camera: "+str(changed))
	print("Saved Betty flight exhaust pixels: ",changed)
	var directory:=OS.get_environment("GOF2_CAPTURE_DIR")
	if not directory.is_empty():
		DirAccess.make_dir_recursive_absolute(directory)
		check(visible.save_png(directory.path_join("saved-betty-exhaust-visible.png"))==OK,"Could not save visible Betty exhaust")
		check(hidden.save_png(directory.path_join("saved-betty-exhaust-hidden.png"))==OK,"Could not save hidden Betty exhaust comparison")

func _step(host: Control,commands:=Vector2.ZERO) -> bool:
	for line in 12:
		if not host.session.snapshot().dialogue.visible:break
		check(host.session.navigate("next"),host.session.error)
		if failures:return false
	_time+=100000
	host.session.set_pause("focus",false,_time-100000)
	# Feed physical mouse motion through the real input receiver, then sample the
	# same bounded command and relative-camera flag as the host's process loop.
	var input_command:=Vector2.ZERO
	if host._mouse_captured:
		var motion:=InputEventMouseMotion.new()
		motion.screen_relative=Vector2(-commands.y,commands.x)*60.0/host._controls.mouse_sensitivity
		Input.parse_input_event(motion);Input.flush_buffered_events()
		host._controls.advance_mouse(0.1)
		input_command=host._controls.snapshot().command
		check(input_command.is_equal_approx(commands),"Mouse input did not reach the flight controls")
	var controls: Dictionary=host._controls.snapshot()
	check(host.session.step(_time,input_command,controls.held.fire,host._mouse_captured,controls.strafe,controls.held.brake),host.session.error)
	if failures:return false
	host.present_session()
	return true

func _press(key: Key) -> void:
	for down in [true,false]:
		var event:=InputEventKey.new();event.physical_keycode=key;event.pressed=down
		Input.parse_input_event(event);Input.flush_buffered_events()

func _acquire(host: Control,except_index: int) -> int:
	var state: Dictionary=host.session.snapshot()
	var bodies: Array=state.scenery.bodies.objects
	var target:=-1;var best:=-2.0
	for body in bodies:
		if body.index==except_index or body.get("mined",false):continue
		var direction: Vector3=(body.position-state.player_pose.origin).normalized()
		var alignment: float=state.player_pose.basis.z.dot(direction)
		# Turn far enough away from a retained lock to exercise aim-loss reset.
		if except_index>=0 and alignment>0.90:continue
		if alignment>best:target=int(body.index);best=alignment
	check(target>=0,"No distinct generated asteroid is available for reacquisition")
	if failures:return -1
	for tick in 600:
		state=host.session.snapshot()
		var point: Vector3=state.scenery.objects[target].position
		if not _step(host,Pilot.steering_toward(state.player_pose,point)):return -1
		var query: Dictionary=host.session.snapshot().mining_targeting
		if query.selected_object_index>=0 and query.selected_object_index!=except_index:
			print("Acquired asteroid ",query.selected_object_index," after ",tick," frames; elapsed=",query.elapsed_ms)
			return int(query.selected_object_index)
	var last: Dictionary=host.session.snapshot()
	var query: Dictionary=last.mining_targeting.duplicate()
	query.erase("markers")
	print("Failed reacquisition: ",query," phase=",last.phase," dialogue=",last.dialogue," approach=",last.mining_approach.phase," autopilot=",last.station_autopilot.active," scanner=",last.get("npc_scanner",{}).get("found_actor_id",-1))
	check(false,"A second generated asteroid did not acquire after steering into its scan window")
	return -1

func _choose_autopilot(host: Control,action: String) -> void:
	_press(KEY_Q)
	check(host.flight_menu.visible and host.session.is_paused() and not host._mouse_captured,"Q did not open the destination menu and release the pointer")
	if failures:return
	var rows: Array=host.flight_menu.snapshot().rows
	for index in rows.size():
		if rows[index].action==action:
			_press(KEY_1+index)
			check(not host.flight_menu.visible and not host.session.is_paused(),"Destination choice did not resume flight")
			return
	check(false,"Missing Q action "+action)
