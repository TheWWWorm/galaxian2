extends "res://tests/tractor_purchase_application.gd"
## Refit the earned Aquila35 save through Hangar for source shipwreck recovery.

func _initialize() -> void:
	if OS.get_environment("GOF2_SOURCE_SAVE").is_empty():call_deferred("missing_scanner_input")
	else:call_deferred("run_free_checkpoint")

func missing_scanner_input() -> void:
	check(false,"Set GOF2_SOURCE_SAVE to the earned repaired Aquila35 career")
	quit(1)

func verify_free_application() -> void:
	chapter_directory=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	if chapter_directory.is_empty() or not FreePlayCheckpoint.private_path(chapter_directory.path_join("save.bin")):
		check(false,"Set a fresh private scanner fitting save directory");return
	var original: Dictionary=app.session.station_owner().snapshot()
	var devices: Array=original.loadout.slots.slice(2)
	print("Earned Aquila35 slots: ",original.loadout.slots,"; cargo ",original.cargo.entries)
	check(original.campaign_cursor==24 and original.loadout.station_id==35 and original.mission.station_id==48,"The scanner refit requires the real repaired Aquila35 Sahi prerequisite")
	check(original.contracts.credits==2771 and original.contracts.passengers==3 and original.cargo.capacity==25,"The repaired supplier stop lost its paid wallet, passengers or original hold")
	check(original.loadout.slots.size()==5 and devices.size()==3 and devices.all(func(slot):return slot!=null and int(slot.category)==3),"The source ship no longer has three occupied device slots")
	check(original.loadout.equipment_ids.has(2) and original.loadout.equipment_ids.has(43) and original.loadout.equipment_ids.has(55) and original.loadout.equipment_ids.has(68) and original.loadout.equipment_ids.has(91) and not original.loadout.equipment_ids.has(81),"The repaired paid loadout does not have the expected armor, tractor, cabin and weapons")
	check(original.cargo.entries.any(func(row):return int(row.item_id)==81 and int(row.quantity)==1),"The earned scanner81 is not owned in cargo")
	check(emp_rounds(original)==10,"The actual purchased EMP43 launcher lost its ten rounds")
	if failures:return
	var quantities:=inventory_quantities(original)
	var armor_slot:=-1
	for index in original.loadout.slots.size():
		var installed: Variant=original.loadout.slots[index]
		if installed!=null and int(installed.item_id)==55:armor_slot=index;break
	check(armor_slot>=2,"The earned armor is not in a replaceable device slot")
	if failures:return
	app.enable_saves(chapter_directory)
	app.show();app.present_session();await process_frame;resume_application_focus()
	if not app.equipment_action("open"):check(false,app.status.text);return
	check(app.equipment_panel.visible and app.equipment_panel._installed_rows.has(armor_slot),"Actual Hangar did not expose the occupied armor slot")
	if failures:return
	if not mount_owned_device(81,10):return
	var fitted: Dictionary=app.session.station_owner().snapshot()
	check(fitted.loadout.slots[armor_slot]!=null and int(fitted.loadout.slots[armor_slot].item_id)==81 and fitted.loadout.equipment_ids.has(68) and fitted.loadout.equipment_ids.has(91),"The real fitting failed to retain scanner, tractor and cabin together")
	check(not fitted.loadout.equipment_ids.has(55) and fitted.cargo.entries.any(func(row):return int(row.item_id)==55 and int(row.quantity)==1),"Replacing armor did not return its owned unit to cargo")
	check(inventory_quantities(fitted)==quantities and fitted.cargo.used==original.cargo.used and emp_rounds(fitted)==10,"Fitting changed owned quantities, hold usage or paid EMP ammunition")
	check(fitted.contracts.credits==2771 and fitted.contracts.passengers==3 and fitted.contracts.mission==original.contracts.mission and fitted.mission==original.mission,"Fitting changed wallet, passengers or pending Sahi story")
	if failures:return
	if not app.equipment_action("close"):check(false,app.status.text);return
	var ready: Dictionary=app.session.station_owner().snapshot()
	check(ready.campaign_cursor==24 and ready.loadout.station_id==35 and ready.mission==original.mission and ready.progress==original.progress,"Closing Hangar changed earned campaign or progress")
	check(ready.contracts.credits==2771 and ready.contracts.passengers==3 and ready.contracts.mission==original.contracts.mission and ready.contracts.completed_side_missions==original.contracts.completed_side_missions and ready.contracts.progress==original.contracts.progress and ready.contracts.travel_statistics==original.contracts.travel_statistics,"Closing Hangar changed durable wallet, job or travel progress")
	if failures or not retain_chapter_save("sahi-route-station35-scanner"):return
	var loaded: Dictionary=app.session.station_owner().snapshot()
	check(inventory_quantities(loaded)==quantities and loaded.loadout.slots[armor_slot].item_id==81 and loaded.contracts.credits==2771 and loaded.contracts.passengers==3 and emp_rounds(loaded)==10,"The genuine scanner-equipped save lost paid inventory or passengers")
	if failures:return
	if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
	var flight: Dictionary=app.session.snapshot()
	check(flight.campaign_cursor==24 and flight.location.station_id==35 and flight.tractor.equipment_id==68 and flight.tractor.scanner_id==81,"Native Aquila departure did not bind the fitted tractor and ship scanner")
	check(flight.player.equipment_ids==loaded.loadout.equipment_ids and flight.cargo==loaded.cargo and flight.contracts.credits==2771 and flight.contracts.passengers==3 and flight.mission==loaded.mission,"Departure changed the genuine saved inventory or pending Sahi career")
	print("Earned scanner-equipped route prerequisite: ",chapter_directory.path_join("sahi-route-station35-scanner.gof2save"))

func inventory_quantities(state: Dictionary) -> Dictionary:
	var totals:={}
	for row in state.cargo.entries:
		var id: int=int(row.item_id)
		totals[id]=int(totals.get(id,0))+int(row.quantity)
	for slot in state.loadout.slots:
		if slot==null:continue
		var id: int=int(slot.item_id)
		totals[id]=int(totals.get(id,0))+int(slot.quantity)
	return totals

func emp_rounds(state: Dictionary) -> int:
	for slot in state.loadout.slots:
		if slot!=null and int(slot.item_id)==43:return int(slot.quantity)
	return 0
