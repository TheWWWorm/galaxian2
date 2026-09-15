extends "res://tests/alioth_return.gd"
## Earned ordinary flight through application confirmation, input and station
## return. The optional checkpoint is captured by the inherited campaign path.
var _free_capture_dir:=""

func _initialize() -> void:
	if OS.get_environment("GOF2_FREE_PLAY_STATION_SCENARIO").is_empty():super._initialize()
	else:call_deferred("run_free_checkpoint")

func run_free_checkpoint() -> void:
	var args:=OS.get_cmdline_user_args()
	if not open_application_content(args):quit(1);return
	var checkpoint:=FreePlayCheckpoint.new()
	var station: RefCounted=checkpoint.open(OS.get_environment("GOF2_FREE_PLAY_STATION_SCENARIO"),definitions)
	if station==null:check(false,checkpoint.error);quit(1);return
	app=Host.new();root.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.set_context(source,definitions,visual);app.set_process(false);app._focused=true
	var restored:=StationSession.new();app.viewport.add_child(restored);restored._world=station.fork()
	if not restored._build_scene(source,definitions,visual,catalogue,now_us,42) or not app.station_panel.configure_empty(source,definitions) or not restored.activate():check(false,restored.error+app.station_panel.error)
	else:
		app.session=restored;app._locations=restored.location_owner()
		await verify_free_application()
	app.free()
	print("Ordinary application: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func open_application_content(args: PackedStringArray) -> bool:
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,720)
	if args.size() not in [3,4]:check(false,"Expected content, bindings, visuals and optional captures");return false
	if args.size()==4:_free_capture_dir=args[3]
	source=Library.new();definitions=Bindings.new();catalogue=Catalogues.new();visual=Visuals.new()
	if not source.open(args[0]) or not definitions.open(args[1],source.manifest) or not catalogue.open(source) or not source.select_language("gb") or not visual.open(args[2],source.manifest):check(false,source.error+definitions.error+catalogue.error+visual.error);return false
	return true

func after_alioth_flight(live: Node3D,frame: RefCounted,station: RefCounted) -> void:
	await super.after_alioth_flight(live,frame,station)
	if failures==0:await verify_free_application()

func verify_free_application() -> void:
	var original: Dictionary=app.session.station_owner().snapshot()
	if definitions.mido_travel.has("gate_arrival"):check(original.contracts.get("travel_statistics")=={"jumpgates_used":0},"The earned opening counted a scripted journey as an ordinary jumpgate")
	if not definitions.mido_travel.has("free_flight"):
		check(not FlightSession.supported(definitions,18) and app.session.station_owner().prepare_departure(definitions,catalogue).is_empty(),"Older bindings exposed ordinary flight")
		return
	var locations: Dictionary=app.session.location_owner().snapshot()
	app.show();app.present_session();await process_frame;resume_application_focus()
	check(app._launch_button.visible and not app._lounge_button.visible,"The earned ordinary station has incorrect available actions")
	await capture_free_application("free-station-desktop")
	for trip in 2:
		var retained: RefCounted=app.session.station_owner();var before: Dictionary=retained.snapshot()
		var packet: Dictionary=retained.prepare_departure(definitions,catalogue)
		if packet.is_empty():check(false,retained.error);return
		check(packet.confirmation_required and packet.confirmation_text_id==int(definitions.station_departure.confirmation_text_id) and retained.snapshot()==before,"Ordinary confirmation changed the station or omitted the original question")
		var refused: RefCounted=retained.fork();refused._state.acknowledged=false
		check(refused.prepare_departure(definitions,catalogue).is_empty(),"Unacknowledged ordinary station allowed launch")
		refused=retained.fork();refused._state.mission.station_id=98
		check(refused.prepare_departure(definitions,catalogue).is_empty(),"Changed pending story allowed ordinary launch")
		app._focused=false
		check(not app.request_departure() and app.session.station_owner().snapshot()==before,"Unfocused application prepared departure")
		resume_application_focus()
		var key:=InputEventKey.new();key.physical_keycode=KEY_ENTER;key.pressed=true;app._unhandled_input(key)
		check(app._launch_packet==packet and app._launch_dialog.visible,"Keyboard departure omitted the original confirmation")
		app.cancel_departure();resume_application_focus()
		check(app.session.station_owner().snapshot()==before and app.session.location_owner().snapshot()==locations,"Cancelled departure changed career or generated new station stock")
		if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
		check(app.session is FlightSession and app.session.snapshot().campaign_cursor==18 and app.session.snapshot().player_pose.origin==Vector3(10,10,10000),"Application launched an unsupported or relocated free flight")
		check(app.session.snapshot().mission==original.mission and app.session.snapshot().contracts.credits==original.contracts.credits,"Departure changed pending story or credits")
		check(not app._flight_actions.visible and not app.touch_overlay.visible and not app._pause_button.visible,"Desktop ordinary flight ignored the touch-controls preference")
		if not await release_application_flight():return
		if trip==0:
			var left:=InputEventKey.new();left.physical_keycode=KEY_A;left.pressed=true;app._unhandled_input(left)
			var fire:=InputEventKey.new();fire.physical_keycode=KEY_SPACE;fire.pressed=true;app._unhandled_input(fire)
			var shots:=0
			for tick in 12:
				var input: Dictionary=app._controls.snapshot();now_us+=100000
				if not app.session.step(now_us,input.command,input.held.fire):check(false,app.session.error);return
				app.present_session()
				for gun in app.session.snapshot().encounter.primary_fire.get("weapons",[]):
					if gun.result.get("fired",false):shots+=1
			app.clear_input()
			check(shots>0 and app.session.snapshot().angular_units!=Vector2.ZERO,"Application keyboard input did not steer and fire")
			await capture_free_application("free-flight-desktop")
			await verify_free_touch_controls()
			if failures:return
		if not await dock_application():return
		app.present_session()
		var landed: Dictionary=app.session.snapshot()
		check(landed.phase=="free_play_required" and landed.campaign_cursor==18 and not landed.dialogue.visible and landed.alioth_return_acknowledged,"Ordinary return replayed or advanced the Alioth conversation")
		check(landed.progress==landed.contracts.progress and landed.contracts.credits==original.contracts.credits and landed.contracts.completed_side_missions==4 and landed.reward_credits==0,"Ordinary docking changed retained career or granted a reward")
		check(landed.mission==original.mission and landed.cargo==original.cargo and landed.equipment.ship_affiliation==0,"Ordinary docking changed cargo, affiliation or pending story")
		if definitions.mido_travel.has("gate_arrival"):check(landed.contracts.travel_statistics==original.contracts.travel_statistics,"Ordinary docking changed the earned jumpgate count")
		check(landed.player_cache.values.hull==landed.arrival_player.vitals.hull and landed.player_cache.values.shield==int(landed.arrival_player.vitals.shield),"Station entry discarded current flight damage")
		check(app.current_locations().snapshot()==locations and app.session.location_owner().snapshot()==locations,"Ordinary docking regenerated the retained station stock or contacts")
		check(app.session.audio.snapshot().get("history",[]).is_empty() and app._launch_button.visible,"Ordinary docking replayed speech or disabled the next departure")
		check(retained.snapshot()==before,"A completed flight mutated its retained departure station")
		print("Application ordinary trip ",trip+1," returned to Alioth at ",landed.flight_elapsed_ms,"ms; retained ",landed.contracts.credits," credits")
		if failures:return
	await capture_free_application("free-return-desktop")
	await verify_free_game_over()

