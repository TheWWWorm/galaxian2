extends "res://tests/opening_application.gd"
## Skip only passive scenes; the shared controlled-contact fixture isolates the
## earned escape boundary without manufacturing a save or skipping combat.

func verify_source(content: String,pack: String,textures: String) -> void:
	var app:=App.new();root.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app._open_content(content);app._open_bindings(pack);app._open_visuals(textures)
	app.tabs.current_tab=app.opening_preview.get_index();await process_frame
	var preview: Control=app.opening_preview
	preview.set_process(false);preview.set_player_mode(true);preview.start()
	if preview.session==null:check(false,preview.status.text);app.free();return
	var session: Node3D=preview.session
	resume_fixture_focus(preview,0);preview.present_session()
	check(session.can_skip_cinematic() and preview._flight_hint.visible and "Skip cinematic" in preview._flight_hint.text,"Fresh cinematic omitted its desktop skip hint")
	check(not preview._skip_button.visible,"Desktop cinematic ignored the touch-controls preference")
	check(not preview.flight_vitals.visible,"Intro cinematic showed ordinary flight gauges")
	await capture(preview,"opening-skip-desktop")
	key_event(KEY_ENTER,true);Input.flush_buffered_events();key_event(KEY_ENTER,false);Input.flush_buffered_events()
	check(session.cinematic_skipping() and session.audio.snapshot().paused,"Keyboard skip did not begin a muted source sequence")
	var now:=0
	for tick in 300:
		if not session.cinematic_skipping():break
		now+=16667
		if not session.step(now):check(false,session.error);app.free();return
	check(session.can_control() and not session.can_skip_cinematic(),"Intro skip crossed or failed to reach ordinary flight")
	check(session.snapshot().world_frame.controller.death_accounting.counter_deltas.player_kills==0,"Intro skip granted combat progress")
	if failures:app.free();return
	now+=100000
	if not session.step(now):check(false,session.error);app.free();return
	preview.present_session()
	check(preview.flight_vitals.visible and preview.flight_vitals._armor_visible and preview.flight_vitals._shield_visible,"Opening fight omitted its accepted armor/shield gauges")
	check(not preview.flight_vitals._cargo_frame.visible and not preview.flight_vitals._hull_text.visible,"Opening fight exposed absent cargo or its scripted hull reserve")
	await capture(preview,"opening-flight-controls",now)
	var before: Dictionary=session.snapshot()
	check(not session.request_cinematic_skip() and session.snapshot()==before,"Skip accepted the live fight")
	complete_encounter_fixture(session)
	if failures:app.free();return
	now=100000
	for tick in 1200:
		if session.can_skip_cinematic():break
		now+=100000
		if not session.step(now):check(false,session.error);app.free();return
	check(session.can_skip_cinematic() and session.snapshot().world_frame.controller.death_accounting.counter_deltas.player_kills==3,"Completed fight did not enter its source escape cinematic")
	TouchInput.set_preference(preview,true);preview.present_session()
	check(not preview.flight_vitals.visible,"Escape cinematic retained ordinary flight gauges")
	check(preview._skip_button.visible and preview._skip_button.size.y>=44,"Landscape touch layout omitted its skip action")
	await capture(preview,"opening-skip-touch",now)
	preview._skip_button.pressed.emit()
	check(session.cinematic_skipping(),"Touch skip did not use the native cinematic owner")
	check(session.set_pause("focus",true,now),session.error)
	before=session.snapshot()
	check(session.step(now+9000000) and session.snapshot()==before and session.audio.snapshot().paused,"Focus loss advanced a skipped cinematic")
	check(session.set_pause("focus",false,now),session.error)
	var close_view_captured:=false
	for tick in 300:
		if not session.cinematic_skipping():break
		now+=16667
		if not session.step(now):check(false,session.error);app.free();return
		if not close_view_captured and session.snapshot().camera.shot.phase in [12,13,14,15]:
			await capture(preview,"opening-escape-close",now)
			close_view_captured=true
	check(session.status=="arrival_transition_required" and not session.cinematic_skipping(),"Escape skip did not stop at the original rescue boundary")
	var state: Dictionary=session.snapshot()
	check(state.world_frame.controller.death_accounting.counter_deltas.player_kills==3,"Escape skip added kills or lost accepted combat progress")
	check(state.radio.finished.slice(10,23).all(func(done):return done),"Escape skip bypassed original radio dependencies")
	before=session.snapshot()
	check(session.step(now+100000) and session.snapshot()==before,"Skipped boundary kept simulating")
	app.free()

func capture(preview: Control,name: String,now: int=0) -> void:
	var directory:=OS.get_environment("GOF2_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name()=="headless":return
	preview.present_session()
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(directory)
	check(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Could not capture "+name)
	resume_fixture_focus(preview,now)
