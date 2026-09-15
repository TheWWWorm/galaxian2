extends "res://tests/free_application.gd"
## Actual post-unlock lounge acceptance, flight, docking and acknowledged payment.
## Every chosen offer belongs to a normally generated, retained station lounge.

func verify_free_application() -> void:
	var original: Dictionary=app.session.station_owner().snapshot()
	app.show();app.present_session();await process_frame;resume_application_focus()
	var requested_kind:=11 if OS.get_environment("GOF2_ORDINARY_PASSENGER_TEST")=="1" else 0
	if requested_kind==11 and not await acquire_passenger_cabin():return
	check(app._lounge_button.visible and app._launch_button.visible,"The unlocked station omitted its lounge")
	var chosen:=-1
	for destination in [-1,96,97,99,95,98]:
		if destination==int(app.session.station_owner().snapshot().loadout.station_id):continue
		if destination>=0 and not await visit_delivery_station(destination):return
		var key:=InputEventKey.new();key.physical_keycode=KEY_L;key.pressed=true
		app._unhandled_input(key)
		check(app.session.snapshot().get("lounge_open",false) and app.lounge_panel.visible,"L did not open the unlocked lounge")
		var station: RefCounted=app.session.station_owner()
		var career: Dictionary=station.snapshot().contracts
		for id in career.offers:
			var row: Dictionary=career.offers[id]
			if row.consumed:continue
			var preview: Dictionary=station.contract_preview(id,definitions)
			print("Ordinary application offer: ",{"origin":career.station_id,"id":id,"kind":row.offer.mission.kind,"destination":row.offer.mission.station_id,"quantity":row.offer.mission.quantity,"can_accept":preview.get("can_accept",false)})
			if row.offer.mission.kind==requested_kind and int(row.offer.mission.station_id) in [95,96,97,98,99] and preview.get("can_accept",false):chosen=id;break
		if chosen>=0:break
		if not app.contract_action("close",-1):check(false,app.session.error);return
	if chosen<0:check(false,"Actual local journeys produced no supported affordable delivery");return
	var before: Dictionary=app.session.station_owner().snapshot()
	var offer: Dictionary=before.contracts.offers[chosen].offer
	var quote: Dictionary=app.session.station_owner().contract_preview(chosen,definitions)
	app.lounge_panel.select_contact(chosen)
	await capture_free_application("ordinary-contract-offer-desktop")
	app.lounge_panel.confirm()
	check(app.session.station_owner().snapshot()==before and app.lounge_panel._confirming,"Selecting an offer skipped acknowledgement")
	await capture_free_application("ordinary-contract-confirm-desktop")
	app.lounge_panel.back()
	check(app.session.station_owner().snapshot()==before and not app.lounge_panel._confirming,"Cancelled acceptance changed the career")
	app.lounge_panel.confirm();app.lounge_panel.confirm()
	var accepted: Dictionary=app.session.station_owner().snapshot()
	check(accepted.contracts.mission==offer.mission and accepted.contracts.accepted_contact.offer==offer,"The lounge changed its actual generated contract")
	check(accepted.mission==original.mission and accepted.contracts.completed_side_missions==original.contracts.completed_side_missions,"Acceptance changed pending story or granted completion")
	check(accepted.contracts.credits==before.contracts.credits-int(quote.fee) and accepted.cargo.used==before.cargo.used+int(quote.cargo_tons),"Acceptance lost its source cargo or fee")
	check(accepted.contracts.passengers==(int(offer.mission.quantity) if requested_kind==11 else 0),"Acceptance lost its retained passenger count")
	check(not app.contract_action("accept",chosen) and app.session.station_owner().snapshot()==accepted,"A consumed contact accepted twice")
	if not app.contract_action("close",-1):check(false,app.session.error);return
	await verify_delivery_route(original,before,offer,accepted,requested_kind)

