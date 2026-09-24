extends "res://tests/tractor_purchase_application.gd"
## Continue the actual paid and fitted career through its authored Sahi flight.
const StoryPilot=preload("res://tests/fixtures/story_flight_pilot.gd")
const NativeSave=preload("res://src/simulation/station_save_file.gd")
var route_credits:=0

func verify_free_application() -> void:
	var original: Dictionary=app.session.station_owner().snapshot()
	var route_resume:=OS.get_environment("GOF2_SAHI_ROUTE_RESUME")=="1"
	var weymire_resume:=OS.get_environment("GOF2_SAHI_ROUTE_WEYMIRE_RESUME")=="1"
	var direct_gate:=OS.get_environment("GOF2_SAHI_ROUTE_DIRECT_GATE")=="1"
	check(not (route_resume and weymire_resume) and (not direct_gate or route_resume),"Choose one actual route checkpoint; direct gate needs the repaired Aquila station")
	check(original.campaign_cursor==24 and original.loadout.station_id==(45 if weymire_resume else 35 if route_resume else 37) and original.loadout.equipment_ids.has(68) and original.loadout.equipment_ids.has(2) and original.mission.station_id==48,"Resume the earned paid tractor and pending Sahi route")
	if failures:return
	chapter_directory=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	if chapter_directory.is_empty() or not FreePlayCheckpoint.private_path(chapter_directory+"/save.bin"):check(false,"Set a private story save directory");return
	app.enable_saves(chapter_directory);app.show();app.present_session();await process_frame;resume_application_focus()
	retained_job=original.contracts.mission.duplicate(true)
	route_credits=int(original.contracts.credits)
	if weymire_resume:
		if not verify_weymire_resume(original) or not retain_chapter_save("sahi-route-station45-ready"):return
		if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
		if not await release_application_flight():return
	else:
		if route_resume:
			check((original.loadout.equipment_ids.has(55) or original.loadout.equipment_ids.has(81)) and not original.loadout.equipment_ids.has(86),"The retained Aquila stop lost its actual owned-device fitting")
			if failures or not prepare_route_emp() or not retain_chapter_save("sahi-route-station35-ready"):return
		else:
			if not prepare_sahi_route_armor(original):return
		if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
		if not await release_application_flight():return
		if not route_resume:
			if not await travel_application(35):return
		if not direct_gate:
			if not await clear_route_attackers("Aquila35"):return
			if not await refresh_route_at_station(35,original):return
			if OS.get_environment("GOF2_SAHI_ROUTE_AQUILA_ONLY")=="1":
				print("Earned Aquila35 station, source equipment and paid EMP43 checkpoint")
				return
		if not await follow_gate_course(11,55) or not await release_application_flight():return
		if not await suppress_kappa_for_gate() or not await approach_kappa_gate():return
		if not await follow_gate_course(9,45) or not await release_application_flight():return
		if OS.get_environment("GOF2_SAHI_ROUTE_ONLY")!="1":
			if not await refresh_route_at_station(45,original):return
	if not await acquire_application_planet(48):return
	if not app.enter_local_arrival(now_us,4096,1789100000):check(false,app.status.text);return
	var arrival: Dictionary=app.session.snapshot()
	check(arrival.campaign_cursor==24 and arrival.location.station_id==48 and arrival.actors.size()==5 and arrival.has("sahi_stage"),"The earned route did not select Sahi's authored world")
	check(arrival.contracts.credits==route_credits and arrival.contracts.mission==retained_job and arrival.contracts.passengers==3,"Sahi arrival changed the paid wallet or occupied passenger cabin")
	check(arrival.contracts.travel_statistics.jumpgates_used==original.contracts.travel_statistics.jumpgates_used+(0 if weymire_resume else 2),"Sahi route skipped or added a gate")
	if failures:return
	if OS.get_environment("GOF2_SAHI_ROUTE_ONLY")=="1":
		print("Earned fitted Carme37→Aquila35→Kappa55→Weymire45→Sahi48 arrival; alive hull ",arrival.player.vitals.hull," and two actual gates")
		return
	if failures or not await acknowledge_story_lines(definitions.mido_travel.sahi_visit.briefing.events):return
	await capture_story(null,null,"earned-sahi-arrival")
	var survived: RefCounted=await StoryPilot.recover_void_cargo(app.session.flight_owner(),app.session.scene,Callable(self,"advance_story"),Callable(self,"capture_story"),Callable(self,"check"),process_frame)
	if survived==null:return
	var recovered: Dictionary=app.session.snapshot()
	check(recovered.encounter.combat.recovery.kind9_quantity>=3 and recovered.cargo.used>=arrival.cargo.used+3,"Sahi did not recover its three actual Void cargo units")
	check(recovered.progress.cargo_recovered==int(arrival.progress.get("cargo_recovered",0))+recovered.encounter.combat.recovery.accepted_quantity,"Sahi recovery was omitted or counted twice in the earned career")
	if failures:return
	var contact: RefCounted=await StoryPilot.enter_sahi_portal(survived,app.session.scene,Callable(self,"advance_story"),Callable(self,"capture_story"),Callable(self,"check"),process_frame)
	if contact==null or not adopt_portal(25):return
	if not await acknowledge_story_lines(definitions.mido_travel.post_sahi.missions["25"].result_events):return
	check(app.session.snapshot().campaign_cursor==26 and app.session.can_control(),"Void result did not advance the career while retaining the living Void world")
	if failures or not await fly_void_portal() or not adopt_portal(26):return
	if not await acknowledge_story_lines(definitions.mido_travel.post_sahi.missions["26"].briefing_events):return
	var pursuit: Dictionary=app.session.snapshot()
	if not select_paid_emp():return
	print("Earned pursuit begins with hull ",pursuit.player.vitals.hull," and EMP43 rounds ",pursuit.encounter.secondaries.guns[0].ammunition)
	survived=await StoryPilot.recover_void_cargo(app.session.flight_owner(),app.session.scene,Callable(self,"advance_story"),Callable(self,"capture_story"),Callable(self,"check"),process_frame,false)
	if survived==null or not await acknowledge_story_lines(definitions.mido_travel.post_sahi.missions["26"].result_events):return
	var completed: Dictionary=app.session.snapshot()
	check(completed.campaign_cursor==27 and completed.mining_objective.mission_completed and completed.progress.player_kills==pursuit.progress.player_kills+2,"Actual pursuit combat lost its earned completion")
	check(completed.cargo==pursuit.cargo and completed.contracts.credits==route_credits,"Pursuit completion granted cargo or payment")
	check(completed.encounter.secondaries.guns[0].ammunition<pursuit.encounter.secondaries.guns[0].ammunition,"The earned pursuit did not use its purchased EMP ammunition")
	print("Earned pursuit completed with hull ",completed.player.vitals.hull," and EMP43 rounds ",completed.encounter.secondaries.guns[0].ammunition)
	if failures or not await dock_application():return
	var landed: Dictionary=app.session.station_owner().snapshot()
	check(landed.campaign_cursor==27 and landed.loadout.station_id==48 and landed.mission.kind==11 and landed.mission.station_id==10,"Completed Sahi return did not retain the original Thynome visit")
	check(landed.contracts.mission==retained_job and landed.contracts.passengers==3 and landed.contracts.credits==route_credits and landed.cargo==completed.cargo,"Sahi docking lost the occupied cabin, wallet or recovered cargo")
	check(landed.player_cache.values.hull==completed.player.vitals.hull,"Station entry repaired the actual pursuit damage")
	check(landed.progress.cargo_recovered==recovered.progress.cargo_recovered,"Void, pursuit or docking changed the actual recovered-cargo statistic")
	if failures:return
	await capture_free_application("earned-sahi-station")
	if not retain_chapter_save("sahi27-return"):return
	await verify_sahi_return_departure(landed)
	if failures:return
	print("Earned Carme fitting -> Sahi24 recovery -> Void25 escape -> pursuit26 combat -> Sahi27 station, save/load and ordinary departure")

