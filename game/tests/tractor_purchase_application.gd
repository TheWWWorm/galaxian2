extends "res://tests/kappa_rescue_application.gd"
## Acquire recovery equipment through the earned career's ordinary station services.

func verify_free_application() -> void:
	var original: Dictionary=app.session.station_owner().snapshot()
	var retained_only:=OS.get_environment("GOF2_TRACTOR_RETAIN_ONLY")=="1"
	var fitting:=OS.get_environment("GOF2_TRACTOR_FITTING")=="1"
	var purchase_only:=OS.get_environment("GOF2_TRACTOR_PURCHASE_ONLY")=="1"
	check(original.campaign_cursor==24 and original.loadout.station_id==(37 if retained_only or fitting or purchase_only else 10),"Resume the actual earned supplier prerequisite")
	if failures:return
	chapter_directory=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	if chapter_directory.is_empty() or not FreePlayCheckpoint.private_path(chapter_directory+"/save.bin"):check(false,"Set a private supplier save directory");return
	app.enable_saves(chapter_directory)
	app.show();app.present_session();await process_frame;resume_application_focus()
	retained_job=original.contracts.mission.duplicate(true)
	if fitting:
		await verify_owned_fitting(original)
		return
	if retained_only:
		check(original.cargo.entries.any(func(row):return row.item_id==68 and row.quantity==1),"The saved supplier purchase does not own its tractor")
		if not failures:verify_supplier_reopen(original)
		return
	if purchase_only:
		await purchase_tractor(original,original)
		return
	# Pan's designated supplier is still locked in this earned career. Visit
	# Carme through its actual available gate, local flight and cached stock.
	var flags: Array=app.session.station_owner().contract_owner().location_owner().snapshot().system_availability
	check(not flags[1] and flags[7],"The supplier journey must retain the original unlocked systems")
	if failures or not prepare_supplier_trip():return
	var prepared: Dictionary=app.session.station_owner().snapshot()
	if not await visit_gate(7,35) or not await release_application_flight():return
	if not await travel_application(37):return
	if not app.open_secondary_menu(now_us):check(false,app.status.text);return
	app.secondary_panel.handle_selection_event(gate_key_event(KEY_DOWN,true))
	if not app.confirm_secondary_selection(41,now_us):check(false,app.status.text);return
	var traffic: Array=app.session.snapshot().encounter.combat.actors
	var attackers: Array=traffic.filter(func(actor):return actor.hostile and actor.vitals.hull>0)
	print("Carme departure threats: ",attackers.map(func(actor):return {"id":actor.actor_id,"hull":actor.vitals.hull,"position":actor.position}))
	for actor in attackers:
		if not await clear_return_attacker(int(actor.actor_id)):return
	var survived: Dictionary=app.session.snapshot()
	if not await dock_application():return
	var landed: Dictionary=app.session.station_owner().snapshot()
	check(landed.loadout.station_id==37 and landed.campaign_cursor==24 and landed.contracts.travel_statistics.jumpgates_used==original.contracts.travel_statistics.jumpgates_used+1,"Supplier visit skipped a gate or changed campaign progress")
	check(landed.contracts.credits==prepared.contracts.credits and landed.cargo==prepared.cargo,"Supplier travel granted money or cargo")
	check(landed.loadout.equipment_ids==survived.player.equipment_ids,"Docking lost the actual surviving loadout")
	if failures or not retain_chapter_save("tractor-carme-before-purchase"):return
	await purchase_tractor(landed,original)

