extends SceneTree
## Player frontend journey with original full-hull primary contacts. Contacts
## are controlled test inputs; this is not a manually played campaign fixture.
const Frontend=preload("res://src/presentation/player_frontend.gd")
const Opening=preload("res://src/presentation/opening_session.gd")
const Arrival=preload("res://src/presentation/arrival_session.gd")
const Station=preload("res://src/presentation/station_session.gd")
const Flight=preload("res://src/presentation/first_flight_session.gd")
const Archive=preload("res://src/simulation/station_archive.gd")
const Guard=preload("res://tests/fixtures/convoy_station_scenario.gd")
var checks:=0
var failures:=0
var app: Control
var directory:=""
var mode:=""
var now:=0
var tick:=0

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	directory=OS.get_environment("GOF2_MENU_TEST_DIRECTORY")
	mode=OS.get_environment("GOF2_OPENING_JOURNEY_MODE")
	if mode.is_empty():mode="watched"
	if args.size()!=1 or mode not in ["watched","skipped","resume"] or directory.is_empty() or not Guard.private_path(directory.path_join("player.json")):
		check(false,"Expected an import receipt and an isolated watched/skipped/resume profile");finish();return
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,720)
	app=Frontend.new();root.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if mode=="resume":
		check(app.boot(PackedStringArray(),directory),app.error)
		if not failures:await resume_and_depart()
	else:
		check(not FileAccess.file_exists(directory.path_join("player.json")),"Use a fresh profile for each complete journey")
		app.boot(PackedStringArray(),directory)
		check(app.open_import(args[0]),app.error)
		if not failures:await play_opening()
	app.free();await process_frame;finish()

func play_opening() -> void:
	dismiss_title()
	await process_frame;await process_frame
	click(app.menu._buttons.new_game);await process_frame
	check(app.phase=="game" and app.has_session(),app.error)
	if failures:return
	var host: Control=app.game
	host.set_process(false);focus(host)
	check(host.session is Opening and host.session.rebase_time(0),"New Game did not start the opening")
	if failures:return
	if mode=="skipped":host.skip_cinematic()
	for frame in 2500:
		if host.session.can_control():break
		if not advance(host):return
	check(host.session.can_control(),"Opening introduction did not release controls")
	if failures:return
	await verify_opening_controls(host)
	if failures:return
	# Use the equipped primary's actual source damage against original hulls.
	# Do not reduce hull, grant rewards or replace campaign state.
	var contacts:=0
	for volley in 100:
		var alive:=false
		for actor in host.session.snapshot().combat.actors:
			if actor.vitals.hull<=0:continue
			alive=true
			var gun: RefCounted=host.session._world_frame._primaries._guns[0].projectiles
			gun._elapsed_ms=int(gun.snapshot().weapon.interval_ms)+1
			check(gun.fire(actor.pose.origin,Vector3.BACK,true).get("fired",false),gun.error);contacts+=1
		if not alive:break
		if not advance(host,100000):return
	print(mode,": original-hull primary contacts=",contacts)
	var phases:={};var radio:={};var requested_skip:=false;var peak_births:=0
	for frame in 6500:
		if host.session.status=="arrival_transition_required":break
		if mode=="skipped" and not requested_skip and host.session.can_skip_cinematic():
			host.skip_cinematic();requested_skip=true
		var before: Dictionary=host.session.snapshot()
		var phase:=int(before.camera.shot.phase)
		# Exercise the short manager interval around the discontinuous warp,
		# and high-rate death rotations as well as ordinary/slow frames.
		var delta:=6944 if frame<300 or phase in [9,10] else 0
		if not advance(host,delta):
			print("Failure after phase=",phase," tick=",tick," pose=",before.scene.player_pose.origin)
			return
		var state: Dictionary=host.session.snapshot()
		phase=int(state.camera.shot.phase)
		if state.radio.visible:radio[int(state.radio.active_event)]=true
		for births in state.world_frame.get("engine_particles",{}).get("births",{}).values():peak_births=maxi(peak_births,int(births))
		if phase not in phases:
			phases[phase]=true
			print(mode,": escape phase=",phase," time_ms=",state.elapsed_ms)
			if phase in [5,7,10,12]:await capture("escape-%d"%phase);focus(host)
	check(host.session.status=="arrival_transition_required","Opening did not finish its escape and fade")
	if failures:return
	var completed: Dictionary=host.session.snapshot()
	check(completed.world_frame.controller.death_accounting.counter_deltas.player_kills==3,"Opening kill credit changed")
	if mode=="watched":
		for phase in range(5,17):check(phases.has(phase),"Watched opening missed phase %d"%phase)
		check(completed.radio.finished.all(func(value):return value),"Watched opening missed original dialogue")
	else:check(requested_skip,"Skipped route never requested the escape skip")
	print(mode,": escape complete; largest nozzle birth batch=",peak_births)
	host._process(0)
	check(host.session is Arrival,"Automatic rescue transition failed: "+host.status.text)
	if failures:return
	now=0;focus(host);check(host.session.rebase_time(now),host.session.error)
	var rescue_radio:={}
	for frame in 2500:
		if not advance(host):return
		var state: Dictionary=host.session.snapshot()
		if state.radio.visible:rescue_radio[int(state.radio.active_event)]=true
		if host.session.status=="station_transition_required":break
	check(host.session.status=="station_transition_required" and rescue_radio.size()==3,"Rescue did not complete all three transmissions")
	if failures:return
	host._process(0)
	check(host.session is Station,"Automatic first-station transition failed: "+host.status.text)
	if failures:return
	now=0;focus(host)
	# Host processing is disabled for explicit frame timing. Advance the
	# original station's dialogue-start delay before looking for its buttons.
	for frame in 120:
		if host.session.snapshot().conversation_started:break
		if not advance(host):return
	check(host.session.snapshot().conversation_started,"First-station conversation did not start")
	if failures:return
	host.present_session();await process_frame;await process_frame
	for line in 40:
		if not host.station_panel.visible:break
		click(host.station_panel._next);await process_frame
	check(not host.station_panel.visible and host.session.snapshot().campaign_cursor==2,"First-station conversation did not finish")
	check(host.station_shell.visible and host.station_shell._actions.depart.visible,"First-station interface omitted Depart")
	check(host.save_station(false),host._save_notice.text)
	if failures:return
	var document:=Frontend.SaveFile.new().read_document(host.station_save_path())
	check(document==Archive.new().capture(host.session.station_owner(),app.bindings,host.session.location_owner()),"Saved first station differs from the live career")
	await capture("first-station");focus(host)
	if failures:return
	await depart()