func verify_sahi_return_departure(landed: Dictionary) -> void:
	if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
	if not await release_application_flight():return
	var departed: Dictionary=app.session.snapshot()
	check(departed.campaign_cursor==27 and departed.location.station_id==48 and not departed.has("sahi_stage") and not departed.has("void_portal"),"The saved return replayed a completed story encounter")
	check(departed.cargo==landed.cargo and departed.progress==landed.progress and departed.contracts.mission==retained_job and departed.contracts.passengers==3 and departed.contracts.credits==route_credits,"Ordinary departure lost the saved recovery, wallet or occupied cabin")
	if not app.open_map():check(false,app.status.text);return
	var destinations: Array=app.map_panel.snapshot().rows.filter(func(row):return row.station_id==45)
	check(destinations.size()==1 and destinations[0].supported,"The saved Sahi return cannot select ordinary Weymire travel")
	if not app.close_map(now_us):check(false,app.status.text);return
	await capture_free_application("earned-sahi-ordinary-departure")

func verify_weymire_resume(original: Dictionary) -> bool:
	var reference_path:=OS.get_environment("GOF2_SAHI_ROUTE_AQUILA_REFERENCE")
	check(reference_path.is_absolute_path() and FileAccess.file_exists(reference_path),"Weymire continuation needs its original earned Aquila reference save")
	if failures:return false
	var file:=NativeSave.new()
	var reference: Dictionary=file.load_document(reference_path,definitions,catalogue,source)
	check(not reference.is_empty() and not file.recovered_backup,"The original Aquila reference did not load directly: "+file.error)
	if failures:return false
	check(reference.version==4 and reference.station.campaign_cursor==24 and reference.inventory.loadout.station_id==35 and reference.station.mission==original.mission,"The reference is not the pending Sahi Aquila station")
	check(original.loadout.station_id==45 and original.campaign_cursor==24 and original.loadout.equipment_ids.has(81) and original.loadout.equipment_ids.has(68) and original.loadout.equipment_ids.has(91) and original.loadout.equipment_ids.has(43) and not original.loadout.equipment_ids.has(55) and not original.loadout.equipment_ids.has(86),"Weymire lost the actual scanner, tractor, cabin or paid launcher fitting")
	check(original.contracts.travel_statistics.jumpgates_used==reference.career.travel_statistics.jumpgates_used+2 and original.contracts.credits==reference.career.credits and original.contracts.mission==reference.career.mission and original.contracts.passengers==reference.career.passengers and original.contracts.passengers==3,"Weymire did not retain exactly two genuine gates and the paid career")
	check(original.player_cache.values.hull>0 and original.loadout.slots[1]!=null and original.loadout.slots[1].item_id==43 and original.loadout.slots[1].quantity>0 and original.loadout.slots[1].quantity<reference.inventory.loadout.slots[1].quantity,"Weymire did not retain a living pilot and the spent paid EMP ammunition")
	print("Earned Weymire45 station: hull ",original.player_cache.values.hull," EMP43 rounds ",original.loadout.slots[1].quantity," credits ",original.contracts.credits," gate history ",original.contracts.travel_statistics)
	print("Earned Weymire45 supported secondary stock: ",app.session.station_owner().contract_owner().location_owner().item_stock(45).filter(func(row):return int(row.item_id) in [41,42,43]))
	return failures==0

