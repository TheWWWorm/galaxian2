extends "res://tests/sahi_application.gd"
## Resume an earned Sahi station, follow the original expedition and retain its
## actual return. All motion, combat, fitting and dialogue use application input.

func verify_free_application() -> void:
	var original: Dictionary=app.session.station_owner().snapshot()
	check((original.campaign_cursor==27 and original.loadout.station_id==48) or (original.campaign_cursor==28 and original.loadout.station_id in [10,35,90]),"Resume an earned Sahi, Thynome, Aquila or Pescal Inartu expedition station")
	if failures:return
	chapter_directory=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	if chapter_directory.is_empty() or not FreePlayCheckpoint.private_path(chapter_directory+"/save.bin"):check(false,"Set a private expedition save directory");return
	app.enable_saves(chapter_directory)
	retained_job=original.contracts.mission.duplicate(true);route_credits=int(original.contracts.credits)
	app.show();app.present_session();await process_frame;resume_application_focus()
	if original.campaign_cursor==27:
		if not original.loadout.equipment_ids.has(43) and not purchase_route_emp(10,false):return
		if not fit_owned_expedition_armor():return
		if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
		if not await release_application_flight() or not await travel_application(45):return
		for destination in [[11,55],[7,35],[6,10]]:
			if not await expedition_gate(destination[0],destination[1]):return
		if not await dock_application() or not await acknowledge_station_chapter(27):return
		var acknowledged: Dictionary=app.session.station_owner().snapshot()
		check(acknowledged.campaign_cursor==28 and acknowledged.loadout.station_id==10 and acknowledged.mission=={"kind":4,"station_id":91,"reward":0,"bonus":0,"source_parameter":0},"Thynome changed its original destination or relocated the player")
		check(acknowledged.contracts.credits==route_credits and acknowledged.contracts.mission==retained_job and acknowledged.contracts.passengers==3,"Thynome paid an unearned reward or changed accepted passengers")
		if failures or not retain_chapter_save("thynome28-departure"):return
		if OS.get_environment("GOF2_EXPEDITION_THYNOME_ONLY")=="1":
			print("Earned Sahi27 -> Thynome original result -> mission28 station save/load")
			return
	if original.loadout.station_id==35 and OS.get_environment("GOF2_EXPEDITION_AQUILA_ONLY")=="1":
		if not sell_expedition_spares() or not purchase_route_emp(10,false):return
		if retain_chapter_save("dima28-aquila"):print("Earned Aquila28 paid ammunition and station save/load")
		return
	if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
	if not await release_application_flight():return
	if original.loadout.station_id!=90:
		if original.loadout.station_id!=35:
			if not await expedition_gate(7,35) or not await dock_with_paid_emp(2147483647):return
			if not sell_expedition_spares() or not purchase_route_emp(10,false):return
			if not retain_chapter_save("dima28-aquila"):return
			if OS.get_environment("GOF2_EXPEDITION_AQUILA_ONLY")=="1":
				print("Earned Thynome28 -> Aquila paid ammunition and station save/load")
				return
			if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
			if not await release_application_flight():return
		for destination in [[11,55],[9,45],[2,30],[8,40],[18,90]]:
			if not await expedition_gate(destination[0],destination[1]):return
		if not await dock_with_paid_emp(2147483647):return
		if not retain_chapter_save("dima28-staging"):return
		if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
		if not await release_application_flight():return
	if not await acquire_application_planet(91):return
	if not app.enter_local_arrival(now_us,4096,1789100000):check(false,app.status.text);return
	var dima: Dictionary=app.session.snapshot()
	check(dima.campaign_cursor==28 and dima.location.station_id==91 and dima.actors.size()==8 and dima.has("void_portal"),"The earned route did not select the original Dima cast and portal")
	check(dima.contracts.credits==route_credits and dima.contracts.mission==retained_job and dima.contracts.passengers==3,"The Dima route changed the retained wallet or passengers")
	if failures:return
	var pilot=load("res://tests/fixtures/expedition_flight_pilot.gd")
	var contact: RefCounted=await pilot.enter_portal(app.session.flight_owner(),Callable(self,"advance_story"),Callable(self,"capture_story"),Callable(self,"check"),process_frame)
	if contact==null or not adopt_expedition_portal(29):return
	var explored: RefCounted=await pilot.complete_probe(app.session.flight_owner(),Callable(self,"advance_story"),Callable(self,"capture_story"),Callable(self,"check"),process_frame,Callable(self,"navigate_expedition"))
	if explored==null:return
	var result: Dictionary=app.session.snapshot()
	check(result.campaign_cursor==29 and result.void_probe_stage.phase==2 and result.void_probe_stage.stage_elapsed_ms>180000 and result.mining_objective.mission_completed,"The expedition result bypassed the original post-probe wait")
	check(not app.session.flight_owner().void_return_required(),"The result opened an exit before acknowledgement")
	if failures or not await acknowledge_story_lines(definitions.mido_travel.void_probe.mission29.result_events):return
	var acknowledged_probe: Dictionary=app.session.snapshot()
	check(acknowledged_probe.campaign_cursor==30 and acknowledged_probe.location.station_id==-1,"Final probe Next changed location or failed to retire the selected mission")
	if failures:return
	contact=await pilot.enter_portal(app.session.flight_owner(),Callable(self,"advance_story"),Callable(self,"capture_story"),Callable(self,"check"),process_frame)
	if contact==null or not adopt_expedition_portal(30):return
	var returned: Dictionary=app.session.snapshot()
	check(returned.location.station_id==91 and returned.location.system_id==18 and returned.actors.is_empty() and not returned.has("void_probe"),"The original return did not select Dima's ordinary visit")
	if failures or not await acknowledge_story_lines(definitions.mido_travel.dima_return.result30.result_events):return
	var next: Dictionary=app.session.snapshot()
	check(next.campaign_cursor==31 and next.mission=={"kind":11,"station_id":98,"reward":30000,"bonus":0,"source_parameter":0} and next.location.station_id==91,"Dima result lost the pending Alioth mission or changed location")
	check(next.cargo==returned.cargo and next.contracts.credits==route_credits and next.contracts.mission==retained_job and next.contracts.passengers==3,"Dima acknowledgement paid the future reward or changed cargo/passengers")
	if failures or not await dock_application():return
	var landed: Dictionary=app.session.station_owner().snapshot()
	check(landed.campaign_cursor==31 and landed.loadout.station_id==91 and landed.contracts.credits==route_credits and landed.cargo==next.cargo,"Dima docking lost the earned expedition")
	if failures or not retain_chapter_save("dima31-return"):return
	await capture_free_application("earned-dima31-station")
	if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
	if not await release_application_flight():return
	var departed: Dictionary=app.session.snapshot()
	check(departed.campaign_cursor==31 and departed.location.station_id==91 and not departed.has("void_probe") and not departed.has("void_portal") and departed.progress==landed.progress and departed.cargo==landed.cargo,"Ordinary Dima departure replayed the completed expedition or changed progress")
	print("Earned Thynome27 result -> Dima28 portal -> Void29 probe -> Dima30 result ->31 docking, save/load and departure")