func resume_and_depart() -> void:
	dismiss_title();check(app.has_save(),"Fresh process cannot find the completed first-station save")
	if failures:return
	await process_frame;await process_frame
	var path:=Frontend.SaveFile.path_for(directory.path_join("saves"),app.bindings)
	var file:=Frontend.SaveFile.new();var document:=file.read_document(path)
	click(app.menu._buttons.resume);await process_frame
	check(app.phase=="game" and app.has_session() and app.game.session is Station,"Resume did not load the station")
	if failures:return
	app.game.set_process(false);focus(app.game);app.game.present_session()
	check(Archive.new().capture(app.game.session.station_owner(),app.bindings,app.game.session.location_owner())==document,"Resume changed the saved career")
	await capture("resumed-station");focus(app.game)
	if not failures:await depart()

func depart() -> void:
	var host: Control=app.game
	host.present_session();await process_frame;focus(host)
	click(host.station_shell._actions.depart);await process_frame
	check(host._launch_dialog.visible and not host._launch_dialog._yes.disabled,"Depart did not open its active confirmation")
	if failures:return
	await capture("departure-confirmation");focus(host)
	click(host._launch_dialog._yes);await process_frame
	check(host.session is Flight and not host._launch_dialog.visible,"Yes did not leave the first station: "+host.status.text+" / "+host._save_notice.text)
	if failures:return
	now=0;focus(host);check(host.session.rebase_time(now),host.session.error)
	for frame in 300:
		if not advance(host):return
		if host.session.can_control():break
	check(host.session.can_control(),"Station departure did not release flight controls")
	await capture("departed-flight");focus(host)
	var retained: Node=host.session
	app.show_menu();check(retained.is_paused(),"Menu did not pause departed flight")
	app.request_action("resume");focus(host)
	check(app.game.session==retained and not retained.is_paused(),"In-flight Resume replaced or left the session paused")
	check(retained.rebase_time(now),retained.error)
	for frame in 20:
		if not advance(host):return
	print(mode,": first station, saved career and confirmed departure complete")

