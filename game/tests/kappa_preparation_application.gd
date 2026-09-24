extends "res://tests/campaign_visit_application.gd"
## Resume an earned identity-matching career, fly the Kappa visit, then acquire
## and install the original station reserve through the actual service controls.
var chapter_directory:=""

func verify_free_application() -> void:
	chapter_directory=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	if chapter_directory.is_empty() or not FreePlayCheckpoint.private_path(chapter_directory+"/save.bin"):check(false,"Set a private chapter save directory");return
	app.enable_saves(chapter_directory)
	app.show();app.present_session();await process_frame;resume_application_focus()
	var initial: Dictionary=app.session.station_owner().snapshot()
	check((initial.campaign_cursor==19 and initial.loadout.station_id==56) or (initial.campaign_cursor==20 and initial.loadout.station_id==55),"Resume the genuinely earned Suttnar or Kappa fitting checkpoint")
	if failures:return
	retained_job=initial.contracts.mission.duplicate(true)
	if initial.campaign_cursor==19 and not await visit_kappa(initial):return
	var landed: Dictionary=app.session.station_owner().snapshot()
	check(landed.campaign_cursor==20 and landed.loadout.station_id==55 and landed.contracts.completed_side_missions==4,"Kappa docking lost the earned career")
	var reserve: Array=app.session.station_owner().contract_owner().location_owner().item_stock(55).filter(func(row):return int(row.item_id)==41)
	check(not reserve.is_empty() and reserve.all(func(row):return row.unit_price==0) and reserve[0].quantity>=10,"The actual station entry did not add its original free reserve")
	if failures or not retain_chapter_save("kappa20-before-fitting"):return
	check(not app.request_departure() and app.session.error==source.strings[520],"The unfinished fitting lesson did not show original launch refusal520")
	if not app.equipment_action("open"):check(false,app.status.text);return
	var panel: Control=app.equipment_panel
	panel.select_tab("shop")
	for unit in 10:panel._rows[41].actions.buy.pressed.emit()
	var bought: Dictionary=app.session.station_owner().snapshot()
	check(bought.contracts.credits==initial.contracts.credits and bought.cargo.used==landed.cargo.used+10 and not bought.loadout.equipment_ids.has(41),"Free purchases changed the wallet or silently fitted ammunition")
	panel.select_tab("cargo");panel._rows[41].actions.mount.pressed.emit()
	var fitted: Dictionary=app.session.station_owner().snapshot()
	var rounds: Array=fitted.loadout.slots.filter(func(slot):return slot!=null and int(slot.item_id)==41)
	check(rounds.size()==1 and rounds[0].quantity==10 and fitted.cargo==landed.cargo and fitted.campaign_cursor==20,"Mounting failed to transfer the complete reserve or bypassed the lesson")
	if failures:return
	if not app.equipment_action("close"):check(false,app.status.text);return
	app.session.rebase_time(now_us)
	for tick in 60:
		if app.session.snapshot().dialogue.visible:break
		now_us+=100000
		if not app.session.step(now_us):check(false,app.session.error);return
	var lesson: Dictionary=app.session.snapshot()
	check(lesson.campaign_conversation and lesson.dialogue.visible and lesson.dialogue.text_id==int(definitions.mido_travel.kappa_preparation.fitting.events[0].text_id) and lesson.campaign_cursor==20,"The fitted EMP did not open the original acknowledged lesson")
	await capture_free_application("kappa-fitting-lesson")
	app.station_navigation("next")
	app.present_session()
	var ready: Dictionary=app.session.station_owner().snapshot()
	check(ready.campaign_cursor==21 and ready.mission=={"kind":4,"station_id":55,"reward":0,"bonus":0,"source_parameter":0},"The final fitting acknowledgement did not select the rescue: "+str({"phase":ready.phase,"cursor":ready.campaign_cursor,"status":app.status.text,"session_error":app.session.error,"paused":app.session.is_paused(),"focused":app._focused}))
	check(ready.contracts.mission==retained_job and ready.contracts.passengers==3 and ready.contracts.credits==initial.contracts.credits,"Fitting changed the retained job, passengers or wallet")
	if failures or not retain_chapter_save("kappa21-fitted"):return
	check(app.request_departure(),app.session.error)
	app.cancel_departure()
	print("Earned Kappa19 visit ->20 actual reserve/purchase/fitting ->21 lesson acknowledgement and source launch permission")
	await after_kappa_fitting(ready)

func visit_kappa(initial: Dictionary) -> bool:
	if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return false
	if not await release_application_flight() or not await acquire_application_planet(55):return false
	if not app.enter_local_arrival(now_us,4096,1789100000):check(false,app.status.text);return false
	var arrival: Dictionary=app.session.snapshot()
	check(arrival.location.station_id==55 and arrival.location.system_id==11 and arrival.encounter.combat.actors.is_empty(),"Kappa visit selected a different world or invented ordinary ships")
	var field: RefCounted=app.session.flight_owner()._scenery.presentation_identity()
	var identity: RefCounted=app.session.flight_owner()._encounter._control.flight_identity()
	for tick in 125:
		if app.session.snapshot().dialogue.visible:break
		if not application_step():return false
	var opened: Dictionary=app.session.snapshot()
	check(opened.dialogue.visible and opened.world_elapsed_ms>10000 and opened.campaign_cursor==19,"Kappa visit did not wait for its original flight/HUD clocks")
	if failures:return false
	for event in definitions.mido_travel.kappa_preparation.visit.events:
		var current: Dictionary=app.session.snapshot()
		check(current.dialogue.text_id==int(event.text_id) and current.dialogue.voice_event_id==int(event.voice_event_id) and current.campaign_cursor==19,"The visit changed original text, voice or acknowledgement order")
		await capture_free_application("kappa-visit-%d"%int(event.text_id))
		if not app.session.navigate("next"):check(false,app.session.error);return false
	var completed: Dictionary=app.session.snapshot()
	check(completed.campaign_cursor==20 and completed.mission.kind==189 and completed.mission.station_id==55,"The acknowledged visit did not select the original fitting lesson")
	check(app.session.flight_owner()._scenery.presentation_identity()==field and app.session.flight_owner()._encounter._control.flight_identity()==identity,"The visit regenerated its retained flight")
	check(completed.contracts.credits==initial.contracts.credits and completed.contracts.mission==retained_job and completed.contracts.passengers==3,"The visit changed the wallet or accepted passengers")
	if failures or not await dock_application():return false
	return failures==0

func after_kappa_fitting(_ready: Dictionary) -> void:pass

func retain_chapter_save(label: String) -> bool:
	var before: Dictionary=app.session.station_owner().snapshot()
	if not app.save_station():check(false,app._save_notice.text);return false
	var path:=chapter_directory.path_join(label+".gof2save")
	if FileAccess.file_exists(path):check(false,"Use a fresh output directory for earned checkpoints");return false
	if DirAccess.copy_absolute(app.station_save_path(),path)!=OK:check(false,"Could not retain the actual station save");return false
	if not app.load_station(now_us):check(false,app._save_notice.text);return false
	check(app.session.station_owner().snapshot()==before,"Save/load changed actual story, stock, inventory or career: "+label)
	print("Earned native station: ",path)
	return failures==0