func verify_delivery_route(original: Dictionary,before: Dictionary,offer: Dictionary,accepted: Dictionary,requested_kind: int) -> void:
	if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
	var context: Dictionary=app.session.snapshot().encounter.combat.free_context
	check(context.side_mission==offer.mission and context.mission_kind==-1,"Off-target courier lost its side slot or selected its destination early")
	if not await release_application_flight():return
	if not app.open_map():check(false,app.status.text);return
	check(app.map_panel.snapshot().rows.filter(func(row):return row.mission_target).map(func(row):return row.station_id)==[int(offer.mission.station_id)],"The map did not identify the courier destination")
	await capture_free_application("ordinary-contract-map-desktop")
	if not app.close_map(now_us):check(false,app.status.text);return
	if not await travel_application(int(offer.mission.station_id)):return
	var arrived: Dictionary=app.session.snapshot()
	check(arrived.contracts.mission==offer.mission and arrived.contracts.credits==accepted.contracts.credits,"Arriving in space paid or discarded the delivery")
	var selected: Dictionary=arrived.encounter.combat.free_context
	check(selected.mission_kind==(0 if requested_kind==0 else -1),"The destination selected the wrong delivery mission")
	if requested_kind==0:check(arrived.encounter.combat.actors==[],"Destination courier constructed ordinary or delivery pirates")
	else:check(not arrived.encounter.combat.actors.is_empty() and arrived.contracts.passengers==accepted.contracts.passengers,"Passenger destination lost ordinary traffic or disembarked in space")
	await capture_free_application("ordinary-contract-destination-flight")
	if not await dock_application():return
	if not application_step():return
	app.present_session();await process_frame
	var pending: Dictionary=app.session.station_owner().snapshot()
	var result: Dictionary=pending.contracts.pending_result
	check(not result.is_empty() and result.kind==requested_kind and result.acknowledgement_required,"Docking did not open the source delivery result")
	if result.is_empty():return
	check(pending.contracts.credits==accepted.contracts.credits and pending.contracts.completed_side_missions==accepted.contracts.completed_side_missions and pending.cargo==accepted.cargo,"Opening the result paid or removed cargo before acknowledgement")
	check(not app._hangar_button.visible and not app._launch_button.visible,"The delivery acknowledgement retained conflicting station actions")
	await capture_free_application("ordinary-contract-result-desktop")
	root.size=Vector2i(960,540);app.set_mobile_layout(true);app.set_touch_controls(true)
	await process_frame;resume_application_focus();app.present_session()
	check(app.lounge_panel._mobile and app.lounge_panel._yes.size.y>=44,"The landscape result lost its larger touch control")
	await capture_free_application("ordinary-contract-result-mobile-landscape")
	var serial: int=result.serial
	app.lounge_panel.confirm()
	var paid: Dictionary=app.session.station_owner().snapshot()
	check(paid.contracts.pending_result.is_empty() and paid.contracts.mission.is_empty(),"Acknowledgement did not retire the delivery")
	check(paid.contracts.passengers==0,"Acknowledgement retained delivered passengers")
	check(paid.contracts.credits==accepted.contracts.credits+int(offer.mission.reward)+int(offer.mission.bonus),"Acknowledgement paid another amount")
	check(paid.contracts.completed_side_missions==original.contracts.completed_side_missions+1 and paid.cargo==before.cargo,"Delivery completion lost its count or retained ordinary cargo")
	check(paid.mission==original.mission and paid.campaign_cursor==18,"Delivery completed the pending Suttnar story")
	check(not app.contract_action("result_close",serial) and app.session.station_owner().snapshot()==paid,"A repeated result paid twice")
	print("Ordinary delivery earned: ",{"origin":before.loadout.station_id,"destination":paid.loadout.station_id,"quantity":offer.mission.quantity,"reward":int(offer.mission.reward)+int(offer.mission.bonus),"credits":paid.contracts.credits,"completed_jobs":paid.contracts.completed_side_missions})
	await capture_free_application("ordinary-contract-paid-mobile-landscape")

func acquire_passenger_cabin() -> bool:
	# Visit the source-stocked cabin supplier first so the three-location cache
	# can retain Alioth's original passenger offer through the shopping trip.
	for destination in [-1,99,96,97,95]:
		if destination==int(app.session.station_owner().snapshot().loadout.station_id):continue
		if destination>=0 and not await visit_delivery_station(destination):return false
		if await fit_passenger_cabin():
			return true if int(app.session.station_owner().snapshot().loadout.station_id)==98 else await visit_delivery_station(98)
		if failures:return false
	check(false,"Actual local station stock supplied no affordable supported cabin")
	return false

func fit_passenger_cabin() -> bool:
	if not app.equipment_action("open"):check(false,app.session.error);return false
	var shop: Dictionary=app.session.station_owner().snapshot()
	var cabin:={}
	for row in shop.equipment.market_rows:
		var properties: Dictionary=catalogue.tables.items[row.item_id].properties
		if int(properties.get(2,-1))==20 and int(properties.get(34,0))>=3 and row.stock>0 and row.unit_price<=shop.contracts.credits and shop.equipment.fitting_support[row.item_id].is_empty():
			if cabin.is_empty() or row.unit_price<cabin.price:cabin={"item_id":row.item_id,"price":row.unit_price}
	if cabin.is_empty():
		print("No affordable supported cabin at station ",shop.loadout.station_id)
		check(app.equipment_action("close"),app.session.error)
		return false
	# Vacate the starter's actual scanner slot. The scanner stays owned in cargo.
	var slot:=-1
	for index in shop.loadout.slots.size():
		if shop.loadout.slots[index]!=null and shop.loadout.slots[index].item_id==81:slot=index;break
	if slot<0:check(false,"The earned ship lost its original scanner slot");return false
	if not app.equipment_action("unmount",81,slot) or not app.equipment_action("buy",int(cabin.item_id)) or not app.equipment_action("mount",int(cabin.item_id)):check(false,app.session.error);return false
	var fitted: Dictionary=app.session.station_owner().snapshot()
	check(fitted.contracts.credits==shop.contracts.credits-int(cabin.price) and fitted.equipment.fitting_stats.passenger_capacity>=3,"Paid fitting lost its cabin places or price")
	print("Passenger cabin purchased: ",cabin)
	await capture_free_application("ordinary-contract-passenger-cabin")
	if not app.equipment_action("close"):check(false,app.session.error);return false
	return failures==0

func visit_delivery_station(destination: int) -> bool:
	if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return false
	if not await release_application_flight() or not await travel_application(destination) or not await dock_application():return false
	return true