func advance(host: Control,delta: int=0) -> bool:
	var cadence:=[16667,33333,6944,6667,67000,149000]
	now+=int(cadence[tick%cadence.size()]) if delta==0 else delta;tick+=1
	if not host.session.step(now):check(false,host.session.error);return false
	host.present_session()
	check(host.session!=null and not host._transition_failed,"Presentation lost the scene: "+host.status.text)
	return failures==0

func verify_opening_controls(host: Control) -> void:
	var initial: Transform3D=host.session.snapshot().scene.player_pose
	flight_key(KEY_S,true)
	if not manual_frame(host):return
	var state: Dictionary=host.session.snapshot()
	check(state.scene.player_pose.origin.is_equal_approx(initial.origin) and state.world_frame.control_throttle==0.0,"Opening S did not stop forward motion")
	check(not state.world_frame.engine_particles.draw_enabled and host.session.geometry.engine_particles.frame.counts.all(func(count):return int(count)==0),"Opening brake left rendered exhaust visible")
	await capture("brake-exhaust-off");focus(host)
	# Restoring window focus clears held input, as it does for a player.
	flight_key(KEY_S,true)
	flight_key(KEY_A,true)
	for frame in 8:
		if not manual_frame(host):return
	flight_key(KEY_A,false)
	var left: Transform3D=host.session.snapshot().scene.player_pose
	check((initial.basis.inverse()*(left.origin-initial.origin)).x>0.0 and left.basis.is_equal_approx(initial.basis),"Opening A changed heading or did not strafe left")
	flight_key(KEY_D,true)
	for frame in 8:
		if not manual_frame(host):return
	flight_key(KEY_D,false)
	var right: Transform3D=host.session.snapshot().scene.player_pose
	check((left.basis.inverse()*(right.origin-left.origin)).x<0.0 and right.basis.is_equal_approx(left.basis),"Opening D changed heading or did not strafe right")
	check(absf((initial.basis.inverse()*(right.origin-initial.origin)).z)<0.05 and not host.session.snapshot().world_frame.engine_particles.draw_enabled,"Held opening brake crept forward or restored exhaust while strafing")
	await capture("brake-held-exhaust-off");focus(host)
	flight_key(KEY_S,false)
	for frame in 3:
		if not manual_frame(host):return
	state=host.session.snapshot()
	check(state.world_frame.control_throttle==1.0 and state.world_frame.engine_particles.draw_enabled and host.session.geometry.engine_particles.frame.counts.all(func(count):return int(count)>0),"Opening brake release did not restore throttle and exhaust")
	await capture("brake-release-exhaust-on");focus(host)

func manual_frame(host: Control) -> bool:
	now+=100000
	var input: Dictionary=host._controls.snapshot()
	check(host.session.step(now,input.command,input.held.fire,input.strafe,input.held.brake),host.session.error)
	if failures:return false
	host.present_session()
	return true

func flight_key(code: int,pressed: bool) -> void:
	var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()

func focus(host: Control) -> void:
	host._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	if host.session!=null:check(host.session.rebase_time(now),host.session.error)

func dismiss_title() -> void:
	var event:=InputEventKey.new();event.physical_keycode=KEY_ENTER;event.pressed=true
	app.menu._unhandled_input(event)
	check(not app.menu._title_active,"Title did not accept Enter")

func click(button: Button) -> void:
	var point:=root.get_final_transform()*button.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point
	Input.parse_input_event(motion);Input.flush_buffered_events()
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT
		event.position=point;event.global_position=point;event.pressed=down
		Input.parse_input_event(event);Input.flush_buffered_events()

func capture(name: String) -> void:
	var output:=OS.get_environment("GOF2_CAPTURE_DIR")
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(output)
	check(root.get_texture().get_image().save_png(output.path_join(mode+"-"+name+".png"))==OK,"Could not capture "+name)

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish() -> void:
	print("Opening player journey ",mode,": ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)