func purchase_tractor(landed: Dictionary,original: Dictionary) -> void:
	check(landed.campaign_cursor==24 and landed.loadout.station_id==37 and not landed.cargo.entries.any(func(row):return int(row.item_id)==68),"The paid purchase requires the earned Carme station before owning a tractor")
	if failures:return
	if not app.equipment_action("open"):check(false,app.status.text);return
	var panel: Control=app.equipment_panel
	panel.select_tab("shop")
	var supplied_stock: Array=app.session.station_owner().contract_owner().location_owner().item_stock(37)
	var offers: Array=supplied_stock.filter(func(row):return int(row.item_id) in [68,69,70])
	print("Actual Carme tractor offers: ",offers)
	check(offers.any(func(row):return row.item_id==68 and row.quantity>0 and row.unit_price>0),"Actual Carme stock has no basic tractor; do not regenerate it")
	if failures:return
	await reveal_supplier_row(panel)
	await capture_free_application("tractor-carme-shop")
	var offer: Dictionary=offers.filter(func(row):return int(row.item_id)==68)[0]
	check(panel._rows.has(68) and not panel._rows[68].actions.buy.disabled,"The earned wallet cannot buy the original basic tractor")
	if failures:return
	panel._rows[68].actions.buy.pressed.emit()
	var bought: Dictionary=app.session.station_owner().snapshot()
	check(bought.contracts.credits==landed.contracts.credits-int(offer.unit_price) and bought.cargo.used==landed.cargo.used+1,"The paid tractor did not debit its real price and occupy cargo")
	check(bought.loadout==landed.loadout and bought.campaign_cursor==24 and bought.mission==original.mission and bought.contracts.mission==retained_job and bought.contracts.passengers==3,"Buying a tractor fitted it or changed story/passengers")
	var expected_stock: Array=supplied_stock.duplicate(true)
	for row in expected_stock:
		if int(row.item_id)==68:row.quantity-=1
	expected_stock=expected_stock.filter(func(row):return row.quantity>0)
	check(app.session.station_owner().contract_owner().location_owner().item_stock(37)==expected_stock,"Purchase did not debit the cached supplier stock exactly once")
	if int(offer.quantity)==1:
		check(panel._rows[68].actions.buy.disabled,"The exhausted original offer still permits another purchase")
		check(not app.equipment_action("buy",68) and app.session.station_owner().snapshot()==bought,"Repeating an exhausted purchase duplicated cargo or changed the wallet")
	panel.select_tab("cargo")
	check(panel._rows.has(68) and bought.equipment.fitting_support[68].is_empty(),"The earned tractor lacks its cargo row or verified fitting support")
	check(bought.loadout.slots.size()==5 and bought.loadout.slots.slice(2).all(func(slot):return slot!=null and slot.category==3),"The earned ship no longer has three occupied equipment slots")
	if failures:return
	panel._rows[68].actions.mount.pressed.emit()
	check(app.status.text=="No compatible ship slot is free" and app.session.station_owner().snapshot()==bought,"Mounting into the occupied ship slots changed the paid tractor or retained career")
	await reveal_supplier_row(panel)
	await capture_free_application("tractor-owned-cargo")
	if failures:return
	if not app.equipment_action("close"):check(false,app.status.text);return
	if not retain_chapter_save("tractor-carme-owned"):return
	var retained: Dictionary=app.session.station_owner().snapshot()
	verify_supplier_reopen(retained)
	if not failures:print("Earned Aquila/Carme journey, paid tractor68 at ",offer.unit_price," credits, retained wallet ",retained.contracts.credits," and real save/load")