func prepare_sahi_route_armor(original: Dictionary) -> bool:
	print("Earned Carme secondary stock: ",app.session.station_owner().contract_owner().location_owner().item_stock(37).filter(func(row):return int(row.item_id) in [41,43]))
	check(original.loadout.equipment_ids.has(86) and original.cargo.entries.any(func(row):return row.item_id==55 and row.quantity==1),"The earned fitting lost its installed mining drill or owned armor")
	if failures or not app.equipment_action("open"):check(false,app.status.text);return false
	if not mount_owned_device(55,19):return false
	var armored: Dictionary=app.session.station_owner().snapshot()
	check(armored.equipment.fitting_stats.armor==int(catalogue.tables.items[55].properties[20]),"The real armor fitting did not restore its source capacity")
	if failures or not app.equipment_action("close"):check(false,app.status.text);return false
	var ready: Dictionary=app.session.station_owner().snapshot()
	check(ready.loadout.equipment_ids.has(55) and ready.loadout.equipment_ids.has(68) and ready.loadout.equipment_ids.has(91) and not ready.loadout.equipment_ids.has(86),"The defensive refit lost the paid tractor or occupied passenger cabin")
	check(ready.contracts.credits==original.contracts.credits and ready.contracts.mission==original.contracts.mission and ready.contracts.passengers==3 and ready.mission==original.mission and ready.cargo.used==original.cargo.used,"The owned armor exchange changed the wallet, career, passengers or cargo quantity")
	return failures==0

func refresh_route_at_station(station_id: int,original: Dictionary) -> bool:
	if station_id==45:
		if not await dock_weymire_with_emp():return false
	elif not await dock_application():return false
	var landed: Dictionary=app.session.station_owner().snapshot()
	check(landed.loadout.station_id==station_id and landed.campaign_cursor==24 and landed.contracts.credits==route_credits and landed.contracts.mission==retained_job and landed.contracts.passengers==3,"Intermediate docking changed the earned Sahi route or paid career")
	if station_id==35 and not failures and not prepare_route_emp():return false
	if station_id==45 and not failures and not prepare_route_scanner():return false
	var ready: Dictionary=app.session.station_owner().snapshot()
	if failures or not retain_chapter_save("sahi-route-station"+str(station_id)):return false
	if station_id==35 and OS.get_environment("GOF2_SAHI_ROUTE_AQUILA_ONLY")=="1":return failures==0
	if failures or not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return false
	if not await release_application_flight():return false
	var departed: Dictionary=app.session.snapshot()
	var expected_armor: int=int(catalogue.tables.items[55].properties[20]) if ready.loadout.equipment_ids.has(55) else 0
	check(departed.location.station_id==station_id and departed.player.vitals.hull>=ready.player_cache.values.hull and departed.player.vitals.armor==expected_armor,"The ordinary station departure did not retain its real fitted capacities")
	return failures==0

func dock_weymire_with_emp() -> bool:
	var arrival: Dictionary=app.session.snapshot()
	check(arrival.location.station_id==45 and arrival.campaign_cursor==24 and arrival.encounter.has("secondaries") and arrival.encounter.secondaries.guns[0].ammunition>0,"Weymire docking requires the real gate arrival and remaining paid EMP")
	if failures:return false
	return await dock_with_paid_emp()

func dock_with_paid_emp(refresh_ms:=7000) -> bool:
	var arrival: Dictionary=app.session.snapshot()
	if not arrival.encounter.has("secondaries") or arrival.encounter.secondaries.guns[0].ammunition<=0:return await dock_application()
	var label:="station "+str(arrival.location.station_id)+" dock"
	if not select_paid_emp():return false
	if not app.session.action("autopilot"):check(false,app.session.error);return false
	app.session.rebase_time(now_us)
	for tick in 2000:
		if app.session.status=="station_transition_required":break
		var frame: Dictionary=app.session.snapshot()
		var emp_request: Dictionary={}
		if app.session.can_control() and not try_paid_emp(frame,refresh_ms,5000.0,label+" tick "+str(tick),true,emp_request):return false
		now_us+=100000
		if not app.session.step(now_us):check(false,app.session.error);return false
		var state: Dictionary=app.session.snapshot()
		if not verify_emp_request(emp_request,frame,state,label+" tick "+str(tick)):return false
		if app.session.flight_owner().death_active():check(false,"The paid docking pilot was destroyed by live traffic at "+str(arrival.location.station_id));return false
		if tick%50==0:
			print("Earned ",label," ",tick," station distance ",int(state.player_pose.origin.distance_to(state.station_autopilot.target_position))," throttle ",state.station_autopilot.throttle," player ",state.player.vitals," EMP ",state.encounter.secondaries.guns[0].ammunition," threats ",state.encounter.combat.actors.filter(func(actor):return actor.active and actor.hostile and actor.vitals.hull>0).map(func(actor):return {"id":actor.actor_id,"distance":int(actor.position.distance_to(state.player_pose.origin)),"disabled":actor.systems_disabled}))
		if tick%20==0:await process_frame
	check(app.session.status=="station_transition_required","Paid EMP docking did not reach the native station transition at "+str(arrival.location.station_id))
	if failures or not app.enter_station(now_us,42):check(false,app.status.text);return false
	app.session.rebase_time(now_us)
	return true

func prepare_route_scanner() -> bool:
	if OS.get_environment("GOF2_SAHI_ROUTE_ONLY")=="1" or OS.get_environment("GOF2_SAHI_ROUTE_AQUILA_ONLY")=="1":return true
	var before: Dictionary=app.session.station_owner().snapshot()
	if before.loadout.equipment_ids.has(81):return true
	if not app.equipment_action("open"):check(false,app.status.text);return false
	if not mount_owned_device(81,10):return false
	if not app.equipment_action("close"):check(false,app.status.text);return false
	var ready: Dictionary=app.session.station_owner().snapshot()
	check(ready.loadout.equipment_ids.has(81) and ready.loadout.equipment_ids.has(68) and ready.loadout.equipment_ids.has(91) and ready.cargo.used==before.cargo.used,"Installing the owned shipwreck scanner changed the cabin or cargo quantity")
	for field in ["credits","mission","passengers","progress","completed_side_missions","travel_statistics"]:
		check(ready.contracts[field]==before.contracts[field],"Installing the owned scanner changed retained "+field)
	return failures==0

