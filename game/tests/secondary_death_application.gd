extends "res://tests/kappa_preparation_application.gd"
## Earned journey regression: use the last EMP, then verify game over and retry.

func verify_free_application() -> void:
	var original: Dictionary=app.session.station_owner().snapshot()
	check(original.campaign_cursor==24 and original.loadout.station_id==10,"Expected the earned paid Deep Science return")
	if failures:return
	chapter_directory=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	if chapter_directory.is_empty() or not FreePlayCheckpoint.private_path(chapter_directory+"/save.bin"):check(false,"Set a private save directory");return
	app.enable_saves(chapter_directory)
	app.show();app.present_session();await process_frame;resume_application_focus()
	retained_job=original.contracts.mission.duplicate(true)
	if not retain_chapter_save("secondary-death-earned-departure"):return
	var saved_path: String=app.station_save_path()
	var saved_bytes:=FileAccess.get_file_as_bytes(saved_path)
	if not await visit_gate(7,35) or not await release_application_flight():return
	if not await travel_application(37):return
	if not app.open_secondary_menu(now_us):check(false,app.status.text);return
	app.secondary_panel.handle_selection_event(gate_key_event(KEY_DOWN,true))
	if not app.confirm_secondary_selection(41,now_us):check(false,app.status.text);return
	var ready: Dictionary=app.session.snapshot()
	check(ready.encounter.secondaries.guns[0].ammunition==1 and 41 in ready.player.equipment_ids,"Expected one actually owned EMP round")
	if failures:return
	if not app.session.action("missiles"):check(false,app.session.error);return
	if not application_step():return
	var spent: Dictionary=app.session.snapshot()
	check(spent.encounter.secondaries.guns[0].ammunition==0 and 41 not in spent.player.equipment_ids,"The live launcher did not consume its last owned round")
	if failures:return
	if not app.session.action("autopilot"):check(false,app.session.error);return
	await verify_retry(original,saved_path,saved_bytes)

func verify_retry(original: Dictionary,saved_path: String,saved_bytes: PackedByteArray) -> void:
	# Original Carme opponents supply the contacts during ordinary docking.
	for tick in 900:
		if app.session.snapshot().player_destruction.continue_enabled:break
		if not application_step():return
		if tick%20==0:await process_frame
	var dead: Dictionary=app.session.snapshot()
	check(dead.player.vitals.hull==0 and dead.player_destruction.continue_enabled,"Depleted-ammo flight did not reach game over")
	check(dead.campaign_cursor==24 and dead.contracts.credits==original.contracts.credits and dead.contracts.mission==retained_job and dead.contracts.passengers==3,"The failed journey changed the pending story or wallet")
	check(41 not in dead.player.equipment_ids and dead.encounter.secondaries.guns[0].ammunition==0,"Game over recreated spent ammunition")
	if failures:return
	await capture_free_application("secondary-depleted-game-over")
	if not app.session.request_game_over_exit():check(false,app.session.error);return
	var packet: Dictionary=app.session.prepare_game_over()
	check(app.session.status=="game_over_transition_required" and packet.source_state==1 and packet.campaign_cursor==24,"Game-over acknowledgement changed campaign progress")
	if failures:return
	if not app.enter_game_over():check(false,app.status.text);return
	check(app.session==null and FileAccess.get_file_as_bytes(saved_path)==saved_bytes,"Failure exit overwrote the earned checkpoint")
	if not app.load_station(now_us):check(false,app._save_notice.text);return
	check(app.session.station_owner().snapshot()==original,"Retry did not restore the exact earned wallet, passengers and original ammunition")
	await capture_free_application("secondary-depleted-earned-retry")
	print("Actual final EMP launch, native game over, unchanged save and exact earned retry")

func application_step() -> bool:
	resume_application_focus()
	now_us+=100000
	if not app.session.step(now_us):check(false,app.session.error);return false
	app.present_session()
	return true