func verify_owned_fitting(original: Dictionary) -> void:
	check(original.cargo.entries.any(func(row):return row.item_id==68 and row.quantity==1),"The saved paid purchase has no tractor to mount")
	if failures or not app.equipment_action("open"):check(false,app.status.text);return
	var opened: Dictionary=app.session.station_owner().snapshot()
	check(opened.equipment.fitting_support[68].is_empty() and opened.equipment.fitting_support[69].is_empty(),"The verified timed tractors are still refused")
	check(not opened.equipment.fitting_support[70].is_empty() and not opened.equipment.fitting_support[194].is_empty(),"Timed recovery enabled unsupported automatic tractors")
	if failures or not mount_owned_device(68,10):return
	var fitted: Dictionary=app.session.station_owner().snapshot()
	check(fitted.loadout.equipment_ids.any(func(id):return int(id)==68) and fitted.loadout.equipment_ids.any(func(id):return int(id)==91) and not fitted.loadout.equipment_ids.any(func(id):return catalogue.tables.items[id].arrays[2][3]==3 and catalogue.tables.items[id].arrays[2][5]==10),"Mounting the paid tractor failed to exchange the original armor or preserve the passenger cabin")
	check(fitted.contracts.credits==original.contracts.credits and fitted.contracts.mission==retained_job and fitted.contracts.passengers==3 and fitted.mission==original.mission,"Fitting changed the wallet, passengers or pending story")
	app.equipment_panel.select_tab("ship")
	await capture_free_application("tractor-fitted-carme")
	if failures or not app.equipment_action("close"):return
	if not retain_chapter_save("tractor-carme-fitted"):return
	var ready: Dictionary=app.session.station_owner().snapshot()
	if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
	if not await release_application_flight():return
	var entry: Dictionary=app.session.snapshot()
	check(entry.tractor.equipment_id==68 and entry.tractor.scanner_id==-1 and entry.mining_targeting.duration_ms==8000,"The fitted departure did not use its real tractor and source default scenery clock")
	check(entry.player.equipment_ids==ready.loadout.equipment_ids and entry.cargo==ready.cargo,"Tractor departure changed the fitted inventory")
	if failures or not await recover_generated_scenery():return
	var recovered: Dictionary=app.session.snapshot()
	var accepted:=recovered_quantity(recovered)
	check(accepted>0 and recovered.campaign_cursor==24 and recovered.contracts.credits==ready.contracts.credits,"Ordinary recovery granted campaign progress or lost accepted cargo")
	if failures or not await dock_application():return
	var landed: Dictionary=app.session.station_owner().snapshot()
	check(landed.cargo==recovered.cargo and landed.loadout.equipment_ids==ready.loadout.equipment_ids,"Docking lost recovered cargo or the fitted tractor")
	check(landed.contracts.progress.get("cargo_recovered",0)==int(ready.contracts.progress.get("cargo_recovered",0))+accepted,"Docking did not credit the actual recovered quantity exactly once")
	if failures or not retain_chapter_save("tractor-carme-recovered"):return
	print("Earned paid tractor68 fitting, native firing/scenery acquisition/pickup, dock and save/load; recovered ",accepted)

func mount_owned_device(item_id: int,replaced_subtype: int) -> bool:
	var before: Dictionary=app.session.station_owner().snapshot()
	var slot:=-1
	for index in before.loadout.slots.size():
		var installed: Variant=before.loadout.slots[index]
		if installed!=null and installed.category==3 and catalogue.tables.items[installed.item_id].arrays[2][5]==replaced_subtype:slot=index;break
	check(slot>=0,"The actual ship has no replaceable equipment of subtype "+str(replaced_subtype))
	if failures:return false
	var panel: Control=app.equipment_panel
	panel.select_tab("ship");panel._installed_rows[slot].button.pressed.emit()
	panel.select_tab("cargo")
	check(panel._rows.has(item_id) and not panel._rows[item_id].actions.mount.disabled,"The owned device cannot be mounted in its vacated slot: "+app.status.text)
	if failures:return false
	panel._rows[item_id].actions.mount.pressed.emit()
	check(app.session.station_owner().snapshot().loadout.slots[slot].item_id==item_id,"The actual Mount button failed to install the paid device")
	return failures==0