func prepare_route_emp() -> bool:
	var before: Dictionary=app.session.station_owner().snapshot()
	check(before.loadout.station_id==35 and before.campaign_cursor==24 and before.loadout.equipment_ids.has(68) and before.loadout.equipment_ids.has(91),"The EMP supplier lost the earned Aquila stop, tractor or passenger cabin")
	if failures:return false
	if before.loadout.equipment_ids.has(43):
		check(before.loadout.slots.any(func(slot):return slot!=null and slot.item_id==43 and slot.quantity>0),"The retained EMP launcher has no purchased ammunition")
		return failures==0
	return purchase_route_emp(10)

func purchase_route_emp(maximum_rounds: int,require_full:=true,item_id:=43) -> bool:
	if not app.equipment_action("open"):check(false,app.status.text);return false
	var quote: Dictionary=app.session.station_owner().snapshot()
	var panel: Control=app.equipment_panel
	var cargo_rounds:=0
	for row in quote.cargo.entries:
		if row.item_id==item_id:cargo_rounds+=int(row.quantity)
	var installed_rounds: int=int(quote.loadout.slots[1].quantity) if quote.loadout.slots[1]!=null and quote.loadout.slots[1].item_id==item_id else 0
	panel.select_tab("shop")
	var offers: Array=app.session.station_owner().contract_owner().location_owner().item_stock(int(quote.loadout.station_id)).filter(func(row):return int(row.item_id)==item_id)
	var quantity:=0
	if offers.size()==1 and int(offers[0].unit_price)>0:
		quantity=mini(maximum_rounds,mini(maxi(0,int(quote.cargo.free_space)-installed_rounds),mini(int(offers[0].quantity),int(float(quote.contracts.credits)/float(offers[0].unit_price)))))
	if not require_full and quantity==0:
		print("Earned route EMP supplier has no affordable rounds at station ",quote.loadout.station_id)
		if not app.equipment_action("close"):check(false,app.status.text);return false
		return true
	check(quantity>0 and (not require_full or quantity==maximum_rounds),"The actual wallet or stock cannot buy the requested supported EMP rounds")
	check(panel._rows.has(item_id) and quote.equipment.fitting_support[item_id].is_empty() and not panel._rows[item_id].actions.buy.disabled,"The original EMP row is unavailable to the earned ship")
	if failures:return false
	var unit_price: int=int(offers[0].unit_price)
	for round_index in quantity:panel._rows[item_id].actions.buy.pressed.emit()
	var bought: Dictionary=app.session.station_owner().snapshot()
	check(bought.contracts.credits==quote.contracts.credits-quantity*unit_price and bought.cargo.used==quote.cargo.used+quantity and bought.loadout==quote.loadout,"Paid EMP purchases did not debit the actual quote or stay in cargo")
	if failures:return false
	if installed_rounds>0:
		panel.select_tab("ship");panel._installed_rows[1].button.pressed.emit()
		var unmounted: Dictionary=app.session.station_owner().snapshot()
		check(unmounted.loadout.slots[1]==null and unmounted.cargo.used==bought.cargo.used+installed_rounds and unmounted.contracts.credits==bought.contracts.credits,"Demounting the paid launcher changed its remaining rounds or wallet")
		if failures:return false
	panel.select_tab("cargo")
	check(panel._rows.has(item_id) and not panel._rows[item_id].actions.mount.disabled,"Paid EMP cargo cannot enter the available secondary slot")
	if failures:return false
	panel._rows[item_id].actions.mount.pressed.emit()
	var mounted: Dictionary=app.session.station_owner().snapshot()
	var retained_cargo: Dictionary=quote.cargo.duplicate(true)
	retained_cargo.entries=retained_cargo.entries.filter(func(row):return row.item_id!=item_id);retained_cargo.used-=cargo_rounds
	retained_cargo.free_space+=cargo_rounds
	check(mounted.loadout.slots[1]!=null and mounted.loadout.slots[1].item_id==item_id and mounted.loadout.slots[1].quantity==quantity+cargo_rounds+installed_rounds and mounted.cargo==retained_cargo,"The actual Mount action did not fit exactly the retained and newly paid EMP rounds")
	check(quote.loadout.equipment_ids.all(func(id):return mounted.loadout.equipment_ids.has(id)) and mounted.contracts.mission==retained_job and mounted.contracts.passengers==3 and mounted.mission==quote.mission and mounted.progress==quote.progress,"EMP fitting changed retained equipment, passengers, story or earned progress")
	if failures or not app.equipment_action("close"):check(false,app.status.text);return false
	route_credits=int(mounted.contracts.credits)
	print("Earned station ",quote.loadout.station_id," EMP",item_id,": ",quantity," actual rounds at ",unit_price," credits, retained wallet ",route_credits)
	return failures==0

func release_application_flight() -> bool:
	app.session.rebase_time(now_us)
	for tick in 71:
		if app.session.can_control() and app.session.flight_audio!=null:
			print("Earned route controls released after ",tick," real flight ticks at station ",app.session.snapshot().location.station_id)
			return true
		if not application_step():return false
	check(app.session.can_control() and app.session.flight_audio!=null,"The earned route never released flight controls or audio")
	return failures==0

