extends "res://tests/ordinary_shopping.gd"
## Earned inventory exercises station fitting. Separate zero-price test offers
## cover catalogue-wide slot and capacity rules without entering a career.
const Cargo=preload("res://src/simulation/flight_cargo.gd")

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:verify_fitting(args)
	else:check(false,"Expected content, bindings and visuals")
	print("Ordinary fitting: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_fitting(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not library.select_language("gb") or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var checkpoint:=Checkpoint.new()
	var station: RefCounted=checkpoint.open(OS.get_environment("GOF2_FREE_PLAY_STATION_SCENARIO"),bindings)
	if station==null:check(false,checkpoint.error);return
	var original: Dictionary=station.snapshot()
	var branch: RefCounted=station.fork()
	if not branch.open_equipment(bindings,cat,library,TIMES):check(false,branch.error);return
	var before: Dictionary=branch.snapshot()
	if not before.equipment.has("fitting_support"):
		check(not branch.equipment_action("mount",0,bindings,cat) and branch.snapshot()==before,"Earlier bindings inferred fitting")
		return
	var affordable:=[]
	for row in before.equipment.market_rows:
		if row.stock>0 and row.unit_price<=before.contracts.credits and before.equipment.fitting_support[row.item_id].is_empty():affordable.append({"id":row.item_id,"price":row.unit_price,"stock":row.stock})
	print("Actual affordable fitting offers: ",affordable)
	var locations: Dictionary=branch.contract_owner().location_owner().snapshot()
	check(not branch.equipment_action("mount",0,bindings,cat) and branch.snapshot()==before,"A second gun entered the starter's full primary slot")
	check(branch.equipment_action("unmount",22,bindings,cat,0),branch.error)
	check(branch.equipment_action("mount",0,bindings,cat),branch.error)
	var mounted: Dictionary=branch.snapshot()
	check(mounted.cargo.used==before.cargo.used and mounted.loadout.slots[0].item_id==0,"Earned spare gun did not use the vacated primary slot")
	check(mounted.contracts.credits==before.contracts.credits and branch.contract_owner().location_owner().snapshot()==locations,"Fitting charged credits, consumed random draws or changed station stock")
	check(not branch.equipment_action("unmount",0,bindings,cat,1) and branch.snapshot()==mounted,"A mismatched explicit slot removed equipment")
	check(branch.equipment_action("unmount",0,bindings,cat,0),branch.error)
	check(branch.equipment_action("mount",22,bindings,cat),branch.error)
	check(branch.snapshot().cargo==before.cargo and branch.snapshot().loadout==before.loadout,"Explicit demount failed to restore actual owned quantities")
	var slots: Array=branch.snapshot().loadout.slots
	for i in slots.size():
		if slots[i]!=null:check(branch.equipment_action("unmount",slots[i].item_id,bindings,cat,i),branch.error)
	check(branch.snapshot().loadout.equipment_ids.is_empty() and not branch.snapshot().equipment.requirements.satisfied,"Ordinary fitting retained a tutorial weapon or armor requirement")
	check(branch.close_equipment(),branch.error)
	check(not branch.prepare_departure(bindings,cat).is_empty(),"Unarmed ordinary departure was blocked: "+branch.error)
	check(branch.open_equipment(bindings,cat,library,TIMES),branch.error)
	check(branch.snapshot().loadout.equipment_ids.is_empty() and branch.snapshot().mission==original.mission and branch.snapshot().contracts.credits==7850,"Reopening restored equipment or changed earned progress")
	verify_catalogue_fitting(station,bindings,cat,library)
	check(station.snapshot()==original,"Detached fitting changed its earned station source")

func verify_catalogue_fitting(station: RefCounted,bindings: RefCounted,cat: RefCounted,library: RefCounted) -> void:
	var base: RefCounted=station.equipment_owner();var rows:=[]
	for id in cat.tables.items.size():rows.append({"item_id":id,"quantity":100,"unit_price":0})
	var rng: Dictionary=station.contract_owner().location_owner().snapshot().random
	if base.open_ordinary_shopping(bindings,cat,rows,rng,TIMES,0,library).is_empty():check(false,base.error);return
	var slots: Array=base.snapshot().loadout.slots
	for i in slots.size():
		if slots[i]!=null and not base.fit(bindings,cat,"unmount",slots[i].item_id,i):check(false,base.error);return
	var empty: Dictionary=base.snapshot()
	for id in empty.fitting_support:
		if not empty.fitting_support[id].is_empty():continue
		var branch: RefCounted=base.fork()
		if not branch.transact("buy",id,0) or not branch.transact("buy",id,0) or not branch.fit(bindings,cat,"mount",id):check(false,"Catalogue fitting %d: %s"%[id,branch.error]);continue
		var mounted: Dictionary=branch.snapshot();var selected:=-1
		for i in mounted.loadout.slots.size():
			if mounted.loadout.slots[i]!=null:selected=i;break
		check(selected>=0 and mounted.credit_delta==0,"Fitting lost its one installed instance or charged credits")
		var subtype: int=cat.tables.items[id].arrays[2][5]
		var multiple: bool=(int(bindings.station_equipment.multiple_subtype_mask)&(1<<subtype))!=0
		if multiple and int(branch._counts[cat.tables.items[id].arrays[2][3]])>1:
			check(branch.fit(bindings,cat,"mount",id),"A source stackable subtype was refused: "+branch.error)
			var second:=-1
			for i in branch.snapshot().loadout.slots.size():
				if i!=selected and branch.snapshot().loadout.slots[i]!=null:second=i
			check(second>selected,"Repeated equipment lost its category-slot order")
			check(branch.fit(bindings,cat,"unmount",id,second),branch.error)
			check(branch.snapshot().loadout.slots[selected]!=null and branch.snapshot().loadout.slots[second]==null,"Explicit removal cleared every matching ID")
		elif multiple:
			check(not branch.fit(bindings,cat,"mount",id) and branch.snapshot()==mounted,"A repeated item bypassed the ship's physical slot count")
		else:
			check(not branch.fit(bindings,cat,"mount",id) and branch.snapshot()==mounted,"A unique subtype mounted twice")
			check(branch.fit(bindings,cat,"replace",id,selected),"Confirmed replacement failed: "+branch.error)
		check(branch.fit(bindings,cat,"unmount",id),branch.error)
		check(branch.snapshot().loadout.equipment_ids.is_empty(),"The first matching item was not demounted")
	var capacity: RefCounted=base.fork()
	check(capacity.transact("buy",63,0) and capacity.fit(bindings,cat,"mount",63),capacity.error)
	while capacity.snapshot().cargo.used<40:
		if not capacity.transact("buy",116,0):check(false,capacity.error);return
	check(capacity.fit(bindings,cat,"unmount",63),capacity.error)
	check(capacity.snapshot().cargo.capacity==25 and capacity.snapshot().cargo.used==41 and capacity.snapshot().cargo.free_space==-16,"Removing a cargo expansion was capacity-limited or failed to recalculate")
	var flight:=Cargo.new()
	check(not flight.configure_equipment(bindings,cat,capacity),"Overfilled station cargo entered flight")
	check(capacity.fit(bindings,cat,"mount",63) and flight.configure_equipment(bindings,cat,capacity),"Restored cargo capacity could not enter flight: "+capacity.error+flight.error)
	var armor: RefCounted=base.fork()
	check(armor.transact("buy",55,0) and armor.fit(bindings,cat,"mount",55) and armor.transact("buy",56,0),armor.error)
	var conflict: Dictionary=armor.snapshot().fitting_conflicts[56]
	check(armor.fit(bindings,cat,"replace",56,conflict.index) and armor.snapshot().fitting_stats.armor==80,"Replacing armor did not update the actual pool capacity")
	# Isolated owner diagnostics: protected flags and occupied berths never
	# enter the successful career or stand in for an accepted passenger job.
	var cabins: RefCounted=base.fork()
	check(cabins.transact("buy",91,0) and cabins.fit(bindings,cat,"mount",91),cabins.error)
	var occupied: Dictionary=cabins.snapshot()
	check(occupied.fitting_stats.passenger_capacity>0,"The installed cabin supplied no berths")
	check(not cabins.fit(bindings,cat,"unmount",91,-1,1) and cabins.snapshot()==occupied,"An occupied cabin was removed or its refusal changed inventory")
	check(cabins.transact("buy",92,0) and cabins.fit(bindings,cat,"mount",92),cabins.error)
	check(cabins.fit(bindings,cat,"unmount",91,-1,1),"Removing a cabin ignored sufficient remaining berths: "+cabins.error)
	var protected: RefCounted=base.fork()
	check(protected.transact("buy",0,0) and protected.fit(bindings,cat,"mount",0),protected.error)
	protected._state.protected_item_ids=[0]
	var guarded: Dictionary=protected.snapshot()
	check(not protected.fit(bindings,cat,"unmount",0) and protected.snapshot()==guarded,"Protected equipment was demounted")
	check(not protected.fit(bindings,cat,"mount",0) and protected.snapshot()==guarded,"Protected cargo was mounted")
