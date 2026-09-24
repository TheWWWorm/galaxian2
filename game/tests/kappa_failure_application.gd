extends "res://tests/kappa_rescue_application.gd"
## Diagnostic lethal contacts exercise failure/retirement on an earned entry.
## This branch produces no earned success, mission payment or station save.

func fly_rescue(ready: Dictionary) -> void:
	var saved_path: String=app.station_save_path()
	var saved_bytes:=FileAccess.get_file_as_bytes(saved_path)
	# The shared diagnostic activates each original actor through its real
	# proximity pass before delivering lethal native contacts.
	if not damage_contract_targets(4):return
	check(not app.session.snapshot().dialogue.visible and app.session.snapshot().campaign_cursor==21,"Zero hull bypassed retirement or granted rescue success")
	for tick in 300:
		if app.session.snapshot().dialogue.visible:break
		if not application_step():return
		if tick%20==0:await process_frame
	var failed: Dictionary=app.session.snapshot()
	var outcome: Dictionary=failed.mining_objective.campaign_visit
	var expected: Dictionary=load("res://src/content/free_campaign_definitions.gd").result_presentation(definitions,21,ready.mission,true)
	check(failed.dialogue.visible and outcome.outcome=="failed" and failed.campaign_cursor==21,"Native retirement did not present the original rescue failure")
	check(expected.events.size()==1 and failed.dialogue.text_id==int(expected.events[0].text_id) and failed.dialogue.voice_event_id==-1,"The failure used another instruction or invented speech")
	check(failed.contracts.credits==ready.contracts.credits and failed.contracts.mission==retained_job and failed.contracts.passengers==3,"Failure changed money or the retained passenger contract")
	if failures:return
	await capture_free_application("kappa-failure-diagnostic")
	if not app.session.navigate("next"):check(false,app.session.error);return
	var exit_packet: Dictionary=app.session.prepare_game_over()
	check(app.session.status=="game_over_transition_required" and exit_packet.source_state==1 and exit_packet.campaign_cursor==21 and exit_packet.campaign_failure.outcome=="failed","Failure acknowledgement did not request original source state1")
	check(FileAccess.get_file_as_bytes(saved_path)==saved_bytes,"Acknowledged rescue failure overwrote the earned station save")
	if failures:return
	resume_application_focus()
	if not app.enter_game_over():check(false,app.status.text);return
	check(app.session==null and app.game_over_result().transition==exit_packet,"The application did not leave the failed flight")
	check(FileAccess.get_file_as_bytes(saved_path)==saved_bytes,"Failure exit changed the station checkpoint")
	if not app.load_station(now_us):check(false,app._save_notice.text);return
	check(app.session.station_owner().snapshot()==ready,"Retry failed to restore the exact earned pre-rescue station")
	print("Diagnostic rescue retirement -> original silent failure -> acknowledged menu exit -> exact earned retry")