func clear_route_attackers(label: String) -> bool:
	var state: Dictionary=app.session.snapshot()
	var actors: Array=state.encounter.combat.actors
	var attackers: Array=actors.filter(func(actor):return actor.hostile and actor.vitals.hull>0)
	print("Earned route ",label," living traffic: ",actors.filter(func(actor):return actor.active and actor.vitals.hull>0).map(func(actor):return {"id":actor.actor_id,"kind":actor.actor_kind,"hostile":actor.hostile,"position":actor.position}))
	print("Earned route ",label," vitals ",state.player.vitals," departure threats: ",attackers.map(func(actor):return {"id":actor.actor_id,"hull":actor.vitals.hull,"position":actor.position}))
	for round_index in attackers.size():
		var current: Dictionary=app.session.snapshot()
		var living: Array=current.encounter.combat.actors.filter(func(actor):return actor.active and actor.hostile and actor.vitals.hull>0)
		if living.is_empty():break
		var use_emp: bool=current.encounter.has("secondaries") and current.encounter.secondaries.guns[0].ammunition>0
		if use_emp:
			var neutrals: Array=current.encounter.combat.actors.filter(func(actor):return actor.active and not actor.hostile and actor.vitals.hull>0)
			living.sort_custom(func(a,b):return nearest_neutral_distance_squared(a,neutrals)>nearest_neutral_distance_squared(b,neutrals))
		else:
			living.sort_custom(func(a,b):return a.position.distance_squared_to(current.player_pose.origin)<b.position.distance_squared_to(current.player_pose.origin))
		var target: Dictionary=living[0]
		if use_emp and not select_paid_emp():return false
		print("Earned route attacker ",target.actor_id," armed ",use_emp," current range ",int(target.position.distance_to(current.player_pose.origin)))
		if not await clear_route_attacker(int(target.actor_id),use_emp):return false
		var result: Dictionary=app.session.snapshot()
		print("Earned route attacker ",target.actor_id," defeated: ",{"player":result.player.vitals,"living_hostile":result.encounter.combat.actors.filter(func(other):return other.hostile and other.vitals.hull>0).map(func(other):return other.actor_id),"provocation":result.encounter.combat.get("provocation",{}),"ammunition":result.encounter.secondaries.guns[0].ammunition if result.encounter.has("secondaries") else -1})
	var survived: Dictionary=app.session.snapshot()
	check(survived.player.vitals.hull>0 and attackers.all(func(actor):return survived.encounter.combat.actors[int(actor.actor_id)].vitals.hull<=0),"Earned route left an active attacker or a dead player at "+label)
	return failures==0

func nearest_neutral_distance_squared(actor: Dictionary,neutrals: Array) -> float:
	var nearest:=1.0e30
	for neutral in neutrals:nearest=minf(nearest,actor.position.distance_squared_to(neutral.position))
	return nearest

func suppress_kappa_for_gate() -> bool:
	var initial: Dictionary=app.session.snapshot()
	check(initial.location.station_id==55 and initial.encounter.has("secondaries") and initial.encounter.secondaries.guns[0].ammunition>0,"The real gate9 escape lacks its paid EMP or Kappa arrival")
	if failures:return false
	if not select_paid_emp():return false
	app.session.rebase_time(now_us)
	var pulses:=0
	for tick in 180:
		var state: Dictionary=app.session.snapshot()
		var hostiles: Array=state.encounter.combat.actors.filter(func(actor):return actor.active and actor.hostile and actor.vitals.hull>0)
		var due: Array=hostiles.filter(func(actor):return not actor.systems_disabled)
		if due.is_empty():return true
		var neutrals: Array=state.encounter.combat.actors.filter(func(actor):return actor.active and not actor.hostile and actor.vitals.hull>0)
		var center:=Vector3.ZERO
		for actor in due:center+=actor.position
		center/=float(due.size())
		var offset: Vector3=center-state.player_pose.origin
		var muzzle: Vector3=state.player_pose.origin+state.player_pose.basis.z*400.0
		var radius: float=float(catalogue.tables.items[43].properties[14])
		var clearance: float=sqrt(nearest_neutral_distance_squared({"position":muzzle},neutrals))
		var covered: int=hostiles.filter(func(actor):return actor.position.distance_to(muzzle)<radius).size()
		var damage: float=float(catalogue.tables.items[43].properties[10])
		var suppressible: Array=due.filter(func(actor):return damage*(1.0-actor.position.distance_to(muzzle)/radius)>=float(actor.systems.integrity)+8.0)
		if tick%30==0:print("Earned Kappa gate EMP approach ",tick," center distance ",int(offset.length())," neutral clearance ",int(clearance)," pirate coverage ",covered," suppressible ",suppressible.map(func(actor):return actor.actor_id)," player ",state.player.vitals)
		var bomb: Dictionary=state.encounter.secondaries.guns[0].bomb
		var ammo: int=state.encounter.secondaries.guns[0].ammunition
		if pulses<4 and ammo>0 and bomb.shot.get("phase")!="flying" and bomb.elapsed_ms>bomb.weapon.interval_ms and clearance>radius+8000.0 and not suppressible.is_empty():
			if not app.session.action("missiles"):check(false,app.session.error);return false
			now_us+=100000
			if not app.session.step(now_us,Vector2.ZERO,false):check(false,app.session.error);return false
			var flying: Dictionary=app.session.snapshot()
			var shot: Dictionary=flying.encounter.secondaries.guns[0].bomb.shot
			var live_neutrals: Array=flying.encounter.combat.actors.filter(func(actor):return actor.active and not actor.hostile and actor.vitals.hull>0)
			check(shot.get("phase")=="flying" and sqrt(nearest_neutral_distance_squared({"position":shot.position},live_neutrals))>radius+4000.0,"The actual EMP projectile lost neutral clearance before detonation")
			if failures:return false
			if not app.session.action("missiles"):check(false,app.session.error);return false
			now_us+=100000
			if not app.session.step(now_us,Vector2.ZERO,false):check(false,app.session.error);return false
			var pulsed: Dictionary=app.session.snapshot()
			var disabled: Array=pulsed.encounter.combat.actors.filter(func(actor):return actor.hostile and actor.systems_disabled)
			print("Earned Kappa gate EMP pulse: ",{"ammunition":pulsed.encounter.secondaries.guns[0].ammunition,"disabled":disabled.map(func(actor):return actor.actor_id),"systems":pulsed.encounter.combat.actors.filter(func(actor):return actor.hostile).map(func(actor):return {"id":actor.actor_id,"pool":actor.systems}),"player":pulsed.player.vitals,"provocation":pulsed.encounter.combat.get("provocation",{}).get("forced_hostile",[])})
			check(pulsed.encounter.secondaries.guns[0].ammunition==ammo-1 and due.any(func(actor):return disabled.any(func(hit):return hit.actor_id==actor.actor_id)) and pulsed.encounter.combat.actors.slice(0,4).all(func(actor):return not actor.hostile),"The real Kappa EMP failed to suppress a live pirate without provoking patrols")
			if failures:return false
			pulses+=1
			if disabled.size()==hostiles.size():return true
			continue
		var local: Vector3=state.player_pose.basis.inverse()*offset
		var angles:=Vector2(-atan2(local.y,sqrt(local.x*local.x+local.z*local.z)),atan2(local.x,local.z))
		var command:=Vector2(signf(angles.x)*sqrt(minf(absf(angles.x)*2.0,1.0)),signf(angles.y)*sqrt(minf(absf(angles.y)*2.0,1.0)))
		var desired:=1.0
		while absf(float(app.session.snapshot().input_throttle)-desired)>.05:
			if not app.session.action("throttle_down" if desired==0.0 else "throttle_up"):check(false,app.session.error);return false
		now_us+=100000
		if not app.session.step(now_us,command,false):check(false,app.session.error);return false
		if app.session.flight_owner().death_active():check(false,"The actual Kappa EMP approach was destroyed by the hostile traffic");return false
		if tick%20==0:await process_frame
	check(false,"The actual Kappa pirate cluster never entered a neutral-safe EMP pulse")
	return false

