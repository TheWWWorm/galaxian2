extends "res://tests/shopping_application.gd"
## Actual owned equipment, paid trading, UI fitting and unarmed travel. The
## successful route never supplies credits, equipment or campaign progress.
func verify_free_application() -> void:
	var original: Dictionary=app.session.station_owner().snapshot()
	if OS.get_environment("GOF2_FITTING_COURIER_RETURN")=="1":
		await verify_courier_return(original)
		return
	if not original.contracts.mission.is_empty():
		await verify_active_contract_fitting(original)
		return
	app.show();app.present_session();await process_frame;resume_application_focus()
	if not app.equipment_action("open"):check(false,app.status.text);return
	var panel: Control=app.equipment_panel
	var quote: Dictionary=app.session.station_owner().snapshot()
	if not quote.equipment.has("fitting_support"):check(false,"The earned hangar has no fitting capability");return
	# Sell and buy the real spare back at its current quote. This exercises a
	# paid acquisition even when the generated station lacks another cheap gun.
	panel.select_tab("cargo");panel._rows[0].actions.sell.pressed.emit()
	check(app.session.snapshot().contracts.credits>original.contracts.credits,"Selling the actual spare did not earn its station price")
	panel.select_tab("shop");panel._rows[0].actions.buy.pressed.emit()
	check(app.session.snapshot().contracts.credits==original.contracts.credits,"Rebuying the same quote changed the wallet")
	var paid: Dictionary=app.session.station_owner().snapshot()
	panel.select_tab("cargo");panel._rows[0].actions.mount.pressed.emit()
	check(app.session.station_owner().snapshot()==paid,"The starter's full primary slot accepted another gun")
	panel.select_tab("ship");panel._installed_rows[0].button.pressed.emit()
	panel.select_tab("cargo");panel._rows[0].actions.mount.pressed.emit()
	var equipped: Dictionary=app.session.station_owner().snapshot()
	check(equipped.loadout.slots[0].item_id==0 and equipped.cargo.used==1,"The actual Mount button did not install the paid spare in its vacated slot")
	check(app.session.audio.snapshot().equipment_effects.back()==98,"Accepted mounting omitted its original sound")
	panel.select_tab("ship")
	check(panel._installed_rows[0].node.visible,"The installed gun has no individual slot row")
	panel._installed_rows[0].button.pressed.emit()
	check(app.session.snapshot().loadout.slots[0]==null,"The selected primary slot was not emptied")
	check(app.session.audio.snapshot().equipment_effects.back()==96,"Accepted demount omitted its original sound")
	panel.select_tab("cargo");panel._rows[0].actions.mount.pressed.emit()
	var current: Dictionary=app.session.station_owner().snapshot()
	var upgrade: Dictionary={}
	for row in current.equipment.market_rows:
		if row.stock<2 or row.unit_price<=0 or 2*row.unit_price>current.contracts.credits or not current.equipment.fitting_support[row.item_id].is_empty():continue
		if catalogue.tables.items[row.item_id].arrays[2][3]!=3:continue
		if (int(definitions.station_equipment.multiple_subtype_mask)&(1<<catalogue.tables.items[row.item_id].arrays[2][5]))!=0:continue
		if upgrade.is_empty() or (current.equipment.fitting_conflicts.has(row.item_id) and not current.equipment.fitting_conflicts.has(upgrade.item_id)) or row.unit_price<upgrade.unit_price:upgrade=row
	if not upgrade.is_empty():
		panel.select_tab("shop");panel._rows[upgrade.item_id].actions.buy.pressed.emit()
		var purchased: Dictionary=app.session.station_owner().snapshot()
		check(purchased.contracts.credits==current.contracts.credits-upgrade.unit_price,"The equipment upgrade was not paid from the actual wallet")
		# The starter also fills its passive slots. Demount its armor to fit
		# the actual shield offer; no test-created slot or inventory is used.
		panel.select_tab("ship")
		for i in purchased.loadout.slots.size():
			if purchased.loadout.slots[i]!=null and purchased.loadout.slots[i].item_id==55:panel._installed_rows[i].button.pressed.emit();break
		panel.select_tab("cargo");panel._rows[upgrade.item_id].actions.mount.pressed.emit()
		check(app.session.snapshot().loadout.equipment_ids.has(upgrade.item_id),"Fitting did not mount the purchased upgrade: "+app.status.text)
		# A second real purchase exercises the source unique-subtype prompt,
		# including replacing an item with another instance of the same ID.
		panel.select_tab("shop");panel._rows[upgrade.item_id].actions.buy.pressed.emit()
		purchased=app.session.station_owner().snapshot()
		check(purchased.contracts.credits==current.contracts.credits-2*upgrade.unit_price,"The replacement instance was not paid for")
		panel.select_tab("cargo");panel._rows[upgrade.item_id].actions.mount.pressed.emit()
		check(not panel._pending_replace.is_empty(),"A duplicate unique subtype omitted its replacement prompt")
		if not panel._pending_replace.is_empty():
			check(app.session.station_owner().snapshot()==purchased,"Opening a replacement prompt moved equipment")
			await capture_free_application("fitting-replacement-prompt")
			panel._replacement.get_cancel_button().pressed.emit()
			check(app.session.station_owner().snapshot()==purchased and panel._pending_replace.is_empty(),"Cancelling replacement changed equipment")
			resume_application_focus();panel._rows[upgrade.item_id].actions.mount.pressed.emit()
			panel._replacement.get_ok_button().pressed.emit();resume_application_focus()
		check(app.session.snapshot().loadout.equipment_ids.has(upgrade.item_id),"Confirmed fitting did not mount the purchased upgrade: "+app.status.text)
		print("Actual paid equipment upgrade ",upgrade.item_id," at ",upgrade.unit_price,"cr")
	else:check(false,"This earned station fixture no longer contains the affordable unique equipment needed by the paid replacement test");return
	panel.select_tab("ship")
	await verify_shop_layout(false);await capture_free_application("fitting-installed-desktop")
	root.size=Vector2i(960,540);app.set_mobile_layout(true);TouchInput.set_preference(app,true)
	await process_frame;resume_application_focus();app.present_session()
	await verify_shop_layout(true);await capture_free_application("fitting-installed-mobile-landscape")
	root.size=Vector2i(1280,720);app.set_mobile_layout(false);app.set_touch_controls(false)
	await process_frame;resume_application_focus();app.present_session()
	var before: Dictionary=app.session.station_owner().snapshot()
	var refused:=RefusedPanel.new();root.add_child(refused)
	check(not app.session.equipment_action("unmount",0,source,definitions,app.station_panel,refused,null,0) and app.session.station_owner().snapshot()==before,"Failed fitting presentation moved the installed gun")
	refused.free()
	if failures:return
	if not app.equipment_action("close"):check(false,app.status.text);return
	for destination in [95,98]:
		var departure: Dictionary=app.session.station_owner().snapshot()
		if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
		if not await release_application_flight():return
		var flight: RefCounted=app.session.flight_owner()
		if destination==95:
			check(flight.snapshot().player.equipment_ids==departure.loadout.equipment_ids,"Departure ignored fitted equipment")
			var fired_items: Array=[]
			for tick in 8:
				now_us+=100000
				if not app.session.step(now_us,Vector2.ZERO,true):check(false,app.session.error);return
				for gun in app.session.snapshot().encounter.primary_fire.get("weapons",[]):
					if gun.result.get("fired",false) and not fired_items.has(gun.item_id):fired_items.append(gun.item_id)
			check(fired_items==[0],"Flight did not fire only the newly mounted gun")
			await capture_free_application("fitting-armed-flight")
		else:
			check(flight.snapshot().player.capacities.armor==0 and flight.snapshot().player.capacities.shield==0,"An empty loadout restored the old shield or armor")
			check(flight.snapshot().encounter.primaries.guns.is_empty(),"Unarmed departure silently recreated a gun")
			now_us+=100000
			check(app.session.step(now_us,Vector2.ZERO,true),"Unarmed fire input failed: "+app.session.error)
			await capture_free_application("fitting-unarmed-flight")
		if not await travel_application(destination) or not await dock_application():return
		var landed: Dictionary=app.session.station_owner().snapshot()
		check(landed.loadout==departure.loadout.merged({"station_id":destination},true) and landed.cargo==departure.cargo,"Travel or docking restored the previous fitted equipment")
		check(landed.contracts.credits==departure.contracts.credits and landed.mission==original.mission and landed.contracts.completed_side_missions==4,"Fitting travel changed the wallet, jobs or pending story")
		if not app.equipment_action("open"):check(false,app.status.text);return
		if destination==95:
			var slots: Array=app.session.snapshot().loadout.slots
			panel.select_tab("ship")
			for i in slots.size():
				if slots[i]!=null:panel._installed_rows[i].button.pressed.emit()
			check(app.session.snapshot().loadout.equipment_ids.is_empty(),"The ordinary Ship tab could not demount the complete loadout")
			await capture_free_application("fitting-empty-ship")
		else:
			check(app.session.snapshot().loadout.equipment_ids.is_empty(),"Reopening at Alioth restored tutorial equipment")
			panel.select_tab("cargo");await capture_free_application("fitting-retained-cargo")
		if not app.equipment_action("close"):check(false,app.status.text);return
	if failures==0:await verify_free_game_over()

