extends SceneTree
## Queue/edge unit checks and a real saved-flight pause regression. The queue
## probe has no game world and cannot create ammunition or campaign progress.
const Controls=preload("res://src/input/flight_controls.gd")
const Session=preload("res://src/presentation/first_flight_session.gd")
const Application=preload("res://src/presentation/opening_preview.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Archive=preload("res://src/simulation/station_archive.gd")
const SaveFile=preload("res://src/simulation/station_save_file.gd")
var checks:=0
var failures:=0

class QueueProbe extends "res://src/presentation/first_flight_session.gd":
	var permitted:=true
	var supported_launcher:=true
	func can_control() -> bool:return permitted
	func secondary_available() -> bool:return supported_launcher

func _initialize() -> void:call_deferred("run")

func run() -> void:
	verify_edges()
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:await verify_saved_session(args)
	else:check(false,"Expected one content/binding/visual triple")
	print("Secondary input and saved session: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_edges() -> void:
	var controls:=Controls.new();var queue:=QueueProbe.new()
	var key:=InputEventKey.new();key.physical_keycode=KEY_R;key.pressed=true
	check(controls.accept(key) and controls.take_pressed()==["missiles"],"R did not generate a secondary edge")
	check(queue.action("missiles") and queue._secondary_requested,"Secondary action was not queued")
	check(controls.accept(key) and controls.take_pressed().is_empty(),"Held R generated another edge")
	check(queue.action("missiles") and queue._take_secondary_request() and not queue._take_secondary_request(),"Multiple pre-frame requests did not coalesce to exactly one pass")
	key.pressed=false;controls.accept(key);key.pressed=true
	check(controls.accept(key) and controls.take_pressed()==["missiles"],"A released and pressed key could not detonate")
	for mode in ["clear","blocked","unsupported"]:
		queue.permitted=true;queue.supported_launcher=true
		check(queue.action("missiles"),"Queue setup failed")
		if mode=="clear":queue.clear_flight_input()
		elif mode=="blocked":queue.permitted=false
		else:
			queue.clear_flight_input();queue.supported_launcher=false
			check(not queue.action("missiles"),"Unsupported launcher accepted input")
		check(not queue._take_secondary_request(),"Blocked input leaked into a later frame: "+mode)
		queue.permitted=true
		check(not queue._take_secondary_request(),"Unblocking replayed the previous input: "+mode)
	var button:=InputEventJoypadButton.new();button.device=1;button.button_index=JOY_BUTTON_B;button.pressed=true
	check(controls.accept(button) and controls.take_pressed()==["missiles"],"Controller B did not request a secondary")
	check(controls.accept(button) and controls.take_pressed().is_empty(),"Held controller B repeated detonation")
	controls.clear()
	var trigger:=InputEventJoypadMotion.new();trigger.device=1;trigger.axis=JOY_AXIS_TRIGGER_LEFT;trigger.axis_value=0.9
	check(controls.accept(trigger) and controls.take_pressed()==["missiles"],"Left trigger did not request a secondary")
	check(controls.accept(trigger) and controls.take_pressed().is_empty(),"Held left trigger repeated detonation")
	trigger.axis_value=0.0;controls.accept(trigger);trigger.axis_value=0.9
	check(controls.accept(trigger) and controls.take_pressed()==["missiles"],"Left-trigger release did not rearm the edge")
	controls.set_touch_controls(true)
	check(controls.set_touch_action("missiles",true) and controls.take_pressed()==["missiles"],"Touch secondary action lost its press edge")
	check(controls.set_touch_action("missiles",true) and controls.take_pressed().is_empty(),"Held touch action repeated detonation")
	controls.clear();key.physical_keycode=KEY_G;key.pressed=true
	check(controls.accept(key) and controls.take_pressed()==["secondary_menu"],"G failed to request the menu without firing")
	controls.clear();button.button_index=JOY_BUTTON_DPAD_RIGHT
	check(controls.accept(button) and controls.take_pressed()==["secondary_menu"],"D-pad right failed to request the menu without firing")
	queue.free()
	verify_trigger_boundaries()

func verify_trigger_boundaries() -> void:
	for axis in [JOY_AXIS_TRIGGER_LEFT,JOY_AXIS_TRIGGER_RIGHT]:
		var controls:=Controls.new()
		var event:=InputEventJoypadMotion.new();event.device=7;event.axis=axis;event.axis_value=0.9
		var action: String=Controls.AXIS_ACTIONS[axis]
		check(controls.accept(event) and controls.take_pressed()==[action],"Initial trigger edge is unavailable")
		controls.clear()
		check(controls.accept(event) and controls.take_pressed().is_empty() and not controls.snapshot().held[action],"Clearing input converted a held trigger into a new shot")
		controls.clear()
		check(controls.accept(event) and controls.take_pressed().is_empty(),"Repeated modal clearing lost the trigger release guard")
		event.axis_value=0.25;controls.accept(event);event.axis_value=0.9
		check(controls.accept(event) and controls.take_pressed()==[action],"Returning a trigger to neutral did not rearm it")
		controls.clear();event.device=8
		check(controls.accept(event) and controls.take_pressed()==[action],"A different controller inherited another device's release guard")
		controls.clear();controls.discard_modal_event(event)
		check(controls.accept(event) and controls.take_pressed().is_empty(),"A trigger pressed during a modal leaked into flight")
		event.axis_value=0.0;controls.discard_modal_event(event);event.axis_value=0.9
		check(controls.accept(event) and controls.take_pressed()==[action],"A release inside the menu failed to rearm flight input")
		controls.clear();controls.disconnect_controller(8)
		check(controls.accept(event) and controls.take_pressed()==[action],"A disconnected device retained a stale release guard")

func verify_saved_session(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new();var visuals:=Visuals.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not library.select_language("gb") or not cat.open(library) or not visuals.open(args[2],library.manifest):check(false,library.error+bindings.error+cat.error+visuals.error);return
	var file:=SaveFile.new();var archive:=Archive.new()
	var document:=file.load_document(OS.get_environment("GOF2_SOURCE_SAVE"),bindings,cat,library)
	if document.is_empty():check(false,file.error);return
	var station:=archive.restore(bindings,cat,library,document)
	if station==null:check(false,archive.error);return
	var before: Dictionary=station.snapshot()
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,720)
	var app:=Application.new();root.add_child(app);app.set_process(false)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.set_context(library,bindings,visuals)
	await process_frame
	var live:=Session.new();app.viewport.add_child(live)
	if not live.configure_free(library,bindings,visuals,station,0,4096,1789100000) or not live.activate():check(false,live.error);app.free();return
	app.session=live
	var now:=0
	for tick in 85:
		now+=100000
		if not live.step(now):check(false,live.error);app.free();return
	check(live.can_control() and not live.secondary_available(),"Saved baseline lost normal flight or acquired unearned secondaries")
	var accepted: Dictionary=live.snapshot()
	check(not live.can_open_secondary_menu() and not app.open_secondary_menu(now) and not live.secondary_menu_open(),"An earned flight with no secondary launcher opened its menu")
	check(not live.confirm_secondary(41,now) and not live.close_secondary_menu(now) and live.snapshot()==accepted and not live.is_paused(),"Unsupported menu operations changed the earned flight or left a pause")
	check(live.secondary_feedback().is_empty(),"Saved baseline advertised an unearned equipped launcher")
	app._touch_detected=false
	app.set_touch_controls(true);app.present_session()
	check(not app._flight_actions.visible and not app.touch_overlay.visible,"A touch preference without detected input exposed flight controls")
	var screen_touch:=InputEventScreenTouch.new();screen_touch.device=0;screen_touch.pressed=true
	app._input(screen_touch)
	for touch in [false,true]:
		app.set_touch_controls(touch);app.present_session()
		check(not app._transition_failed and not app.secondary_panel.visible and app.secondary_panel.snapshot().state.is_empty(),"Application exposed secondary controls in unsupported saved flight")
		check(app._flight_actions.visible==touch and app.touch_overlay.visible==touch,"Secondary overlay changed the ordinary touch-controls preference")
	for key_code in [KEY_R,KEY_G]:
		var key:=InputEventKey.new();key.physical_keycode=key_code;key.pressed=true
		app._unhandled_input(key)
		check(not live._secondary_requested and live.snapshot()==accepted,"Application accepted unavailable secondary keyboard input")
	if app.open_map(now):
		check(live.map_open() and not app.secondary_panel.visible and not live._secondary_requested,"Map exposed secondary controls or retained pending fire")
		check(app.close_map(now) and live.snapshot()==accepted,"Closing the actual map changed earned flight state")
	else:check(false,"Saved flight could not exercise the actual application map")
	check(not live.action("missiles") and not live._secondary_requested and live.snapshot()==accepted,"Unsupported saved flight accepted or mutated a secondary action")
	# Seed only the transient input queue, not inventory or the world. These
	# boundaries must discard a pending edge even before a launcher is available.
	for reason in ["user","focus","hidden"]:
		live._secondary_requested=true
		if not live.set_pause(reason,true,now):check(false,live.error);break
		app.present_session()
		check(not app.secondary_panel.visible and not app.secondary_panel.snapshot().activate_enabled,"Paused application retained secondary controls: "+reason)
		check(not live._secondary_requested and not live.can_control(),"Pausing failed to clear queued secondary input: "+reason)
		now+=100000
		if not live.step(now):check(false,live.error);break
		check(live.snapshot()==accepted,"Paused saved flight changed its accepted world")
		if not live.set_pause(reason,false,now):check(false,live.error);break
		check(not live._secondary_requested,"Resuming restored a queued missile press")
	# Input-only queue state is not inventory. Disconnect events must discard
	# an edge already consumed by the application, not just Controls' own edges.
	app._controls.device=17;live._secondary_requested=true
	app._controller_connection(18,false)
	check(live._secondary_requested,"An unrelated controller cancelled the active input queue")
	app._controller_connection(17,true)
	check(live._secondary_requested,"A connection notification cancelled the active input queue")
	app._controller_connection(17,false)
	check(not live._secondary_requested and app._controls.device==-1 and live.snapshot()==accepted,"Disconnecting the active controller left a queued secondary press")
	check(station.snapshot()==before,"Input validation mutated the earned departure station")
	app.reset()
	check(not app.secondary_panel.visible and app.secondary_panel.snapshot().state.is_empty(),"Reset retained the old flight controls")
	app.free()
	await process_frame

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures+=1;push_error(message)
