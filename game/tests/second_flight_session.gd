extends "res://tests/first_flight_session.gd"
## Application continuation from the earned first return. Close asteroid
## placement isolates drilling; a separate branch reuses that real departure
## packet and positions a lethal source projectile. No live audio owner rewinds.
const DeathFixture=preload("res://tests/player_death_flight.gd")
const GameOverPanel=preload("res://src/presentation/game_over_panel.gd")

func run():
	var args:=OS.get_cmdline_user_args()
	if args.size()==3 and DisplayServer.get_name()!="headless" and not OS.get_environment("GOF2_CAPTURE_DIR").is_empty():args.append(OS.get_environment("GOF2_CAPTURE_DIR"))
	check(args.size() in [3,4],"Expected Mac content, bindings, visuals and optional captures")
	if args.size() in [3,4]:await verify(args)
	if is_instance_valid(host):host.free()
	print("Second flight session: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func after_first_return(args: PackedStringArray):
	if not Trip.supported(bindings,4):
		check(not host.request_departure(),"Older pack offered an incomplete second application trip")
		return
	var station: Node=host.session;var accepted: Dictionary=station.snapshot()
	check(host.request_departure(),"Earned first return did not offer the second departure")
	var packet: Dictionary=host._launch_packet.duplicate(true)
	host.cancel_departure()
	check(station.snapshot()==accepted and not host.enter_first_flight(now_us),"Cancelled second departure changed the station")
	var textures: Dictionary=visuals.textures;visuals.textures={}
	check(host.request_departure() and not host.enter_first_flight(now_us,4096,1789100000) and host.session==station and station.snapshot()==accepted,"Failed second preparation lost the station")
	visuals.textures=textures
	check(host.retry_transition() and host.enter_first_flight(now_us,4096,1789100000),host.status.text)
	if not host.session is Trip:return
	host.session.rebase_time(now_us)
	check(not is_instance_valid(station) and host.session.flight_audio!=null and host.session.flight_audio._flight_serial==0 and host.session.scene.game_over!=null,"Second departure did not install its presentation/audio before advancing")
	if not release_second_briefing():return
	if args.size()==4:await capture(args[3],"app-second-briefing")
	key(KEY_ENTER)
	check(host.session.can_control() and host.session.briefing_audio._player==null,"Second briefing did not release input and stop speech")
	if not start_second_drill():return
	for i in 500:
		var drill: Dictionary=host.session.snapshot().mining_session.drill
		if drill.is_empty():break
		var desired: Vector2=-(drill.point+(drill.input+drill.drift)*5.0)*.2-drill.drift
		var command:=Vector2.ZERO
		for axis in 2:command[axis]=signf(desired[axis])*sqrt(minf(1,absf(desired[axis])/3.0))
		if not step(command):return
	check(host.session.snapshot().cargo.used==25 and host.session.snapshot().scenery.mined_count==1,"Second session failed to earn its 25-ton cargo once")
	for i in 60:
		if host.session.snapshot().dialogue.visible:break
		if not step():return
	check(host.session.snapshot().dialogue.text_id==int(bindings.full_hold_story.completion_events[0].text_id) and host.session.objective_audio.snapshot().history[0].source_id==431,"Second cargo instruction used the wrong line or voice")
	if args.size()==4:await capture(args[3],"app-second-warning")
	key(KEY_ENTER)
	check(host.session.snapshot().dialogue.text_id==int(bindings.full_hold_story.completion_events[1].text_id) and host.session.objective_audio.snapshot().history.back().source_id==432,"Second warning lost its acknowledgement/voice order")
	key(KEY_ENTER);button(JOY_BUTTON_Y);key(KEY_2)
	check(host.session.snapshot().campaign_cursor==5 and host.session.snapshot().station_autopilot.active,"Second return failed to activate native station guidance")
	var flight: Node=host.session;var audio: Node=flight.flight_audio
	for i in 4000:
		if not step():return
		if flight.status=="station_transition_required":break
	var arrived: Dictionary=flight.snapshot()
	check(flight.status=="station_transition_required" and arrived.cargo.used==25 and arrived.player.vitals.hull>0,"Second application trip failed to reach the station alive")
	if flight.status!="station_transition_required":return
	var heard:=false
	for event in audio.snapshot().history:
		if event.get("source_id")==61 and event.action=="start_spatial":heard=true
	check(heard and audio._flight_serial==arrived.flight_audio.serial,"Live pirate fire did not reach the accepted audio owner")
	textures=visuals.textures;visuals.textures={}
	check(not host.enter_station(now_us,42) and host.session==flight and flight.snapshot()==arrived and audio.snapshot().paused,"Failed second return lost flight or left audio running")
	visuals.textures=textures
	check(host.retry_transition(),host.status.text)
	if not host.session is Station:return
	check(not is_instance_valid(flight) and not is_instance_valid(audio) and not host.viewport.is_audio_listener_3d(),"Station entry retained flight audio or its listener")
	host.session.rebase_time(now_us)
	for i in 10:
		if not step():return
	check(host.session.snapshot().cargo==arrived.cargo and host.session.snapshot().arrival_player==arrived.player,"Second station entry reset the accepted player or cargo")
	if args.size()==4:await capture(args[3],"app-second-return")
	for i in 6:
		check(host.session.snapshot().dialogue.text_id==int(bindings.full_hold_return.events[i].text_id) and not host.request_departure(),"Second station conversation skipped a line or allowed departure")
		if i<5:check(host.session.audio.snapshot().history.back().source_id==433+i,"Second station conversation used the wrong recording")
		else:
			check(host.session.audio._player==null,"Silent equipment instruction retained speech")
			if args.size()==4:await capture(args[3],"app-second-equipment-instruction")
		key(KEY_ENTER)
	var finished: Dictionary=host.session.snapshot()
	check(finished.campaign_cursor==6 and finished.phase=="station_equipment_required" and finished.mission.kind==158 and not host._launch_button.visible and not host.request_departure(),"Second return skipped its unsupported equipment boundary")
	check(finished.cargo.entries.is_empty() and finished.cargo.used==25 and finished.cargo.free_space==0 and finished.cargo_cache_stale,"Second return silently refreshed the source's retained cargo cache")
	check(finished.reward_credits==0 and not finished.mining_completed and finished.arrival_player==arrived.player,"Second return granted unearned reward, healing or tutorial completion")
	if args.size()==4:await capture(args[3],"app-second-equipment-boundary")
	await after_second_return(args)
	await death_branch(args,packet)

func after_second_return(_args: PackedStringArray):pass

func release_second_briefing() -> bool:
	for i in 160:
		if host.session.snapshot().dialogue.visible:break
		if not step():return false
	check(host.session.snapshot().phase=="briefing" and host.session.snapshot().dialogue.text_id==int(bindings.full_hold_story.briefing_events[0].text_id) and host.session.briefing_audio.snapshot().history[0].source_id==188,"Second departure lost its source briefing")
	var before: Dictionary=host.session.snapshot();var serial: int=before.flight_audio.serial
	for i in 3:
		if not step():return false
	check(host.session.snapshot().campaign_cursor==4 and host.session.snapshot().dialogue==before.dialogue and host.session.snapshot().flight_audio.serial==serial+3 and host.session.flight_audio._flight_serial==serial+3,"Modal second-trip world visits failed to preserve dialogue or advance accepted audio serials")
	return true

func start_second_drill(hold_trigger:=false) -> bool:
	var world: RefCounted=host.session.flight_owner();var asteroid:={}
	for body in world.snapshot().scenery.bodies.objects:
		if body.source_size_value==7:asteroid=body;break
	if asteroid.is_empty():check(false,"No source core asteroid for the second application trip");return false
	place_for_mining(world,asteroid)
	if not host.session._commit(world,false):check(false,host.session.error);return false
	if hold_trigger:trigger(.9)
	else:key(KEY_F)
	for i in 200:
		if host.session.flight_owner().drill_owner()!=null:return true
		if not step():return false
	check(false,"Second application approach never reached drilling");return false

func death_branch(args: PackedStringArray, packet: Dictionary):
	# A separate test branch starts at serial zero from the earned departure.
	host.reset()
	var flight:=Trip.new();host.viewport.add_child(flight);host.session=flight
	if not flight.configure(lib,bindings,visuals,packet,true,now_us,4096,1789100000):check(false,flight.error);return
	flight.transition_rejected.connect(host.transition_error)
	check(flight.activate(),flight.error);host.present_session()
	if not release_second_briefing():return
	key(KEY_ENTER)
	if not start_second_drill(true):return
	var fixture:=DeathFixture.new();var dead: RefCounted=fixture.lethal(flight.flight_owner())
	check(dead!=null and fixture.failures==0,"Positioned source projectile failed to start the application death branch")
	fixture.free()
	if dead==null:return
	if not flight._commit(dead,false):check(false,flight.error);return
	host.present_session()
	check(not flight.can_control() and flight.can_stop_mining() and not host._flight_actions.visible,"Death allowed normal flight or lost the existing drill stop")
	key(KEY_UP);key(KEY_Q);key(KEY_SLASH)
	check(host._controls.snapshot().command==Vector2.ZERO and flight.snapshot().input_throttle==1 and not flight.snapshot().station_autopilot.active,"Dead application accepted steering, throttle or a new autopilot")
	key(KEY_F)
	check(flight.flight_owner().drill_owner()==null and flight.snapshot().cargo.used==0 and not flight.can_stop_mining(),"Death input failed to stop the existing zero-ore drill")
	var before: Dictionary=flight.snapshot()
	for reason in ["user","focus","hidden"]:
		flight.set_pause(reason,true,now_us)
		check(step() and flight.snapshot()==before and flight.flight_audio.snapshot().paused and not flight.request_game_over_exit(),"Pause advanced death or accepted continuation: "+reason)
		flight.set_pause(reason,false,now_us)
	var identity: Dictionary=flight.scene.game_over._identity.duplicate(true)
	var sound: Dictionary=flight.flight_audio.snapshot()
	flight.scene.game_over._identity.binding_id="foreign"
	check(not flight.step(now_us+100000) and flight.snapshot()==before and flight.flight_audio.snapshot()==sound,"Rejected death rendering committed simulation, sound or RNG")
	host.transition_error(flight.error)
	check(flight.is_paused() and flight.flight_audio.snapshot().paused,"Application presentation failure did not freeze input and audio")
	flight.scene.game_over._identity=identity
	check(host.retry_transition() and not flight.is_paused(),"Accepted death presentation could not recover")
	flight.rebase_time(now_us)
	key_down(KEY_SPACE)
	var captured_trail:=false;var captured_explosion:=false;var captured_tail:=false
	for i in 180:
		if not step():return
		var state: Dictionary=flight.snapshot().player_destruction
		if args.size()==4 and state.elapsed_ms>=1000 and not captured_trail:
			await capture(args[3],"app-second-death-trail");captured_trail=true
		if args.size()==4 and state.elapsed_ms>=3800 and not captured_explosion:
			await capture(args[3],"app-second-death-breakup");captured_explosion=true
		if args.size()==4 and state.elapsed_ms>=6500 and not captured_tail:
			await capture(args[3],"app-second-death-explosion-tail");captured_tail=true
		if state.phase=="game_over":break
	check(flight.snapshot().player_destruction.phase=="game_over" and flight.status=="running","Application death did not reach an acknowledged game-over screen")
	check(flight.scene.game_over.snapshot().absolute_ms==now_us/1000 and flight.scene.game_over.snapshot().prompt_alpha_byte==GameOverPanel.blink_alpha(now_us/1000,float(bindings.game_over_presentation.blink_radians_per_millisecond)),"Game-over prompt did not use the application absolute clock")
	key_down(KEY_SPACE)
	check(flight.status=="running","Fire held across the fade automatically continued")
	key_up(KEY_SPACE)
	trigger(.95)
	check(flight.status=="running","Trigger held before lethal contact automatically continued after the fade")
	trigger(0)
	if flight.status!="running":return
	var ids:=[]
	for event in flight.flight_audio.snapshot().history:
		if event.action in ["start","start_spatial"]:ids.append(int(event.source_id))
	check(19 in ids and 37 in ids,"Application death omitted breakup or failure sound")
	# Wait through the native blink to capture a readable prompt, without
	# replacing the simulation camera or supplying a synthetic presentation time.
	for i in 12:
		if flight.scene.game_over.snapshot().prompt_alpha_byte>=200:break
		if not step():return
	check(flight.scene.game_over.snapshot().prompt_alpha_byte>=200,"Game-over prompt never reached its visible blink interval")
	if args.size()==4:await capture(args[3],"app-second-game-over")
	key(KEY_ESCAPE);var waiting: Dictionary=flight.snapshot()
	key(KEY_ENTER)
	check(flight.is_paused() and flight.snapshot()==waiting,"Paused game-over accepted Enter")
	key(KEY_ESCAPE);flight.rebase_time(now_us)
	# Dispatch through the real root viewport and embedded scene input path.
	var event:=InputEventKey.new();event.physical_keycode=KEY_ENTER;event.keycode=KEY_ENTER;event.pressed=true
	root.push_input(event,true)
	event=InputEventKey.new();event.physical_keycode=KEY_ENTER;event.keycode=KEY_ENTER;event.pressed=false;root.push_input(event,true)
	await process_frame
	check(flight.status=="game_over_transition_required","Viewport acknowledgement did not reach the native game-over boundary")
	if flight.status!="game_over_transition_required":return
	var boundary: Dictionary=flight.snapshot();var audio: Node=flight.flight_audio
	var exit_packet: Dictionary=flight._world._game_over_packet.duplicate(true)
	flight._world._game_over_packet.source_state=2
	check(not host.enter_game_over() and host.session==flight and flight.snapshot()==boundary and flight.flight_audio.snapshot().paused,"Malformed game-over destination discarded flight or continued playback")
	flight._world._game_over_packet=exit_packet
	check(host.retry_transition() and host.session==null and not is_instance_valid(audio) and not host.viewport.is_audio_listener_3d(),"Game-over retry did not release the accepted flight/audio")
	var result: Dictionary=host.game_over_result()
	check(result.transition==exit_packet and result.flight==boundary and result.flight.player.vitals.hull==0 and result.flight.cargo.used==0 and result.flight.campaign_cursor==4,"Game-over exit changed cargo, health or earned progress")
	result.flight.cargo.used=100
	check(host.game_over_result().flight.cargo.used==0 and not host._retry_button.visible and not host._flight_actions.visible and not host._launch_button.visible,"Launcher exposed retained state or kept obsolete flight actions")
	host._process(0)
	check(host.session==null and host.status.text.begins_with("Game over"),"Game-over launcher silently started another game")
	if args.size()==4:await capture(args[3],"app-second-game-over-launcher")

func trigger(value: float):
	var event:=InputEventJoypadMotion.new();event.axis=JOY_AXIS_TRIGGER_RIGHT;event.axis_value=value;event.device=7
	host._unhandled_input(event)
