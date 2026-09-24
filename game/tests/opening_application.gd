extends SceneTree
## Development launcher integration; player menu entry has its own fixture.
const App = preload("res://src/presentation/development_launcher.gd")
const Session = preload("res://src/presentation/opening_session.gd")
const ArrivalSession = preload("res://src/presentation/arrival_session.gd")
const StationSession = preload("res://src/presentation/station_session.gd")
const TouchInput = preload("res://tests/fixtures/touch_input.gd")
var failures := 0

func _initialize() -> void:
	create_timer(360).timeout.connect(func():push_error("Opening application checks timed out");quit(1))
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected content/bindings/visuals triples")
	for i in range(0,args.size()-2,3):await verify_source(args[i],args[i+1],args[i+2])
	print("Opening application checks: %d failures" % failures)
	quit(1 if failures else 0)

func verify_source(content: String,pack: String,textures: String) -> void:
	var app := App.new();root.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app._open_content(content);app._open_bindings(pack);app._open_visuals(textures)
	app.tabs.current_tab=app.opening_preview.get_index()
	await process_frame
	var preview: Control = app.opening_preview
	preview.set_process(false);preview.start()
	check(preview.session!=null,preview.status.text)
	if preview.session==null:app.free();return
	check(preview.session.escape_sequence==Session.supports_escape(app.bindings),"Application did not select its supported escape capability")
	check(not preview.target_frame.visible and preview.target_frame.prepared==preview.session.interactive,"Frame availability disagrees with the opening capability")
	preview.set_touch_controls(true)
	check(not preview.touch_overlay.visible and not preview.touch_overlay.active,"Initial cinematic showed flight touch actions")
	preview.set_touch_controls(OS.has_feature("mobile"))
	check(not preview._pause_button.visible or OS.has_feature("mobile"),"Desktop opening showed a touch pause action by default")
	check(preview.session.rebase_time(0),preview.session.error)
	var rendered := false
	for frame in 1800:
		resume_fixture_focus(preview,frame*100000)
		check(preview.session.step((frame+1)*100000),preview.session.error)
		var state: Dictionary = preview.session.snapshot()
		check(preview.radio_panel.present(state.radio),preview.radio_panel.error)
		if state.scene.formation_revealed and state.radio.visible:
			check(preview.radio_panel.visible,"Active source radio was hidden")
			check(preview.radio_panel._snapshot.text==app.library.strings[int(state.radio.text_id)],"Application displayed another localization row")
			if not app.bindings.opening_dialogue.get("voice",{}).is_empty():
				var voice: Dictionary=preview.session.audio.snapshot()
				var spoken: Array=voice.history.filter(func(op):return op.get("radio_event")==state.radio.active_event)
				check(voice.voice_displayed[state.radio.active_event] and spoken.size()==1 and spoken[0].source_id==app.bindings.opening_dialogue.voice.event_ids[state.radio.active_event],"Application radio text did not reach its source voice exactly once")
			if DisplayServer.get_name()!="headless":
				await process_frame;await process_frame;await RenderingServer.frame_post_draw
				var image := root.get_texture().get_image()
				var output := OS.get_environment("GOF2_CAPTURE_DIR")
				if not output.is_empty():
					DirAccess.make_dir_recursive_absolute(output)
					check(image.save_png(output.path_join("opening-app-"+app.library.manifest.profile.edition+".png"))==OK,"Application capture failed")
			rendered=true;break
	check(rendered,"Opening application never showed formation and radio together")
	resume_fixture_focus(preview,0)
	var key := InputEventKey.new();key.physical_keycode=KEY_ESCAPE;key.pressed=true
	Input.parse_input_event(key);await process_frame
	check(preview.session.is_paused(),"Escape did not pause the opening")
	key=InputEventKey.new();key.physical_keycode=KEY_ESCAPE;key.pressed=false
	Input.parse_input_event(key);await process_frame
	var button := InputEventJoypadButton.new();button.device=42;button.button_index=JOY_BUTTON_START;button.pressed=true
	Input.parse_input_event(button);await process_frame
	check(not preview.session.is_paused(),"Controller Start did not resume the opening")
	button=InputEventJoypadButton.new();button.device=42;button.button_index=JOY_BUTTON_START;button.pressed=false
	Input.parse_input_event(button);await process_frame
	var before: Dictionary = preview.session.snapshot()
	root.size=Vector2i(900,650)
	await process_frame;await process_frame
	check(preview.session.snapshot()==before,"Window resize changed source radio timing")
	preview._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(preview.session.is_paused(),"Application focus loss did not pause the opening")
	check(preview.session.rebase_time(0) and preview.session.step(100000),preview.session.error)
	check(preview.session.snapshot()==before,"Lost application focus advanced the opening")
	preview._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not preview.session.is_paused(),"Application focus restoration retained its pause")
	check(preview.session.rebase_time(0),preview.session.error)
	var captured_phases := {}
	for frame in 1800:
		resume_fixture_focus(preview,frame*100000)
		check(preview.session.step((frame+1)*100000),preview.session.error)
		var current: Dictionary=preview.session.snapshot()
		if not current.world_frame.is_empty() and current.camera.shot.phase>=3:
			for actor in current.combat.actors:
				check(preview.session.geometry.actors[actor.actor_id].transform==actor.pose,"Live controller pose did not reach application geometry")
			var phase: int=current.camera.shot.phase
			if not captured_phases.has(phase):
				captured_phases[phase]=true
				check(preview.radio_panel.present(current.radio),preview.radio_panel.error)
				if DisplayServer.get_name()!="headless":
					await process_frame;await process_frame;await RenderingServer.frame_post_draw
					var output := OS.get_environment("GOF2_CAPTURE_DIR")
					if not output.is_empty():
						check(root.get_texture().get_image().save_png(output.path_join("opening-live-%s-phase-%d.png" % [app.library.manifest.profile.edition,phase]))==OK,"Live opening capture failed")
		if preview.session.status=="encounter_required" or preview.session.can_control():break
	var boundary: Dictionary = preview.session.snapshot()
	check(preview.session.status==("running" if preview.session.interactive else "encounter_required") and not boundary.radio.started[9],"Application boundary mismatch: status=%s phase=%d elapsed=%d pauses=%s"%[preview.session.status,boundary.camera.shot.phase,boundary.elapsed_ms,str(preview.session._pauses)])
	if not app.bindings.opening_actors.get("npc_initialization",{}).get("activation",{}).is_empty():
		check(boundary.has("combat") and boundary.combat.activated,"Application did not run source NPC activation")
		for actor in boundary.combat.actors:
			check(actor.active and actor.vitals.hull==150,"Application fabricated damage or failed activation")
	if preview.session.interactive:await check_playable(preview,app.library.manifest.profile.edition)
	# Context changes stop the old scene before replacing the mutable libraries.
	app._language_selected(0)
	check(preview.session==null and not preview.radio_panel.visible,"Language change retained the old opening")
	preview.start();check(preview.session!=null,preview.status.text)
	app._open_bindings("")
	check(preview.session==null,"Failed binding replacement retained the old scene")
	app.free()
	root.size=Vector2i(1120,720)
	print("Opening application: ",content.get_file()," launch, radio, input, boundaries, resize and context invalidation verified")

