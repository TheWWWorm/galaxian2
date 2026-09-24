extends "res://tests/campaign_visit_application.gd"
## Paid EMP acquisition and retained ammunition through the real application.
## Start with the inherited earned campaign or an identity-matching native save;
## never insert equipment, change a saved cursor, or manufacture a wallet.
const SecondaryRules=preload("res://src/content/secondary_ownership_definitions.gd")
const FittedSave=preload("res://src/simulation/station_save_file.gd")
var _emp_save_directory:=""

func verify_free_application() -> void:
	_emp_save_directory=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	if _emp_save_directory.is_empty() or not FreePlayCheckpoint.private_path(_emp_save_directory+"/save.bin"):
		check(false,"Use a private secondary-fitting save directory");return
	if not SecondaryRules.available(definitions):check(false,"The selected content lacks equipped EMP support");return
	if DisplayServer.get_name()!="headless":
		_free_capture_dir=_emp_save_directory.path_join("captures")
		if DirAccess.make_dir_recursive_absolute(_free_capture_dir)!=OK:check(false,"Could not prepare private EMP captures");return
	app.enable_saves(_emp_save_directory)
	app.show();app.present_session();await process_frame;resume_application_focus()
	if not retain_emp_save("earned-before-fitting"):return
	var initial: Dictionary=app.session.station_owner().snapshot()
	if initial.contracts.mission.is_empty():
		if not await acquire_passenger_cabin():return
		var station: RefCounted=app.session.station_owner();var chosen:=-1
		for id in station.snapshot().contracts.offers:
			var offer: Dictionary=station.snapshot().contracts.offers[id].offer
			if offer.mission.kind==11 and offer.mission.station_id==99 and offer.mission.difficulty==1 and station.contract_preview(id,definitions).get("can_accept",false):chosen=id;break
		if chosen<0:check(false,"The earned station lacks its genuine three-passenger offer");return
		if not app.contract_action("open",-1) or not app.contract_action("accept",chosen) or not app.contract_action("close",-1):check(false,app.status.text);return
	var retained: Dictionary=app.session.station_owner().snapshot()
	check(retained.contracts.passengers==3 and retained.contracts.mission.kind==11 and retained.contracts.mission.station_id==99,"The fitting trip lost its actually accepted passengers")
	if failures or not retain_emp_save("passengers-before-fitting"):return
	var purchase: Dictionary=await find_paid_emp()
	if purchase.is_empty():return
	var quote: Dictionary=purchase.quote;var offer: Dictionary=purchase.offer
	var id: int=offer.item_id;var price: int=offer.unit_price
	var quantity: int=purchase.quantity;var remaining:=quantity-1
	var panel: Control=app.equipment_panel
	panel.select_tab("shop")
	for unit in quantity:panel._rows[id].actions.buy.pressed.emit()
	var bought: Dictionary=app.session.station_owner().snapshot()
	check(bought.contracts.credits==quote.contracts.credits-quantity*price and bought.cargo.used==quote.cargo.used+quantity,"EMP rounds were not acquired through actual paid purchases")
	check(not bought.loadout.equipment_ids.has(id),"Buying EMP cargo silently installed it")
	panel.select_tab("cargo");panel._rows[id].actions.mount.pressed.emit()
	var mounted: Dictionary=app.session.station_owner().snapshot();var slot:=-1
	for index in mounted.loadout.slots.size():
		if mounted.loadout.slots[index]!=null and mounted.loadout.slots[index].item_id==id:slot=index;break
	if slot<0:check(false,"The actual Mount button did not install paid EMP cargo: "+app.status.text);return
	check(mounted.loadout.slots[slot].category==1 and mounted.loadout.slots[slot].quantity==quantity and mounted.cargo==quote.cargo,"EMP fitting did not move the whole stack out of cargo")
	check(mounted.contracts.credits==bought.contracts.credits and mounted.mission==retained.mission and mounted.contracts.mission==retained.contracts.mission and mounted.contracts.passengers==3,"EMP fitting changed the wallet, story or accepted passenger job")
	check(app.session.audio.snapshot().equipment_effects.back()==98,"Mounting a paid EMP stack omitted the source equipment sound")
	panel.select_tab("ship")
	check(panel._installed_rows[slot].node.visible,"The fitted EMP stack has no installed slot row")
	await capture_free_application("emp-paid-installed")
	if not app.equipment_action("close") or not retain_emp_save("emp-fitted"):return
	verify_saved_ammunition(slot)
	if failures:return
	var fitted: Dictionary=app.session.station_owner().snapshot()
	if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
	if not await release_application_flight():return
	var live: Dictionary=app.session.snapshot()
	check(app.session.secondary_available() and live.encounter.selected_secondary==-1 and live.encounter.secondaries.guns[0].ammunition==quantity,"Actual fitted departure lost its ammunition or invented a selection")
	check(app.session.flight_owner()._encounter.secondary_owner().has_detonations(),"Actual fitted departure omitted its original burst resources")
	if not app.open_secondary_menu(now_us):check(false,app.status.text);return
	check(app.session.secondary_menu_active() and app.secondary_panel.visible,"The equipped flight did not open its paused selection menu")
	if not app.session.confirm_secondary(id,now_us):check(false,app.session.error);return
	app.present_session();resume_application_focus()
	if not press_emp():return
	var fired: Dictionary=app.session.snapshot()
	check(fired.encounter.secondaries.launches==1 and fired.encounter.secondaries.guns[0].ammunition==remaining,"Actual R input did not consume exactly one purchased round")
	check(fired.encounter.secondary_events.size()==1 and fired.encounter.secondary_events[0].action=="launched","Actual R input did not publish its live launch event")
	var active_loadout: Dictionary=fired.encounter.secondaries.loadout.duplicate(true)
	check(active_loadout.get("campaign_cursor")==fired.campaign_cursor,"The launcher lost its actual encounter cursor")
	# The station inventory intentionally has no encounter cursor. Compare
	# every retained inventory field after checking that flight-only metadata.
	active_loadout.erase("campaign_cursor")
	check(fired.equipment.loadout.slots[slot].quantity==remaining and active_loadout==fired.equipment.loadout,"Firing failed to retain the same equipped ammunition across owners")
	await capture_free_application("emp-paid-flight")
	if not press_emp():return
	var detonated: Dictionary=app.session.snapshot()
	check(detonated.encounter.secondaries.guns[0].bomb.shot.phase=="detonated" and detonated.encounter.secondaries.guns[0].ammunition==remaining,"The second R edge spent another round instead of detonating")
	if not application_step():return
	check(app.session.snapshot().encounter.secondaries.guns[0].detonation.effect.active,"Actual detonation did not create its original burst")
	await capture_free_application("emp-paid-burst")
	if failures or not await dock_application():return
	var landed: Dictionary=app.session.station_owner().snapshot()
	check(landed.loadout.slots[slot].quantity==remaining and landed.cargo==fitted.cargo,"Docking restored spent EMP ammunition or changed cargo")
	check(landed.contracts.credits==fitted.contracts.credits and landed.contracts.passengers==3 and landed.contracts.mission==fitted.contracts.mission and landed.mission==fitted.mission,"Armed docking changed the wallet, passengers, accepted job or story")
	if not retain_emp_save("emp-spent-return"):return
	if not app.equipment_action("open"):check(false,app.status.text);return
	panel.select_tab("ship");panel._installed_rows[slot].button.pressed.emit()
	var demounted: Dictionary=app.session.station_owner().snapshot()
	check(demounted.loadout.slots[slot]==null and demounted.cargo.used==landed.cargo.used+remaining,"Demounting returned purchased rather than remaining ammunition")
	panel.select_tab("cargo");panel._rows[id].actions.mount.pressed.emit()
	check(app.session.station_owner().snapshot().loadout.slots[slot].quantity==remaining,"Remounting created extra ammunition")
	if not app.equipment_action("close") or not retain_emp_save("emp-remounted-return"):return
	if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
	if not await release_application_flight():return
	check(app.session.snapshot().encounter.secondaries.guns[0].ammunition==remaining and app.session.snapshot().encounter.secondaries.launches==0,"Relaunch restored spent ammunition or retained an old projectile")
	print("Paid EMP ",id," at ",price,"cr: bought/fitted",quantity," -> launched/detonated1 -> docked/saved/remounted/relaunched",remaining,", with three accepted passengers retained")
	if failures:return
	await verify_empty_return(id,slot,remaining,fitted)