func approach_kappa_gate() -> bool:
	var entry: Dictionary=app.session.snapshot()
	var index: int=int(definitions.mido_travel.gate_transit.contact.environment_object_index)
	var gates: Array=entry.gate_animation.layout.objects.filter(func(row):return row.index==index and row.interactive)
	check(gates.size()==1 and entry.gate_transit.phase=="flight","The actual Kappa arrival has no active source gate to approach")
	if failures:return false
	var gate: Dictionary=gates[0]
	var safe_stop: float=maxf(float(gate.collision_radius)*1.8,8000.0)
	app.session.rebase_time(now_us)
	for tick in 500:
		var state: Dictionary=app.session.snapshot()
		var offset: Vector3=gate.pose.origin-state.player_pose.origin
		if tick%30==0:print("Earned Kappa manual gate approach ",tick," distance ",int(offset.length())," stop ",int(safe_stop)," player ",state.player.vitals)
		if offset.length()<=safe_stop:
			check(state.gate_transit.phase=="flight" and state.player.vitals.hull>0,"The manual approach crossed the gate before the real map course")
			return failures==0
		if kappa_emp_refresh_needed(state) and not try_paid_emp(state,4500,1000.0,"Kappa manual tick "+str(tick)):return false
		var local: Vector3=state.player_pose.basis.inverse()*offset
		var angles:=Vector2(-atan2(local.y,sqrt(local.x*local.x+local.z*local.z)),atan2(local.x,local.z))
		var command:=Vector2(signf(angles.x)*sqrt(minf(absf(angles.x)*2.0,1.0)),signf(angles.y)*sqrt(minf(absf(angles.y)*2.0,1.0)))
		while float(app.session.snapshot().input_throttle)<.95:
			if not app.session.action("throttle_up"):check(false,app.session.error);return false
		now_us+=100000
		if not app.session.step(now_us,command,false):check(false,app.session.error);return false
		if app.session.flight_owner().death_active():check(false,"The earned manual Kappa gate approach was destroyed");return false
		if tick%20==0:await process_frame
	check(false,"The source gate remained beyond the actual disabled-traffic approach")
	return false

func reach_gate_confirmation() -> bool:
	var before: Dictionary=app.session.snapshot()
	if before.location.station_id not in [35,55]:return await super.reach_gate_confirmation()
	return await reach_paid_gate_confirmation()