func recover_generated_scenery() -> bool:
	# Shoot and collect the ordinary generated asteroids with player controls.
	# No body, cargo, player pose, RNG or campaign state is supplied by this test.
	var target:=-1
	var visited:=[]
	var captured:=false
	var side_goal: Variant=null
	var changed_view:=false
	for tick in 3600:
		resume_application_focus()
		var state: Dictionary=app.session.snapshot()
		if recovered_quantity(state)>0:
			await capture_free_application("tractor-earned-pickup")
			return true
		var field: Dictionary=state.scenery
		if target>=0 and not field.bodies.objects[target].active and not field.destruction[target].lifecycle.drop_allowed:target=-1
		if target<0:
			var candidates: Array=field.objects.filter(func(row):return row.source_size_value!=7 and not visited.has(row.index) and field.bodies.objects[row.index].active)
			candidates.sort_custom(func(a,b):return a.position.distance_squared_to(state.player_pose.origin)<b.position.distance_squared_to(state.player_pose.origin))
			if candidates.is_empty():break
			target=int(candidates[0].index);visited.append(target);side_goal=null;changed_view=false
		var life: Dictionary=field.destruction[target].lifecycle
		var dropping: bool=life.actor_state in [3,4]
		if dropping and not life.drop_allowed:target=-1;continue
		var offset: Vector3=field.objects[target].position-state.player_pose.origin
		# The original HUD keeps only the first four scenery candidates. Fly to
		# another viewing angle when intervening asteroids occupy that window.
		if dropping and not changed_view and offset.length()<9000 and not state.mining_targeting.candidate_indices.has(target):
			side_goal=state.player_pose.origin+state.player_pose.basis.x*6000.0;changed_view=true
		if side_goal!=null and state.player_pose.origin.distance_to(side_goal)<1000:side_goal=null
		var direction: Vector3=offset if side_goal==null else side_goal-state.player_pose.origin
		var local: Vector3=state.player_pose.basis.inverse()*direction
		var angles:=Vector2(-atan2(local.y,sqrt(local.x*local.x+local.z*local.z)),atan2(local.x,local.z))
		var command:=Vector2(signf(angles.x)*sqrt(minf(absf(angles.x)*2.0,1.0)),signf(angles.y)*sqrt(minf(absf(angles.y)*2.0,1.0)))
		var desired:=1.0 if side_goal!=null or offset.length()>(2500.0 if dropping else 8000.0) else 0.0
		while absf(float(app.session.snapshot().input_throttle)-desired)>.05:
			if not app.session.action("throttle_up" if desired>0 else "throttle_down"):check(false,app.session.error);return false
		now_us+=100000
		if not app.session.step(now_us,command,not dropping and offset.length()<22000 and angles.length()<.1):check(false,app.session.error);return false
		if app.session.flight_owner().death_active():check(false,"The recovery pilot died before collecting its generated cargo");return false
		if not captured and app.session.snapshot().tractor_frame.get("phase")=="pulling":
			await capture_free_application("tractor-earned-beam");captured=true
		if tick%100==0:print("Scenery recovery flight: tick ",tick," target ",target," distance ",int(offset.length())," hull ",state.player.vitals.hull," lifecycle ",life.actor_state," acquisition ",state.mining_targeting.elapsed_ms," candidate ",state.mining_targeting.candidate_object_index," recovery ",state.mining_targeting.recovery_object_index," request ",state.tractor.request_actor_id," cargo ",life.cargo)
		if tick%20==0:await process_frame
	check(false,"The ordinary generated scenery did not yield a collected cargo drop")
	return false

func recovered_quantity(state: Dictionary) -> int:
	return int(state.encounter.combat.get("recovery",{}).get("accepted_quantity",0))

func verify_supplier_reopen(retained: Dictionary) -> void:
	print("Actual purchased supplier cargo: ",retained.cargo.entries,"; used ",retained.cargo.used,"; credits ",retained.contracts.credits)
	if not app.equipment_action("open"):check(false,app.status.text);return
	print("Retained passenger job: ",retained.contracts.mission,"; quoted recovery support: ",app.session.station_owner().contract_owner().location_owner().item_stock(37).filter(func(row):return row.item_id==41))
	if not app.equipment_action("close"):check(false,app.status.text);return
	var reopened: Dictionary=app.session.station_owner().snapshot()
	# Original shop entry reprices retained items and commits its quote RNG to
	# ContractSession's locations. Every other career and inventory field stays.
	var before_quotes: Dictionary=without_station_quotes(retained)
	var after_quotes: Dictionary=without_station_quotes(reopened)
	before_quotes.contracts.lounges.erase("random")
	after_quotes.contracts.lounges.erase("random")
	check(before_quotes==after_quotes,"Reopening the supplier changed more than its source-defined pricing")
	check(app.request_departure(),app.session.error)
	app.cancel_departure()

