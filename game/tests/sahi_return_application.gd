extends "res://tests/sahi_application.gd"
## Resume the application's earned Sahi return for ordinary departure checks.

func verify_free_application() -> void:
	var landed: Dictionary=app.session.station_owner().snapshot()
	check(landed.campaign_cursor==27 and landed.loadout.station_id==48 and landed.mission.kind==11 and landed.mission.station_id==10,"Use the application's earned Sahi return")
	if failures:return
	retained_job=landed.contracts.mission.duplicate(true)
	route_credits=int(landed.contracts.credits)
	app.show();app.present_session();await process_frame;resume_application_focus()
	await verify_sahi_return_departure(landed)
	if failures or not await acquire_application_planet(45):return
	var departing: Dictionary=app.session.snapshot()
	if not app.enter_local_arrival(now_us,4096,1789100000):check(false,app.status.text);return
	var arrived: Dictionary=app.session.snapshot()
	check(arrived.location.station_id==45 and arrived.campaign_cursor==27,"The earned Sahi return did not reach ordinary Weymire")
	check(arrived.progress==departing.progress and arrived.contracts.progress==arrived.progress and arrived.progress.cargo_recovered==landed.progress.cargo_recovered,"Ordinary arrival lost or duplicated the earned recovered-cargo statistic")
	check(arrived.cargo==departing.cargo and arrived.contracts.credits==route_credits and arrived.contracts.mission==retained_job,"Ordinary arrival changed the retained cargo, wallet or passengers")