func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)

func resume_fixture_focus(preview: Control, now: int) -> void:
	# Synthetic-time playback must not depend on desktop focus while captures run.
	# Actual notification pause/resume behavior is checked explicitly above.
	if preview._focused:return
	print("Restoring application test focus at synthetic time ",now)
	preview._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(preview.session.rebase_time(now),preview.session.error)

func check_playable(preview: Control, edition: String) -> void:
	resume_fixture_focus(preview,0)
	var session: Node3D=preview.session
	check(session.can_control() and session.projectiles.guns.size()==5 and session.impacts.guns.size()==5,"Application did not join player weapons and feedback")
	var now:=0
	check(session.rebase_time(now),session.error)
	var unchanged: Dictionary=session.snapshot()
	var unchanged_audio:=audio_state(session)
	check(not session.step(100000,Vector2(NAN,0),true) and session.snapshot()==unchanged,"Invalid input changed the application frame")
	check(audio_state(session)==unchanged_audio,"Invalid application input consumed audio state")
	if unchanged.world_frame.has("player_aim"):
		var settings: Dictionary=session._projection._settings
		session._projection._settings={}
		check(not session.step(100000,Vector2.ONE,true) and session.snapshot()==unchanged,"Late presentation failure consumed aim, contact or flight state")
		check(audio_state(session)==unchanged_audio,"Late application presentation failure played or consumed a sound")
		session._projection._settings=settings
		check(session.present(),session.error)
	key_event(KEY_UP,true);key_event(KEY_SPACE,true)
	var input: Dictionary=preview._controls.snapshot()
	check(input.command.x==-1 and input.held.fire,"Keyboard flight commands did not reach the opening")
	check(session.rebase_time(Time.get_ticks_usec()-100000),session.error)
	preview._process(0)
	if preview.session==null:check(false,preview.status.text);return
	check(preview.target_frame.visible,"Application omitted the original target frame in ordinary flight")
	if session.snapshot().world_frame.has("player_aim"):
		check(preview.aim_reticle.visible and preview.aim_reticle.prepared,"Application omitted its ordinary aim reticle")
		var aim: Dictionary=session.snapshot().world_frame.player_aim
		check(preview.aim_reticle.sprite.position+preview.aim_reticle.sprite.size*0.5==Vector2(int(aim.point.x),int(aim.point.y)),"Application reticle is detached from its retained aim")
	if session.snapshot().world_frame.has("npc_scanner"):
		check(preview.npc_markers.visible and preview.npc_markers.prepared,"Application omitted verified NPC markers")
		check(preview.npc_markers._sample==session.snapshot().world_frame.npc_scanner,"Displayed scanner differs from committed frame")
	check(session.rebase_time(now),session.error)
	check(session.snapshot().world_frame.primary_fire.get("weapons",[]).size()==2,"Application fire did not dispatch both equipped primaries")
	check_keyboard_audio(session)
	check(session.snapshot().world_frame.player_flight.angular_units.x<0,"Application input did not retain steering")
	if session.snapshot().world_frame.has("player_engine"):
		var engine: Dictionary=session.snapshot().world_frame.player_engine
		check(engine.initial_source_id==45 and engine.source_id==45 and engine.source_commands==Vector2(-1,0),"Opening loadout or keyboard input selected the wrong engine or command")
	key_event(KEY_UP,false);key_event(KEY_SPACE,false)
	var prior: Transform3D=session.snapshot().scene.player_pose
	now+=100000;check(session.step(now),session.error)
	check(session.snapshot().scene.player_pose.basis!=prior.basis,"Retained application steering did not turn the ship")
	if session.snapshot().world_frame.has("player_engine"):
		var engine: Dictionary=session.snapshot().world_frame.player_engine
		var sound: Dictionary=session.audio.snapshot().active.get("player_engine",{})
		check(engine.parameters==[1.0,0.5,0.0] and engine.source_commands==Vector2.ZERO,"Application engine did not consume the preceding keyboard input")
		check(sound.get("parameter_loop",{}).get("parameters")==engine.parameters and sound.get("position")==engine.position,"Committed engine control or source position missed playback")
	axis_event(JOY_AXIS_LEFT_X,0.8);axis_event(JOY_AXIS_TRIGGER_RIGHT,1.0)
	input=preview._controls.snapshot();check(input.command.y<0 and input.held.fire,"Controller stick/trigger were not routed")
	preview._controller_connection(42,false)
	input=preview._controls.snapshot();check(input.command==Vector2.ZERO and not input.held.fire,"Controller disconnect left held flight input")
	preview._touch_toggle.grab_focus()
	TouchInput.set_preference(preview,true);preview.refresh_render_mode()
	check(preview._touch_toggle.button_pressed and not preview._touch_toggle.has_focus(),"Touch preference or keyboard focus disagrees with flight controls")
	await process_frame
	resume_fixture_focus(preview,now)
	var touch: Control=preview.touch_overlay
	check(touch.visible and touch.active and preview._pause_button.visible,"Touch preference omitted flight actions")
	var stick: Vector2=touch.get_global_transform_with_canvas()*(touch.stick_center()+Vector2(touch.radius()*0.6,0))
	var fire: Vector2=touch.get_global_transform_with_canvas()*touch.fire_center()
	touch_event(3,stick,true);touch_event(4,fire,true)
	input=preview._controls.snapshot();check(input.command.y< -0.5 and input.held.fire,"Simultaneous steering and fire touches were lost: %s, stick=%d, fingers=%s"%[str(input),touch._stick_id,str(touch._fire_ids)])
	now+=100000;check(session.step(now,input.command,input.held.fire),session.error)
	touch_event(3,Vector2.ZERO,false)
	input=preview._controls.snapshot();check(input.command==Vector2.ZERO and input.held.fire,"Releasing steering also released the fire finger: input=%s fingers=%s focus=%s pauses=%s"%[str(input),str(touch._fire_ids),str(preview._focused),str(session._pauses)])
	key_event(KEY_ESCAPE,true)
	check(session.is_paused() and not preview._controls.snapshot().held.fire and not touch.active,"Pause retained a held touch fire")
	var frozen: Dictionary=session.snapshot()
	var frozen_audio:=audio_state(session)
	check(session.step(now+5000000,Vector2.ONE,true) and session.snapshot()==frozen,"Paused application moved or fired")
	check(audio_state(session)==frozen_audio,"Paused application consumed or replayed weapon audio")
	key_event(KEY_ESCAPE,false);key_event(KEY_ESCAPE,true);key_event(KEY_ESCAPE,false)
	check(not session.is_paused(),"Keyboard could not resume the interactive opening: focus=%s pauses=%s"%[str(preview._focused),str(session._pauses)])
	touch_event(4,Vector2.ZERO,false)
	check(not preview._controls.snapshot().held.fire,"Old touch release reactivated fire")
	check(session.rebase_time(now),session.error)
	key_event(KEY_RIGHT,true);key_event(KEY_SPACE,true)
	preview._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(session.is_paused() and preview._controls.snapshot().command==Vector2.ZERO and not preview._controls.snapshot().held.fire,"Focus loss retained flight input")
	preview._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not session.is_paused(),"Focus restore retained its interactive pause")
	key_event(KEY_RIGHT,false);key_event(KEY_SPACE,false)
	check(session.rebase_time(now),session.error)
	key_event(KEY_LEFT,true);key_event(KEY_SPACE,true)
	preview.hide()
	check(session.is_paused() and preview._controls.snapshot().command==Vector2.ZERO and not preview._controls.snapshot().held.fire,"Hidden opening retained held input")
	preview.show()
	check(not session.is_paused(),"Visible opening retained the hidden pause")
	key_event(KEY_LEFT,false);key_event(KEY_SPACE,false)
	check(session.rebase_time(now),session.error)
	preview.refresh_render_mode()
	if session.snapshot().world_frame.has("player_aim"):
		# The fixture drives the session explicitly with preview processing off.
		# Refresh its HUD from the same final sample before taking a flight capture.
		for frame in 40:
			now+=100000
			check(session.step(now),session.error)
		var aim: Dictionary=session.snapshot().world_frame.player_aim
		check(preview.aim_reticle.present(aim),preview.aim_reticle.error)
		check(aim.point.x>=0 and aim.point.y>=0 and aim.point.x<preview.viewport.size.x and aim.point.y<preview.viewport.size.y,"Settled forward aim did not meet the visible flight viewport: %s"%str(aim))
	check(preview.radio_panel.present(session.snapshot().radio),preview.radio_panel.error)
	if DisplayServer.get_name()!="headless":
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		var output:=OS.get_environment("GOF2_CAPTURE_DIR")
		if not output.is_empty():check(root.get_texture().get_image().save_png(output.path_join("opening-controls-"+edition+".png"))==OK,"Interactive controls capture failed")
	resume_fixture_focus(preview,now)
	preview.set_touch_controls(false)
	check(not touch.visible and not preview._pause_button.visible and not preview._controls.snapshot().held.fire,"Hiding touch controls retained a flight action")
	check(preview.target_frame.visible,"Touch preference hid the flight target frame")
	if session.snapshot().world_frame.has("player_aim"):check(preview.aim_reticle.visible,"Touch preference hid the aiming reticle")
	await check_boundaries(preview,edition)
	preview.reset();check(not touch.active and not preview._controls.snapshot().held.fire,"Stopping retained active controls")
	check(not preview.target_frame.visible and not preview.target_frame.prepared,"Stopping retained the target frame")