func reveal_supplier_row(panel: Control) -> void:
	await process_frame
	var row: Control=panel._rows[68].node
	var scroll: ScrollContainer=row.get_parent().get_parent()
	scroll.ensure_control_visible(row)
	await process_frame

func without_station_quotes(value: Variant) -> Variant:
	if value is Array:return value.map(without_station_quotes)
	if not value is Dictionary:return value
	var retained: Dictionary={}
	for key in value:
		if key not in ["prices","unit_price"]:retained[key]=without_station_quotes(value[key])
	return retained

func prepare_supplier_trip() -> bool:
	var before: Dictionary=app.session.station_owner().snapshot()
	if not app.equipment_action("open"):check(false,app.status.text);return false
	var stock: Array=app.session.station_owner().contract_owner().location_owner().item_stock(10)
	var offers: Array=stock.filter(func(row):return int(row.item_id)==2 and int(row.quantity)>0 and int(row.unit_price)>0)
	check(offers.size()==1,"The earned station does not sell the primary upgrade; do not regenerate its stock")
	if failures:return false
	var offer: Dictionary=offers[0]
	var panel: Control=app.equipment_panel
	panel.select_tab("shop")
	check(panel._rows.has(2) and not panel._rows[2].actions.buy.disabled,"The earned wallet cannot buy the quoted primary")
	if failures:return false
	panel._rows[2].actions.buy.pressed.emit()
	var bought: Dictionary=app.session.station_owner().snapshot()
	check(bought.contracts.credits==before.contracts.credits-int(offer.unit_price) and bought.loadout==before.loadout,"Buying the primary did not debit its actual price or silently fitted it")
	var old_slot:=-1
	for index in before.loadout.slots.size():
		if before.loadout.slots[index]!=null and before.loadout.slots[index].item_id==22:old_slot=index;break
	check(old_slot>=0 and panel._installed_rows.has(old_slot),"The earned ship lost its original primary slot")
	if failures:return false
	panel.select_tab("ship")
	check(not panel._installed_rows[old_slot].button.disabled,"The old primary cannot be moved to cargo")
	if failures:return false
	panel._installed_rows[old_slot].button.pressed.emit()
	panel.select_tab("cargo")
	check(panel._rows.has(2) and not panel._rows[2].actions.mount.disabled,"The bought primary cannot be mounted normally")
	if failures:return false
	panel._rows[2].actions.mount.pressed.emit()
	if not app.equipment_action("close"):check(false,app.status.text);return false
	var after: Dictionary=app.session.station_owner().snapshot()
	var expected_slots: Array=before.loadout.slots.duplicate(true)
	expected_slots[old_slot].item_id=2
	var expected_cargo: Array=before.cargo.entries.duplicate(true)
	expected_cargo.append({"item_id":22,"quantity":1})
	check(after.loadout.slots==expected_slots and after.cargo.entries==expected_cargo,"The upgrade lost the original gun, scanner or retained ammunition")
	var expected_used:=0
	for entry in expected_cargo:expected_used+=int(entry.quantity)
	check(after.cargo.used==expected_used and after.cargo.free_space==after.cargo.capacity-expected_used,"The explicit fitting commit did not refresh the actual cargo quantities: "+str(after.cargo))
	check(after.campaign_cursor==24 and after.mission==before.mission and after.contracts.mission==retained_job and after.contracts.passengers==3,"The paid upgrade changed pending story or passengers")
	print("Paid primary upgrade2: ",offer.unit_price," credits; remaining wallet ",after.contracts.credits,"; original gun and scanner retained in cargo")
	return failures==0