func verify_courier_return(original: Dictionary) -> void:
	# Reach the retained courier contact by normal travel from the earlier
	# earned journey; changing a saved station ID would bypass the world.
	if original.campaign_cursor!=18 or original.loadout.station_id!=95 or original.contracts.passengers!=3:check(false,"Use the earned passenger journey at Gome C for courier preparation");return
	var directory:=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	if directory.is_empty() or not FreePlayCheckpoint.private_path(directory+"/save.bin"):check(false,"Use a private courier preparation save directory");return
	app.enable_saves(directory)
	app.show();app.present_session();await process_frame;resume_application_focus()
	if not await visit_delivery_station(98):return
	var arrived: Dictionary=app.session.station_owner().snapshot()
	check(arrived.loadout==original.loadout.merged({"station_id":98},true) and arrived.cargo==original.cargo,"The actual Alioth return changed inventory")
	for key in ["mission","accepted_contact","passengers","credits","completed_side_missions","travel_statistics"]:
		check(arrived.contracts[key]==original.contracts[key],"The actual Alioth return changed retained "+key)
	check(arrived.campaign_cursor==18 and arrived.mission==original.mission,"Returning for a courier offer advanced the pending story")
	if not app.save_station() or not app.load_station(now_us):check(false,app._save_notice.text);return
	check(app.session.station_owner().snapshot()==arrived,"Saving the courier preparation changed its earned state")
	await capture_free_application("active-fitting-courier-return")
	print("Actual Gome C to Alioth passenger return saved for courier fitting coverage")