func audio_state(session: Node3D) -> Dictionary:
	if session.audio==null:return {}
	# Hardware playback cursors can advance between frames. Check only committed
	# event ownership and selection, which a rejected or paused frame must preserve.
	var state: Dictionary=session.audio.snapshot()
	var result:={"revision":state.revision,"history":state.history,"random_state":state.random_state,"voice_displayed":state.voice_displayed}
	var engine: Dictionary=state.active.get("player_engine",{})
	if not engine.is_empty():result.engine={"position":engine.position,"parameters":engine.get("parameter_loop",{}).get("parameters",[]),"generation":state.engine_generation,"source_id":state.engine_id}
	return result

func check_keyboard_audio(session: Node3D) -> void:
	var rows: Array=session.snapshot().world_frame.primary_fire.get("weapons",[])
	if rows.is_empty() or not rows[0].has("audio_events"):return
	check(rows.size()==2 and rows[0].result.fired and rows[1].result.fired,"Keyboard fire did not launch both source weapons")
	check(rows[0].slot==1 and rows[0].audio_events.size()==1 and rows[1].audio_events.is_empty(),"Keyboard fire did not retain the source duplicate-gun sound selection")
	if rows[0].audio_events.size()!=1 or session.audio==null:return
	var cue: Dictionary=rows[0].audio_events[0]
	var state: Dictionary=session.audio.snapshot()
	var played: Array=state.history.filter(func(op):return op.revision==state.revision and op.has("mount_id"))
	check(played.size()==1,"Application committed duplicate or missing primary sounds")
	if played.size()==1:
		check(played[0].source_id==54 and played[0].mount_id==rows[0].mount_id and played[0].position==cue.position and played[0].pitch_raw==cue.pitch_raw,"Application sound differs from its committed weapon launch")
	check(state.active.has(54) and state.unsupported.is_empty(),"Keyboard firing did not produce a playable original weapon sound")
	print("Application weapon audio: keyboard launch, duplicate selection and accepted-frame playback verified")