func navigate_expedition(_frame: RefCounted,action: String) -> RefCounted:
	if not app.session.navigate(action):check(false,app.session.error);return null
	return app.session.flight_owner()

func expedition_gate(system_id: int,station_id: int) -> bool:
	if not await follow_gate_course(system_id,station_id) or not await release_application_flight():return false
	var state: Dictionary=app.session.snapshot()
	check(state.contracts.credits==route_credits and state.contracts.mission==retained_job and state.contracts.passengers==3,"Expedition gate changed the retained wallet or passenger job")
	return failures==0

func reach_gate_confirmation() -> bool:
	# Save the purchased rounds until a hostile actually recovers its systems.
	return await reach_paid_gate_confirmation(2147483647,false)

func sell_expedition_spares() -> bool:
	if not app.equipment_action("open"):check(false,app.status.text);return false
	var before: Dictionary=app.session.station_owner().snapshot()
	var panel: Control=app.equipment_panel
	var expected_cargo: Dictionary=before.cargo.duplicate(true)
	var proceeds:=0
	for item_id in [0,22]:
		var rows: Array=before.equipment.market_rows.filter(func(row):return row.item_id==item_id and row.owned==1 and not row.mission and row.unit_price>0)
		check(rows.size()==1 and expected_cargo.entries.any(func(row):return row.item_id==item_id and row.quantity==1),"The expedition lacks its actual unprotected spare for sale")
		if failures:return false
		panel.select_tab("cargo")
		check(panel._rows.has(item_id) and not panel._rows[item_id].actions.sell.disabled,"The owned spare cannot be sold through the station UI")
		if failures:return false
		panel._rows[item_id].actions.sell.pressed.emit()
		proceeds+=int(rows[0].unit_price);expected_cargo.used-=1
		expected_cargo.free_space+=1
		expected_cargo.entries=expected_cargo.entries.filter(func(row):return row.item_id!=item_id)
	var after: Dictionary=app.session.station_owner().snapshot()
	check(after.contracts.credits==before.contracts.credits+proceeds and after.cargo==expected_cargo and after.loadout==before.loadout,"The normal spare sales changed the wrong cargo, equipment or amount of credits")
	check(after.progress==before.progress and after.mission==before.mission and after.contracts.mission==retained_job and after.contracts.passengers==3,"Trading spares changed the earned campaign or occupied passenger cabin")
	if failures or not app.equipment_action("close"):check(false,app.status.text);return false
	route_credits=int(after.contracts.credits)
	print("Earned expedition spare sales: ",proceeds," credits, retained wallet ",route_credits)
	return true