func verify_empty_return(id: int,slot: int,remaining: int,fitted: Dictionary) -> void:
	if not app.open_secondary_menu(now_us) or not app.session.confirm_secondary(id,now_us):check(false,app.status.text+app.session.error);return
	app.present_session();resume_application_focus()
	for round_index in remaining:
		var ready:=false
		for tick in 200:
			var feedback: Dictionary=app.session.flight_owner().secondary_feedback()
			if feedback.get("actions",[]).any(func(action):return action.action=="launched"):
				ready=true;break
			if not application_step():return
		if not ready:check(false,"The retained EMP launcher never completed its actual reload");return
		if not press_emp() or not press_emp():return
		check(app.session.snapshot().encounter.secondaries.guns[0].ammunition==remaining-round_index-1,"The remaining purchased rounds were not consumed exactly once")
	var empty: Dictionary=app.session.snapshot()
	check(empty.equipment.loadout.slots[slot]==null and not empty.equipment.loadout.equipment_ids.has(id) and empty.encounter.secondaries.guns[0].bomb.shot.phase=="detonated","The last round left installed ammunition or prevented its live bomb from detonating")
	if failures or not await dock_application():return
	var landed: Dictionary=app.session.station_owner().snapshot()
	check(landed.loadout.slots[slot]==null and landed.cargo==fitted.cargo and landed.contracts.credits==fitted.contracts.credits and landed.contracts.passengers==3 and landed.contracts.mission==fitted.contracts.mission,"Empty-launcher docking restored ammunition or changed the retained cargo, wallet or passengers")
	if not retain_emp_save("emp-empty-return"):return
	if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
	if not await release_application_flight():return
	check(not app.session.secondary_available() and not app.session.snapshot().equipment.loadout.equipment_ids.has(id),"Empty-launcher relaunch recreated a spent weapon")