func verify_free_game_over() -> void:
	# Separate lethal-contact diagnostic. The successful two-trip path above
	# receives ordinary flight input, without injected damage or progress.
	var retained: RefCounted=app.session.station_owner();var before: Dictionary=retained.snapshot()
	if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
	if not await release_application_flight():return
	var branch: RefCounted=app.session.flight_owner()
	var weapon: Dictionary=branch._player._npc_weapons[0]
	for hit in 4096:
		if branch._player.snapshot().vitals.hull==0:break
		if branch._player.weapon_hit(weapon,true,true,false).is_empty():check(false,branch._player.error);return
	var rules: Dictionary=definitions.player_destruction
	var frames:=ceili(float(rules.failure_after_ms+rules.failure_delay_ms+rules.fade_ms)/150.0)+8
	for tick in frames:
		if branch.snapshot().player_destruction.phase=="game_over":break
		var next: RefCounted=branch.evaluate(150)
		if next==null:check(false,branch.error);return
		branch=next
		if not app.session._commit(branch,true):check(false,app.session.error);return
	check(branch.snapshot().player_destruction.phase=="game_over","Ordinary death did not finish its game-over fade")
	if failures:return
	app.present_session()
	await capture_free_application("free-game-over-desktop")
	check(not app.enter_first_flight(now_us,4096,1789100000),"Game over reused a station launch confirmation")
	if not app.session.request_game_over_exit() or not app.enter_game_over():check(false,app.session.error if app.session!=null else app.status.text);return
	var exited: Dictionary=app.game_over_result()
	check(app.session==null and exited.transition.campaign_cursor==18 and exited.transition.source_state==1,"Ordinary game over did not return to the frontend")
	check(exited.flight.mission==before.mission and exited.flight.contracts.credits==before.contracts.credits and exited.flight.contracts.completed_side_missions==before.contracts.completed_side_missions,"Ordinary death advanced the story or paid a reward")
	check(retained.snapshot()==before,"The death diagnostic changed its retained station")

func verify_free_touch_controls() -> void:
	root.size=Vector2i(960,540);app.set_mobile_layout(true);app.set_touch_controls(true)
	await process_frame;resume_application_focus();app.present_session()
	check(app._flight_actions.visible and app.touch_overlay.visible and app._pause_button.visible,"Landscape touch preference omitted ordinary flight actions")
	app.touch_overlay.firing.emit(true)
	check(app._controls.snapshot().held.fire,"Touch fire did not reach ordinary flight input")
	app.touch_overlay.firing.emit(false)
	check(not app._controls.snapshot().held.fire,"Releasing touch fire left the weapon held")
	for tick in 25:
		if not application_step():return
	await capture_free_application("free-flight-mobile-landscape")
	root.size=Vector2i(1280,720);app.set_mobile_layout(false);app.set_touch_controls(false)
	await process_frame;resume_application_focus();app.present_session()
	for tick in 25:
		if not application_step():return
	check(not app._flight_actions.visible and not app.touch_overlay.visible and not app._pause_button.visible,"Disabling touch preference left ordinary flight controls visible")

func capture_free_application(label: String) -> void:
	if _free_capture_dir.is_empty() or DisplayServer.get_name()=="headless":return
	if not FreePlayCheckpoint.private_path(_free_capture_dir+"/capture.png"):check(false,"Keep application captures outside engine source");return
	DirAccess.make_dir_recursive_absolute(_free_capture_dir)
	resume_application_focus();app.present_session();await process_frame
	RenderingServer.force_draw(false);await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(_free_capture_dir.path_join(label+".png"))==OK,"Could not capture ordinary application "+label)
	resume_application_focus()
