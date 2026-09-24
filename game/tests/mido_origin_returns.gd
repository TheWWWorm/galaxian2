extends "res://tests/mido_application.gd"
## Repeat the actual earned three-leg introduction, inserting a return to each
## origin before pursuing its destination. Combat fixtures remain inherited.

func verify_local_session_journey(args: PackedStringArray,existing: Node=null):
	if existing==null:check(false,"Expected the actual local departure");return
	if not await verify_origin_return():return
	if not host.request_departure() or not host.enter_first_flight(now_us,1789100000,1789100000):check(false,host.status.text);return
	host.session.rebase_time(now_us)
	await super.verify_local_session_journey(args,host.session)

func verify_yrdal_application(args: PackedStringArray,cursor: int=11):
	if not host.request_departure() or not host.enter_first_flight(now_us,1789100000,1789100000):check(false,host.status.text);return
	host.session.rebase_time(now_us)
	if not await verify_origin_return():return
	await super.verify_yrdal_application(args,cursor)

func verify_origin_return() -> bool:
	var origin: RefCounted=host.session.flight_owner().departure_station_owner()
	check(origin!=null,"Departure did not retain its acknowledged origin")
	if failures:return false
	var before: Dictionary=origin.snapshot()
	for tick in 100:
		if host.session.can_control():break
		if not training_app_step():return false
	check(host.session.can_control(),"Entry did not release origin-return controls")
	if failures:return false
	check(host.session.action("station_autopilot"),host.session.error)
	for tick in 1000:
		if host.session.status=="station_transition_required":break
		if not training_app_step():return false
	check(host.session.status=="station_transition_required","Selected origin did not reach the docking boundary")
	if failures:return false
	check(host.enter_station(now_us,42),host.status.text)
	check(host.session is Station,"Accepted origin docking did not enter the station")
	if failures:return false
	var after: Dictionary=host.session.snapshot()
	check(after.campaign_cursor==before.campaign_cursor and after.mission==before.mission,"Origin return completed an unvisited destination")
	check(after.loadout==before.loadout and after.equipment==before.equipment,"Origin return repeated an exchange or changed equipment")
	check(not after.dialogue.visible and after.phase==before.phase,"Origin return replayed station dialogue")
	check(after.progress==before.progress,"Origin return changed earned story progress")
	print("Verified local origin return at cursor ",after.campaign_cursor," station ",after.loadout.station_id)
	return failures==0