func check_boundaries(preview: Control, edition: String) -> void:
	var session: Node3D=preview.session
	# Controlled contacts test the scene's transition ownership, not player skill.
	var saved:={"clock":session._clock,"timeline":session._timeline,"world":session._world_frame,"scenery":session._scenery}
	var frame: RefCounted=session._world_frame.fork_for_frame()
	frame._player_state._state.vitals={"hull":1,"armor":0,"shield":0.0}
	var gun: RefCounted=frame._weapons._guns[0]
	for shot in gun.snapshot().slots:
		if shot!=null:check(gun.retire(shot.id),gun.error)
	gun._elapsed_ms=int(gun.snapshot().weapon.interval_ms)+1
	check(gun.fire(session.snapshot().scene.player_pose.origin,Vector3.BACK,true).get("fired",false),gun.error)
	session._world_frame=frame
	check(session.rebase_time(0) and session.step(0),session.error)
	check(session.status=="player_death_required" and not session.can_control(),"Scene did not stop at the unsupported player-death transition")
	var frozen: Dictionary=session.snapshot()
	check(session.step(10000000,Vector2.ONE,true) and session.snapshot()==frozen,"Player-death boundary advanced or accepted fire")
	session._clock=saved.clock;session._timeline=saved.timeline;session._world_frame=saved.world;session._scenery=saved.scenery;session.status="running"
	check(session.present(),session.error)
	complete_encounter_fixture(session)
	if failures:return
	var now:=100000
	var phases:={};var paused_escape:=false;var radio_during_escape:=false
	preview.set_touch_controls(true)
	for tick in 5000:
		if session.status!="running":break
		now+=100000
		if not session.step(now):check(false,session.error);break
		preview.present_session()
		if preview.session==null:check(false,preview.status.text);return
		var state: Dictionary=session.snapshot();var phase:=int(state.camera.shot.phase)
		if phase>4:
			check(not session.can_control() and not session.flight_hud_visible(),"Escape restored flight input or HUD")
			check(not preview.target_frame.visible and not preview.aim_reticle.visible and not preview.npc_markers.visible,"Escape retained a combat overlay")
			check(not preview.touch_overlay.visible and not preview.touch_overlay.active and preview._controls.snapshot().command==Vector2.ZERO and not preview._controls.snapshot().held.fire,"Escape retained touch flight actions")
			if state.radio.visible:radio_during_escape=true;check(preview.radio_panel.visible,"Hidden flight HUD also hid timed radio")
			if not paused_escape:
				paused_escape=true
				key_event(KEY_ESCAPE,true);key_event(KEY_ESCAPE,false)
				check(session.is_paused(),"Escape cinematic lost its keyboard pause shortcut")
				var held: Dictionary=session.snapshot();var held_audio:=audio_state(session)
				check(session.step(now+9000000) and session.snapshot()==held and audio_state(session)==held_audio,"Paused escape advanced source state or audio")
				key_event(KEY_ESCAPE,true);key_event(KEY_ESCAPE,false)
				check(not session.is_paused() and session.rebase_time(now),"Escape cinematic did not resume")
			if phase in [5,7,12,16] and not phases.has(phase):
				phases[phase]=true
				if DisplayServer.get_name()!="headless":
					await process_frame;await process_frame;await RenderingServer.frame_post_draw
					var output:=OS.get_environment("GOF2_CAPTURE_DIR")
					if not output.is_empty():check(root.get_texture().get_image().save_png(output.path_join("opening-app-%s-escape-%d.png"%[edition,phase]))==OK,"Application escape capture failed")
				resume_fixture_focus(preview,now)
	if session.escape_sequence:
		check(session.status=="arrival_transition_required" and session.snapshot().radio.finished.all(func(value):return value),"Application did not reach arrival after all original radio")
		check(paused_escape and radio_during_escape and phases.size()==4,"Application escape omitted HUD, radio, pause or phase coverage")
		check(session.snapshot().fade.alpha_byte==255 and preview.status.text.contains("arrival scene"),"Arrival lost the final black plate or displayed an unrelated boundary message")
		if not preview.bindings.opening_handoff.is_empty():
			var catalogues:=preload("res://src/content/catalogues.gd").new()
			check(catalogues.open(preview.library),catalogues.error)
			var previous: Dictionary=session.snapshot()
			var handoff: Dictionary=session.prepare_arrival(preview.bindings,catalogues)
			check(not handoff.is_empty(),session.error)
			if not handoff.is_empty():
				check(handoff.progress.rank==1 and handoff.progress.rank_score==10 and handoff.progress.player_kills==3 and handoff.progress.pirate_kills==3,"Live Opening failed to retain its earned counters and rescue rank")
				check(handoff.player.vitals.hull==200 and handoff.player_cache.campaign_cursor==1 and not handoff.rescue_disposition.actor_hostile,"Live Opening failed to prepare its restored rescue player and neutral actor")
				check(session.prepare_arrival(preview.bindings,catalogues)==handoff and session.snapshot()==previous,"Preparing live entry changed the Opening or repeated an award")
		if DisplayServer.get_name()!="headless":
			await process_frame;await process_frame;await RenderingServer.frame_post_draw
			var output:=OS.get_environment("GOF2_CAPTURE_DIR")
			if not output.is_empty():check(root.get_texture().get_image().save_png(output.path_join("opening-app-%s-arrival-boundary.png"%edition))==OK,"Application arrival capture failed")
	else:
		check(session.status=="mission_transition_required" and session.snapshot().radio.finished[10],"Scene did not retain the legacy postcombat radio boundary")
		check(session.snapshot().radio.started.slice(11).all(func(value):return not value),"Legacy scene advanced unsupported mission radio")
	frozen=session.snapshot()
	check(session.step(now+10000000,Vector2.ONE,true) and session.snapshot()==frozen,"Unimplemented scene transition advanced mission state")
	if session.status=="arrival_transition_required" and not preview.bindings.arrival_session.is_empty():
		# Loading failure must preserve the completed world, its final black plate
		# and its audio listener; the same committed state can be retried.
		var old_panel: Control=preview.radio_panel
		check(not preview.enter_arrival(now,"invalid fixture seed") and preview.session==session and session.snapshot()==frozen and preview.radio_panel==old_panel,"Failed rescue preparation consumed the Opening")
		check(preview.viewport.get_camera_3d()==session.camera and preview.viewport.is_audio_listener_3d(),"Rejected rescue preparation lost the old camera/listener")
		preview._transition_failed=false
		preview._process(0)
		check(preview.session!=null and preview.session is ArrivalSession,"Application did not automatically enter the rescue: "+preview.status.text)
		if preview.session==null or preview.session is Session:return
		session=preview.session
		check(not is_instance_valid(old_panel) and preview.radio_panel._identity.campaign_cursor==1 and preview.viewport.is_audio_listener_3d(),"Scene replacement retained old radio or lost audio listener ownership")
		check(session.snapshot().elapsed_ms==0 and session.snapshot().world_frame.progress.rank_score==10,"Loading consumed rescue time or lost earned Opening progress")
		now=0;resume_fixture_focus(preview,now);check(session.rebase_time(now),session.error)
		var rescue_before: Dictionary=session.snapshot()
		key_event(KEY_ESCAPE,true);key_event(KEY_ESCAPE,false)
		check(session.is_paused() and session.step(10000000) and session.snapshot()==rescue_before,"Keyboard pause failed in rescue")
		key_event(KEY_ESCAPE,true);key_event(KEY_ESCAPE,false)
		check(not session.is_paused() and session.rebase_time(now),session.error)
		preview.set_touch_controls(true)
		check(not preview.touch_overlay.visible and not preview.target_frame.visible and not preview.aim_reticle.visible and not preview.npc_markers.visible,"Rescue retained flight controls or HUD")
		preview.set_touch_controls(OS.has_feature("mobile"))
		var seen:={}
		for i in 550:
			now+=100000
			check(session.step(now),session.error);preview.present_session()
			var rescue: Dictionary=session.snapshot()
			if rescue.radio.visible:seen[rescue.radio.active_event]=true
			if session.status=="station_transition_required":break
		check(seen.size()==3 and session.status=="station_transition_required" and preview.status.text.contains("Station entry"),"Application failed rescue playback through the station boundary")
		var final_state: Dictionary=session.snapshot()
		check(final_state.fade.alpha_byte==255 and final_state.world_frame.progress.rank_score==10 and final_state.world_frame.player.vitals.hull==200,"Rescue changed progression/player state or lost its final fade")
		check(session.step(now+10000000) and session.snapshot()==final_state,"Station boundary advanced unsupported progression")
		if StationSession.supported(preview.bindings):
			preview._process(0)
			check(preview.session is StationSession,"Application did not automatically enter the first station: "+preview.status.text)
			if not preview.session is StationSession:return
			session=preview.session
			check(session.snapshot().progress.rank_score==10 and session.snapshot().campaign_cursor==1,"Station loading changed earned progress")
			resume_fixture_focus(preview,0);session.rebase_time(0)
			for i in 10:check(session.step((i+1)*100000),session.error)
			preview.present_session()
			check(preview.station_panel.visible and not preview.radio_panel.visible and not preview.touch_overlay.visible,"Station conversation retained flight UI")
			for i in 19:
				check(session.snapshot().dialogue.index==i and session.snapshot().campaign_cursor==1,"Application skipped an acknowledged station line")
				key_event(KEY_ENTER,true);key_event(KEY_ENTER,false)
			check(session.snapshot().campaign_cursor==2 and session.snapshot().progress.rank_score==11 and session.snapshot().reward_credits==0 and not session.snapshot().mining_completed,"Application station completion lost rank or invented mining success")

