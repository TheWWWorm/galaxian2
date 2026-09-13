extends SceneTree
## App launch, mining input, speech and return. Asteroid placement and a retained
## drill branch isolate controls; the successful trip earns and delivers cargo.
const Host=preload("res://src/presentation/opening_preview.gd")
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
	check(args.size() in [3,4],"Expected Mac content, bindings, visuals and optional captures")
	if args.size() in [3,4]:await verify(args)
	if is_instance_valid(host):host.free()
	print("First flight session: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not lib.select_language("gb") or not cat.open(lib) or not visuals.open(args[2],lib.manifest):check(false,lib.error+bindings.error+cat.error+visuals.error);return
	if bindings.station_return.is_empty():check(not Trip.supported(bindings),"Legacy pack offered an incomplete mining trip");return
	var player:=Player.new();var handoff:=Handoff.new();check(player.configure(bindings,cat),player.error)
	var arrival:=Arrival.new()
	if not arrival.configure(bindings,cat,lib,handoff.prepare(bindings,cat,Fixture.completed(bindings,player,3)),[1,1,1],1789100000):check(false,arrival.error);return
	for i in 500:
		arrival=arrival.evaluate(100)
		if arrival==null:check(false,"Rescue fixture failed");return
		if not arrival.snapshot().boundary.is_empty():break
	root.size=Vector2i(1280,720)
	host=Host.new();root.add_child(host);host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.set_context(lib,bindings,visuals);host.set_process(false)
	for i in 3:await process_frame
	var station:=Station.new();host.viewport.add_child(station);host.session=station
	if not station.configure(lib,bindings,visuals,arrival.prepare_station(),0,42) or not host.station_panel.configure(lib,bindings,visuals) or not station.activate():check(false,station.error+host.station_panel.error);return
	check(not host.request_departure(),"Unacknowledged station offered launch")
	for i in 10:station.step((i+1)*100000)
	for i in 19:key(KEY_ENTER)
	host.present_session()
	var before: Dictionary=station.snapshot()
	check(before.campaign_cursor==2 and host._launch_button.visible and not host._pause_button.visible,"Ready station lacked launch or exposed desktop touch actions")
	check(host.request_departure() and host._launch_dialog.visible and host._launch_dialog.dialog_text==lib.strings[386],"Launch omitted the original confirmation")
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
	check(waited==expected_modal and waited.session_generation>modal.session_generation,"Modal world visits advanced clocks or auto-acknowledged the briefing")
	modal=waited
	key(KEY_W)
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
	key_down(KEY_W);step();step();key_up(KEY_W)
	check(host.session.snapshot().angular_units.x<0 and host.session.snapshot().player_pose!=held.player_pose,"Keyboard steering did not reach the live frame")
	key(KEY_MINUS);check(is_equal_approx(host.session.snapshot().input_throttle,.9),"Throttle key did not reach flight")
	button(JOY_BUTTON_Y)
	check(host.session.snapshot().station_autopilot.active and host.session.snapshot().input_throttle==1,"Controller station selection did not restore cruise throttle")
	key(KEY_P);check(not host.session.snapshot().station_autopilot.active,"Keyboard station cancellation failed")
	host.set_touch_controls(true)
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
	await after_first_return(args)
	host.reset();check(host.session==null and not host._launch_dialog.visible and not host._flight_actions.visible,"Reset retained a flight scene or action overlay")

func after_first_return(_args: PackedStringArray):pass

func mine_trip(args: PackedStringArray) -> bool:
	var flight: RefCounted=host.session.flight_owner();var asteroid:={}
	for body in flight.snapshot().scenery.bodies.objects:
		if body.source_size_value==7:asteroid=body;break
	if asteroid.is_empty():check(false,"No source core asteroid for live input verification");return false
	# Explicit close-placement/selected-target fixture; source acquisition and
	# long approach have separate coverage. This session still owns all drilling.
	place_for_mining(flight,asteroid)
	if not host.session._commit(flight,false):check(false,host.session.error);return false
	key_down(KEY_E);var selected: Dictionary=host.session.snapshot();key_down(KEY_E);key_up(KEY_E)
	check(selected.mining_approach.phase!="idle" and host.session.snapshot()==selected,"Held mining key cancelled its own approach")
	for i in 200:
		if not step():return false
		if not host.session.snapshot().mining_session.drill.is_empty():break
	if host.session.snapshot().mining_session.drill.is_empty():check(false,"Live input never reached drilling");return false
	var drill: RefCounted=host.session.flight_owner()
	host.set_touch_controls(true);host.present_session()
	if args.size()==4:await capture(args[3],"app-mining-touch")
	var touch: Control=host.touch_overlay
	var point: Vector2=touch.get_global_transform_with_canvas()*touch.fire_center()
	check(touch.press(37,point),"Touch mining button rejected its pointer")
	host.handle_actions(host._controls.take_pressed());touch.release(37)
	check(host.session.snapshot().mining_session.drill.is_empty() and host.session.snapshot().cargo.used==0,"Touch stop failed to commit a zero-ore cancellation")
	# Restore the accepted pre-stop branch solely for the successful path.
	if not host.session._commit(drill,false):check(false,host.session.error);return false
	host.set_touch_controls(false)
	for i in 500:
		var state: Dictionary=host.session.snapshot().mining_session.drill
		var desired: Vector2=-(state.point+(state.input+state.drift)*5.0)*.2-state.drift
		var command:=Vector2.ZERO
		for axis in 2:command[axis]=signf(desired[axis])*sqrt(minf(1.0,absf(desired[axis])/3.0))
		if not step(command):return false
		if i==24 and args.size()==4:await capture(args[3],"app-mining-drill")
		if host.session.snapshot().mining_session.drill.is_empty():break
	check(host.session.snapshot().cargo.used==25 and host.session.snapshot().scenery.mined_count==1,"Session drilling did not earn its cargo exactly once")
	for i in 60:
		if host.session.snapshot().dialogue.visible:break
		if not step():return false
	check(host.session.snapshot().dialogue.text_id==1706 and host.session.objective_audio.snapshot().history[0].source_id==327,"Cargo return instructions lost their original speech")
	for i in 3:key(KEY_ENTER)
	button(JOY_BUTTON_Y)
	check(host.session.snapshot().campaign_cursor==3 and host.session.snapshot().station_autopilot.active,"Acknowledged return did not accept controller station input")
	if args.size()==4:await capture(args[3],"app-mining-return-flight")
	if args.size()==4:await capture_phone(args[3])
	for i in 4000:
		if not step():return false
		if host.session.status=="station_transition_required":break
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
	for i in 8:await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Could not capture "+name)
func capture_phone(directory: String, name: String="app-mining-phone"):
	var canvas:=SubViewport.new();canvas.size=Vector2i(420,800);canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	host.reparent(canvas);host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);host.set_mobile_layout(true);host.set_touch_controls(true)
	for i in 8:await process_frame
	host.present_session()
	if host.session.has_method("present_current"):check(host.session.present_current(),host.session.error)
	await RenderingServer.frame_post_draw
	check(Rect2(Vector2.ZERO,canvas.size).encloses(host._flight_actions.get_global_rect()),"Phone flight action buttons escape the viewport")
	check(canvas.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Could not capture phone controls")
	host.reparent(root);host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);host.set_mobile_layout(false);host.set_touch_controls(false)
	canvas.free();host.session.rebase_time(now_us)
	root.grab_focus()
	for i in 3:await process_frame
	if host.session.has_method("present_current"):check(host.session.present_current(),host.session.error)
func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;printerr("FAIL ",checks,": ",message)
