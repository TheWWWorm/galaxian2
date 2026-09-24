extends "res://tests/expedition_application.gd"
## Continue the earned Dima return through original travel, station dialogue,
## payment and save/load. Each retained route checkpoint comes from real input.
const PostProbeCampaign=preload("res://src/content/free_campaign_definitions.gd")
const PostProbeNavigation=preload("res://src/content/free_navigation_definitions.gd")
const ALIOTH_ROUTE=[[18,90],[8,40],[2,30],[9,45],[11,55],[14,70],[19,95]]
var _world_clock_base:=1789100000
var _retained_client: Dictionary={}

func flight_world_seconds() -> int:
	# The application's normal entry samples the current clock for each world.
	# Advance the deterministic pilot clock rather than freezing every encounter.
	var seconds:=_world_clock_base+int(now_us/1000000)
	print("Earned Alioth world Unix time ",seconds)
	return seconds

func verify_free_application() -> void:
	var saved_clock:=OS.get_environment("GOF2_ALIOTH_WORLD_BASE")
	if not saved_clock.is_empty():
		check(saved_clock.is_valid_int() and saved_clock.to_int()>=0 and saved_clock.to_int()<2147480000,"Use the recorded Unix clock base when replaying an earned route checkpoint")
		if failures:return
		_world_clock_base=saved_clock.to_int()
	var original: Dictionary=app.session.station_owner().snapshot()
	check(PostProbeCampaign.post_probe_available(definitions.mido_travel),"The earned continuation requires its post-probe declarations")
	check(original.campaign_cursor in [31,32] and original.mission==PostProbeCampaign.mission(definitions.mido_travel,original.campaign_cursor),"Resume the earned pending or acknowledged Alioth result")
	check(original.contracts.passengers==3 and original.contracts.mission.kind==11 and original.contracts.mission.station_id==99,"The earned Alioth route lost its accepted passengers")
	if failures:return
	chapter_directory=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	if chapter_directory.is_empty() or not FreePlayCheckpoint.private_path(chapter_directory+"/save.bin"):check(false,"Set a private Alioth save directory");return
	app.enable_saves(chapter_directory)
	retained_job=original.contracts.mission.duplicate(true);route_credits=int(original.contracts.credits)
	_retained_client=original.contracts.accepted_contact.duplicate(true)
	app.show();app.present_session();await process_frame;resume_application_focus()
	if original.campaign_cursor==32:
		check(original.loadout.station_id==98,"Resume the actual acknowledged Alioth32 station")
		if not failures:await verify_alioth_continuation(original)
		return
	if original.loadout.station_id!=98:
		if not await travel_to_alioth(original):return
	var landed: Dictionary=app.session.station_owner().snapshot()
	check(landed.campaign_cursor==31 and landed.loadout.station_id==98 and landed.loadout.system_id==19 and landed.contracts.credits==route_credits,"The actual route did not reach Alioth with the unpaid reward")
	check(landed.contracts.accepted_contact==_retained_client,"Returning to the regenerated source lounge changed the accepted passenger client")
	# Arrival opens the original result immediately. Its unacknowledged state
	# cannot be archived; the latest safe route station is the retry checkpoint.
	if failures:return
	if not await acknowledge_station_chapter(31):return
	var paid: Dictionary=app.session.station_owner().snapshot()
	check(paid.campaign_cursor==32 and paid.loadout==landed.loadout and paid.cargo==landed.cargo and paid.player_cache.values==landed.player_cache.values,"Alioth final Next changed the current location, inventory or flight pools")
	check(paid.contracts.credits==landed.contracts.credits+30000 and paid.reward_credits==30000 and not paid.has("next_course"),"Alioth paid another amount or forced a navigation course")
	check(paid.contracts.mission==retained_job and paid.contracts.passengers==landed.contracts.passengers and paid.contracts.travel_statistics==landed.contracts.travel_statistics,"Alioth final Next changed an accepted job, passenger or gate history")
	if landed.contracts.has("void_source"):
		check(paid.contracts.void_source==landed.contracts.void_source and paid.contracts.void_source.eligible_selection_count==0,"Alioth final Next counted an unchanged location or lost its native Void source")
		check(paid.contracts.blueprints==landed.contracts.blueprints,"Alioth final Next changed the retained blueprint recipes")
	var access: Array=app.session.station_owner().contract_owner().location_owner().snapshot().system_availability
	check(access==landed.contracts.lounges.system_availability,"Alioth final Next granted unearned system access")
	var station: RefCounted=app.session.station_owner()
	check(not station.acknowledge() and not station.begin_campaign_conversation(definitions,catalogue,source) and station.snapshot()==paid,"The acknowledged Alioth result paid or opened twice")
	if failures or not retain_chapter_save("alioth32-paid"):return
	await verify_alioth_continuation(paid)
	if not failures:print("Earned Dima31 -> actual Alioth travel -> ten original result lines ->30000 credits -> mission32 station save/load and ordinary departure")