func reach_paid_gate_confirmation(refresh_ms:=10000,reserve_ammunition:=true) -> bool:
	var before: Dictionary=app.session.snapshot()
	if not before.encounter.has("secondaries") or before.encounter.secondaries.guns[0].ammunition<=0:return await super.reach_gate_confirmation()
	if not select_paid_emp():return false
	var label:="station "+str(before.location.station_id)+" gate"
	var coasting:=false
	for tick in 1800:
		if app.session.status!="running":break
		resume_application_focus()
		var frame: Dictionary=app.session.snapshot()
		var emp_request: Dictionary={}
		if app.session.can_control() and (not reserve_ammunition or before.location.station_id==35 or kappa_emp_refresh_needed(frame)) and not try_paid_emp(frame,refresh_ms,5000.0,label+" tick "+str(tick),true,emp_request):return false
		now_us+=100000
		if not app.session.step(now_us):check(false,app.session.error);return false
		var advanced: Dictionary=app.session.snapshot()
		if not verify_emp_request(emp_request,frame,advanced,label+" tick "+str(tick)):return false
		frame=advanced
		if frame.player.vitals.hull<=0:check(false,"Gate approach was destroyed: "+str({"station":frame.location.station_id,"clock":frame.world_elapsed_ms,"vitals":frame.player.vitals,"pose":frame.player_pose.origin}));return false
		coasting=coasting or frame.gate_transit.coasting
		if tick%100==0:
			print("Earned ",label," guidance ",tick," player ",frame.player.vitals," can_control ",app.session.can_control()," hostiles ",frame.encounter.combat.actors.filter(func(actor):return actor.hostile and actor.active and actor.vitals.hull>0).map(func(actor):return {"id":actor.actor_id,"distance":int(actor.position.distance_to(frame.player_pose.origin)),"disabled":actor.systems_disabled,"system_ms":actor.systems.elapsed_ms}))
			await process_frame
	app.present_session()
	var observed: Dictionary=app.session.snapshot()
	check(app.session.status=="gate_confirmation_required" and coasting,"Actual gate guidance did not coast into its source confirmation: "+str({"status":app.session.status,"station":before.location.station_id,"coasting":coasting,"player":observed.player.vitals,"world_ms":observed.world_elapsed_ms}))
	return failures==0

func clear_route_attacker(actor_id: int,use_emp: bool) -> bool:
	# Approach with the inherited primary steering. Hand control to the shared
	# combat pilot only when its next live EMP pulse clears neutral traffic.
	resume_application_focus();app.session.rebase_time(now_us)
	var previous: Variant=null
	for tick in 900:
		resume_application_focus()
		var state: Dictionary=app.session.snapshot()
		var target: Dictionary=state.encounter.combat.actors[actor_id]
		if target.vitals.hull<=0:return true
		var offset: Vector3=target.position-state.player_pose.origin
		var aim:=offset
		if previous!=null:
			var speed: float=state.encounter.primaries.guns[0].projectiles.weapon.speed_units_per_millisecond
			aim+=(target.position-previous)/100.0*minf(offset.length()/speed,2000.0)
		previous=target.position
		var local: Vector3=state.player_pose.basis.inverse()*aim
		var angles:=Vector2(-atan2(local.y,sqrt(local.x*local.x+local.z*local.z)),atan2(local.x,local.z))
		var command:=Vector2(signf(angles.x)*sqrt(minf(absf(angles.x)*2.0,1.0)),signf(angles.y)*sqrt(minf(absf(angles.y)*2.0,1.0)))
		if use_emp:
			if target.systems_disabled:return await clear_return_attacker(actor_id)
			var gun: Dictionary=state.encounter.secondaries.guns[0]
			var bomb: Dictionary=gun.bomb
			var neutrals: Array=state.encounter.combat.actors.filter(func(other):return other.active and not other.hostile and other.vitals.hull>0)
			var flying: bool=bomb.shot.get("phase")=="flying"
			var pulse_position: Vector3=bomb.shot.position if flying else state.player_pose.origin+state.player_pose.basis.z*400.0
			var clearance: float=sqrt(nearest_neutral_distance_squared({"position":pulse_position},neutrals))
			var radius: float=float(catalogue.tables.items[int(gun.equipment.item_id)].properties[14])
			if clearance>radius+8000.0 and ((flying and target.position.distance_to(pulse_position)<radius) or (not flying and gun.ammunition>0 and bomb.elapsed_ms>bomb.weapon.interval_ms and offset.length()<18000.0 and angles.length()<.7)):
				if not app.session.action("missiles"):check(false,app.session.error);return false
				print("Earned route live EMP ","detonated" if flying else "launched"," for actor ",actor_id," target distance ",int(offset.length())," neutral clearance ",int(clearance))
		var desired:=1.0 if use_emp or offset.length()>6000.0 else 0.0
		while absf(float(app.session.snapshot().input_throttle)-desired)>.05:
			if not app.session.action("throttle_up" if desired>0 else "throttle_down"):check(false,app.session.error);return false
		now_us+=100000
		if not app.session.step(now_us,command,offset.length()<24000 and angles.length()<.2):check(false,app.session.error);return false
		if app.session.flight_owner().death_active():check(false,"The earned route pilot died fighting attacker "+str(actor_id));return false
		if tick%100==0:print("Earned route combat: ",tick," attacker ",actor_id," distance ",int(offset.length())," enemy hull ",target.vitals.hull," player hull ",state.player.vitals.hull)
		if tick%20==0:await process_frame
	check(false,"The earned route pilot never defeated attacker "+str(actor_id))
	return false

## Pilot decision only: fire/detonate the actual paid launcher, preserving its
## cooldown, range, damage falloff and friendly-fire behavior in the simulation.
func select_paid_emp() -> bool:
	var selected: Dictionary=app.session.snapshot()
	var item_id: int=int(selected.encounter.secondaries.guns[0].equipment.item_id)
	if selected.encounter.selected_secondary==item_id:return true
	if not app.open_secondary_menu(now_us) or not app.session.confirm_secondary(item_id,now_us):check(false,app.status.text+app.session.error);return false
	app.present_session();resume_application_focus()
	check(app.session.snapshot().encounter.selected_secondary==item_id,"The real secondary menu did not select the installed paid EMP")
	return failures==0

func kappa_emp_refresh_needed(state: Dictionary) -> bool:
	# The already-confirmed two-pulse Kappa suppression opens the gate approach.
	# Preserve the purchased rounds for the longer Weymire station guidance while
	# this real player hull can absorb recovered traffic; use a pulse if endangered.
	return state.encounter.secondaries.guns[0].ammunition>5 or int(state.player.vitals.hull)<45

