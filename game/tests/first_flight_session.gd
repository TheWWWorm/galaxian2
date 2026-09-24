extends SceneTree
## App launch, mining input, speech and return. Asteroid placement and a retained
## fresh asteroid positions isolate controls; the successful trip earns and delivers cargo.
const Host=preload("res://src/presentation/opening_preview.gd")
const TouchInput=preload("res://tests/fixtures/touch_input.gd")
const Trip=preload("res://src/presentation/first_flight_session.gd")
const Station=preload("res://src/presentation/station_session.gd")
const Arrival=preload("res://src/simulation/arrival_world_frame.gd")
const Handoff=preload("res://src/simulation/opening_handoff.gd")
const Fixture=preload("res://tests/opening_handoff_fixture.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Aim=preload("res://src/simulation/opening_aim.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Archive=preload("res://src/simulation/station_archive.gd")
const SaveFile=preload("res://src/simulation/station_save_file.gd")
var checks:=0
var failures:=0
var host: Control
var now_us:=0
var lib:=Library.new()
var bindings:=Bindings.new()
var visuals:=Visuals.new()
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	if args.size()==3 and DisplayServer.get_name()!="headless" and not OS.get_environment("GOF2_CAPTURE_DIR").is_empty():args.append(OS.get_environment("GOF2_CAPTURE_DIR"))
	check(args.size() in [3,4],"Expected Mac content, bindings, visuals and optional captures")
	if args.size() in [3,4]:await verify(args)
	if is_instance_valid(host):host.free()
	print("First flight session: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not lib.select_language("gb") or not cat.open(lib) or not visuals.open(args[2],lib.manifest):check(false,lib.error+bindings.error+cat.error+visuals.error);return
	if bindings.station_return.is_empty():check(not Trip.supported(bindings),"Legacy pack offered an incomplete mining trip");return
	var player:=Player.new();var handoff:=Handoff.new();check(player.configure(bindings,cat),player.error)
	root.size=Vector2i(1280,720)
	host=Host.new();root.add_child(host);host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.set_context(lib,bindings,visuals);host.set_process(false)
	for i in 3:await process_frame
	await restore_test_focus()
	# Enter through the real rescue session so the first station's hidden stock
	# and contacts are retained throughout both mining trips and the equipment
	# prerequisite. Only the preceding three opening kills are a fixture.
	var arrival: Node3D=load("res://src/presentation/arrival_session.gd").new()
	host.viewport.add_child(arrival);host.session=arrival
	if not arrival.configure(lib,bindings,visuals,handoff.prepare(bindings,cat,Fixture.completed(bindings,player,3)),0,1789100000):check(false,arrival.error);return
	for i in 500:
		if arrival.status!="running":break
		if not arrival.step((i+1)*100000):check(false,arrival.error);return
	if not host.enter_station(60000000,42):check(false,host.status.text);return
	var station: Node=host.session;station.rebase_time(0)
	# Exercise the same focus recovery used after capture windows. User pause must
	# survive it; only the operating-system focus reason may be cleared.
	host._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	station.set_pause("user",true,0)
	await restore_test_focus()
	check(host._focused and station.is_paused(),"Restoring test focus lost a deliberate user pause")
	station.set_pause("user",false,0);station.rebase_time(0)
	check(not host.request_departure(),"Unacknowledged station offered launch")
	for i in 10:station.step((i+1)*100000)
	for i in 18:key(KEY_ENTER)
	var instruction: Dictionary=station.snapshot()
	check(instruction.campaign_cursor==1 and instruction.dialogue.index==18 and instruction.dialogue.text_id==int(bindings.station_entry.dialogue.events[-1].text_id) and instruction.dialogue.visible,"The first station omitted its final silent instruction")
	check(station.audio._clips.size()==19 and station.audio._clips[18]==null and station.audio._player==null,"The first station's silent instruction lost its real speech slot")
	check(station.audio.valid_line(18) and not station.audio.valid_line(19),"Initial speech accepted a phantom page or rejected its actual instruction")
	key(KEY_LEFT)
	check(station.snapshot().dialogue.index==17 and station.audio._player!=null,"Previous navigation from the silent instruction did not replay its preceding voice")
	key(KEY_ENTER)
	check(station.snapshot().campaign_cursor==1 and station.audio._player==null,"Returning to the silent instruction acknowledged it or kept speech playing")
	key(KEY_ENTER)
	host.present_session()
	var before: Dictionary=station.snapshot()
	check(before.campaign_cursor==2 and host._launch_button.visible and not host._pause_button.visible,"Ready station lacked launch or exposed desktop touch actions")
	check(host.request_departure() and host._launch_dialog.visible and host._launch_dialog.snapshot().text==lib.strings[386],"Launch omitted the original confirmation")
	host.cancel_departure()
	check(station.snapshot()==before and not host._launch_dialog.visible and not host.enter_first_flight(0),"Cancelled/unconfirmed launch changed the station")
	var textures: Dictionary=visuals.textures;visuals.textures={}
	check(host.request_departure() and not host.enter_first_flight(0,4096,1789100000),"Missing textures replaced the station")
	check(host.session==station and station.snapshot()==before and is_instance_valid(station.camera),"Failed launch destroyed the accepted station")
	visuals.textures=textures
	check(host._retry_button.visible and host.retry_transition() and host.enter_first_flight(0,4096,1789100000),host.status.text)
	if not host.session is Trip:return
	check(not is_instance_valid(station) and not host.station_panel.visible and not host.radio_panel.visible and not host._launch_button.visible,"Launch retained the old station scene/UI")
	host.session.rebase_time(0);now_us=0
	check(not host.session.can_control() and not host._flight_actions.visible and host.session.briefing_audio.snapshot().history.is_empty(),"Loading enabled flight input or started speech")
	for i in 130:
		if not step():return
	var modal: Dictionary=host.session.snapshot()
	check(modal.phase=="briefing" and modal.dialogue.visible and not host.session.can_control(),"First-flight entry did not open its modal briefing")
	check(host.session.briefing_audio.snapshot().history[0].source_id==int(bindings.mining_briefing.events[0].voice_event_id),"Wrong first-flight recording")
	for i in 20:step()
	var waited: Dictionary=host.session.snapshot()
	var expected_modal:=modal.duplicate(true);expected_modal.session_generation=waited.session_generation
	if modal.has("flight_audio"):expected_modal.flight_audio.serial=int(modal.flight_audio.serial)+20
	check(waited==expected_modal and waited.session_generation>modal.session_generation,"Modal world visits advanced clocks or auto-acknowledged the briefing")
	modal=waited
	key(KEY_UP)
	check(host._controls.snapshot().command==Vector2.ZERO,"Modal instruction accepted steering")
	key(KEY_ESCAPE);check(host.session.is_paused() and host.session.briefing_audio._player.stream_paused,"Keyboard pause did not stop briefing speech")
	key(KEY_ENTER);check(host.session.snapshot()==modal,"Paused Enter acknowledged briefing")
	key(KEY_ESCAPE);host.session.rebase_time(now_us)
	key(KEY_ENTER);key(KEY_LEFT)
	check(host.session.snapshot().dialogue.index==0 and host.session.briefing_audio.snapshot().history.size()==3,"Briefing back navigation lost voice replay")
	if args.size()==4:await capture(args[3],"app-mining-briefing")
	for i in 5:button(JOY_BUTTON_A)
	check(host.session.can_control() and not host.session.snapshot().dialogue.visible and host.session.briefing_audio._player==null,"Controller acknowledgement did not release flight and stop speech")
	var held: Dictionary=host.session.snapshot()
	for reason in ["user","focus","hidden"]:
		host.session.set_pause(reason,true,now_us);step()
		check(host.session.snapshot()==held and not host.session.action("autopilot"),"Pause advanced flight or accepted an action: "+reason)
		host.session.set_pause(reason,false,now_us)
	key_down(KEY_UP);step();step();key_up(KEY_UP)
	check(host.session.snapshot().angular_units.x<0 and host.session.snapshot().player_pose!=held.player_pose,"Keyboard steering did not reach the live frame")
	if not bindings.ordinary_music.is_empty():
		var music: Dictionary=host.session.flight_audio.snapshot()
		check(bindings.ordinary_music.faction_event_ids.any(func(id):return int(id)==music.music_id) and music.active.has(music.music_id),"Accepted exploration flight did not play its source faction cue")
	key(KEY_SLASH);check(is_equal_approx(host.session.snapshot().input_throttle,.9),"Throttle key did not reach flight")
	button(JOY_BUTTON_Y);key(KEY_2)
	check(host.session.snapshot().station_autopilot.active and host.session.snapshot().input_throttle==1,"Controller station selection did not restore cruise throttle")
	key(KEY_Q);key(KEY_1);check(not host.session.snapshot().station_autopilot.active,"Keyboard station cancellation failed")
	TouchInput.set_preference(host,true)
	check(host._pause_button.visible and host._flight_actions.visible and host.touch_overlay.visible,"Enabled touch controls were missing")
	host.set_touch_controls(false)
	check(not host._pause_button.visible and not host._flight_actions.visible and not host.touch_overlay.visible,"Desktop hid only some flight action buttons")
	var accepted: Dictionary=host.session.snapshot();var voices: Dictionary=host.session.briefing_audio.snapshot()
	var identity: Dictionary=host.session.scene.dialogue._identity.duplicate(true)
	host.session.scene.dialogue._identity.binding_id="foreign"
	check(not host.session.step(now_us+100000) and host.session.snapshot()==accepted and host.session.briefing_audio.snapshot()==voices,"Rejected rendering committed world or speech")
	host.session.scene.dialogue._identity=identity;check(host.session.scene.present(host.session.flight_owner()),host.session.scene.error)
	if not await mine_trip(args):return
	var trip: Node=host.session;var arrival_state: Dictionary=trip.snapshot()
	check(trip.status=="station_transition_required" and arrival_state.cargo.used==25 and arrival_state.campaign_cursor==3,"Live trip did not reach the cargo-preserving station boundary")
	textures=visuals.textures;visuals.textures={}
	check(not host.enter_station(now_us,42) and host.session==trip and trip.snapshot()==arrival_state,"Failed return replaced or changed flight")
	visuals.textures=textures
	check(host._retry_button.visible and host.retry_transition(),host.status.text)
	if not host.session is Station:return
	check(not is_instance_valid(trip) and host.session.snapshot().cargo==arrival_state.cargo and not host.touch_overlay.visible,"Station return lost cargo or retained its flight UI")
	host.session.rebase_time(now_us)
	for i in 10:step()
	check(host.session.audio.snapshot().history[0].source_id==411,"Application return started the wrong recording")
	if args.size()==4:await capture(args[3],"app-station-return")
	for i in 5:key(KEY_ENTER)
	var second_supported: bool=Trip.supported(bindings,4)
	check(host.session.snapshot().campaign_cursor==4 and host.session.snapshot().cargo.used==0 and host._launch_button.visible==second_supported and host.request_departure()==second_supported,"Application second departure disagreed with its capabilities or acknowledged cargo reset")
	host.cancel_departure()
	check(host.session.snapshot().reward_credits==0 and not host.session.snapshot().mining_completed,"Application granted an unearned reward or tutorial completion")
	verify_mining_history_save()
	await after_first_return(args)
	host.reset();check(host.session==null and not host._launch_dialog.visible and not host._flight_actions.visible,"Reset retained a flight scene or action overlay")

func after_first_return(_args: PackedStringArray):pass

func verify_mining_history_save():
	if not bindings.mining_session.has("failure_instruction"):return
	var seen: bool=not bindings.mining_session.failure_instruction.repeat_each_drill
	var owner: RefCounted=host.session.station_owner()
	check(owner.snapshot().progress.get("mining_failure_hint_seen")==seen,"The returned station lost source-specific instruction history")
	var archive:=Archive.new();var cat:=Catalogues.new();check(cat.open(lib),cat.error)
	if not Archive.available(bindings):
		# Partial development packs lack the retained stock/contact declarations.
		# Keep that save boundary explicit; complete packs still run every round-trip check below.
		var held: Dictionary=owner.snapshot()
		var next_departure: Dictionary=owner.prepare_departure(bindings,cat)
		check(not next_departure.is_empty() and next_departure.progress.get("mining_failure_hint_seen")==seen,"The next departure forgot its source-specific mining instruction history")
		check(archive.capture(owner,bindings,host.session.location_owner()).is_empty() and not archive.error.is_empty(),"A partial pack invented a save without retained station stock and contacts")
		check(archive.restore(bindings,cat,lib,{})==null and owner.snapshot()==held,"A partial pack restored an unsupported save or changed its station")
		return
	var saved: Dictionary=archive.capture(owner,bindings,host.session.location_owner())
	var restored: RefCounted=archive.restore(bindings,cat,lib,saved)
	check(not saved.is_empty() and restored!=null,archive.error)
	if restored==null:return
	check(restored.snapshot().progress==owner.snapshot().progress,"Saving changed earned instruction history or career counters")
	var departure: Dictionary=restored.prepare_departure(bindings,cat)
	check(not departure.is_empty() and departure.progress.get("mining_failure_hint_seen")==seen,"The next departure forgot a shown mining instruction")
	var directory:=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	if not directory.is_empty():
		var file:=SaveFile.new();var path:=SaveFile.path_for(directory.path_join("mining-hint"),bindings)
		check(file.save(path,owner,bindings,cat,lib,host.session.location_owner()),file.error)
		var document:=file.load_document(path,bindings,cat,lib)
		check(document==saved,"Disk save/load changed the earned mining instruction flag")
	for invalid in [1,"true",null]:
		var broken: Dictionary=saved.duplicate(true);broken.station.progress.mining_failure_hint_seen=invalid
		check(archive.restore(bindings,cat,lib,broken)==null,"A malformed instruction flag was loaded")

func restore_test_focus() -> void:
	if DisplayServer.get_name()!="headless":
		root.grab_focus()
		for i in 3:await process_frame
	# Headless runs have no window-manager focus event. GPU runs explicitly send
	# the same event after focus settles; input still goes through the real host.
	if not host._focused:host._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)

func mine_trip(args: PackedStringArray) -> bool:
	var flight: RefCounted=host.session.flight_owner();var asteroid:={}
	for body in flight.snapshot().scenery.bodies.objects:
		if body.source_size_value==7:asteroid=body;break
	if asteroid.is_empty():check(false,"No source core asteroid for live input verification");return false
	# Explicit close-placement/selected-target fixture; source acquisition and
	# long approach have separate coverage. This session still owns all drilling.
	place_for_mining(flight,asteroid)
	if not host.session._commit(flight,false):check(false,host.session.error);return false
	key_down(KEY_F);var selected: Dictionary=host.session.snapshot();key_down(KEY_F)
	check(selected.mining_approach.phase!="idle" and host.session.snapshot()==selected,"Held mining key cancelled its own approach")
	key_up(KEY_F)
	# The shared action release now resets Fast Forward/camera response. It must
	# leave the approach and every other gameplay owner unchanged.
	var released: Dictionary=host.session.snapshot();var retained:=selected.duplicate(true)
	for data in [released,retained]:
		data.erase("fast_forward");data.erase("session_generation")
	check(released==retained,"Mining action release changed retained gameplay")
	for i in 200:
		if not step():return false
		if not host.session.snapshot().mining_session.drill.is_empty():break
	if host.session.snapshot().mining_session.drill.is_empty():check(false,"Live input never reached drilling");return false
	TouchInput.set_preference(host,true);host.present_session()
	if args.size()==4:await capture(args[3],"app-mining-touch")
	var touch: Control=host.touch_overlay
	var point: Vector2=touch.get_global_transform_with_canvas()*touch.fire_center()
	var pressed: bool=touch.press(37,point)
	check(pressed,"Touch mining button rejected its pointer")
	if not pressed:return false
	host.handle_actions(host._controls.take_pressed());touch.release(37)
	check(host.session.snapshot().mining_session.drill.is_empty() and host.session.snapshot().cargo.used==0,"Touch stop failed to commit a zero-ore cancellation")
	check(host.session.snapshot().scenery.mined_count==1,"Manual stop did not retire its actual asteroid")
	host.set_touch_controls(false)
	if not begin_next_core_drill():return false
	var failures_to_mine:=2 if bindings.mining_session.has("failure_instruction") else 0
	for attempt in failures_to_mine:
		for i in 200:
			if not step(Vector2.ONE):return false
			if host.session.snapshot().mining_session.drill.is_empty():break
		var failed: Dictionary=host.session.snapshot()
		var repeats: bool=bindings.mining_session.failure_instruction.repeat_each_drill
		check(failed.cargo.used==0 and failed.scenery.mined_count==attempt+2 and failed.mining_session.extraction.phase=="failed","A failed attempt lost its actual asteroid transaction")
		check(failed.dialogue.visible==(attempt==0 or repeats),"The mining popup did not follow this source's repeat rule")
		if failed.dialogue.visible:
			check(failed.dialogue.text_id==606 and failed.phase=="mining_instruction","The session displayed another failure instruction")
			if args.size()==4:await capture(args[3],"app-mining-failure-"+str(attempt))
			key(KEY_ENTER)
		check(not host.session.snapshot().dialogue.visible and host.session.snapshot().progress.get("mining_failure_hint_seen",false),"Acknowledgement lost the shown flag or retained the modal")
		if not begin_next_core_drill():return false
		check(host.session.snapshot().progress.get("mining_failure_hint_seen",false)==not repeats,"Starting another drill applied the wrong source hint reset")
	for i in 500:
		var state: Dictionary=host.session.snapshot().mining_session.drill
		var desired: Vector2=-(state.point+(state.input+state.drift)*5.0)*.2-state.drift
		var command:=Vector2.ZERO
		for axis in 2:command[axis]=signf(desired[axis])*sqrt(minf(1.0,absf(desired[axis])/3.0))
		if not step(command):return false
		if i==24 and args.size()==4:await capture(args[3],"app-mining-drill")
		if host.session.snapshot().mining_session.drill.is_empty():break
	check(host.session.snapshot().cargo.used==25 and host.session.snapshot().scenery.mined_count==2+failures_to_mine,"Session drilling did not earn its cargo exactly once after real failed attempts")
	for i in 60:
		if host.session.snapshot().dialogue.visible:break
		if not step():return false
	check(host.session.snapshot().dialogue.text_id==int(bindings.mining_objective.events[0].text_id) and host.session.objective_audio.snapshot().history[0].source_id==327,"Cargo return instructions lost their original speech")
	for i in 3:key(KEY_ENTER)
	button(JOY_BUTTON_Y);key(KEY_2)
	check(host.session.snapshot().campaign_cursor==3 and host.session.snapshot().station_autopilot.active,"Acknowledged return did not accept controller station input")
	if args.size()==4:await capture(args[3],"app-mining-return-flight")
	if args.size()==4:await capture_phone(args[3])
	for i in 4000:
		if not step():return false
		if host.session.status=="station_transition_required":break
	return true

func begin_next_core_drill() -> bool:
	var continuing: RefCounted=host.session.flight_owner();var next_asteroid:={}
	for body in continuing.snapshot().scenery.bodies.objects:
		if body.source_size_value==7 and not body.get("mined",false):next_asteroid=body;break
	if next_asteroid.is_empty():check(false,"The earned field has no further core asteroid");return false
	place_for_mining(continuing,next_asteroid)
	if not host.session._commit(continuing,false):check(false,host.session.error);return false
	key(KEY_F)
	for i in 200:
		if not step():return false
		if not host.session.snapshot().mining_session.drill.is_empty():break
	if host.session.snapshot().mining_session.drill.is_empty():check(false,"The next actual approach did not reach drilling");return false
	return true

func place_for_mining(flight: RefCounted, asteroid: Dictionary):
	var stand_off:=float(int(asteroid.scale*2500))
	flight._pose=Transform3D(Basis(Vector3.UP,PI),asteroid.position+Vector3(0,0,stand_off-.5))
	flight._pilot.angular_units=Vector2.ZERO;flight._targeting._selected=int(asteroid.index)
	flight._autopilot.observe_manual(flight._pose,Vector2.ZERO)
	var follow: Dictionary=bindings.camera_follow
	var eye: Vector3=flight._pose*Vector3(follow.eye_offset[0],follow.eye_offset[1],follow.eye_offset[2])
	var look: Vector3=flight._pose*Vector3(follow.look_offset[0],follow.look_offset[1],follow.look_offset[2])
	flight._camera._state.eye=eye;flight._camera._state.look=look;flight._camera._state.pose=Transform3D.IDENTITY.looking_at(look-eye,Vector3.UP);flight._camera._state.pose.origin=eye
	flight._aim=Aim.new();flight._aim.configure(bindings)

func step(command:=Vector2(INF,INF)) -> bool:
	now_us+=100000
	var axes: Vector2=host._controls.snapshot().command if command==Vector2(INF,INF) else command
	if not host.session.step(now_us,axes):check(false,host.session.error);return false
	host.present_session();return true
func key(code: int):key_down(code);key_up(code)
func key_down(code: int):
	var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=true;host._unhandled_input(event)
func key_up(code: int):
	var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=false;host._unhandled_input(event)
func button(code: int):
	var event:=InputEventJoypadButton.new();event.button_index=code;event.device=7;event.pressed=true;host._unhandled_input(event)
	event=InputEventJoypadButton.new();event.button_index=code;event.device=7;event.pressed=false;host._unhandled_input(event)
func capture(directory: String,name: String):
	var retained_session: Node=host.session
	var retained_pauses: Dictionary={} if retained_session==null else retained_session._pauses.duplicate()
	retained_pauses.erase("focus")
	for i in 8:await process_frame
	await restore_test_focus()
	check(host.session==retained_session,"Capture replaced its accepted session: "+name)
	if host.session!=retained_session:return
	if retained_session!=null:
		retained_session.rebase_time(now_us);host.present_session()
		check(host._focused and retained_session._pauses==retained_pauses,"Capture focus recovery changed a user pause: "+name)
		if retained_session.has_method("present_current"):check(retained_session.present_current(),retained_session.error)
	else:
		check(host._focused,"Launcher capture failed to recover focus: "+name)
	# Let the child flight viewport draw after resuming focus before reading the root.
	for i in 2:await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Could not capture "+name)
func capture_phone(directory: String, name: String="app-mining-phone"):
	var retained_pauses: Dictionary=host.session._pauses.duplicate()
	var canvas:=SubViewport.new();canvas.size=Vector2i(800,450);canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	host.reparent(canvas);host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);host.set_mobile_layout(true);TouchInput.set_preference(host,true)
	for i in 8:await process_frame
	host.present_session()
	if host.session.has_method("present_current"):check(host.session.present_current(),host.session.error)
	await RenderingServer.frame_post_draw
	check(Rect2(Vector2.ZERO,canvas.size).encloses(host._flight_actions.get_global_rect()),"Phone flight action buttons escape the viewport")
	if host.session is Trip and host.session.scene.radio!=null and host.session.scene.radio.visible:
		check(not host._flight_actions.get_rect().intersects(host.session.scene.radio._panel.get_rect()),"Phone flight actions overlap the radio transmission")
	check(canvas.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Could not capture phone controls")
	host.reparent(root);host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);host.set_mobile_layout(false);host.set_touch_controls(false)
	canvas.free()
	await restore_test_focus()
	host.session.rebase_time(now_us)
	check(host._focused and host.session._pauses==retained_pauses,"Phone capture changed focus or pause state: %s, focused=%s, pauses=%s, retained=%s"%[name,host._focused,host.session._pauses,retained_pauses])
	if host.session.has_method("present_current"):check(host.session.present_current(),host.session.error)
func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;printerr("FAIL ",checks,": ",message)