func verify_active_contract_fitting(original: Dictionary) -> void:
	# The visit application earned this save with its real passenger offer.
	# Reuse the same paid/UI/travel owners; never clear the job to enable fitting.
	if original.campaign_cursor!=19 or original.loadout.station_id!=56 or original.contracts.mission.kind!=11 or original.contracts.passengers!=3:check(false,"Use the earned Suttnar passenger save for active fitting");return
	var directory:=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	if directory.is_empty() or not FreePlayCheckpoint.private_path(directory+"/save.bin"):check(false,"Use a private active-fitting save directory");return
	var retained: RefCounted=app.session.station_owner()
	app.enable_saves(directory)
	app.show();app.present_session();await process_frame;resume_application_focus()
	if not app.equipment_action("open"):check(false,app.status.text);return
	var panel: Control=app.equipment_panel
	var quoted: Dictionary=app.session.station_owner().snapshot()
	var primary:=-1;var cabin:=-1;var spare:=-1
	for i in quoted.loadout.slots.size():
		var slot: Variant=quoted.loadout.slots[i]
		if slot==null:continue
		if slot.category==0:primary=i
		if catalogue.tables.items[slot.item_id].arrays[2][5]==20:cabin=i
	for row in quoted.equipment.market_rows:
		if row.owned>0 and not row.mission and row.unit_price>0 and catalogue.tables.items[row.item_id].arrays[2][3]==0 and quoted.equipment.fitting_support.get(row.item_id,"unsupported").is_empty():spare=row.item_id;break
	if primary<0 or cabin<0 or spare<0:check(false,"The earned passenger save lost its cabin, primary or paid spare");return
	var old_primary: int=quoted.loadout.slots[primary].item_id
	var cabin_id: int=quoted.loadout.slots[cabin].item_id
	var sound: Dictionary=app.session.audio.snapshot()
	check(not app.equipment_action("unmount",cabin_id,cabin) and app.session.station_owner().snapshot()==quoted and app.session.audio.snapshot()==sound,"Occupied-cabin refusal changed inventory or played fitting audio")
	panel.select_tab("cargo");panel._rows[spare].actions.sell.pressed.emit()
	check(app.session.snapshot().contracts.credits>quoted.contracts.credits,"Selling the owned spare during a passenger contract did not retain its price")
	panel.select_tab("shop");panel._rows[spare].actions.buy.pressed.emit()
	var paid: Dictionary=app.session.station_owner().snapshot()
	check(paid.contracts.credits==quoted.contracts.credits and paid.cargo==quoted.cargo,"The actual spare's sale/repurchase lost money or cargo")
	if failures:return
	var refused:=RefusedPanel.new();root.add_child(refused)
	check(not app.session.equipment_action("unmount",old_primary,source,definitions,app.station_panel,refused,null,primary) and app.session.station_owner().snapshot()==paid,"Refused active-fitting presentation changed the actual career")
	refused.free()
	panel.select_tab("ship");panel._installed_rows[primary].button.pressed.emit()
	check(app.session.snapshot().loadout.slots[primary]==null,"Active passengers blocked the unrelated Demount button")
	if failures:return
	panel.select_tab("cargo");panel._rows[spare].actions.mount.pressed.emit()
	var fitted: Dictionary=app.session.station_owner().snapshot()
	check(fitted.loadout.slots[primary].item_id==spare and fitted.loadout.slots[cabin]==quoted.loadout.slots[cabin],"The actual Mount button changed the wrong installed equipment")
	check(fitted.contracts==paid.contracts and fitted.mission==original.mission and fitted.progress==original.progress,"Active fitting changed passengers, wallet, job, story, progress or cached randomness")
	check(app.session.audio.snapshot().equipment_effects.slice(-2)==[96,98],"Active demount/mount omitted its original fitting sounds")
	panel.select_tab("ship");await capture_free_application("active-fitting-installed")
	if not app.equipment_action("close"):check(false,app.session.error);return
	var departure: Dictionary=app.session.station_owner().snapshot()
	if not app.save_station() or not app.load_station(now_us):check(false,app._save_notice.text);return
	check(app.session.station_owner().snapshot()==departure,"Saving or loading the actively contracted fitted ship changed retained state")
	if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
	if not await release_application_flight():return
	var fired_items: Array=[]
	for tick in 8:
		now_us+=100000
		if not app.session.step(now_us,Vector2.ZERO,true):check(false,app.session.error);return
		for gun in app.session.snapshot().encounter.primary_fire.get("weapons",[]):
			if gun.result.get("fired",false) and not fired_items.has(gun.item_id):fired_items.append(gun.item_id)
	check(fired_items==[spare] and app.session.snapshot().contracts.passengers==3,"Departure did not fire the fitted gun with its actual passengers retained")
	await capture_free_application("active-fitting-flight")
	if not app.open_map():check(false,app.status.text);return
	var kappa: Array=app.map_panel.snapshot().rows.filter(func(row):return row.station_id==55)
	check(kappa.size()==1 and kappa[0].mission_target and not kappa[0].supported,"Active fitting exposed the unfinished Kappa chapter")
	if not app.close_map(now_us):check(false,app.status.text);return
	if failures:return
	if not await travel_application(57) or not await dock_application():return
	var landed: Dictionary=app.session.station_owner().snapshot()
	check(landed.loadout==departure.loadout.merged({"station_id":57},true) and landed.cargo==departure.cargo,"Actual Tornard travel or docking discarded fitted inventory")
	for key in ["mission","accepted_contact","passengers","credits","completed_side_missions","travel_statistics"]:
		check(landed.contracts[key]==departure.contracts[key],"Active-fitting travel changed retained "+key)
	check(landed.campaign_cursor==19 and landed.mission==original.mission,"Fitting travel advanced the unfinished story")
	if not app.save_station() or not app.load_station(now_us):check(false,app._save_notice.text);return
	check(app.session.station_owner().snapshot()==landed,"The destination save lost the fitted passenger ship")
	if not app.equipment_action("open"):check(false,app.session.error);return
	var reopened: Dictionary=app.session.station_owner().snapshot()
	check(not app.equipment_action("unmount",cabin_id,cabin) and app.session.station_owner().snapshot()==reopened,"Docking and restoring removed occupied-berth protection")
	app.equipment_panel.select_tab("ship");await capture_free_application("active-fitting-tornard")
	if not app.equipment_action("close"):check(false,app.session.error);return
	check(retained.snapshot()==original,"The successful fitting journey mutated its retained departure station")
	print("Earned active passenger fitting: paid spare, UI/audio, occupied-cabin guard, save/load, actual fitted fire and Suttnar-to-Tornard docking passed")