func verify_emp_request(request: Dictionary,before: Dictionary,after: Dictionary,label: String) -> bool:
	if request.is_empty():return true
	var old_gun: Dictionary=before.encounter.secondaries.guns[0]
	var new_gun: Dictionary=after.encounter.secondaries.guns[0]
	if request.kind=="launch":
		check(new_gun.ammunition==old_gun.ammunition-1 and new_gun.bomb.shot.get("phase")=="flying","The selected paid EMP did not launch during "+label)
	else:
		check(new_gun.bomb.shot.get("phase")!="flying","The paid EMP did not detonate during "+label)
	if failures:return false
	print("Earned EMP ",label," ",request.kind," confirmed, rounds ",new_gun.ammunition)
	return true

func try_paid_emp(state: Dictionary,refresh_ms: int,neutral_margin: float,label: String,require_disable:=false,request: Dictionary={}) -> bool:
	var gun: Dictionary=state.encounter.secondaries.guns[0]
	var bomb: Dictionary=gun.bomb
	var flying: bool=bomb.shot.get("phase")=="flying"
	var point: Vector3=bomb.shot.position if flying else state.player_pose.origin+state.player_pose.basis.z*400.0
	var radius: float=float(catalogue.tables.items[int(gun.equipment.item_id)].properties[14])
	var damage: float=float(catalogue.tables.items[int(gun.equipment.item_id)].properties[10])
	var actors: Array=state.encounter.combat.actors
	var neutrals: Array=actors.filter(func(actor):return actor.active and not actor.hostile and actor.vitals.hull>0)
	var due: Array=actors.filter(func(actor):return actor.active and actor.hostile and actor.vitals.hull>0 and (not actor.systems_disabled or actor.systems.elapsed_ms>=refresh_ms))
	var targets: Array=due.filter(func(actor):
		var threshold: float=float(actor.systems.integrity)+8.0
		# Basic EMP can need successive pulses; partial systems damage persists.
		if int(gun.equipment.item_id)==41:threshold=minf(threshold,damage*.25)
		return actor.position.distance_to(point)<radius*.95 and (not require_disable or damage*(1.0-actor.position.distance_to(point)/radius)>=threshold))
	var clearance: float=sqrt(nearest_neutral_distance_squared({"position":point},neutrals))
	if clearance>radius+neutral_margin and not targets.is_empty() and (flying or (gun.ammunition>0 and bomb.elapsed_ms>bomb.weapon.interval_ms)):
		if not app.session.action("missiles"):check(false,app.session.error);return false
		request.kind="detonation" if flying else "launch"
		print("Earned EMP ",label," ",request.kind," requested against ",targets.map(func(actor):return actor.actor_id)," rounds ",gun.ammunition)
	return true

func advance_story(frame: RefCounted,milliseconds: int,commands: Vector2,throttle: float,fire:=false) -> RefCounted:
	resume_application_focus()
	if app.session.can_control():
		var state: Dictionary=app.session.snapshot()
		if state.player.campaign_cursor==26 and state.campaign_cursor==26 and state.encounter.selected_secondary==43 and not try_paid_emp(state,9000,1000.0,"Sahi pursuit",true):return null
		for step in 10:
			var current: float=app.session.snapshot().input_throttle
			if absf(current-throttle)<.01:break
			if not app.session.action("throttle_down" if current>throttle else "throttle_up"):check(false,app.session.error);return null
	now_us+=milliseconds*1000
	if not app.session.step(now_us,commands,fire):check(false,app.session.error);return null
	var next: RefCounted=app.session.flight_owner()
	if next.death_active():check(false,"The earned Sahi pilot died before its next boundary");return null
	return next

func acknowledge_story_lines(events: Array) -> bool:
	for tick in 200:
		if app.session.snapshot().dialogue.visible:break
		if advance_story(app.session.flight_owner(),100,Vector2.ZERO,0)==null:return false
	var first: Dictionary=app.session.snapshot()
	check(first.dialogue.visible and first.dialogue.count==events.size(),"The actual story flight did not open its original conversation")
	if failures:return false
	for event in events:
		var shown: Dictionary=app.session.snapshot().dialogue
		check(shown.text_id==int(event.text_id) and shown.voice_event_id==int(event.voice_event_id),"The earned story selected another line or voice")
		if not app.session.navigate("next"):check(false,app.session.error);return false
	return failures==0

func adopt_portal(cursor: int) -> bool:
	var before: Dictionary=app.session.snapshot()
	if not app.enter_portal_arrival(now_us,4096,1789100000):check(false,app.status.text);return false
	var after: Dictionary=app.session.snapshot()
	check(after.campaign_cursor==cursor and after.player.vitals==before.player.vitals and after.cargo.used==before.cargo.used,"Portal adoption changed living pools, cargo quantity or its original next mission")
	check(after.contracts.credits==before.contracts.credits and after.contracts.mission==retained_job and after.contracts.passengers==3,"Portal adoption lost the retained paid career")
	return failures==0

func fly_void_portal() -> bool:
	for tick in 3500:
		if app.session.status=="void_return_transition_required":return true
		var state: Dictionary=app.session.snapshot()
		var offset: Vector3=state.player_pose.basis.inverse()*(state.void_portal.position-state.player_pose.origin)
		var angles:=Vector2(-atan2(offset.y,sqrt(offset.x*offset.x+offset.z*offset.z)),atan2(offset.x,offset.z))
		var commands:=Vector2(signf(angles.x)*sqrt(minf(absf(angles.x)*2,1)),signf(angles.y)*sqrt(minf(absf(angles.y)*2,1)))
		if advance_story(app.session.flight_owner(),100,commands,1)==null:return false
		if tick%20==0:await process_frame
	check(false,"The earned Void pilot did not reach its returning portal")
	return false

func capture_story(_scene: Node3D,_frame: RefCounted,label: String) -> void:
	app.present_session()
	await capture_free_application(label)
