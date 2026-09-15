extends "res://tests/gate_environment.gd"
## Paid transactions replay an earned career. No credit, cargo or campaign
## progress is supplied to the successful purchase and overfill paths.
const Checkpoint=preload("res://tests/fixtures/free_play_station_scenario.gd")
const Shopping=preload("res://src/content/ordinary_shopping_definitions.gd")
const TIMES=[1789100000,1789100001,1789100002]

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size() in [2,3]:verify(args)
	else:check(false,"Expected explicit content and bindings")
	print("Ordinary shopping: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not library.select_language("gb") or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var checkpoint:=Checkpoint.new()
	var station: RefCounted=checkpoint.open(OS.get_environment("GOF2_FREE_PLAY_STATION_SCENARIO"),bindings)
	if station==null:check(false,checkpoint.error);return
	var original: Dictionary=station.snapshot()
	if not Shopping.available(bindings):
		check(not station.open_equipment(bindings,cat,library,TIMES) and station.snapshot()==original,"Older content enabled ordinary shopping")
		return
	check(original.contracts.credits==7850 and original.contracts.completed_side_missions==4 and original.campaign_cursor==18,"The fixture lost its earned credits or opening")
	check(not station.equipment_action("buy",0,bindings,cat) and station.snapshot()==original,"Closed hangar accepted a trade")
	for times in [[],[1,2],[-1,2,3],[1.0,2,3]]:
		check(not station.open_equipment(bindings,cat,library,times) and station.snapshot()==original,"Invalid price timestamp changed the career")
	var unavailable: Dictionary=bindings.mido_travel.ordinary_shopping
	bindings.mido_travel.erase("ordinary_shopping")
	check(not station.open_equipment(bindings,cat,library,TIMES) and station.snapshot()==original,"A missing capability used tutorial free offers")
	bindings.mido_travel.ordinary_shopping=unavailable
	var branch: RefCounted=station.fork()
	if not branch.open_equipment(bindings,cat,library,TIMES):check(false,branch.error);return
	var quoted: Dictionary=branch.snapshot()
	check(quoted.hangar_open and quoted.equipment.ordinary_shopping_open and quoted.phase==original.phase,"Paid hangar entered the tutorial phase")
	check(quoted.contracts.credits==original.contracts.credits and quoted.cargo==original.cargo and quoted.loadout==original.loadout,"Opening prices charged the wallet or changed item ownership")
	check(quoted.mission==original.mission and quoted.progress==original.progress,"Opening the hangar changed pending story or earned career")
	check(not branch.open_equipment(bindings,cat,library,TIMES) and branch.snapshot()==quoted,"The open hangar repriced twice")
	check(branch.prepare_departure(bindings,cat).is_empty() and branch.snapshot()==quoted,"Departure escaped an open shop")
	var location: RefCounted=branch.contract_owner().location_owner()
	check(location.item_stock(98)==quoted.equipment.stock,"The displayed quote differs from retained station stock")
	check(location.location(98).stock==station.contract_owner().location_owner().location(98).stock,"Repricing overwrote original stock-generation evidence")
	var unique:=[]
	for row in quoted.equipment.market_rows:
		check(row.item_id not in unique,"The combined market repeated an item ID")
		unique.append(row.item_id)
	var affordable:=cheapest(quoted)
	if affordable.is_empty():check(false,"The earned station has no affordable positive-priced item");return
	var id: int=affordable.item_id;var price: int=affordable.unit_price
	print("Earned shopping quote: item ",id," / ",price,"cr, hold ",quoted.cargo.used,"/",quoted.cargo.capacity)
	var inventory: RefCounted=branch.equipment_owner();var inventory_before: Dictionary=inventory.snapshot()
	check(not inventory.transact("buy",id,price-1) and inventory.snapshot()==inventory_before,"An unaffordable unit changed inventory")
	check(not branch.equipment_action("mount",id,bindings,cat) and branch.snapshot()==quoted,"Stock presence enabled unsupported equipment fitting")
	if not branch.equipment_action("buy",id,bindings,cat):check(false,branch.error);return
	var bought: Dictionary=branch.snapshot();var purchased:=market_row(bought,id)
	check(bought.contracts.credits==quoted.contracts.credits-price and purchased.owned==affordable.owned+1 and purchased.stock==affordable.stock-1,"Paid purchase lost the one-unit wallet/stock/cargo transaction")
	check(bought.cargo.used==quoted.cargo.used+1 and bought.cargo.free_space==quoted.cargo.free_space-1 and not bought.cargo_cache_stale,"Paid purchase failed to commit actual cargo quantities")
	check(branch.contract_owner().location_owner().item_stock(98)==bought.equipment.stock,"Paid purchase did not retain station stock")
	var career: Dictionary=bought.contracts.duplicate(true);var old_career: Dictionary=quoted.contracts.duplicate(true)
	for key in ["credits","lounges"]:career.erase(key);old_career.erase(key)
	check(career==old_career and bought.mission==quoted.mission and bought.loadout==quoted.loadout,"Buying changed unrelated career, equipment or story")
	var cached: RefCounted=branch.contract_owner().location_owner();var cache_before: Dictionary=cached.snapshot()
	check(not cached.replace_item_stock(bindings,cat,98,quoted.equipment.stock,bought.equipment.stock) and cached.snapshot()==cache_before,"A stale quote replaced accepted stock")
	check(not cached.replace_item_stock(bindings,cat,95,bought.equipment.stock,bought.equipment.stock) and cached.snapshot()==cache_before,"Trading changed another cached station")
	if not branch.equipment_action("sell",id,bindings,cat):check(false,branch.error);return
	var sold: Dictionary=branch.snapshot()
	check(sold.contracts.credits==quoted.contracts.credits and sold.cargo==quoted.cargo and sold.equipment.stock==quoted.equipment.stock,"One-unit resale failed to restore wallet and quantities")
	check(branch.close_equipment(),branch.error)
	var closed: Dictionary=branch.snapshot()
	check(not closed.hangar_open and not closed.equipment.has("ordinary_shopping_open") and closed.phase==original.phase and closed.mission==original.mission,"Closing the ordinary shop started tutorial completion")
	check(not branch.prepare_departure(bindings,cat).is_empty(),branch.error)
	check(branch.open_equipment(bindings,cat,library,TIMES),branch.error)
	check(branch.snapshot().contracts.credits==closed.contracts.credits and branch.snapshot().cargo==closed.cargo,"Reopening restored stock or charged a new fee")
	verify_overfill(station,bindings,cat,library)
	verify_merge_and_boundaries(station,bindings,cat,library)
	check(station.snapshot()==original,"Detached trading changed its earned source station")

func verify_overfill(station: RefCounted,bindings: RefCounted,cat: RefCounted,library: RefCounted) -> void:
	var branch: RefCounted=station.fork()
	if not branch.open_equipment(bindings,cat,library,TIMES):check(false,branch.error);return
	var count:=0
	while branch.snapshot().cargo.used<=branch.snapshot().cargo.capacity and count<1024:
		var offer:=cheapest(branch.snapshot())
		if offer.is_empty():check(false,"Earned credits and generated stock could not exercise overfill");return
		if not branch.equipment_action("buy",offer.item_id,bindings,cat):check(false,branch.error);return
		count+=1
	var full: Dictionary=branch.snapshot()
	check(full.cargo.used==full.cargo.capacity+1 and full.cargo.free_space==-1,"Ordinary purchases were incorrectly capacity-limited")
	print("Overfilled with ",count," actual paid units; ",full.contracts.credits,"cr retained")
	var flight_inventory: RefCounted=branch.equipment_owner();var unchanged: Dictionary=flight_inventory.snapshot()
	check(not flight_inventory.retain_flight_cargo(full.cargo) and flight_inventory.snapshot()==unchanged,"Station overfill weakened the strict flight-cargo boundary")
	check(branch.close_equipment(),branch.error)
	var closed: Dictionary=branch.snapshot()
	check(branch.prepare_departure(bindings,cat).is_empty() and branch.snapshot()==closed,"An overfilled hold departed or lost inventory on refusal")
	check(branch.open_equipment(bindings,cat,library,TIMES),branch.error)
	check(branch.snapshot().cargo==full.cargo and branch.snapshot().contracts.credits==full.contracts.credits,"Reopening an overfilled hold discarded its purchase")
	var sale: Dictionary={}
	for row in branch.snapshot().equipment.market_rows:
		if row.owned>0 and not row.mission:sale=row;break
	if sale.is_empty():check(false,"The purchased overfill could not be sold");return
	check(branch.equipment_action("sell",sale.item_id,bindings,cat),branch.error)
	check(branch.close_equipment(),branch.error)
	check(branch.snapshot().cargo.used==full.cargo.capacity and not branch.prepare_departure(bindings,cat).is_empty(),"An exactly full hold could not depart after selling one unit")

func verify_merge_and_boundaries(station: RefCounted,bindings: RefCounted,cat: RefCounted,library: RefCounted) -> void:
	# Detached inventory diagnostics exercise source row arithmetic only. These
	# supplied stocks never enter a career or stand in for earned progress.
	var seed: RefCounted=station.equipment_owner();var before: Dictionary=seed.snapshot()
	var times:=TIMES.duplicate()
	if before.cargo.entries.is_empty():times[0]=null
	var random: Dictionary=station.contract_owner().location_owner().snapshot().random
	var rows:=[{"item_id":116,"quantity":2,"unit_price":0},{"item_id":116,"quantity":3,"unit_price":0}]
	var receipt: Dictionary=seed.open_ordinary_shopping(bindings,cat,rows,random,times,0,library)
	if receipt.is_empty():check(false,seed.error);return
	var offered: Dictionary=seed.snapshot()
	check(offered.stock==[{"item_id":116,"quantity":3,"unit_price":0}],"Repeated stock IDs did not use the last station instance")
	var used: int=offered.cargo.used
	for number in 3:check(seed.transact("buy",116,0),seed.error)
	var exhausted: Dictionary=seed.snapshot()
	check(exhausted.stock.is_empty() and exhausted.cargo.used==used+3 and exhausted.credit_delta==0,"Zero-price units were mistaken for failed transfers")
	check(not seed.transact("buy",116,0) and seed.snapshot()==exhausted,"Exhausted stock produced an extra unit")
	for number in 3:check(seed.transact("sell",116,0),seed.error)
	var restored: Dictionary=seed.snapshot()
	check(restored.stock==offered.stock and restored.cargo==offered.cargo,"Zero-price sales failed to split retained stock and cargo")
	check(not seed.transact("sell",116,0) and seed.snapshot()==restored,"Empty cargo could be sold")
	for malformed in [[{"item_id":116,"quantity":0,"unit_price":0}],[{"item_id":116,"quantity":1.0,"unit_price":0}],[{"item_id":233,"quantity":1,"unit_price":0}]]:
		check(not Shopping.valid_stock(malformed,cat.tables.items.size()),"Invalid stock passed the station mutation boundary")

static func cheapest(state: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for row in state.equipment.market_rows:
		if row.stock<1 or row.unit_price<=0 or row.unit_price>state.contracts.credits or row.mission:continue
		if result.is_empty() or row.unit_price<result.unit_price:result=row
	return result.duplicate(true)

static func market_row(state: Dictionary,id: int) -> Dictionary:
	for row in state.equipment.market_rows:
		if row.item_id==id:return row.duplicate(true)
	return {}
