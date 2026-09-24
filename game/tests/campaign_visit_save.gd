extends "res://tests/station_save.gd"
## Reuse the application's earned post-visit save for corruption, shopping
## and interrupted-write checks without replaying the journey.

func verify_save(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not library.select_language("gb") or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var file:=SaveFile.new();var archive:=Archive.new()
	var record:=file.load_document(OS.get_environment("GOF2_SOURCE_SAVE"),bindings,cat,library)
	if record.is_empty():check(false,file.error);return
	var station:=archive.restore(bindings,cat,library,record)
	if station==null:check(false,archive.error);return
	var original: Dictionary=station.snapshot()
	var campaign=load("res://src/content/free_campaign_definitions.gd")
	var suttnar: bool=record.version==3 and original.campaign_cursor==19 and original.loadout.station_id in [56,57]
	var kappa: bool=record.version==4 and original.campaign_cursor in [21,22,23,24] and campaign.chapter_available(bindings.mido_travel)
	var sahi: bool=record.version==5 and original.campaign_cursor==27 and original.loadout.station_id==48 and campaign.Post.available(bindings)
	var expedition: bool=record.version==6 and ((original.campaign_cursor==28 and original.loadout.station_id in [10,35,90]) or (original.campaign_cursor==31 and original.loadout.station_id in [91,98])) and campaign.expedition_available(bindings.mido_travel)
	var post_probe: bool=record.version==7 and original.campaign_cursor==32 and original.loadout.station_id==98 and campaign.post_probe_available(bindings.mido_travel)
	check(suttnar or kappa or sahi or expedition or post_probe,"Use an application's earned campaign continuation")
	check(original.mission==campaign.mission(bindings.mido_travel,original.campaign_cursor) and original.contracts.mission.kind==11 and original.contracts.mission.station_id==99 and original.contracts.passengers==3,"The retained pending story or accepted passengers changed")
	print("Earned campaign save: cursor ",original.campaign_cursor," station ",original.loadout.station_id," credits ",original.contracts.credits)
	check(archive.capture(station,bindings)==record and not station.prepare_departure(bindings,cat).is_empty(),"The saved continuation cannot round-trip and depart")
	if sahi:
		check(original.reward_credits==0 and original.mission.kind==11 and original.mission.station_id==10 and original.progress.get("cargo_recovered",0)>=3,"The earned Sahi save lost recovered cargo progress or retained an unearned station reward")
		for version in [3,4]:
			var broken:=record.duplicate(true);broken.version=version
			check(archive.restore(bindings,cat,library,broken)==null and not archive.error.is_empty(),"The Sahi career was accepted under an earlier station save version")
	if expedition:
		check(original.reward_credits==0 and original.progress.get("cargo_recovered",0)>=3,"The expedition lost earned recovery or paid an unearned reward")
		for version in [3,4,5]:
			var broken:=record.duplicate(true);broken.version=version
			check(archive.restore(bindings,cat,library,broken)==null and not archive.error.is_empty(),"An earlier station save version accepted the expedition")
		for mutation in [["reward_credits",30000],["campaign_conversation",true],["next_course",{"station_id":98,"system_id":19}]]:
			var broken:=record.duplicate(true);broken.station[mutation[0]]=mutation[1]
			check(archive.restore(bindings,cat,library,broken)==null and not archive.error.is_empty(),"The expedition accepted an unearned or unresolved station receipt: "+mutation[0])
		if original.campaign_cursor==31:check(original.mission.reward==30000 and original.mission.station_id==98,"The saved expedition lost its future Alioth reward")
	if original.campaign_cursor==24:
		verify_return_receipt(bindings,cat,library,archive,record)
		if failures:return
	if post_probe:
		verify_post_probe_receipt(bindings,cat,library,archive,record)
		if failures:return
	for mutation in [
		[["version"],1],[["version"],2],[["binding_id"],"0".repeat(64)],
		[["station","campaign_cursor"],18],[["career","campaign_cursor"],18],
		[["station","mission","station_id"],(int(original.mission.station_id)+1)%cat.tables.stations.size()],[["station","mission"],[]],
		[["station","acknowledged"],false],[["station","player_cache","values","hull"],0],
		[["inventory","cargo","used"],-1],[["career","progress","rank_score"],0],
		[["career","mission"],{}],[["locations","current_station_id"],(int(original.loadout.station_id)+1)%cat.tables.stations.size()]]:
		var broken:=record.duplicate(true);var parent: Dictionary=broken
		for index in mutation[0].size()-1:parent=parent[mutation[0][index]]
		parent[mutation[0].back()]=mutation[1]
		check(archive.restore(bindings,cat,library,broken)==null and not archive.error.is_empty(),"Malformed continuation accepted: "+str(mutation[0]))
	var purchased: RefCounted=station.fork()
	if not purchased.open_equipment(bindings,cat,library,[1789100000,1789100000,1789100000]):check(false,purchased.error);return
	var selected:=-1
	for row in purchased.equipment_owner().snapshot().market_rows:
		if row.stock>0 and not row.mission and row.unit_price>0 and row.unit_price<=original.contracts.credits:selected=row.item_id;break
	if selected<0 or not purchased.equipment_action("buy",selected,bindings,cat) or not purchased.close_equipment():check(false,purchased.error);return
	var paid:=archive.capture(purchased,bindings)
	var loaded:=archive.restore(bindings,cat,library,paid)
	if loaded==null:check(false,archive.error);return
	check(loaded.snapshot()==purchased.snapshot() and loaded.snapshot().contracts.credits<original.contracts.credits,"The continuation lost a paid purchase or changed station stock")
	check(loaded.snapshot().contracts.mission==original.contracts.mission and loaded.snapshot().mission==original.mission,"Shopping after the visit changed the accepted delivery or story")
	check(station.snapshot()==original,"A failed restore or detached purchase changed the saved career")
	if failures:return
	verify_active_fitting(bindings,cat,library,station,archive)
	if failures:return
	# A station's real contacts need not include a courier. The optional
	# second save is earned by fitting_application's actual return journey.
	var courier_path:=OS.get_environment("GOF2_COURIER_SOURCE_SAVE")
	if not courier_path.is_empty():
		var courier_record:=file.load_document(courier_path,bindings,cat,library)
		if courier_record.is_empty():check(false,file.error);return
		var courier_station:=archive.restore(bindings,cat,library,courier_record)
		if courier_station==null:check(false,archive.error);return
		verify_courier_fitting(bindings,cat,library,courier_station,archive)
	if failures:return
	verify_files(bindings,cat,library,station,purchased,record,paid)

func verify_post_probe_receipt(bindings: RefCounted,cat: RefCounted,library: RefCounted,archive: RefCounted,record: Dictionary) -> void:
	check(record.station.reward_credits==30000 and record.station.mission=={"kind":11,"station_id":10,"reward":0,"bonus":0,"source_parameter":0} and not record.station.has("next_course"),"The earned Alioth result lost its original payment or selected an automatic course")
	var client: Dictionary=record.career.accepted_contact
	check(client.station_id==record.career.station_id and client.offer.context.campaign_cursor<record.career.population.context.campaign_cursor,"The earned Alioth save must cover an accepted client surviving source-lounge eviction and regeneration")
	var changed_client:=record.duplicate(true)
	changed_client.career.accepted_contact.offer.mission.reward+=1
	check(archive.restore(bindings,cat,library,changed_client)==null,"Regenerated lounges allowed changed original contract terms")
	for version in [3,4,5,6]:
		var broken:=record.duplicate(true);broken.version=version
		check(archive.restore(bindings,cat,library,broken)==null and not archive.error.is_empty(),"An earlier station format accepted the post-probe result")
	for value in [null,-1,30001,"30000",30000.0,[],{}]:
		var broken:=record.duplicate(true);broken.station.reward_credits=value
		check(archive.restore(bindings,cat,library,broken)==null and not archive.error.is_empty(),"Malformed Alioth payment receipt accepted: "+str(value))
	for mutation in [["campaign_conversation",true],["next_course",{"station_id":10,"system_id":6}]]:
		var broken:=record.duplicate(true);broken.station[mutation[0]]=mutation[1]
		check(archive.restore(bindings,cat,library,broken)==null and not archive.error.is_empty(),"The post-probe save accepted an unfinished result or invented course")
	var restored: RefCounted=archive.restore(bindings,cat,library,record)
	if restored==null:check(false,archive.error);return
	var before: Dictionary=restored.snapshot()
	check(not restored.acknowledge() and not restored.begin_campaign_conversation(bindings,cat,library) and restored.snapshot()==before,"Loading the paid result repeated its payment or dialogue")
	check(archive.capture(restored,bindings)==record,"Rejected receipt changes mutated the valid Alioth save")

func verify_return_receipt(bindings: RefCounted,cat: RefCounted,library: RefCounted,archive: RefCounted,record: Dictionary) -> void:
	# Only the application's actual station acknowledgement supplies this input.
	# Malformed copies must not turn a retained course into a different payment.
	var rules: Dictionary=bindings.mido_travel.kappa_return.conversations[-1]
	var course: Dictionary=record.station.get("next_course",{})
	check(record.station.reward_credits==int(rules.reward_credits) and course.size()==rules.next_course.size(),"The earned return lacks its original payment and course receipt")
	for key in rules.next_course:
		check(course.get(key) is int and course[key]==int(rules.next_course[key]),"The saved course lost its native coordinate: "+key)
	if failures:return
	var mutations:=[]
	for value in [null,0,-1,int(rules.reward_credits)+1,str(int(rules.reward_credits)),float(rules.reward_credits),[],{}]:
		var broken:=record.duplicate(true);broken.station.reward_credits=value;mutations.append(broken)
	for value in [null,[],{},"Sahi"]:
		var broken:=record.duplicate(true);broken.station.next_course=value;mutations.append(broken)
	for key in course:
		var missing:=record.duplicate(true);missing.station.next_course.erase(key);mutations.append(missing)
		for value in [null,str(course[key]),float(course[key]),int(course[key])+1]:
			var broken:=record.duplicate(true);broken.station.next_course[key]=value;mutations.append(broken)
	var extra:=record.duplicate(true);extra.station.next_course["unrecognized"]=0;mutations.append(extra)
	var omitted:=record.duplicate(true);omitted.station.erase("next_course");mutations.append(omitted)
	for index in mutations.size():
		check(archive.restore(bindings,cat,library,mutations[index])==null and not archive.error.is_empty(),"Malformed acknowledged return receipt accepted: "+str(index))
	var restored: RefCounted=archive.restore(bindings,cat,library,record)
	check(restored!=null and archive.capture(restored,bindings)==record,"A rejected return receipt changed the valid earned save: "+archive.error)

func verify_active_fitting(bindings: RefCounted,cat: RefCounted,library: RefCounted,station: RefCounted,archive: RefCounted) -> void:
	# The input is the application's earned passenger save. Only normal
	# station transactions change the successful branch; the input stays owned.
	var original: Dictionary=station.snapshot()
	var fitted: RefCounted=station.fork()
	if not fitted.open_equipment(bindings,cat,library,[1789100000,1789100000,1789100000]):check(false,fitted.error);return
	var opened: Dictionary=fitted.snapshot()
	var cabin:=-1;var primary:=-1;var spare:=-1
	for i in opened.loadout.slots.size():
		var slot: Variant=opened.loadout.slots[i]
		if slot==null:continue
		if cat.tables.items[slot.item_id].arrays[2][5]==20:cabin=i
		if slot.category==0:primary=i
	for row in opened.equipment.market_rows:
		if row.owned>0 and not row.mission and cat.tables.items[row.item_id].arrays[2][3]==0 and opened.equipment.fitting_support.get(row.item_id,"unsupported").is_empty():spare=row.item_id;break
	if cabin<0 or primary<0:check(false,"The earned save lost its occupied cabin or installed primary");return
	var cabin_id: int=opened.loadout.slots[cabin].item_id
	check(not fitted.equipment_action("unmount",cabin_id,bindings,cat,cabin) and fitted.snapshot()==opened,"Active passengers lost their occupied berths or refusal partially committed")
	var old_primary: int=opened.loadout.slots[primary].item_id
	# A later earned career may have sold its spare. Demount/remount the owned
	# primary then; retained earlier fixtures still exercise the actual swap.
	if spare<0:spare=old_primary
	verify_fitting_context_guards(bindings,cat,fitted,old_primary,primary)
	if failures:return
	if not fitted.equipment_action("unmount",old_primary,bindings,cat,primary):check(false,"Active contract blocked an unrelated primary demount: "+fitted.error);return
	if not fitted.equipment_action("mount",spare,bindings,cat):check(false,"Active contract blocked the owned primary: "+fitted.error);return
	var accepted: Dictionary=fitted.snapshot()
	check(accepted.loadout.slots[primary].item_id==spare and accepted.loadout.slots[cabin]==opened.loadout.slots[cabin],"Fitting did not preserve the actual passenger cabin")
	check(accepted.contracts==opened.contracts and accepted.mission==original.mission and accepted.progress==original.progress,"Fitting changed the accepted contract, wallet, passengers, story, rank or cached random stream")
	check(accepted.cargo.used==opened.cargo.used and accepted.equipment.transactions==opened.equipment.transactions+2,"A slot exchange lost cargo quantity or transaction count")
	check(not fitted.equipment_action("unmount",cabin_id,bindings,cat,cabin) and fitted.snapshot()==accepted,"A later fitting operation forgot retained passengers")
	if not fitted.close_equipment():check(false,fitted.error);return
	var saved: Dictionary=archive.capture(fitted,bindings)
	var restored: RefCounted=archive.restore(bindings,cat,library,saved)
	if restored==null:check(false,archive.error);return
	check(restored.snapshot()==fitted.snapshot() and not restored.prepare_departure(bindings,cat).is_empty(),"The actively contracted fitted ship could not save, restore and prepare departure")
	if not restored.open_equipment(bindings,cat,library,[1789100000,1789100000,1789100000]):check(false,restored.error);return
	var reopened: Dictionary=restored.snapshot()
	check(not restored.equipment_action("unmount",cabin_id,bindings,cat,cabin) and restored.snapshot()==reopened,"Restoring the fitted save removed occupied-cabin protection")
	check(restored.equipment_action("unmount",spare,bindings,cat,primary) and restored.equipment_action("mount",old_primary,bindings,cat),"The restored active contract blocked further safe fitting: "+restored.error)
	check(station.snapshot()==original,"Active fitting mutated the retained source station")
	print("Earned passenger save: owned primary fitting, occupied-cabin refusal, exact career retention and fitted save/load passed")

func verify_fitting_context_guards(bindings: RefCounted,cat: RefCounted,station: RefCounted,item_id: int,slot_index: int) -> void:
	# Fault injection is confined to rejected forks, never the successful
	# journey, fixture or save. Missing quantities must fail without casting.
	var equipment: RefCounted=station.equipment_owner()
	var original: Dictionary=equipment.snapshot()
	for field in ["passengers","quantity"]:
		for value in [-1,0,4,3.5,null,"3",2147483648]:
			var broken: RefCounted=station.contract_owner()
			if field=="passengers":broken._state.passengers=value
			else:broken._state.mission.quantity=value
			var held: Dictionary=broken.snapshot()
			check(broken.transact_shopping(bindings,cat,equipment,"unmount",item_id,slot_index)==null and broken.snapshot()==held and equipment.snapshot()==original,"Malformed fitting passenger context changed retained owners: "+field+"="+str(value))
	var unsupported: RefCounted=station.contract_owner()
	unsupported._state.mission.kind=1
	var held: Dictionary=unsupported.snapshot()
	check(unsupported.transact_shopping(bindings,cat,equipment,"unmount",item_id,slot_index)==null and unsupported.snapshot()==held and equipment.snapshot()==original,"An unsupported active contract inferred fitting support")

func verify_courier_fitting(bindings: RefCounted,cat: RefCounted,library: RefCounted,station: RefCounted,archive: RefCounted) -> void:
	# Take an actual available courier offer on a separate earned branch.
	# Explicit replacement uses the native owner and clears its real passengers.
	var original: Dictionary=station.snapshot()
	var courier: RefCounted=station.fork()
	var chosen:=-1
	for id in original.contracts.offers:
		var row: Dictionary=original.contracts.offers[id]
		if not row.consumed and row.offer.mission.kind==int(bindings.early_contracts.courier.kind) and not courier.contract_preview(id,bindings).is_empty():chosen=id;break
	if chosen<0 or original.contracts.passengers<1:check(false,"Use an earned passenger station with a supported courier offer");return
	# Free space by selling real spare cargo at the actual station quote,
	# not by adding hold capacity or deleting cargo from the save.
	if not courier.contract_preview(chosen,bindings).can_accept:
		if not courier.open_equipment(bindings,cat,library,[1789100000,1789100000,1789100000]):check(false,courier.error);return
		for unit in original.cargo.used:
			if courier.contract_preview(chosen,bindings).get("can_accept",false):break
			var sale:=-1
			for row in courier.snapshot().equipment.market_rows:
				if row.owned>0 and not row.mission:sale=row.item_id;break
			if sale<0 or not courier.equipment_action("sell",sale,bindings,cat):check(false,"The real courier requirements could not be met through ordinary cargo sales");return
		if not courier.close_equipment():check(false,courier.error);return
	var ready: Dictionary=courier.snapshot()
	check(courier.contract_preview(chosen,bindings).get("can_accept",false) and ready.contracts.mission==original.contracts.mission and ready.contracts.passengers==original.contracts.passengers,"Making space for the real courier discarded its existing passengers")
	check(not courier.accept_contract(chosen,false,bindings) and courier.snapshot()==ready,"Courier fitting discarded the passenger contract without confirmation")
	if not courier.accept_contract(chosen,true,bindings):check(false,courier.error);return
	var accepted: Dictionary=courier.snapshot()
	check(accepted.contracts.passengers==0 and accepted.contracts.mission.kind==int(bindings.early_contracts.courier.kind),"The actual courier replacement retained old passengers")
	if not courier.open_equipment(bindings,cat,library,[1789100000,1789100000,1789100000]):check(false,courier.error);return
	var opened: Dictionary=courier.snapshot()
	var mission_cargo: int=bindings.early_contracts.courier.cargo_item_id
	var rows: Array=opened.cargo.entries.filter(func(row):return row.item_id==mission_cargo and row.get("mission",false))
	if rows.size()!=1:check(false,"Accepting the original courier did not create its protected cargo");return
	for action in ["sell","mount"]:
		check(not courier.equipment_action(action,mission_cargo,bindings,cat) and courier.snapshot()==opened,"Active courier fitting altered protected cargo: "+action)
	var cabin:=-1
	for i in opened.loadout.slots.size():
		var slot: Variant=opened.loadout.slots[i]
		if slot!=null and cat.tables.items[slot.item_id].arrays[2][5]==20:cabin=i;break
	if cabin<0:check(false,"The courier branch lost its previously occupied cabin");return
	var cabin_id: int=opened.loadout.slots[cabin].item_id
	if not courier.equipment_action("unmount",cabin_id,bindings,cat,cabin):check(false,"Courier fitting kept a stale occupied-berth restriction: "+courier.error);return
	var fitted: Dictionary=courier.snapshot()
	check(fitted.contracts==opened.contracts and fitted.cargo.entries.filter(func(row):return row.get("mission",false))==rows,"Courier fitting changed the accepted job, wallet, cached randomness or protected cargo")
	if not courier.equipment_action("mount",cabin_id,bindings,cat):check(false,"The empty cabin could not be refitted during the courier: "+courier.error);return
	check(courier.snapshot().cargo==opened.cargo,"Refitting the cabin changed protected courier cargo")
	if not courier.close_equipment():check(false,courier.error);return
	var restored: RefCounted=archive.restore(bindings,cat,library,archive.capture(courier,bindings))
	if restored==null:check(false,archive.error);return
	check(restored.snapshot()==courier.snapshot() and not restored.prepare_departure(bindings,cat).is_empty(),"The fitted courier did not retain protected cargo through save/load and departure preparation")
	check(station.snapshot()==original,"The separate courier branch changed the original passenger save")
	print("Earned courier offer ",chosen,": confirmed replacement, protected mission cargo, released cabin and fitted save/load passed")
