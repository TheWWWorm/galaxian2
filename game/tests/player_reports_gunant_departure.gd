extends "res://tests/combat_training_flight.gd"
## Replay the actual equipment prerequisite and existing combat/contact fixture,
## then use real input and isolated autosaves for the post-Gunant conversation
## and departure. This covers the earned training return, not later campaign.
var departed_after_gunant:=false
var gunant_saves:=""

func run() -> void:
	var args:=training_arguments()
	if args.size() not in [3,4]:check(false,"Expected content, bindings and visuals");quit(1);return
	gunant_saves=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	if gunant_saves.is_empty() or not preload("res://tests/fixtures/convoy_station_scenario.gd").private_path(gunant_saves.path_join("station.gof2save")):
		check(false,"Set a private save directory for the player departure path");quit(1);return
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not lib.select_language("gb") or not visuals.open(args[2],lib.manifest):check(false,lib.error+bindings.error+visuals.error);quit(1);return
	await verify_training_application(args)
	check(departed_after_gunant,"The real post-Gunant application never released its next flight")
	if is_instance_valid(host):host.free()
	print("Player-reported Gunant departure: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func after_training_application_reload(args: PackedStringArray) -> void:
	if failures:return
	host.set_player_mode(true)
	# The player frontend always autosaves. A development-only host with saves
	# disabled can launch even when that real departure transaction would fail.
	host.enable_saves(gunant_saves)
	var station: Node=host.session
	station.rebase_time(now_us)
	for tick in 10:
		if not training_app_step():return
	for event in bindings.mido_travel.conversations[0].events:
		check(station.snapshot().dialogue.text_id==int(event.text_id),"Post-Gunant dialogue skipped an original line")
		input_key(KEY_ENTER)
		if failures:return
	var accepted: Dictionary=station.snapshot()
	check(accepted.campaign_cursor==10 and accepted.phase=="local_departure_required","Final dialogue acknowledgement left departure locked")
	check(FileAccess.file_exists(host.station_save_path()),"Post-Gunant acknowledgement did not autosave: "+host._save_notice.text)
	check(host.station_shell.visible and host.station_shell._actions.map.visible,"Earned post-Gunant station omitted Map")
	check(host.open_map(now_us) and host.map_panel.visible,"Earned post-Gunant Map could not open")
	check(host.close_map(now_us) and host.session.snapshot()==accepted,"Closing the post-Gunant Map changed the earned station")
	input_key(KEY_ENTER)
	check(host._launch_dialog.visible and station.snapshot()==accepted,"Enter did not offer departure confirmation")
	input_key(KEY_ESCAPE)
	check(not host._launch_dialog.visible and station.snapshot()==accepted,"Cancelling post-Gunant departure changed the station")
	input_key(KEY_ENTER)
	if args.size()==4:await capture(args[3],"gunant-departure-question")
	await process_frame;await process_frame
	click_yes()
	check(host.session is TrainingSession and not host._launch_dialog.visible,"Confirming post-Gunant departure did not launch: "+host.status.text+" / "+host._save_notice.text)
	if failures:return
	host.session.rebase_time(now_us)
	for tick in 71:
		if not training_app_step():return
	check(host.session.can_control() and host.session.snapshot().campaign_cursor==10,"Post-Gunant launch did not release flight controls")
	check(host.session.snapshot().cargo==accepted.cargo and host.session.snapshot().equipment==accepted.equipment and host.session.snapshot().progress==accepted.progress,"Post-Gunant launch changed earned inventory or story")
	departed_after_gunant=failures==0
	if args.size()==4:await capture(args[3],"gunant-departure-flight")

func mine_on_training_return() -> bool:
	# Reproduce returning immediately after the pirate fight. The base
	# integration separately covers optional mining before docking.
	return false

func verify_training_game_over(_args: PackedStringArray,_packet: Dictionary,_equipment: RefCounted) -> void:
	pass

func input_key(code: int) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=pressed
		Input.parse_input_event(event);Input.flush_buffered_events()

func click_yes() -> void:
	var point: Vector2=host._launch_dialog._yes.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point
	Input.parse_input_event(motion);Input.flush_buffered_events()
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT
		event.position=point;event.global_position=point;event.pressed=pressed
		Input.parse_input_event(event);Input.flush_buffered_events()