func travel_to_alioth(original: Dictionary) -> bool:
	var current: int=original.loadout.station_id
	check(current==91 or ALIOTH_ROUTE.any(func(row):return int(row[1])==current),"Resume an actual checkpoint on the Alioth route")
	if failures:return false
	if current==91:
		if not await depart_alioth_route() or not await travel_application(90) or not await settle_alioth_route(90):return false
		current=90
	var route_index:=-1
	for index in ALIOTH_ROUTE.size():
		if int(ALIOTH_ROUTE[index][1])==current:route_index=index;break
	for index in range(route_index+1,ALIOTH_ROUTE.size()):
		if not await depart_alioth_route():return false
		var destination: Array=ALIOTH_ROUTE[index]
		if not await expedition_gate(int(destination[0]),int(destination[1])) or not await settle_alioth_route(int(destination[1])):return false
	if not await depart_alioth_route() or not await travel_application(98):return false
	var arrival: Dictionary=app.session.snapshot()
	check(arrival.campaign_cursor==31 and arrival.location.station_id==98 and arrival.encounter.combat.actors.is_empty() and not arrival.dialogue.visible,"Alioth31 opened a flight result or spawned an authored cast")
	check(arrival.contracts.credits==route_credits and arrival.contracts.mission==retained_job and arrival.contracts.passengers==3,"Alioth flight paid the pending reward or changed passengers")
	if failures:return false
	return await dock_application()

func settle_alioth_route(station_id: int) -> bool:
	var frame: Dictionary=app.session.snapshot()
	var armed: bool=frame.encounter.has("secondaries") and frame.encounter.secondaries.guns[0].ammunition>0
	if not armed and frame.encounter.combat.actors.any(func(actor):return actor.active and actor.hostile and actor.vitals.hull>0):
		print("Earned Alioth route continues through hostile gate station ",station_id," with ",frame.player.vitals)
		return true
	if not await dock_with_paid_emp(2147483647):return false
	return retain_chapter_save("alioth31-route-"+str(station_id))

func depart_alioth_route() -> bool:
	# Buy only source-offered ammunition affordable with the retained wallet.
	# This shared pilot uses no synthetic inventory, damage or travel shortcuts.
	if app.session is FlightSession and app.session.status=="running":return true
	var station: RefCounted=app.session.station_owner()
	var ready: Dictionary=station.snapshot()
	var item_id:=43
	if ready.loadout.slots[1]!=null:item_id=int(ready.loadout.slots[1].item_id)
	else:
		var stock: Array=station.contract_owner().location_owner().item_stock(int(ready.loadout.station_id))
		for candidate in [43,42,41]:
			if stock.any(func(row):return int(row.item_id)==candidate and int(row.quantity)>0 and int(row.unit_price)>0 and int(row.unit_price)<=ready.contracts.credits):
				item_id=candidate;break
	if not purchase_route_emp(14,false,item_id):return false
	if not retain_chapter_save("alioth31-prepared-"+str(ready.loadout.station_id)):return false
	if not app.request_departure() or not app.enter_first_flight(now_us,4096,flight_world_seconds()):check(false,app.status.text);return false
	return await release_application_flight()

func verify_alioth_continuation(paid: Dictionary) -> void:
	check(paid.campaign_cursor==32 and paid.loadout.station_id==98 and paid.mission=={"kind":11,"station_id":10,"reward":0,"bonus":0,"source_parameter":0},"The saved payment lost its original pending Thynome mission")
	if failures:return
	if not app.save_station():check(false,app._save_notice.text);return
	var file:=NativeSave.new()
	var record: Dictionary=file.load_document(app.station_save_path(),definitions,catalogue,source)
	check(record.get("version")==(8 if paid.contracts.has("void_source") else 7) and record.station.reward_credits==30000,"The Alioth payment did not produce its supported station archive")
	if not app.load_station(now_us):check(false,app._save_notice.text);return
	check(app.session.station_owner().snapshot()==paid,"Alioth save/load changed the actual paid career")
	await capture_free_application("earned-alioth32-station")
	if failures or not app.request_departure() or not app.enter_first_flight(now_us,4096,flight_world_seconds()):check(false,app.status.text);return
	if not await release_application_flight():return
	var departed: Dictionary=app.session.snapshot()
	check(departed.campaign_cursor==32 and departed.location.station_id==98 and departed.mission==paid.mission and not departed.encounter.combat.actors.is_empty(),"Alioth departure replayed the completed empty story scene")
	check(departed.contracts.credits==paid.contracts.credits and departed.contracts.mission==retained_job and departed.contracts.passengers==3 and departed.cargo==paid.cargo and departed.progress==paid.progress,"Alioth departure lost payment, cargo or earned progress")
	check(not departed.dialogue.visible and not departed.has("void_probe") and not departed.has("void_portal"),"Alioth ordinary departure selected unsupported authored flight content")
	if not app.open_map(now_us):check(false,app.status.text);return
	var navigation: Dictionary=app.map_panel.snapshot()
	check(navigation.system_id==19 and navigation.rows.any(func(row):return row.supported),"Alioth departure lost ordinary local navigation")
	# Thynome is beyond this flight's local/neighbor map. Check the story guard
	# directly and ensure an invalid live request cannot change the earned world.
	var mapped: Dictionary=app.session.snapshot()
	check(not PostProbeNavigation.destination_supported(definitions,32,paid.mission,10) and not app.session.confirm_map_planet(10,now_us) and app.session.snapshot()==mapped,"The next unimplemented Thynome result bypassed its mission guard")
	if not app.close_map(now_us):check(false,app.status.text);return
	await capture_free_application("earned-alioth32-ordinary-departure")