func find_paid_emp() -> Dictionary:
	# Follow actual supported local travel, not a generated market or a credit
	# grant. Exclude99: delivering there would complete the retained passenger
	# job. Two rounds suffice to verify that firing leaves real ammunition.
	for destination in [-1,96,97,95]:
		var current: int=app.session.station_owner().snapshot().loadout.station_id
		if destination==current:continue
		if destination>=0 and not await visit_delivery_station(destination):return {}
		if not app.equipment_action("open"):check(false,app.status.text);return {}
		var quote: Dictionary=app.session.station_owner().snapshot()
		var available:=[];var offer: Dictionary={};var quantity:=0
		for row in quote.equipment.market_rows:
			if row.item_id not in [41,42,43]:continue
			available.append({"item_id":row.item_id,"stock":row.stock,"price":row.unit_price})
			if row.stock<2 or row.unit_price<=0 or not quote.equipment.fitting_support[row.item_id].is_empty():continue
			var affordable:=mini(3,mini(int(row.stock),int(floor(float(quote.contracts.credits)/float(row.unit_price)))))
			if affordable>=2 and (offer.is_empty() or row.unit_price<offer.unit_price):offer=row;quantity=affordable
		print("Actual EMP stock at ",quote.loadout.station_id,": ",available,"; wallet ",quote.contracts.credits)
		if not app.equipment_action("close"):check(false,app.status.text);return {}
		var label: String=("emp-searched-" if offer.is_empty() else "emp-supplier-")+str(quote.loadout.station_id)
		if not retain_emp_save(label):return {}
		if not offer.is_empty():
			if not app.equipment_action("open"):check(false,app.status.text);return {}
			return {"quote":app.session.station_owner().snapshot(),"offer":offer,"quantity":quantity}
	check(false,"Actual local suppliers offered no affordable supported EMP pair")
	return {}

func verify_saved_ammunition(slot: int) -> void:
	var file:=FittedSave.new()
	var document:=file.load_document(app.station_save_path(),definitions,catalogue,source)
	if document.is_empty():check(false,file.error);return
	var before: Dictionary=app.session.station_owner().snapshot()
	var archive:=FittedSave.Archive.new()
	# This native binary format keeps integer quantities; it does not parse
	# integral JSON floats. Never change the actual file or retained game.
	for invalid in [0,-1,1.5,3.0,true,2147483648]:
		var altered: Dictionary=document.duplicate(true)
		altered.inventory.loadout.slots[slot].quantity=invalid
		altered.station.loadout.slots[slot].quantity=invalid
		check(archive.restore(definitions,catalogue,source,altered)==null,"Native save accepted malformed installed ammunition")
	for index in before.loadout.slots.size():
		if before.loadout.slots[index]==null or before.loadout.slots[index].category==1:continue
		var altered: Dictionary=document.duplicate(true)
		altered.inventory.loadout.slots[index].quantity=2
		altered.station.loadout.slots[index].quantity=2
		check(archive.restore(definitions,catalogue,source,altered)==null,"Native save treated unit equipment as an ammunition stack")
	check(app.session.station_owner().snapshot()==before,"Rejected ammunition records changed the actual saved career")

func press_emp() -> bool:
	resume_application_focus()
	var key:=InputEventKey.new();key.physical_keycode=KEY_R;key.pressed=true
	app._unhandled_input(key)
	if not app.session._secondary_requested:check(false,"Actual R key failed to queue an equipped secondary edge");return false
	if not application_step():return false
	key.pressed=false;app._unhandled_input(key)
	return true

func retain_emp_save(label: String) -> bool:
	var before: Dictionary=app.session.station_owner().snapshot()
	if not app.save_station():check(false,app._save_notice.text);return false
	var path:=_emp_save_directory.path_join(label+".gof2save")
	if FileAccess.file_exists(path):check(false,"Use a fresh private save directory, not an existing fixture");return false
	if DirAccess.copy_absolute(app.station_save_path(),path)!=OK:check(false,"Could not retain the actual native station save");return false
	if not app.load_station(now_us):check(false,app._save_notice.text);return false
	check(app.session.station_owner().snapshot()==before,"Native save/load changed the earned station: "+label)
	print("Actual native save: ",path)
	return failures==0