func fit_owned_expedition_armor() -> bool:
	var before: Dictionary=app.session.station_owner().snapshot()
	check(before.loadout.equipment_ids.has(81) and before.loadout.equipment_ids.has(91),"The earned expedition lost its scanner or occupied cabin")
	if failures:return false
	if before.loadout.equipment_ids.has(55):return true
	check(before.loadout.equipment_ids.has(68) and before.cargo.entries.any(func(row):return row.item_id==55 and row.quantity==1),"Use only the already owned armor and tractor slot")
	if failures or not app.equipment_action("open"):check(false,app.status.text);return false
	if not mount_owned_device(55,int(catalogue.tables.items[68].arrays[2][5])):return false
	if not app.equipment_action("close"):check(false,app.status.text);return false
	var after: Dictionary=app.session.station_owner().snapshot()
	check(after.loadout.equipment_ids.has(55) and after.loadout.equipment_ids.has(81) and after.loadout.equipment_ids.has(91) and after.cargo.used==before.cargo.used and after.contracts.credits==before.contracts.credits and after.progress==before.progress,"Owned armor fitting changed cargo quantity, scanner, passengers or earned progress")
	return failures==0

func adopt_expedition_portal(cursor: int) -> bool:
	var before: Dictionary=app.session.snapshot()
	if not app.enter_portal_arrival(now_us,4096,1789100000):check(false,app.status.text);return false
	var after: Dictionary=app.session.snapshot()
	# Arrival caches truncate charge; the live combat owner restores binary32 pools.
	var pools: Dictionary=before.player.vitals.duplicate(true);pools.shield=float(int(pools.shield))
	print("Expedition portal adoption: ",{"cursor":after.campaign_cursor,"expected_cursor":cursor,"before_vitals":before.player.vitals,"after_vitals":after.player.vitals,"before_gamma":before.player.gamma,"after_gamma":after.player.gamma,"cargo_equal":after.cargo==before.cargo})
	if after.cargo!=before.cargo:print("Expedition portal cargo: ",{"before":before.cargo,"after":after.cargo})
	check(after.campaign_cursor==cursor and after.player.vitals==pools and int(after.player.gamma)==int(before.player.gamma) and after.cargo==before.cargo,"Portal adoption changed retained player pools, cargo or next mission")
	check(after.contracts.credits==before.contracts.credits and after.contracts.mission==retained_job and after.contracts.passengers==3,"Portal adoption lost the earned wallet or accepted passengers")
	return failures==0