# Flush injected input before reading it; explicit focus/hidden checks above own
# their interruption points. Render awaits occur outside held-input assertions.
## Shared controlled-contact fixture; this is not a freshly earned save.
func complete_encounter_fixture(session: Node3D) -> void:
	var frame: RefCounted=session._world_frame.fork_for_frame()
	var timeline: RefCounted=session._timeline.fork_for_frame();var combat: RefCounted=timeline.combat_owner()
	for actor in combat.snapshot().actors:
		check(not combat.normal_hit(actor.actor_id,actor.vitals.hull-1).is_empty(),combat.error)
	check(timeline.adopt_contact_pass(combat),timeline.error)
	var gun: RefCounted=frame._primaries._guns[0].projectiles
	for shot in gun.snapshot().slots:
		if shot!=null:check(gun.retire(shot.id),gun.error)
	for actor in combat.snapshot().actors:
		gun._elapsed_ms=int(gun.snapshot().weapon.interval_ms)+1
		check(gun.fire(actor.pose.origin,Vector3.BACK,true).get("fired",false),gun.error)
	session._world_frame=frame;session._timeline=timeline
	check(session.rebase_time(0) and session.step(100000),session.error)
	check(session.snapshot().world_frame.controller.death_accounting.counter_deltas.player_kills==3,"Scene lost controlled primary kill credit")

func key_event(key: int, pressed: bool) -> void:
	var event:=InputEventKey.new();event.physical_keycode=key;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()
func axis_event(axis: int, value: float) -> void:
	var event:=InputEventJoypadMotion.new();event.device=42;event.axis=axis;event.axis_value=value
	Input.parse_input_event(event);Input.flush_buffered_events()
func touch_event(id: int, point: Vector2, pressed: bool) -> void:
	var event:=InputEventScreenTouch.new();event.index=id;event.position=root.get_final_transform()*point;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()
